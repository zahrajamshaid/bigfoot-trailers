// =============================================================================
// BIGFOOT TRAILERS — Open-stock Packing Slip Seed (Mulberry batch)
//
// Inserts the 25 trailers extracted from the open-stock packing-slip PDFs in
// D:\BigFoot\all_trailers\open mul (mix of Mulberry, Jacksonville, Atlanta
// stock builds + 4 customer-assigned trailers). PDFs are optionally uploaded
// to DigitalOcean Spaces and linked as the trailer's QB SO PDF.
//
// Idempotent: trailer_models upsert by `code`, trailers upsert by
// `so_number`. PDF upload is skipped per trailer if the trailer already has
// a qb_so_pdf_storage_key, so re-running is safe.
//
// Run with:
//   # Local (no PDF upload — DO_SPACES_* not set):
//   npx tsx prisma/seed-open-mul.ts
//
//   # Production-style (PDFs go to Spaces):
//   OPEN_MUL_PDF_DIR=/data/open-mul \
//   DO_SPACES_ENDPOINT=... DO_SPACES_ACCESS_KEY=... \
//   DO_SPACES_SECRET_KEY=... DO_SPACES_BUCKET=... \
//   npx tsx prisma/seed-open-mul.ts
// =============================================================================

import 'dotenv/config';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { TrailerSeries, TrailerStatus } from '@prisma/client';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

// ─── Inputs ──────────────────────────────────────────────────────────────────
const DATA_JSON = join(__dirname, 'data', 'open-mul-trailers.json');
// PDFs ship inside the repo (prisma/data/open-mul-pdfs/) so the prod runner
// can read them straight out of the docker image. Override with
// OPEN_MUL_PDF_DIR to point at a mounted volume / external location.
const PDF_DIR =
  process.env['OPEN_MUL_PDF_DIR'] ?? join(__dirname, 'data', 'open-mul-pdfs');

// ─── New trailer models the open-mul batch references ──────────────────────
const NEW_MODELS: {
  code: string;
  displayName: string;
  series: TrailerSeries;
  weightRating: string;
}[] = [
  { code: 'TLT_15K', displayName: '15K Tilt', series: TrailerSeries.yeti, weightRating: '15,000 lb' },
  { code: 'TLT_18K', displayName: '18K Tilt', series: TrailerSeries.yeti, weightRating: '18,000 lb' },
  { code: 'GN_21K', displayName: '21K Gooseneck', series: TrailerSeries.gooseneck_dump, weightRating: '21,000 lb' },
];

// ─── PDF "service code" → trailer_model.code ────────────────────────────────
// Built from the extracted PDFs in the open-mul batch.
const MODEL_BY_PDF_CODE: Record<string, string> = {
  '18ET20YETI': 'YETI_18K',
  '15ET20YETI': 'YETI_15K',
  '18ET22YETI': 'YETI_18K',
  '17DO25': 'DO_17K',
  '21ET26': 'GN_21K',
  '14DO20': 'DO_14K',
  '18TLT26': 'TLT_18K',
  '18ET20TLT': 'TLT_18K',
  '18TLT22': 'TLT_18K',
  '15TET24TLT': 'TLT_15K',
  '18ET24TLT': 'TLT_18K',
  '15ET20TLT': 'TLT_15K',
  '15TLT22': 'TLT_15K',
  '14ET24XP': 'XP_14ET',
};

// "Ship to" line → location code. Anything that doesn't match a stock yard
// is treated as a customer-assigned trailer (soldToName is set instead).
const STOCK_LOCATIONS: { needle: RegExp; code: 'MULBERRY' | 'JACKSONVILLE' | 'ATLANTA' }[] = [
  { needle: /open stock mulberry|open stock mul\b/i, code: 'MULBERRY' },
  { needle: /open stock jacksonville/i, code: 'JACKSONVILLE' },
  { needle: /open stock georgia|atlanta/i, code: 'ATLANTA' },
];

// ─── Types for the extracted JSON ───────────────────────────────────────────
interface ExtractedRecord {
  file: string;
  soNumber: string;
  pdfModelCode: string | null;
  shipTo: string | null;
  date: string | null;
  lengthFt: string | null;
  gvwr: string | null;
  series: string | null;
  rawDescriptionHead: string;
}

