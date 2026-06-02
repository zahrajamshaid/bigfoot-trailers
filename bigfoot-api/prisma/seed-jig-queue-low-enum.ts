// =============================================================================
// BIGFOOT TRAILERS — Ensure NotificationType has 'jig_queue_low'
//
// api-deploy doesn't run `prisma db push`, so on prod the enum value
// needs to be added via raw SQL. This one-shot is safe to run repeatedly
// — IF NOT EXISTS clause makes it a no-op once the value is present.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main(): Promise<void> {
  await prisma.$executeRawUnsafe(
    `ALTER TYPE notification_type_enum ADD VALUE IF NOT EXISTS 'jig_queue_low';`,
  );
  console.log("✅ notification_type_enum has 'jig_queue_low'");
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
