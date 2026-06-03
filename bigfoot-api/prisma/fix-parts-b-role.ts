// =============================================================================
// BIGFOOT TRAILERS — One-shot: change parts_b@bigfoot.dev role to `parts`
//
// The account was created via the admin UI before the mobile role dropdown
// exposed the `parts` option, so it landed as `worker` (the default). This
// flips the row to the correct role.
//
// Idempotent: re-running after the change is a no-op.
// =============================================================================

import 'dotenv/config';
import { UserRole } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const TARGET_EMAIL = 'parts_b@bigfoot.dev';

async function main(): Promise<void> {
  const user = await prisma.user.findUnique({
    where: { email: TARGET_EMAIL },
    select: { id: true, email: true, fullName: true, role: true },
  });
  if (!user) throw new Error(`User ${TARGET_EMAIL} not found.`);

  console.log(`📋 ${user.email} (${user.fullName}) — current role: ${user.role}`);

  if (user.role === UserRole.parts) {
    console.log('  Already `parts` — no change.');
    return;
  }

  await prisma.user.update({
    where: { id: user.id },
    data: { role: UserRole.parts },
  });
  console.log(`  Role updated: ${user.role} → ${UserRole.parts}`);
  console.log(`\n🎉 Done.`);
}

main()
  .catch((e) => {
    console.error('❌ Role fix failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
