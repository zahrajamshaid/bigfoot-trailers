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
    productionStep: { count: jest.fn() },
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
      // Department query specifically excludes QC steps so the grid matches
      // the payroll matrix's convention.
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
  // getWeeklyReport
  // ==========================================================================
  describe('getWeeklyReport', () => {
    beforeEach(() => {
      // Default everything to empty so individual tests only set what they care about.
      mockPrisma.productionStep.count.mockResolvedValue(0);
      mockPrisma.qcInspection.findMany.mockResolvedValue([]);
      mockPrisma.delivery.count.mockResolvedValue(0);
      mockPrisma.trailer.count.mockResolvedValue(0);
      mockPrisma.trailer.findMany.mockResolvedValue([]);
      mockPrisma.trailer.groupBy.mockResolvedValue([]);
      mockPrisma.location.findMany.mockResolvedValue([]);
    });

    it('rejects a non-YYYY-MM-DD weekStart', async () => {
      await expect(service.getWeeklyReport('not-a-date')).rejects.toMatchObject({
        errorCode: ErrorCode.BAD_REQUEST,
      });
    });

    it('returns the Sunday-aligned week window', async () => {
      // 2026-06-19 is a Friday. Sunday of that week is 2026-06-14.
      const result = await service.getWeeklyReport('2026-06-19');
      expect(result.weekStart).toBe('2026-06-14');
      expect(result.weekEnd).toBe('2026-06-21');
    });

    it('aggregates throughput counts and groups exited by series', async () => {
      mockPrisma.productionStep.count.mockResolvedValue(7); // entered
      mockPrisma.qcInspection.findMany.mockResolvedValue([
        { trailer: { trailerModel: { series: 'xp' } } },
        { trailer: { trailerModel: { series: 'xp' } } },
        { trailer: { trailerModel: { series: 'yeti' } } },
      ]);
      mockPrisma.delivery.count.mockResolvedValue(4);
      mockPrisma.trailer.count
        .mockResolvedValueOnce(42) // inProduction
        .mockResolvedValueOnce(12); // readyForDelivery

      const result = await service.getWeeklyReport('2026-06-19');

      expect(result.throughput).toEqual({
        enteredProduction: 7,
        exitedProduction: 3,
        exitedBySeries: { xp: 2, yeti: 1 },
        delivered: 4,
      });
      expect(result.snapshot.inProduction).toBe(42);
      expect(result.snapshot.readyForDelivery).toBe(12);
    });

    it('joins yard inventory groupby with location codes', async () => {
      mockPrisma.trailer.groupBy.mockResolvedValue([
        { currentLocationId: 4, _count: { _all: 12 } },
        { currentLocationId: 6, _count: { _all: 38 } },
      ]);
      mockPrisma.location.findMany.mockResolvedValue([
        { id: 4, code: 'JACKSONVILLE', name: 'Jax', isFactory: false },
        { id: 6, code: 'TAPPAHANNOCK', name: 'Tap', isFactory: false },
      ]);

      const result = await service.getWeeklyReport('2026-06-19');

      expect(result.snapshot.inventoryByYard).toEqual([
        {
          locationId: 4,
          code: 'JACKSONVILLE',
          name: 'Jax',
          isFactory: false,
          count: 12,
        },
        {
          locationId: 6,
          code: 'TAPPAHANNOCK',
          name: 'Tap',
          isFactory: false,
          count: 38,
        },
      ]);
    });

    it('computes WIP cumulative vs projected from the stage cost matrix', async () => {
      mockPrisma.trailer.findMany.mockResolvedValue([
        {
          id: 233n,
          soNumber: '6715',
          trailerModelId: 1,
          trailerModel: { code: 'XP_14ET', displayName: '14K XP', series: 'xp' },
          productionSteps: [
            { departmentId: 10, status: 'complete' },
            { departmentId: 20, status: 'complete' },
            { departmentId: 30, status: 'active' },
            { departmentId: 40, status: 'waiting' },
          ],
        },
      ]);
      mockPrisma.trailerModelStageCost.findMany.mockResolvedValue([
        {
          trailerModelId: 1,
          departmentId: 10,
          costDollars: new Prisma.Decimal('100'),
        },
        {
          trailerModelId: 1,
          departmentId: 20,
          costDollars: new Prisma.Decimal('250'),
        },
        {
          trailerModelId: 1,
          departmentId: 30,
          costDollars: new Prisma.Decimal('150'),
        },
        // No cell for dept 40 — should default to 0 so projected isn't NaN.
      ]);

      const result = await service.getWeeklyReport('2026-06-19');

      expect(result.wipCost.totalCumulativeDollars).toBe(350); // 100 + 250
      expect(result.wipCost.totalProjectedDollars).toBe(500); // 100 + 250 + 150 + 0
      expect(result.wipCost.perTrailer).toEqual([
        {
          trailerId: '233',
          soNumber: '6715',
          modelCode: 'XP_14ET',
          modelName: '14K XP',
          cumulativeDollars: 350,
          projectedDollars: 500,
        },
      ]);
    });

    it('returns zero WIP when no trailers are in production', async () => {
      // Default mocks: no trailers, no costs.
      const result = await service.getWeeklyReport('2026-06-19');
      expect(result.wipCost.totalCumulativeDollars).toBe(0);
      expect(result.wipCost.totalProjectedDollars).toBe(0);
      expect(result.wipCost.perTrailer).toEqual([]);
    });
  });
});
