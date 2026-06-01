// =============================================================================
// BIGFOOT TRAILERS — Parts dev login
//
// Adds the new `parts` role enum value and creates a dev login
//   parts@bigfoot.dev / Dev1234!
// with the four jig departments wired in as extra departments:
//
//   primary           XP_JIG
//   extras            YETI_JIG, DO_JIG, GN_WELD
//
// Same multi-department pattern used for paint-master / wire-hyd-master
// accounts — the queue screen renders the primary + extras together so the
// parts person sees all jig work in one view.
//
// Idempotent on email + on the enum value (ALTER TYPE ADD VALUE IF NOT
// EXISTS runs on its own connection because it can't sit in a transaction).
//
// Run via:
//   gh workflow run "DB · Seed (manual)" --field script=seed-parts-user
// =============================================================================

import 'dotenv/config';
import * as bcrypt from 'bcrypt';
import { UserRole } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const DEV_PASSWORD = 'Dev1234!';
const EMAIL = 'parts@bigfoot.dev';
const PRIMARY_DEPT_CODE = 'XP_JIG';
const EXTRA_DEPT_CODES = ['YETI_JIG', 'DO_JIG', 'GN_WELD'];

async function main(): Promise<void> {
  console.log("🔧 Adding 'parts' role + dev account...\n");

  // ─── 0. Ensure the enum value exists in prod (db push doesn't run there)
  await prisma.$executeRawUnsafe(
    `ALTER TYPE user_role_enum ADD VALUE IF NOT EXISTS 'parts';`,
  );
  console.log("✅ Enum user_role_enum has 'parts' value\n");

  // ─── 1. Resolve departments ───────────────────────────────────────────────
  const allCodes = [PRIMARY_DEPT_CODE, ...EXTRA_DEPT_CODES];
  const depts = await prisma.department.findMany({
    where: { code: { in: allCodes } },
    select: { id: true, code: true, displayName: true },
  });
  const byCode = new Map(depts.map((d) => [d.code, d]));
  for (const code of allCodes) {
    if (!byCode.has(code)) {
      throw new Error(
        `Department ${code} not found — run the base seed first (npx tsx prisma/seed.ts).`,
      );
    }
  }
  const primary = byCode.get(PRIMARY_DEPT_CODE)!;
  const extras = EXTRA_DEPT_CODES.map((c) => byCode.get(c)!);

  // ─── 2. Upsert user ───────────────────────────────────────────────────────
  const passwordHash = await bcrypt.hash(DEV_PASSWORD, 12);
  const existing = await prisma.user.findUnique({
    where: { email: EMAIL },
    select: { id: true },
  });
  const extraIds = extras.map((d) => d.id);
  const user = await prisma.user.upsert({
    where: { email: EMAIL },
    update: {
      passwordHash,
      fullName: 'Parts Staff',
      role: UserRole.parts,
      primaryDepartmentId: primary.id,
      extraDepartmentIds: extraIds,
      primaryLocationId: null,
      isActive: true,
    },
    create: {
      email: EMAIL,
      passwordHash,
      fullName: 'Parts Staff',
      role: UserRole.parts,
      primaryDepartmentId: primary.id,
      extraDepartmentIds: extraIds,
      primaryLocationId: null,
      isActive: true,
    },
    select: { id: true, email: true, fullName: true },
  });
  console.log(
    `  ${existing ? '=' : '+'} ${user.email} (id=${user.id}) — primary ${primary.code} (${primary.displayName})`,
  );
  for (const d of extras) {
    console.log(`    + extra ${d.code.padEnd(10)} ${d.displayName}`);
  }

  console.log(`\n🎉 Done. Login with ${EMAIL} / ${DEV_PASSWORD}`);
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
