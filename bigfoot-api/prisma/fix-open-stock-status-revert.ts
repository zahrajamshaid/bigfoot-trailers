// =============================================================================
// BIGFOOT TRAILERS — One-shot: open-stock trailer status correction
//
// Several seed/restock scripts (seed-open-mul-restock, seed-open-stock, etc.)
// historically used trailer.status='delivered' to encode "this is now
// permanent open stock at a yard." That was always wrong semantically — open
// stock should be `ready_for_delivery` (available stock at a yard, waiting on
// a buyer), and `delivered` should mean "a customer has taken it." Until
// today's leg-1 fix in getStockInventory (which filters trailer.status !=
// delivered to drop picked-up units), the misuse was invisible: both legs of
// stock inventory ignored trailer.status. The new filter exposes the bug —
// every misencoded open-stock unit silently disappears from its yard's tile.
//
// This script flips those rows back to ready_for_delivery. Strict criteria:
//   • is_stock_build = TRUE              (it's stock, not a customer trailer)
//   • status         = 'delivered'        (the broken encoding)
//   • sale_status    = 'available'        (no sale ever happened)
//   • customer_id    IS NULL              (no linked customer)
//   • sold_to_name   IS NULL or empty     (no free-text buyer either)
//
// Any of those failing means the trailer actually was sold + delivered to a
// customer — those stay as-is. After this runs, Mulberry + every satellite
// yard's stock-inventory tile shows its real open-stock count again, and
// TALLAHASSEE's group reappears.
//
// Idempotent: re-running finds nothing to migrate.
// =============================================================================

import 'dotenv/config';
import { TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🩹 Reverting mis-encoded open-stock trailers (delivered → ready_for_delivery)\n');

  const candidates = await prisma.trailer.findMany({
    where: {
      isStockBuild: true,
      status: TrailerStatus.delivered,
      saleStatus: 'available',
      customerId: null,
      OR: [{ soldToName: null }, { soldToName: '' }],
    },
    select: {
      id: true,
      soNumber: true,
      currentLocation: { select: { code: true } },
    },
    orderBy: [{ currentLocationId: 'asc' }, { soNumber: 'asc' }],
  });

  console.log(`📋 ${candidates.length} trailer(s) to flip\n`);

  // Group counts by yard for the audit-trail print-out.
  const perYard = new Map<string, number>();
  for (const t of candidates) {
    const yard = t.currentLocation?.code ?? '?';
    perYard.set(yard, (perYard.get(yard) ?? 0) + 1);
  }

  for (const [yard, n] of [...perYard.entries()].sort()) {
    console.log(`  ${yard.padEnd(14)} → flipping ${n} trailer(s)`);
  }

  if (candidates.length === 0) {
    console.log('\n🎉 Nothing to do — every open-stock trailer is already ready_for_delivery.');
    return;
  }

  const ids = candidates.map((c) => c.id);
  const result = await prisma.trailer.updateMany({
    where: { id: { in: ids } },
    data: { status: TrailerStatus.ready_for_delivery },
  });

  console.log(`\n🎉 Done. ${result.count} trailer(s) updated.`);
}

main()
  .catch((e) => {
    console.error('❌ Backfill failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
