// =============================================================================
// BIGFOOT TRAILERS — One-shot: add 'estimate_accepted' to notification_type_enum
//
// The nightly estimate-acceptance reconciliation notifies the office when a
// customer accepts their estimate in QuickBooks. That notification carries
// type 'estimate_accepted', which must exist on the enum before the code can
// write it.
//
// Runs through $executeRawUnsafe so the existing db-seed GitHub Actions
// workflow can apply it on prod. `ADD VALUE IF NOT EXISTS` is idempotent and
// purely additive — existing rows and the running API are unaffected.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log("🔔 Adding 'estimate_accepted' to notification_type_enum (idempotent)...\n");

  // ALTER TYPE ... ADD VALUE cannot run inside a transaction block, and Prisma
  // wraps $executeRaw in one — so use $executeRawUnsafe, which does not.
  await prisma.$executeRawUnsafe(
    `ALTER TYPE notification_type_enum ADD VALUE IF NOT EXISTS 'estimate_accepted';`,
  );

  console.log('  ✅ estimate_accepted present on notification_type_enum');
  console.log('\n🎉 Done. The office can now be notified when an estimate is accepted.');
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
