// =============================================================================
// BIGFOOT TRAILERS — Backfill destinationLocationId on ghost stack deliveries
//
// Some stack-to-yard deliveries were flipped to `delivered` without ever
// having their destinationLocationId set (and no customer address either).
// The stock-inventory endpoint reads destinationLocationId to group each
// trailer under its yard, and treats a NULL destinationLocationId as "this
// was delivered to a customer address, skip it." So these delivered-but-
// destination-less rows fall through both legs of the inventory query and
// their trailer becomes invisible in the yard tile.
//
// Detected on 2026-07-07 while reconciling the VA yard-report: SOs 6361,
// 6417, 6586, 6743 all had delivery rows delivered on 2026-06-22 with
// NULL destinationLocation. Fix is to backfill destination from the
// trailer's intended_stock_location (which is where the stack run was
// meant for) — that matches reality for the 6361/etc semi shipment and
// is the safest default for any future ghost deliveries in the same
// shape.
//
// Query criteria:
//   - delivery.status = 'delivered'
//   - delivery.destinationLocationId IS NULL
//   - delivery.customer_delivery_address IS NULL / empty
//   - trailer.isStockBuild = true
//   - trailer.status in (ready_for_delivery / pending_production / in_production)
//   - trailer.intended_stock_location_id IS NOT NULL (used as the fallback)
//
// Idempotent — every update guards on destinationLocationId === null so
// a re-run is a no-op.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-fix-delivered-null-destination
// =============================================================================

import 'dotenv/config';
import { DeliveryStatus, TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log(
    '🚛 Backfilling destinationLocationId on ghost stock stack deliveries...\n',
  );

  const targets = await prisma.delivery.findMany({
    where: {
      status: DeliveryStatus.delivered,
      destinationLocationId: null,
      // customer_delivery_address is stored as customerDeliveryAddress in
      // Prisma. Empty string or null both mean "no customer address" —
      // the delivery was a stack-to-yard, just missing its destination.
      OR: [
        { customerDeliveryAddress: null },
        { customerDeliveryAddress: '' },
      ],
      trailer: {
        isStockBuild: true,
        status: {
          in: [
            TrailerStatus.ready_for_delivery,
            TrailerStatus.pending_production,
            TrailerStatus.in_production,
          ],
        },
        intendedStockLocationId: { not: null },
      },
    },
    select: {
      id: true,
      trailer: {
        select: {
          id: true,
          soNumber: true,
          intendedStockLocationId: true,
          intendedStockLocation: { select: { code: true } },
        },
      },
    },
  });

  console.log(
    `Found ${targets.length} delivered deliveries with NULL destination.\n`,
  );

  let fixed = 0;
  for (const d of targets) {
    const intended = d.trailer.intendedStockLocationId;
    if (!intended) {
      console.warn(
        `  ! delivery ${d.id.toString()} (SO ${d.trailer.soNumber}) has no intended yard — skipping`,
      );
      continue;
    }
    await prisma.delivery.update({
      where: { id: d.id },
      data: { destinationLocationId: intended },
    });
    console.log(
      `  + delivery ${d.id.toString()} (SO ${d.trailer.soNumber}) → destination ${d.trailer.intendedStockLocation?.code ?? intended}`,
    );
    fixed++;
  }

  console.log(`\n✅ ${fixed} deliveries fixed.\n🎉 Done.`);
}

main()
  .catch((e) => {
    console.error('❌ Fix failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
