// =============================================================================
// BIGFOOT TRAILERS — Production-queue seed
//
// Drops 44 trailers into the active production line, starting at either the
// jig-weld (step 1) or finish-weld (step 3) of their series's 12-step
// workflow, based on the source PDF folder:
//
//   xp-jig    / yeti-jig    / do-jig    / gn-weld   → start at step 1 (jig)
//   xp-fin    / yeti-fin    / do-fin                → start at step 3 (finish)
//
// The trailer's catalog model determines which series workflow is used (so
// a TLT_18K, which is series=yeti, runs the yeti workflow even if its source
// folder was "xp finish" — the folder only carries the start-position hint).
// All steps before the start step are marked `completed` (with becameActiveAt
// / completedAt = now), the start step is `active`, the rest stay `waiting`.
//
// createdByUserId points at the owner account — these trailers were intended
// to be created by admin per the user's spec.
//
// Idempotent on so_number: existing trailers are skipped (we don't want to
// stomp production steps that have already moved forward).
//
// Run with: npx tsx prisma/seed-production-queue.ts
// =============================================================================

import 'dotenv/config';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import {
  ProductionStepStatus,
  TrailerSeries,
  TrailerStatus,
} from '@prisma/client';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DATA_JSON = join(__dirname, 'data', 'production-queue-trailers.json');
const PDF_ROOT =
  process.env['PRODUCTION_QUEUE_PDF_ROOT'] ??
  join(__dirname, 'data', 'production-queue-pdfs');

// PDF service code → trailer_model.code. Union of all 30 distinct codes
// surfaced in this batch + carryovers from prior batches so it's a single
// source of truth going forward.
const MODEL_BY_PDF_CODE: Record<string, string> = {
  // XP — 10K
  '10ET18XP': 'XP_10K',
  '10ET20XP': 'XP_10K',
  '10ET22XP': 'XP_10K',
  '10ET24XP': 'XP_10K',

  // XP — 14K (legacy ET-XP rung, kept consistent with prior batches)
  '14ET14XP': 'XP_14ET',
  '14ET16XP': 'XP_14ET',
  '14ET18XP': 'XP_14ET',
  '14ET20XP': 'XP_14ET',
  '14ET24XP': 'XP_14ET',

  // XP — 17K
  '17ET20XP': 'XP_17K',
  '17ET22': 'XP_17K',
  '17ET24': 'XP_17K',

  // YETI (15 / 18 / 21K)
  '15ET20YETI': 'YETI_15K',
  '15ET22YETI': 'YETI_15K',
  '18ET20YETI': 'YETI_18K',
  '18ET24YETI': 'YETI_18K',
  '21ET24YETI': 'YETI_21K',

  // Top Load Tilt (catalog series=yeti)
  '15ET20TLT': 'TLT_15K',
  '15TET24TLT': 'TLT_15K',
  '15TLT22': 'TLT_15K',
  '18ET20TLT': 'TLT_18K',
  '18ET24TLT': 'TLT_18K',
  '18TLT22': 'TLT_18K',
  '21ET24TLT': 'TLT_21K',

  // Deck Over (10 / 14 / 17 / 22 / 26K)
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

  // Goosenecks
  '22GN30': 'GN_22K',
  '26GN36-40': 'GN_26K',

  // Dumps
  '18DU16-2': 'DUMP_18K',
  '26DU20GN': 'DUMP_26K_GN',
};

interface PdfRecord {
  bucket: string;
  series: 'xp' | 'yeti' | 'deck_over' | 'gooseneck_dump';
  startStepOrder: number; // 1 (jig) or 3 (finish) per folder
  startDeptCode: string;
  file: string;
  soNumber: string;
  pdfModelCode: string | null;
  date: string | null;
  lengthFt: string | null;
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
  console.log('🛠  Seeding production-queue trailers...\n');

  // ─── 1. Prerequisites ──────────────────────────────────────────────────────
  const owner =
    (await prisma.user.findFirst({ where: { role: 'owner' } })) ??
    (await prisma.user.findFirst());
  if (!owner) throw new Error('No users in DB.');

  const mulberry = await prisma.location.findUnique({
    where: { code: 'MULBERRY' },
    select: { id: true, name: true },
  });
  if (!mulberry) throw new Error('Mulberry location missing — run base seed.');

