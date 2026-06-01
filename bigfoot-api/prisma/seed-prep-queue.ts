// =============================================================================
// BIGFOOT TRAILERS — Prep-queue seed (single-pass)
//
// 50 trailers, 5 source buckets:
//   wood          → step 11 (WOOD) in the model's series workflow
//   wire-hydro    → step 9 (WIRE for xp/yeti/deck_over; HYDRAULICS for
//                   gooseneck_dump — the per-series template carries the
//                   correct dept)
//   paint-prep    → step 5 (PAINT_PREP)
//   enclosed-mul  → ENCLOSED inventory model (no workflow), at MULBERRY
//   enclosed-va   → ENCLOSED inventory model, at TAPPAHANNOCK
//
// Workflow buckets: 12 production_steps created. Pre-start steps = complete,
// start step = active, post-start = waiting. trailer.status = in_production.
//
// Customer / stock detection from PDF shipTo (applied to BOTH newly created
// trailers and existing ones — earlier runs of this seed didn't carry it):
//   "Open Stock <yard>" / "OPEN STOCK KENNY" → isStockBuild=true,
//     currentLocationId = matched yard, saleStatus=available.
//   "Tropic Trailers"                        → customerId=Tropic dealer,
//     saleStatus=sold, soldToName="Tropic Trailers".
//   Anything else with text                  → saleStatus=sold,
//     soldToName=parsed customer.
//
// Idempotent: re-runs skip the production-step generation for existing
// trailers (so we don't stomp work already past the seeded step) but DO
// reconcile saleStatus / isStockBuild / customer fields.
//
// Run: npx tsx prisma/seed-prep-queue.ts
// =============================================================================

import 'dotenv/config';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import {
  CustomerType,
  Prisma,
  ProductionStepStatus,
  TrailerSaleStatus,
  TrailerSeries,
  TrailerStatus,
} from '@prisma/client';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DATA_JSON = join(__dirname, 'data', 'prep-queue-trailers.json');
const PDF_ROOT =
  process.env['PREP_QUEUE_PDF_ROOT'] ??
  join(__dirname, 'data', 'prep-queue-pdfs');

const TROPIC_DEALER_NAME = 'Tropic Trailers';

const MODEL_BY_PDF_CODE: Record<string, string> = {
  '10ET18XP': 'XP_10K',
  '10ET20XP': 'XP_10K',
  '10ET22XP': 'XP_10K',
  '10ET24XP': 'XP_10K',
  '14ET14XP': 'XP_14ET',
  '14ET16XP': 'XP_14ET',
  '14ET18XP': 'XP_14ET',
  '14ET20XP': 'XP_14ET',
  '14ET22XP': 'XP_14ET',
  '14ET24XP': 'XP_14ET',
  '17ET20XP': 'XP_17K',
  '17ET22': 'XP_17K',
  '17ET24': 'XP_17K',
  '15ET20YETI': 'YETI_15K',
  '15ET22YETI': 'YETI_15K',
  '15ET24YETI': 'YETI_15K',
  '18ET20YETI': 'YETI_18K',
  '18ET24YETI': 'YETI_18K',
  '21ET24YETI': 'YETI_21K',
  '15ET20TLT': 'TLT_15K',
  '15TET24TLT': 'TLT_15K',
  '15TLT22': 'TLT_15K',
  '18ET20TLT': 'TLT_18K',
  '18ET24TLT': 'TLT_18K',
  '18TLT22': 'TLT_18K',
  '21ET24TLT': 'TLT_21K',
  '21TLT26': 'TLT_21K',
  '10DO24': 'DO_10K',
  '14DO20': 'DO_14K',
  '14DO20FLT': 'DO_14K',
  '14DO24FLT': 'DO_14K',
  '14DO25': 'DO_14K',
  '14DO26FLT': 'DO_14K',
  '17DO22': 'DO_17K',
  '17DO25': 'DO_17K',
  '17DO26': 'DO_17K',
  '21DO25': 'DO_22K',
  '22DO25': 'DO_22K',
  '25DO30': 'DO_26K',
  '25DO35': 'DO_26K',
  '22GN25': 'GN_22K',
  '22GN30': 'GN_22K',
  '26GN30': 'GN_26K',
  '26GN32-40': 'GN_26K',
  '26GN36-40': 'GN_26K',
  '18DU16-2': 'DUMP_18K',
  '26DU20GN': 'DUMP_26K_GN',
  '7X16TA2': 'ENCLOSED',
};

