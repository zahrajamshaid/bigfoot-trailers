// =============================================================================
// BIGFOOT TRAILERS — Backfill trailer.qb_so_date from seeded JSON
//
// Scope: trailers currently `pending_production` or `in_production` with
// qb_so_date still null. Every such trailer was created from one of our
// PDF-extracted JSON files (production-queue, prep-queue, etc.), each of
// which already carries the Date: field parsed off the source PDF.
//
// We avoid running pdf-parse in prod (it's a devDependency that isn't
// bundled into the runtime image). Instead we read every prisma/data/
// *trailers*.json shipped inside the docker image, build a soNumber →
// date map, and persist the dates straight in.
//
// Idempotent: rows that already have a qbSoDate are skipped.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=backfill-qb-so-date
// =============================================================================

import 'dotenv/config';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const DATA_DIR = join(__dirname, 'data');

interface JsonRow {
  soNumber?: string;
  date?: string | null;
}

// "MM/DD/YYYY" → UTC noon. UTC-noon dodges any timezone-edge midnight bug
// when @db.Date strips the time portion downstream.
function parsePdfDate(s: string | null | undefined): Date | null {
  if (!s) return null;
  const m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!m) return null;
  const [, mm, dd, yyyy] = m;
  const d = new Date(Date.UTC(Number(yyyy), Number(mm) - 1, Number(dd), 12));
  return Number.isNaN(d.getTime()) ? null : d;
}

function loadDatesFromJsonFiles(): Map<string, Date> {
  const dateBySo = new Map<string, Date>();
  const files = readdirSync(DATA_DIR).filter(
    (f) => f.endsWith('-trailers.json'),
  );
  for (const f of files) {
    const fp = join(DATA_DIR, f);
    if (!statSync(fp).isFile()) continue;
    try {
      const rows = JSON.parse(readFileSync(fp, 'utf8')) as JsonRow[];
      let kept = 0;
      for (const r of rows) {
        if (!r.soNumber) continue;
        const d = parsePdfDate(r.date ?? null);
        if (!d) continue;
        // First-write wins. We process the production-line JSONs first by
        // sort order, which is what we want — those are the SOs we care
        // about backfilling.
        if (!dateBySo.has(r.soNumber)) {
          dateBySo.set(r.soNumber, d);
          kept++;
        }
      }
      console.log(`  ${f.padEnd(40)} → ${kept} date(s)`);
    } catch (e) {
      console.error(`  ✖ ${f}: ${(e as Error).message}`);
    }
  }
  return dateBySo;
}

async function main(): Promise<void> {
  console.log('🩹 Backfilling trailers.qb_so_date from seeded JSON files...\n');

  const dateBySo = loadDatesFromJsonFiles();
  console.log(`\n📦 Built date lookup for ${dateBySo.size} SO(s).\n`);

  const trailers = await prisma.trailer.findMany({
    where: {
      status: {
        in: [TrailerStatus.pending_production, TrailerStatus.in_production],
      },
      qbSoDate: null,
    },
    select: { id: true, soNumber: true },
  });
  console.log(`📋 ${trailers.length} trailer(s) eligible for backfill.\n`);

  let updated = 0;
  let skipped = 0;

  for (const t of trailers) {
    const d = dateBySo.get(t.soNumber);
    if (!d) {
      skipped++;
      continue;
    }
    await prisma.trailer.update({
      where: { id: t.id },
      data: { qbSoDate: d },
    });
    updated++;
    console.log(
      `  + SO ${t.soNumber.padEnd(6)} → ${d.toISOString().slice(0, 10)}`,
    );
  }

  console.log(
    `\n🎉 Done. ${updated} updated, ${skipped} skipped (no date in any JSON).`,
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
