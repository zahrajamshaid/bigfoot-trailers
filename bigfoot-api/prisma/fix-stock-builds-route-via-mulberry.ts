// =============================================================================
// BIGFOOT TRAILERS — One-shot: route in-flight stock builds via Mulberry
//
// Until 2026-06-15 the trailer-create flow set currentLocationId to the
// destination yard the moment a stock build was created. That made stock
// builds for satellite yards (JAX, VA, ATL, TAL) silently *not* appear in
// any inventory tile — they couldn't be in their destination yard yet
// (no completed delivery), and they couldn't be in Mulberry inventory
// because currentLocationId pointed away from it.
//
// Going forward, every stock build is born at the factory and the destination
// goes into the new intendedStockLocationId column. This script back-fills
// existing in-flight stock builds so the historical data matches the new
// invariant:
//
//   • Filter: is_stock_build=true AND status IN
//       (pending_production, in_production, ready_for_delivery)
//       AND current_location_id != MULBERRY
//       AND no delivered delivery exists for the trailer.
//   • Action: intended_stock_location_id := current_location_id (preserve
//     the destination intent), then current_location_id := MULBERRY.
//
// Skipped (intentionally):
//   • Stock builds that already have a completed delivery — those are
//     physically at the destination yard, leave them alone.
//   • Trailers with an open (scheduled / in_transit) delivery — moving them
//     mid-shipment would desync the driver's queue.
//   • Trailers already at Mulberry — nothing to do.
//
// Idempotent: re-running after the first pass finds nothing to migrate.
// =============================================================================

import 'dotenv/config';
import { DeliveryStatus, TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const IN_FLIGHT_STATUSES: TrailerStatus[] = [
  TrailerStatus.pending_production,
  TrailerStatus.in_production,
  TrailerStatus.ready_for_delivery,
];

async function hasOpenDelivery(trailerId: bigint): Promise<boolean> {
  const open = await prisma.delivery.count({
    where: {
      trailerId,
      status: { in: [DeliveryStatus.scheduled, DeliveryStatus.in_transit] },
    },
  });
  return open > 0;
}

async function main(): Promise<void> {
  console.log('🚚 Routing in-flight stock builds back through Mulberry\n');

  const mulberry = await prisma.location.findUnique({
    where: { code: 'MULBERRY' },
    select: { id: true },
  });
  if (!mulberry) {
    throw new Error('MULBERRY location not found — run the base seed first.');
  }

  // Candidates: in-flight stock builds not currently at Mulberry, with no
  // delivered delivery record. We pull them up-front so the run output gives
  // a complete picture even when we skip rows for open-delivery reasons.
  const candidates = await prisma.trailer.findMany({
    where: {
      isStockBuild: true,
      status: { in: IN_FLIGHT_STATUSES },
      currentLocationId: { not: mulberry.id },
      deliveries: { none: { status: DeliveryStatus.delivered } },
    },
    select: {
      id: true,
      soNumber: true,
      status: true,
      currentLocationId: true,
      intendedStockLocationId: true,
      currentLocation: { select: { code: true } },
    },
    orderBy: { soNumber: 'asc' },
  });

  console.log(`📋 ${candidates.length} candidate(s) to migrate:\n`);

  let migrated = 0;
  let alreadyOk = 0;
  let skippedOpenDelivery = 0;

  for (const t of candidates) {
    const fromCode = t.currentLocation?.code ?? `loc#${t.currentLocationId}`;
    if (await hasOpenDelivery(t.id)) {
      console.log(
        `  ${t.soNumber.padEnd(6)} → has open delivery (status=${t.status}, from=${fromCode}), skipping`,
      );
      skippedOpenDelivery++;
      continue;
    }

    // Preserve existing intent if it was set manually; otherwise stamp the
    // old current_location_id as the intent so transport still knows where
    // this trailer was earmarked.
    const nextIntent = t.intendedStockLocationId ?? t.currentLocationId;

    if (
      t.currentLocationId === mulberry.id &&
      t.intendedStockLocationId === nextIntent
    ) {
      alreadyOk++;
      continue;
    }

    console.log(
      `  ${t.soNumber.padEnd(6)} before → currentLocation=${fromCode}, intent=${t.intendedStockLocationId ?? 'null'}, status=${t.status}`,
    );

    await prisma.trailer.update({
      where: { id: t.id },
      data: {
        currentLocationId: mulberry.id,
        intendedStockLocationId: nextIntent,
      },
    });
    migrated++;

    console.log(
      `  ${t.soNumber.padEnd(6)} after  → currentLocation=MULBERRY, intent=loc#${nextIntent}`,
    );
  }

  console.log(
    `\n🎉 Done. Migrated ${migrated}, already-ok ${alreadyOk}, skipped-open-delivery ${skippedOpenDelivery}.`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
