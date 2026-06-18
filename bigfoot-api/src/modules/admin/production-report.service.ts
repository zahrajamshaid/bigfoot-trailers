import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { AppError, ErrorCode } from '../../common/errors';

export interface UpsertStageCostInput {
  trailerModelId: number;
  departmentId: number;
  costDollars: number | string;
  /** ISO date (YYYY-MM-DD). Defaults to today — same semantics as PointValue. */
  effectiveFrom?: string;
}

@Injectable()
export class ProductionReportService {
  constructor(private readonly prisma: PrismaService) {}

  // ---------------------------------------------------------------------------
  // Cost matrix
  // ---------------------------------------------------------------------------
  /**
   * Build a grid of (trailer model x non-QC department) → dollar cost using
   * the most recent `effective_from` row per cell. Empty cells are omitted —
   * the mobile screen renders them as "—" so admin can spot what still
   * needs a value.
   */
  async getCostMatrix() {
    const [models, departments, latestPerCell] = await Promise.all([
      this.prisma.trailerModel.findMany({
        where: { isActive: true },
        select: { id: true, code: true, displayName: true, series: true },
        orderBy: { displayName: 'asc' },
      }),
      // QC departments don't represent stages with a dollar cost — they're
      // checkpoints. Match the payroll matrix's behavior so the two grids
      // stay consistent visually.
      this.prisma.department.findMany({
        where: { isQcStep: false },
        select: { id: true, code: true, displayName: true, isQcStep: true },
        orderBy: { code: 'asc' },
      }),
      // For each (model, dept) pair, the row with the latest effectiveFrom.
      // distinct works because Prisma resolves it via SQL DISTINCT ON when
      // combined with the right orderBy.
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

  /**
   * Upsert a single (model, dept, effectiveFrom) cell. Idempotent — if the
   * cell already exists for that date we update the cost in place; otherwise
   * a new effective-dated row is created and the prior row stays untouched
   * so history is preserved.
   */
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
    // Date-only column — strip the time portion so two calls on the same
    // day land on the same row instead of creating duplicates.
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
  // Weekly production report
  // ---------------------------------------------------------------------------
  /**
   * Production throughput + WIP cost for the calendar week that contains
   * the supplied date. `weekStart` is treated as a date-only marker; the
   * actual window is Sunday 00:00 → next Sunday 00:00 UTC (matches the
   * payroll/weekly-completed conventions already used elsewhere).
   */
  async getWeeklyReport(weekStart: string) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(weekStart)) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'weekStart must be a YYYY-MM-DD date',
      );
    }
    const start = this.startOfWeek(new Date(`${weekStart}T00:00:00Z`));
    const end = new Date(start.getTime() + 7 * 24 * 60 * 60 * 1000);

    // Throughput counts. Each query has a tight where so the response stays
    // O(few queries) regardless of trailer volume.
    const [
      enteredCount,
      exitedRows,
      deliveredCount,
      inProductionCount,
      readyForDeliveryCount,
      inventoryByYard,
      wip,
    ] = await Promise.all([
      // Entered production this week — the FIRST production_step of a
      // trailer became active during the window. Step.stepOrder is the
      // natural ordinal; we filter on it == 1 so a re-routed trailer
      // doesn't double-count.
      this.prisma.productionStep.count({
        where: {
          stepOrder: 1,
          becameActiveAt: { gte: start, lt: end },
        },
      }),
      // Exited production — FINAL_QC pass that landed in this week. Group
      // by series so the report can break the throughput down.
      this.prisma.qcInspection.findMany({
        where: {
          result: 'pass',
          isFinalQc: true,
          inspectedAt: { gte: start, lt: end },
        },
        select: {
          trailer: { select: { trailerModel: { select: { series: true } } } },
        },
      }),
      // Delivered customer / yard handoffs in the window.
      this.prisma.delivery.count({
        where: {
          status: 'delivered',
          deliveredAt: { gte: start, lt: end },
        },
      }),
      this.prisma.trailer.count({ where: { status: 'in_production' } }),
      this.prisma.trailer.count({ where: { status: 'ready_for_delivery' } }),
      // Yard inventory snapshot: trailers whose status == ready_for_delivery
      // and currentLocation is non-factory. ready+not-factory ≈ "open stock
      // at a satellite yard"; the Mulberry-resident pool counts under that
      // yard so admins see the full picture.
      this.prisma.trailer.groupBy({
        by: ['currentLocationId'],
        where: { status: 'ready_for_delivery' },
        _count: { _all: true },
      }),
      this.computeWipCost(),
    ]);

