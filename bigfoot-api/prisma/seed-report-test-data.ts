// =============================================================================
// BIGFOOT TRAILERS — Weekly Production Report Test Data
// Creates a handful of clearly-labeled test trailers (so_number prefix
// `RPT-TEST-`) and seeds COMPLETED production steps dated within the CURRENT
// week so the Admin → Reports (weekly production report) screen populates.
//
// The report aggregates ProductionStep rows where:
//   status = 'complete', is_rework = false, completed_at within [Sun, Sun+7)
// grouping points + step counts by completed_by_user. See
// src/modules/admin/admin.service.ts → getWeeklyProductionReport().
//
// Idempotent: re-running deletes any prior RPT-TEST- steps and re-creates them,
// and upserts the trailers by so_number — safe to run repeatedly.
// Prerequisite: base seed must have run (locations, models, users, departments).
//
// Run with:  npx ts-node prisma/seed-report-test-data.ts
// =============================================================================

import 'dotenv/config';
import { TrailerStatus } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const SO_PREFIX = 'RPT-TEST-';

/** Sunday 00:00 UTC of the week containing `d` (matches the report's week math). */
function weekStartSundayUTC(d: Date): Date {
  const day = d.getUTCDay(); // 0 = Sunday
  const sunday = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()),
  );
  sunday.setUTCDate(sunday.getUTCDate() - day);
  return sunday;
}

async function main() {
  console.log('📊 Seeding weekly production report test data...\n');

  const now = new Date();
  const weekStart = weekStartSundayUTC(now);
  console.log(`   Current report week (Sunday, UTC): ${weekStart.toISOString().split('T')[0]}\n`);

  // ─── Prerequisites ─────────────────────────────────────────────────────────
  const factory =
    (await prisma.location.findFirst({ where: { isFactory: true } })) ??
    (await prisma.location.findFirst());
  const creator =
    (await prisma.user.findFirst({ where: { role: 'owner' } })) ??
    (await prisma.user.findFirst());
  if (!factory || !creator) {
    throw new Error('Missing locations/users. Run the base seed first: npx prisma db seed');
  }

  const models = await prisma.trailerModel.findMany({ orderBy: { id: 'asc' }, take: 8 });
  // Production (non-QC) departments only — these are what earn points.
  const depts = await prisma.department.findMany({
    where: { isQcStep: false },
    orderBy: { id: 'asc' },
  });
  // Real worker-role users so the per-worker summary has several rows.
  const workers = await prisma.user.findMany({
    where: { role: 'worker' },
    orderBy: { id: 'asc' },
    take: 6,
  });
  if (!models.length || !depts.length || !workers.length) {
    throw new Error('Missing models/departments/workers. Run the base seed first.');
  }

  // ─── Wipe any prior RPT-TEST- production steps (idempotency) ───────────────
  const existingTestTrailers = await prisma.trailer.findMany({
    where: { soNumber: { startsWith: SO_PREFIX } },
    select: { id: true },
  });
  if (existingTestTrailers.length) {
    const deleted = await prisma.productionStep.deleteMany({
      where: { trailerId: { in: existingTestTrailers.map((t) => t.id) } },
    });
    console.log(`   Cleared ${deleted.count} prior test production step(s).\n`);
  }

  // ─── Test trailers ─────────────────────────────────────────────────────────
  const trailerDefs = [
    { soNumber: `${SO_PREFIX}001`, color: 'Black', sizeFt: '20' },
    { soNumber: `${SO_PREFIX}002`, color: 'White', sizeFt: '24' },
    { soNumber: `${SO_PREFIX}003`, color: 'Charcoal', sizeFt: '18' },
    { soNumber: `${SO_PREFIX}004`, color: 'Red', sizeFt: '22' },
  ];

  // A few completed steps per trailer, spread across departments + workers,
  // each completed at a distinct hour within this week (always <= now).
  // pointsAwarded varies so totals are non-trivial.
  const pointOptions = [8, 10, 12, 6, 15, 9];

  let totalSteps = 0;
  let totalPoints = 0;

  for (let i = 0; i < trailerDefs.length; i++) {
    const def = trailerDefs[i];
    const model = models[i % models.length];

    const trailer = await prisma.trailer.upsert({
      where: { soNumber: def.soNumber },
      update: {
        status: TrailerStatus.ready_for_delivery,
        currentLocationId: factory.id,
        trailerModelId: model.id,
        color: def.color,
        sizeFt: def.sizeFt,
      },
      create: {
        soNumber: def.soNumber,
        trailerModelId: model.id,
        currentLocationId: factory.id,
        createdByUserId: creator.id,
        status: TrailerStatus.ready_for_delivery,
        isStockBuild: true,
        color: def.color,
        sizeFt: def.sizeFt,
        specialNote: 'Test trailer for weekly production report',
      },
      select: { id: true, soNumber: true },
    });

    // 5 completed steps per trailer across the first 5 production departments.
    const stepsPerTrailer = 5;
    for (let s = 0; s < stepsPerTrailer; s++) {
      const dept = depts[s % depts.length];
      const worker = workers[(i + s) % workers.length];
      const points = pointOptions[(i + s) % pointOptions.length];

      // Spread completions across the week: hours back from now, but never
      // earlier than the week's Sunday start.
      const hoursBack = (i * stepsPerTrailer + s) * 5; // 0,5,10,... hours
      let completedAt = new Date(now.getTime() - hoursBack * 3600 * 1000);
      if (completedAt < weekStart) completedAt = new Date(weekStart.getTime() + 3600 * 1000);

      await prisma.productionStep.create({
        data: {
          trailerId: trailer.id,
          departmentId: dept.id,
          stepOrder: s + 1,
          status: 'complete',
          isRework: false,
          completedByUserId: worker.id,
          becameActiveAt: new Date(completedAt.getTime() - 2 * 3600 * 1000),
          completedAt,
          pointsAwarded: points,
        },
      });

      totalSteps++;
      totalPoints += points;
    }

    console.log(`  ✅ ${trailer.soNumber}  →  ${model.displayName}  (${stepsPerTrailer} completed steps)`);
  }

  console.log(
    `\n🎉 Done. ${trailerDefs.length} trailers, ${totalSteps} completed steps, ` +
      `${totalPoints} total points seeded into week ${weekStart.toISOString().split('T')[0]}.`,
  );
  console.log('   Open Admin → Reports (current week) to see the populated report.');
}

main()
  .catch((e) => {
    console.error('❌ Report test-data seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
