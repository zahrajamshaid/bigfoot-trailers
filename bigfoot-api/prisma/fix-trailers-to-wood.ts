// =============================================================================
// BIGFOOT TRAILERS — One-shot: move SO 6702 + 6704 to WOOD (step 11)
//
// Manager-requested jump-ahead. For each trailer we:
//   - Mark every step before step 11 as complete (preserves any existing
//     completedAt; only fills in the blank rows).
//   - Set step 11 (WOOD) active, becameActiveAt = now, queuePosition at the
//     tail of WOOD's existing active queue so it doesn't displace anyone.
//   - Leave step 12 (FINAL_QC) waiting.
// Idempotent — re-running on a trailer already past WOOD is a no-op.
// =============================================================================

import 'dotenv/config';
import { ProductionStepStatus, TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const TARGET_SOS = ['6702', '6704'];

async function jumpToWood(soNumber: string): Promise<void> {
  const trailer = await prisma.trailer.findUnique({
    where: { soNumber },
    select: {
      id: true,
      soNumber: true,
      trailerModel: { select: { series: true } },
    },
  });
  if (!trailer) {
    console.error(`  ✖ SO ${soNumber}: trailer not found`);
    return;
  }

  const wood = await prisma.department.findUnique({
    where: { code: 'WOOD' },
    select: { id: true, code: true, displayName: true },
  });
  if (!wood) throw new Error('WOOD department missing');

  let steps = await prisma.productionStep.findMany({
    where: { trailerId: trailer.id },
    orderBy: { stepOrder: 'asc' },
    select: { id: true, stepOrder: true, status: true, departmentId: true },
  });

  // No workflow yet — these trailers were created as ready-for-delivery by
  // the sold-and-delivery seed. Generate the 12 steps from the model's
  // series template with everything before WOOD pre-completed.
  if (steps.length === 0) {
    const templates = await prisma.workflowTemplate.findMany({
      where: { series: trailer.trailerModel.series },
      orderBy: { stepOrder: 'asc' },
      select: { departmentId: true, stepOrder: true },
    });
    if (templates.length !== 12) {
      console.error(
        `  ✖ SO ${soNumber}: expected 12 templates for series ${trailer.trailerModel.series}, found ${templates.length}`,
      );
      return;
    }
    const now = new Date();
    for (const t of templates) {
      const isPre = t.stepOrder < 11;
      const isWood = t.stepOrder === 11;
      await prisma.productionStep.create({
        data: {
          trailerId: trailer.id,
          departmentId: t.departmentId,
          stepOrder: t.stepOrder,
          status: isPre
            ? ProductionStepStatus.complete
            : isWood
              ? ProductionStepStatus.active
              : ProductionStepStatus.waiting,
          becameActiveAt: isPre || isWood ? now : null,
          completedAt: isPre ? now : null,
          queuePosition: isWood ? 1 : null,
        },
      });
    }
    await prisma.trailer.update({
      where: { id: trailer.id },
      data: { status: TrailerStatus.in_production },
    });
    console.log(
      `  + SO ${trailer.soNumber}: 12 step(s) generated → WOOD active (no prior workflow)`,
    );
    return;
  }

  if (steps.length !== 12) {
    console.error(
      `  ✖ SO ${soNumber}: expected 12 steps, found ${steps.length}`,
    );
    return;
  }

  const now = new Date();
  let updates = 0;

  for (const s of steps) {
    if (s.stepOrder < 11) {
      if (s.status !== ProductionStepStatus.complete) {
        await prisma.productionStep.update({
          where: { id: s.id },
          data: {
            status: ProductionStepStatus.complete,
            becameActiveAt: now,
            completedAt: now,
            queuePosition: null,
          },
        });
        updates++;
      }
    } else if (s.stepOrder === 11) {
      if (s.status !== ProductionStepStatus.active) {
        // Drop in at the tail of the current WOOD active queue.
        const maxPos = await prisma.productionStep.aggregate({
          where: {
            departmentId: wood.id,
            status: ProductionStepStatus.active,
          },
          _max: { queuePosition: true },
        });
        await prisma.productionStep.update({
          where: { id: s.id },
          data: {
            status: ProductionStepStatus.active,
            becameActiveAt: now,
            completedAt: null,
            queuePosition: (maxPos._max.queuePosition ?? 0) + 1,
          },
        });
        updates++;
      }
    }
  }

  // Sync trailer.status so downstream queries don't lag.
  await prisma.trailer.update({
    where: { id: trailer.id },
    data: { status: TrailerStatus.in_production },
  });

  console.log(`  + SO ${trailer.soNumber}: ${updates} step(s) updated → WOOD active`);
}

async function main(): Promise<void> {
  console.log('🛠  Jumping trailers to WOOD step...\n');
  for (const so of TARGET_SOS) await jumpToWood(so);
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
