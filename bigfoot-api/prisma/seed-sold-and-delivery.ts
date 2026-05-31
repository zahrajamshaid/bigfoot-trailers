// =============================================================================
// BIGFOOT TRAILERS — Sold-pending-pickup + scheduled deliveries seed
//
// Reads prisma/data/sold-and-delivery-trailers.json (produced by
// scripts/extract-sold-delivery-trailers.ts) and lands each row according to
// its bucket:
//
//   sold-pending-pickup-{jax,mul,va}  (27 PDFs)
//     • Trailer moves to the folder's yard (JAX / MUL / TAP).
//     • saleStatus=sold, status=ready_for_delivery.
//     • soldToName ← PDF shipTo when it looks like a real customer;
//       blank when stale ("Open Stock X").
//     • Synthetic delivered stack_to_location Delivery to the folder's
//       yard so it surfaces under the right yard in Stock Inventory.
//     • Scheduled factory_pickup Delivery — represents the planned
//       customer pickup that hasn't happened yet.
//
//   delivery-stack-to-{atl,va}        (12 PDFs)
//     • Trailer's current location is preserved if the SO already exists
//       (per user direction: "Reuse existing location if SO already in DB").
//       New SOs default to MULBERRY.
//     • status=ready_for_delivery (dispatchable).
//     • Scheduled stack_to_location Delivery to ATL / TAP.
//     • saleStatus, customer info left alone.
//
//   delivery-dealer-tropic            (4 PDFs)
//     • Trailer's current location preserved or defaults to MULBERRY.
//     • saleStatus=sold, status=ready_for_delivery.
//     • Customer = Tropic Trailers (dealer record auto-created).
//     • Scheduled stack_to_dealer Delivery with the dealer's address.
//
// PDFs upload to Spaces and link via qbSoPdfStorageKey when DO_SPACES_* env
// vars are set. Idempotent on so_number; deliveries are deduped on
// (trailer, type, status, destination/dealer).
//
// Run with:
//   npx tsx prisma/seed-sold-and-delivery.ts
// =============================================================================

import 'dotenv/config';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import {
  BatchType,
  CustomerType,
  DeliveryBatchStatus,
  DeliveryStatus,
  DeliveryType,
  TrailerSaleStatus,
  TrailerStatus,
} from '@prisma/client';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DATA_JSON = join(__dirname, 'data', 'sold-and-delivery-trailers.json');
const PDF_ROOT =
  process.env['SOLD_DELIVERY_PDF_ROOT'] ??
  join(__dirname, 'data', 'sold-and-delivery-pdfs');

const TROPIC_DEALER_NAME = 'Tropic Trailers';
const TROPIC_DEALER_ADDRESS = '9451 Workmen Way, Fort Myers, FL 33905';

// Stable batchNumbers so re-running this seed reattaches deliveries to the
// same DeliveryBatch rows instead of creating duplicates.
const BATCH_NUMBER_BY_DEST_LOCATION_CODE: Record<string, string> = {
  ATLANTA: 'OPEN-BATCH-ATL',
  TAPPAHANNOCK: 'OPEN-BATCH-VA',
};
const BATCH_NUMBER_TROPIC = 'OPEN-BATCH-TROPIC';
const DEV_DRIVER_EMAIL = 'driver@bigfoot.dev';

// PDF service code → trailer_model.code. Built from the combined set of
// codes that appear across the 43 PDFs in this batch.
const MODEL_BY_PDF_CODE: Record<string, string> = {
  // XP series
  '10ET24XP': 'XP_10K',
  '14ET14XP': 'XP_14ET',
  '14ET16XP': 'XP_14ET',
  '14ET20XP': 'XP_14ET',
  '14ET24XP': 'XP_14ET',
  '17ET20XP': 'XP_17K',
  '17ET24': 'XP_17K',

  // YETI
  '15ET20YETI': 'YETI_15K',
  '15ET22YETI': 'YETI_15K',
  '18ET20YETI': 'YETI_18K',
  '18ET24YETI': 'YETI_18K',
  '21ET24YETI': 'YETI_21K',

  // Top Load Tilt
  '15ET20TLT': 'TLT_15K',
  '15TET24TLT': 'TLT_15K',
  '18ET20TLT': 'TLT_18K',
  '18ET24TLT': 'TLT_18K',
  '18TLT22': 'TLT_18K',
  '21ET24TLT': 'TLT_21K',

  // Deck Over
  '10DO24': 'DO_10K',
  '17DO22': 'DO_17K',
  '22DO25': 'DO_22K',

  // Gooseneck flatbed
  GOOSENECK: 'GN_15K', // 15K Dexter axles per PDF spec

  // Gooseneck dump
  '26DU20GN': 'DUMP_26K_GN',
  '8X20': 'DUMP_26K_GN', // custom 40K dump → closest 26K rung

  // Inventory-only: small custom builds and enclosed cargo
  '70CH24': 'MISC',
  '7X16TA2': 'ENCLOSED',
};

