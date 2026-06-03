// =============================================================================
// BIGFOOT TRAILERS — Coupler verification at every jig + at QC_1
//
// Two complementary checks land in the same SQL table (qc_checklist_items):
//
//  1. WORKER SELF-CHECK at each jig department — when the welder taps
//     "Complete" on a jig step, they must affirm the right coupler is on
//     the trailer. The four jig departments are:
//        • XP_JIG       (xp series)
//        • YETI_JIG     (yeti)
//        • DO_JIG       (deck_over)
//        • GN_WELD      (gooseneck_dump + gooseneck_yeti — both use GN_WELD)
//
//  2. QC INSPECTION at QC_1 (Jig Weld QC) — covers every series via scope
//     `all`. Distinct from the existing "Coupler plate square and welded"
//     row, which is about the weld, not the coupler SKU itself.
//
// Series scope: all five rows are inserted with appliesToSeries = `all`.
// The QC + production services both filter
//     where appliesToSeries IN (trailer.series, 'all')
// so a single `all` row covers every series for that department.
//
// Sort order: appended at sortOrder = 100 so existing items keep their
// position. The mobile sorts ascending, so the new item shows at the end
// of each checklist.
//
// Idempotent: re-running upserts by (departmentId, itemLabel, appliesToSeries,
// requiresAddonKey). No duplicates, no inspection-history loss.
// =============================================================================

import 'dotenv/config';
import { QcSeriesScope } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const COUPLER_ITEM_LABEL = 'Correct coupler installed (matches sales order)';
const APPEND_SORT_ORDER = 100;

const TARGET_DEPT_CODES = ['XP_JIG', 'YETI_JIG', 'DO_JIG', 'GN_WELD', 'QC_1'] as const;

async function main(): Promise<void> {
  console.log('🔩 Seeding "correct coupler installed" check at every jig + QC_1\n');

  const depts = await prisma.department.findMany({
    where: { code: { in: TARGET_DEPT_CODES as unknown as string[] } },
    select: { id: true, code: true, isQcStep: true },
  });
  const byCode = new Map(depts.map((d) => [d.code, d]));

  const missing = TARGET_DEPT_CODES.filter((c) => !byCode.has(c));
  if (missing.length) {
    throw new Error(`Missing departments: ${missing.join(', ')}. Run base seed first.`);
  }

  let created = 0;
  let updated = 0;

  for (const code of TARGET_DEPT_CODES) {
    const dept = byCode.get(code)!;
    const role = dept.isQcStep ? 'QC inspection' : 'worker self-check';

    const existing = await prisma.qcChecklistItem.findFirst({
      where: {
        departmentId: dept.id,
        itemLabel: COUPLER_ITEM_LABEL,
        appliesToSeries: QcSeriesScope.all,
        requiresAddonKey: null,
      },
      select: { id: true },
    });

    if (existing) {
      await prisma.qcChecklistItem.update({
        where: { id: existing.id },
        data: { sortOrder: APPEND_SORT_ORDER, isActive: true },
      });
      updated++;
      console.log(`  ${code.padEnd(8)} (${role}) → updated existing item id=${existing.id}`);
    } else {
      const row = await prisma.qcChecklistItem.create({
        data: {
          departmentId: dept.id,
          itemLabel: COUPLER_ITEM_LABEL,
          appliesToSeries: QcSeriesScope.all,
          sortOrder: APPEND_SORT_ORDER,
          isActive: true,
          requiresAddonKey: null,
        },
        select: { id: true },
      });
      created++;
      console.log(`  ${code.padEnd(8)} (${role}) → created new item id=${row.id}`);
    }
  }

  console.log(
    `\n🎉 Done. ${created} created, ${updated} updated across ${TARGET_DEPT_CODES.length} departments.`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Coupler-check seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
