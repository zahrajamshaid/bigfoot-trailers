// =============================================================================
// BIGFOOT TRAILERS — One-shot: generate the missing workflow for SO 7089
//
// SO 7089 was entered as a "misc" (inventory-only) trailer, then switched to a
// 10K XP (model XP_10K, series xp). The model change didn't backfill a
// workflow, so the trailer had ZERO production_steps and was sitting in
// ready_for_delivery — invisible to the production line.
//
// This creates the full 12-step XP workflow for it exactly the way the app's
// WorkflowGeneratorService would at trailer-create time, and drops the trailer
// back to pending_production with XP_JIG active at the start:
//
//   - Reads the xp workflow_templates (the 12 canonical steps, in order).
//   - Paint booth (step 7): PAINT_A/PAINT_B picked from the trailer's own
//     size_ft — ≥20ft forces PAINT_B, otherwise the lighter booth. (7089 is
//     22ft → PAINT_B.)
//   - Wire/Hydraulics (step 9): >24ft on the XP line diverts WIRE → HYDRAULICS.
//     (7089 is 22ft → stays WIRE.)
//   - Step 1 (XP_JIG) → active, queue_position 1, became_active_at now.
//     Every later step → waiting. No gooseneck bypass on the xp line.
//   - Trailer status → pending_production (mirrors a fresh build; it flips to
//     in_production on its own when XP_JIG is completed).
//
// An audit_log row records this as a hand correction.
//
// Idempotent: if the trailer already has production_steps, it does nothing.
// Run:  gh workflow run db-seed.yml -f script=fix-generate-workflow-7089-2026-07-28
//   Preview with the same command after setting DRY_RUN=true in the workflow.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DRY_RUN = process.env['DRY_RUN'] === 'true';
const SO = '7089';

// Mirror WorkflowGeneratorService constants exactly.
const PAINT_A_CODE = 'PAINT_A';
const PAINT_B_CODE = 'PAINT_B';
const WIRE_CODE = 'WIRE';
const HYDRAULICS_CODE = 'HYDRAULICS';
const PAINT_A_MAX_FT = 20; // ≥ this → force PAINT_B (PAINT_A is the smaller booth)
const WIRE_MAX_FT = 24; //  > this → WIRE diverts to HYDRAULICS

function parseSizeFt(sizeFt: string | null | undefined): number | null {
  if (!sizeFt) return null;
  const m = String(sizeFt).match(/(\d+(?:\.\d+)?)/);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) ? n : null;
}

