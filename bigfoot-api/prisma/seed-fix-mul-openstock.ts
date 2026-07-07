// =============================================================================
// BIGFOOT TRAILERS — Fix Mulberry open-stock discrepancies (2026-07-07)
//
// Operator reconciled the July 7 yard-report open-stock list against the
// app. Two rows didn't match:
//
//   6770  Paper: open stock at Mulberry. The paper's note reads
//         "OLD HI LOW ASK BRETT FOR PICS" — that's a description of the
//         trailer (an old hi-low model, ask Brett for pics) not a
//         customer name. Someone read it as a buyer and marked the
//         trailer sold to "Hi Low". Clear the sale.
//
//   6893  Paper: open stock at Mulberry. App has it as in_production +
//         sale_pending. Physical build is done; unstick it — complete
//         remaining production_steps, flip status → ready_for_delivery,
//         clear the sale_pending (matches the rest of the open-stock
//         column).
//
// Not in DB: 6670 (25 DO 35, BEAST & HYDRO JACKS). Operator will create
// the trailer record — not addressable from a seed.
//
// Idempotent — every update guards on the current field state so re-runs
// are no-ops.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-fix-mul-openstock
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
  console.log('🚛 Mulberry open-stock reconciliation...\n');

  const now = new Date();

  // ── 6770 — clear the phantom "Hi Low" sale ───────────────────────────────
  {
    const t = await prisma.trailer.findFirst({
      where: { soNumber: '6770' },
      select: {
        id: true,
        saleStatus: true,
        soldToName: true,
        customerId: true,
      },
    });
    if (!t) {
      console.warn('  ! SO 6770 not found');
    } else if (t.saleStatus === TrailerSaleStatus.available) {
      console.log('  = SO 6770 already available — no-op');
    } else {
      await prisma.trailer.update({
        where: { id: t.id },
        data: {
          saleStatus: TrailerSaleStatus.available,
          soldToName: null,
          soldAt: null,
          ...(t.customerId !== null
            ? { customer: { disconnect: true as const } }
            : {}),
        },
      });
      console.log(
        `  + SO 6770: cleared sale (was ${t.saleStatus}, buyer "${t.soldToName ?? t.customerId}") → available`,
      );
    }
  }

  // ── 6893 — complete build, mark ready + available ───────────────────────
  {
    const t = await prisma.trailer.findFirst({
      where: { soNumber: '6893' },
      select: { id: true, status: true, saleStatus: true },
    });
    if (!t) {
      console.warn('  ! SO 6893 not found');
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
      const data: {
        status?: TrailerStatus;
        saleStatus?: TrailerSaleStatus;
      } = {};
      if (t.status !== TrailerStatus.ready_for_delivery) {
        data.status = TrailerStatus.ready_for_delivery;
      }
      if (t.saleStatus !== TrailerSaleStatus.available) {
        data.saleStatus = TrailerSaleStatus.available;
      }
      if (Object.keys(data).length > 0) {
        await prisma.trailer.update({
          where: { id: t.id },
          data,
        });
      }
      console.log(
        `  + SO 6893: closed ${openSteps.length} step(s), status → ready_for_delivery, sale ${t.saleStatus} → available`,
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
