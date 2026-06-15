// =============================================================================
// BIGFOOT TRAILERS — One-shot: reconcile stuck delivery batches
//
// OPEN-BATCH-TROPIC (id 3) sat in the driver's view as status=scheduled even
// though every delivery inside had been marked delivered weeks ago. Root
// cause: the per-delivery completion path that DID call
// reconcileBatchCompletion was patched into deliveries.service later than
// these rows were written, so the batch's status never flipped.
//
// This script back-fills any batch where every delivery is in a terminal
// state (delivered or failed) but the batch itself hasn't been moved to
// `complete`. Each row's "before" state is logged so the run reads as an
// audit trail. Idempotent — re-running finds nothing to migrate.
// =============================================================================

import 'dotenv/config';
import { DeliveryBatchStatus, DeliveryStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🪢 Reconciling stuck delivery batches\n');

  // Pull every batch that hasn't reached `complete`. We compute the resolution
  // status per-batch so the run output explains exactly why each row was (or
  // wasn't) flipped.
  const candidates = await prisma.deliveryBatch.findMany({
    where: { status: { not: DeliveryBatchStatus.complete } },
    select: {
      id: true,
      batchNumber: true,
      status: true,
      _count: { select: { deliveries: true } },
    },
    orderBy: { createdAt: 'asc' },
  });

  console.log(`📋 ${candidates.length} non-complete batch(es) to inspect\n`);

  let flipped = 0;
  let leftAlone = 0;

  for (const b of candidates) {
    const open = await prisma.delivery.count({
      where: {
        deliveryBatchId: b.id,
        status: { in: [DeliveryStatus.scheduled, DeliveryStatus.in_transit] },
      },
    });
    const total = b._count.deliveries;

    if (total === 0) {
      console.log(
        `  ${b.batchNumber.padEnd(24)} → no deliveries, leaving as ${b.status}`,
      );
      leftAlone++;
      continue;
    }
    if (open > 0) {
      console.log(
        `  ${b.batchNumber.padEnd(24)} → ${open}/${total} still open, leaving as ${b.status}`,
      );
      leftAlone++;
      continue;
    }

    console.log(
      `  ${b.batchNumber.padEnd(24)} before → status=${b.status}, deliveries=${total} (all terminal)`,
    );
    await prisma.deliveryBatch.update({
      where: { id: b.id },
      data: {
        status: DeliveryBatchStatus.complete,
        completedAt: new Date(),
      },
    });
    flipped++;
    console.log(
      `  ${b.batchNumber.padEnd(24)} after  → status=complete, completedAt=now`,
    );
  }

  console.log(`\n🎉 Done. Flipped ${flipped}, left alone ${leftAlone}.`);
}

main()
  .catch((e) => {
    console.error('❌ Reconcile failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
