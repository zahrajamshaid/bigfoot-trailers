// =============================================================================
// BIGFOOT TRAILERS — One-shot: add trailers.intended_stock_location_id column
//
// Mirrors prisma/sql-patches/2026-06-15_add_trailer_intended_stock_location.sql.
// Runs through Prisma's $executeRawUnsafe so the existing db-seed GitHub
// Actions workflow can apply it on prod without psql.
//
// Idempotent: column add + FK add + index add are all guarded.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🏷️  Adding trailers.intended_stock_location_id column (idempotent)...\n');

  await prisma.$executeRawUnsafe(
    `ALTER TABLE trailers ADD COLUMN IF NOT EXISTS intended_stock_location_id INT;`,
  );
  console.log('  ✅ trailers.intended_stock_location_id column present');

  await prisma.$executeRawUnsafe(`
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM information_schema.table_constraints
        WHERE constraint_name = 'trailers_intended_stock_location_id_fkey'
          AND table_name = 'trailers'
      ) THEN
        ALTER TABLE trailers
          ADD CONSTRAINT trailers_intended_stock_location_id_fkey
          FOREIGN KEY (intended_stock_location_id) REFERENCES locations(id);
      END IF;
    END $$;
  `);
  console.log('  ✅ FK to locations present');

  await prisma.$executeRawUnsafe(
    `CREATE INDEX IF NOT EXISTS idx_trailers_intended_stock_location
       ON trailers (intended_stock_location_id);`,
  );
  console.log('  ✅ idx_trailers_intended_stock_location present');

  console.log('\n🎉 Done. Stock builds can now record their intended destination yard.');
}

main()
  .catch((e) => {
    console.error('❌ Migration failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
