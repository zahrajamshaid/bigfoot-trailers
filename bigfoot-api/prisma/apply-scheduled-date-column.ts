// =============================================================================
// BIGFOOT TRAILERS — One-shot: add deliveries.scheduled_date column
//
// Mirrors prisma/sql-patches/2026-06-03_add_delivery_scheduled_date.sql, but
// runs through Prisma's $executeRawUnsafe so the existing db-seed GitHub
// Actions workflow (which only invokes .ts scripts) can apply it on prod.
//
// Idempotent: both statements use IF NOT EXISTS.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🗓️  Adding deliveries.scheduled_date column (idempotent)...\n');

  await prisma.$executeRawUnsafe(
    `ALTER TABLE deliveries ADD COLUMN IF NOT EXISTS scheduled_date DATE;`,
  );
  console.log('  ✅ deliveries.scheduled_date column present');

  await prisma.$executeRawUnsafe(
    `CREATE INDEX IF NOT EXISTS idx_deliveries_scheduled_date
       ON deliveries (scheduled_date)
       WHERE scheduled_date IS NOT NULL;`,
  );
  console.log('  ✅ idx_deliveries_scheduled_date present');

  console.log('\n🎉 Done. Delivery rows can now carry a scheduledDate.');
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
