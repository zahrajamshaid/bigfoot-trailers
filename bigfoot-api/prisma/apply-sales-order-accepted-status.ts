// =============================================================================
// BIGFOOT TRAILERS — One-shot: add 'accepted' to sales_order_status_enum
//
// When an estimate is converted to a Sales Order it now moves to ACCEPTED
// (was in_production — but "in production" is the trailer's job, not the
// estimate's). Adds the enum value and re-labels any existing converted rows.
//
// Runs through $executeRawUnsafe so the existing db-seed workflow can apply it.
// Purely additive + a corrective re-label; safe to run before the code deploys.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log("✅ Adding 'accepted' to sales_order_status_enum (idempotent)...\n");

  // ADD VALUE cannot run in a transaction, and must commit before it can be
  // used — so it's its own $executeRawUnsafe (no transaction wrapping), and the
  // re-label below runs as a separate, later statement.
  await prisma.$executeRawUnsafe(
    `ALTER TYPE sales_order_status_enum ADD VALUE IF NOT EXISTS 'accepted' AFTER 'approved';`,
  );
  console.log('  ✅ accepted present on sales_order_status_enum');

  // Existing converted estimates carried status=in_production; re-label them so
  // old and new conversions read the same.
  const relabelled = await prisma.$executeRawUnsafe(
    `UPDATE sales_orders SET status = 'accepted' WHERE status = 'in_production';`,
  );
  console.log(`  ✅ re-labelled ${relabelled} converted estimate(s) in_production → accepted`);

  console.log('\n🎉 Done. Converting an estimate now shows it as Accepted.');
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
