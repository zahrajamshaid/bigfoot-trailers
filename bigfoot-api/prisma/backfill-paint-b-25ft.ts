// =============================================================================
// BIGFOOT TRAILERS — Migrate ≥25ft trailers off PAINT_A to PAINT_B
//
// PAINT_A is the smaller booth and physically only fits trailers under 25ft.
// Going forward the workflow generator enforces this on create, but existing
// production_steps assigned to PAINT_A on tall trailers need to be shifted.
//
// Strategy: find every production_step whose department is PAINT_A AND whose
// trailer's parsed size_ft is ≥ 25; update those rows to point at PAINT_B.
// Status / queuePosition / timestamps are preserved — only the routing
// changes. Re-running is a no-op (the SQL filter excludes rows already on
// PAINT_B).
//
// Run via the seed workflow:
//   gh workflow run "DB · Seed (manual)" --field script=backfill-paint-b-25ft
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

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

  // Parse size_ft as a float, extracting the leading number. Anything that
  // doesn't parse (NULL or garbage) stays where it is — we only move rows we
  // can prove are ≥25ft.
  const updated = await prisma.$executeRawUnsafe(
    `UPDATE production_steps ps
        SET department_id = $1
       FROM trailers t
      WHERE ps.trailer_id     = t.id
        AND ps.department_id  = $2
        AND t.size_ft IS NOT NULL
        AND (substring(t.size_ft FROM '^[0-9]+(\\.[0-9]+)?'))::numeric >= 25`,
    paintB.id,
    paintA.id,
  );
  console.log(`✅ Shifted ${updated} production_step row(s) from PAINT_A → PAINT_B.`);
}

main()
  .catch((e) => {
    console.error('❌ Backfill failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
