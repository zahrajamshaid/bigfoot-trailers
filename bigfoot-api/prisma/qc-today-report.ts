// =============================================================================
// BIGFOOT TRAILERS — Read-only: list trailers QC'd today
//
// Prints every QC inspection submitted today (server local time) with:
//   • SO number
//   • Pass / fail result
//   • QC department (QC_1 … FINAL_QC)
//   • Inspector name
//   • Timestamp
//
// Scope:
//   • All users (inspectors, production managers, owners) — anyone who has
//     hit POST /qc/inspections today. The "today" window is local server
//     time from 00:00:00 to 23:59:59.
//   • Both pass and fail results are included; failures are flagged.
//
// Read-only — no writes. Safe to re-run as many times as you want.
// =============================================================================

import 'dotenv/config';
import { createPrismaClient } from './db-client';

const prisma = createPrismaClient();

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function endOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
}

async function main(): Promise<void> {
  const now = new Date();
  const dayStart = startOfDay(now);
  const dayEnd = endOfDay(now);

  console.log(
    `🔍 QC inspections submitted today (${dayStart.toISOString().slice(0, 10)})\n`,
  );

  const inspections = await prisma.qcInspection.findMany({
    where: { inspectedAt: { gte: dayStart, lte: dayEnd } },
    orderBy: { inspectedAt: 'asc' },
    select: {
      id: true,
      result: true,
      inspectedAt: true,
      isFinalQc: true,
      trailer: { select: { soNumber: true } },
      productionStep: {
        select: {
          stepOrder: true,
          department: { select: { code: true, displayName: true } },
        },
      },
      inspectorUser: { select: { fullName: true, email: true, role: true } },
    },
  });

  if (inspections.length === 0) {
    console.log('  (no inspections recorded today)');
    return;
  }

  // ── Header ──
  console.log(
    `  ${'SO'.padEnd(8)}${'Result'.padEnd(8)}${'QC dept'.padEnd(12)}${'Inspector'.padEnd(28)}Time`,
  );
  console.log(`  ${'─'.repeat(80)}`);

  let pass = 0;
  let fail = 0;
  const perInspector = new Map<string, number>();
  const trailersSeen = new Set<string>();

  for (const i of inspections) {
    const so = i.trailer.soNumber.padEnd(8);
    const result = i.result.padEnd(8);
    const dept = (i.productionStep.department.code ?? '?').padEnd(12);
    const inspector = (i.inspectorUser.fullName ?? i.inspectorUser.email).padEnd(28);
    const time = i.inspectedAt.toISOString().slice(11, 19) + 'Z';
    console.log(`  ${so}${result}${dept}${inspector}${time}`);

    if (i.result === 'pass') pass++;
    else fail++;
    perInspector.set(
      i.inspectorUser.fullName ?? i.inspectorUser.email,
      (perInspector.get(i.inspectorUser.fullName ?? i.inspectorUser.email) ?? 0) + 1,
    );
    trailersSeen.add(i.trailer.soNumber);
  }

  console.log(`\n📊 Totals\n`);
  console.log(`  ${inspections.length} inspection(s) — ${pass} pass / ${fail} fail`);
  console.log(`  ${trailersSeen.size} distinct trailer(s) touched`);
  console.log(`\n  by inspector:`);
  const inspectors = Array.from(perInspector.entries()).sort((a, b) => b[1] - a[1]);
  for (const [name, n] of inspectors) {
    console.log(`    ${n.toString().padStart(3)}  ${name}`);
  }

  console.log(`\n📋 Distinct SO numbers (for pasting into Slack / mobile filter):`);
  console.log(`  ${Array.from(trailersSeen).sort().join(', ')}`);
}

main()
  .catch((e) => {
    console.error('❌ QC report failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
