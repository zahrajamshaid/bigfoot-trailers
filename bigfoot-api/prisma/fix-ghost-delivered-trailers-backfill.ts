// =============================================================================
// BIGFOOT TRAILERS — One-shot: back-fill missing delivery rows for ghost
// "delivered" trailers
//
// A handful of trailers (SO 6715, 6373, 6738, …) sit at a yard with
// trailer.status=delivered + saleStatus=sold but no rows in the deliveries
// table — they predate the proper delivery flow or were imported / edited
// directly. They're effectively ghosts:
//   • not in Stock Inventory   (leg 1 needs a delivered delivery row)
//   • not in Completed Deliveries (no delivery rows at all)
//   • only findable via the Trailers screen with the Delivered chip on
//
// This script inserts the legs each trailer must have taken so the history
// is on record:
//   • At a satellite yard (JAX / TAP / ATL / TAL): two rows —
//       1. stack_to_location MUL → yard   (deliveredAt = trailer.createdAt)
//       2. factory_pickup                  (deliveredAt = trailer.updatedAt)
//   • At Mulberry: one row —
//       1. factory_pickup                  (deliveredAt = trailer.updatedAt)
//     (no stack_to_location needed — the customer came to the factory)
//
// Each delivery row carries the trailer's createdByUserId. Trailer state
// itself is untouched.
//
// Idempotent: a trailer with any existing delivery row is left alone.
// =============================================================================

import 'dotenv/config';
import { DeliveryStatus, DeliveryType } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('📦 Back-filling missing delivery rows for ghost "delivered" trailers\n');

  const ghosts = await prisma.trailer.findMany({
    where: {
      status: 'delivered',
      saleStatus: 'sold',
      deliveries: { none: {} },
    },
    select: {
      id: true,
      soNumber: true,
      createdAt: true,
      updatedAt: true,
      createdByUserId: true,
      currentLocationId: true,
      currentLocation: { select: { code: true, isFactory: true } },
    },
    orderBy: { soNumber: 'asc' },
  });

  console.log(`📋 ${ghosts.length} ghost trailer(s) to back-fill\n`);

  let oneLeg = 0;
  let twoLeg = 0;

  for (const t of ghosts) {
    const isAtFactory = t.currentLocation?.isFactory === true;
    const yardCode = t.currentLocation?.code ?? `loc#${t.currentLocationId}`;

    if (!isAtFactory) {
      // Inbound leg (only when the trailer ended up at a satellite yard).
      const inbound = await prisma.delivery.create({
        data: {
          trailerId: t.id,
          deliveryType: DeliveryType.stack_to_location,
          status: DeliveryStatus.delivered,
          destinationLocationId: t.currentLocationId,
          deliveredAt: t.createdAt,
          createdByUserId: t.createdByUserId,
        },
        select: { id: true },
      });
      console.log(
        `  ${t.soNumber.padEnd(8)} → stack_to_location #${inbound.id} → ${yardCode}, deliveredAt=${t.createdAt.toISOString()}`,
      );
      twoLeg++;
    } else {
      oneLeg++;
    }

    // Pickup leg — every ghost gets one. deliveredAt = updatedAt is the best
    // available proxy for the actual pickup time on the legacy rows.
    const pickup = await prisma.delivery.create({
      data: {
        trailerId: t.id,
        deliveryType: DeliveryType.factory_pickup,
        status: DeliveryStatus.delivered,
        deliveredAt: t.updatedAt,
        createdByUserId: t.createdByUserId,
      },
      select: { id: true },
    });
    console.log(
      `  ${t.soNumber.padEnd(8)} → factory_pickup    #${pickup.id} at ${yardCode}, deliveredAt=${t.updatedAt.toISOString()}`,
    );
  }

  console.log(
    `\n🎉 Done. ${twoLeg} two-leg back-fill(s) (satellite yards) + ${oneLeg} single-leg (Mulberry pickup).`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Back-fill failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
