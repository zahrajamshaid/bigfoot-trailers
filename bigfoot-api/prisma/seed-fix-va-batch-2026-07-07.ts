// =============================================================================
// BIGFOOT TRAILERS — 2026-07-07 batch: unstick 7 workflows + reconcile VA
//
// Two operator asks, one script:
//
//  A) Trailers whose physical build is done but the app is still holding
//     open production_steps. Close every remaining step and flip the
//     trailer to ready_for_delivery. 6768 has no steps at all (inventory-
//     only trailer, currently `delivered`) — just flip its status back
//     to ready_for_delivery so it shows up for customer pickup.
//
//       6924  workflow steps → complete, status → ready_for_delivery
//       6859  workflow steps → complete, status → ready_for_delivery
//       6860  workflow steps → complete, status → ready_for_delivery
//       6659  workflow steps → complete, status → ready_for_delivery
//       6742  workflow steps → complete, status → ready_for_delivery
//       6779  workflow steps → complete, status → ready_for_delivery
//       6869  workflow steps → complete, status → ready_for_delivery
//       6768  0 steps, status delivered → ready_for_delivery
//
//  B) Trailers physically at VA that the app doesn't reflect yet from the
//     last-week stack shipment. Most are already correct; the two
//     outliers get fixed here:
//
//       6862  currentLocation MULBERRY → TAPPAHANNOCK. Also completes
//             ghost delivery #284 (scheduled with every field NULL) into
//             a delivered stack-to-VA record so the delivery history is
//             clean and inventory tile groups it under TAPPAHANNOCK via
//             leg 1.
//       6781  status delivered → ready_for_delivery. Sale was cleared
//             mid-reconciliation; the leftover delivered status was
//             hiding the trailer from the VA inventory tile.
//
// Idempotent — every update guards on the current state, so a re-run
// only touches rows that still need touching.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-fix-va-batch-2026-07-07
// =============================================================================

import 'dotenv/config';
import {
  DeliveryStatus,
  ProductionStepStatus,
  TrailerStatus,
} from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

// Workflow-stuck trailers where remaining production_steps need closing.
const COMPLETE_AND_READY = [
  '6924',
  '6859',
  '6860',
  '6659',
  '6742',
  '6779',
  '6869',
];
// Trailer with no workflow (inventory-only) that just needs the status
// flipped back to ready_for_delivery.
const READY_ONLY = ['6768'];

async function closeStepsAndReady(so: string, now: Date): Promise<boolean> {
  const t = await prisma.trailer.findFirst({
    where: { soNumber: so },
    select: { id: true, status: true, soNumber: true },
  });
  if (!t) {
    console.warn(`  ! SO ${so} not found`);
    return false;
  }
  const openSteps = await prisma.productionStep.findMany({
    where: {
      trailerId: t.id,
      status: { not: ProductionStepStatus.complete },
    },
    select: { id: true, stepOrder: true, becameActiveAt: true },
  });
  for (const step of openSteps) {
    await prisma.productionStep.update({
      where: { id: step.id },
      data: {
        status: ProductionStepStatus.complete,
        // Keep the original becameActiveAt if the step ever went active;
        // otherwise fall back to now so downstream reports have something
        // sensible rather than NULL.
        becameActiveAt: step.becameActiveAt ?? now,
        completedAt: now,
      },
    });
  }
  const flipped =
    t.status !== TrailerStatus.ready_for_delivery
      ? await prisma.trailer.update({
          where: { id: t.id },
          data: { status: TrailerStatus.ready_for_delivery },
          select: { id: true },
        })
      : null;
  console.log(
    `  + SO ${so}: closed ${openSteps.length} step(s)${flipped ? ', status → ready_for_delivery' : ' (status already ready)'}`,
  );
  return true;
}

async function flipStatusReady(so: string): Promise<boolean> {
  const t = await prisma.trailer.findFirst({
    where: { soNumber: so },
    select: { id: true, status: true },
  });
  if (!t) {
    console.warn(`  ! SO ${so} not found`);
    return false;
  }
  if (t.status === TrailerStatus.ready_for_delivery) {
    console.log(`  = SO ${so} already ready — no-op`);
    return false;
  }
  await prisma.trailer.update({
    where: { id: t.id },
    data: { status: TrailerStatus.ready_for_delivery },
  });
  console.log(`  + SO ${so}: status ${t.status} → ready_for_delivery`);
  return true;
}

async function main(): Promise<void> {
  console.log('🚛 2026-07-07 VA batch: 7 workflow unsticks + VA reconciles...\n');

  const va = await prisma.location.findFirst({
    where: { code: 'TAPPAHANNOCK' },
    select: { id: true, name: true },
  });
  if (!va) throw new Error('TAPPAHANNOCK location not seeded');

  const now = new Date();

  console.log('── Batch A: workflow stuck ─────────────────────────────');
  for (const so of COMPLETE_AND_READY) {
    await closeStepsAndReady(so, now);
  }
  for (const so of READY_ONLY) {
    await flipStatusReady(so);
  }

  console.log('\n── Batch B: VA reconciles ─────────────────────────────');
  // 6862 — move to VA + fix ghost delivery #284
  {
    const t = await prisma.trailer.findFirst({
      where: { soNumber: '6862' },
      select: {
        id: true,
        currentLocationId: true,
      },
    });
    if (!t) console.warn('  ! SO 6862 not found');
    else {
      if (t.currentLocationId !== va.id) {
        await prisma.trailer.update({
          where: { id: t.id },
          data: { currentLocation: { connect: { id: va.id } } },
        });
        console.log('  + SO 6862: currentLocation → TAPPAHANNOCK');
      } else {
        console.log('  = SO 6862 already at TAPPAHANNOCK');
      }
      // Ghost delivery #284: scheduled with every field NULL. Turn it into
      // a delivered stack-to-VA record so the delivery-history is honest
      // and the inventory tile groups 6862 via leg 1.
      const ghost = await prisma.delivery.findFirst({
        where: {
          trailerId: t.id,
          status: DeliveryStatus.scheduled,
          destinationLocationId: null,
        },
        select: { id: true },
      });
      if (ghost) {
        await prisma.delivery.update({
          where: { id: ghost.id },
          data: {
            status: DeliveryStatus.delivered,
            destinationLocationId: va.id,
            deliveredAt: now,
          },
        });
        console.log(
          `  + delivery #${ghost.id.toString()} (SO 6862): scheduled+null → delivered @ TAPPAHANNOCK`,
        );
      } else {
        console.log('  = SO 6862 has no ghost scheduled delivery');
      }
    }
  }

  // 6781 — status delivered → ready
  await flipStatusReady('6781');

  console.log('\n🎉 Done.');
}

main()
  .catch((e) => {
    console.error('❌ Fix failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
