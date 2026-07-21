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

    // Open-stock reporting: how many stock orders were PUT IN, and of the stock
    // that sold, how much came off the line vs out of the yard.
    it('counts open-stock orders placed and splits stock sales by production vs inventory', async () => {
      const model = { id: 1, code: 'XP_14ET', displayName: 'XP 14ET', series: 'xp' };
      const soldAt = new Date('2026-06-16T12:00:00Z');

      // stockOrdersPlaced is the only trailer.count keyed on isStockBuild+createdAt.
      mockPrisma.trailer.count.mockImplementation((args: never) => {
        const w = (args as { where?: Record<string, unknown> })?.where ?? {};
        return Promise.resolve(w.isStockBuild === true && w.createdAt ? 5 : 0);
      });

      mockPrisma.trailer.findMany.mockImplementation((args: never) => {
        const w = (args as { where?: Record<string, unknown> })?.where ?? {};
        if (w.isStockBuild !== true || w.saleStatus !== 'sold') {
          return Promise.resolve([]);
        }
        return Promise.resolve([
          // A step never finished → it was still being built when it sold.
          {
            trailerModelId: 1,
            soldAt,
            trailerModel: model,
            productionSteps: [{ completedAt: null }],
          },
          // A step finished AFTER the sale → still on the line at sale time.
          {
            trailerModelId: 1,
            soldAt,
            trailerModel: model,
            productionSteps: [
              { completedAt: new Date('2026-06-15T00:00:00Z') },
              { completedAt: new Date('2026-06-17T00:00:00Z') },
            ],
          },
          // Every step done before the sale → sold out of finished stock.
          {
            trailerModelId: 1,
            soldAt,
            trailerModel: model,
            productionSteps: [{ completedAt: new Date('2026-06-10T00:00:00Z') }],
          },
          // Never ran the line at all (inventory-only series) → inventory.
          { trailerModelId: 1, soldAt, trailerModel: model, productionSteps: [] },
        ]);
      });

      const { current } = await service.getReport({
        period: 'weekly',
        start: '2026-06-19',
      });

      expect(current.sales.stockOrdersPlaced).toBe(5);
      expect(current.sales.openStockSold).toBe(4);
      expect(current.sales.openStockSoldFromProduction).toBe(2);
      expect(current.sales.openStockSoldFromInventory).toBe(2);
      // The split must always reconcile with the total.
      expect(
        current.sales.openStockSoldFromProduction +
          current.sales.openStockSoldFromInventory,
      ).toBe(current.sales.openStockSold);
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
        // No stock orders were placed in this window (trailer.count stubbed 0),
        // and neither sold stock row carries step data, so both read as sold
        // out of finished inventory.
        stockOrdersPlaced: 0,
        openStockSoldFromProduction: 0,
        openStockSoldFromInventory: 2,
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
            // trailer.saleStatus is selected alongside active steps now —
            // the buildLiveSnapshot uses it to colour the "sold here"
            // count. Available here so we only assert on `waiting`.
            trailer: { saleStatus: 'available' },
          },
          {
            trailerId: 200n,
            stepOrder: 3,
            departmentId: 2, // XP_FIN, a real prod dept
            department: { id: 2, code: 'XP_FIN', isQcStep: false },
            trailer: { saleStatus: 'available' },
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

    it('counts sold trailers currently active at each dept (with QC roll-back)', async () => {
      mockPrisma.department.findMany.mockResolvedValue([
        { id: 1, code: 'XP_JIG', displayName: 'XP Jig Weld' },
        { id: 2, code: 'XP_FIN', displayName: 'XP Finish Weld' },
        { id: 3, code: 'DO_JIG', displayName: 'Deck Over Jig Weld' },
      ]);
      // Active steps — three sold trailers, one unsold:
      //   trailer 100 sold, active at XP_JIG directly
      //   trailer 101 sold, active at QC_1 (rolled back to XP_JIG)
      //   trailer 102 sold, active at XP_FIN directly
      //   trailer 103 unsold, active at DO_JIG (does not bump sold count)
      mockPrisma.productionStep.findMany
        .mockResolvedValueOnce([
          {
            trailerId: 100n,
            stepOrder: 1,
            departmentId: 1,
            department: { id: 1, code: 'XP_JIG', isQcStep: false },
            trailer: { saleStatus: 'sold' },
          },
          {
            trailerId: 101n,
            stepOrder: 2,
            departmentId: 99, // QC_1
            department: { id: 99, code: 'QC_1', isQcStep: true },
            trailer: { saleStatus: 'sold' },
          },
          {
            trailerId: 102n,
            stepOrder: 3,
            departmentId: 2,
            department: { id: 2, code: 'XP_FIN', isQcStep: false },
            trailer: { saleStatus: 'sold' },
          },
          {
            trailerId: 103n,
            stepOrder: 1,
            departmentId: 3,
            department: { id: 3, code: 'DO_JIG', isQcStep: false },
            trailer: { saleStatus: 'available' },
          },
        ])
        // Predecessor lookup for QC active steps — trailer 101's step 1 is XP_JIG.
        .mockResolvedValueOnce([
          { trailerId: 101n, stepOrder: 1, departmentId: 1 },
        ]);

      const result = await service.getReport({
        period: 'weekly',
        start: '2026-06-19',
      });

      const xpJig = result.live.departments.find((d) => d.code === 'XP_JIG');
      const xpFin = result.live.departments.find((d) => d.code === 'XP_FIN');
      const doJig = result.live.departments.find((d) => d.code === 'DO_JIG');
      expect(xpJig?.soldHere).toBe(2); // 100 directly + 101 rolled back from QC_1
      expect(xpFin?.soldHere).toBe(1); // 102 directly
      expect(doJig?.soldHere).toBe(0); // 103 is unsold
    });
  });
});
