// =============================================================================
// BIGFOOT TRAILERS — Production-customer data seed
//
// Updates trailers in production (those already created by
// seed-production-queue.ts) with customer name and stock/order build flags
// extracted from their QB packing slips.
//
// For each SO:
// - If stock build (detected from "Open Stock" in ship-to), sets isStockBuild=true
//   and currentLocationId to the inferred yard (Mulberry, Jacksonville, etc.)
// - If customer order, sets soldToName = customer company name and saleStatus = 'sold'
//
// Idempotent: uses so_number as the key. Re-running updates existing trailers
// but skips those with customerLocked=true (to preserve manual overrides).
//
// Run with: npx tsx prisma/seed-production-customer-data.ts
// =============================================================================

import 'dotenv/config';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { TrailerSaleStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DATA_JSON = join(__dirname, 'data', 'production-customer-data.json');

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

async function main(): Promise<void> {
  console.log('🛠  Updating production trailers with customer data...\n');

  // ─── 1. Prerequisites ──────────────────────────────────────────────────────
  if (!existsSync(DATA_JSON)) {
    throw new Error(
      `Missing ${DATA_JSON} — run: npx tsx scripts/extract-production-customer-data.ts`,
    );
  }

  const records: CustomerRecord[] = JSON.parse(readFileSync(DATA_JSON, 'utf8'));
  console.log(`📋 Loaded ${records.length} records\n`);

  // Build a location map: code → id
  const locationsByCode = new Map<string, number>();
  for (const loc of await prisma.location.findMany({ select: { id: true, code: true } })) {
    locationsByCode.set(loc.code, loc.id);
  }

  // ─── 2. Process each record ────────────────────────────────────────────────
  let updated = 0;
  let skipped = 0;
  let errors = 0;

  for (const r of records) {
    try {
      const trailer = await prisma.trailer.findUnique({
        where: { soNumber: r.soNumber },
        select: {
          id: true,
          customerLocked: true,
          isStockBuild: true,
          soldToName: true,
          currentLocationId: true,
        },
      });

      if (!trailer) {
        console.warn(`  ⊘ SO ${r.soNumber}: trailer not found (may not be in production)`);
        skipped++;
        continue;
      }

      // Skip if customer was manually locked
      if (trailer.customerLocked) {
        console.log(`  ⊙ SO ${r.soNumber}: customerLocked=true — skipping`);
        skipped++;
        continue;
      }

      // Prepare update
      const updateData: any = {};

      if (r.isStockBuild && r.sellingLocation) {
        // Stock build: set isStockBuild and move to yard location
        const locationId = locationsByCode.get(r.sellingLocation);
        if (locationId) {
          updateData.isStockBuild = true;
          updateData.currentLocationId = locationId;
          console.log(
            `  ✓ SO ${r.soNumber}: stock build → ${r.sellingLocation}`,
          );
        } else {
          console.warn(
            `  ⚠ SO ${r.soNumber}: stock location "${r.sellingLocation}" not found in DB`,
          );
        }
      } else if (r.customerName && !r.isStockBuild) {
        // Customer order: set soldToName and mark as sold
        updateData.soldToName = r.customerName;
        updateData.saleStatus = TrailerSaleStatus.sold;
        console.log(
          `  ✓ SO ${r.soNumber}: order → ${r.customerName.slice(0, 40)} (SOLD)`,
        );
      } else {
        console.log(`  ○ SO ${r.soNumber}: no update needed`);
        skipped++;
        continue;
      }

      // Apply update
      await prisma.trailer.update({
        where: { id: trailer.id },
        data: updateData,
      });
      updated++;
    } catch (e) {
      console.error(
        `  ✖ SO ${r.soNumber}: ${(e as Error).message}`,
      );
      errors++;
    }
  }

  console.log(`\n🎉 Done.`);
  console.log(`  Trailers: ${updated} updated, ${skipped} skipped (not found / locked)`);
  if (errors > 0) console.log(`  Errors:   ${errors}`);
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
