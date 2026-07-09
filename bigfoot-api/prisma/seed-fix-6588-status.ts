// =============================================================================
// BIGFOOT TRAILERS — Fix SO 6588 status after the sale-pending regression
//
// The operator marked 6588 (open stock at VA, ready_for_delivery) as
// sale_pending, then added a customer. A bug in updateSaleStatus flipped
// its status to `delivered` the moment it went sale_pending — see the
// removed "inverse revert" block in trailers.service.updateSaleStatus.
// The trailer is physically at VA, now sold to Elevated Ag Solution, and
// should be ready_for_delivery (waiting for pickup / delivery), not
// delivered.
//
// Fix: status delivered → ready_for_delivery. Sale info (sold + Elevated
// Ag Solution) and location (VA) are left as the operator set them.
//
// Idempotent — guarded on status === delivered.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-fix-6588-status
// =============================================================================

import 'dotenv/config';
import { TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🚛 Fixing SO 6588 status (sale-pending regression)...\n');

  const t = await prisma.trailer.findFirst({
    where: { soNumber: '6588' },
    select: { id: true, status: true },
  });
  if (!t) {
    console.warn('  ! SO 6588 not found');
    return;
  }
  if (t.status !== TrailerStatus.delivered) {
    console.log(`  = SO 6588 status=${t.status} — no-op`);
    return;
  }
  await prisma.trailer.update({
    where: { id: t.id },
    data: { status: TrailerStatus.ready_for_delivery },
  });
  console.log('  + SO 6588: status delivered → ready_for_delivery');
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