interface PdfRecord {
  bucket: string;
  kind: 'sold_pending' | 'stack' | 'dealer';
  locationCode: string | null;
  dealerName: string | null;
  file: string;
  soNumber: string;
  pdfModelCode: string | null;
  shipTo: string | null;
  shipToLines: string[];
  date: string | null;
  lengthFt: string | null;
  rawDescriptionHead: string;
}

function parsePdfDate(s: string | null): Date | null {
  if (!s) return null;
  const m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!m) return null;
  const [, mm, dd, yyyy] = m;
  const d = new Date(Date.UTC(Number(yyyy), Number(mm) - 1, Number(dd), 12));
  return Number.isNaN(d.getTime()) ? null : d;
}

// PDFs often render "Open Stock X" as the ship-to when the trailer has been
// re-routed but the SO wasn't reprinted. Those aren't real customer names.
function isStockShipTo(s: string | null | undefined): boolean {
  return !!s && /\bopen stock\b/i.test(s);
}

// Pull a clean customer name from the merged ship-to run. Handles the
// "NAME NAME 123 ADDRESS ..." doubled-prefix pattern QuickBooks emits.
function customerNameFrom(shipTo: string | null): string | null {
  if (!shipTo) return null;
  if (isStockShipTo(shipTo)) return null;

  // Anything before the first run of digits is usually the name + company.
  const beforeDigits = shipTo.match(/^([^0-9]+?)(?=\s+\d)/);
  let name = (beforeDigits ? beforeDigits[1] : shipTo).trim();

  // Collapse "NAME NAME" doubled-prefix (QB sometimes prints company twice).
  const half = Math.floor(name.length / 2);
  const left = name.slice(0, half).trim();
  const right = name.slice(half).trim();
  if (name.length > 6 && left.length > 0 && left === right) {
    name = left;
  } else {
    const words = name.split(/\s+/);
    if (words.length >= 4) {
      const firstTwo = words.slice(0, 2).join(' ');
      const rest = words.slice(2).join(' ');
      if (rest.startsWith(firstTwo)) name = firstTwo;
    }
  }
  return name.slice(0, 200);
}

interface SpacesUploader {
  upload(bucket: string, file: string, soNumber: string): Promise<string>;
}

function buildSpacesUploader(): SpacesUploader | null {
  const endpoint = process.env['DO_SPACES_ENDPOINT'];
  const accessKeyId = process.env['DO_SPACES_ACCESS_KEY'];
  const secretAccessKey = process.env['DO_SPACES_SECRET_KEY'];
  const bucketName = process.env['DO_SPACES_BUCKET'];
  const region = process.env['DO_SPACES_REGION'] ?? 'us-east-1';
  if (!endpoint || !accessKeyId || !secretAccessKey || !bucketName) return null;

  const s3 = new S3Client({
    endpoint,
    region,
    credentials: { accessKeyId, secretAccessKey },
    forcePathStyle: false,
  });
  return {
    async upload(folder, file, soNumber) {
      const bytes = readFileSync(join(PDF_ROOT, folder, file));
      const uuid = randomUUID();
      const soSlug = soNumber.toLowerCase().replace(/[^a-z0-9-]/g, '-');
      const key = `so-pdf/${soSlug}/${uuid}.pdf`;
      await s3.send(
        new PutObjectCommand({
          Bucket: bucketName,
          Key: key,
          Body: bytes,
          ContentType: 'application/pdf',
        }),
      );
      return key;
    },
  };
}

