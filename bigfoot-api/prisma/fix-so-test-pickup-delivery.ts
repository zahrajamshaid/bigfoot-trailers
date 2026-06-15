// =============================================================================
// BIGFOOT TRAILERS — One-shot: insert missing pickup delivery for SO TEST
//
// Before the markCompleted patch landed, clicking "Mark Picked Up" on a
// trailer with no open delivery only flipped trailer.status to delivered.
// No deliveries row was written, so the completed-deliveries view showed
// just the prior leg (e.g. the single_pull / stack_to_location that put the
// trailer at the yard) and missed the pickup itself.
//
// SO TEST is the one trailer the operator flagged. It has:
//   • exactly one delivered delivery (the inbound leg)
//   • trailer.status = delivered
//   • trailer.updated_at > the inbound delivery's deliveredAt (i.e. the
//     trailer was marked delivered separately, after the inbound leg)
//
// We back-fill a factory_pickup row dated trailer.updated_at so the operator
// sees both events. Going forward, markCompleted creates this row itself —
// this script is just for the one historical case the user pointed out.
//
// Idempotent: skips if a pickup row already exists for this trailer.
// =============================================================================

import 'dotenv/config';
import { DeliveryStatus, DeliveryType } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const TARGET_SO = 'TEST';

async function main(): Promise<void> {
  console.log(`📦 Back-filling pickup delivery for SO ${TARGET_SO}\n`);

  const trailer = await prisma.trailer.findUnique({
    where: { soNumber: TARGET_SO },
    select: {
      id: true,
      soNumber: true,
      status: true,
      createdByUserId: true,
      updatedAt: true,
    },
  });

  if (!trailer) {
    console.log(`  Trailer ${TARGET_SO} not found, skipping`);
    return;
  }

  // Already has a factory_pickup? Don't double up.
  const existingPickup = await prisma.delivery.findFirst({
    where: {
      trailerId: trailer.id,
      deliveryType: DeliveryType.factory_pickup,
    },
    select: { id: true, status: true },
  });
  if (existingPickup) {
    console.log(
      `  Pickup delivery #${existingPickup.id} (status=${existingPickup.status}) already exists, leaving alone`,
    );
    return;
  }

  console.log(
    `  Trailer ${TARGET_SO} state → status=${trailer.status}, updatedAt=${trailer.updatedAt.toISOString()}`,
  );

  const created = await prisma.delivery.create({
    data: {
      trailerId: trailer.id,
      deliveryType: DeliveryType.factory_pickup,
      status: DeliveryStatus.delivered,
      deliveredAt: trailer.updatedAt,
      createdByUserId: trailer.createdByUserId,
    },
    select: { id: true },
  });

  console.log(
    `  ✅ Inserted factory_pickup delivery #${created.id}, deliveredAt=${trailer.updatedAt.toISOString()}`,
  );
  console.log('\n🎉 Done. Both legs now show in Completed Deliveries.');
}

main()
  .catch((e) => {
    console.error('❌ Back-fill failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