const STOCK_PATTERNS: { regex: RegExp; locationCode: string }[] = [
  { regex: /open stock\s+mulberry/i, locationCode: 'MULBERRY' },
  { regex: /open stock\s+jacksonville/i, locationCode: 'JACKSONVILLE' },
  { regex: /open stock\s+(?:atlanta|georgia)/i, locationCode: 'ATLANTA' },
  { regex: /open stock\s+tallahassee/i, locationCode: 'TALLAHASSEE' },
  // "OPEN STOCK KENNY" — Kenny is the Tappahannock yard contact.
  { regex: /open stock\s+kenny/i, locationCode: 'TAPPAHANNOCK' },
  { regex: /\bopen stock\b/i, locationCode: 'MULBERRY' },
];

interface PdfRecord {
  bucket: string;
  kind: 'workflow' | 'inventory';
  startStepOrder: number | null;
  startDeptHint: string | null;
  locationCode: string | null;
  file: string;
  soNumber: string;
  pdfModelCode: string | null;
  shipTo: string | null;
  shipToLines: string[];
  date: string | null;
  lengthFt: string | null;
}

function detectStockLocationCode(shipTo: string | null): string | null {
  if (!shipTo) return null;
  for (const p of STOCK_PATTERNS) if (p.regex.test(shipTo)) return p.locationCode;
  return null;
}

