// =============================================================================
// BIGFOOT TRAILERS — Multi-location open-stock packing-slip seed
//
// Reads every record from prisma/data/open-stock-trailers.json (extracted from
// prisma/data/open-stock-pdfs/<location>/*.pdf by scripts/extract-pdf-trailers.ts)
// and lands each trailer in its source folder's stock yard:
//
//   open-stock-pdfs/mulberry/*.pdf      → MULBERRY stock inventory
//   open-stock-pdfs/jacksonville/*.pdf  → JACKSONVILLE stock inventory
//   open-stock-pdfs/atlanta/*.pdf       → ATLANTA stock inventory
//   open-stock-pdfs/tallahassee/*.pdf   → TALLAHASSEE stock inventory
//   open-stock-pdfs/tappahannock/*.pdf  → TAPPAHANNOCK stock inventory
//
// Per trailer it:
//   1. Upserts trailer (by so_number) with isStockBuild=true, status=delivered,
//      saleStatus=available, currentLocationId=<folder>, all notes cleared.
//   2. Creates a delivered stack_to_location Delivery to the folder's location
//      (idempotent — skipped if one already exists for that destination).
//      The Stock Inventory query keys off the latest delivered Delivery, not
//      trailer.currentLocationId, so this is what makes the trailer show up
//      under the right yard in the app.
//   3. Uploads the PDF to Spaces (if DO_SPACES_* env vars are set) and links
//      it as qbSoPdfStorageKey. Skipped if the trailer already carries a key.
//
// Inventory-only models (Triple Crown utility / equipment / GN, etc.) skip
// workflow generation thanks to series=inventory on TrailerModel — they're
// created straight in delivered state.
//
// Idempotent across all 93 records — re-running is safe and will reconcile
// any drift on prior trailers (e.g., the 25 Mulberry trailers already seeded
// by seed-open-mul + seed-open-mul-restock).
//
// Run with:
//   # Local (no PDF upload):
//   npx tsx prisma/seed-open-stock.ts
//
//   # Production (PDFs uploaded to Spaces):
//   DO_SPACES_ENDPOINT=... DO_SPACES_ACCESS_KEY=... \
//   DO_SPACES_SECRET_KEY=... DO_SPACES_BUCKET=... \
//   npx tsx prisma/seed-open-stock.ts
// =============================================================================

import 'dotenv/config';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import {
  DeliveryStatus,
  DeliveryType,
  TrailerSaleStatus,
  TrailerSeries,
  TrailerStatus,
} from '@prisma/client';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DATA_JSON = join(__dirname, 'data', 'open-stock-trailers.json');
const PDF_ROOT =
  process.env['OPEN_STOCK_PDF_ROOT'] ??
  join(__dirname, 'data', 'open-stock-pdfs');

// ─── Folder name (lowercased) → DB location code ────────────────────────────
// Mirrors the table in scripts/extract-pdf-trailers.ts.
const FOLDER_TO_LOCATION_CODE: Record<string, string> = {
  mulberry: 'MULBERRY',
  jacksonville: 'JACKSONVILLE',
  atlanta: 'ATLANTA',
  tallahassee: 'TALLAHASSEE',
  tappahannock: 'TAPPAHANNOCK',
};

// ─── Models referenced by the open-stock PDFs that aren't already in the
// base catalog. seed-open-mul + seed-inventory-models-and-sales added the
// rest. TLT_21K is new for the 21K Top Load Tilt that appears in the
// Jacksonville batch (SO 6555 etc.).
// ─────────────────────────────────────────────────────────────────────────
const NEW_MODELS: {
  code: string;
  displayName: string;
  series: TrailerSeries;
  weightRating: string;
}[] = [
  {
    code: 'TLT_21K',
    displayName: '21K Tilt',
    series: TrailerSeries.yeti,
    weightRating: '21,000 lb',
  },
];

