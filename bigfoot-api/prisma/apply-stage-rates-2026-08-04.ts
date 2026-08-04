// =============================================================================
// BIGFOOT TRAILERS -- Load the flat pay + cost matrix (2026-08-04)
//
// Payroll moved from points to a flat $/stage. This adds the pay columns to
// trailer_model_stage_costs (idempotent) and loads every model's Cost/Stage and
// Pay Rate per department from "Bigfoot App Updated" -- backing BOTH the cost
// matrix and the pay matrix. Worker-split stages (gooseneck jig 665/500/400,
// yeti finish 200/190/160) carry an ordered split for the crew-pay engine.
//
// Idempotent: upserts on (model, dept, effectiveFrom=2026-08-04).
// Run:  gh workflow run db-seed.yml -f script=apply-stage-rates-2026-08-04
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';
import { Prisma } from '@prisma/client';

const prisma = createPrismaClient();
const EFFECTIVE_FROM = new Date('2026-08-04T00:00:00Z');

// [db_model_code, dept_code, costDollars|null, payDollars, split|null]
const ROWS: Array<[string, string, number | null, number, number[] | null]> = [
  ['CXP_10', 'GN_WELD', 2989.0, 100.0, null],
  ['CXP_10', 'GN_FIN', 3589.0, 100.0, null],
  ['CXP_10', 'PAINT_PREP', 3599.0, 20.0, null],
  ['CXP_10', 'PAINT_B', 3699.0, 50.0, null],
  ['CXP_10', 'WIRE', 4099.0, 60.0, null],
  ['CXP_10', 'WOOD', 4799.0, 0.0, null],
  ['CXP_14K', 'GN_WELD', 3189.0, 100.0, null],
  ['CXP_14K', 'GN_FIN', 3789.0, 100.0, null],
  ['CXP_14K', 'PAINT_PREP', 3799.0, 20.0, null],
  ['CXP_14K', 'PAINT_B', 3899.0, 50.0, null],
  ['CXP_14K', 'WIRE', 4299.0, 60.0, null],
  ['CXP_14K', 'WOOD', 4999.0, 0.0, null],
  ['XP_10K', 'XP_JIG', 3489.0, 120.0, null],
  ['XP_10K', 'XP_FIN', 4089.0, 135.0, null],
  ['XP_10K', 'PAINT_PREP', 4099.0, 40.0, null],
  ['XP_10K', 'PAINT_B', 4199.0, 70.0, null],
  ['XP_10K', 'HYDRAULICS', 4599.0, 0.0, null],
  ['XP_10K', 'WIRE', 4599.0, 50.0, null],
  ['XP_10K', 'WOOD', 5299.0, 60.0, null],
  ['XP_14K', 'XP_JIG', 3489.0, 120.0, null],
  ['XP_14K', 'XP_FIN', 4089.0, 135.0, null],
  ['XP_14K', 'PAINT_PREP', 4099.0, 40.0, null],
  ['XP_14K', 'PAINT_B', 4199.0, 70.0, null],
  ['XP_14K', 'HYDRAULICS', 4599.0, 0.0, null],
  ['XP_14K', 'WIRE', 4599.0, 50.0, null],
  ['XP_14K', 'WOOD', 5299.0, 60.0, null],
  ['XP_17K', 'XP_JIG', 3489.0, 120.0, null],
  ['XP_17K', 'XP_FIN', 4089.0, 135.0, null],
  ['XP_17K', 'PAINT_PREP', 4099.0, 40.0, null],
  ['XP_17K', 'PAINT_B', 4199.0, 70.0, null],
  ['XP_17K', 'HYDRAULICS', 4599.0, 0.0, null],
  ['XP_17K', 'WIRE', 4599.0, 50.0, null],
  ['XP_17K', 'WOOD', 5299.0, 60.0, null],
  ['DO_10K', 'DO_JIG', 5089.0, 270.0, null],
  ['DO_10K', 'DO_FIN', 5689.0, 270.0, null],
  ['DO_10K', 'PAINT_PREP', 5699.0, 46.0, null],
  ['DO_10K', 'PAINT_B', 5799.0, 90.0, null],
  ['DO_10K', 'HYDRAULICS', 6199.0, 0.0, null],
  ['DO_10K', 'WIRE', 6899.0, 80.0, null],
  ['DO_10K', 'WOOD', 6899.0, 80.0, null],
  ['DO_14K', 'DO_JIG', 6089.0, 270.0, null],
  ['DO_14K', 'DO_FIN', 6689.0, 270.0, null],
  ['DO_14K', 'PAINT_PREP', 6699.0, 46.0, null],
  ['DO_14K', 'PAINT_B', 6799.0, 90.0, null],
  ['DO_14K', 'HYDRAULICS', 7199.0, 0.0, null],
  ['DO_14K', 'WIRE', 7899.0, 80.0, null],
  ['DO_14K', 'WOOD', 7899.0, 80.0, null],
  ['DO_17K', 'DO_JIG', 7790.0, 450.0, null],
  ['DO_17K', 'DO_FIN', 8390.0, 450.0, null],
  ['DO_17K', 'PAINT_PREP', 8400.0, 46.0, null],
  ['DO_17K', 'PAINT_B', 8500.0, 80.0, null],
  ['DO_17K', 'HYDRAULICS', 8900.0, 0.0, null],
  ['DO_17K', 'WIRE', 9600.0, 80.0, null],
  ['DO_17K', 'WOOD', 9600.0, 80.0, null],
  ['DO_22K', 'DO_JIG', 12340.0, 450.0, null],
  ['DO_22K', 'DO_FIN', 12940.0, 450.0, null],
  ['DO_22K', 'PAINT_PREP', 12950.0, 46.0, null],
  ['DO_22K', 'PAINT_B', 13050.0, 80.0, null],
  ['DO_22K', 'HYDRAULICS', 13450.0, 0.0, null],
  ['DO_22K', 'WIRE', 14550.0, 80.0, null],
  ['DO_22K', 'WOOD', 14550.0, 80.0, null],
  ['DO_26K', 'DO_JIG', 14340.0, 450.0, null],
  ['DO_26K', 'DO_FIN', 14940.0, 450.0, null],
  ['DO_26K', 'PAINT_PREP', 14950.0, 46.0, null],
  ['DO_26K', 'PAINT_B', 15050.0, 80.0, null],
  ['DO_26K', 'HYDRAULICS', 15450.0, 0.0, null],
  ['DO_26K', 'WIRE', 16550.0, 80.0, null],
  ['DO_26K', 'WOOD', 16550.0, 80.0, null],
  ['DUMP_15K', 'GN_WELD', 13700.0, 665.0, [665.0, 500.0, 400.0]],
  ['DUMP_15K', 'GN_FIN', 14100.0, 0.0, null],
  ['DUMP_15K', 'PAINT_PREP', 14100.0, 72.0, null],
  ['DUMP_15K', 'PAINT_B', 14300.0, 120.0, null],
  ['DUMP_15K', 'HYDRAULICS', 15000.0, 260.0, null],
  ['DUMP_18K', 'GN_WELD', 15550.0, 665.0, [665.0, 500.0, 400.0]],
  ['DUMP_18K', 'GN_FIN', 15950.0, 0.0, null],
  ['DUMP_18K', 'PAINT_PREP', 15950.0, 72.0, null],
  ['DUMP_18K', 'PAINT_B', 16150.0, 120.0, null],
  ['DUMP_18K', 'HYDRAULICS', 16850.0, 260.0, null],
  ['DUMP_26K_GN', 'GN_WELD', 27800.0, 665.0, [665.0, 500.0, 400.0]],
  ['DUMP_26K_GN', 'GN_FIN', 28200.0, 0.0, null],
  ['DUMP_26K_GN', 'PAINT_PREP', 28200.0, 100.0, null],
  ['DUMP_26K_GN', 'PAINT_B', 28400.0, 200.0, null],
  ['DUMP_26K_GN', 'HYDRAULICS', 29600.0, 260.0, null],
  ['GN_15K', 'GN_WELD', 11250.0, 665.0, [665.0, 500.0, 400.0]],
  ['GN_15K', 'GN_FIN', 11550.0, 0.0, null],
  ['GN_15K', 'PAINT_PREP', 11550.0, 72.0, null],
  ['GN_15K', 'PAINT_B', 11750.0, 150.0, null],
  ['GN_15K', 'HYDRAULICS', 12250.0, 0.0, null],
  ['GN_15K', 'WIRE', 12750.0, 80.0, null],
  ['GN_15K', 'WOOD', 13950.0, 95.0, null],
  ['GN_18K', 'GN_WELD', 9100.0, 665.0, [665.0, 500.0, 400.0]],
  ['GN_18K', 'GN_FIN', 9400.0, 0.0, null],
  ['GN_18K', 'PAINT_PREP', 9400.0, 72.0, null],
  ['GN_18K', 'PAINT_B', 9600.0, 150.0, null],
  ['GN_18K', 'HYDRAULICS', 10100.0, 0.0, null],
  ['GN_18K', 'WIRE', 10600.0, 80.0, null],
  ['GN_18K', 'WOOD', 11800.0, 95.0, null],
  ['GN_21K', 'GN_WELD', 12900.0, 665.0, [665.0, 500.0, 400.0]],
  ['GN_21K', 'GN_FIN', 13200.0, 0.0, null],
  ['GN_21K', 'PAINT_PREP', 13200.0, 72.0, null],
  ['GN_21K', 'PAINT_B', 13400.0, 150.0, null],
  ['GN_21K', 'HYDRAULICS', 13900.0, 0.0, null],
  ['GN_21K', 'WIRE', 14400.0, 80.0, null],
  ['GN_21K', 'WOOD', 15600.0, 95.0, null],
  ['GN_22K', 'GN_WELD', 12900.0, 665.0, [665.0, 500.0, 400.0]],
  ['GN_22K', 'GN_FIN', 13200.0, 0.0, null],
  ['GN_22K', 'PAINT_PREP', 13200.0, 72.0, null],
  ['GN_22K', 'PAINT_B', 13400.0, 150.0, null],
  ['GN_22K', 'HYDRAULICS', 13900.0, 0.0, null],
  ['GN_22K', 'WIRE', 14400.0, 80.0, null],
  ['GN_22K', 'WOOD', 15600.0, 95.0, null],
  ['GN_26K', 'GN_WELD', 14700.0, 665.0, [665.0, 500.0, 400.0]],
  ['GN_26K', 'GN_FIN', 15000.0, 0.0, null],
  ['GN_26K', 'PAINT_PREP', 15000.0, 72.0, null],
  ['GN_26K', 'PAINT_B', 15200.0, 150.0, null],
  ['GN_26K', 'HYDRAULICS', 15700.0, 0.0, null],
  ['GN_26K', 'WIRE', 16200.0, 80.0, null],
  ['GN_26K', 'WOOD', 17400.0, 95.0, null],
  ['GN_30K', 'GN_WELD', 21000.0, 665.0, [665.0, 500.0, 400.0]],
  ['GN_30K', 'GN_FIN', 21300.0, 0.0, null],
  ['GN_30K', 'PAINT_PREP', 21300.0, 72.0, null],
  ['GN_30K', 'PAINT_B', 21500.0, 150.0, null],
  ['GN_30K', 'HYDRAULICS', 22000.0, 0.0, null],
  ['GN_30K', 'WIRE', 22500.0, 80.0, null],
  ['GN_30K', 'WOOD', 23700.0, 95.0, null],
  ['GN_YETI', 'GN_WELD', 10700.0, 665.0, [665.0, 500.0, 400.0]],
  ['GN_YETI', 'YETI_FIN', 11000.0, 0.0, null],
  ['GN_YETI', 'PAINT_PREP', 11000.0, 72.0, null],
  ['GN_YETI', 'PAINT_B', 11200.0, 150.0, null],
  ['GN_YETI', 'HYDRAULICS', 11700.0, 0.0, null],
  ['GN_YETI', 'WIRE', 12200.0, 80.0, null],
  ['GN_YETI', 'WOOD', 13000.0, 95.0, null],
  ['YETI_15K', 'YETI_JIG', 5900.0, 150.0, null],
  ['YETI_15K', 'YETI_FIN', 6800.0, 200.0, [200.0, 190.0, 160.0]],
  ['YETI_15K', 'PAINT_PREP', 7000.0, 40.0, null],
  ['YETI_15K', 'PAINT_B', 7200.0, 70.0, null],
  ['YETI_15K', 'WIRE', 7700.0, 50.0, null],
  ['YETI_15K', 'WOOD', 8500.0, 60.0, null],
  ['YETI_18K', 'YETI_JIG', 7900.0, 150.0, null],
  ['YETI_18K', 'YETI_FIN', 8800.0, 200.0, [200.0, 190.0, 160.0]],
  ['YETI_18K', 'PAINT_PREP', 9000.0, 40.0, null],
  ['YETI_18K', 'PAINT_B', 9200.0, 70.0, null],
  ['YETI_18K', 'HYDRAULICS', 9700.0, 50.0, null],
  ['YETI_18K', 'WOOD', 10500.0, 60.0, null],
  ['YETI_21K', 'YETI_JIG', 10400.0, 225.0, null],
  ['YETI_21K', 'YETI_FIN', 11300.0, 200.0, [200.0, 190.0, 160.0]],
  ['YETI_21K', 'PAINT_PREP', 11500.0, 40.0, null],
  ['YETI_21K', 'PAINT_B', 11700.0, 70.0, null],
  ['YETI_21K', 'HYDRAULICS', 12200.0, 50.0, null],
  ['YETI_21K', 'WOOD', 13000.0, 60.0, null],
  ['TLT_15K', 'YETI_JIG', 6900.0, 150.0, null],
  ['TLT_15K', 'YETI_FIN', 7800.0, 200.0, [200.0, 190.0, 160.0]],
  ['TLT_15K', 'PAINT_PREP', 8000.0, 40.0, null],
  ['TLT_15K', 'PAINT_B', 8200.0, 70.0, null],
  ['TLT_15K', 'HYDRAULICS', 8700.0, 70.0, null],
  ['TLT_15K', 'WOOD', 9500.0, 60.0, null],
  ['TLT_18K', 'YETI_JIG', 8900.0, 150.0, null],
  ['TLT_18K', 'YETI_FIN', 9800.0, 200.0, [200.0, 190.0, 160.0]],
  ['TLT_18K', 'PAINT_PREP', 10000.0, 40.0, null],
  ['TLT_18K', 'PAINT_B', 10200.0, 70.0, null],
  ['TLT_18K', 'HYDRAULICS', 10700.0, 70.0, null],
  ['TLT_18K', 'WOOD', 11500.0, 60.0, null],
  ['TLT_21K', 'YETI_JIG', 10400.0, 225.0, null],
  ['TLT_21K', 'YETI_FIN', 11300.0, 250.0, [250.0, 237.5, 200.0]],
  ['TLT_21K', 'PAINT_PREP', 11500.0, 40.0, null],
  ['TLT_21K', 'PAINT_B', 11700.0, 70.0, null],
  ['TLT_21K', 'HYDRAULICS', 12200.0, 70.0, null],
  ['TLT_21K', 'WOOD', 13000.0, 60.0, null],
];

