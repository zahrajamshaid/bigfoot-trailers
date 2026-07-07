// =============================================================================
// BIGFOOT TRAILERS — Revert 5 VA trailers back to ready_for_delivery
//
// Follow-up correction to seed-fix-va-reconcile-2 — that seed marked
// these five as `delivered` on the read of "not on paper → picked up",
// but the operator clarified they are still physically at VA waiting
// for their buyers. Same sale info, same yard, just the wrong status
// transition. Flip back.
//
//   6658  DO_17K   sold Sawgrass                — back to ready_for_delivery
//   6783  DO_14K   sold MYR EQUIPMENT LLC       — back to ready_for_delivery
//   6784  DO_14K   sold MYR EQUIPMENT LLC       — back to ready_for_delivery
//   6785  DO_14K   sold MYR EQUIPMENT LLC       — back to ready_for_delivery
//   6866  XP_10K   sold Aqua Clean Solutions    — back to ready_for_delivery
//
// Idempotent — every update guards on status === delivered so a re-run
// is a no-op. currentLocation and sale info are left alone.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-fix-va-revert-delivered
// =============================================================================

import 'dotenv/config';
import { TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const SOS = ['6658', '6783', '6784', '6785', '6866'];

async function main(): Promise<void> {
  console.log('🚛 Reverting 5 VA sold trailers back to ready_for_delivery...\n');

  let fixed = 0;
  let skipped = 0;
  for (const so of SOS) {
    const t = await prisma.trailer.findFirst({
      where: { soNumber: so },
      select: { id: true, status: true },
    });
    if (!t) {
      console.warn(`  ! SO ${so} not found`);
      continue;
    }
    if (t.status !== TrailerStatus.delivered) {
      console.log(`  = SO ${so} already status=${t.status} — no-op`);
      skipped++;
      continue;
    }
    await prisma.trailer.update({
      where: { id: t.id },
      data: { status: TrailerStatus.ready_for_delivery },
    });
    console.log(`  + SO ${so}: delivered → ready_for_delivery`);
    fixed++;
  }

  console.log(`\n✅ ${fixed} reverted, ${skipped} already correct.\n🎉 Done.`);
}

main()
  .catch((e) => {
    console.error('❌ Fix failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