// ─── PDF "service code" → trailer_model.code ────────────────────────────────
// Consolidated table covering every distinct code surfaced by the extractor
// across all 5 location folders (32 codes total).
const MODEL_BY_PDF_CODE: Record<string, string> = {
  // 14K XP series (different lengths, same model)
  '14ET16XP': 'XP_14ET',
  '14ET18XP': 'XP_14ET',
  '14ET20XP': 'XP_14ET',
  '14ET24XP': 'XP_14ET',

  // YETI (15/18/21K)
  '15ET20YETI': 'YETI_15K',
  '18ET20YETI': 'YETI_18K',
  '18ET22YETI': 'YETI_18K',
  '18ET24YETI': 'YETI_18K',
  '21ET24YETI': 'YETI_21K',

  // Top Load Tilt (15/18/21K)
  '15ET20TLT': 'TLT_15K',
  '15TET24TLT': 'TLT_15K',
  '15TLT22': 'TLT_15K',
  '18ET20TLT': 'TLT_18K',
  '18ET24TLT': 'TLT_18K',
  '18TLT22': 'TLT_18K',
  '18TLT26': 'TLT_18K',
  '21ET24TLT': 'TLT_21K',

  // Deck Over (14/17/22/26K)
  '14DO20': 'DO_14K',
  '14DO25': 'DO_14K',
  '17DO25': 'DO_17K',
  '22DO25': 'DO_22K', // PDF says 23K GVWR — DO_22K is the closest catalog rung
  '25DO30': 'DO_26K', // 25K rating, 30ft deck — closest catalog rung

  // Gooseneck (Bigfoot 21K)
  '21ET26': 'GN_21K',

  // Triple Crown brand — utility (U…), equipment (E…), gooseneck dump (GN…-DT).
  // All map to the inventory-only TRIPLE_CROWN model so they skip workflow
  // generation and land straight in ready_for_delivery → delivered.
  'GN16-35DT': 'TRIPLE_CROWN',
  'GN22-30DT': 'TRIPLE_CROWN',
  'GN22-40DT': 'TRIPLE_CROWN',
  'GN25-40DT': 'TRIPLE_CROWN',
  E7X2014K: 'TRIPLE_CROWN',
  E8X2414K: 'TRIPLE_CROWN',
  U5X10S140: 'TRIPLE_CROWN',
  U6X12S140: 'TRIPLE_CROWN',
  U6X16T140: 'TRIPLE_CROWN',
};

interface ExtractedRecord {
  locationCode: string;
  folder: string;
  file: string;
  soNumber: string;
  pdfModelCode: string | null;
  shipTo: string | null;
  date: string | null;
  lengthFt: string | null;
  gvwr: string | null;
  rawDescriptionHead: string;
}

// "MM/DD/YYYY" → Date in UTC at midday, or null if unparseable.
function parsePdfDate(s: string | null): Date | null {
  if (!s) return null;
  const m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!m) return null;
  const [, mm, dd, yyyy] = m;
  const d = new Date(Date.UTC(Number(yyyy), Number(mm) - 1, Number(dd), 12));
  return Number.isNaN(d.getTime()) ? null : d;
}

// ─── Optional Spaces uploader ───────────────────────────────────────────────
interface SpacesUploader {
  upload(folder: string, pdfFile: string, soNumber: string): Promise<string>;
}

function buildSpacesUploader(): SpacesUploader | null {
  const endpoint = process.env['DO_SPACES_ENDPOINT'];
  const accessKeyId = process.env['DO_SPACES_ACCESS_KEY'];
  const secretAccessKey = process.env['DO_SPACES_SECRET_KEY'];
  const bucket = process.env['DO_SPACES_BUCKET'];
  const region = process.env['DO_SPACES_REGION'] ?? 'us-east-1';
  if (!endpoint || !accessKeyId || !secretAccessKey || !bucket) return null;

  const s3 = new S3Client({
    endpoint,
    region,
    credentials: { accessKeyId, secretAccessKey },
    forcePathStyle: false,
  });

  return {
    async upload(folder, pdfFile, soNumber): Promise<string> {
      const bytes = readFileSync(join(PDF_ROOT, folder, pdfFile));
      const uuid = randomUUID();
      const soSlug = soNumber.toLowerCase().replace(/[^a-z0-9-]/g, '-');
      const storageKey = `so-pdf/${soSlug}/${uuid}.pdf`;
      await s3.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key: storageKey,
          Body: bytes,
          ContentType: 'application/pdf',
        }),
      );
      return storageKey;
    },
  };
}

