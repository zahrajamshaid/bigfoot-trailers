// =============================================================================
// BIGFOOT TRAILERS — backfill: restore status on stock trailers stuck in
// ready_for_delivery after a sold → available revert.
//
// Same predicate as the inverse transition we just added to
// TrailersService.updateSaleStatus: status=ready_for_delivery, sale status
// is not sold, the most recent delivered Delivery landed at a stock
// location, and no newer live delivery (scheduled / in_transit / failed)
// exists. For each match, flip status → delivered so the trailer reads
// correctly in status-filtered lists.
//
// Idempotent: a second run finds nothing to update.
//
// Run with:
//   npx tsx prisma/backfill-stuck-stock-status.ts
// =============================================================================

import 'dotenv/config';
import {
  DeliveryStatus,
  TrailerSaleStatus,
  TrailerStatus,
} from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  const candidates = await prisma.trailer.findMany({
    where: {
      status: TrailerStatus.ready_for_delivery,
      saleStatus: { in: [TrailerSaleStatus.available, TrailerSaleStatus.sale_pending] },
    },
    select: { id: true, soNumber: true, saleStatus: true },
  });

  console.log(`Checking ${candidates.length} trailers in status=ready_for_delivery and saleStatus≠sold...\n`);

  let fixed = 0;
  let skippedNoStock = 0;
  let skippedLiveDelivery = 0;

  for (const t of candidates) {
    const lastDelivered = await prisma.delivery.findFirst({
      where: { trailerId: t.id, status: DeliveryStatus.delivered },
      orderBy: { deliveredAt: 'desc' },
      select: { id: true, deliveredAt: true, destinationLocationId: true },
    });
    if (lastDelivered?.destinationLocationId == null) {
      skippedNoStock++;
      continue;
    }

    const newerLive = await prisma.delivery.findFirst({
      where: {
        trailerId: t.id,
        status: {
          in: [
            DeliveryStatus.scheduled,
            DeliveryStatus.in_transit,
            DeliveryStatus.failed,
          ],
        },
        createdAt: { gt: lastDelivered.deliveredAt ?? new Date(0) },
      },
      select: { id: true },
    });
    if (newerLive) {
      skippedLiveDelivery++;
      continue;
    }

    await prisma.trailer.update({
      where: { id: t.id },
      data: { status: TrailerStatus.delivered },
    });
    fixed++;
    console.log(`  ✅ SO ${t.soNumber}: ready_for_delivery → delivered`);
  }

  console.log(
    `\n🎉 Done. fixed=${fixed} skipped (no prior stock delivery)=${skippedNoStock} skipped (live delivery exists)=${skippedLiveDelivery} total checked=${candidates.length}`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Backfill failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
