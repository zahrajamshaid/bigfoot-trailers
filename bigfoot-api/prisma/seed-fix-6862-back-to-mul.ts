// =============================================================================
// BIGFOOT TRAILERS — Move SO 6862 back to Mulberry
//
// SO 6862 got shuffled a few times during the 2026-07-07 yard reconcile:
//   - Originally at Mulberry with a ghost scheduled delivery (#284).
//   - Batch B moved it to VA when the operator said it was sent last week.
//   - Operator now confirms it's actually physically at Mulberry, not VA.
//
// Move currentLocation TAPPAHANNOCK → MULBERRY. Leave saleStatus /
// intendedStockLocation alone. The old ghost delivery #284 was already
// flipped to delivered @ TAPPAHANNOCK by seed-fix-va-batch — that
// historical row is fine to leave (it now says "was delivered to VA"
// but the trailer moved back afterwards, and inventory reads
// trailer.currentLocation, not delivery destination).
//
// Idempotent — guarded on currentLocationId.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-fix-6862-back-to-mul
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🚛 Moving SO 6862 back to Mulberry...\n');

  const mul = await prisma.location.findFirst({
    where: { code: 'MULBERRY' },
    select: { id: true, name: true },
  });
  if (!mul) throw new Error('MULBERRY location not seeded');

  const t = await prisma.trailer.findFirst({
    where: { soNumber: '6862' },
    select: { id: true, currentLocationId: true },
  });
  if (!t) {
    console.warn('  ! SO 6862 not found');
    return;
  }
  if (t.currentLocationId === mul.id) {
    console.log('  = SO 6862 already at Mulberry — no-op');
    return;
  }
  await prisma.trailer.update({
    where: { id: t.id },
    data: { currentLocation: { connect: { id: mul.id } } },
  });
  console.log(
    `  + SO 6862: currentLocation → ${mul.name} (was ${t.currentLocationId})`,
  );

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
