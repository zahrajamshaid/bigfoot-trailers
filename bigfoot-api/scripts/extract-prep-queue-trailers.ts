/* eslint-disable */
// Extracts trailer data from prisma/data/prep-queue-pdfs/<bucket>/<so>.pdf
// and writes prisma/data/prep-queue-trailers.json. Bucket maps to:
//   wood        → production workflow step 11 (WOOD)
//   wire-hydro  → step 9 (WIRE for xp/yeti/do; HYDRAULICS for gooseneck_dump
//                  — the workflow_template per-series handles the dept split)
//   paint-prep  → step 5 (PAINT_PREP)
//   enclosed-mul/-va → no workflow; ENCLOSED inventory model at MUL / TAP
//
// PDFs live under prisma/data so they ship inside the docker image — the
// prod runner can't reach D:\BigFoot\all_trailers.
//
// Run: npx tsx scripts/extract-prep-queue-trailers.ts

import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { PDFParse } = require('pdf-parse');

const ROOT =
  process.env['PREP_QUEUE_PDF_ROOT'] ??
  join(__dirname, '..', 'prisma', 'data', 'prep-queue-pdfs');

interface BucketConfig {
  kind: 'workflow' | 'inventory';
  startStepOrder?: number;
  startDeptHint?: string;
  locationCode?: string;
}
const BUCKETS: Record<string, BucketConfig> = {
  wood: { kind: 'workflow', startStepOrder: 11, startDeptHint: 'WOOD' },
  'wire-hydro': {
    kind: 'workflow',
    startStepOrder: 9,
    startDeptHint: 'WIRE/HYDRAULICS',
  },
  'paint-prep': {
    kind: 'workflow',
    startStepOrder: 5,
    startDeptHint: 'PAINT_PREP',
  },
  'enclosed-mul': { kind: 'inventory', locationCode: 'MULBERRY' },
  'enclosed-va': { kind: 'inventory', locationCode: 'TAPPAHANNOCK' },
};

interface PdfRecord {
  bucket: string;
  kind: BucketConfig['kind'];
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
  rawDescriptionHead: string;
}

function parseShipTo(text: string): { lines: string[]; raw: string | null } {
  const m = text.match(
    /Ship to\s+([\s\S]+?)(?=Bill to|Shipping info|Sales Order details|$)/i,
  );
  if (!m) return { lines: [], raw: null };
  const raw = m[1].replace(/\s+/g, ' ').trim();
  const lines = raw
    .split(/,| {2,}/)
    .map((s) => s.trim())
    .filter(Boolean);
  return { lines, raw };
}

async function extract(bucket: string, file: string): Promise<PdfRecord> {
  const buf = readFileSync(join(ROOT, bucket, file));
  const { text } = await new PDFParse({ data: buf }).getText();
  const t: string = text ?? '';

  const soMatch = t.match(/Sales Order no\.\s*:\s*(\d+)/i);
  const dateMatch = t.match(/Date:\s*([\d/]+)/);
  const afterHeader = t.split(/QTY\s*/i)[1] ?? t;
  const codeMatch = afterHeader.match(/\b([0-9A-Z][0-9A-Z\-]{3,})\b/);
  const pdfModelCode = codeMatch ? codeMatch[1] : null;

  const ship = parseShipTo(t);
  const lengthMatch = t.match(/LENGTH\s*:?\s*(\d+)\s*'?/i);
  const cfg = BUCKETS[bucket];

  return {
    bucket,
    kind: cfg.kind,
    startStepOrder: cfg.startStepOrder ?? null,
    startDeptHint: cfg.startDeptHint ?? null,
    locationCode: cfg.locationCode ?? null,
    file,
    soNumber: soMatch ? soMatch[1] : file.replace(/\.pdf$/i, ''),
    pdfModelCode,
    shipTo: ship.raw,
    shipToLines: ship.lines,
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
      console.warn(`⚠ "${bucket}" missing from BUCKETS — skipping`);
      continue;
    }
    const files = readdirSync(join(ROOT, bucket)).filter((f) =>
      f.toLowerCase().endsWith('.pdf'),
    );
    const cfg = BUCKETS[bucket];
    const desc =
      cfg.kind === 'workflow'
        ? `step ${cfg.startStepOrder} (${cfg.startDeptHint})`
        : `inventory @ ${cfg.locationCode}`;
    console.log(`=== ${bucket} → ${desc} — ${files.length} PDFs ===`);
    for (const f of files) {
      try {
        const r = await extract(bucket, f);
        records.push(r);
        const ship = (r.shipTo ?? '').slice(0, 45);
        console.log(
          `  ${r.file.padEnd(10)} SO=${r.soNumber.padEnd(6)} code=${(r.pdfModelCode ?? '?').padEnd(14)} ship="${ship}"`,
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

  const out = join(
    __dirname,
    '..',
    'prisma',
    'data',
    'prep-queue-trailers.json',
  );
  writeFileSync(out, JSON.stringify(records, null, 2));
  console.log(`\nWrote ${records.length} records to ${out}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
