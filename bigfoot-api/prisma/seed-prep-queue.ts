// =============================================================================
// BIGFOOT TRAILERS — Prep-queue seed
//
// Drops trailers into the prep workflow line (wood, wire-hydro, paint prep),
// starting at their designated step (5, 9, or 11 depending on folder).
// All steps before the start step are marked `complete`, the start step is
// `active`, the rest stay `waiting`.
//
// createdByUserId points at the owner account.
//
// Idempotent on so_number: existing trailers are skipped.
//
// Run with: npx tsx prisma/seed-prep-queue.ts
// =============================================================================

import 'dotenv/config';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  ProductionStepStatus,
  TrailerSeries,
  TrailerStatus,
} from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const DATA_JSON = join(__dirname, 'data', 'prep-queue-trailers.json');

interface PdfRecord {
  folder: string;
  file: string;
  soNumber: string;
  pdfModelCode: string | null;
  series: string | null;
  startStepOrder: number;
  startDeptCode: string;
  date: string | null;
  lengthFt: string | null;
}

async function main(): Promise<void> {
  console.log('🛠  Seeding prep-queue trailers...\n');

  // ─── 1. Prerequisites ──────────────────────────────────────────────────────
  const owner =
    (await prisma.user.findFirst({ where: { role: 'owner' } })) ??
    (await prisma.user.findFirst());
  if (!owner) throw new Error('No users in DB.');

  const mulberry = await prisma.location.findUnique({
    where: { code: 'MULBERRY' },
    select: { id: true, name: true },
  });
  if (!mulberry) throw new Error('Mulberry location missing — run base seed.');

  // ─── 2. Build model cache by series ────────────────────────────────────────
  const modelsBySeriesSample = new Map<string, number>();
  for (const series of ['xp', 'yeti', 'deck_over', 'gooseneck_dump']) {
    const model = await prisma.trailerModel.findFirst({
      where: { series: series as any },
      select: { id: true },
    });
    if (model) {
      modelsBySeriesSample.set(series, model.id);
    }
  }

  // ─── 2. Load records ───────────────────────────────────────────────────────
  if (!existsSync(DATA_JSON)) {
    throw new Error(
      `Missing ${DATA_JSON} — run: npx tsx scripts/extract-prep-queue-trailers.ts`,
    );
  }
  const records: PdfRecord[] = JSON.parse(readFileSync(DATA_JSON, 'utf8'));
  console.log(`📋 Loaded ${records.length} records\n`);

  // Build workflow template cache by series
  const templatesBySeriesAndStep = new Map<string, Map<number, any>>();
  for (const series of ['xp', 'yeti', 'deck_over', 'gooseneck_dump']) {
    const templates = await prisma.workflowTemplate.findMany({
      where: { series: series as any },
      orderBy: { stepOrder: 'asc' },
      select: { id: true, stepOrder: true, departmentId: true },
    });
    const stepsById = new Map(
      templates.map((s) => [s.stepOrder, s]),
    );
    templatesBySeriesAndStep.set(series, stepsById);
  }

  // ─── 3. Process each record ────────────────────────────────────────────────
  let trailersCreated = 0;
  let trailersSkipped = 0;
  let stepsTotal = 0;
  let errors = 0;

  for (const r of records) {
    try {
      // Check if trailer already exists
      const existing = await prisma.trailer.findUnique({
        where: { soNumber: r.soNumber },
        select: { id: true, status: true },
      });

      if (existing) {
        console.log(`  ⊘ SO ${r.soNumber}: already exists (status=${existing.status})`);
        trailersSkipped++;
        continue;
      }

      // Validate series
      if (!r.series) {
        console.warn(`  ⚠ SO ${r.soNumber}: unknown series from code "${r.pdfModelCode}"`);
        errors++;
        continue;
      }

      const stepsMap = templatesBySeriesAndStep.get(r.series);
      if (!stepsMap) {
        console.error(`  ✖ SO ${r.soNumber}: series ${r.series} has no workflow template`);
        errors++;
        continue;
      }

      // Get all workflow step templates for this series
      const allSteps = Array.from(stepsMap.entries()).sort((a, b) => a[0] - b[0]);
      if (allSteps.length === 0) {
        console.error(`  ✖ SO ${r.soNumber}: workflow has no steps`);
        errors++;
        continue;
      }

      // Get model for this series (use first available as placeholder)
      const modelId = modelsBySeriesSample.get(r.series);
      if (!modelId) {
        console.warn(
          `  ⚠ SO ${r.soNumber}: no trailer model found for series ${r.series}`,
        );
        errors++;
        continue;
      }

      const now = new Date();

      // Create the trailer
      const trailer = await prisma.trailer.create({
        data: {
          soNumber: r.soNumber,
          trailerModelId: modelId,
          currentLocationId: mulberry.id,
          createdByUserId: owner.id,
          status: TrailerStatus.in_production,
          sizeFt: r.lengthFt ?? undefined,
          isStockBuild: false,
        },
      });

      console.log(
        `  + SO ${r.soNumber} (${r.series}) at step ${r.startStepOrder} (${r.startDeptCode})`,
      );

      // Create production steps
      const createdSteps = [];
      for (const [stepOrder, template] of allSteps) {
        let status: ProductionStepStatus;
        let becameActiveAt: Date | null = null;
        let completedAt: Date | null = null;
        let queuePosition: number | null = null;

        if (stepOrder < r.startStepOrder) {
          status = ProductionStepStatus.complete;
          becameActiveAt = now;
          completedAt = now;
        } else if (stepOrder === r.startStepOrder) {
          status = ProductionStepStatus.active;
          becameActiveAt = now;
          queuePosition = 1;
        } else {
          status = ProductionStepStatus.waiting;
        }

        const step = await prisma.productionStep.create({
          data: {
            trailerId: trailer.id,
            departmentId: template.departmentId,
            stepOrder: template.stepOrder,
            status,
            queuePosition,
            becameActiveAt,
            completedAt,
          },
        });
        createdSteps.push(step);
        stepsTotal++;
      }

      trailersCreated++;
    } catch (e) {
      console.error(
        `  ✖ SO ${r.soNumber}: ${(e as Error).message}`,
      );
      errors++;
    }
  }

  console.log(`\n🎉 Done.`);
  console.log(
    `  Trailers: ${trailersCreated} created, ${trailersSkipped} skipped (existing)`,
  );
  console.log(`  Steps:    ${stepsTotal} created (${stepsTotal > 0 ? Math.round(stepsTotal / trailersCreated) : 0} per trailer)`);
  if (errors > 0) console.log(`  Errors:   ${errors}`);
}

main()
  .catch((e) => {
    console.error('❌ Seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
