// =============================================================================
// BIGFOOT TRAILERS — Backfill trailer.qb_so_date from attached PDFs
//
// Scope: trailers currently `pending_production` or `in_production` with a
// qb_so_pdf_storage_key set. Skips rows that already have qb_so_date so
// re-runs are no-ops.
//
// For each matching trailer we download the PDF from DigitalOcean Spaces,
// pull the "Date: MM/DD/YYYY" field, and persist it as a DATE (no time).
//
// Requires DO_SPACES_* env vars (provided to the prod container via the
// existing env_file). Without them the script reports the count it would
// have processed and exits cleanly.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=backfill-qb-so-date
// =============================================================================

import 'dotenv/config';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { PDFParse } = require('pdf-parse');

const prisma = createPrismaClient();

function buildS3(): {
  client: S3Client;
  bucket: string;
} | null {
  const endpoint = process.env['DO_SPACES_ENDPOINT'];
  const accessKeyId = process.env['DO_SPACES_ACCESS_KEY'];
  const secretAccessKey = process.env['DO_SPACES_SECRET_KEY'];
  const bucket = process.env['DO_SPACES_BUCKET'];
  const region = process.env['DO_SPACES_REGION'] ?? 'us-east-1';
  if (!endpoint || !accessKeyId || !secretAccessKey || !bucket) return null;
  return {
    client: new S3Client({
      endpoint,
      region,
      credentials: { accessKeyId, secretAccessKey },
      forcePathStyle: false,
    }),
    bucket,
  };
}

async function streamToBuffer(stream: NodeJS.ReadableStream): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : (chunk as Buffer));
  }
  return Buffer.concat(chunks);
}

function parsePdfDate(text: string): Date | null {
  const m = text.match(/Date:\s*(\d{1,2})\/(\d{1,2})\/(\d{4})/i);
  if (!m) return null;
  const mm = Number(m[1]);
  const dd = Number(m[2]);
  const yyyy = Number(m[3]);
  if (!mm || !dd || !yyyy) return null;
  // Store as a UTC date at noon to dodge any timezone-edge midnight bugs
  // when @db.Date strips the time portion downstream.
  const d = new Date(Date.UTC(yyyy, mm - 1, dd, 12));
  return Number.isNaN(d.getTime()) ? null : d;
}

async function main(): Promise<void> {
  console.log('🩹 Backfilling trailers.qb_so_date from attached PDFs...\n');

  const s3 = buildS3();
  if (!s3) {
    console.error(
      '⚠ DO_SPACES_* env vars not set. Cannot download PDFs. Exiting.',
    );
    return;
  }

  const trailers = await prisma.trailer.findMany({
    where: {
      status: {
        in: [TrailerStatus.pending_production, TrailerStatus.in_production],
      },
      qbSoPdfStorageKey: { not: null },
      qbSoDate: null,
    },
    select: {
      id: true,
      soNumber: true,
      qbSoPdfStorageKey: true,
    },
  });
  console.log(`📋 ${trailers.length} trailer(s) eligible for backfill.\n`);

  let parsed = 0;
  let skipped = 0;
  let errors = 0;

  for (const t of trailers) {
    try {
      const obj = await s3.client.send(
        new GetObjectCommand({
          Bucket: s3.bucket,
          Key: t.qbSoPdfStorageKey!,
        }),
      );
      if (!obj.Body) {
        skipped++;
        console.log(`  ~ SO ${t.soNumber}: empty body — skipped`);
        continue;
      }
      const buf = await streamToBuffer(obj.Body as NodeJS.ReadableStream);
      const { text } = await new PDFParse({ data: buf }).getText();
      const date = parsePdfDate(text ?? '');
      if (!date) {
        skipped++;
        console.log(`  ~ SO ${t.soNumber}: no Date field in PDF — skipped`);
        continue;
      }
      await prisma.trailer.update({
        where: { id: t.id },
        data: { qbSoDate: date },
      });
      parsed++;
      console.log(
        `  + SO ${t.soNumber.padEnd(6)} → ${date.toISOString().slice(0, 10)}`,
      );
    } catch (e) {
      errors++;
      console.error(`  ✖ SO ${t.soNumber}: ${(e as Error).message}`);
    }
  }

  console.log(
    `\n🎉 Done. ${parsed} parsed, ${skipped} skipped, ${errors} errors.`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Backfill failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
