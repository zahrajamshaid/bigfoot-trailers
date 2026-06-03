// =============================================================================
// BIGFOOT TRAILERS — Backfill: trailers >24ft on WIRE step → HYDRAULICS
//
// New policy: XP/Yeti/Deck-Over trailers strictly over 24ft now route step 9
// to HYDRAULICS instead of WIRE (workflow-generator.service.ts already does
// this for newly created trailers). This script retro-applies the rule to
// every in-flight trailer that was created before the policy went live.
//
// Scope:
//   • Series = xp | yeti | deck_over (gooseneck templates already point at
//     HYDRAULICS, no override needed and we leave them alone).
//   • trailer.sizeFt parses to a number strictly greater than 24.
//   • The trailer's step_order=9 production_step is currently WIRE AND
//     status = waiting. We deliberately skip `active` (someone is mid-step
//     — don't yank them) and `complete` (work already done, can't undo).
//
// Idempotent: re-runs touch zero rows once the backfill has settled.
// =============================================================================

import 'dotenv/config';
import { ProductionStepStatus, TrailerSeries } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const WIRE_CODE = 'WIRE';
const HYDRAULICS_CODE = 'HYDRAULICS';
const WIRE_MAX_FT = 24;

const TARGET_SERIES: TrailerSeries[] = [
  TrailerSeries.xp,
  TrailerSeries.yeti,
  TrailerSeries.deck_over,
];

function parseSizeFt(sizeFt: string | null | undefined): number | null {
  if (!sizeFt) return null;
  const m = String(sizeFt).match(/(\d+(?:\.\d+)?)/);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) ? n : null;
}

async function main(): Promise<void> {
  console.log(`🔄 Backfilling WIRE → HYDRAULICS for non-gooseneck trailers >${WIRE_MAX_FT}ft\n`);

  const [wireDept, hydraulicsDept] = await Promise.all([
    prisma.department.findFirst({ where: { code: WIRE_CODE }, select: { id: true } }),
    prisma.department.findFirst({ where: { code: HYDRAULICS_CODE }, select: { id: true } }),
  ]);
  if (!wireDept) throw new Error(`Department ${WIRE_CODE} missing.`);
  if (!hydraulicsDept) throw new Error(`Department ${HYDRAULICS_CODE} missing.`);

  // All non-gooseneck trailers with a sizeFt set. We filter by length in JS
  // because sizeFt is a free-form string column (e.g., "28ft", "24.5").
  const trailers = await prisma.trailer.findMany({
    where: {
      sizeFt: { not: null },
      trailerModel: { series: { in: TARGET_SERIES } },
    },
    select: {
      id: true,
      soNumber: true,
      sizeFt: true,
      trailerModel: { select: { series: true } },
    },
  });

  console.log(`📋 Scanning ${trailers.length} non-gooseneck trailer(s) with a sizeFt.\n`);

  let moved = 0;
  let skippedTooShort = 0;
  let skippedNotWire = 0;
  let skippedActiveOrDone = 0;
  let skippedNoStep9 = 0;

  for (const t of trailers) {
    const lengthFt = parseSizeFt(t.sizeFt);
    if (lengthFt === null || lengthFt <= WIRE_MAX_FT) {
      skippedTooShort++;
      continue;
    }

    const step9 = await prisma.productionStep.findFirst({
      where: { trailerId: t.id, stepOrder: 9 },
      select: {
        id: true,
        status: true,
        departmentId: true,
        department: { select: { code: true } },
      },
    });
    if (!step9) {
      skippedNoStep9++;
      continue;
    }
    if (step9.department.code !== WIRE_CODE) {
      skippedNotWire++;
      continue;
    }
    if (step9.status !== ProductionStepStatus.waiting) {
      skippedActiveOrDone++;
      console.log(
        `  SO ${t.soNumber.padEnd(6)} (${t.sizeFt}, ${t.trailerModel.series}) → WIRE step is ${step9.status}, skipping`,
      );
      continue;
    }

    await prisma.productionStep.update({
      where: { id: step9.id },
      data: { departmentId: hydraulicsDept.id },
    });
    moved++;
    console.log(
      `  SO ${t.soNumber.padEnd(6)} (${t.sizeFt}, ${t.trailerModel.series}) → WIRE → HYDRAULICS`,
    );
  }

  console.log(
    `\n🎉 Done. ${moved} moved, ${skippedActiveOrDone} skipped (active/complete), ${skippedNotWire} skipped (not WIRE), ${skippedNoStep9} skipped (no step 9), ${skippedTooShort} skipped (≤${WIRE_MAX_FT}ft or unparseable).`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Backfill failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
