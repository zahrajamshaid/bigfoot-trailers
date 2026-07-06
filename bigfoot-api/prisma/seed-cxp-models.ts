// =============================================================================
// BIGFOOT TRAILERS — CXP series + 10 CXP / 14K CXP models
//
// Adds the `cxp` series, its 12 workflow_template rows, and two trailer
// models: `CXP_10` (10 CXP) and `CXP_14K` (14K CXP).
//
// Runbook fit:
//   CXP is a small pull-behind that shares the gooseneck production line
//   step-for-step. The workflow is a straight copy of gooseneck_dump —
//   including the GN_FIN + QC_2 bypass (steps 3+4) and PAINT_B as the
//   default paint booth. It is NOT a gooseneck, though, so we keep it on
//   its own series so filtering / reporting can distinguish it and so a
//   customer looking at their trailer sees "10 CXP" rather than
//   "Gooseneck 10".
//
//     1  GN_WELD
//     2  QC_1
//     3  GN_FIN       ← pre-completed by the workflow generator (bypass)
//     4  QC_2         ← pre-completed by the workflow generator (bypass)
//     5  PAINT_PREP
//     6  QC_3
//     7  PAINT_B
//     8  QC_4
//     9  HYDRAULICS
//     10 QC_5
//     11 WOOD
//     12 FINAL_QC
//
// Idempotent: enum value + workflow templates + models are all upserted.
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-cxp-models
// =============================================================================

import 'dotenv/config';
import { TrailerSeries } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

// Same step / department mapping as gooseneck_dump. GN_FIN + QC_2 stay in
// the template so the audit history reflects the workflow shape — the
// workflow generator pre-completes them at trailer creation because there
// is no physical Gooseneck Finish Weld station on the floor.
const STEPS: { stepOrder: number; deptCode: string }[] = [
  { stepOrder: 1, deptCode: 'GN_WELD' },
  { stepOrder: 2, deptCode: 'QC_1' },
  { stepOrder: 3, deptCode: 'GN_FIN' },
  { stepOrder: 4, deptCode: 'QC_2' },
  { stepOrder: 5, deptCode: 'PAINT_PREP' },
  { stepOrder: 6, deptCode: 'QC_3' },
  { stepOrder: 7, deptCode: 'PAINT_B' },
  { stepOrder: 8, deptCode: 'QC_4' },
  { stepOrder: 9, deptCode: 'HYDRAULICS' },
  { stepOrder: 10, deptCode: 'QC_5' },
  { stepOrder: 11, deptCode: 'WOOD' },
  { stepOrder: 12, deptCode: 'FINAL_QC' },
];

const MODELS: { code: string; displayName: string }[] = [
  { code: 'CXP_10', displayName: '10 CXP' },
  { code: 'CXP_14K', displayName: '14K CXP' },
];

async function main(): Promise<void> {
  console.log('🦬 Seeding CXP series + workflow + models...\n');

  // ─── 0. Add the enum value in prod (ALTER TYPE can't run in a tx) ─────────
  await prisma.$executeRawUnsafe(
    `ALTER TYPE trailer_series_enum ADD VALUE IF NOT EXISTS 'cxp';`,
  );
  console.log("✅ Enum trailer_series_enum has 'cxp' value\n");

  // ─── 1. Resolve every department we need ──────────────────────────────────
  const deptCodes = Array.from(new Set(STEPS.map((s) => s.deptCode)));
  const depts = await prisma.department.findMany({
    where: { code: { in: deptCodes } },
    select: { id: true, code: true, displayName: true },
  });
  const byCode = new Map(depts.map((d) => [d.code, d]));
  for (const c of deptCodes) {
    if (!byCode.has(c)) {
      throw new Error(`Department ${c} missing — run the base seed first.`);
    }
  }

  // ─── 2. Upsert all 12 workflow_template rows by (series, stepOrder) ──────
  let tplCreated = 0;
  let tplExisted = 0;
  for (const s of STEPS) {
    const dept = byCode.get(s.deptCode)!;
    const existing = await prisma.workflowTemplate.findUnique({
      where: {
        series_stepOrder: {
          series: TrailerSeries.cxp,
          stepOrder: s.stepOrder,
        },
      },
      select: { id: true },
    });
    await prisma.workflowTemplate.upsert({
      where: {
        series_stepOrder: {
          series: TrailerSeries.cxp,
          stepOrder: s.stepOrder,
        },
      },
      update: { departmentId: dept.id },
      create: {
        series: TrailerSeries.cxp,
        stepOrder: s.stepOrder,
        departmentId: dept.id,
      },
    });
    if (existing) tplExisted++;
    else tplCreated++;
    console.log(
      `  ${existing ? '=' : '+'} step ${s.stepOrder.toString().padStart(2)} → ${dept.code.padEnd(12)} ${dept.displayName}`,
    );
  }
  console.log(
    `\n✅ Workflow templates: ${tplCreated} created, ${tplExisted} already present.\n`,
  );

  // ─── 3. Upsert the two CXP trailer models ────────────────────────────────
  for (const m of MODELS) {
    const model = await prisma.trailerModel.upsert({
      where: { code: m.code },
      update: {
        displayName: m.displayName,
        series: TrailerSeries.cxp,
        isActive: true,
      },
      create: {
        code: m.code,
        displayName: m.displayName,
        series: TrailerSeries.cxp,
        isActive: true,
      },
      select: { id: true, code: true, displayName: true, series: true },
    });
    console.log(
      `✅ Model ${model.code} → "${model.displayName}" (series=${model.series}, id=${model.id})`,
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
