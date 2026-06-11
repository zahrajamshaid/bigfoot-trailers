// =============================================================================
// BIGFOOT TRAILERS — Migrate ≥20ft trailers off PAINT_A to PAINT_B
//
// The paint booth physical constraint dropped from 25ft to 20ft on the floor,
// so the workflow generator now routes any trailer ≥20ft to PAINT_B from
// creation forward. This script retro-applies the new rule to trailers
// already in flight: every production_step still pointing at PAINT_A whose
// trailer's parsed size is ≥20ft is shifted to PAINT_B.
//
// Status guard: only `waiting` and `active` steps are touched. `complete`
// steps stay where they are because the trailer was *physically* painted
// at PAINT_A — re-routing the historical row would silently rewrite the
// audit trail.
//
// Idempotent: re-runs after the first pass are no-ops because the filter
// excludes any row already pointing at PAINT_B.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const THRESHOLD_FT = 20;

async function main(): Promise<void> {
  const paintA = await prisma.department.findUnique({
    where: { code: 'PAINT_A' },
    select: { id: true },
  });
  const paintB = await prisma.department.findUnique({
    where: { code: 'PAINT_B' },
    select: { id: true },
  });
  if (!paintA || !paintB) {
    throw new Error('PAINT_A or PAINT_B department missing — base seed first.');
  }

  // Audit pass — print the trailers that will move so the run log doubles
  // as a paper trail.
  const candidates = await prisma.$queryRawUnsafe<
    Array<{ step_id: string; so_number: string; size_ft: string; status: string }>
  >(
    `SELECT ps.id::text AS step_id,
            t.so_number,
            t.size_ft,
            ps.status::text AS status
       FROM production_steps ps
       JOIN trailers t ON t.id = ps.trailer_id
      WHERE ps.department_id = $1
        AND ps.status IN ('waiting', 'active')
        AND t.size_ft IS NOT NULL
        AND (substring(t.size_ft FROM '^[0-9]+(\\.[0-9]+)?'))::numeric >= ${THRESHOLD_FT}
      ORDER BY t.so_number`,
    paintA.id,
  );

  console.log(
    `🎨 Shifting ${candidates.length} PAINT_A step(s) → PAINT_B (size ≥${THRESHOLD_FT}ft)\n`,
  );
  for (const row of candidates) {
    console.log(
      `  SO ${row.so_number.padEnd(8)} step=${row.step_id.padEnd(6)} size=${row.size_ft.padEnd(8)} status=${row.status}`,
    );
  }

  if (candidates.length === 0) {
    console.log('  (no rows match — nothing to do)');
    return;
  }

  const moved = await prisma.$executeRawUnsafe(
    `UPDATE production_steps ps
        SET department_id = $1
       FROM trailers t
      WHERE ps.trailer_id     = t.id
        AND ps.department_id  = $2
        AND ps.status IN ('waiting', 'active')
        AND t.size_ft IS NOT NULL
        AND (substring(t.size_ft FROM '^[0-9]+(\\.[0-9]+)?'))::numeric >= ${THRESHOLD_FT}`,
    paintB.id,
    paintA.id,
  );

  console.log(
    `\n🎉 Done. Shifted ${moved} production_step row(s) from PAINT_A → PAINT_B.`,
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
