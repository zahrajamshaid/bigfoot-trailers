// =============================================================================
// BIGFOOT TRAILERS — One-shot: revert pre-dispatch batches to `building`
//
// The currently-deployed mobile builds only show the "Edit" button on
// delivery batches whose status is exactly `building`. Some batches in
// prod were manually advanced past that, which silently hid the edit
// affordance on every operator's phone.
//
// This flips eligible batches back to `building` so the Edit button
// reappears against the existing app, without forcing testers to install
// a new build. The backend's edit gate (batches.service.ts update) already
// accepts both `building` and `scheduled`, so the revert is a no-op from
// the API's perspective.
//
// Strict guard rails:
//   • Audits every batch by status first (visible in the workflow log) so
//     you can see exactly what was found before any writes happen.
//   • Touches any non-`building` batch IFF every delivery on it is still
//     `scheduled`. `in_transit` and `complete` batches always have at
//     least one dispatched/delivered/failed delivery, so they are
//     automatically left alone — flipping them would silently let an
//     operator re-add trailers to work that's already moved.
//
// Idempotent: re-running after the revert is a no-op.
// =============================================================================

import 'dotenv/config';
import { DeliveryBatchStatus, DeliveryStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log(
    '🔄 Reverting eligible batches → building so the deployed app shows Edit\n',
  );

  // ── Audit pass — print one line per current status so the run log shows
  //    exactly what the production data looks like before we touch it. ──
  const grouped = await prisma.deliveryBatch.groupBy({
    by: ['status'],
    _count: { _all: true },
  });
  console.log('📊 Current batch status histogram:');
  for (const g of grouped) {
    console.log(`   ${g.status.padEnd(12)} ${g._count._all}`);
  }
  console.log('');

  // ── Candidates: every batch NOT already at building. The per-delivery
  //    safety check below excludes any batch that has actually departed. ──
  const candidates = await prisma.deliveryBatch.findMany({
    where: { status: { not: DeliveryBatchStatus.building } },
    select: {
      id: true,
      batchNumber: true,
      status: true,
      deliveries: { select: { id: true, status: true } },
    },
    orderBy: { id: 'asc' },
  });

  console.log(
    `📋 Inspecting ${candidates.length} batch(es) not at status=building.\n`,
  );

  let reverted = 0;
  let skippedDispatched = 0;

  for (const b of candidates) {
    const hasInFlight = b.deliveries.some(
      (d) => d.status !== DeliveryStatus.scheduled,
    );
    if (hasInFlight) {
      skippedDispatched++;
      const offending = b.deliveries
        .filter((d) => d.status !== DeliveryStatus.scheduled)
        .map((d) => `${d.id}:${d.status}`)
        .join(', ');
      console.log(
        `  ${b.batchNumber.padEnd(20)} (${b.status.padEnd(10)}) → skipped (deliveries already dispatched: ${offending})`,
      );
      continue;
    }

    await prisma.deliveryBatch.update({
      where: { id: b.id },
      data: { status: DeliveryBatchStatus.building },
    });
    reverted++;
    console.log(
      `  ${b.batchNumber.padEnd(20)} (${b.status.padEnd(10)}) → building`,
    );
  }

  console.log(
    `\n🎉 Done. ${reverted} reverted, ${skippedDispatched} skipped (already past dispatch).`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Batch revert failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