interface PlannedTrailer {
  file: string;
  soNumber: string;
  modelCode: string;
  isStockBuild: boolean;
  stockLocationCode: 'MULBERRY' | 'JACKSONVILLE' | 'ATLANTA';
  soldToName: string | null;
  sizeFt: string | null;
  optionsNotes: string;
}

function planFromRecord(r: ExtractedRecord): PlannedTrailer {
  const ship = (r.shipTo ?? '').trim();
  const stockMatch = STOCK_LOCATIONS.find((s) => s.needle.test(ship));

  // "open mul" was the staging folder; trailers built there default to
  // Mulberry even when assigned to a customer — they sit in our yard until
  // pickup or delivery.
  const stockLocationCode: 'MULBERRY' | 'JACKSONVILLE' | 'ATLANTA' =
    stockMatch?.code ?? 'MULBERRY';
  const isStockBuild = !!stockMatch;
  const soldToName = stockMatch ? null : ship || null;

  const modelCode = MODEL_BY_PDF_CODE[r.pdfModelCode ?? ''];
  if (!modelCode) {
    throw new Error(`No model mapping for PDF code "${r.pdfModelCode}" (SO ${r.soNumber})`);
  }

  // Strip the boilerplate header and collapse whitespace so optionsNotes is
  // the trailer-specific spec block from the PDF.
  const desc = r.rawDescriptionHead
    .replace(/^.*?QTY\s*/i, '')
    .replace(/\s+/g, ' ')
    .trim();

  return {
    file: r.file,
    soNumber: r.soNumber,
    modelCode,
    isStockBuild,
    stockLocationCode,
    soldToName,
    // Store just the number; UI formats with `${size}ft` already.
    sizeFt: r.lengthFt ?? null,
    optionsNotes: desc.slice(0, 1500),
  };
}