function customerNameFrom(shipTo: string | null): string | null {
  if (!shipTo) return null;
  if (detectStockLocationCode(shipTo)) return null;
  const beforeDigits = shipTo.match(/^([^0-9]+?)(?=\s+\d)/);
  let name = (beforeDigits ? beforeDigits[1] : shipTo).trim();
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

interface SaleDecision {
  currentLocationCode: string;
  isStockBuild: boolean;
  saleStatus: TrailerSaleStatus;
  soldToName: string | null;
  customerId: bigint | null;
  customerLocked: boolean;
  tag: string;
}

function decideSale(
  r: PdfRecord,
  tropic: { id: bigint } | null,
): SaleDecision {
  if (r.kind === 'inventory') {
    return {
      currentLocationCode: r.locationCode!,
      isStockBuild: true,
      saleStatus: TrailerSaleStatus.available,
      soldToName: null,
      customerId: null,
      customerLocked: false,
      tag: `stock@${r.locationCode}`,
    };
  }
  const stockYard = detectStockLocationCode(r.shipTo);
  if (stockYard) {
    return {
      currentLocationCode: stockYard,
      isStockBuild: true,
      saleStatus: TrailerSaleStatus.available,
      soldToName: null,
      customerId: null,
      customerLocked: false,
      tag: `stock@${stockYard}`,
    };
  }
  if (tropic && r.shipTo && /tropic trailers/i.test(r.shipTo)) {
    return {
      currentLocationCode: 'MULBERRY',
      isStockBuild: false,
      saleStatus: TrailerSaleStatus.sold,
      soldToName: TROPIC_DEALER_NAME,
      customerId: tropic.id,
      customerLocked: true,
      tag: 'sold→Tropic',
    };
  }
  const name = customerNameFrom(r.shipTo);
  return {
    currentLocationCode: 'MULBERRY',
    isStockBuild: false,
    saleStatus: TrailerSaleStatus.sold,
    soldToName: name,
    customerId: null,
    customerLocked: false,
    tag: name ? `sold→"${name}"` : 'sold→?',
  };
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
  console.log('🛠  Seeding prep-queue trailers...\n');

  await prisma.$executeRawUnsafe(
    `ALTER TYPE trailer_series_enum ADD VALUE IF NOT EXISTS 'inventory';`,
  );

  const owner =
    (await prisma.user.findFirst({ where: { role: 'owner' } })) ??
    (await prisma.user.findFirst());
  if (!owner) throw new Error('No users in DB.');

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
    if (!loc) throw new Error(`Location ${code} missing.`);
    locByCode[code] = loc;
  }

  const tropic = await prisma.customer.findFirst({
    where: { name: TROPIC_DEALER_NAME, customerType: CustomerType.dealer },
    select: { id: true, name: true },
  });

  const modelsByCode = new Map<
    string,
    { id: number; series: TrailerSeries }
  >();
  for (const m of await prisma.trailerModel.findMany({
    select: { id: true, code: true, series: true },
  })) {
    modelsByCode.set(m.code, { id: m.id, series: m.series });
  }

  if (!existsSync(DATA_JSON)) {
    throw new Error(
      `Missing ${DATA_JSON} — run: npx tsx scripts/extract-prep-queue-trailers.ts`,
    );
  }
  const records: PdfRecord[] = JSON.parse(readFileSync(DATA_JSON, 'utf8'));
  console.log(`📋 Loaded ${records.length} records\n`);

  const uploader = buildSpacesUploader();
  if (!uploader) console.log('⚠ Spaces creds not set — skipping PDF upload.\n');

  let trailersCreated = 0;
  let trailersUpdated = 0;
  let stepsCreated = 0;
  let pdfsAttached = 0;
  let pdfsSkipped = 0;
  let errors = 0;

  for (const r of records) {
    const modelCode = r.pdfModelCode
      ? MODEL_BY_PDF_CODE[r.pdfModelCode]
      : undefined;
    if (!modelCode) {
      console.error(
        `  ✖ SO ${r.soNumber} (${r.bucket}): no mapping for "${r.pdfModelCode}"`,
      );
      errors++;
      continue;
    }
    const model = modelsByCode.get(modelCode);
    if (!model) {
      console.error(`  ✖ SO ${r.soNumber}: model ${modelCode} not in DB.`);
      errors++;
      continue;
    }

    const decision = decideSale(r, tropic);
    const currentLocation = locByCode[decision.currentLocationCode]!;

    const existing = await prisma.trailer.findUnique({
      where: { soNumber: r.soNumber },
      select: { id: true, qbSoPdfStorageKey: true },
    });

    if (existing) {
      // Reconcile sale/customer/stock for trailers that earlier seed runs
      // created without this info. Production steps are left alone.
      // Use unchecked update so we can write the FK scalars directly without
      // mixing relation syntax (Prisma rejects `customer: { connect }` next
      // to `currentLocationId: ...` in the same call).
      const update: Prisma.TrailerUncheckedUpdateInput = {
        currentLocationId: currentLocation.id,
        isStockBuild: decision.isStockBuild,
        saleStatus: decision.saleStatus,
        soldToName: decision.soldToName,
        customerLocked: decision.customerLocked,
        customerId: decision.customerId,
      };
      await prisma.trailer.update({ where: { id: existing.id }, data: update });
      trailersUpdated++;
      console.log(
        `  ~ SO ${r.soNumber.padEnd(6)} ${modelCode.padEnd(13)} reconciled [${decision.tag}]`,
      );

      // Backfill PDF if missing.
      if (uploader && !existing.qbSoPdfStorageKey) {
        try {
          const key = await uploader.upload(r.bucket, r.file, r.soNumber);
          await prisma.trailer.update({
            where: { id: existing.id },
            data: { qbSoPdfStorageKey: key, qbSoPdfStorageUrl: key },
          });
          pdfsAttached++;
        } catch (e) {
          console.error(`     ✖ PDF upload failed: ${(e as Error).message}`);
          pdfsSkipped++;
        }
      } else {
        pdfsSkipped++;
      }
      continue;
    }

    // ─── Inventory bucket (ENCLOSED) — no workflow, straight to ready ────────
    if (r.kind === 'inventory') {
      const created = await prisma.trailer.create({
        data: {
          soNumber: r.soNumber,
          trailerModelId: model.id,
          currentLocationId: currentLocation.id,
          status: TrailerStatus.ready_for_delivery,
          saleStatus: decision.saleStatus,
          soldToName: decision.soldToName,
          customerLocked: decision.customerLocked,
          customerId: decision.customerId,
          isStockBuild: decision.isStockBuild,
          createdByUserId: owner.id,
          ...(r.lengthFt ? { sizeFt: r.lengthFt } : {}),
        },
        select: { id: true, soNumber: true },
      });
      trailersCreated++;
      console.log(
        `  + SO ${created.soNumber.padEnd(6)} ${modelCode.padEnd(13)} ENCLOSED ready_for_delivery [${decision.tag}]`,
      );
      if (uploader) {
        try {
          const key = await uploader.upload(r.bucket, r.file, r.soNumber);
          await prisma.trailer.update({
            where: { id: created.id },
            data: { qbSoPdfStorageKey: key, qbSoPdfStorageUrl: key },
          });
          pdfsAttached++;
        } catch (e) {
          console.error(`     ✖ PDF upload failed: ${(e as Error).message}`);
          pdfsSkipped++;
        }
      } else {
        pdfsSkipped++;
      }
      continue;
    }

    // ─── Workflow bucket — 12 steps with the target one set active ──────────
    const templates = await prisma.workflowTemplate.findMany({
      where: { series: model.series },
      orderBy: { stepOrder: 'asc' },
      include: { department: { select: { id: true, code: true } } },
    });
    if (templates.length !== 12) {
      console.error(
        `  ✖ SO ${r.soNumber}: expected 12 templates for series ${model.series}, got ${templates.length}`,
      );
      errors++;
      continue;
    }
    const startStep = Math.max(1, Math.min(12, r.startStepOrder!));

    const trailerId = await prisma.$transaction(async (tx) => {
      const trailer = await tx.trailer.create({
        data: {
          soNumber: r.soNumber,
          trailerModelId: model.id,
          currentLocationId: currentLocation.id,
          status: TrailerStatus.in_production,
          saleStatus: decision.saleStatus,
          soldToName: decision.soldToName,
          customerLocked: decision.customerLocked,
          customerId: decision.customerId,
          isStockBuild: decision.isStockBuild,
          createdByUserId: owner.id,
          ...(r.lengthFt ? { sizeFt: r.lengthFt } : {}),
        },
        select: { id: true },
      });

      const now = new Date();
      for (const t of templates) {
        let status: ProductionStepStatus;
        let becameActiveAt: Date | null = null;
        let completedAt: Date | null = null;
        let queuePosition: number | null = null;
        if (t.stepOrder < startStep) {
          status = ProductionStepStatus.complete;
          becameActiveAt = now;
          completedAt = now;
        } else if (t.stepOrder === startStep) {
          status = ProductionStepStatus.active;
          becameActiveAt = now;
          queuePosition = 1;
        } else {
          status = ProductionStepStatus.waiting;
        }
        await tx.productionStep.create({
          data: {
            trailerId: trailer.id,
            departmentId: t.departmentId,
            stepOrder: t.stepOrder,
            status,
            queuePosition,
            becameActiveAt,
            completedAt,
          },
        });
      }
      return trailer.id;
    });
    trailersCreated++;
    stepsCreated += 12;

    const targetDept =
      templates.find((t) => t.stepOrder === startStep)?.department.code ?? '?';
    console.log(
      `  + SO ${r.soNumber.padEnd(6)} ${modelCode.padEnd(13)} ${model.series.padEnd(15)} step ${startStep} (${targetDept}) [${decision.tag}]`,
    );

    if (uploader) {
      try {
        const key = await uploader.upload(r.bucket, r.file, r.soNumber);
        await prisma.trailer.update({
          where: { id: trailerId },
          data: { qbSoPdfStorageKey: key, qbSoPdfStorageUrl: key },
        });
        pdfsAttached++;
      } catch (e) {
        console.error(`     ✖ PDF upload failed: ${(e as Error).message}`);
        pdfsSkipped++;
      }
    } else {
      pdfsSkipped++;
    }
  }

  console.log(
    `\n🎉 Done.\n` +
      `  Trailers: ${trailersCreated} created, ${trailersUpdated} updated (reconciled customer/stock)\n` +
      `  Steps:    ${stepsCreated} created (12 per new workflow trailer)\n` +
      `  PDFs:     ${pdfsAttached} attached, ${pdfsSkipped} skipped` +
      (errors ? `\n  Errors:   ${errors}` : ''),
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
