// =============================================================================
// BIGFOOT TRAILERS — One-shot: sales_orders deposit columns
//
// Records an initial deposit RECEIVED on a trailer (amount + when + method),
// plus the QuickBooks Payment it posted as (qbo_payment_id). Distinct from the
// existing deposit_required (the quoted target). Office/owner/sales record it;
// it shows on the estimate and the trailer.
//
// Runs through $executeRawUnsafe so the existing db-seed workflow can apply it
// on prod. Purely additive (all nullable), so the running API is unaffected and
// it's safe to apply before the code that reads these columns deploys.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('💰 Adding sales_orders deposit columns (idempotent)...\n');

  await prisma.$executeRawUnsafe(`
    ALTER TABLE sales_orders
      ADD COLUMN IF NOT EXISTS deposit_amount NUMERIC(12, 2),
      ADD COLUMN IF NOT EXISTS deposit_paid_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS deposit_method VARCHAR(40),
      ADD COLUMN IF NOT EXISTS qbo_payment_id VARCHAR(50);
  `);

  console.log('  ✅ deposit_amount / deposit_paid_at / deposit_method / qbo_payment_id present');
  console.log('\n🎉 Done. Deposits can now be recorded on estimates/trailers.');
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
