// =============================================================================
// BIGFOOT TRAILERS — Trailer Catalog + Ready Trailers Seed
// 1. Upserts the full trailer-model catalog (the models shown when creating a
//    trailer) so a live database picks up new models without a full re-seed.
// 2. Creates a set of trailers in `ready_for_delivery` status at the factory.
//
// Idempotent: models upsert by `code`, trailers upsert by `so_number`.
// Prerequisite: the base seed must have run first (locations + users).
//
// Run with:  npx ts-node prisma/seed-trailer-catalog.ts
// =============================================================================

import 'dotenv/config';
import { PrismaClient, TrailerSeries, TrailerStatus } from '@prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';

const connectionString = process.env['DATABASE_URL']!;
const adapter = new PrismaPg({ connectionString });
const prisma = new PrismaClient({ adapter });

// ─── New trailer models to add to the create-trailer list ────────────────────
const trailerModelData: {
  code: string;
  displayName: string;
  series: TrailerSeries;
  weightRating: string | null;
}[] = [
  // XP series
  { code: 'XP_10K', displayName: '10K XP', series: TrailerSeries.xp, weightRating: '10,000 lb' },
  { code: 'XP_14K', displayName: '14K XP', series: TrailerSeries.xp, weightRating: '14,000 lb' },
  { code: 'XP_17K', displayName: '17K XP', series: TrailerSeries.xp, weightRating: '17,000 lb' },
  // Yeti series
  { code: 'YETI_15K', displayName: '15K Yeti', series: TrailerSeries.yeti, weightRating: '15,000 lb' },
  { code: 'YETI_18K', displayName: '18K Yeti', series: TrailerSeries.yeti, weightRating: '18,000 lb' },
  { code: 'YETI_21K', displayName: '21K Yeti', series: TrailerSeries.yeti, weightRating: '21,000 lb' },
  // Deck Over series
  { code: 'DO_10K', displayName: '10K Deck Over', series: TrailerSeries.deck_over, weightRating: '10,000 lb' },
  { code: 'DO_14K', displayName: '14K Deck Over', series: TrailerSeries.deck_over, weightRating: '14,000 lb' },
  { code: 'DO_17K', displayName: '17K Deck Over', series: TrailerSeries.deck_over, weightRating: '17,000 lb' },
  { code: 'DO_22K', displayName: '22K Deck Over', series: TrailerSeries.deck_over, weightRating: '22,000 lb' },
  { code: 'DO_26K', displayName: '26K Deck Over', series: TrailerSeries.deck_over, weightRating: '26,000 lb' },
  { code: 'DO_30K', displayName: '30K Deck Over', series: TrailerSeries.deck_over, weightRating: '30,000 lb' },
  // Gooseneck / Dump series
  { code: 'GN_15K', displayName: '15K Gooseneck', series: TrailerSeries.gooseneck_dump, weightRating: '15,000 lb' },
  { code: 'GN_18K', displayName: '18K Gooseneck', series: TrailerSeries.gooseneck_dump, weightRating: '18,000 lb' },
  { code: 'GN_22K', displayName: '22K Gooseneck', series: TrailerSeries.gooseneck_dump, weightRating: '22,000 lb' },
  { code: 'GN_26K', displayName: '26K Gooseneck', series: TrailerSeries.gooseneck_dump, weightRating: '26,000 lb' },
  { code: 'GN_30K', displayName: '30K Gooseneck', series: TrailerSeries.gooseneck_dump, weightRating: '30,000 lb' },
  { code: 'DUMP_15K', displayName: '15K Dump', series: TrailerSeries.gooseneck_dump, weightRating: '15,000 lb' },
  { code: 'DUMP_18K', displayName: '18K Dump', series: TrailerSeries.gooseneck_dump, weightRating: '18,000 lb' },
  { code: 'DUMP_26K_GN', displayName: '26K GN Dump', series: TrailerSeries.gooseneck_dump, weightRating: '26,000 lb' },
];

// ─── Ready-for-delivery stock trailers ───────────────────────────────────────
const readyTrailers: {
  soNumber: string;
  modelCode: string;
  color: string;
  sizeFt: string;
}[] = [
  { soNumber: 'STK-1001', modelCode: 'XP_14K', color: 'Black', sizeFt: '20' },
  { soNumber: 'STK-1002', modelCode: 'XP_17K', color: 'White', sizeFt: '24' },
  { soNumber: 'STK-1003', modelCode: 'YETI_18K', color: 'Charcoal', sizeFt: '22' },
  { soNumber: 'STK-1004', modelCode: 'DO_22K', color: 'Red', sizeFt: '26' },
  { soNumber: 'STK-1005', modelCode: 'DO_30K', color: 'Silver', sizeFt: '32' },
  { soNumber: 'STK-1006', modelCode: 'GN_26K', color: 'Blue', sizeFt: '28' },
  { soNumber: 'STK-1007', modelCode: 'GN_30K', color: 'Gray', sizeFt: '32' },
  { soNumber: 'STK-1008', modelCode: 'DUMP_18K', color: 'Green', sizeFt: '16' },
];

async function main() {
  console.log('🚛 Seeding trailer catalog + ready trailers...\n');

  // ─── 1. Trailer models ─────────────────────────────────────────────────────
  let modelsCreated = 0;
  let modelsExisted = 0;
  const modelsByCode = new Map<string, { id: number; displayName: string }>();
  for (const m of trailerModelData) {
    const existing = await prisma.trailerModel.findUnique({
      where: { code: m.code },
      select: { id: true },
    });
    const model = await prisma.trailerModel.upsert({
      where: { code: m.code },
      update: {},
      create: m,
      select: { id: true, code: true, displayName: true },
    });
    modelsByCode.set(model.code, { id: model.id, displayName: model.displayName });
    if (existing) modelsExisted++;
    else modelsCreated++;
  }
  console.log(
    `✅ Trailer models: ${modelsCreated} created, ${modelsExisted} already present (${trailerModelData.length} total).\n`,
  );

  // ─── Prerequisites for trailers ────────────────────────────────────────────
  const factory =
    (await prisma.location.findFirst({ where: { isFactory: true } })) ??
    (await prisma.location.findFirst());
  if (!factory) {
    throw new Error('No locations found. Run the base seed first:  npx prisma db seed');
  }

  const creator =
    (await prisma.user.findFirst({ where: { role: 'owner' } })) ??
    (await prisma.user.findFirst());
  if (!creator) {
    throw new Error('No users found. Run the base seed first:  npx prisma db seed');
  }

  // ─── 2. Ready-for-delivery trailers ────────────────────────────────────────
  let trailersCreated = 0;
  let trailersUpdated = 0;
  for (const t of readyTrailers) {
    const model = modelsByCode.get(t.modelCode);
    if (!model) {
      throw new Error(`Model code "${t.modelCode}" not found — check trailerModelData.`);
    }

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
        specialNote: 'Stock build — ready for delivery',
      },
      select: { id: true, soNumber: true, status: true },
    });

    if (existing) trailersUpdated++;
    else trailersCreated++;
    console.log(
      `  ✅ ${trailer.soNumber}  →  ${model.displayName}  [${trailer.status}]`,
    );
  }

  console.log(
    `\n🎉 Done. Ready trailers: ${trailersCreated} created, ${trailersUpdated} updated — ${readyTrailers.length} ready_for_delivery at "${factory.name}".`,
  );
}

main()
  .catch((e) => {
    console.error('❌ Trailer catalog seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