  const modelsByCode = new Map<
    string,
    { id: number; series: TrailerSeries }
  >();
  for (const m of await prisma.trailerModel.findMany({
    select: { id: true, code: true, series: true },
  })) {
    modelsByCode.set(m.code, { id: m.id, series: m.series });
  }

  // ─── 2. Load records ───────────────────────────────────────────────────────
  if (!existsSync(DATA_JSON)) {
    throw new Error(
      `Missing ${DATA_JSON} — run: npx tsx scripts/extract-production-queue-trailers.ts`,
    );
  }
  const records: PdfRecord[] = JSON.parse(readFileSync(DATA_JSON, 'utf8'));
  console.log(`📋 Loaded ${records.length} records\n`);

  const uploader = buildSpacesUploader();
  if (!uploader) console.log('⚠ Spaces creds not set — skipping PDF upload.\n');

  // ─── 3. Process each record ────────────────────────────────────────────────
  let trailersCreated = 0;
  let trailersSkipped = 0;
  let stepsTotal = 0;
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
      console.error(`  ✖ SO ${r.soNumber}: model ${modelCode} missing.`);
      errors++;
      continue;
    }

    const existing = await prisma.trailer.findUnique({
      where: { soNumber: r.soNumber },
      select: { id: true, qbSoPdfStorageKey: true },
    });
    if (existing) {
      // Don't clobber a trailer that's already moving through the line.
      trailersSkipped++;
      console.log(
        `  = SO ${r.soNumber.padEnd(6)} ${modelCode.padEnd(13)} skipped (already exists)`,
      );
      continue;
    }

    // Use model.series for workflow lookup (not the folder's hinted series).
    // The folder only tells us where to drop in (jig vs finish step). A
    // TLT_18K placed in xp-fin still runs the yeti workflow because TLT is
    // catalog-classified yeti — the folder hint of "fin" just means "start
    // at step 3" of that workflow.
    const templates = await prisma.workflowTemplate.findMany({
      where: { series: model.series },
      orderBy: { stepOrder: 'asc' },
      include: { department: { select: { id: true, code: true } } },
    });
    if (templates.length !== 12) {
      console.error(
        `  ✖ SO ${r.soNumber}: expected 12 templates for series ${model.series}, found ${templates.length}`,
      );
      errors++;
      continue;
    }

    const startStep = Math.max(1, Math.min(12, r.startStepOrder));

    // Create trailer + 12 production_steps in one transaction. Trailer
    // status: pending_production when starting at jig (matches the existing
    // /trailers POST flow); in_production when dropping in mid-line.
    const { id: trailerId, soNumber } = await prisma.$transaction(async (tx) => {
      const trailer = await tx.trailer.create({
        data: {
          soNumber: r.soNumber,
          trailerModelId: model.id,
          currentLocationId: mulberry.id,
          status:
            startStep === 1
              ? TrailerStatus.pending_production
              : TrailerStatus.in_production,
          isStockBuild: true,
          createdByUserId: owner.id,
          ...(r.lengthFt ? { sizeFt: `${r.lengthFt}ft` } : {}),
        },
        select: { id: true, soNumber: true },
      });

      const now = new Date();
      for (const t of templates) {
        let status: ProductionStepStatus;
        let becameActiveAt: Date | null = null;
        let completedAt: Date | null = null;
        let queuePosition: number | null = null;

        if (t.stepOrder < startStep) {
          status = ProductionStepStatus.completed;
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
      return { id: trailer.id, soNumber: trailer.soNumber };
    });
    trailersCreated++;
    stepsTotal += 12;

    console.log(
      `  + SO ${soNumber.padEnd(6)} ${modelCode.padEnd(13)} ${model.series.padEnd(15)} start@step ${startStep} (${r.bucket})`,
    );

    // PDF upload
    if (!uploader) {
      pdfsSkipped++;
      continue;
    }
    const pdfPath = join(PDF_ROOT, r.bucket, r.file);
    if (!existsSync(pdfPath)) {
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

  console.log(
    `\n🎉 Done.\n` +
      `  Trailers: ${trailersCreated} created, ${trailersSkipped} skipped (existing)\n` +
      `  Steps:    ${stepsTotal} created (12 per new trailer)\n` +
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
