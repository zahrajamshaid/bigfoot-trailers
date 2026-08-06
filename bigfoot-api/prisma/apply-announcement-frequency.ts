// =============================================================================
// BIGFOOT TRAILERS — One-shot: add system_announcements.frequency column
//
// Backs the announcement recurrence feature: an announcement can now re-appear
// for a user on every login, once per day, or once per week (default is the
// original behaviour — show once until acked).
//
// Runs through Prisma's $executeRawUnsafe so the existing db-seed GitHub
// Actions workflow (which only invokes .ts scripts) can apply it on prod.
//
// Idempotent: ADD COLUMN IF NOT EXISTS.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('📣 Adding system_announcements.frequency column (idempotent)...\n');

  await prisma.$executeRawUnsafe(
    `ALTER TABLE system_announcements
       ADD COLUMN IF NOT EXISTS frequency VARCHAR(16) NOT NULL DEFAULT 'once';`,
  );
  console.log("  ✅ system_announcements.frequency present (default 'once')");

  console.log('\n🎉 Done. Announcements can now recur per login / daily / weekly.');
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
