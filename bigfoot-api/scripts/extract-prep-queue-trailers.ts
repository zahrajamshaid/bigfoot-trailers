/* eslint-disable */
// Extracts trailer data from PDFs in prep workflow folders (wood, wire-hydro, prep)
// and writes prisma/data/prep-queue-trailers.json. Each record carries:
// - soNumber (matched to trailers.so_number)
// - folder (wood / wire-hydro / prep, determines starting step)
// - series (inferred from model code)
// - startStepOrder (11 for wood, 9 for wire-hydro, 5 for paint prep)
//
// Run with: npx tsx scripts/extract-prep-queue-trailers.ts

import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { PDFParse } = require('pdf-parse');

const ROOT = process.env['PREP_PDF_ROOT'] ?? join(__dirname, '..', '..', 'all_trailers');

// Prep-line folders → starting step + series (derived from model code)
const PREP_FOLDERS = [
  { name: 'wood', startStepOrder: 11, startDeptCode: 'WOOD' },
  { name: 'wire-hydro', startStepOrder: 9, startDeptCode: 'WIRE' },
  { name: 'prep', startStepOrder: 5, startDeptCode: 'PAINT_PREP' },
];

// PDF service code → series (same mapping as production-queue + prep additions)
const SERIES_BY_PDF_CODE: Record<string, string> = {
  // XP
  '10ET18XP': 'xp',
  '10ET20XP': 'xp',
  '10ET22XP': 'xp',
  '10ET24XP': 'xp',
  '14ET14XP': 'xp',
  '14ET16XP': 'xp',
  '14ET18XP': 'xp',
  '14ET20XP': 'xp',
  '14ET22XP': 'xp',
  '14ET24XP': 'xp',
  '17ET20XP': 'xp',
  '17ET22': 'xp',
  '17ET24': 'xp',
  
  // YETI / TLT
  '15ET20YETI': 'yeti',
  '15ET22YETI': 'yeti',
  '15ET24YETI': 'yeti',
  '18ET20YETI': 'yeti',
  '18ET24YETI': 'yeti',
  '21ET24YETI': 'yeti',
  '15ET20TLT': 'yeti',
  '15TET24TLT': 'yeti',
  '15TLT22': 'yeti',
  '18ET20TLT': 'yeti',
  '18ET24TLT': 'yeti',
  '18TLT22': 'yeti',
  '21ET24TLT': 'yeti',
  '21TLT26': 'yeti',
  
  // Deck Over
  '10DO24': 'deck_over',
  '14DO20': 'deck_over',
  '14DO20FLT': 'deck_over',
  '14DO24FLT': 'deck_over',
  '14DO25': 'deck_over',
  '14DO26FLT': 'deck_over',
  '17DO22': 'deck_over',
  '17DO25': 'deck_over',
  '17DO26': 'deck_over',
  '21DO25': 'deck_over',
  '22DO25': 'deck_over',
  '25DO30': 'deck_over',
  '25DO35': 'deck_over',
  
  // Gooseneck
  '22GN25': 'gooseneck_dump',
  '22GN30': 'gooseneck_dump',
  '26GN30': 'gooseneck_dump',
  '26GN32-40': 'gooseneck_dump',
  '26GN36-40': 'gooseneck_dump',
  
  // Dumps
  '18DU16-2': 'gooseneck_dump',
  '26DU20GN': 'gooseneck_dump',
};

interface PdfRecord {
  folder: string;
  file: string;
  soNumber: string;
  pdfModelCode: string | null;
  series: string | null;
  startStepOrder: number;
  startDeptCode: string;
  date: string | null;
  lengthFt: string | null;
}

async function extract(folder: string, file: string, startStepOrder: number, startDeptCode: string): Promise<PdfRecord> {
  const buf = readFileSync(join(ROOT, folder, file));
  const { text } = await new PDFParse({ data: buf }).getText();
  const t: string = text ?? '';

  const soMatch = t.match(/Sales Order no\.\s*:\s*(\d+)/i);
  const dateMatch = t.match(/Date:\s*([\d/]+)/);
  const lengthMatch = t.match(/LENGTH\s*:?\s*(\d+)\s*'?/i);

  const afterHeader = t.split(/QTY\s*/i)[1] ?? t;
  const codeMatch = afterHeader.match(/\b([0-9A-Z][0-9A-Z\-]{3,})\b/);
  const pdfModelCode = codeMatch ? codeMatch[1] : null;

  const series = pdfModelCode ? (SERIES_BY_PDF_CODE[pdfModelCode] ?? null) : null;

  return {
    folder,
    file,
    soNumber: soMatch ? soMatch[1] : file.replace(/\.pdf$/i, ''),
    pdfModelCode,
    series,
    startStepOrder,
    startDeptCode,
    date: dateMatch ? dateMatch[1] : null,
    lengthFt: lengthMatch ? lengthMatch[1] : null,
  };
}

async function main(): Promise<void> {
  console.log(`Extracting prep-queue trailers from ${PREP_FOLDERS.length} folders\n`);

  const records: PdfRecord[] = [];
  let totalFiles = 0;
  let totalExtracted = 0;
  let totalErrors = 0;
  const byFolder: Record<string, number> = {};

  for (const config of PREP_FOLDERS) {
    const folderPath = join(ROOT, config.name);
    if (!statSync(folderPath, { throwIfNoEntry: false })) {
      console.warn(`⚠ Folder "${config.name}" not found — skipping`);
      continue;
    }

    const files = readdirSync(folderPath).filter((f) => f.toLowerCase().endsWith('.pdf'));
    if (files.length === 0) {
      console.log(`${config.name}: 0 PDFs`);
      continue;
    }

    console.log(`${config.name}: ${files.length} PDFs (step ${config.startStepOrder} / ${config.startDeptCode})`);
    totalFiles += files.length;
    byFolder[config.name] = files.length;

    for (const f of files) {
      try {
        const r = await extract(config.name, f, config.startStepOrder, config.startDeptCode);
        records.push(r);
        totalExtracted++;
        console.log(
          `  ${r.file.padEnd(10)} SO=${r.soNumber.padEnd(6)} code=${(r.pdfModelCode ?? '?').padEnd(14)} series=${(r.series || '?').padEnd(10)}`,
        );
      } catch (e) {
        console.error(`  ✖ ${f}: ${(e as Error).message}`);
        totalErrors++;
      }
    }
  }

  console.log(`\n✅ Extracted ${totalExtracted}/${totalFiles} PDFs (${totalErrors} errors)`);
  const series = Array.from(new Set(records.map((r) => r.series).filter((s): s is string => !!s))).sort();
  console.log(`📊 Series: ${series.join(', ')}`);
  for (const [folder, count] of Object.entries(byFolder)) {
    console.log(`   ${folder}: ${count}`);
  }

  const out = join(__dirname, '..', 'prisma', 'data', 'prep-queue-trailers.json');
  writeFileSync(out, JSON.stringify(records, null, 2));
  console.log(`\n📝 Wrote ${records.length} records to ${out}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
