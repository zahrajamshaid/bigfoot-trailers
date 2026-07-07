// =============================================================================
// BIGFOOT TRAILERS — Flip SO 6781 back to ready_for_delivery
//
// SO 6781 got its status flipped to `delivered` while the reconcile
// work was in progress (someone tapped a delivery-complete action in
// the app between queries). The sale was cleared by that flow but the
// status left it out of yard inventory. Restore ready_for_delivery so
// 6781 shows up as open stock at VA.
//
// Idempotent — guarded on status === delivered.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-fix-6781-status
// =============================================================================

import 'dotenv/config';
import { TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🚛 Flipping SO 6781 back to ready_for_delivery...\n');

  const t = await prisma.trailer.findFirst({
    where: { soNumber: '6781' },
    select: { id: true, status: true },
  });
  if (!t) {
    console.warn('  ! SO 6781 not found');
    return;
  }
  if (t.status !== TrailerStatus.delivered) {
    console.log(`  = SO 6781 status=${t.status} — no-op`);
    return;
  }
  await prisma.trailer.update({
    where: { id: t.id },
    data: { status: TrailerStatus.ready_for_delivery },
  });
  console.log('  + SO 6781: delivered → ready_for_delivery');
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
