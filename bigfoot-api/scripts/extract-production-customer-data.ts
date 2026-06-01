/* eslint-disable */
// Extracts customer data from PDFs in production folders (XP Jig, XP finish,
// yeti jig, yeti finish, DO jig, DO finish, gn-dump jig and finish weld) and
// writes prisma/data/production-customer-data.json. Each record carries:
// - soNumber (matched to trailers.so_number)
// - customerName (from "Ship to" line or "Bill to")
// - isStockBuild (detected from ship-to text)
// - sellingLocation (inferred from ship-to address)
//
// Run with: npx tsx scripts/extract-production-customer-data.ts

import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { PDFParse } = require('pdf-parse');

const ROOT = process.env['PRODUCTION_PDF_ROOT'] ?? join(__dirname, '..', '..', 'all_trailers');

// Production-line folders — extract customer data from all of them
const PRODUCTION_FOLDERS = [
  'XP Jig',
  'XP finish',
  'yeti jig',
  'yeti finish',
  'DO jig',
  'DO finish',
  'gn-dump jig and finish weld',
];

// Stock location keywords
const STOCK_LOCATION_KEYWORDS: { needle: RegExp; code: string }[] = [
  { needle: /mulberry/i, code: 'MULBERRY' },
  { needle: /jacksonville/i, code: 'JACKSONVILLE' },
  { needle: /atlanta|georgia/i, code: 'ATLANTA' },
  { needle: /(\w+\s+\w+\s+)?TAL\b|tal\b/i, code: 'TAL' },
  { needle: /VA\b|virginia/i, code: 'VA' },
];

interface CustomerRecord {
  folder: string;
  file: string;
  soNumber: string;
  customerName: string | null;
  billTo: string | null;
  shipTo: string | null;
  isStockBuild: boolean;
  sellingLocation: string | null;
  date: string | null;
  rawText: string;
}

function detectStockBuild(shipTo: string | null): boolean {
  if (!shipTo) return false;
  return /open stock|stock|inventory/i.test(shipTo);
}

function detectSellingLocation(shipTo: string | null): string | null {
  if (!shipTo) return null;
  for (const { needle, code } of STOCK_LOCATION_KEYWORDS) {
    if (needle.test(shipTo)) return code;
  }
  return null;
}

function extractCustomerName(text: string): {
  billTo: string | null;
  shipTo: string | null;
} {
  const billToMatch = text.match(/Bill\s+to\s+([^\n]+)/i);
  const shipToMatch = text.match(/Ship\s+to\s+([^\n]+)/i);
  return {
    billTo: billToMatch ? billToMatch[1].trim() : null,
    shipTo: shipToMatch ? shipToMatch[1].trim() : null,
  };
}

async function extract(folder: string, file: string): Promise<CustomerRecord> {
  const buf = readFileSync(join(ROOT, folder, file));
  const { text } = await new PDFParse({ data: buf }).getText();
  const t: string = text ?? '';

  const soMatch = t.match(/Sales Order no\.\s*:\s*(\d+)/i);
  const dateMatch = t.match(/Date:\s*([\d/]+)/);

  const { billTo, shipTo } = extractCustomerName(t);
  const customerName = shipTo || billTo;

  const isStockBuild = detectStockBuild(shipTo);
  const sellingLocation = detectSellingLocation(shipTo);

  return {
    folder,
    file,
    soNumber: soMatch ? soMatch[1] : file.replace(/\.pdf$/i, ''),
    customerName,
    billTo,
    shipTo,
    isStockBuild,
    sellingLocation,
    date: dateMatch ? dateMatch[1] : null,
    rawText: t.slice(0, 300).replace(/\s+/g, ' '),
  };
}

async function main(): Promise<void> {
  console.log(`Extracting customer data from ${PRODUCTION_FOLDERS.length} production folders\n`);

  const records: CustomerRecord[] = [];
  let totalFiles = 0;
  let totalExtracted = 0;
  let totalErrors = 0;

  for (const folder of PRODUCTION_FOLDERS) {
    const folderPath = join(ROOT, folder);
    if (!statSync(folderPath, { throwIfNoEntry: false })) {
      console.warn(`⚠ Folder "${folder}" not found — skipping`);
      continue;
    }

    const files = readdirSync(folderPath).filter((f) => f.toLowerCase().endsWith('.pdf'));
    if (files.length === 0) {
      console.log(`${folder}: 0 PDFs`);
      continue;
    }

    console.log(`${folder}: ${files.length} PDFs`);
    totalFiles += files.length;

    for (const f of files) {
      try {
        const r = await extract(folder, f);
        records.push(r);
        totalExtracted++;
        console.log(
          `  ${r.file.padEnd(10)} SO=${r.soNumber.padEnd(6)} stock=${r.isStockBuild ? 'Y' : 'N'} loc=${(r.sellingLocation || 'ORDER').padEnd(10)} cust=${(r.customerName ? r.customerName.slice(0, 20) : '?').padEnd(20)}`,
        );
      } catch (e) {
        console.error(`  ✖ ${f}: ${(e as Error).message}`);
        totalErrors++;
      }
    }
  }

  console.log(`\n✅ Extracted ${totalExtracted}/${totalFiles} PDFs (${totalErrors} errors)`);
  console.log(`📊 Stock builds: ${records.filter((r) => r.isStockBuild).length}`);
  console.log(
    `📊 Order builds: ${records.filter((r) => !r.isStockBuild).length}`,
  );

  const out = join(__dirname, '..', 'prisma', 'data', 'production-customer-data.json');
  writeFileSync(out, JSON.stringify(records, null, 2));
  console.log(`\n📝 Wrote ${records.length} records to ${out}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
