// =============================================================================
// BIGFOOT TRAILERS — Add "Install fenders" to the WOOD checklist
//
// qc_checklist_items rows attached to a non-QC department surface as
// worker self-check items on that department's step (see qc.service
// getChecklistItemsForStep). Adding "Install fenders" to WOOD will appear
// for the welder/finisher when they tick through their wood-step checks.
//
// Idempotent — skips when an identical row already exists.
// =============================================================================

import 'dotenv/config';
import { QcSeriesScope } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const DEPT_CODE = 'WOOD';
const ITEM_LABEL = 'Install fenders';

async function main(): Promise<void> {
  const wood = await prisma.department.findUnique({
    where: { code: DEPT_CODE },
    select: { id: true, displayName: true },
  });
  if (!wood) throw new Error(`Department ${DEPT_CODE} missing`);

  const existing = await prisma.qcChecklistItem.findFirst({
    where: { departmentId: wood.id, itemLabel: ITEM_LABEL },
    select: { id: true, sortOrder: true, isActive: true },
  });
  if (existing) {
    if (!existing.isActive) {
      await prisma.qcChecklistItem.update({
        where: { id: existing.id },
        data: { isActive: true },
      });
      console.log(
        `  ~ "${ITEM_LABEL}" already on ${DEPT_CODE} (id=${existing.id}) — reactivated`,
      );
    } else {
      console.log(
        `  = "${ITEM_LABEL}" already on ${DEPT_CODE} (id=${existing.id}) — no change`,
      );
    }
  } else {
    const maxSort = await prisma.qcChecklistItem.aggregate({
      where: { departmentId: wood.id },
      _max: { sortOrder: true },
    });
    const created = await prisma.qcChecklistItem.create({
      data: {
        departmentId: wood.id,
        itemLabel: ITEM_LABEL,
        sortOrder: (maxSort._max.sortOrder ?? 0) + 1,
        appliesToSeries: QcSeriesScope.all,
        isActive: true,
      },
      select: { id: true, sortOrder: true },
    });
    console.log(
      `  + "${ITEM_LABEL}" added to ${DEPT_CODE} (${wood.displayName}) at sort ${created.sortOrder} (id=${created.id})`,
    );
  }
  console.log('\n🎉 Done.');
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
