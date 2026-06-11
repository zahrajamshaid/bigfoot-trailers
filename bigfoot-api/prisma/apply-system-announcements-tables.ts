// =============================================================================
// BIGFOOT TRAILERS — One-shot: create system_announcements + acks tables
//
// Mirrors prisma/sql-patches/2026-06-11_add_system_announcements.sql but
// runs through Prisma's $executeRawUnsafe so the existing db-seed Actions
// workflow can apply it on prod. Idempotent — re-runs are no-ops.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const STATEMENTS = [
  `CREATE TABLE IF NOT EXISTS system_announcements (
     id                BIGSERIAL PRIMARY KEY,
     title             VARCHAR(120),
     body              TEXT        NOT NULL,
     posted_by_user_id BIGINT      NOT NULL REFERENCES users(id),
     is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
     expires_at        TIMESTAMPTZ,
     created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
   )`,
  `CREATE INDEX IF NOT EXISTS idx_announcements_active_oldest
     ON system_announcements (is_active, created_at)`,
  `CREATE TABLE IF NOT EXISTS system_announcement_acks (
     id              BIGSERIAL PRIMARY KEY,
     announcement_id BIGINT      NOT NULL REFERENCES system_announcements(id) ON DELETE CASCADE,
     user_id         BIGINT      NOT NULL REFERENCES users(id),
     acked_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
   )`,
  `CREATE UNIQUE INDEX IF NOT EXISTS uq_announcement_ack_per_user
     ON system_announcement_acks (announcement_id, user_id)`,
  `CREATE INDEX IF NOT EXISTS idx_announcement_acks_user
     ON system_announcement_acks (user_id, acked_at DESC)`,
];

async function main(): Promise<void> {
  console.log('📣 Creating system_announcements + acks (idempotent)...\n');
  for (const sql of STATEMENTS) {
    const label = sql.split(/\s+/, 6).slice(2, 4).join(' ');
    await prisma.$executeRawUnsafe(sql);
    console.log(`  ✅ ${label}`);
  }
  console.log('\n🎉 Done. Owner/production-manager can now post announcements.');
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
