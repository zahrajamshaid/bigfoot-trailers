// =============================================================================
// BIGFOOT TRAILERS — Backfill sizeFt on in-inventory trailers
//
// Scope: trailers that have a delivered Delivery landing them at a stock
// yard but no sizeFt on the trailer row. The inventory cards render the
// length from trailer.size_ft, so without it the card just shows the
// model name and the delivered date.
//
// Source of truth: the prisma/data/*-trailers.json files we seeded from
// the original PDFs. Each row carries a lengthFt extracted at seed time.
// Walking those files gives us the SO → length map without having to
// re-download PDFs from Spaces or run pdf-parse in prod.
//
// Idempotent: only touches rows where sizeFt is currently null.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=backfill-inventory-size-ft
// =============================================================================

import 'dotenv/config';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { DeliveryStatus, TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const DATA_DIR = join(__dirname, 'data');

interface JsonRow {
  soNumber?: string;
  lengthFt?: string | number | null;
  pdfModelCode?: string | null;
  rawDescriptionHead?: string | null;
}

/// PDF service codes carry the length as digits sandwiched between letter
/// runs (15TLT22, 21ET24YETI, 14DO20) or as the second factor in a WxL
/// utility code (7X16TA2, U5X10S140, E8X2414K). Pull the most likely
/// length figure when the JSON's explicit lengthFt is missing.
function lengthFromModelCode(code: string | null | undefined): string | null {
  if (!code) return null;
  const s = code.trim();
  if (!s) return null;
  // 7X16 / 8X24 / U6X12 / E7X20 — width × length format.
  const wxl = s.match(/^[UEL]?(\d{1,2})X(\d{2})/i);
  if (wxl) return wxl[2];
  // Trailer codes: 21ET24YETI / 15TLT22 / 14DO20 / 17DO25 / 21ET26 …
  // We want the digits AFTER the alpha cluster in the middle. The width
  // is the leading digits; the inner digits are the length.
  const ml = s.match(/^\d{2,3}[A-Z]+(\d{2})/i);
  if (ml) return ml[1];
  // Fall-through for codes like "GOOSENECK" or "MISC" that carry no length.
  return null;
}

/// Strip stray quote / `'` characters and lone trailing "ft" so the row
/// renders cleanly under the existing `${size}ft` template.
function normaliseLength(value: string | number): string | null {
  let s = String(value).trim();
  if (!s) return null;
  s = s.replace(/['"]/g, '');
  s = s.replace(/ft\s*$/i, '');
  s = s.trim();
  return s || null;
}

function loadLengthsFromJsonFiles(): Map<string, string> {
  const lengthBySo = new Map<string, string>();
  const files = readdirSync(DATA_DIR).filter(
    (f) => f.endsWith('-trailers.json'),
  );
  for (const f of files) {
    const fp = join(DATA_DIR, f);
    if (!statSync(fp).isFile()) continue;
    try {
      const rows = JSON.parse(readFileSync(fp, 'utf8')) as JsonRow[];
      let kept = 0;
      let fromExplicit = 0;
      let fromCode = 0;
      for (const r of rows) {
        if (!r.soNumber) continue;
        let len: string | null = null;
        if (r.lengthFt !== null && r.lengthFt !== undefined) {
          len = normaliseLength(r.lengthFt);
          if (len) fromExplicit++;
        }
        if (!len) {
          len = lengthFromModelCode(r.pdfModelCode);
          if (len) fromCode++;
        }
        if (!len) continue;
        // First-write wins so production-line JSONs (which came directly
        // from the PDF) take priority over later derived files.
        if (!lengthBySo.has(r.soNumber)) {
          lengthBySo.set(r.soNumber, len);
          kept++;
        }
      }
      console.log(
        `  ${f.padEnd(40)} → ${kept} length(s) (${fromExplicit} explicit, ${fromCode} from code)`,
      );
    } catch (e) {
      console.error(`  ✖ ${f}: ${(e as Error).message}`);
    }
  }
  return lengthBySo;
}

async function main(): Promise<void> {
  console.log('📏 Backfilling sizeFt on in-inventory trailers from seeded JSON...\n');

  const lengthBySo = loadLengthsFromJsonFiles();
  console.log(`\n📦 Built length lookup for ${lengthBySo.size} SO(s).\n`);

  // In-inventory predicate: trailer status reads as "at a yard" AND the
  // latest delivered Delivery is to a Location (matches the
  // /deliveries/stock-inventory query).
  const trailers = await prisma.trailer.findMany({
    where: {
      sizeFt: null,
      status: {
        in: [
          TrailerStatus.delivered,
          TrailerStatus.ready_for_delivery,
          TrailerStatus.on_hold,
        ],
      },
      deliveries: {
        some: {
          status: DeliveryStatus.delivered,
          destinationLocationId: { not: null },
        },
      },
    },
    select: { id: true, soNumber: true },
  });
  console.log(`📋 ${trailers.length} in-inventory trailer(s) without sizeFt.\n`);

  let updated = 0;
  let skipped = 0;
  for (const t of trailers) {
    const len = lengthBySo.get(t.soNumber);
    if (!len) {
      skipped++;
      continue;
    }
    await prisma.trailer.update({
      where: { id: t.id },
      data: { sizeFt: len },
    });
    updated++;
    console.log(`  + SO ${t.soNumber.padEnd(6)} → ${len}ft`);
  }

  console.log(
    `\n🎉 Done. ${updated} updated, ${skipped} skipped (no length in any JSON).`,
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
