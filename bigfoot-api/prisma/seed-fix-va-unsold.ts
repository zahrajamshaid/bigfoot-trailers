// =============================================================================
// BIGFOOT TRAILERS — Revert 3 VA trailers back to open stock
//
// Operator says the buyers on 6875 / 6911 / 6781 were placeholders /
// wrong — none of them are actually sold. They should be open stock at
// Virginia (TAPPAHANNOCK), available for sale to a real buyer.
//
//   6875  XP_10K  — was sold to Joe Halterman at MULBERRY.
//                    Move to TAPPAHANNOCK + clear sale.
//   6911  XP_14K  — was sold to "A and R Septic Brett" at TAPPAHANNOCK.
//                    Clear sale, stay at VA.
//   6781  XP_17K  — was sold to Russell Barb at TAPPAHANNOCK.
//                    Clear sale, stay at VA.
//
// "Clear sale" means: saleStatus → available, soldToName → null,
// customer disconnect, soldAt → null so a future re-sale gets a fresh
// timestamp (matches the trailers.service.updateSaleStatus semantics).
// Status stays ready_for_delivery so they surface on the VA inventory
// tile (the seed-fix-va-reconcile-2 semantics: open stock at a yard is
// ready_for_delivery so it's movable between yards).
//
// Idempotent — guards on the current saleStatus / currentLocationId so
// a re-run is a no-op.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-fix-va-unsold
// =============================================================================

import 'dotenv/config';
import { Prisma, TrailerSaleStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

interface UnsellTarget {
  soNumber: string;
  moveToVa: boolean;
}

const TARGETS: UnsellTarget[] = [
  { soNumber: '6875', moveToVa: true },
  { soNumber: '6911', moveToVa: false },
  { soNumber: '6781', moveToVa: false },
];

async function main(): Promise<void> {
  console.log('🚛 Reverting 3 VA trailers back to open stock...\n');

  const va = await prisma.location.findFirst({
    where: { code: 'TAPPAHANNOCK' },
    select: { id: true, name: true },
  });
  if (!va) throw new Error('TAPPAHANNOCK location not seeded');

  let fixed = 0;
  let skipped = 0;
  for (const target of TARGETS) {
    const t = await prisma.trailer.findFirst({
      where: { soNumber: target.soNumber },
      select: {
        id: true,
        saleStatus: true,
        soldToName: true,
        soldAt: true,
        customerId: true,
        currentLocationId: true,
      },
    });
    if (!t) {
      console.warn(`  ! SO ${target.soNumber} not found`);
      continue;
    }
    const alreadyAvailable = t.saleStatus === TrailerSaleStatus.available;
    const alreadyAtVa = t.currentLocationId === va.id;
    if (alreadyAvailable && (!target.moveToVa || alreadyAtVa)) {
      console.log(`  = SO ${target.soNumber} already open stock at right yard — no-op`);
      skipped++;
      continue;
    }

    const data: Prisma.TrailerUpdateInput = {};
    if (!alreadyAvailable) {
      data.saleStatus = TrailerSaleStatus.available;
      data.soldToName = null;
      data.soldAt = null;
      if (t.customerId !== null) {
        data.customer = { disconnect: true };
      }
    }
    if (target.moveToVa && !alreadyAtVa) {
      data.currentLocation = { connect: { id: va.id } };
    }

    await prisma.trailer.update({
      where: { id: t.id },
      data,
    });
    const parts: string[] = [];
    if (!alreadyAvailable) {
      parts.push(
        `saleStatus ${t.saleStatus} → available (cleared "${t.soldToName ?? t.customerId}")`,
      );
    }
    if (target.moveToVa && !alreadyAtVa) {
      parts.push(`location ${t.currentLocationId} → ${va.name}`);
    }
    console.log(`  + SO ${target.soNumber}: ${parts.join('; ')}`);
    fixed++;
  }

  console.log(`\n✅ ${fixed} unsold, ${skipped} already correct.\n🎉 Done.`);
}

main()
  .catch((e) => {
    console.error('❌ Fix failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