// ─── Optional Spaces uploader ───────────────────────────────────────────────
interface SpacesUploader {
  upload(pdfFile: string, soNumber: string): Promise<string>;
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
    async upload(pdfFile: string, soNumber: string): Promise<string> {
      const bytes = readFileSync(join(PDF_DIR, pdfFile));
      const ext = 'pdf';
      const uuid = randomUUID();
      // Mirror the shape used by storage.service.ts: <prefix>/<soSlug>/<uuid>.<ext>
      const soSlug = soNumber.toLowerCase().replace(/[^a-z0-9-]/g, '-');
      const storageKey = `so-pdf/${soSlug}/${uuid}.${ext}`;
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
  console.log('🚛 Seeding open-stock packing-slip trailers (Mulberry batch)...\n');

  // ─── 1. Upsert the 3 new trailer models ────────────────────────────────────
  let modelsCreated = 0;
  let modelsExisted = 0;
  for (const m of NEW_MODELS) {
    const existing = await prisma.trailerModel.findUnique({
      where: { code: m.code },
      select: { id: true },
    });
    await prisma.trailerModel.upsert({
      where: { code: m.code },
      update: {},
      create: m,
    });
    if (existing) modelsExisted++;
    else modelsCreated++;
  }
  console.log(
    `✅ New trailer models: ${modelsCreated} created, ${modelsExisted} already present (${NEW_MODELS.length} total).\n`,
  );

  // ─── 2. Prerequisites ──────────────────────────────────────────────────────
  const locationsByCode: Record<string, { id: number; name: string }> = {};
  for (const code of ['MULBERRY', 'JACKSONVILLE', 'ATLANTA']) {
    const loc = await prisma.location.findUnique({
      where: { code },
      select: { id: true, name: true },
    });
    if (!loc) {
      throw new Error(`Location ${code} not found. Run the base seed first: npx tsx prisma/seed.ts`);
    }
    locationsByCode[code] = loc;
  }

  const creator =
    (await prisma.user.findFirst({ where: { role: 'owner' } })) ??
    (await prisma.user.findFirst());
  if (!creator) {
    throw new Error('No users found. Run the base seed first: npx tsx prisma/seed.ts');
  }

  const modelsByCode = new Map<string, number>();
  for (const m of await prisma.trailerModel.findMany({ select: { id: true, code: true } })) {
    modelsByCode.set(m.code, m.id);
  }

  // ─── 3. Load extracted PDF data + build planned trailers ───────────────────
  if (!existsSync(DATA_JSON)) {
    throw new Error(`Extracted records file missing: ${DATA_JSON}`);
  }
  const records: ExtractedRecord[] = JSON.parse(readFileSync(DATA_JSON, 'utf8'));
  const planned = records.map(planFromRecord);
  console.log(`📋 Planned ${planned.length} trailers from ${DATA_JSON}\n`);

  // ─── 4. Upload PDFs (only if Spaces creds are configured) ──────────────────
  const uploader = buildSpacesUploader();
  if (!uploader) {
    console.log(
      '⚠ Spaces creds not set (DO_SPACES_*) — skipping PDF upload. ' +
        'Trailers will be created without qbSoPdfStorageKey; re-run this seed in an environment with credentials to attach PDFs.\n',
    );
  } else if (!existsSync(PDF_DIR)) {
    console.log(`⚠ PDF source dir not found at ${PDF_DIR} — skipping PDF upload.\n`);
  }

  // ─── 5. Upsert trailers ────────────────────────────────────────────────────
  let trailersCreated = 0;
  let trailersUpdated = 0;
  let pdfsAttached = 0;
  let pdfsSkipped = 0;

  for (const p of planned) {
    const modelId = modelsByCode.get(p.modelCode);
    if (!modelId) {
      console.error(`  ✖ SO ${p.soNumber}: unknown model code ${p.modelCode}`);
      continue;
    }
    const locId = locationsByCode[p.stockLocationCode]!.id;

    const existing = await prisma.trailer.findUnique({
      where: { soNumber: p.soNumber },
      select: { id: true, qbSoPdfStorageKey: true },
    });

    const updateData: Record<string, unknown> = {
      trailerModelId: modelId,
      currentLocationId: locId,
      isStockBuild: p.isStockBuild,
      status: TrailerStatus.ready_for_delivery,
      optionsNotes: p.optionsNotes,
    };
    if (p.sizeFt) updateData['sizeFt'] = p.sizeFt;
    if (p.soldToName) updateData['soldToName'] = p.soldToName;

    const createData: Record<string, unknown> = {
      ...updateData,
      soNumber: p.soNumber,
      createdByUserId: creator.id,
    };

    const trailer = await prisma.trailer.upsert({
      where: { soNumber: p.soNumber },
      update: updateData,
      create: createData as never,
      select: { id: true, soNumber: true, qbSoPdfStorageKey: true },
    });
    if (existing) trailersUpdated++;
    else trailersCreated++;

    const tag = p.isStockBuild
      ? `stock@${p.stockLocationCode}`
      : `sold→"${p.soldToName}"`;
    console.log(`  ✅ ${trailer.soNumber}  →  ${p.modelCode}  [${tag}]`);

    // ─── Attach PDF if we have an uploader and the trailer doesn't already
    //     carry a storage key. Skipping when key is present keeps re-runs
    //     idempotent and avoids racking up duplicate Spaces objects.
    if (!uploader) {
      pdfsSkipped++;
      continue;
    }
    if (trailer.qbSoPdfStorageKey) {
      pdfsSkipped++;
      continue;
    }
    try {
      const storageKey = await uploader.upload(p.file, p.soNumber);
      await prisma.trailer.update({
        where: { id: trailer.id },
        data: { qbSoPdfStorageKey: storageKey, qbSoPdfStorageUrl: storageKey },
      });
      pdfsAttached++;
      console.log(`     ↳ PDF → ${storageKey.slice(-60)}`);
    } catch (e) {
      console.error(`     ✖ PDF upload failed: ${(e as Error).message}`);
    }
  }

  console.log(
    `\n🎉 Done. Trailers: ${trailersCreated} created, ${trailersUpdated} updated. PDFs: ${pdfsAttached} attached, ${pdfsSkipped} skipped.`,
  );
}

main()
  .catch((e) => {
    console.error('❌ open-mul seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
