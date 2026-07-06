// =============================================================================
// BIGFOOT TRAILERS — Backfill trailers.sold_at from the audit log
//
// Every trailer already carries a saleStatus, but before we added the
// `soldAt` timestamp column there was no dedicated "when was this sold"
// signal. This backfill fills in soldAt for existing sold trailers so
// Health Check → Sales counts are accurate for historical periods, not
// just sales going forward.
//
// Source of truth (best available, in order):
//   1. audit_log rows with entityType='trailer', entityId=<t.id>, and
//      newValues.saleStatus='sold' — the earliest such row is when the
//      sale was recorded. This is the most reliable signal for sales
//      that flipped after creation.
//   2. Trailer.createdAt — used for trailers that were BORN sold
//      (created with a customerId or soldToName, so the very first
//      saleStatus was 'sold' — a scenario the audit interceptor doesn't
//      always capture, since the sale isn't a separate PATCH but
//      derived from the CREATE body).
//
// Skips: trailers whose soldAt is already set (idempotent re-runs are
// safe) and trailers that aren't currently sold (nothing to backfill).
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-backfill-sold-at
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  console.log('🦬 Backfilling trailers.sold_at from audit log...\n');

  const targets = await prisma.trailer.findMany({
    where: { saleStatus: 'sold', soldAt: null },
    select: { id: true, createdAt: true, soNumber: true },
  });
  console.log(`Found ${targets.length} sold trailers with no soldAt.\n`);

  let fromAudit = 0;
  let fromCreatedAt = 0;
  for (const t of targets) {
    // Find the earliest audit_log row that flipped this trailer's
    // saleStatus to `sold`. Use a raw SQL query — Prisma's `path`
    // filter on JSON works but is fussy about column typing, and this
    // is a one-shot migration where a targeted SQL is clearer.
    const rows = await prisma.$queryRawUnsafe<{ created_at: Date }[]>(
      `SELECT created_at
         FROM audit_log
        WHERE entity_type = 'trailer'
          AND entity_id = $1::bigint
          AND new_values ->> 'saleStatus' = 'sold'
        ORDER BY created_at ASC
        LIMIT 1`,
      t.id.toString(),
    );

    let soldAt: Date;
    if (rows.length > 0) {
      soldAt = rows[0].created_at;
      fromAudit++;
    } else {
      // No audit signal — the sale was set on CREATE (customerId or
      // soldToName in the create body, service derived saleStatus).
      // createdAt is our best proxy.
      soldAt = t.createdAt;
      fromCreatedAt++;
    }

    await prisma.trailer.update({
      where: { id: t.id },
      data: { soldAt },
    });
  }

  console.log(`✅ Backfilled ${targets.length} trailers:`);
  console.log(`   - ${fromAudit} from audit_log (real sale flip)`);
  console.log(`   - ${fromCreatedAt} from createdAt (born sold)\n`);
  console.log('🎉 Done.');
}

main()
  .catch((e) => {
    console.error('❌ Backfill failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
