// =============================================================================
// BIGFOOT TRAILERS — One-shot data correction (2026-07-21)
//
// Two corrections, both from the owner:
//
//  1. TRAILER LOCATIONS. Six stock trailers were physically moved to the Jax
//     and Atlanta yards but the app still had them at Mulberry. Their current
//     location is corrected, and the intended stock yard is aligned to match
//     (a trailer sitting at Jax that is still earmarked for Mulberry keeps
//     showing on the "ready to ship from Mulberry" tile).
//     Two customer orders have gone out to the customer and are marked
//     delivered.
//
//  2. OPTION REVIEW BACKFILL. Options added before the flag rule was fixed
//     were never flagged, so they never reached the production manager's
//     review box. Flag the outstanding ones so they surface once.
//
// Every change is written with an audit_log row so the history shows what was
// corrected and why — these are hand corrections, not app actions.
//
// Idempotent: re-running only writes rows that are still wrong.
// Run:  gh workflow run db-seed.yml -f script=fix-trailer-locations-2026-07-21
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

/** Set true to preview without writing. */
const DRY_RUN = process.env['DRY_RUN'] === 'true';

// Yard moves: SO number -> location code the trailer is physically at now.
const YARD_MOVES: Record<string, 'JACKSONVILLE' | 'ATLANTA' | 'TALLAHASSEE'> = {
  '6680': 'JACKSONVILLE',
  '6999': 'JACKSONVILLE',
  '6778': 'JACKSONVILLE',
  '6859': 'ATLANTA',
  '6904': 'ATLANTA',
  '6844': 'ATLANTA',
  // Already standing at Jim's (Tallahassee) but still earmarked for Mulberry,
  // so it kept reading as "still to ship". Align the intended yard.
  '6959': 'TALLAHASSEE',
};

// Customer orders that have gone out to the customer.
const DELIVERED = ['6891'];

async function main(): Promise<void> {
  console.log(`🔧 Trailer corrections${DRY_RUN ? ' (DRY RUN — nothing written)' : ''}\n`);

  const locations = await prisma.location.findMany({
    select: { id: true, code: true },
  });
  const locId = new Map(locations.map((l) => [l.code, l.id]));

  // ── 1. Yard moves ─────────────────────────────────────────────────────────
  for (const [soNumber, code] of Object.entries(YARD_MOVES)) {
    const target = locId.get(code);
    if (!target) {
      console.log(`  ⚠️  ${soNumber}: location ${code} not found — skipped`);
      continue;
    }
    const t = await prisma.trailer.findFirst({
      where: { soNumber },
      select: {
        id: true,
        currentLocationId: true,
        intendedStockLocationId: true,
        isStockBuild: true,
        status: true,
      },
    });
    if (!t) {
      console.log(`  ⚠️  ${soNumber}: not found — skipped`);
      continue;
    }

    // Align the intended yard for stock builds so yard tiles/filters agree
    // with where the trailer actually is.
    const nextIntended = t.isStockBuild ? target : t.intendedStockLocationId;
    const changed =
      t.currentLocationId !== target || t.intendedStockLocationId !== nextIntended;
    if (!changed) {
      console.log(`  ✓ ${soNumber}: already at ${code}`);
      continue;
    }

    console.log(
      `  → ${soNumber}: current ${t.currentLocationId ?? '-'} → ${target} (${code})` +
        (t.isStockBuild ? `, intended ${t.intendedStockLocationId ?? '-'} → ${target}` : ''),
    );
    if (DRY_RUN) continue;

    await prisma.trailer.update({
      where: { id: t.id },
      data: { currentLocationId: target, intendedStockLocationId: nextIntended },
    });
    await prisma.auditLog.create({
      data: {
        entityType: 'trailer',
        entityId: t.id,
        action: 'trailer.location_corrected',
        oldValues: {
          currentLocationId: t.currentLocationId,
          intendedStockLocationId: t.intendedStockLocationId,
        },
        newValues: {
          currentLocationId: target,
          intendedStockLocationId: nextIntended,
          note: `Physically at ${code}; corrected from the yard count`,
        },
      },
    });
  }

  // ── 2. Delivered to customer ──────────────────────────────────────────────
  for (const soNumber of DELIVERED) {
    const t = await prisma.trailer.findFirst({
      where: { soNumber },
      select: { id: true, status: true, saleStatus: true, soldToName: true },
    });
    if (!t) {
      console.log(`  ⚠️  ${soNumber}: not found — skipped`);
      continue;
    }
    if (t.status === 'delivered') {
      console.log(`  ✓ ${soNumber}: already delivered`);
      continue;
    }
    console.log(`  → ${soNumber}: status ${t.status} → delivered (gone to ${t.soldToName ?? 'customer'})`);
    if (DRY_RUN) continue;

    await prisma.trailer.update({
      where: { id: t.id },
      data: { status: 'delivered' },
    });
    await prisma.auditLog.create({
      data: {
        entityType: 'trailer',
        entityId: t.id,
        action: 'trailer.status_corrected',
        oldValues: { status: t.status },
        newValues: {
          status: 'delivered',
          note: 'Gone to the customer; corrected from the yard count',
        },
      },
    });
  }

  // ── 3. Option review backfill ─────────────────────────────────────────────
  const unflagged = await prisma.trailerAddon.findMany({
    where: { addedDuringProduction: false, pmAcknowledgedAt: null },
    select: { id: true, addonName: true, trailerId: true },
  });
  console.log(`\n  ${unflagged.length} unflagged option(s) awaiting review`);
  for (const a of unflagged) {
    console.log(`  → option ${a.id} "${a.addonName}" → flagged for review`);
  }
  if (!DRY_RUN && unflagged.length > 0) {
    await prisma.trailerAddon.updateMany({
      where: { id: { in: unflagged.map((a) => a.id) } },
      data: { addedDuringProduction: true },
    });
  }

  console.log(`\n🎉 Done${DRY_RUN ? ' (dry run)' : ''}.`);
}

main()
  .catch((e) => {
    console.error('❌ Correction failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
