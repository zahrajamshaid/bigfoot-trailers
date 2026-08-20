// =============================================================================
// BIGFOOT TRAILERS — One-shot: create payroll_adjustments table (idempotent)
//
// Backs manual payroll line-items (bonus / correction / deduction) a manager
// adds to a worker's week. Rolls into the weekly report total alongside the
// computed step payouts. Soft-voided (voided_at) rather than deleted.
//
// Run:  gh workflow run db-seed.yml -f script=apply-payroll-adjustments-table
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('💵 Creating payroll_adjustments (idempotent)...\n');

  await prisma.$executeRawUnsafe(`
    CREATE TABLE IF NOT EXISTS payroll_adjustments (
      id                 BIGSERIAL PRIMARY KEY,
      user_id            BIGINT NOT NULL REFERENCES users(id),
      effective_date     DATE NOT NULL,
      dollars            NUMERIC(10,2) NOT NULL,
      note               VARCHAR(200) NOT NULL,
      created_by_user_id BIGINT NOT NULL REFERENCES users(id),
      created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
      voided_at          TIMESTAMPTZ,
      voided_by_user_id  BIGINT REFERENCES users(id)
    );
  `);
  console.log('  ✅ table payroll_adjustments present');

  await prisma.$executeRawUnsafe(
    `CREATE INDEX IF NOT EXISTS idx_payroll_adjustments_date
       ON payroll_adjustments (effective_date);`,
  );
  await prisma.$executeRawUnsafe(
    `CREATE INDEX IF NOT EXISTS idx_payroll_adjustments_user_date
       ON payroll_adjustments (user_id, effective_date);`,
  );
  console.log('  ✅ indexes present');

  console.log('\n🎉 Done. Managers can now add manual payroll line-items.');
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
