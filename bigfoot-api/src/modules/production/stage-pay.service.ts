import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';

/** Manual per-completion pay inputs the worker/PM supplies (add-ons aren't
 *  structured data, so jacks/ramps/toolbox/tire-swaps come in here). */
export interface PayAdjustmentsInput {
  hydraulicJack?: 'single' | 'double' | 'ramps_jack';
  toolbox?: boolean;
  rampJacks?: number;
  tireSwaps?: number;
}

export interface RecordPayoutsParams {
  stepId: bigint;
  departmentId: number;
  deptCode: string;
  series: string;
  sizeFt: string | null;
  color: string | null;
  completedByUserId: bigint;
  isRework: boolean;
  payDollars: number;
  /** worker_split from the stage rate (crew stages only), highest→lowest. */
  workerSplit: number[] | null;
  adjustments?: PayAdjustmentsInput;
}

// Series that run the gooseneck line — the ">30ft on GN" adjustment tiers.
const GN_SERIES = new Set(['gooseneck_dump', 'gooseneck_yeti', 'cxp']);

function parseFt(sizeFt: string | null): number | null {
  if (!sizeFt) return null;
  const m = String(sizeFt).match(/(\d+(?:\.\d+)?)/);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) ? n : null;
}

function isNonGray(color: string | null): boolean {
  if (!color) return false;
  const c = color.trim().toLowerCase();
  if (!c) return false;
  return !(c.includes('gray') || c.includes('grey'));
}

/**
 * Computes and writes the per-worker payout rows for a completed step. Payroll
 * reads dollars straight from these rows, so this is where the whole pay model
 * (flat stage pay, crew splits, conditional adjustments) actually lands.
 * Must be called inside the completion transaction.
 */
@Injectable()
export class StagePayService {
  async recordPayouts(
    tx: Prisma.TransactionClient,
    p: RecordPayoutsParams,
  ): Promise<void> {
    if (p.isRework) return; // rework is uncompensated

    // Idempotent: never double-pay a step (this runs best-effort after commit).
    const already = await tx.productionStepPayout.count({
      where: { productionStepId: p.stepId },
    });
    if (already > 0) return;

    const rows: Array<{
      userId: bigint;
      dollars: number;
      kind: string;
      note: string | null;
    }> = [];
    const split = p.workerSplit && p.workerSplit.length > 1 ? p.workerSplit : null;

    // ── Base pay ──────────────────────────────────────────────────────────
    if (split) {
      // Crew stage: pay each roster member their slot's rate.
      const roster = await tx.stageCrewMember.findMany({
        where: { departmentId: p.departmentId },
        orderBy: { slot: 'asc' },
        select: { slot: true, userId: true },
      });
      if (roster.length > 0) {
        for (const m of roster) {
          const rate = split[m.slot];
          if (rate != null) {
            rows.push({
              userId: m.userId,
              dollars: rate,
              kind: 'base',
              note: `crew slot ${m.slot + 1}`,
            });
          }
        }
      } else {
        // No roster configured yet — don't lose the pay: credit the completer
        // the primary rate until a crew is set.
        rows.push({
          userId: p.completedByUserId,
          dollars: split[0],
          kind: 'base',
          note: 'crew (no roster set) — primary rate',
        });
      }
    } else {
      rows.push({
        userId: p.completedByUserId,
        dollars: p.payDollars,
        kind: 'base',
        note: null,
      });
    }

    // ── Adjustments (credited to the completer) ───────────────────────────
    const ft = parseFt(p.sizeFt);
    const over30 = ft != null && ft > 30;
    const isGN = GN_SERIES.has(p.series);
    const a = p.adjustments;
    const add = (d: number, note: string) => {
      if (d > 0)
        rows.push({ userId: p.completedByUserId, dollars: d, kind: 'adjustment', note });
    };

    switch (p.deptCode) {
      case 'PAINT_PREP':
        if (over30) add(14, 'over 30ft prep');
        break;
      case 'WOOD':
        if (over30) add(isGN ? 30 : 15, isGN ? 'over 30ft wood (GN)' : 'over 30ft wood');
        if (a?.tireSwaps) add(25 * a.tireSwaps, `${a.tireSwaps} tire swap(s)`);
        break;
      case 'PAINT_B':
      case 'PAINT_A':
        if (over30)
          add(isGN ? 50 : 20, isGN ? 'over 30ft paint (GN)' : 'over 30ft paint');
        if (isNonGray(p.color)) add(p.payDollars, 'non-gray double paint');
        if (a?.rampJacks) add(15 * a.rampJacks, `${a.rampJacks} ramp jack(s)`);
        break;
      case 'WIRE':
        if (a?.hydraulicJack === 'single') add(40, 'single hydraulic jack');
        else if (a?.hydraulicJack === 'double') add(65, 'double hydraulic jack');
        else if (a?.hydraulicJack === 'ramps_jack') add(125, 'hydraulic ramps + jack');
        if (a?.toolbox) add(15, 'plastic toolbox');
        break;
      default:
        break;
    }

    if (rows.length > 0) {
      await tx.productionStepPayout.createMany({
        data: rows.map((r) => ({
          productionStepId: p.stepId,
          userId: r.userId,
          dollars: new Prisma.Decimal(r.dollars),
          kind: r.kind,
          note: r.note,
        })),
      });
    }
  }
}
