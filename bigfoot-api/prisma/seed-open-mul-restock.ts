// =============================================================================
// BIGFOOT TRAILERS — Restock the open-mul batch into Mulberry stock inventory
//
// Normalizes the 25 trailers seeded by `seed-open-mul.ts` so they all show up
// under "Mulberry — Open Stock" in the mobile/web Stock Inventory screen:
//   • isStockBuild = true, currentLocationId = MULBERRY
//   • status = delivered, saleStatus = available
//   • soldToName / customerId / optionsNotes / specialNote → null
//
// The Stock Inventory query is driven by the *latest delivered Delivery* per
// trailer (not the trailer's current_location column), so this script also
// creates a `stack_to_location` delivery to Mulberry with status=delivered
// when no such delivery already exists for that trailer.
//
// Idempotent: re-running won't duplicate deliveries (we check first) and the
// trailer updates are pure column writes.
//
// Run with:
//   npx tsx prisma/seed-open-mul-restock.ts
// =============================================================================

import 'dotenv/config';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import {
  DeliveryStatus,
  DeliveryType,
  TrailerSaleStatus,
  TrailerStatus,
} from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const DATA_JSON = join(__dirname, 'data', 'open-mul-trailers.json');
const TARGET_LOCATION_CODE = 'MULBERRY';

interface ExtractedRecord {
  soNumber: string;
  date: string | null; // "MM/DD/YYYY" from the PDF, e.g. "12/01/2025"
}

// "MM/DD/YYYY" → Date in UTC, or null if unparseable.
function parsePdfDate(s: string | null): Date | null {
  if (!s) return null;
  const m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!m) return null;
  const [, mm, dd, yyyy] = m;
  const d = new Date(Date.UTC(Number(yyyy), Number(mm) - 1, Number(dd), 12));
  return Number.isNaN(d.getTime()) ? null : d;
}

async function main(): Promise<void> {
  if (!existsSync(DATA_JSON)) {
    throw new Error(`Missing ${DATA_JSON} — run seed-open-mul.ts first.`);
  }
  const records: ExtractedRecord[] = JSON.parse(readFileSync(DATA_JSON, 'utf8'));
  console.log(`🚛 Restocking ${records.length} trailers into ${TARGET_LOCATION_CODE} stock inventory...\n`);

  const mulberry = await prisma.location.findUnique({
    where: { code: TARGET_LOCATION_CODE },
    select: { id: true, name: true },
  });
  if (!mulberry) {
    throw new Error(`Location ${TARGET_LOCATION_CODE} not found.`);
  }

  // Use the owner account as the "createdByUser" for the synthetic delivery
  // records — same convention as the catalog seed.
  const creator =
    (await prisma.user.findFirst({ where: { role: 'owner' } })) ??
    (await prisma.user.findFirst());
  if (!creator) {
    throw new Error('No users in DB — run the base seed first.');
  }

  let trailersUpdated = 0;
  let trailersMissing = 0;
  let deliveriesCreated = 0;
  let deliveriesSkipped = 0;

  for (const r of records) {
    const trailer = await prisma.trailer.findUnique({
      where: { soNumber: r.soNumber },
      select: { id: true, soNumber: true, qbSoPdfStorageKey: true },
    });
    if (!trailer) {
      console.error(`  ✖ SO ${r.soNumber}: trailer missing — skipping`);
      trailersMissing++;
      continue;
    }

    // 1. Normalize trailer columns. Notes blow away the long PDF spec block;
    //    customerId / soldToName clear any prior "sold" state.
    await prisma.trailer.update({
      where: { id: trailer.id },
      data: {
        isStockBuild: true,
        currentLocationId: mulberry.id,
        status: TrailerStatus.delivered,
        saleStatus: TrailerSaleStatus.available,
        customerId: null,
        customerLocked: false,
        soldToName: null,
        optionsNotes: null,
        specialNote: null,
      },
    });
    trailersUpdated++;

    // 2. Synthetic "delivered" Delivery to Mulberry — the Stock Inventory
    //    query keys off the latest delivered delivery, not the trailer's
    //    current_location_id. Idempotent: only create when there isn't
    //    already a delivered delivery for this trailer at Mulberry.
    const existing = await prisma.delivery.findFirst({
      where: {
        trailerId: trailer.id,
        status: DeliveryStatus.delivered,
        destinationLocationId: mulberry.id,
      },
      select: { id: true },
    });
    if (existing) {
      deliveriesSkipped++;
      console.log(`  ✅ SO ${trailer.soNumber}: trailer normalized; existing delivery kept`);
      continue;
    }

    const deliveredAt = parsePdfDate(r.date) ?? new Date();
    await prisma.delivery.create({
      data: {
        trailerId: trailer.id,
        deliveryType: DeliveryType.stack_to_location,
        destinationLocationId: mulberry.id,
        status: DeliveryStatus.delivered,
        deliveredAt,
        createdByUserId: creator.id,
      },
    });
    deliveriesCreated++;
    console.log(
      `  ✅ SO ${trailer.soNumber}: normalized + delivered@${deliveredAt
        .toISOString()
        .slice(0, 10)}`,
    );
  }

  console.log(
    `\n🎉 Done. Trailers updated: ${trailersUpdated}` +
      (trailersMissing ? ` (${trailersMissing} missing)` : '') +
      `. Deliveries: ${deliveriesCreated} created, ${deliveriesSkipped} already existed.`,
  );
  console.log(
    `\nVerify in the app:  Stock Inventory → ${mulberry.name} → expand the yard.`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Restock failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