async function ensureColumns(): Promise<void> {
  await prisma.$executeRawUnsafe(
    `ALTER TABLE trailer_model_stage_costs ADD COLUMN IF NOT EXISTS pay_dollars NUMERIC(10,2) NOT NULL DEFAULT 0;`,
  );
  await prisma.$executeRawUnsafe(
    `ALTER TABLE trailer_model_stage_costs ADD COLUMN IF NOT EXISTS worker_split JSONB;`,
  );
}

async function main(): Promise<void> {
  console.log('Loading flat pay + cost matrix...');
  await ensureColumns();
  console.log('  ok: pay_dollars + worker_split columns ensured');

  const models = await prisma.trailerModel.findMany({ select: { id: true, code: true } });
  const depts = await prisma.department.findMany({ select: { id: true, code: true } });
  const modelId = new Map(models.map((m) => [m.code, m.id]));
  const deptId = new Map(depts.map((d) => [d.code, d.id]));

  let ok = 0;
  const missing: string[] = [];
  for (const [mc, dc, cost, pay, split] of ROWS) {
    const mid = modelId.get(mc);
    const did = deptId.get(dc);
    if (mid == null || did == null) {
      missing.push(`${mc}/${dc}`);
      continue;
    }
    const data = {
      costDollars: new Prisma.Decimal(cost ?? 0),
      payDollars: new Prisma.Decimal(pay ?? 0),
      workerSplit: split ?? Prisma.JsonNull,
    };
    await prisma.trailerModelStageCost.upsert({
      where: {
        trailerModelId_departmentId_effectiveFrom: {
          trailerModelId: mid,
          departmentId: did,
          effectiveFrom: EFFECTIVE_FROM,
        },
      },
      create: { trailerModelId: mid, departmentId: did, effectiveFrom: EFFECTIVE_FROM, ...data },
      update: data,
    });
    ok++;
  }

  console.log(`Upserted ${ok}/${ROWS.length} stage rates.`);
  if (missing.length) console.log(`  WARN ${missing.length} unmapped (skipped): ${missing.join(', ')}`);

  // Points are retired: earned pay is now the stage payDollars stored on each
  // production step. The weekly report multiplies points x dept-dollar-rate, so
  // set every production dept's rate to exactly 1.0 as of the switch date — the
  // math then yields dollars unchanged.
  const prodDepts = await prisma.department.findMany({
    where: { isQcStep: false },
    select: { id: true },
  });
  for (const d of prodDepts) {
    await prisma.deptDollarRate.upsert({
      where: {
        departmentId_effectiveFrom: { departmentId: d.id, effectiveFrom: EFFECTIVE_FROM },
      },
      create: {
        departmentId: d.id,
        effectiveFrom: EFFECTIVE_FROM,
        dollarPerPoint: new Prisma.Decimal(1),
      },
      update: { dollarPerPoint: new Prisma.Decimal(1) },
    });
  }
  console.log(`Set ${prodDepts.length} dept dollar rates to 1.0 (dollars == points now).`);
  console.log('Done.');
}

main()
  .catch((e) => { console.error('Load failed:', e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); });
