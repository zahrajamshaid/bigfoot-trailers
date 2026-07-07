// =============================================================================
// BIGFOOT TRAILERS — VA yard reconciliation, round 2
//
// Follow-up to seed-fix-va-semi-arrival (which moved the June 22 semi
// shipment). This one handles the remaining paper-vs-app mismatches
// found in the 2026-07-07 yard-report reconciliation:
//
//   6698  — was `delivered` at TAPPAHANNOCK, sold to BODNER FENCE. Paper
//           says it's still physically at VA in a 3-stack; someone flipped
//           it to delivered prematurely. Flip back to ready_for_delivery
//           so BODNER can pick it up.
//   6911  — was `ready_for_delivery` at MULBERRY, saleStatus available.
//           Paper says at VA sold to "A and R Septic Brett". Move to
//           TAPPAHANNOCK + mark sold + stamp soldAt.
//   6658  — sold to Sawgrass, at TAPPAHANNOCK, ready. Not on paper →
//           picked up. Mark delivered.
//   6783, 6784, 6785 — MYR Equipment batch of 3 at TAPPAHANNOCK, ready +
//           sold. Not on paper → picked up as a batch. Mark delivered.
//   6866  — sold to Aqua Clean Solutions, at TAPPAHANNOCK, ready. Not on
//           paper → picked up. Mark delivered.
//
// Idempotent: every guard checks the field it's about to set is still in
// the old state, so re-runs are safe.
//
// Left untouched intentionally:
//   6875  — user says the app is right (sold to Joe Halterman, at
//           Mulberry). Paper's VA/open-stock listing was a yard mistake.
//   6298, 6455, 6527  — user is checking the yard physically.
//   6821, 6826 (Triple Crown) — same treatment; not on paper, no buyer,
//           awaiting physical verification.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-fix-va-reconcile-2
// =============================================================================

import 'dotenv/config';
import { TrailerStatus, TrailerSaleStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🚛 VA reconciliation round 2 — paper vs app cleanup...\n');

  const va = await prisma.location.findFirst({
    where: { code: 'TAPPAHANNOCK' },
    select: { id: true, name: true },
  });
  if (!va) throw new Error('TAPPAHANNOCK location not seeded');

  const now = new Date();
  let fixed = 0;
  let skipped = 0;

  const log = (so: string, msg: string, changed: boolean) => {
    console.log(`  ${changed ? '+' : '='} SO ${so}: ${msg}`);
    if (changed) fixed++;
    else skipped++;
  };

  // ── 6698 — reopen for BODNER pickup ─────────────────────────────────────
  {
    const t = await prisma.trailer.findFirst({
      where: { soNumber: '6698' },
      select: { id: true, status: true },
    });
    if (!t) console.warn('  ! SO 6698 not found');
    else if (t.status !== TrailerStatus.delivered) {
      log('6698', `already status=${t.status}, no change`, false);
    } else {
      await prisma.trailer.update({
        where: { id: t.id },
        data: { status: TrailerStatus.ready_for_delivery },
      });
      log('6698', 'status delivered → ready_for_delivery (BODNER pickup at VA)', true);
    }
  }

  // ── 6911 — move to VA + mark sold to A and R Septic Brett ──────────────
  {
    const t = await prisma.trailer.findFirst({
      where: { soNumber: '6911' },
      select: {
        id: true,
        currentLocationId: true,
        saleStatus: true,
        soldToName: true,
      },
    });
    if (!t) console.warn('  ! SO 6911 not found');
    else {
      const needsMove = t.currentLocationId !== va.id;
      const needsSale = t.saleStatus !== TrailerSaleStatus.sold;
      if (!needsMove && !needsSale) {
        log('6911', 'already at VA + sold — no change', false);
      } else {
        await prisma.trailer.update({
          where: { id: t.id },
          data: {
            currentLocationId: va.id,
            saleStatus: TrailerSaleStatus.sold,
            soldToName: 'A and R Septic Brett',
            // soldAt stamped so Health Check → Sales counts pick this
            // up as a sale today (not backdated to createdAt).
            soldAt: now,
          },
        });
        log(
          '6911',
          `move to VA + mark sold to "A and R Septic Brett" (was location=${t.currentLocationId}, sale=${t.saleStatus})`,
          true,
        );
      }
    }
  }

  // ── 6658, 6783, 6784, 6785, 6866 — mark delivered (customer picked up) ─
  const pickedUp = ['6658', '6783', '6784', '6785', '6866'];
  for (const so of pickedUp) {
    const t = await prisma.trailer.findFirst({
      where: { soNumber: so },
      select: { id: true, status: true, soldToName: true },
    });
    if (!t) {
      console.warn(`  ! SO ${so} not found`);
      continue;
    }
    if (t.status === TrailerStatus.delivered) {
      log(so, 'already delivered — no change', false);
      continue;
    }
    await prisma.trailer.update({
      where: { id: t.id },
      data: { status: TrailerStatus.delivered },
    });
    log(so, `status ${t.status} → delivered (picked up)`, true);
  }

  console.log(`\n✅ ${fixed} fixed, ${skipped} already correct.\n🎉 Done.`);
}

main()
  .catch((e) => {
    console.error('❌ Fix failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
