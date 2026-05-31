/* eslint-disable */
// Extracts trailer data from every packing-slip PDF under
// prisma/data/open-stock-pdfs/<location>/<so>.pdf and writes a single
// combined JSON file (prisma/data/open-stock-trailers.json) that the seed
// script reads. Each record carries its source-folder location code so the
// seed knows which yard to stock the trailer at.
//
// Run with:  npx tsx scripts/extract-pdf-trailers.ts

import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
// pdf-parse v2 exposes a PDFParse class; data is { data: Buffer }.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { PDFParse } = require('pdf-parse');

const ROOT =
  process.env['OPEN_STOCK_PDF_ROOT'] ??
  join(__dirname, '..', 'prisma', 'data', 'open-stock-pdfs');

// Subfolder name → DB location code. Must match a row in `locations.code`.
const FOLDER_TO_LOCATION_CODE: Record<string, string> = {
  mulberry: 'MULBERRY',
  jacksonville: 'JACKSONVILLE',
  atlanta: 'ATLANTA',
  tallahassee: 'TALLAHASSEE',
  tappahannock: 'TAPPAHANNOCK',
};

interface PdfRecord {
  locationCode: string; // DB code (MULBERRY etc.)
  folder: string; // raw subfolder name (mulberry, etc.)
  file: string; // e.g., "6720.pdf"
  soNumber: string;
  pdfModelCode: string | null;
  shipTo: string | null;
  date: string | null;
  lengthFt: string | null;
  gvwr: string | null;
  rawDescriptionHead: string;
}

async function extract(folder: string, file: string): Promise<PdfRecord> {
  const buf = readFileSync(join(ROOT, folder, file));
  const result = await new PDFParse({ data: buf }).getText();
  const text: string = result.text ?? '';

  const soMatch = text.match(/Sales Order no\.\s*:\s*(\d+)/i);
  const dateMatch = text.match(/Date:\s*([\d/]+)/);
  const shipToMatch = text.match(/Ship to\s*\n([^\n]+)/i);

  // The "Service" column word that sits immediately after the QTY header is
  // the model code. We scan for the first all-uppercase token of length ≥ 4
  // (digits + letters, hyphens allowed) after that header.
  const afterHeader = text.split(/QTY\s*/i)[1] ?? text;
  const codeMatch = afterHeader.match(/\b([0-9A-Z][0-9A-Z\-]{3,})\b/);
  const pdfModelCode = codeMatch ? codeMatch[1] : null;

  const lengthMatch = text.match(/LENGTH\s*:?\s*(\d+)\s*'?/i);
  const gvwrMatch = text.match(/GVWR\s*:?\s*([\d,]+)/i);

  return {
    locationCode: FOLDER_TO_LOCATION_CODE[folder] ?? folder.toUpperCase(),
    folder,
    file,
    soNumber: soMatch ? soMatch[1] : file.replace(/\.pdf$/i, ''),
    pdfModelCode,
    shipTo: shipToMatch ? shipToMatch[1].trim() : null,
    date: dateMatch ? dateMatch[1] : null,
    lengthFt: lengthMatch ? lengthMatch[1] : null,
    gvwr: gvwrMatch ? gvwrMatch[1] : null,
    rawDescriptionHead: text.slice(0, 500).replace(/\s+/g, ' '),
  };
}

async function main() {
  const folders = readdirSync(ROOT).filter((f) =>
    statSync(join(ROOT, f)).isDirectory(),
  );
  console.log(`Scanning ${folders.length} location folders under ${ROOT}\n`);

  const records: PdfRecord[] = [];
  for (const folder of folders) {
    if (!FOLDER_TO_LOCATION_CODE[folder]) {
      console.warn(
        `⚠ Folder "${folder}" has no FOLDER_TO_LOCATION_CODE mapping — skipping`,
      );
      continue;
    }
    const files = readdirSync(join(ROOT, folder)).filter((f) =>
      f.toLowerCase().endsWith('.pdf'),
    );
    console.log(`=== ${folder} (${files.length} PDFs) ===`);
    for (const f of files) {
      try {
        const r = await extract(folder, f);
        records.push(r);
        console.log(
          `  ${r.file.padEnd(10)} SO=${r.soNumber.padEnd(6)} code=${(r.pdfModelCode ?? '?').padEnd(14)} → ${r.locationCode}`,
        );
      } catch (e) {
        console.error(`  ✖ ${f}: ${(e as Error).message}`);
      }
    }
  }

  // Surface every distinct PDF model code so we can audit the mapping table
  // in the seed script before running it.
  const codes = Array.from(
    new Set(records.map((r) => r.pdfModelCode).filter((c): c is string => !!c)),
  ).sort();
  console.log(`\nDistinct PDF model codes (${codes.length}):`);
  for (const c of codes) console.log(`  ${c}`);

  const outPath = join(__dirname, '..', 'prisma', 'data', 'open-stock-trailers.json');
  writeFileSync(outPath, JSON.stringify(records, null, 2));
  console.log(`\nWrote ${records.length} records to ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