    const exitedBySeries: Record<string, number> = {};
    for (const row of exitedRows) {
      const s = row.trailer.trailerModel.series as string;
      exitedBySeries[s] = (exitedBySeries[s] ?? 0) + 1;
    }

    // Resolve location codes for the inventory groupby.
    const locIds = inventoryByYard.map((r) => r.currentLocationId);
    const locations = locIds.length
      ? await this.prisma.location.findMany({
          where: { id: { in: locIds } },
          select: { id: true, code: true, name: true, isFactory: true },
        })
      : [];
    const byLocId = new Map(locations.map((l) => [l.id, l]));
    const inventory = inventoryByYard
      .map((r) => ({
        locationId: r.currentLocationId,
        code: byLocId.get(r.currentLocationId)?.code ?? '?',
        name: byLocId.get(r.currentLocationId)?.name ?? '?',
        isFactory: byLocId.get(r.currentLocationId)?.isFactory ?? false,
        count: r._count._all,
      }))
      .sort((a, b) => a.code.localeCompare(b.code));

    return {
      weekStart: start.toISOString().slice(0, 10),
      weekEnd: end.toISOString().slice(0, 10),
      throughput: {
        enteredProduction: enteredCount,
        exitedProduction: exitedRows.length,
        exitedBySeries,
        delivered: deliveredCount,
      },
      snapshot: {
        inProduction: inProductionCount,
        readyForDelivery: readyForDeliveryCount,
        inventoryByYard: inventory,
      },
      wipCost: wip,
    };
  }

  // ---------------------------------------------------------------------------
  // WIP cost helper
  // ---------------------------------------------------------------------------
  // Returns:
  //   totalCumulative — sum of (matrix cost) for every COMPLETED step on
  //                     every in_production trailer.
  //   totalProjected  — sum of (matrix cost) for ALL steps in each trailer's
  //                     model workflow (rough invested-capital ceiling).
  //   perTrailer      — per-trailer breakdown so the report can render a
  //                     drill-down table.
  // ---------------------------------------------------------------------------
  private async computeWipCost() {
    // 1) Pull all in-production trailers + their steps. Trailer model id is
    //    cached so the cost lookup runs in one extra query, not N+1.
    const trailers = await this.prisma.trailer.findMany({
      where: { status: 'in_production' },
      select: {
        id: true,
        soNumber: true,
        trailerModelId: true,
        trailerModel: { select: { code: true, displayName: true, series: true } },
        productionSteps: {
          select: {
            departmentId: true,
            status: true,
          },
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
          cumulativeDollars: number;
          projectedDollars: number;
        }>,
      };
    }

    // 2) One pass to find every (model, dept) pair we need a cost for.
    const cellKeys = new Set<string>();
    for (const t of trailers) {
      for (const s of t.productionSteps) {
        cellKeys.add(`${t.trailerModelId}:${s.departmentId}`);
      }
    }

    // 3) Fetch the latest cost cell for each of those pairs in one batch.
    //    distinct + orderBy desc(effectiveFrom) gives us "latest only".
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

    // 4) Sum per trailer + roll up totals.
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

  /// Truncate a Date to the Sunday-00:00:00 UTC of its calendar week.
  /// Matches the payroll convention used elsewhere in admin.service.
  private startOfWeek(d: Date): Date {
    const dayOfWeek = d.getUTCDay(); // Sun=0 … Sat=6
    return new Date(
      Date.UTC(
        d.getUTCFullYear(),
        d.getUTCMonth(),
        d.getUTCDate() - dayOfWeek,
      ),
    );
  }
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
