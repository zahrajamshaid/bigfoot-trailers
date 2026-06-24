import { Test, TestingModule } from '@nestjs/testing';
import { Prisma } from '@prisma/client';
import { ProductionReportService } from './production-report.service';
import { PrismaService } from '../../prisma/prisma.service';
import { ErrorCode } from '../../common/errors';

describe('ProductionReportService', () => {
  let service: ProductionReportService;

  const mockPrisma = {
    trailerModel: { findMany: jest.fn() },
    department: { findMany: jest.fn() },
    trailerModelStageCost: {
      findMany: jest.fn(),
      upsert: jest.fn(),
    },
    productionStep: { count: jest.fn(), findMany: jest.fn() },
    qcInspection: { findMany: jest.fn() },
    delivery: { count: jest.fn() },
    trailer: { count: jest.fn(), findMany: jest.fn(), groupBy: jest.fn() },
    location: { findMany: jest.fn() },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ProductionReportService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<ProductionReportService>(ProductionReportService);
    jest.clearAllMocks();
  });

  // ==========================================================================
  // getCostMatrix
  // ==========================================================================
  describe('getCostMatrix', () => {
    it('returns models, non-QC departments, and the latest cell per pair', async () => {
      mockPrisma.trailerModel.findMany.mockResolvedValue([
        { id: 1, code: 'XP_14ET', displayName: '14K XP', series: 'xp' },
      ]);
      mockPrisma.department.findMany.mockResolvedValue([
        { id: 10, code: 'WIRE', displayName: 'Wiring', isQcStep: false },
      ]);
      mockPrisma.trailerModelStageCost.findMany.mockResolvedValue([
        {
          trailerModelId: 1,
          departmentId: 10,
          costDollars: new Prisma.Decimal('425.50'),
          effectiveFrom: new Date('2026-06-19T00:00:00Z'),
        },
      ]);

      const result = await service.getCostMatrix();

      expect(result.models).toHaveLength(1);
      expect(result.departments[0].code).toBe('WIRE');
      expect(mockPrisma.department.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ isQcStep: false }),
        }),
      );
      expect(result.cells).toEqual([
        {
          trailerModelId: 1,
          departmentId: 10,
          costDollars: 425.5,
          effectiveFrom: '2026-06-19',
        },
      ]);
    });
  });

  // ==========================================================================
  // upsertStageCost
  // ==========================================================================
  describe('upsertStageCost', () => {
    it('rejects negative dollar amounts', async () => {
      await expect(
        service.upsertStageCost({
          trailerModelId: 1,
          departmentId: 10,
          costDollars: -5,
        }),
      ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
    });

    it('strips time of day so two same-day calls hit the same row', async () => {
      mockPrisma.trailerModelStageCost.upsert.mockResolvedValue({ id: 99 });

      await service.upsertStageCost({
        trailerModelId: 1,
        departmentId: 10,
        costDollars: 100,
        effectiveFrom: '2026-06-19',
      });

      const args = mockPrisma.trailerModelStageCost.upsert.mock.calls[0][0];
      const whereDate = args.where
        .trailerModelId_departmentId_effectiveFrom.effectiveFrom as Date;
      expect(whereDate.toISOString()).toBe('2026-06-19T00:00:00.000Z');
    });
  });

  // ==========================================================================
  // getReport
  // ==========================================================================
  describe('getReport', () => {
    // Every test stubs the same wide set of zero defaults so individual tests
    // only set the queries they actually care about.
    beforeEach(() => {
      mockPrisma.productionStep.count.mockResolvedValue(0);
      mockPrisma.productionStep.findMany.mockResolvedValue([]);
      mockPrisma.qcInspection.findMany.mockResolvedValue([]);
      mockPrisma.delivery.count.mockResolvedValue(0);
      mockPrisma.trailer.count.mockResolvedValue(0);
      mockPrisma.trailer.findMany.mockResolvedValue([]);
      mockPrisma.trailer.groupBy.mockResolvedValue([]);
      mockPrisma.department.findMany.mockResolvedValue([]);
      mockPrisma.location.findMany.mockResolvedValue([]);
      mockPrisma.trailerModelStageCost.findMany.mockResolvedValue([]);
    });

    it('rejects an invalid period', async () => {
      await expect(
        service.getReport({ period: 'forever' as any }),
      ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
    });

    it('snaps weekly windows to Sunday and exposes inclusive end', async () => {
      // 2026-06-19 is a Friday → Sunday of that week is 2026-06-14, end +6
      const result = await service.getReport({
        period: 'weekly',
        start: '2026-06-19',
      });
      expect(result.window.start).toBe('2026-06-14');
      expect(result.window.end).toBe('2026-06-20'); // inclusive last day of window
      // Previous = same length ending the day before current.start = 2026-06-07..13
      expect(result.previousWindow.start).toBe('2026-06-07');
      expect(result.previousWindow.end).toBe('2026-06-13');
    });

    it('produces a 14-day biweekly window from the containing Sunday', async () => {
      const result = await service.getReport({
        period: 'biweekly',
        start: '2026-06-19',
      });
      expect(result.window.start).toBe('2026-06-14');
      expect(result.window.end).toBe('2026-06-27');
    });

    it('snaps monthly to first..last day of the calendar month', async () => {
      const result = await service.getReport({
        period: 'monthly',
        start: '2026-06-19',
      });
      expect(result.window.start).toBe('2026-06-01');
      expect(result.window.end).toBe('2026-06-30');
    });

    it('honors custom start/end inclusive', async () => {
      const result = await service.getReport({
        period: 'custom',
        start: '2026-06-10',
        end: '2026-06-20',
      });
      expect(result.window.start).toBe('2026-06-10');
      expect(result.window.end).toBe('2026-06-20');
      // previous = 11-day window ending the day before current start
      expect(result.previousWindow.start).toBe('2026-05-30');
      expect(result.previousWindow.end).toBe('2026-06-09');
    });

    it('rejects custom without both dates', async () => {
      await expect(
        service.getReport({ period: 'custom', start: '2026-06-10' }),
      ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
    });

    it('aggregates throughput and per-model sold-vs-built', async () => {
      // 7 trailers entered production, current period
      mockPrisma.productionStep.count.mockResolvedValue(7);
      // 3 trailers exited (passed FINAL_QC) — 2 XP, 1 Yeti
      mockPrisma.qcInspection.findMany.mockResolvedValue([
        {
          trailer: {
            trailerModelId: 1,
            trailerModel: {
              id: 1,
              code: 'XP_14ET',
              displayName: '14K XP',
              series: 'xp',
            },
          },
        },
        {
          trailer: {
            trailerModelId: 1,
            trailerModel: {
              id: 1,
              code: 'XP_14ET',
              displayName: '14K XP',
              series: 'xp',
            },
          },
        },
        {
          trailer: {
            trailerModelId: 2,
            trailerModel: {
              id: 2,
              code: 'YETI_14K',
              displayName: '14K Yeti',
              series: 'yeti',
            },
          },
        },
      ]);
      mockPrisma.delivery.count.mockResolvedValue(4);
      // 5 customer orders this week, all XP
      mockPrisma.trailer.findMany.mockResolvedValueOnce([
        {
          trailerModelId: 1,
          trailerModel: {
            id: 1,
            code: 'XP_14ET',
            displayName: '14K XP',
            series: 'xp',
          },
        },
        {
          trailerModelId: 1,
          trailerModel: {
            id: 1,
            code: 'XP_14ET',
            displayName: '14K XP',
            series: 'xp',
          },
        },
        {
          trailerModelId: 1,
          trailerModel: {
            id: 1,
            code: 'XP_14ET',
            displayName: '14K XP',
            series: 'xp',
          },
        },
        {
          trailerModelId: 1,
          trailerModel: {
            id: 1,
            code: 'XP_14ET',
            displayName: '14K XP',
            series: 'xp',
          },
        },
        {
          trailerModelId: 1,
          trailerModel: {
            id: 1,
            code: 'XP_14ET',
            displayName: '14K XP',
            series: 'xp',
          },
        },
      ]);
      // 2 open-stock sold this week, 1 XP + 1 Yeti
      mockPrisma.trailer.findMany.mockResolvedValueOnce([
        {
          trailerModelId: 1,
          trailerModel: {
            id: 1,
            code: 'XP_14ET',
            displayName: '14K XP',
            series: 'xp',
          },
        },
        {
          trailerModelId: 2,
          trailerModel: {
            id: 2,
            code: 'YETI_14K',
            displayName: '14K Yeti',
            series: 'yeti',
          },
        },
      ]);

      const result = await service.getReport({
        period: 'weekly',
        start: '2026-06-19',
      });

      expect(result.current.throughput).toEqual({
        enteredProduction: 7,
        exitedProduction: 3,
        delivered: 4,
        exitedBySeries: { xp: 2, yeti: 1 },
      });
      expect(result.current.sales).toEqual({
        customerOrders: 5,
        openStockSold: 2,
        totalSales: 7,
      });
      // Per-model: XP gets 5 cust + 1 stock + 2 built = (sold 6, built 2),
      //            Yeti gets 1 stock + 1 built = (sold 1, built 1)
      expect(result.current.soldVsBuilt.totalSold).toBe(7);
      expect(result.current.soldVsBuilt.totalBuilt).toBe(3);
      const xp = result.current.soldVsBuilt.perModel.find(
        (m) => m.modelCode === 'XP_14ET',
      );
      const yeti = result.current.soldVsBuilt.perModel.find(
        (m) => m.modelCode === 'YETI_14K',
      );
      expect(xp).toEqual(
        expect.objectContaining({ sold: 6, built: 2, series: 'xp' }),
      );
      expect(yeti).toEqual(
        expect.objectContaining({ sold: 1, built: 1, series: 'yeti' }),
      );
    });

    it('rolls active QC steps back into their predecessor prod dept on the live board', async () => {
      mockPrisma.department.findMany.mockResolvedValue([
        { id: 1, code: 'XP_JIG', displayName: 'XP Jig Weld' },
        { id: 2, code: 'XP_FIN', displayName: 'XP Finish Weld' },
      ]);
      // Trailer 100 has an active QC_1 step (stepOrder=2); QC_1 inspects
      // step 1 = XP_JIG → should bucket the trailer under XP_JIG, not under
      // any QC tile (there are none) and not double-count.
      mockPrisma.productionStep.findMany
        .mockResolvedValueOnce([
          {
            trailerId: 100n,
            stepOrder: 2,
            departmentId: 99, // a QC dept id (not on the tile board)
            department: { id: 99, code: 'QC_1', isQcStep: true },
          },
          {
            trailerId: 200n,
            stepOrder: 3,
            departmentId: 2, // XP_FIN, a real prod dept
            department: { id: 2, code: 'XP_FIN', isQcStep: false },
          },
        ])
        // Predecessor query: stepOrder=1 for trailer 100 is XP_JIG (id=1)
        .mockResolvedValueOnce([
          { trailerId: 100n, stepOrder: 1, departmentId: 1 },
        ]);

      const result = await service.getReport({
        period: 'weekly',
        start: '2026-06-19',
      });

      const xpJig = result.live.departments.find((d) => d.code === 'XP_JIG');
      const xpFin = result.live.departments.find((d) => d.code === 'XP_FIN');
      expect(xpJig?.waiting).toBe(1); // QC_1 rolled back here
      expect(xpFin?.waiting).toBe(1); // direct active prod step
    });

    it('buckets sold-but-not-started trailers onto their first-step dept', async () => {
      mockPrisma.department.findMany.mockResolvedValue([
        { id: 1, code: 'XP_JIG', displayName: 'XP Jig Weld' },
        { id: 3, code: 'DO_JIG', displayName: 'Deck Over Jig Weld' },
      ]);
      // No active steps — board is purely showing sold-not-started.
      mockPrisma.productionStep.findMany.mockResolvedValueOnce([]);
      mockPrisma.trailer.findMany.mockImplementation((args: any) => {
        // The first .findMany on trailer with productionSteps relation in the
        // where clause is the sold-not-started query.
        if (args?.where?.productionSteps?.none) {
          return Promise.resolve([
            { id: 1n, productionSteps: [{ departmentId: 1 }] },
            { id: 2n, productionSteps: [{ departmentId: 1 }] },
            { id: 3n, productionSteps: [{ departmentId: 3 }] },
          ]);
        }
        return Promise.resolve([]);
      });

      const result = await service.getReport({
        period: 'weekly',
        start: '2026-06-19',
      });

      const xpJig = result.live.departments.find((d) => d.code === 'XP_JIG');
      const doJig = result.live.departments.find((d) => d.code === 'DO_JIG');
      expect(xpJig?.soldNotStarted).toBe(2);
      expect(doJig?.soldNotStarted).toBe(1);
    });
  });
});
