// =============================================================================
// BIGFOOT TRAILERS — Additive migration: support / problem-report tables
//
// Creates support_tickets + support_ticket_messages and the
// support_ticket_status_enum, and adds the `support_message` value to the
// notification_type_enum. All idempotent (IF NOT EXISTS / ADD VALUE IF NOT
// EXISTS) so it's safe to run against prod through the db-seed Action and safe
// to re-run.
//
// Run:  gh workflow run db-seed.yml -f script=apply-support-tables-2026-08-04
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const statements: Array<{ label: string; sql: string }> = [
  {
    label: 'support_ticket_status_enum',
    sql: `DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'support_ticket_status_enum') THEN
        CREATE TYPE support_ticket_status_enum AS ENUM ('open', 'resolved');
      END IF;
    END $$;`,
  },
  {
    label: 'notification_type_enum += support_message',
    // ALTER TYPE ... ADD VALUE can't run inside a transaction block; run bare.
    sql: `ALTER TYPE notification_type_enum ADD VALUE IF NOT EXISTS 'support_message';`,
  },
  {
    label: 'support_tickets table',
    sql: `CREATE TABLE IF NOT EXISTS support_tickets (
      id               BIGSERIAL PRIMARY KEY,
      reporter_user_id BIGINT NOT NULL REFERENCES users(id),
      subject          VARCHAR(160) NOT NULL,
      status           support_ticket_status_enum NOT NULL DEFAULT 'open',
      created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
    );`,
  },
  {
    label: 'idx_support_tickets_status_updated',
    sql: `CREATE INDEX IF NOT EXISTS idx_support_tickets_status_updated
      ON support_tickets (status, updated_at DESC);`,
  },
  {
    label: 'idx_support_tickets_reporter',
    sql: `CREATE INDEX IF NOT EXISTS idx_support_tickets_reporter
      ON support_tickets (reporter_user_id, updated_at DESC);`,
  },
  {
    label: 'support_ticket_messages table',
    sql: `CREATE TABLE IF NOT EXISTS support_ticket_messages (
      id             BIGSERIAL PRIMARY KEY,
      ticket_id      BIGINT NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
      sender_user_id BIGINT NOT NULL REFERENCES users(id),
      body           TEXT NOT NULL,
      created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
    );`,
  },
  {
    label: 'idx_support_messages_ticket',
    sql: `CREATE INDEX IF NOT EXISTS idx_support_messages_ticket
      ON support_ticket_messages (ticket_id, created_at);`,
  },
];

async function main(): Promise<void> {
  console.log('🛟 Creating support ticket tables (idempotent)...\n');
  for (const { label, sql } of statements) {
    await prisma.$executeRawUnsafe(sql);
    console.log(`  ✅ ${label}`);
  }
  console.log('\n🎉 Done. Users can report problems; owner/office/PM get them.');
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
