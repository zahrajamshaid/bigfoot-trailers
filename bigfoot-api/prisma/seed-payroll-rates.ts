// =============================================================================
// BIGFOOT TRAILERS — Payroll Rate Config Seed
// Seeds DeptDollarRate ($/point) for every production (non-QC) department so
// the Weekly Payroll Report can convert points → gross pay. Without these rows
// the report shows $0.00 for every worker (pay = points × dollarPerPoint, and
// the rate map defaults to 0 when no row exists).
//
// See src/modules/payroll/payroll.service.ts → getWeeklyReport(): the rate is
// looked up per department with effective_from <= week and (effective_to null
// or >= week). We seed an open-ended rate effective from 2020-01-01.
//
// Idempotent: upserts by (departmentId, effectiveFrom).
// Run with:  npx ts-node prisma/seed-payroll-rates.ts
// =============================================================================

import 'dotenv/config';
import { Prisma } from '@prisma/client';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

const EFFECTIVE_FROM = new Date('2020-01-01T00:00:00.000Z');

// Per-department $/point. Welding/finish departments pay a bit more than
// assembly. Anything not listed falls back to DEFAULT_RATE.
const DEFAULT_RATE = 1.25;
const RATE_BY_CODE: Record<string, number> = {
  XP_JIG: 1.75,
  XP_FIN: 1.6,
  YETI_JIG: 1.75,
  YETI_FIN: 1.6,
  DO_JIG: 1.7,
  DO_FIN: 1.55,
  GN_WELD: 1.8,
  GN_FIN: 1.6,
  PAINT_PREP: 1.1,
  PAINT_A: 1.3,
  PAINT_B: 1.3,
  HYDRAULICS: 1.5,
  WIRE: 1.4,
  WOOD: 1.2,
};

async function main() {
  console.log('💵 Seeding payroll dollar-per-point rates...\n');

  // Production departments only — QC steps don't earn points/pay.
  const depts = await prisma.department.findMany({
    where: { isQcStep: false },
    orderBy: { id: 'asc' },
  });
  if (!depts.length) {
    throw new Error('No departments found. Run the base seed first: npx prisma db seed');
  }

  let created = 0;
  let updated = 0;
  for (const dept of depts) {
    const rate = RATE_BY_CODE[dept.code] ?? DEFAULT_RATE;

    const existing = await prisma.deptDollarRate.findUnique({
      where: {
        departmentId_effectiveFrom: {
          departmentId: dept.id,
          effectiveFrom: EFFECTIVE_FROM,
        },
      },
      select: { id: true },
    });

    await prisma.deptDollarRate.upsert({
      where: {
        departmentId_effectiveFrom: {
          departmentId: dept.id,
          effectiveFrom: EFFECTIVE_FROM,
        },
      },
      update: { dollarPerPoint: new Prisma.Decimal(rate), effectiveTo: null },
      create: {
        departmentId: dept.id,
        dollarPerPoint: new Prisma.Decimal(rate),
        effectiveFrom: EFFECTIVE_FROM,
        effectiveTo: null,
      },
    });

    if (existing) updated++;
    else created++;
    console.log(`  ✅ ${dept.code.padEnd(12)} → $${rate.toFixed(2)} / point`);
  }

  console.log(`\n🎉 Done. ${created} created, ${updated} updated across ${depts.length} departments.`);
  console.log('   Re-open the Weekly Payroll Report — gross pay will now compute.');
}

main()
  .catch((e) => {
    console.error('❌ Payroll rate seed failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
