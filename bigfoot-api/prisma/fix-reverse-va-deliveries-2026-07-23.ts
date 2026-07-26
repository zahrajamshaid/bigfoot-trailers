// =============================================================================
// BIGFOOT TRAILERS — One-shot: reverse the Virginia scheduled deliveries
//
// The owner asked to reverse all deliveries scheduled for Virginia
// (Tappahannock) and send the trailers back in the app. As of the yard count
// these were 8 stack-to-location deliveries in one building batch — none had
// departed, so nothing physically moved; the trailers just need to leave the
// delivery/transport view and return to the ready-to-ship pool at Mulberry.
//
// This mirrors the app's own batch-delete logic exactly (batches.service
// deleteBatch): drop dependent photos + location receipts, UNLINK sms logs
// (history is kept), delete the delivery rows, set each freed trailer back to
// ready_for_delivery, and remove any batch left empty. Every reversal writes an
// audit_log row so the history shows this was a hand correction.
//
// Keyed on destination = TAPPAHANNOCK + status = scheduled (not a hard-coded
// batch id), so it reverses exactly the right deliveries even if the batch
// composition differs, and never touches a delivery that has already departed
// or been delivered.
//
// Idempotent: re-running finds nothing to do once reversed.
// Run:  gh workflow run db-seed.yml -f script=fix-reverse-va-deliveries-2026-07-23
//   Preview first with:  ... -f script=... (set DRY_RUN=true in the workflow env)
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DRY_RUN = process.env['DRY_RUN'] === 'true';
const VA_CODE = 'TAPPAHANNOCK';

async function main(): Promise<void> {
  console.log(`↩️  Reversing Virginia scheduled deliveries${DRY_RUN ? ' (DRY RUN — nothing written)' : ''}\n`);

  const va = await prisma.location.findFirst({
    where: { code: VA_CODE },
    select: { id: true },
  });
  if (!va) {
    console.log(`  ⚠️  ${VA_CODE} location not found — nothing to do.`);
    return;
  }

  // Only scheduled deliveries — never reverse one that already departed/arrived.
  const deliveries = await prisma.delivery.findMany({
    where: { destinationLocationId: va.id, status: 'scheduled' },
    select: {
      id: true,
      trailerId: true,
      deliveryBatchId: true,
      trailer: { select: { soNumber: true, status: true } },
    },
  });

  if (deliveries.length === 0) {
    console.log('  ✓ No Virginia scheduled deliveries remain — already reversed.');
    return;
  }

  console.log(`  Found ${deliveries.length} scheduled Virginia delivery(ies):`);
  for (const d of deliveries) {
    console.log(`    → delivery ${d.id}  SO ${d.trailer.soNumber}  (trailer ${d.trailer.status})`);
  }
  console.log('');

  const deliveryIds = deliveries.map((d) => d.id);
  const trailerIds = [...new Set(deliveries.map((d) => d.trailerId))];
  const touchedBatchIds = [
    ...new Set(deliveries.map((d) => d.deliveryBatchId).filter((b): b is bigint => b != null)),
  ];

  if (DRY_RUN) {
    console.log(`  (dry run) would delete ${deliveryIds.length} delivery row(s), ` +
      `free ${trailerIds.length} trailer(s), and remove any of ${touchedBatchIds.length} batch(es) left empty.`);
    return;
  }

  await prisma.$transaction(async (tx) => {
    // Dependent rows — mirror the app's deleteBatch: photos + receipts go,
    // sms logs are history so they're unlinked, not deleted.
    await tx.deliveryPhoto.deleteMany({ where: { deliveryId: { in: deliveryIds } } });
    await tx.locationReceipt.deleteMany({ where: { deliveryId: { in: deliveryIds } } });
    await tx.smsLog.updateMany({
      where: { deliveryId: { in: deliveryIds } },
      data: { deliveryId: null },
    });
    await tx.delivery.deleteMany({ where: { id: { in: deliveryIds } } });

    // Free the trailers — back into the ready-to-ship pool.
    await tx.trailer.updateMany({
      where: { id: { in: trailerIds } },
      data: { status: 'ready_for_delivery' },
    });

    // Remove any batch that is now empty (the app deletes the batch on a full
    // batch-delete; here we only clean up ones we emptied).
    for (const batchId of touchedBatchIds) {
      const remaining = await tx.delivery.count({ where: { deliveryBatchId: batchId } });
      if (remaining === 0) {
        await tx.deliveryBatch.delete({ where: { id: batchId } });
        console.log(`  🗑️  batch ${batchId} emptied → removed`);
      } else {
        console.log(`  ↺ batch ${batchId} still has ${remaining} other delivery(ies) → kept`);
      }
    }

    // Audit trail — one row per trailer.
    for (const d of deliveries) {
      await tx.auditLog.create({
        data: {
          entityType: 'trailer',
          entityId: d.trailerId,
          action: 'delivery.reversed',
          oldValues: {
            deliveryId: Number(d.id),
            deliveryBatchId: d.deliveryBatchId != null ? Number(d.deliveryBatchId) : null,
            destination: VA_CODE,
          },
          newValues: {
            status: 'ready_for_delivery',
            note: 'Virginia delivery reversed at the owner\'s request; trailer sent back to the ready pool',
          },
        },
      });
    }
  });

  console.log(`\n🎉 Done. Reversed ${deliveryIds.length} Virginia delivery(ies); ${trailerIds.length} trailer(s) back in the ready pool.`);
}

main()
  .catch((e) => {
    console.error('❌ Reversal failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
