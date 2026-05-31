/* eslint-disable */
// Extract trailer data from packing-slip PDFs in D:\BigFoot\all_trailers\open mul
// Writes a JSON file with one record per PDF for human review before import.

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
// pdf-parse v2.x exposes a PDFParse class. The constructor takes { data: Buffer }
// and .getText() returns { text } among other fields.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { PDFParse } = require('pdf-parse');

// Default to the repo-bundled copy of the PDFs. Override via OPEN_MUL_PDF_DIR
// when extracting from a fresh batch on disk.
const FOLDER =
  process.env['OPEN_MUL_PDF_DIR'] ??
  join(__dirname, '..', 'prisma', 'data', 'open-mul-pdfs');

interface PdfRecord {
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

function detectSeries(code: string | null, text: string): string | null {
  if (!code) return null;
  const upper = code.toUpperCase();
  if (upper.endsWith('YETI')) return 'yeti';
  if (upper.endsWith('XP')) return 'xp';
  if (upper.includes('DO') || /DECK\s*OVER/i.test(text)) return 'deck_over';
  if (upper.includes('GN') || /GOOSENECK|DUMP/i.test(text)) return 'gooseneck_dump';
  return null;
}

async function extract(file: string): Promise<PdfRecord> {
  const buf = readFileSync(join(FOLDER, file));
  const parser = new PDFParse({ data: buf });
  const result = await parser.getText();
  const text: string = result.text ?? '';

  // Sales Order no.: 6206
  const soMatch = text.match(/Sales Order no\.\s*:\s*(\d+)/i);
  // Date: 05/05/2026
  const dateMatch = text.match(/Date:\s*([\d/]+)/);
  // Ship to block — line after the "Ship to" label, before "Sales Order details"
  const shipToMatch = text.match(/Ship to\s*\n([^\n]+)/i);
  // Service column: model code is on the line just before the description starts
  // We look for an all-uppercase token containing digits (e.g. "14ET24XP" or "18ET20YETI")
  // immediately following the SERVICE/DESCRIPTION header. Simpler: grab the first
  // word that matches /^[\dA-Z]+$/ from the body after "QTY".
  const afterHeader = text.split(/QTY\s*/i)[1] ?? text;
  const codeMatch = afterHeader.match(/\b([0-9A-Z]{4,})\b/);
  const pdfModelCode = codeMatch ? codeMatch[1] : null;

  // LENGTH:24'  or  LENGTH: 24'
  const lengthMatch = text.match(/LENGTH\s*:?\s*(\d+)\s*'?/i);
  // GVWR: 14,000LBS  or  GVWR 17,900
  const gvwrMatch = text.match(/GVWR\s*:?\s*([\d,]+)/i);

  return {
    file,
    soNumber: soMatch ? soMatch[1] : file.replace(/\.pdf$/i, ''),
    pdfModelCode,
    shipTo: shipToMatch ? shipToMatch[1].trim() : null,
    date: dateMatch ? dateMatch[1] : null,
    lengthFt: lengthMatch ? lengthMatch[1] : null,
    gvwr: gvwrMatch ? gvwrMatch[1] : null,
    series: detectSeries(pdfModelCode, text),
    rawDescriptionHead: text.slice(0, 500).replace(/\s+/g, ' '),
  };
}

async function main() {
  const files = readdirSync(FOLDER).filter((f) => f.toLowerCase().endsWith('.pdf'));
  console.log(`Found ${files.length} PDFs`);
  const records: PdfRecord[] = [];
  for (const f of files) {
    try {
      const r = await extract(f);
      records.push(r);
      console.log(
        `${r.file.padEnd(10)}  SO=${r.soNumber.padEnd(6)}  code=${(r.pdfModelCode ?? '?').padEnd(14)}  series=${(r.series ?? '?').padEnd(15)}  L=${(r.lengthFt ?? '?').padEnd(3)}  GVWR=${(r.gvwr ?? '?').padEnd(8)}  ship=${r.shipTo}`,
      );
    } catch (e) {
      console.error(`FAIL ${f}: ${(e as Error).message}`);
    }
  }
  const outPath = join(__dirname, '..', 'prisma', 'data', 'open-mul-trailers.json');
  writeFileSync(outPath, JSON.stringify(records, null, 2));
  console.log(`\nWrote ${records.length} records to ${outPath}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
