import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { AppError, ErrorCode } from '../../common/errors';
import {
  HealthCheckPeriod,
  HEALTH_CHECK_PERIODS,
} from './dto/health-check-query.dto';

export interface UpsertStageCostInput {
  trailerModelId: number;
  departmentId: number;
  costDollars: number | string;
  /** ISO date (YYYY-MM-DD). Defaults to today — same semantics as PointValue. */
  effectiveFrom?: string;
}

export interface HealthCheckParams {
  period?: HealthCheckPeriod;
  start?: string;
  end?: string;
}

interface ResolvedWindow {
  period: HealthCheckPeriod;
  start: Date;
  end: Date; // exclusive
}

@Injectable()
export class ProductionReportService {
  constructor(private readonly prisma: PrismaService) {}

  // ---------------------------------------------------------------------------
  // Cost matrix
  // ---------------------------------------------------------------------------
  async getCostMatrix() {
    const [models, departments, latestPerCell] = await Promise.all([
      this.prisma.trailerModel.findMany({
        where: { isActive: true },
        select: { id: true, code: true, displayName: true, series: true },
        orderBy: { displayName: 'asc' },
      }),
      this.prisma.department.findMany({
        where: { isQcStep: false },
        select: { id: true, code: true, displayName: true, isQcStep: true },
        orderBy: { code: 'asc' },
      }),
      this.prisma.trailerModelStageCost.findMany({
        distinct: ['trailerModelId', 'departmentId'],
        orderBy: [
          { trailerModelId: 'asc' },
          { departmentId: 'asc' },
          { effectiveFrom: 'desc' },
        ],
        select: {
          trailerModelId: true,
          departmentId: true,
          costDollars: true,
          effectiveFrom: true,
        },
      }),
    ]);

    const cells = latestPerCell.map((c) => ({
      trailerModelId: c.trailerModelId,
      departmentId: c.departmentId,
      costDollars: Number(c.costDollars),
      effectiveFrom: c.effectiveFrom.toISOString().slice(0, 10),
    }));

    return { models, departments, cells };
  }

