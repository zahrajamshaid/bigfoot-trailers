// =============================================================================
// BIGFOOT TRAILERS — Strip "ft" suffix from trailer.size_ft
//
// All four of this session's seeds wrote sizeFt like "20ft" because the
// extractor surfaced a length number and the seeds appended "ft". The UI
// formats with `${size}ft` already (queue_screen, step_completion_dialog),
// so seeded trailers render "20ftft".
//
// One-shot cleanup: trim a single trailing "ft" / "FT" off any row that
// has one. Leaves rows like "20" alone. Run once after the seed scripts
// are patched; re-running is a no-op.
//
//   npx tsx prisma/backfill-size-ft-suffix.ts
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🩹 Stripping trailing "ft" suffix from trailers.size_ft...\n');
  // regexp_replace with anchored 'ft' so we only strip ONE trailing suffix
  // and leave non-matching values untouched.
  const updated = await prisma.$executeRawUnsafe(
    `UPDATE trailers
        SET size_ft = regexp_replace(size_ft, '(?i)ft\\s*$', '')
      WHERE size_ft ~* 'ft\\s*$'`,
  );
  console.log(`✅ Updated ${updated} row(s).`);
}

main()
  .catch((e) => {
    console.error('❌ Backfill failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
