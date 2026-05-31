/* eslint-disable */
// Extracts trailer data from every PDF under
// prisma/data/production-queue-pdfs/<bucket>/<so>.pdf and writes
// prisma/data/production-queue-trailers.json.  Each record carries its
// bucket so the seed knows which workflow step the trailer should be
// dropped into (XP_JIG / XP_FIN / etc.).
//
// Run with: npx tsx scripts/extract-production-queue-trailers.ts

import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { PDFParse } = require('pdf-parse');

const ROOT =
  process.env['PRODUCTION_QUEUE_PDF_ROOT'] ??
  join(__dirname, '..', 'prisma', 'data', 'production-queue-pdfs');

// Folder name → series + starting step. The series tells the seed which
// 12-step workflow_template to instantiate; the startStepOrder picks which
// template step is the active one (everything before it is completed, after
// it is waiting).
//
// "gn-weld" lumps jig + finish PDFs into one bucket per the source folder
// "gn-dump jig and finish weld". Without sub-folder granularity we drop
// them in at the jig step; ops can advance whatever's already past jig.
interface BucketConfig {
  series: 'xp' | 'yeti' | 'deck_over' | 'gooseneck_dump';
  startStepOrder: number;
  startDeptCode: string; // for logging only
}
const BUCKETS: Record<string, BucketConfig> = {
  'xp-jig':   { series: 'xp',             startStepOrder: 1, startDeptCode: 'XP_JIG' },
  'xp-fin':   { series: 'xp',             startStepOrder: 3, startDeptCode: 'XP_FIN' },
  'yeti-jig': { series: 'yeti',           startStepOrder: 1, startDeptCode: 'YETI_JIG' },
  'yeti-fin': { series: 'yeti',           startStepOrder: 3, startDeptCode: 'YETI_FIN' },
  'do-jig':   { series: 'deck_over',      startStepOrder: 1, startDeptCode: 'DO_JIG' },
  'do-fin':   { series: 'deck_over',      startStepOrder: 3, startDeptCode: 'DO_FIN' },
  'gn-weld':  { series: 'gooseneck_dump', startStepOrder: 1, startDeptCode: 'GN_WELD' },
};

interface PdfRecord {
  bucket: string;
  series: BucketConfig['series'];
  startStepOrder: number;
  startDeptCode: string;
  file: string;
  soNumber: string;
  pdfModelCode: string | null;
  shipTo: string | null;
  date: string | null;
  lengthFt: string | null;
  rawDescriptionHead: string;
}

async function extract(bucket: string, file: string): Promise<PdfRecord> {
  const buf = readFileSync(join(ROOT, bucket, file));
  const { text } = await new PDFParse({ data: buf }).getText();
  const t: string = text ?? '';

  const soMatch = t.match(/Sales Order no\.\s*:\s*(\d+)/i);
  const dateMatch = t.match(/Date:\s*([\d/]+)/);
  const shipToMatch = t.match(/Ship to\s+([^\n]+)/i);

  const afterHeader = t.split(/QTY\s*/i)[1] ?? t;
  const codeMatch = afterHeader.match(/\b([0-9A-Z][0-9A-Z\-]{3,})\b/);
  const pdfModelCode = codeMatch ? codeMatch[1] : null;

  const lengthMatch = t.match(/LENGTH\s*:?\s*(\d+)\s*'?/i);

  const cfg = BUCKETS[bucket];
  return {
    bucket,
    series: cfg.series,
    startStepOrder: cfg.startStepOrder,
    startDeptCode: cfg.startDeptCode,
    file,
    soNumber: soMatch ? soMatch[1] : file.replace(/\.pdf$/i, ''),
    pdfModelCode,
    shipTo: shipToMatch ? shipToMatch[1].trim() : null,
    date: dateMatch ? dateMatch[1] : null,
    lengthFt: lengthMatch ? lengthMatch[1] : null,
    rawDescriptionHead: t.slice(0, 400).replace(/\s+/g, ' '),
  };
}

async function main(): Promise<void> {
  const folders = readdirSync(ROOT).filter((f) =>
    statSync(join(ROOT, f)).isDirectory(),
  );
  console.log(`Scanning ${folders.length} bucket folders under ${ROOT}\n`);

  const records: PdfRecord[] = [];
  for (const bucket of folders) {
    if (!BUCKETS[bucket]) {
      console.warn(`⚠ Folder "${bucket}" missing from BUCKETS — skipping`);
      continue;
    }
    const files = readdirSync(join(ROOT, bucket)).filter((f) =>
      f.toLowerCase().endsWith('.pdf'),
    );
    const cfg = BUCKETS[bucket];
    console.log(`=== ${bucket} → ${cfg.series} step ${cfg.startStepOrder} (${cfg.startDeptCode}) — ${files.length} PDFs ===`);
    for (const f of files) {
      try {
        const r = await extract(bucket, f);
        records.push(r);
        console.log(
          `  ${r.file.padEnd(10)} SO=${r.soNumber.padEnd(6)} code=${(r.pdfModelCode ?? '?').padEnd(14)}`,
        );
      } catch (e) {
        console.error(`  ✖ ${f}: ${(e as Error).message}`);
      }
    }
  }

  const codes = Array.from(
    new Set(records.map((r) => r.pdfModelCode).filter((c): c is string => !!c)),
  ).sort();
  console.log(`\nDistinct model codes (${codes.length}):`);
  for (const c of codes) console.log(`  ${c}`);

  const out = join(__dirname, '..', 'prisma', 'data', 'production-queue-trailers.json');
  writeFileSync(out, JSON.stringify(records, null, 2));
  console.log(`\nWrote ${records.length} records to ${out}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
