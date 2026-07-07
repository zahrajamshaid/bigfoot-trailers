// =============================================================================
// BIGFOOT TRAILERS — Fix the "semi shipment that never got marked at VA"
//
// Five trailers were part of a stack-to-VA (Tappahannock) run that shipped
// out of Mulberry on 2026-06-22. Four were flipped to `delivered` on the
// Mulberry side but their trailer.current_location_id was never advanced
// to TAPPAHANNOCK; the fifth (6777) got no arrival mark at all. All five
// are physically at the VA yard per the yard-report (2026-07-07) and
// should be `ready_for_delivery` at TAPPAHANNOCK.
//
// Fixes:
//   6361  YETI_18K  — was `delivered` at MULBERRY → ready_for_delivery at TAPPAHANNOCK
//   6417  YETI_15K  — was `delivered` at MULBERRY → ready_for_delivery at TAPPAHANNOCK
//   6586  DO_17K    — was `delivered` at MULBERRY → ready_for_delivery at TAPPAHANNOCK
//   6743  YETI_18K  — was `delivered` at MULBERRY → ready_for_delivery at TAPPAHANNOCK
//   6777  TLT_18K   — was `ready_for_delivery` at MULBERRY → at TAPPAHANNOCK (status unchanged)
//
// Idempotent: every update matches on (soNumber, currentLocationId !=
// TAPPAHANNOCK) so a re-run is a no-op. The original `delivered` delivery
// rows for the stack run are left alone — they were the legitimate
// Mulberry→VA move, and preserving them keeps the delivery-history audit.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-fix-va-semi-arrival
// =============================================================================

import 'dotenv/config';
import { TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

// Trailers that were flipped to `delivered` on the Mulberry side but need
// to come back to `ready_for_delivery` since they're still at VA waiting
// to be sold off the lot.
const STUCK_DELIVERED = ['6361', '6417', '6586', '6743'];

// Trailer that never got its arrival marked — status is already correct
// (`ready_for_delivery`), but currentLocation is still MULBERRY.
const STUCK_READY = ['6777'];

async function main(): Promise<void> {
  console.log('🚛 Reconciling VA (Tappahannock) semi-shipment arrivals...\n');

  const va = await prisma.location.findFirst({
    where: { code: 'TAPPAHANNOCK' },
    select: { id: true, name: true },
  });
  if (!va) throw new Error('TAPPAHANNOCK location not seeded');
  console.log(`Target yard: ${va.name} (id=${va.id})\n`);

  let stuckFixed = 0;
  let stuckSkipped = 0;
  for (const so of STUCK_DELIVERED) {
    const before = await prisma.trailer.findFirst({
      where: { soNumber: so },
      select: {
        id: true,
        soNumber: true,
        status: true,
        currentLocationId: true,
      },
    });
    if (!before) {
      console.warn(`  ! SO ${so} not found — skipping`);
      continue;
    }
    if (before.currentLocationId === va.id && before.status === TrailerStatus.ready_for_delivery) {
      console.log(`  = SO ${so} already at ${va.name} + ready — no-op`);
      stuckSkipped++;
      continue;
    }
    await prisma.trailer.update({
      where: { id: before.id },
      data: {
        currentLocationId: va.id,
        status: TrailerStatus.ready_for_delivery,
      },
    });
    console.log(
      `  + SO ${so} → currentLocation ${va.name}, status ready_for_delivery ` +
        `(was status=${before.status}, currentLocationId=${before.currentLocationId})`,
    );
    stuckFixed++;
  }

  for (const so of STUCK_READY) {
    const before = await prisma.trailer.findFirst({
      where: { soNumber: so },
      select: {
        id: true,
        soNumber: true,
        status: true,
        currentLocationId: true,
      },
    });
    if (!before) {
      console.warn(`  ! SO ${so} not found — skipping`);
      continue;
    }
    if (before.currentLocationId === va.id) {
      console.log(`  = SO ${so} already at ${va.name} — no-op`);
      stuckSkipped++;
      continue;
    }
    await prisma.trailer.update({
      where: { id: before.id },
      data: { currentLocationId: va.id },
    });
    console.log(
      `  + SO ${so} → currentLocation ${va.name} ` +
        `(was currentLocationId=${before.currentLocationId})`,
    );
    stuckFixed++;
  }

  console.log(
    `\n✅ Fixed ${stuckFixed} trailers, ${stuckSkipped} already correct.\n`,
  );
  console.log('🎉 Done.');
}

main()
  .catch((e) => {
    console.error('❌ Fix failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
