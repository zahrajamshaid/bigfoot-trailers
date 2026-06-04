// =============================================================================
// BIGFOOT TRAILERS — One-shot: bypass GN_FIN + QC_2 on in-flight goosenecks
//
// Mirrors the workflow-generator change (gooseneck steps 3 + 4 auto-complete
// at creation) for trailers that were already on the floor before the change
// went live. Per the original ask the bypass yanks active steps too — any
// gooseneck currently sitting at GN_FIN or its QC_2 inspection is moved
// straight to PAINT_PREP.
//
// Scope:
//   • Only series gooseneck_dump and gooseneck_yeti.
//   • Steps 3 (GN_FIN) and 4 (QC_2) at status waiting or active are flipped
//     to complete with completedAt = now and completedByUserId = null
//     (synthetic, matches the generator's null on auto-complete).
//   • If step 5 (PAINT_PREP) is still waiting AND no other step on the
//     trailer is currently active, step 5 is activated so the trailer
//     re-enters someone's queue. If something else on the trailer is
//     active (e.g. step 1 GN_WELD still in progress, or a rework branch),
//     step 5 stays waiting — normal advance will pick it up when the
//     prerequisite finishes.
//   • Steps already at status complete are left alone.
//
// Stall alerts open on the skipped steps are resolved in the same
// transaction so the dashboard doesn't keep flagging a step we just
// auto-completed.
//
// Idempotent: re-runs after the first sweep are no-ops.
// =============================================================================

import 'dotenv/config';
import {
  ProductionStepStatus,
  TrailerSeries,
} from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const SKIPPED_STEP_ORDERS = [3, 4] as const;
const ADVANCE_TO_STEP_ORDER = 5;

const GOOSENECK_SERIES: TrailerSeries[] = [
  TrailerSeries.gooseneck_dump,
  TrailerSeries.gooseneck_yeti,
];

async function main(): Promise<void> {
  console.log('🪝 Bypassing GN_FIN + QC_2 on in-flight gooseneck trailers\n');

  const trailers = await prisma.trailer.findMany({
    where: { trailerModel: { series: { in: GOOSENECK_SERIES } } },
    select: {
      id: true,
      soNumber: true,
      trailerModel: { select: { series: true } },
      productionSteps: {
        select: {
          id: true,
          stepOrder: true,
          status: true,
          departmentId: true,
        },
        orderBy: { stepOrder: 'asc' },
      },
    },
  });

  console.log(`📋 Scanning ${trailers.length} gooseneck trailer(s).\n`);

  let trailersTouched = 0;
  let stepsFlipped = 0;
  let advancedToPaintPrep = 0;
  let alertsResolved = 0;

  for (const t of trailers) {
    const skipped = t.productionSteps.filter(
      (s) =>
        (SKIPPED_STEP_ORDERS as readonly number[]).includes(s.stepOrder) &&
        s.status !== ProductionStepStatus.complete,
    );
    if (skipped.length === 0) continue;

    const step5 = t.productionSteps.find(
      (s) => s.stepOrder === ADVANCE_TO_STEP_ORDER,
    );
    const otherActiveStep = t.productionSteps.find(
      (s) =>
        s.status === ProductionStepStatus.active &&
        !(SKIPPED_STEP_ORDERS as readonly number[]).includes(s.stepOrder) &&
        s.stepOrder !== ADVANCE_TO_STEP_ORDER,
    );

    await prisma.$transaction(async (tx) => {
      const now = new Date();
      for (const s of skipped) {
        await tx.productionStep.update({
          where: { id: s.id },
          data: {
            status: ProductionStepStatus.complete,
            completedAt: now,
            completedByUserId: null,
            becameActiveAt:
              s.status === ProductionStepStatus.waiting ? now : undefined,
          },
        });
        stepsFlipped++;

        const resolved = await tx.stallAlert.updateMany({
          where: { productionStepId: s.id, resolvedAt: null },
          data: { resolvedAt: now },
        });
        alertsResolved += resolved.count;
      }

      const shouldActivateStep5 =
        step5 &&
        step5.status === ProductionStepStatus.waiting &&
        !otherActiveStep;
      if (shouldActivateStep5) {
        // Park the trailer at the back of PAINT_PREP's queue so it doesn't
        // jump ahead of anything already in line there.
        const maxPos = await tx.productionStep.aggregate({
          where: {
            departmentId: step5.departmentId,
            status: ProductionStepStatus.active,
          },
          _max: { queuePosition: true },
        });
        await tx.productionStep.update({
          where: { id: step5.id },
          data: {
            status: ProductionStepStatus.active,
            becameActiveAt: now,
            queuePosition: (maxPos._max.queuePosition ?? 0) + 1,
          },
        });
        advancedToPaintPrep++;
      }
    });

    trailersTouched++;
    const tag = `${t.soNumber.padEnd(6)} (${t.trailerModel.series})`;
    const note = step5
      ? otherActiveStep
        ? `step ${otherActiveStep.stepOrder} still active — step 5 left waiting`
        : step5.status === ProductionStepStatus.waiting
          ? 'PAINT_PREP activated'
          : `step 5 already ${step5.status}`
      : 'no step 5 found';
    console.log(`  ${tag} → flipped ${skipped.length} step(s); ${note}`);
  }

  console.log(
    `\n🎉 Done. ${trailersTouched} trailer(s) touched, ${stepsFlipped} step(s) flipped, ${advancedToPaintPrep} advanced to PAINT_PREP, ${alertsResolved} stall alert(s) resolved.`,
  );
}

main()
  .catch((e) => {
    console.error('❌ GN bypass failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
