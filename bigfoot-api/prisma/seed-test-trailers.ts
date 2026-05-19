// =============================================================================
// BIGFOOT TRAILERS — Test Trailer Seed
// Creates 6 trailers in `ready_for_delivery` status so they can be added to a
// delivery batch (batch delivery only accepts ready_for_delivery trailers).
//
// Idempotent: re-running upserts by so_number, so it will not duplicate.
// Prerequisite: the base seed must have run first (locations, models, users).
//   Run base seed with:  npx prisma db seed
//
// Run this script with:  npx ts-node prisma/seed-test-trailers.ts
// =============================================================================

import 'dotenv/config';
import { PrismaClient, TrailerStatus } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';

const connectionString = process.env['DATABASE_URL']!;
const adapter = new PrismaPg({ connectionString });
const prisma = new PrismaClient({ adapter });

async function main() {
  console.log('🚚 Seeding test trailers for batch-delivery testing...\n');

  // ─── Prerequisites ─────────────────────────────────────────────────────────
  const factory =
    (await prisma.location.findFirst({ where: { isFactory: true } })) ??
    (await prisma.location.findFirst());
  if (!factory) {
    throw new Error(
      'No locations found. Run the base seed first:  npx prisma db seed',
    );
  }

  const creator =
    (await prisma.user.findFirst({ where: { role: 'owner' } })) ??
    (await prisma.user.findFirst());
  if (!creator) {
    throw new Error(
      'No users found. Run the base seed first:  npx prisma db seed',
    );
  }

  const models = await prisma.trailerModel.findMany({ orderBy: { id: 'asc' } });
  if (models.length === 0) {
    throw new Error(
      'No trailer models found. Run the base seed first:  npx prisma db seed',
    );
  }

  // ─── Test trailers ─────────────────────────────────────────────────────────
  // All start as ready_for_delivery at the factory so they are eligible to be
  // pulled into a delivery batch immediately.
  const testTrailers = [
    { soNumber: 'TEST-BATCH-001', color: 'Black', sizeFt: '20' },
    { soNumber: 'TEST-BATCH-002', color: 'White', sizeFt: '24' },
    { soNumber: 'TEST-BATCH-003', color: 'Charcoal', sizeFt: '18' },
    { soNumber: 'TEST-BATCH-004', color: 'Red', sizeFt: '22' },
    { soNumber: 'TEST-BATCH-005', color: 'Silver', sizeFt: '26' },
    { soNumber: 'TEST-BATCH-006', color: 'Blue', sizeFt: '20' },
  ];

  let created = 0;
  let updated = 0;
  for (let i = 0; i < testTrailers.length; i++) {
    const t = testTrailers[i];
    const model = models[i % models.length];

    const existing = await prisma.trailer.findUnique({
      where: { soNumber: t.soNumber },
      select: { id: true },
    });

    const trailer = await prisma.trailer.upsert({
      where: { soNumber: t.soNumber },
      update: {
        status: TrailerStatus.ready_for_delivery,
        currentLocationId: factory.id,
        trailerModelId: model.id,
        color: t.color,
        sizeFt: t.sizeFt,
      },
      create: {
        soNumber: t.soNumber,
        trailerModelId: model.id,
        currentLocationId: factory.id,
        createdByUserId: creator.id,
        status: TrailerStatus.ready_for_delivery,
        isStockBuild: true,
        color: t.color,
        sizeFt: t.sizeFt,
        specialNote: 'Test trailer for batch-delivery testing',
      },
      select: { id: true, soNumber: true, status: true },
    });

    if (existing) updated++;
    else created++;
    console.log(
      `  ✅ ${trailer.soNumber}  →  ${model.displayName} (${model.series})  [${trailer.status}]`,
    );
  }

  console.log(
    `\n🎉 Done. ${created} created, ${updated} updated — ${testTrailers.length} trailers ready_for_delivery at "${factory.name}".`,
  );
  console.log('   These are now eligible to add to a delivery batch.');
}

main()
  .catch((e) => {
    console.error('❌ Test trailer seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
