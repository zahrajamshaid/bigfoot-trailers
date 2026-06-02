// =============================================================================
// BIGFOOT TRAILERS — Mirror PAINT_A's xp/yeti/deck_over checklists onto PAINT_B
//
// PAINT_B was originally seeded only for the gooseneck_dump series because
// historically only goosenecks went through it. The workflow generator now
// (a) balances non-GN trailers between A and B by queue depth and (b) forces
// trailers ≥25ft to PAINT_B regardless. That left PAINT_B with an empty
// worker self-check for any xp / yeti / deck_over trailer routed there —
// PAINT_A worker sees the checklist, PAINT_B worker sees nothing.
//
// This seed copies every active xp / yeti / deck_over item from PAINT_A to
// PAINT_B (same label / sort order / addon gate / series scope). PAINT_B's
// existing gooseneck_dump rows are left alone. Idempotent: skips items
// already present.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-paint-b-checklists
// =============================================================================

import 'dotenv/config';
import { QcSeriesScope } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  const [paintA, paintB] = await Promise.all([
    prisma.department.findUnique({
      where: { code: 'PAINT_A' },
      select: { id: true, displayName: true },
    }),
    prisma.department.findUnique({
      where: { code: 'PAINT_B' },
      select: { id: true, displayName: true },
    }),
  ]);
  if (!paintA || !paintB) {
    throw new Error('PAINT_A or PAINT_B department missing — run base seed.');
  }

  // Only mirror items for the non-GN series PAINT_B was missing. GN-series
  // items already exist on B from the original seed — don't duplicate.
  const missingScopes: QcSeriesScope[] = [
    QcSeriesScope.xp,
    QcSeriesScope.yeti,
    QcSeriesScope.deck_over,
  ];

  const sourceItems = await prisma.qcChecklistItem.findMany({
    where: {
      departmentId: paintA.id,
      isActive: true,
      appliesToSeries: { in: missingScopes },
    },
    select: {
      itemLabel: true,
      sortOrder: true,
      appliesToSeries: true,
      requiresAddonKey: true,
    },
    orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
  });
  console.log(
    `📋 Found ${sourceItems.length} xp/yeti/deck_over item(s) on PAINT_A to mirror onto PAINT_B.\n`,
  );

  let created = 0;
  let skipped = 0;
  for (const src of sourceItems) {
    // Idempotency: skip when an item with the same (label, series) already
    // exists on PAINT_B. We don't key on sort_order so a manual reorder on
    // either side doesn't trigger a duplicate.
    const existing = await prisma.qcChecklistItem.findFirst({
      where: {
        departmentId: paintB.id,
        itemLabel: src.itemLabel,
        appliesToSeries: src.appliesToSeries,
      },
      select: { id: true, isActive: true },
    });
    if (existing) {
      if (!existing.isActive) {
        await prisma.qcChecklistItem.update({
          where: { id: existing.id },
          data: { isActive: true },
        });
        console.log(
          `  ~ [${src.appliesToSeries}] "${src.itemLabel.slice(0, 60)}" reactivated`,
        );
      } else {
        skipped++;
      }
      continue;
    }
    await prisma.qcChecklistItem.create({
      data: {
        departmentId: paintB.id,
        itemLabel: src.itemLabel,
        sortOrder: src.sortOrder,
        appliesToSeries: src.appliesToSeries,
        requiresAddonKey: src.requiresAddonKey,
        isActive: true,
      },
    });
    created++;
    console.log(
      `  + [${src.appliesToSeries}] "${src.itemLabel.slice(0, 60)}"`,
    );
  }

  console.log(
    `\n🎉 Done. ${created} created, ${skipped} already present on PAINT_B.`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
