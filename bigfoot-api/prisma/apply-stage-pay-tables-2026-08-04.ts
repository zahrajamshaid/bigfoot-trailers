// =============================================================================
// BIGFOOT TRAILERS -- Stage-pay engine tables + history backfill (2026-08-04)
//
// Creates stage_crew_members (fixed crew roster per split stage) and
// production_step_payouts (per-worker pay per step), then backfills a 'base'
// payout for every already-completed, paid, non-rework step so the payout-
// driven weekly report still shows historical weeks. All idempotent.
//
// Run:  gh workflow run db-seed.yml -f script=apply-stage-pay-tables-2026-08-04
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';
import { Prisma } from '@prisma/client';

const prisma = createPrismaClient();

const DDL: Array<{ label: string; sql: string }> = [
  {
    label: 'stage_crew_members table',
    sql: `CREATE TABLE IF NOT EXISTS stage_crew_members (
      id            SERIAL PRIMARY KEY,
      department_id INT NOT NULL REFERENCES departments(id),
      slot          SMALLINT NOT NULL,
      user_id       BIGINT NOT NULL REFERENCES users(id),
      created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (department_id, slot)
    );`,
  },
  {
    label: 'idx stage_crew_members dept',
    sql: `CREATE INDEX IF NOT EXISTS idx_stage_crew_members_dept ON stage_crew_members (department_id);`,
  },
  {
    label: 'production_step_payouts table',
    sql: `CREATE TABLE IF NOT EXISTS production_step_payouts (
      id                 BIGSERIAL PRIMARY KEY,
      production_step_id BIGINT NOT NULL REFERENCES production_steps(id) ON DELETE CASCADE,
      user_id            BIGINT NOT NULL REFERENCES users(id),
      dollars            NUMERIC(10,2) NOT NULL,
      kind               VARCHAR(20) NOT NULL,
      note               VARCHAR(160),
      created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
    );`,
  },
  {
    label: 'idx payouts user',
    sql: `CREATE INDEX IF NOT EXISTS idx_production_step_payouts_user ON production_step_payouts (user_id);`,
  },
  {
    label: 'idx payouts step',
    sql: `CREATE INDEX IF NOT EXISTS idx_production_step_payouts_step ON production_step_payouts (production_step_id);`,
  },
];

async function main(): Promise<void> {
  console.log('Creating stage-pay tables...');
  for (const { label, sql } of DDL) {
    await prisma.$executeRawUnsafe(sql);
    console.log(`  ok: ${label}`);
  }

  // Backfill: base payout for each completed, paid, non-rework step lacking one.
  const steps = await prisma.productionStep.findMany({
    where: {
      status: 'complete',
      isRework: false,
      completedByUserId: { not: null },
      pointsAwarded: { gt: 0 },
      payouts: { none: {} },
    },
    select: { id: true, completedByUserId: true, pointsAwarded: true },
  });
  console.log(`Backfilling ${steps.length} historical step payouts...`);

  let done = 0;
  const CHUNK = 500;
  for (let i = 0; i < steps.length; i += CHUNK) {
    const batch = steps.slice(i, i + CHUNK);
    await prisma.productionStepPayout.createMany({
      data: batch.map((s) => ({
        productionStepId: s.id,
        userId: s.completedByUserId!,
        dollars: new Prisma.Decimal(s.pointsAwarded),
        kind: 'base',
        note: 'backfill (pre-payout completion)',
      })),
    });
    done += batch.length;
  }
  console.log(`Done. Backfilled ${done} payouts.`);
}

main()
  .catch((e) => { console.error('Failed:', e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); });
