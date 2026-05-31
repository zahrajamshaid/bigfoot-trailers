// =============================================================================
// BIGFOOT TRAILERS — Inventory-only models + extra sales logins
//
// Two small additions bundled into one seed:
//
//   1. Three inventory-only trailer models (series=inventory) that skip the
//      workflow-template lookup on trailer create. Used for stock tracking
//      of items we don't actually build on a line:
//        • Triple Crown
//        • Enclosed
//        • Miscellaneous
//
//   2. Two location-scoped sales user logins:
//        • tal-sales@bigfoot.dev → Tallahassee
//        • atl-sales@bigfoot.dev → Atlanta
//      (Password: Dev1234! — same as the other dev accounts.)
//
// Idempotent: models upsert by `code`, users upsert by `email`.
//
// Run with:
//   npx tsx prisma/seed-inventory-models-and-sales.ts
// =============================================================================

import 'dotenv/config';
import * as bcrypt from 'bcrypt';
import { TrailerSeries, UserRole } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();
const DEV_PASSWORD = 'Dev1234!';

const INVENTORY_MODELS = [
  { code: 'TRIPLE_CROWN', displayName: 'Triple Crown' },
  { code: 'ENCLOSED', displayName: 'Enclosed' },
  { code: 'MISC', displayName: 'Miscellaneous' },
] as const;

const SALES_USERS = [
  { email: 'tal-sales@bigfoot.dev', fullName: 'TAL Sales', locationCode: 'TALLAHASSEE' },
  { email: 'atl-sales@bigfoot.dev', fullName: 'ATL Sales', locationCode: 'ATLANTA' },
] as const;

async function main(): Promise<void> {
  console.log('📦 Adding inventory-only models + extra sales logins...\n');

  // ─── 1. Inventory-only trailer models ──────────────────────────────────────
  let modelsCreated = 0;
  let modelsExisted = 0;
  for (const m of INVENTORY_MODELS) {
    const existing = await prisma.trailerModel.findUnique({
      where: { code: m.code },
      select: { id: true },
    });
    const saved = await prisma.trailerModel.upsert({
      where: { code: m.code },
      update: {
        displayName: m.displayName,
        series: TrailerSeries.inventory,
        isActive: true,
      },
      create: {
        code: m.code,
        displayName: m.displayName,
        series: TrailerSeries.inventory,
        isActive: true,
      },
      select: { id: true, code: true, displayName: true },
    });
    if (existing) modelsExisted++;
    else modelsCreated++;
    console.log(
      `  ${existing ? '=' : '+'} model ${saved.code.padEnd(15)} → "${saved.displayName}" (id=${saved.id})`,
    );
  }
  console.log(
    `✅ Inventory models: ${modelsCreated} created, ${modelsExisted} already present.\n`,
  );

  // ─── 2. Extra location-scoped sales users ──────────────────────────────────
  const passwordHash = await bcrypt.hash(DEV_PASSWORD, 12);
  let usersCreated = 0;
  let usersExisted = 0;
  for (const u of SALES_USERS) {
    const loc = await prisma.location.findUnique({
      where: { code: u.locationCode },
      select: { id: true, name: true },
    });
    if (!loc) {
      throw new Error(
        `Location ${u.locationCode} not found — run the base seed first (npx tsx prisma/seed.ts).`,
      );
    }
    const existing = await prisma.user.findUnique({
      where: { email: u.email },
      select: { id: true },
    });
    await prisma.user.upsert({
      where: { email: u.email },
      update: {
        passwordHash,
        fullName: u.fullName,
        role: UserRole.sales,
        primaryLocationId: loc.id,
        primaryDepartmentId: null,
        isActive: true,
      },
      create: {
        email: u.email,
        passwordHash,
        fullName: u.fullName,
        role: UserRole.sales,
        primaryLocationId: loc.id,
        primaryDepartmentId: null,
        isActive: true,
      },
    });
    if (existing) usersExisted++;
    else usersCreated++;
    console.log(`  ${existing ? '=' : '+'} ${u.email.padEnd(28)} → sales @ ${loc.name}`);
  }
  console.log(
    `\n✅ Sales users: ${usersCreated} created, ${usersExisted} already present.`,
  );
  console.log(`   Password for all dev accounts: ${DEV_PASSWORD}`);

  console.log('\n🎉 Done.');
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