async function main(): Promise<void> {
  console.log(
    '🚛 Seeding multi-location open-stock packing-slip trailers...\n',
  );

  // ─── 0. Defensive: ensure the 'inventory' enum value is present in prod.
  // seed-inventory-models-and-sales applied this already, but re-running
  // this seed on a fresh DB where that one hasn't run yet would otherwise
  // fail on the TRIPLE_CROWN upsert. ALTER TYPE ADD VALUE can't run in a
  // transaction; $executeRawUnsafe issues it on its own connection.
  await prisma.$executeRawUnsafe(
    `ALTER TYPE trailer_series_enum ADD VALUE IF NOT EXISTS 'inventory';`,
  );

  // ─── 1. Upsert any new models referenced by this batch ─────────────────────
  for (const m of NEW_MODELS) {
    await prisma.trailerModel.upsert({
      where: { code: m.code },
      update: {},
      create: m,
    });
  }
  console.log(`✅ Catalog: ensured ${NEW_MODELS.length} new model(s).\n`);

  // ─── 2. Load locations referenced by any folder ────────────────────────────
  const locationsByCode: Record<string, { id: number; name: string }> = {};
  for (const code of Object.values(FOLDER_TO_LOCATION_CODE)) {
    const loc = await prisma.location.findUnique({
      where: { code },
      select: { id: true, name: true },
    });
    if (!loc) {
      throw new Error(
        `Location ${code} not found. Run the base seed first: npx tsx prisma/seed.ts`,
      );
    }
    locationsByCode[code] = loc;
  }

  const creator =
    (await prisma.user.findFirst({ where: { role: 'owner' } })) ??
    (await prisma.user.findFirst());
  if (!creator) {
    throw new Error('No users in DB — run the base seed first.');
  }

  // ─── 3. Models index ───────────────────────────────────────────────────────
  const modelsByCode = new Map<string, number>();
  for (const m of await prisma.trailerModel.findMany({
    select: { id: true, code: true },
  })) {
    modelsByCode.set(m.code, m.id);
  }

  // ─── 4. Load extracted records ─────────────────────────────────────────────
  if (!existsSync(DATA_JSON)) {
    throw new Error(
      `Missing ${DATA_JSON} — run: npx tsx scripts/extract-pdf-trailers.ts`,
    );
  }
  const records: ExtractedRecord[] = JSON.parse(readFileSync(DATA_JSON, 'utf8'));
  console.log(
    `📋 Loaded ${records.length} records across ${
      new Set(records.map((r) => r.locationCode)).size
    } locations\n`,
  );

  const uploader = buildSpacesUploader();
  if (!uploader) {
    console.log(
      '⚠ Spaces creds not set (DO_SPACES_*) — skipping PDF upload.\n',
    );
  }

  // ─── 5. Process each record ────────────────────────────────────────────────
  let trailersCreated = 0;
  let trailersUpdated = 0;
  let deliveriesCreated = 0;
  let deliveriesSkipped = 0;
  let pdfsAttached = 0;
  let pdfsSkipped = 0;
  let errors = 0;

  for (const r of records) {
    const modelCode = r.pdfModelCode
      ? MODEL_BY_PDF_CODE[r.pdfModelCode]
      : undefined;
    if (!modelCode) {
      console.error(
        `  ✖ SO ${r.soNumber} (${r.folder}): no mapping for PDF code "${r.pdfModelCode}"`,
      );
      errors++;
      continue;
    }
    const modelId = modelsByCode.get(modelCode);
    if (!modelId) {
      console.error(
        `  ✖ SO ${r.soNumber} (${r.folder}): unknown model ${modelCode} (run seed-inventory-models-and-sales first?)`,
      );
      errors++;
      continue;
    }

    const loc = locationsByCode[r.locationCode];
    if (!loc) {
      console.error(
        `  ✖ SO ${r.soNumber}: location ${r.locationCode} missing`,
      );
      errors++;
      continue;
    }

    // ─── 5a. Upsert trailer ─────────────────────────────────────────────────
    const existing = await prisma.trailer.findUnique({
      where: { soNumber: r.soNumber },
      select: { id: true, qbSoPdfStorageKey: true },
    });

    const data = {
      trailerModelId: modelId,
      currentLocationId: loc.id,
      isStockBuild: true,
      status: TrailerStatus.delivered,
      saleStatus: TrailerSaleStatus.available,
      customerId: null,
      customerLocked: false,
      soldToName: null,
      optionsNotes: null,
      specialNote: null,
      // Store just the number; UI appends "ft" at render.
      ...(r.lengthFt ? { sizeFt: r.lengthFt } : {}),
    };

    const trailer = await prisma.trailer.upsert({
      where: { soNumber: r.soNumber },
      update: data,
      create: {
        ...data,
        soNumber: r.soNumber,
        createdByUserId: creator.id,
      },
      select: { id: true, soNumber: true, qbSoPdfStorageKey: true },
    });
    if (existing) trailersUpdated++;
    else trailersCreated++;

    // ─── 5b. Synthetic delivered Delivery to the folder's location ──────────
    // Stock Inventory keys off the latest delivered Delivery per trailer.
    const existingDelivery = await prisma.delivery.findFirst({
      where: {
        trailerId: trailer.id,
        status: DeliveryStatus.delivered,
        destinationLocationId: loc.id,
      },
      select: { id: true },
    });
    if (existingDelivery) {
      deliveriesSkipped++;
    } else {
      const deliveredAt = parsePdfDate(r.date) ?? new Date();
      await prisma.delivery.create({
        data: {
          trailerId: trailer.id,
          deliveryType: DeliveryType.stack_to_location,
          destinationLocationId: loc.id,
          status: DeliveryStatus.delivered,
          deliveredAt,
          createdByUserId: creator.id,
        },
      });
      deliveriesCreated++;
    }

    console.log(
      `  ✅ ${r.soNumber.padEnd(6)} ${modelCode.padEnd(13)} → ${loc.name}`,
    );

    // ─── 5c. Upload PDF if missing ──────────────────────────────────────────
    if (!uploader) {
      pdfsSkipped++;
      continue;
    }
    if (trailer.qbSoPdfStorageKey) {
      pdfsSkipped++;
      continue;
    }
    const pdfPath = join(PDF_ROOT, r.folder, r.file);
    if (!existsSync(pdfPath)) {
      console.error(`     ✖ PDF missing: ${pdfPath}`);
      pdfsSkipped++;
      continue;
    }
    try {
      const storageKey = await uploader.upload(r.folder, r.file, r.soNumber);
      await prisma.trailer.update({
        where: { id: trailer.id },
        data: {
          qbSoPdfStorageKey: storageKey,
          qbSoPdfStorageUrl: storageKey,
        },
      });
      pdfsAttached++;
      console.log(`     ↳ PDF → ${storageKey.slice(-60)}`);
    } catch (e) {
      console.error(`     ✖ PDF upload failed: ${(e as Error).message}`);
    }
  }

  console.log(
    `\n🎉 Done. Trailers: ${trailersCreated} created, ${trailersUpdated} updated. ` +
      `Deliveries: ${deliveriesCreated} created, ${deliveriesSkipped} kept. ` +
      `PDFs: ${pdfsAttached} attached, ${pdfsSkipped} skipped.` +
      (errors ? ` Errors: ${errors}.` : ''),
  );
}

main()
  .catch((e) => {
    console.error('❌ open-stock seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
