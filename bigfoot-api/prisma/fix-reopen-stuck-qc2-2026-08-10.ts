// =============================================================================
// BIGFOOT TRAILERS — One-shot: unstick 7049 / 7050 / 7051 (2026-08-10)
//
// These three XP trailers were generated together on 07-20 with a workflow
// glitch: step 4 (QC_2, the finish-weld QC) was created ALREADY marked
// `complete`, with no inspector (completed_by_user_id IS NULL) and
// became_active_at == completed_at (the generation timestamp). That is what
// the app shows as "marked by System".
//
// Consequence: when the real finish weld (step 3, XP_FIN) completed on 08-07,
// the engine had no waiting step to hand off to — QC_2 was already complete —
// so it never cascaded to PAINT_PREP. The trailers ended up `in_production`
// with ZERO active steps: invisible in every department queue, including
// paint prep.
//
// Fix (owner's call): RE-OPEN QC_2 so a real QC inspector signs off on the
// finish weld before paint. For each trailer we flip its system-completed QC_2
// step back to `active` (mirroring production.service's activation:
// status=active, becameActiveAt=now, queuePosition = dept max + 1), clearing
// the bogus completion. When the inspector passes it, the normal flow advances
// PAINT_PREP as designed.
//
// Idempotent + safe:
//   - Only acts on a trailer that still has 0 active steps (i.e. still stuck).
//   - Only re-opens a step matching the exact glitch signature: a QC-department
//     step that is `complete`, has NULL completed_by_user_id, and whose
//     became_active_at equals completed_at. Once re-opened it no longer
//     matches, so re-runs are no-ops.
//   - Every change writes an audit_log row.
//
// Run:  gh workflow run db-seed.yml -f script=fix-reopen-stuck-qc2-2026-08-10
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DRY_RUN = process.env['DRY_RUN'] === 'true';
const TARGET_SOS = ['7049', '7050', '7051'];

async function main(): Promise<void> {
  console.log(
    `🩹 Re-opening system-completed QC_2 on ${TARGET_SOS.join(', ')}` +
      `${DRY_RUN ? ' (DRY RUN — nothing written)' : ''}\n`,
  );

  let reopened = 0;

  for (const so of TARGET_SOS) {
    const trailer = await prisma.trailer.findUnique({
      where: { soNumber: so },
      select: { id: true, status: true },
    });
    if (!trailer) {
      console.log(`  ⚠️  SO ${so} not found — skipping`);
      continue;
    }

    // Guard: only touch trailers that are still stuck (no active step).
    const activeCount = await prisma.productionStep.count({
      where: { trailerId: trailer.id, status: 'active' },
    });
    if (activeCount > 0) {
      console.log(`  ✓ SO ${so} already has an active step — nothing to fix (skip)`);
      continue;
    }

    // Find the glitched step: a QC-department step, `complete`, with no
    // inspector, stamped at generation (became_active_at == completed_at).
    const glitched = await prisma.productionStep.findFirst({
      where: {
        trailerId: trailer.id,
        status: 'complete',
        completedByUserId: null,
        department: { code: { startsWith: 'QC' } },
      },
      select: {
        id: true,
        departmentId: true,
        stepOrder: true,
        becameActiveAt: true,
        completedAt: true,
        department: { select: { code: true } },
      },
    });

    if (
      !glitched ||
      !glitched.becameActiveAt ||
      !glitched.completedAt ||
      glitched.becameActiveAt.getTime() !== glitched.completedAt.getTime()
    ) {
      console.log(
        `  ⚠️  SO ${so}: no system-completed QC step matching the glitch — skipping`,
      );
      continue;
    }

    // Next queue position for that QC department (append to its active queue).
    const maxPos = await prisma.productionStep.aggregate({
      where: { departmentId: glitched.departmentId, status: 'active' },
      _max: { queuePosition: true },
    });
    const nextPos = (maxPos._max.queuePosition ?? 0) + 1;

    console.log(
      `  → SO ${so}: re-opening step ${glitched.stepOrder} ` +
        `(${glitched.department.code}) → active @ queue ${nextPos}`,
    );

    if (DRY_RUN) {
      reopened++;
      continue;
    }

    await prisma.$transaction(async (tx) => {
      await tx.productionStep.update({
        where: { id: glitched.id },
        data: {
          status: 'active',
          becameActiveAt: new Date(),
          queuePosition: nextPos,
          completedAt: null,
          completedByUserId: null,
          pointsAwarded: 0,
        },
      });

      await tx.auditLog.create({
        data: {
          entityType: 'trailer',
          entityId: trailer.id,
          action: 'production.qc_reopened',
          oldValues: {
            soNumber: so,
            stepOrder: glitched.stepOrder,
            department: glitched.department.code,
            stepStatus: 'complete',
            completedBy: 'system (auto-generated)',
            reason:
              'QC_2 was auto-completed at workflow generation (07-20) with no ' +
              'inspector, leaving the trailer with no active step after finish weld.',
          },
          newValues: {
            stepStatus: 'active',
            queuePosition: nextPos,
            note: 'Re-opened for a real finish-weld QC inspection before paint prep.',
          },
        },
      });
    });

    reopened++;
    console.log(`  ✅ SO ${so}: QC_2 re-opened — now in the QC queue`);
  }

  console.log(
    `\n🎉 Done. ${reopened} trailer(s) ${DRY_RUN ? 'would be' : ''} re-opened at QC_2.`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Fix failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
