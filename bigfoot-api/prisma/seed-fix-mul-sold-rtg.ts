// =============================================================================
// BIGFOOT TRAILERS — 2026-07-07 Mulberry SOLD RTG reconcile
//
// Operator matched the paper's SOLD RTG section (12 SOs) against the app.
// Nine already matched. Three didn't:
//
//   6659  Paper: sold to "Back Acre" (note: 6/15 Sheffield 15k). App:
//         available. Mark sold to "Back Acre", stamp soldAt.
//   6881  Paper: sold to SCHULTES (already correct in app as AC SCHULTES),
//         but flagged HOT and RTG. App: in_production. Close remaining
//         production_steps and flip status → ready_for_delivery.
//   6912  Paper: sold to A&R SEPTIC. App: available. Mark sold, stamp
//         soldAt.
//
// Idempotent — every update guards on current state.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-fix-mul-sold-rtg
// =============================================================================

import 'dotenv/config';
import {
  ProductionStepStatus,
  TrailerSaleStatus,
  TrailerStatus,
} from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🚛 Mulberry SOLD RTG reconciliation...\n');

  const now = new Date();

  async function markSold(so: string, buyer: string) {
    const t = await prisma.trailer.findFirst({
      where: { soNumber: so },
      select: { id: true, saleStatus: true, soldToName: true },
    });
    if (!t) {
      console.warn(`  ! SO ${so} not found`);
      return;
    }
    if (t.saleStatus === TrailerSaleStatus.sold) {
      console.log(
        `  = SO ${so} already sold (to "${t.soldToName}") — no-op`,
      );
      return;
    }
    await prisma.trailer.update({
      where: { id: t.id },
      data: {
        saleStatus: TrailerSaleStatus.sold,
        soldToName: buyer,
        soldAt: now,
      },
    });
    console.log(`  + SO ${so}: sale ${t.saleStatus} → sold to "${buyer}"`);
  }

  await markSold('6659', 'Back Acre');
  await markSold('6912', 'A&R SEPTIC');

  // 6881 — complete build, flip to ready. Sale is already correct.
  {
    const t = await prisma.trailer.findFirst({
      where: { soNumber: '6881' },
      select: { id: true, status: true },
    });
    if (!t) {
      console.warn('  ! SO 6881 not found');
    } else {
      const openSteps = await prisma.productionStep.findMany({
        where: {
          trailerId: t.id,
          status: { not: ProductionStepStatus.complete },
        },
        select: { id: true, becameActiveAt: true },
      });
      for (const s of openSteps) {
        await prisma.productionStep.update({
          where: { id: s.id },
          data: {
            status: ProductionStepStatus.complete,
            becameActiveAt: s.becameActiveAt ?? now,
            completedAt: now,
          },
        });
      }
      if (t.status !== TrailerStatus.ready_for_delivery) {
        await prisma.trailer.update({
          where: { id: t.id },
          data: { status: TrailerStatus.ready_for_delivery },
        });
      }
      console.log(
        `  + SO 6881: closed ${openSteps.length} step(s), status ${t.status} → ready_for_delivery`,
      );
    }
  }

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
