// =============================================================================
// BIGFOOT TRAILERS — One-shot: move SO 6580's WIRE step → HYDRAULICS
//
// 6580 was created on an XP/Yeti/Deck-Over workflow (step 9 = WIRE) but
// belongs in the hydraulics queue. This script re-points its step-9
// production_step at the HYDRAULICS department.
//
// Guard rails:
//   • Only re-points if the current step-9 dept is WIRE — anything else is
//     either already moved (re-run no-op) or genuinely on a different
//     workflow (gooseneck templates step-9 = HYDRAULICS) and we leave it.
//   • Re-points regardless of step status (active/waiting/completed) —
//     6580 is the explicit case the floor manager asked to move, so we
//     respect that even if a wire tech has already touched it.
//
// Idempotent: re-running after a successful move logs "no change".
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const TARGET_SO = '6580';
const WIRE_CODE = 'WIRE';
const HYDRAULICS_CODE = 'HYDRAULICS';

async function main(): Promise<void> {
  const trailer = await prisma.trailer.findUnique({
    where: { soNumber: TARGET_SO },
    select: {
      id: true,
      soNumber: true,
      sizeFt: true,
      trailerModel: { select: { code: true, series: true } },
    },
  });
  if (!trailer) throw new Error(`Trailer SO ${TARGET_SO} not found.`);

  console.log(
    `📋 SO ${TARGET_SO} (model ${trailer.trailerModel.code}, series ${trailer.trailerModel.series}, size ${trailer.sizeFt ?? 'unknown'})`,
  );

  const hydraulics = await prisma.department.findFirst({
    where: { code: HYDRAULICS_CODE },
    select: { id: true },
  });
  if (!hydraulics) throw new Error(`Department ${HYDRAULICS_CODE} missing.`);

  const steps = await prisma.productionStep.findMany({
    where: { trailerId: trailer.id },
    orderBy: { stepOrder: 'asc' },
    include: { department: { select: { id: true, code: true } } },
  });
  const step9 = steps.find((s) => s.stepOrder === 9);
  if (!step9) throw new Error(`SO ${TARGET_SO}: no step_order=9 row found.`);

  if (step9.department.code === HYDRAULICS_CODE) {
    console.log(`  step  9 ${HYDRAULICS_CODE.padEnd(12)} → already there (no change)`);
    return;
  }
  if (step9.department.code !== WIRE_CODE) {
    console.log(
      `  step  9 ${step9.department.code.padEnd(12)} → expected ${WIRE_CODE}, leaving as-is`,
    );
    return;
  }

  await prisma.productionStep.update({
    where: { id: step9.id },
    data: { departmentId: hydraulics.id },
  });
  console.log(`  step  9 ${WIRE_CODE.padEnd(12)} → ${HYDRAULICS_CODE} (status ${step9.status})`);
  console.log(`\n🎉 Done. SO ${TARGET_SO} step 9 re-routed to ${HYDRAULICS_CODE}.`);
}

main()
  .catch((e) => {
    console.error('❌ Fix failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