  async upsertStageCost(dto: UpsertStageCostInput) {
    const cost = new Prisma.Decimal(dto.costDollars);
    if (cost.lt(0)) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'costDollars must be greater than or equal to 0',
      );
    }
    const effectiveFrom = dto.effectiveFrom
      ? new Date(dto.effectiveFrom)
      : new Date();
    const effectiveDateOnly = new Date(
      Date.UTC(
        effectiveFrom.getUTCFullYear(),
        effectiveFrom.getUTCMonth(),
        effectiveFrom.getUTCDate(),
      ),
    );

    return this.prisma.trailerModelStageCost.upsert({
      where: {
        trailerModelId_departmentId_effectiveFrom: {
          trailerModelId: dto.trailerModelId,
          departmentId: dto.departmentId,
          effectiveFrom: effectiveDateOnly,
        },
      },
      create: {
        trailerModelId: dto.trailerModelId,
        departmentId: dto.departmentId,
        costDollars: cost,
        effectiveFrom: effectiveDateOnly,
      },
      update: { costDollars: cost },
      select: {
        id: true,
        trailerModelId: true,
        departmentId: true,
        costDollars: true,
        effectiveFrom: true,
      },
    });
  }

  // ---------------------------------------------------------------------------
  // Health Check report (formerly "weekly production report")
  // ---------------------------------------------------------------------------
  // Returns:
  //   window / previousWindow — resolved date ranges (previous = same length
  //     ending the day before current start, so +/- deltas are apples-to-apples)
  //   current / previous       — per-window throughput, sales, sold-vs-built
  //   live                     — point-in-time snapshot: in-production, ready,
  //                              inventory by yard, dept-waiting tile board,
  //                              sold-not-yet-started bucketed by first dept
  //   wipCost                  — cumulative vs projected $$ for in-prod trailers
  // ---------------------------------------------------------------------------
  async getReport(params: HealthCheckParams) {
    const window = this.resolveWindow(params);
    const previousWindow = this.resolvePreviousWindow(window);

    const [current, previous, live, wipCost] = await Promise.all([
      this.buildPeriodSnapshot(window.start, window.end),
      this.buildPeriodSnapshot(previousWindow.start, previousWindow.end),
      this.buildLiveSnapshot(),
      this.computeWipCost(),
    ]);

    return {
      window: {
        period: window.period,
        start: isoDate(window.start),
        end: isoDate(addDays(window.end, -1)), // inclusive end for display
      },
      previousWindow: {
        start: isoDate(previousWindow.start),
        end: isoDate(addDays(previousWindow.end, -1)),
      },
      current,
      previous,
      live,
      wipCost,
    };
  }

  // ---------------------------------------------------------------------------
  // Period resolution
  // ---------------------------------------------------------------------------
  private resolveWindow(params: HealthCheckParams): ResolvedWindow {
    const period: HealthCheckPeriod = params.period ?? 'weekly';
    if (!HEALTH_CHECK_PERIODS.includes(period)) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `period must be one of: ${HEALTH_CHECK_PERIODS.join(', ')}`,
      );
    }

    const pivot = params.start ? parseDateOnly(params.start) : todayUtc();

    switch (period) {
      case 'weekly': {
        const start = startOfWeek(pivot);
        return { period, start, end: addDays(start, 7) };
      }
      case 'biweekly': {
        const start = startOfWeek(pivot);
        return { period, start, end: addDays(start, 14) };
      }
      case 'monthly': {
        const start = startOfMonth(pivot);
        const end = startOfMonth(addDays(addDays(start, 31), 0));
        // addDays(start, 31) always lands inside the next month, then
        // startOfMonth snaps to that next month's first day. Robust against
        // 28/29/30/31 day months without manual math.
        return { period, start, end };
      }
      case 'custom': {
        if (!params.start || !params.end) {
          throw new AppError(
            ErrorCode.BAD_REQUEST,
            'period=custom requires both `start` and `end` (YYYY-MM-DD)',
          );
        }
        const start = parseDateOnly(params.start);
        const inclusiveEnd = parseDateOnly(params.end);
        if (inclusiveEnd.getTime() < start.getTime()) {
          throw new AppError(
            ErrorCode.BAD_REQUEST,
            '`end` must be on or after `start`',
          );
        }
        return { period, start, end: addDays(inclusiveEnd, 1) };
      }
    }
  }

  private resolvePreviousWindow(current: ResolvedWindow): ResolvedWindow {
    // Same-length window ending exactly at current.start (so [start - len, start)).
    const lengthMs = current.end.getTime() - current.start.getTime();
    const prevEnd = current.start;
    const prevStart = new Date(prevEnd.getTime() - lengthMs);
    return { period: current.period, start: prevStart, end: prevEnd };
  }

  // ---------------------------------------------------------------------------
  // Per-period snapshot: throughput + sales + sold-vs-built
  // ---------------------------------------------------------------------------
  private async buildPeriodSnapshot(start: Date, end: Date) {
    const [
      enteredCount,
      exitedRows,
      deliveredCount,
      customerOrderRows,
      openStockSoldRows,
    ] = await Promise.all([
      // Entered production: first production step became active in window.
      this.prisma.productionStep.count({
        where: {
          stepOrder: 1,
          becameActiveAt: { gte: start, lt: end },
        },
      }),
      // Exited production: passing FINAL_QC in window. Pull each row's model
      // so we can split by series + by model id for the sold-vs-built grid.
      this.prisma.qcInspection.findMany({
        where: {
          result: 'pass',
          isFinalQc: true,
          inspectedAt: { gte: start, lt: end },
        },
        select: {
          trailer: {
            select: {
              trailerModelId: true,
              trailerModel: {
                select: {
                  id: true,
                  code: true,
                  displayName: true,
                  series: true,
                },
              },
            },
          },
        },
      }),
      // Customer-facing deliveries that finished in window.
      this.prisma.delivery.count({
        where: {
          status: 'delivered',
          deliveredAt: { gte: start, lt: end },
        },
      }),
      // Customer orders: a trailer was created with a customerId attached
      // inside the window. Mirrors the "new order with a customer name"
      // sales definition.
      this.prisma.trailer.findMany({
        where: {
          customerId: { not: null },
          createdAt: { gte: start, lt: end },
        },
        select: {
          trailerModelId: true,
          trailerModel: {
            select: { id: true, code: true, displayName: true, series: true },
          },
        },
      }),
      // Open-stock sold: trailer was a stock build (created without a
      // customer) and is now marked sold inside the window. saleStatus has
      // no dedicated sold-at column, so we approximate with updatedAt. Stock
      // builds rarely receive other edits after the sale flip, so this is
      // usually correct; if drift matters we'll move to audit_log later.
      this.prisma.trailer.findMany({
        where: {
          isStockBuild: true,
          saleStatus: 'sold',
          updatedAt: { gte: start, lt: end },
        },
        select: {
          trailerModelId: true,
          trailerModel: {
            select: { id: true, code: true, displayName: true, series: true },
          },
        },
      }),
    ]);

    // ── Throughput ─────────────────────────────────────────────────────────
    const exitedBySeries: Record<string, number> = {};
    for (const row of exitedRows) {
      const s = row.trailer.trailerModel.series as string;
      exitedBySeries[s] = (exitedBySeries[s] ?? 0) + 1;
    }

    // ── Sales totals ───────────────────────────────────────────────────────
    const customerOrders = customerOrderRows.length;
    const openStockSold = openStockSoldRows.length;
    const totalSales = customerOrders + openStockSold;

    // ── Sold vs Built per model ────────────────────────────────────────────
    type ModelAgg = {
      modelId: number;
      modelCode: string;
      modelName: string;
      series: string;
      sold: number;
      built: number;
    };
    const perModel = new Map<number, ModelAgg>();
    const bumpSold = (m: {
      id: number;
      code: string;
      displayName: string;
      series: string;
    }) => {
      const entry = perModel.get(m.id) ?? {
        modelId: m.id,
        modelCode: m.code,
        modelName: m.displayName,
        series: m.series,
        sold: 0,
        built: 0,
      };
      entry.sold += 1;
      perModel.set(m.id, entry);
    };
    const bumpBuilt = (m: {
      id: number;
      code: string;
      displayName: string;
      series: string;
    }) => {
      const entry = perModel.get(m.id) ?? {
        modelId: m.id,
        modelCode: m.code,
        modelName: m.displayName,
        series: m.series,
        sold: 0,
        built: 0,
      };
      entry.built += 1;
      perModel.set(m.id, entry);
    };
    for (const r of customerOrderRows) {
      bumpSold(r.trailerModel as any);
    }
    for (const r of openStockSoldRows) {
      bumpSold(r.trailerModel as any);
    }
    for (const r of exitedRows) {
      bumpBuilt(r.trailer.trailerModel as any);
    }

    const soldVsBuilt = {
      perModel: Array.from(perModel.values()).sort((a, b) =>
        a.modelCode.localeCompare(b.modelCode),
      ),
      totalSold: totalSales,
      totalBuilt: exitedRows.length,
    };

    return {
      throughput: {
        enteredProduction: enteredCount,
        exitedProduction: exitedRows.length,
        delivered: deliveredCount,
        exitedBySeries,
      },
      sales: {
        customerOrders,
        openStockSold,
        totalSales,
      },
      soldVsBuilt,
    };
  }

  // ---------------------------------------------------------------------------
  // Live (point-in-time) snapshot: dept tile board + inventory + sold-here
  // ---------------------------------------------------------------------------
  private async buildLiveSnapshot() {
    const [
      inProductionCount,
      readyForDeliveryCount,
      inventoryGroup,
      departments,
      activeSteps,
    ] = await Promise.all([
      this.prisma.trailer.count({ where: { status: 'in_production' } }),
      this.prisma.trailer.count({ where: { status: 'ready_for_delivery' } }),
      this.prisma.trailer.groupBy({
        by: ['currentLocationId'],
        where: { status: 'ready_for_delivery' },
        _count: { _all: true },
      }),
      this.prisma.department.findMany({
        where: { isQcStep: false },
        select: { id: true, code: true, displayName: true },
        orderBy: { id: 'asc' },
      }),
      // Every trailer's currently-active step + the trailer's saleStatus,
      // so we can colour each dept tile with both the "waiting" count and
      // the "sold here" count off the same pass. Production is sequential
      // so each in-prod trailer has exactly one row.
      this.prisma.productionStep.findMany({
        where: { status: 'active' },
        select: {
          trailerId: true,
          stepOrder: true,
          departmentId: true,
          department: {
            select: { id: true, code: true, isQcStep: true },
          },
          trailer: { select: { saleStatus: true } },
        },
      }),
    ]);

    // ── Inventory by yard ──────────────────────────────────────────────────
    const locIds = inventoryGroup.map((r) => r.currentLocationId);
    const locations = locIds.length
      ? await this.prisma.location.findMany({
          where: { id: { in: locIds } },
          select: { id: true, code: true, name: true, isFactory: true },
        })
      : [];
    const byLocId = new Map(locations.map((l) => [l.id, l]));
    const inventoryByYard = inventoryGroup
      .map((r) => ({
        locationId: r.currentLocationId,
        code: byLocId.get(r.currentLocationId)?.code ?? '?',
        name: byLocId.get(r.currentLocationId)?.name ?? '?',
        isFactory: byLocId.get(r.currentLocationId)?.isFactory ?? false,
        count: r._count._all,
      }))
      .sort((a, b) => a.code.localeCompare(b.code));

    // ── Department tile board ──────────────────────────────────────────────
    // For each active step, attribute it to a non-QC department. If the
    // active step IS a QC step, roll it back to its predecessor (the prod
    // step it inspects). The predecessor is "step_order - 1" on the same
    // trailer. We batch-fetch all those predecessor rows in a single query.
    const qcActiveSteps = activeSteps.filter((s) => s.department.isQcStep);
    let priorByTrailer = new Map<string, number>();
    if (qcActiveSteps.length > 0) {
      const priorSteps = await this.prisma.productionStep.findMany({
        where: {
          OR: qcActiveSteps.map((s) => ({
            trailerId: s.trailerId,
            stepOrder: s.stepOrder - 1,
          })),
        },
        select: { trailerId: true, stepOrder: true, departmentId: true },
      });
      priorByTrailer = new Map(
        priorSteps.map((s) => [`${s.trailerId}:${s.stepOrder}`, s.departmentId]),
      );
    }

    const waitingByDeptId = new Map<number, number>();
    const soldByDeptId = new Map<number, number>();
    for (const step of activeSteps) {
      let bucketDeptId = step.departmentId;
      if (step.department.isQcStep) {
        const prior = priorByTrailer.get(
          `${step.trailerId}:${step.stepOrder - 1}`,
        );
        if (prior == null) continue; // step_order=1 is never QC, so this is a data anomaly — skip rather than miscount
        bucketDeptId = prior;
      }
      waitingByDeptId.set(
        bucketDeptId,
        (waitingByDeptId.get(bucketDeptId) ?? 0) + 1,
      );
      // "Sold here" — count of sold trailers currently active at this
      // dept (with QC active steps rolled back into the prior prod dept
      // exactly like the waiting count, so a sold trailer parked at QC_2
      // shows up on XP Finish where the work is). Replaces the old
      // "sold not started" badge, which only ever lit up the first
      // welding dept and obscured how much sold work is actually mid-build.
      if (step.trailer.saleStatus === 'sold') {
        soldByDeptId.set(
          bucketDeptId,
          (soldByDeptId.get(bucketDeptId) ?? 0) + 1,
        );
      }
    }

    const deptBoard = departments.map((d) => ({
      departmentId: d.id,
      code: d.code,
      displayName: d.displayName,
      waiting: waitingByDeptId.get(d.id) ?? 0,
      // Renamed from soldNotStarted — the semantic flipped to "sold
      // trailers currently being worked on here." Mobile mirrors the
      // rename; the previous build was only out for a couple of days so
      // there's no long-tail client to keep the old name alive for.
      soldHere: soldByDeptId.get(d.id) ?? 0,
    }));

    const soldHereTotal = Array.from(soldByDeptId.values()).reduce(
      (a, b) => a + b,
      0,
    );

    return {
      inProduction: inProductionCount,
      readyForDelivery: readyForDeliveryCount,
      inventoryByYard,
      departments: deptBoard,
      soldHereTotal,
    };
  }

  // ---------------------------------------------------------------------------
  // WIP cost (unchanged from prior implementation)
  // ---------------------------------------------------------------------------
  private async computeWipCost() {
    const trailers = await this.prisma.trailer.findMany({
      where: { status: 'in_production' },
      select: {
        id: true,
        soNumber: true,
        trailerModelId: true,
        trailerModel: {
          select: { code: true, displayName: true, series: true },
        },
        productionSteps: {
          select: { departmentId: true, status: true },
        },
      },
    });

    if (trailers.length === 0) {
      return {
        totalCumulativeDollars: 0,
        totalProjectedDollars: 0,
        perTrailer: [] as Array<{
          trailerId: string;
          soNumber: string;
          modelCode: string;
          modelName: string;
          cumulativeDollars: number;
          projectedDollars: number;
        }>,
      };
    }

    const modelIds = [...new Set(trailers.map((t) => t.trailerModelId))];
    const deptIds = [
      ...new Set(
        trailers.flatMap((t) => t.productionSteps.map((s) => s.departmentId)),
      ),
    ];
    const cells = await this.prisma.trailerModelStageCost.findMany({
      where: {
        trailerModelId: { in: modelIds },
        departmentId: { in: deptIds },
      },
      distinct: ['trailerModelId', 'departmentId'],
      orderBy: [
        { trailerModelId: 'asc' },
        { departmentId: 'asc' },
        { effectiveFrom: 'desc' },
      ],
      select: {
        trailerModelId: true,
        departmentId: true,
        costDollars: true,
      },
    });

    const costFor = new Map<string, number>();
    for (const c of cells) {
      costFor.set(
        `${c.trailerModelId}:${c.departmentId}`,
        Number(c.costDollars),
      );
    }

    let totalCumulative = 0;
    let totalProjected = 0;
    const perTrailer = trailers.map((t) => {
      let cumulative = 0;
      let projected = 0;
      for (const s of t.productionSteps) {
        const cost = costFor.get(`${t.trailerModelId}:${s.departmentId}`) ?? 0;
        projected += cost;
        if (s.status === 'complete') cumulative += cost;
      }
      totalCumulative += cumulative;
      totalProjected += projected;
      return {
        trailerId: t.id.toString(),
        soNumber: t.soNumber,
        modelCode: t.trailerModel.code,
        modelName: t.trailerModel.displayName,
        cumulativeDollars: round2(cumulative),
        projectedDollars: round2(projected),
      };
    });

    perTrailer.sort((a, b) => b.cumulativeDollars - a.cumulativeDollars);

    return {
      totalCumulativeDollars: round2(totalCumulative),
      totalProjectedDollars: round2(totalProjected),
      perTrailer,
    };
  }
}

// =============================================================================
// Date helpers (all UTC, date-only)
// =============================================================================

function parseDateOnly(s: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    throw new AppError(
      ErrorCode.BAD_REQUEST,
      `date must be YYYY-MM-DD (got "${s}")`,
    );
  }
  return new Date(`${s}T00:00:00Z`);
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function addDays(d: Date, days: number): Date {
  return new Date(
    Date.UTC(
      d.getUTCFullYear(),
      d.getUTCMonth(),
      d.getUTCDate() + days,
    ),
  );
}

function startOfWeek(d: Date): Date {
  const dow = d.getUTCDay(); // Sun=0 … Sat=6
  return new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - dow),
  );
}

function startOfMonth(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1));
}

function todayUtc(): Date {
  const now = new Date();
  return new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
