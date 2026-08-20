// =============================================================================
// BIGFOOT TRAILERS — One-shot: create user_activity_daily table (idempotent)
//
// Backs the admin "User Activity" screen — daily active users + how long each
// person actually used the app that day. Fed by a ~60s foreground heartbeat.
//
// Additive + idempotent: CREATE TABLE / INDEX IF NOT EXISTS.
// Run:  gh workflow run db-seed.yml -f script=apply-user-activity-table
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('📈 Creating user_activity_daily (idempotent)...\n');

  await prisma.$executeRawUnsafe(`
    CREATE TABLE IF NOT EXISTS user_activity_daily (
      id             BIGSERIAL PRIMARY KEY,
      user_id        BIGINT NOT NULL REFERENCES users(id),
      day            DATE NOT NULL,
      first_seen_at  TIMESTAMPTZ NOT NULL,
      last_seen_at   TIMESTAMPTZ NOT NULL,
      active_seconds INTEGER NOT NULL DEFAULT 0,
      ping_count     INTEGER NOT NULL DEFAULT 0
    );
  `);
  console.log('  ✅ table user_activity_daily present');

  await prisma.$executeRawUnsafe(
    `CREATE UNIQUE INDEX IF NOT EXISTS uq_user_activity_day
       ON user_activity_daily (user_id, day);`,
  );
  console.log('  ✅ unique index (user_id, day) present');

  await prisma.$executeRawUnsafe(
    `CREATE INDEX IF NOT EXISTS idx_user_activity_day
       ON user_activity_daily (day);`,
  );
  console.log('  ✅ index (day) present');

  console.log('\n🎉 Done. Heartbeats can now roll up daily usage.');
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