async function main(): Promise<void> {
  console.log(`🔧 Generating XP workflow for SO ${SO}${DRY_RUN ? ' (DRY RUN — nothing written)' : ''}\n`);

  const trailer = await prisma.trailer.findFirst({
    where: { soNumber: SO },
    select: {
      id: true,
      soNumber: true,
      sizeFt: true,
      status: true,
      trailerModel: { select: { code: true, series: true } },
    },
  });

  if (!trailer) {
    console.log(`  ⚠️  SO ${SO} not found — nothing to do.`);
    return;
  }

  console.log(`  Trailer id=${trailer.id} model=${trailer.trailerModel.code} ` +
    `series=${trailer.trailerModel.series} size=${trailer.sizeFt ?? '(null)'} status=${trailer.status}`);

  if (trailer.trailerModel.series !== 'xp') {
    console.log(`  ⚠️  Series is "${trailer.trailerModel.series}", expected "xp" — aborting so we don't build the wrong line.`);
    return;
  }

  const existing = await prisma.productionStep.count({ where: { trailerId: trailer.id } });
  if (existing > 0) {
    console.log(`  ✓ SO ${SO} already has ${existing} production step(s) — already fixed, nothing to do.`);
    return;
  }

  // Ordered xp templates — must be the canonical 12.
  const templates = await prisma.workflowTemplate.findMany({
    where: { series: 'xp' },
    orderBy: { stepOrder: 'asc' },
    include: { department: { select: { id: true, code: true } } },
  });
  if (templates.length !== 12) {
    console.log(`  ⚠️  Expected 12 xp templates, found ${templates.length} — aborting.`);
    return;
  }

  // Departments we may re-point steps to.
  const depts = await prisma.department.findMany({
    where: { code: { in: [PAINT_A_CODE, PAINT_B_CODE, WIRE_CODE, HYDRAULICS_CODE] } },
    select: { id: true, code: true },
  });
  const deptId = (code: string): number | undefined => depts.find((d) => d.code === code)?.id;

  // ── Paint booth resolution (xp is not a gooseneck line) ────────────────────
  const lengthFt = parseSizeFt(trailer.sizeFt);
  const forcePaintB = lengthFt !== null && lengthFt >= PAINT_A_MAX_FT;

  let paintBoothDeptId: number;
  if (forcePaintB) {
    paintBoothDeptId = deptId(PAINT_B_CODE) ?? deptId(PAINT_A_CODE)!;
  } else {
    // Lighter booth by active+waiting load; ties → PAINT_A.
    const paintA = deptId(PAINT_A_CODE);
    const paintB = deptId(PAINT_B_CODE);
    if (paintA == null) paintBoothDeptId = paintB!;
    else if (paintB == null) paintBoothDeptId = paintA;
    else {
      const [countA, countB] = await Promise.all([
        prisma.productionStep.count({ where: { departmentId: paintA, status: { in: ['active', 'waiting'] } } }),
        prisma.productionStep.count({ where: { departmentId: paintB, status: { in: ['active', 'waiting'] } } }),
      ]);
      paintBoothDeptId = countB < countA ? paintB : paintA;
    }
  }

  // ── Wire → Hydraulics override ─────────────────────────────────────────────
  const forceHydraulicsOverWire = lengthFt !== null && lengthFt > WIRE_MAX_FT;
  const hydraulicsDeptId = forceHydraulicsOverWire ? deptId(HYDRAULICS_CODE) ?? null : null;

  const paintCode = depts.find((d) => d.id === paintBoothDeptId)?.code;
  console.log(`  Length=${lengthFt ?? '(null)'}ft → paint booth ${paintCode}` +
    `${forceHydraulicsOverWire ? ', step 9 WIRE→HYDRAULICS' : ', step 9 stays WIRE'}\n`);

  const now = new Date();

  // Build the 12 rows, mirroring generateSteps exactly.
  const rows = templates.map((t) => {
    const isFirstStep = t.stepOrder === 1;
    const isPaintBoothStep = t.department.code === PAINT_A_CODE || t.department.code === PAINT_B_CODE;
    const isWireStep = t.department.code === WIRE_CODE;

    let departmentId = t.departmentId;
    if (isPaintBoothStep) departmentId = paintBoothDeptId;
    else if (isWireStep && hydraulicsDeptId !== null) departmentId = hydraulicsDeptId;

    return {
      trailerId: trailer.id,
      departmentId,
      stepOrder: t.stepOrder,
      status: (isFirstStep ? 'active' : 'waiting') as 'active' | 'waiting',
      queuePosition: isFirstStep ? 1 : null,
      becameActiveAt: isFirstStep ? now : null,
    };
  });

  for (const r of rows) {
    const code = depts.find((d) => d.id === r.departmentId)?.code
      ?? templates.find((t) => t.stepOrder === r.stepOrder)?.department.code;
    console.log(`    ord ${String(r.stepOrder).padStart(2)}  ${code}  ${r.status}${r.status === 'active' ? '  ← XP_JIG start' : ''}`);
  }

  if (DRY_RUN) {
    console.log(`\n  (dry run) would create ${rows.length} steps and set SO ${SO} → pending_production.`);
    return;
  }

  await prisma.$transaction(async (tx) => {
    await tx.productionStep.createMany({ data: rows });

    await tx.trailer.update({
      where: { id: trailer.id },
      data: { status: 'pending_production' },
    });

    await tx.auditLog.create({
      data: {
        entityType: 'trailer',
        entityId: trailer.id,
        action: 'trailer.workflow_generated',
        oldValues: { status: trailer.status, stepCount: 0 },
        newValues: {
          status: 'pending_production',
          stepCount: rows.length,
          paintBooth: paintCode,
          firstStep: 'XP_JIG',
          note: 'Entered as misc then switched to 10K XP; workflow was never generated. ' +
            'Backfilled the full XP line and placed the trailer at the start (XP_JIG).',
        },
      },
    });
  });

  console.log(`\n🎉 Done. Created ${rows.length} steps for SO ${SO}; XP_JIG active, status → pending_production.`);
}

main()
  .catch((e) => {
    console.error('❌ Workflow generation failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
