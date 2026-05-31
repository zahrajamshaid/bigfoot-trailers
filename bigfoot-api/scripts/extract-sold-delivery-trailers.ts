/* eslint-disable */
// Extracts trailer + customer data from every packing-slip PDF under
// prisma/data/sold-and-delivery-pdfs/<bucket>/<so>.pdf and writes a single
// combined JSON file (prisma/data/sold-and-delivery-trailers.json) for the
// seed to consume. Each record carries its "bucket" (folder name) so the
// seed knows whether it's a sold-pending-pickup row or a scheduled delivery,
// and which destination location / dealer applies.
//
// Run with:  npx tsx scripts/extract-sold-delivery-trailers.ts

import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { PDFParse } = require('pdf-parse');

const ROOT =
  process.env['SOLD_DELIVERY_PDF_ROOT'] ??
  join(__dirname, '..', 'prisma', 'data', 'sold-and-delivery-pdfs');

// Folder name → bucket descriptor.
//   kind: 'sold_pending' → trailer flagged sold + factory_pickup scheduled
//   kind: 'stack'        → stack_to_location scheduled, destination yard
//   kind: 'dealer'       → stack_to_dealer scheduled, customer (dealer) set
// `locationCode` is only meaningful for sold_pending (current yard) and
// stack (destination yard). `dealerName` is only meaningful for dealer.
type BucketKind = 'sold_pending' | 'stack' | 'dealer';
interface BucketConfig {
  kind: BucketKind;
  locationCode?: string;
  dealerName?: string;
}
const BUCKETS: Record<string, BucketConfig> = {
  'sold-pending-pickup-jax': { kind: 'sold_pending', locationCode: 'JACKSONVILLE' },
  'sold-pending-pickup-mul': { kind: 'sold_pending', locationCode: 'MULBERRY' },
  // "VA" in the folder name = our Virginia yard, which is the TAPPAHANNOCK
  // location in the DB.
  'sold-pending-pickup-va': { kind: 'sold_pending', locationCode: 'TAPPAHANNOCK' },
  'delivery-stack-to-atl': { kind: 'stack', locationCode: 'ATLANTA' },
  'delivery-stack-to-va': { kind: 'stack', locationCode: 'TAPPAHANNOCK' },
  'delivery-dealer-tropic': { kind: 'dealer', dealerName: 'Tropic Trailers' },
};

interface PdfRecord {
  bucket: string;
  kind: BucketKind;
  locationCode: string | null;
  dealerName: string | null;
  file: string;
  soNumber: string;
  pdfModelCode: string | null;
  // Multi-line "Ship to" block parsed into name + address lines.
  shipTo: string | null;
  shipToLines: string[];
  date: string | null;
  lengthFt: string | null;
  rawDescriptionHead: string;
}

// Pulls everything between "Ship to" and the next labeled section (Bill to /
// Shipping info / Sales Order details). The PDF rendering of the multi-line
// address tends to come back as a single whitespace-collapsed run.
function parseShipTo(text: string): { lines: string[]; raw: string | null } {
  const m = text.match(
    /Ship to\s+([\s\S]+?)(?=Bill to|Shipping info|Sales Order details|$)/i,
  );
  if (!m) return { lines: [], raw: null };
  const raw = m[1].replace(/\s+/g, ' ').trim();
  // Split common address punctuation (commas, double-spaces, USA) into rough
  // lines. The result isn't perfect but it's enough to detect customer-vs-
  // stock-yard ship-tos downstream.
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

  // Model code: first SKU-shaped token after QTY column header.
  const afterHeader = t.split(/QTY\s*/i)[1] ?? t;
  const codeMatch = afterHeader.match(/\b([0-9A-Z][0-9A-Z\-]{3,})\b/);
  const pdfModelCode = codeMatch ? codeMatch[1] : null;

  const ship = parseShipTo(t);
  const lengthMatch = t.match(/LENGTH\s*:?\s*(\d+)\s*'?/i);

  const cfg = BUCKETS[bucket];
  return {
    bucket,
    kind: cfg.kind,
    locationCode: cfg.locationCode ?? null,
    dealerName: cfg.dealerName ?? null,
    file,
    soNumber: soMatch ? soMatch[1] : file.replace(/\.pdf$/i, ''),
    pdfModelCode,
    shipTo: ship.raw,
    shipToLines: ship.lines,
    date: dateMatch ? dateMatch[1] : null,
    lengthFt: lengthMatch ? lengthMatch[1] : null,
    rawDescriptionHead: t.slice(0, 500).replace(/\s+/g, ' '),
  };
}

async function main() {
  const folders = readdirSync(ROOT).filter((f) =>
    statSync(join(ROOT, f)).isDirectory(),
  );
  console.log(`Scanning ${folders.length} bucket folders under ${ROOT}\n`);

  const records: PdfRecord[] = [];
  for (const bucket of folders) {
    if (!BUCKETS[bucket]) {
      console.warn(`⚠ Folder "${bucket}" not in BUCKETS map — skipping`);
      continue;
    }
    const files = readdirSync(join(ROOT, bucket)).filter((f) =>
      f.toLowerCase().endsWith('.pdf'),
    );
    const cfg = BUCKETS[bucket];
    const dest = cfg.dealerName ?? cfg.locationCode ?? '?';
    console.log(`=== ${bucket} → ${cfg.kind}/${dest} (${files.length} PDFs) ===`);
    for (const f of files) {
      try {
        const r = await extract(bucket, f);
        records.push(r);
        const shipPreview = (r.shipTo ?? '').slice(0, 50);
        console.log(
          `  ${r.file.padEnd(10)} SO=${r.soNumber.padEnd(6)} code=${(r.pdfModelCode ?? '?').padEnd(14)} shipTo="${shipPreview}"`,
        );
      } catch (e) {
        console.error(`  ✖ ${f}: ${(e as Error).message}`);
      }
    }
  }

  const codes = Array.from(
    new Set(records.map((r) => r.pdfModelCode).filter((c): c is string => !!c)),
  ).sort();
  console.log(`\nDistinct PDF model codes (${codes.length}):`);
  for (const c of codes) console.log(`  ${c}`);

  const outPath = join(
    __dirname,
    '..',
    'prisma',
    'data',
    'sold-and-delivery-trailers.json',
  );
  writeFileSync(outPath, JSON.stringify(records, null, 2));
  console.log(`\nWrote ${records.length} records to ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
