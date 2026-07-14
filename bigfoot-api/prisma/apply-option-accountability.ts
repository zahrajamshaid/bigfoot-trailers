// =============================================================================
// BIGFOOT TRAILERS — One-shot: option accountability tables
//
// Options are the #1 source of rebuilds: one gets added after the trailer is
// already past weld, nobody tells the department that has to fit it, and the
// trailer is finished wrong. This migration adds the columns that close it:
//
//   trailer_addons.*            — who added it, and whether it landed AFTER the
//                                 build had already started (and at which step),
//                                 so it can surface on the PM dashboard.
//   trailer_addon_departments   — one row per (option, department) that has to
//                                 fit it, carrying that department's OWN
//                                 acknowledgement. An option can need more than
//                                 one department, and each acknowledges
//                                 independently.
//
// Runs through $executeRawUnsafe so the existing db-seed GitHub Actions
// workflow (which only invokes .ts scripts) can apply it on prod.
//
// Idempotent: every statement is IF NOT EXISTS. Purely ADDITIVE — every new
// column is nullable or defaulted, so the currently-deployed API keeps working
// unchanged. Safe to run BEFORE the API deploy (and it must be: the new code
// reads these columns).
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🔧 Adding option-accountability columns + tables (idempotent)...\n');

  // ── 1. trailer_addons — provenance + production-manager review ────────────
  await prisma.$executeRawUnsafe(`
    ALTER TABLE trailer_addons
      ADD COLUMN IF NOT EXISTS added_by_user_id BIGINT REFERENCES users (id),
      ADD COLUMN IF NOT EXISTS added_during_production BOOLEAN NOT NULL DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS added_at_step_order INTEGER,
      ADD COLUMN IF NOT EXISTS added_at_department_id INTEGER REFERENCES departments (id),
      ADD COLUMN IF NOT EXISTS pm_acknowledged_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS pm_acknowledged_by_user_id BIGINT REFERENCES users (id);
  `);
  console.log('  ✅ trailer_addons: provenance + PM-review columns present');

  await prisma.$executeRawUnsafe(
    `CREATE INDEX IF NOT EXISTS idx_trailer_addons_trailer
       ON trailer_addons (trailer_id);`,
  );
  // Drives the "Options Added Mid-Build" dashboard box.
  await prisma.$executeRawUnsafe(
    `CREATE INDEX IF NOT EXISTS idx_trailer_addons_pending_ack
       ON trailer_addons (added_during_production, pm_acknowledged_at);`,
  );
  console.log('  ✅ trailer_addons indexes present');

  // ── 2. trailer_addon_departments — who fits it, and did they acknowledge ──
  await prisma.$executeRawUnsafe(`
    CREATE TABLE IF NOT EXISTS trailer_addon_departments (
      id                      BIGSERIAL PRIMARY KEY,
      addon_id                BIGINT  NOT NULL REFERENCES trailer_addons (id) ON DELETE CASCADE,
      department_id           INTEGER NOT NULL REFERENCES departments (id),
      acknowledged_at         TIMESTAMPTZ,
      acknowledged_by_user_id BIGINT  REFERENCES users (id)
    );
  `);
  console.log('  ✅ trailer_addon_departments table present');

  // Acknowledging twice is a no-op, not a duplicate row.
  await prisma.$executeRawUnsafe(
    `CREATE UNIQUE INDEX IF NOT EXISTS uq_addon_department
       ON trailer_addon_departments (addon_id, department_id);`,
  );
  await prisma.$executeRawUnsafe(
    `CREATE INDEX IF NOT EXISTS idx_addon_dept_pending
       ON trailer_addon_departments (department_id, acknowledged_at);`,
  );
  console.log('  ✅ trailer_addon_departments indexes present');

  // ── 3. Report what the existing rows look like ────────────────────────────
  // Every option that predates this migration keeps added_during_production =
  // FALSE and has no department rows, so it blocks nobody and shows up on
  // nobody's dashboard. The accountability starts with the NEXT option added.
  const [{ count: legacyAddons }] = await prisma.$queryRawUnsafe<
    { count: bigint }[]
  >(`SELECT COUNT(*)::bigint AS count FROM trailer_addons;`);

  console.log(
    `\n📋 ${legacyAddons} existing option(s) left untouched — no department ` +
      `assignments, not flagged mid-build, so they block no steps.`,
  );
  console.log('\n🎉 Done. New options can now be assigned to departments and acknowledged.');
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
