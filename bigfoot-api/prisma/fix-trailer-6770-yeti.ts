// =============================================================================
// BIGFOOT TRAILERS — One-shot: reconcile SO 6770 production steps to YETI
//
// Trailer 6770 was created as XP_14ET (series=xp) and dropped into the XP
// finish-weld queue. Its model has since been swapped to a Yeti, but the
// production_steps still point at XP_JIG / XP_FIN — so it's stuck in the
// XP queues. This script re-routes every step to the matching department
// from the YETI workflow_template, keyed by step_order.
//
// Paint booth (step 7) is preserved if it's already PAINT_A or PAINT_B —
// we don't want to silently move a trailer between booths when the rest
// of the YETI workflow happens to point at PAINT_A by default.
//
// Idempotent: only fires when 6770's step departments are non-YETI.
// =============================================================================

import 'dotenv/config';
import { TrailerSeries } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const TARGET_SO = '6770';
const PAINT_CODES = new Set(['PAINT_A', 'PAINT_B']);

async function main(): Promise<void> {
  const trailer = await prisma.trailer.findUnique({
    where: { soNumber: TARGET_SO },
    select: {
      id: true,
      soNumber: true,
      trailerModel: { select: { code: true, series: true } },
    },
  });
  if (!trailer) throw new Error(`Trailer SO ${TARGET_SO} not found.`);
  if (trailer.trailerModel.series !== TrailerSeries.yeti) {
    throw new Error(
      `SO ${TARGET_SO}: model series is ${trailer.trailerModel.series}, not yeti. ` +
        `Set the trailer model to a Yeti first, then re-run this script.`,
    );
  }

  const templates = await prisma.workflowTemplate.findMany({
    where: { series: TrailerSeries.yeti },
    orderBy: { stepOrder: 'asc' },
    include: { department: { select: { id: true, code: true } } },
  });
  if (templates.length !== 12) {
    throw new Error(`Expected 12 yeti templates, found ${templates.length}.`);
  }

  const steps = await prisma.productionStep.findMany({
    where: { trailerId: trailer.id },
    orderBy: { stepOrder: 'asc' },
    include: { department: { select: { id: true, code: true } } },
  });

  console.log(`📋 SO ${TARGET_SO} (model ${trailer.trailerModel.code}, series ${trailer.trailerModel.series})`);
  console.log(`   ${steps.length} production_steps found.\n`);

  let updates = 0;
  for (const s of steps) {
    const t = templates.find((x) => x.stepOrder === s.stepOrder);
    if (!t) {
      console.log(`  step ${s.stepOrder}: no matching template — skipping`);
      continue;
    }
    // Preserve paint booth choice — don't move active paint A/B assignments.
    if (PAINT_CODES.has(s.department.code) && PAINT_CODES.has(t.department.code)) {
      console.log(
        `  step ${s.stepOrder.toString().padStart(2)} ${s.department.code.padEnd(12)} → preserved (paint booth)`,
      );
      continue;
    }
    if (s.department.id === t.department.id) {
      console.log(
        `  step ${s.stepOrder.toString().padStart(2)} ${s.department.code.padEnd(12)} = ${t.department.code} (no change)`,
      );
      continue;
    }
    await prisma.productionStep.update({
      where: { id: s.id },
      data: { departmentId: t.department.id },
    });
    updates++;
    console.log(
      `  step ${s.stepOrder.toString().padStart(2)} ${s.department.code.padEnd(12)} → ${t.department.code}`,
    );
  }

  console.log(`\n🎉 Done. ${updates} step(s) re-routed.`);
}

main()
  .catch((e) => {
    console.error('❌ Reconcile failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
