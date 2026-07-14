// LOCAL DEV ONLY — not registered in db-seed.yml. Seeds one real model
// (15ET20TLT, spec transcribed from sample SO #6696) + its options + the
// standard fee set, so the configurator can be demonstrated end-to-end.
import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

async function main() {
  // The model — spec matches the sample packing slip exactly.
  const model = await prisma.trailerModel.upsert({
    where: { code: '15TLT20' },
    update: {},
    create: {
      code: '15TLT20',
      displayName: '15K Tilt 20 (Yeti)',
      series: 'yeti',
      weightRating: '14,900',
      basePrice: 8995.0,
      spec: {
        typeModel: '15TLT20',
        length: "16' TILT DECK 4' STATIONARY",
        deckWidth: '83" BETWEEN FENDERS',
        gvwr: '14,900LBS',
        payload: '11,500LBS',
        frame: [
          '8" STRUCTURAL I BEAM - INTEGRATED TONGUE',
          '3" STRUCTURAL CHANNEL CROSSMEMBERS',
        ],
        axles: '7K TORSION-TORFLEX 10 YEAR WARRANTY',
        tires: '235/80R16 14PLY',
        standardOptions: '11GA FENDERS, 6 D RINGS, FULL RUB RAIL, TONGUE TOOL BOX',
        coupler: 'ADJUSTABLE DEMCO EZ LATCH',
        jack: '12K BULLDOG SPRING LOADED LEG',
        wiring:
          'WATERTIGHT PLUG N PLAY AUTOMOTIVE HARNESS WITH FLOW CHARGER BUILT IN. PAIRED WITH ALL LED LIGHTING',
        paint: '2 PART EPOXY PRIMER WITH 2 PART URETHANE TOPCOAT',
      },
    },
  });

  // Options (from the sample's own option lines).
  const options = [
    {
      name: 'Spare Tire 8 Lug Mounted PS',
      description:
        'Radial Spare Tire Mounted on the passenger Side in Front of Fender',
      price: 225,
      taxable: true,
      defaultForModelIds: [model.id], // spare tire standard on this model
    },
    {
      name: 'HYDRAULIC JACK',
      description: '12K HYDRAULIC JACK WITH PUMP AND BATTERY',
      price: 850,
      taxable: true,
      defaultForModelIds: [],
    },
  ];
  for (const o of options) {
    const existing = await prisma.option.findFirst({ where: { name: o.name } });
    if (existing) {
      await prisma.option.update({
        where: { id: existing.id },
        data: { ...o, applicableModelIds: [model.id] },
      });
    } else {
      await prisma.option.create({
        data: { ...o, applicableModelIds: [model.id] },
      });
    }
  }

  // Standard fees (auto-added on every estimate) — amounts from the plan.
  const fees = [
    { name: 'Dealer Fee', amount: 0, taxable: false },
    { name: 'Disposal Fee, Battery Tire', amount: 22, taxable: false },
    { name: 'Tag and Title Processing', amount: 15.5, taxable: false },
    { name: 'Estimated Registration Fee', amount: 180, taxable: false },
  ];
  for (const f of fees) {
    const existing = await prisma.feeSchedule.findFirst({ where: { name: f.name } });
    if (existing) {
      await prisma.feeSchedule.update({
        where: { id: existing.id },
        data: { ...f, autoAdd: true, scope: 'global' },
      });
    } else {
      await prisma.feeSchedule.create({
        data: { ...f, autoAdd: true, scope: 'global' },
      });
    }
  }

  const optRows = await prisma.option.findMany({
    where: { applicableModelIds: { has: model.id } },
    select: { id: true, name: true },
  });
  console.log('✅ Seeded model 15TLT20 (id', model.id, ')');
  console.log('   options:', optRows.map((o) => `${o.id}:${o.name}`).join(', '));
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