async function main(): Promise<void> {
  console.log(
    '🚛 Seeding sold-pending-pickup + scheduled deliveries (43 trailers)...\n',
  );

  await prisma.$executeRawUnsafe(
    `ALTER TYPE trailer_series_enum ADD VALUE IF NOT EXISTS 'inventory';`,
  );

  // ─── 1. Locations + creator ─────────────────────────────────────────────────
  const locByCode: Record<string, { id: number; name: string }> = {};
  for (const code of [
    'MULBERRY',
    'JACKSONVILLE',
    'ATLANTA',
    'TALLAHASSEE',
    'TAPPAHANNOCK',
  ]) {
    const loc = await prisma.location.findUnique({
      where: { code },
      select: { id: true, name: true },
    });
    if (!loc) throw new Error(`Location ${code} missing — run base seed first.`);
    locByCode[code] = loc;
  }

  const creator =
    (await prisma.user.findFirst({ where: { role: 'owner' } })) ??
    (await prisma.user.findFirst());
  if (!creator) throw new Error('No users in DB — run base seed first.');

  // ─── 2. Tropic Trailers dealer Customer ─────────────────────────────────────
  // Customer.name has no unique constraint; lookup by (name, customerType)
  // and create if missing.
  let tropic = await prisma.customer.findFirst({
    where: { name: TROPIC_DEALER_NAME, customerType: CustomerType.dealer },
    select: { id: true, name: true },
  });
  if (!tropic) {
    tropic = await prisma.customer.create({
      data: {
        name: TROPIC_DEALER_NAME,
        customerType: CustomerType.dealer,
        deliveryAddress: TROPIC_DEALER_ADDRESS,
      },
      select: { id: true, name: true },
    });
    console.log(`✅ Dealer created: ${tropic.name} (id=${tropic.id})\n`);
  } else {
    console.log(`✅ Dealer already present: ${tropic.name} (id=${tropic.id})\n`);
  }

  // ─── 3. Trailer-model lookup ────────────────────────────────────────────────
  const modelsByCode = new Map<string, number>();
  for (const m of await prisma.trailerModel.findMany({
    select: { id: true, code: true },
  })) {
    modelsByCode.set(m.code, m.id);
  }

  // ─── 4. Records ─────────────────────────────────────────────────────────────
  if (!existsSync(DATA_JSON)) {
    throw new Error(
      `Missing ${DATA_JSON} — run: npx tsx scripts/extract-sold-delivery-trailers.ts`,
    );
  }
  const records: PdfRecord[] = JSON.parse(readFileSync(DATA_JSON, 'utf8'));
  console.log(`📋 Loaded ${records.length} records across 3 buckets\n`);

  const uploader = buildSpacesUploader();
  if (!uploader) {
    console.log('⚠ Spaces creds not set — skipping PDF upload.\n');
  }

  // ─── 5. Process each record ─────────────────────────────────────────────────
  let trailersCreated = 0;
  let trailersUpdated = 0;
  let stockDeliveriesCreated = 0;
  let stockDeliveriesSkipped = 0;
  let pickupDeliveriesCreated = 0;
  let pickupDeliveriesSkipped = 0;
  let stackDeliveriesCreated = 0;
  let stackDeliveriesSkipped = 0;
  let dealerDeliveriesCreated = 0;
  let dealerDeliveriesSkipped = 0;
  let pdfsAttached = 0;
  let pdfsSkipped = 0;
  let errors = 0;

  for (const r of records) {
    const modelCode = r.pdfModelCode
      ? MODEL_BY_PDF_CODE[r.pdfModelCode]
      : undefined;
    if (!modelCode) {
      console.error(
        `  ✖ SO ${r.soNumber} (${r.bucket}): no mapping for PDF code "${r.pdfModelCode}"`,
      );
      errors++;
      continue;
    }
    const modelId = modelsByCode.get(modelCode);
    if (!modelId) {
      console.error(
        `  ✖ SO ${r.soNumber}: model ${modelCode} not in DB — run base / inventory seeds first`,
      );
      errors++;
      continue;
    }

    const existing = await prisma.trailer.findUnique({
      where: { soNumber: r.soNumber },
      select: {
        id: true,
        currentLocationId: true,
        qbSoPdfStorageKey: true,
      },
    });

    let trailerId: bigint;
    let qbSoPdfStorageKey: string | null = existing?.qbSoPdfStorageKey ?? null;

    if (r.kind === 'sold_pending') {
      // ─── Sold pending pickup ──────────────────────────────────────────────
      const destLoc = locByCode[r.locationCode!];
      if (!destLoc) {
        console.error(`  ✖ SO ${r.soNumber}: location ${r.locationCode} missing`);
        errors++;
        continue;
      }
      const customerName = customerNameFrom(r.shipTo);
      const updateData = {
        trailerModelId: modelId,
        currentLocationId: destLoc.id, // force-move trailer to folder's yard
        isStockBuild: false,
        status: TrailerStatus.ready_for_delivery,
        saleStatus: TrailerSaleStatus.sold,
        soldToName: customerName,
        customerLocked: false,
        optionsNotes: null,
        specialNote: null,
        ...(r.lengthFt ? { sizeFt: `${r.lengthFt}ft` } : {}),
      };
      const trailer = await prisma.trailer.upsert({
        where: { soNumber: r.soNumber },
        update: updateData,
        create: {
          ...updateData,
          soNumber: r.soNumber,
          createdByUserId: creator.id,
        },
        select: { id: true, soNumber: true, qbSoPdfStorageKey: true },
      });
      trailerId = trailer.id;
      qbSoPdfStorageKey = trailer.qbSoPdfStorageKey;
      if (existing) trailersUpdated++;
      else trailersCreated++;

      // delivered Delivery to destLoc so the trailer shows up in Stock
      // Inventory under the right yard. Stock Inventory keys off the latest
      // delivered Delivery, not currentLocationId.
      const hasStockDelivery = await prisma.delivery.findFirst({
        where: {
          trailerId,
          status: DeliveryStatus.delivered,
          destinationLocationId: destLoc.id,
        },
        select: { id: true },
      });
      if (hasStockDelivery) {
        stockDeliveriesSkipped++;
      } else {
        const deliveredAt = parsePdfDate(r.date) ?? new Date();
        await prisma.delivery.create({
          data: {
            trailerId,
            deliveryType: DeliveryType.stack_to_location,
            destinationLocationId: destLoc.id,
            status: DeliveryStatus.delivered,
            deliveredAt,
            createdByUserId: creator.id,
          },
        });
        stockDeliveriesCreated++;
      }

      // Scheduled factory_pickup — the customer hasn't shown up yet.
      const hasPickup = await prisma.delivery.findFirst({
        where: {
          trailerId,
          deliveryType: DeliveryType.factory_pickup,
          status: { in: [DeliveryStatus.scheduled, DeliveryStatus.in_transit] },
        },
        select: { id: true },
      });
      if (hasPickup) {
        pickupDeliveriesSkipped++;
      } else {
        await prisma.delivery.create({
          data: {
            trailerId,
            deliveryType: DeliveryType.factory_pickup,
            status: DeliveryStatus.scheduled,
            pickedUpByName: customerName,
            createdByUserId: creator.id,
          },
        });
        pickupDeliveriesCreated++;
      }

      console.log(
        `  📦 ${r.soNumber.padEnd(6)} ${modelCode.padEnd(13)} → SOLD @ ${destLoc.name}${customerName ? ` (${customerName})` : ' (no customer)'}`,
      );
    } else if (r.kind === 'stack') {
      // ─── Stack delivery (stack_to_location) ───────────────────────────────
      const destLoc = locByCode[r.locationCode!];
      if (!destLoc) {
        console.error(`  ✖ SO ${r.soNumber}: location ${r.locationCode} missing`);
        errors++;
        continue;
      }

      // Preserve existing currentLocationId; new trailers default to MUL.
      const currentLocationId =
        existing?.currentLocationId ?? locByCode['MULBERRY']!.id;

      const updateData = {
        trailerModelId: modelId,
        currentLocationId,
        status: TrailerStatus.ready_for_delivery,
        ...(r.lengthFt ? { sizeFt: `${r.lengthFt}ft` } : {}),
      };
      const trailer = await prisma.trailer.upsert({
        where: { soNumber: r.soNumber },
        update: updateData,
        create: {
          ...updateData,
          soNumber: r.soNumber,
          isStockBuild: false,
          createdByUserId: creator.id,
        },
        select: { id: true, soNumber: true, qbSoPdfStorageKey: true },
      });
      trailerId = trailer.id;
      qbSoPdfStorageKey = trailer.qbSoPdfStorageKey;
      if (existing) trailersUpdated++;
      else trailersCreated++;

      // Scheduled stack_to_location.
      const hasStack = await prisma.delivery.findFirst({
        where: {
          trailerId,
          deliveryType: DeliveryType.stack_to_location,
          destinationLocationId: destLoc.id,
          status: { in: [DeliveryStatus.scheduled, DeliveryStatus.in_transit] },
        },
        select: { id: true },
      });
      if (hasStack) {
        stackDeliveriesSkipped++;
      } else {
        await prisma.delivery.create({
          data: {
            trailerId,
            deliveryType: DeliveryType.stack_to_location,
            destinationLocationId: destLoc.id,
            status: DeliveryStatus.scheduled,
            createdByUserId: creator.id,
          },
        });
        stackDeliveriesCreated++;
      }

      console.log(
        `  🚚 ${r.soNumber.padEnd(6)} ${modelCode.padEnd(13)} → STACK to ${destLoc.name}`,
      );
    } else {
      // ─── Dealer delivery (stack_to_dealer → Tropic Trailers) ──────────────
      const currentLocationId =
        existing?.currentLocationId ?? locByCode['MULBERRY']!.id;

      const updateData = {
        trailerModelId: modelId,
        currentLocationId,
        status: TrailerStatus.ready_for_delivery,
        saleStatus: TrailerSaleStatus.sold,
        customerId: tropic.id,
        customerLocked: true,
        soldToName: TROPIC_DEALER_NAME,
        ...(r.lengthFt ? { sizeFt: `${r.lengthFt}ft` } : {}),
      };
      const trailer = await prisma.trailer.upsert({
        where: { soNumber: r.soNumber },
        update: updateData,
        create: {
          ...updateData,
          soNumber: r.soNumber,
          isStockBuild: false,
          createdByUserId: creator.id,
        },
        select: { id: true, soNumber: true, qbSoPdfStorageKey: true },
      });
      trailerId = trailer.id;
      qbSoPdfStorageKey = trailer.qbSoPdfStorageKey;
      if (existing) trailersUpdated++;
      else trailersCreated++;

      const hasDealer = await prisma.delivery.findFirst({
        where: {
          trailerId,
          deliveryType: DeliveryType.stack_to_dealer,
          status: { in: [DeliveryStatus.scheduled, DeliveryStatus.in_transit] },
        },
        select: { id: true },
      });
      if (hasDealer) {
        dealerDeliveriesSkipped++;
      } else {
        await prisma.delivery.create({
          data: {
            trailerId,
            deliveryType: DeliveryType.stack_to_dealer,
            customerDeliveryAddress: TROPIC_DEALER_ADDRESS,
            status: DeliveryStatus.scheduled,
            createdByUserId: creator.id,
          },
        });
        dealerDeliveriesCreated++;
      }

      console.log(
        `  🏪 ${r.soNumber.padEnd(6)} ${modelCode.padEnd(13)} → DEALER ${TROPIC_DEALER_NAME}`,
      );
    }

    // ─── PDF upload (shared across all kinds) ────────────────────────────────
    if (!uploader) {
      pdfsSkipped++;
      continue;
    }
    if (qbSoPdfStorageKey) {
      pdfsSkipped++;
      continue;
    }
    const pdfPath = join(PDF_ROOT, r.bucket, r.file);
    if (!existsSync(pdfPath)) {
      console.error(`     ✖ PDF missing: ${pdfPath}`);
      pdfsSkipped++;
      continue;
    }
    try {
      const key = await uploader.upload(r.bucket, r.file, r.soNumber);
      await prisma.trailer.update({
        where: { id: trailerId },
        data: { qbSoPdfStorageKey: key, qbSoPdfStorageUrl: key },
      });
      pdfsAttached++;
    } catch (e) {
      console.error(`     ✖ PDF upload failed: ${(e as Error).message}`);
    }
  }

  // ─── 6. Group non-pickup deliveries into batches + assign dev driver ───────
  // factory_pickup is excluded — those are customer-walks-in events and don't
  // belong to a truck batch. stack_to_location groups by destination yard;
  // stack_to_dealer all go into one Tropic batch.
  console.log('\n📦 Grouping scheduled deliveries into driver batches...');

  const devDriver = await prisma.user.findUnique({
    where: { email: DEV_DRIVER_EMAIL },
    select: { id: true, fullName: true },
  });
  if (!devDriver) {
    console.log(
      `  ⚠ ${DEV_DRIVER_EMAIL} not found — skipping batch assignment.\n`,
    );
  } else {
    let batchesCreated = 0;
    let batchesReused = 0;
    let deliveriesAssigned = 0;

    // Helper: upsert a batch by batchNumber + attach the given deliveries.
    const ensureBatch = async (args: {
      batchNumber: string;
      batchType: BatchType;
      destinationLocationId: number | null;
      destinationName: string | null;
      deliveryIds: bigint[];
    }): Promise<void> => {
      if (args.deliveryIds.length === 0) return;

      const existing = await prisma.deliveryBatch.findUnique({
        where: { batchNumber: args.batchNumber },
        select: { id: true },
      });
      const batch = existing
        ? existing
        : await prisma.deliveryBatch.create({
            data: {
              batchNumber: args.batchNumber,
              batchType: args.batchType,
              destinationLocationId: args.destinationLocationId,
              destinationName: args.destinationName,
              driverUserId: devDriver.id,
              status: DeliveryBatchStatus.scheduled,
              createdByUserId: creator.id,
            },
            select: { id: true },
          });
      if (existing) batchesReused++;
      else batchesCreated++;

      // updateMany skips rows already on this batch+driver, so re-runs are
      // a no-op. We still match on `in: deliveryIds` to scope the write.
      const result = await prisma.delivery.updateMany({
        where: {
          id: { in: args.deliveryIds },
          OR: [
            { deliveryBatchId: null },
            { driverUserId: null },
          ],
        },
        data: {
          deliveryBatchId: batch.id,
          driverUserId: devDriver.id,
        },
      });
      deliveriesAssigned += result.count;

      const dest = args.destinationName ?? `loc#${args.destinationLocationId}`;
      console.log(
        `  ${existing ? '=' : '+'} batch ${args.batchNumber.padEnd(18)} → ${dest} (${args.deliveryIds.length} deliveries, ${result.count} newly assigned)`,
      );
    };

    // Pull the scheduled stack_to_location deliveries we just produced.
    const stackDeliveries = await prisma.delivery.findMany({
      where: {
        deliveryType: DeliveryType.stack_to_location,
        status: DeliveryStatus.scheduled,
      },
      select: { id: true, destinationLocationId: true },
    });
    const byDestId = new Map<number, bigint[]>();
    for (const d of stackDeliveries) {
      if (d.destinationLocationId == null) continue;
      const arr = byDestId.get(d.destinationLocationId) ?? [];
      arr.push(d.id);
      byDestId.set(d.destinationLocationId, arr);
    }
    for (const [destLocationId, ids] of byDestId) {
      const locEntry = Object.entries(locByCode).find(
        ([, l]) => l.id === destLocationId,
      );
      if (!locEntry) continue;
      const [code, loc] = locEntry;
      const batchNumber = BATCH_NUMBER_BY_DEST_LOCATION_CODE[code];
      if (!batchNumber) continue; // ignore destinations not in our seed set
      await ensureBatch({
        batchNumber,
        batchType: BatchType.bf_location,
        destinationLocationId: destLocationId,
        destinationName: loc.name,
        deliveryIds: ids,
      });
    }

    // Pull the scheduled stack_to_dealer deliveries (all Tropic in this batch).
    const dealerDeliveries = await prisma.delivery.findMany({
      where: {
        deliveryType: DeliveryType.stack_to_dealer,
        status: DeliveryStatus.scheduled,
      },
      select: { id: true },
    });
    if (dealerDeliveries.length > 0) {
      await ensureBatch({
        batchNumber: BATCH_NUMBER_TROPIC,
        batchType: BatchType.dealer,
        destinationLocationId: null,
        destinationName: TROPIC_DEALER_NAME,
        deliveryIds: dealerDeliveries.map((d) => d.id),
      });
    }

    console.log(
      `✅ Batches: ${batchesCreated} created, ${batchesReused} reused. ${deliveriesAssigned} deliveries assigned to ${devDriver.fullName}.`,
    );
  }

  console.log(
    `\n🎉 Done.\n` +
      `  Trailers:           ${trailersCreated} created, ${trailersUpdated} updated\n` +
      `  Stock deliveries:   ${stockDeliveriesCreated} created, ${stockDeliveriesSkipped} kept (sold-pending → yard)\n` +
      `  Pickup deliveries:  ${pickupDeliveriesCreated} created, ${pickupDeliveriesSkipped} kept (scheduled factory_pickup)\n` +
      `  Stack deliveries:   ${stackDeliveriesCreated} created, ${stackDeliveriesSkipped} kept (scheduled stack_to_location)\n` +
      `  Dealer deliveries:  ${dealerDeliveriesCreated} created, ${dealerDeliveriesSkipped} kept (scheduled stack_to_dealer)\n` +
      `  PDFs:               ${pdfsAttached} attached, ${pdfsSkipped} skipped` +
      (errors ? `\n  Errors:             ${errors}` : ''),
  );
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
