import { Test, TestingModule } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
import { PayrollService } from './payroll.service';
import { PrismaService } from '../../prisma/prisma.service';
import { Prisma } from '@prisma/client';

// ---------------------------------------------------------------------------
// Mock Prisma
// ---------------------------------------------------------------------------

const mockPrisma: Record<string, any> = {
  pointValue: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
    count: jest.fn(),
  },
  department: {
    findUnique: jest.fn(),
  },
  trailerModel: {
    findUnique: jest.fn(),
  },
  deptDollarRate: {
    findMany: jest.fn(),
    create: jest.fn(),
    count: jest.fn(),
  },
  payrollRecord: {
    findMany: jest.fn(),
    findFirst: jest.fn(),
    upsert: jest.fn(),
    count: jest.fn(),
  },
  productionStep: {
    findMany: jest.fn(),
  },
  productionStepPayout: {
    findMany: jest.fn(),
  },
  payrollAdjustment: {
    findMany: jest.fn().mockResolvedValue([]),
    findFirst: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  },
  trailerModelStageCost: {
    findMany: jest.fn(),
  },
  stageCrewMember: {
    findMany: jest.fn(),
    deleteMany: jest.fn(),
    createMany: jest.fn(),
  },
  user: {
    findUnique: jest.fn(),
    count: jest.fn(),
  },
  $transaction: jest.fn(),
};

// Build a payout row in the shape findWeeklyReport / lockWeek select. `dollars`
// is what this worker earned on this step (base, or base+adjustment collapsed).
function payoutRow(
  userId: number,
  deptId: number,
  deptCode: string,
  deptName: string,
  stepId: number,
  dollars: number,
  isRework = false,
) {
  return {
    dollars: new Prisma.Decimal(dollars),
    userId: BigInt(userId),
    user: { id: BigInt(userId), fullName: `User ${userId}`, email: `u${userId}@t.com` },
    productionStep: {
      id: BigInt(stepId),
      isRework,
      departmentId: deptId,
      department: { id: deptId, code: deptCode, displayName: deptName },
      trailer: {
        id: BigInt(stepId),
        soNumber: `SO-${stepId}`,
        sizeFt: '18',
        trailerModel: { id: 1, displayName: 'XP 10K', code: 'XP_10K' },
      },
    },
  };
}

// Wire up $transaction: callback form passes mockPrisma as the tx argument;
// array form (batch) resolves each operation like a real interactive transaction.
mockPrisma.$transaction.mockImplementation((arg: unknown) =>
  Array.isArray(arg) ? Promise.all(arg) : (arg as (tx: any) => Promise<any>)(mockPrisma),
);

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const mockProductionDept = { id: 1, isQcStep: false, displayName: 'XP Jig Weld' };
const mockQcDept = { id: 15, isQcStep: true, displayName: 'Quality Control 1' };
const mockTrailerModel = { id: 1 };

describe('PayrollService', () => {
  let service: PayrollService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [PayrollService, { provide: PrismaService, useValue: mockPrisma }],
    }).compile();

    service = module.get<PayrollService>(PayrollService);
    jest.clearAllMocks();
    // Default: no manual adjustments (individual tests override).
    mockPrisma.payrollAdjustment.findMany.mockResolvedValue([]);
  });

  // =========================================================================
  // findPointValues
  // =========================================================================
  describe('findPointValues', () => {
    it('should return point values with no filters', async () => {
      mockPrisma.pointValue.findMany.mockResolvedValue([]);
      mockPrisma.pointValue.count.mockResolvedValue(0);
      const result = await service.findPointValues({});
      expect(result.items).toEqual([]);
      expect(result.total).toBe(0);
      expect(mockPrisma.pointValue.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: {} }),
      );
    });

    it('should filter by trailerModelId and departmentId', async () => {
      mockPrisma.pointValue.findMany.mockResolvedValue([]);
      await service.findPointValues({ trailerModelId: 1, departmentId: 2 });
      expect(mockPrisma.pointValue.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { trailerModelId: 1, departmentId: 2 } }),
      );
    });
  });

  // =========================================================================
  // createPointValue
  // =========================================================================
  describe('createPointValue', () => {
    const dto = {
      trailerModelId: 1,
      departmentId: 1,
      points: 3.5,
      effectiveFrom: '2026-01-01',
    };

    it('should create a point value for a production department', async () => {
      mockPrisma.department.findUnique.mockResolvedValue(mockProductionDept);
      mockPrisma.trailerModel.findUnique.mockResolvedValue(mockTrailerModel);
      mockPrisma.pointValue.create.mockResolvedValue({ id: 1, ...dto });

      const result = await service.createPointValue(dto);
      expect(result).toEqual({ id: 1, ...dto });
      expect(mockPrisma.pointValue.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            trailerModelId: 1,
            departmentId: 1,
            points: expect.any(Prisma.Decimal),
          }),
        }),
      );
    });

    it('should reject QC departments — QC departments do not award points', async () => {
      mockPrisma.department.findUnique.mockResolvedValue(mockQcDept);

      await expect(service.createPointValue(dto)).rejects.toMatchObject({
        errorCode: ErrorCode.BAD_REQUEST,
      });
    });

    it('should reject if department not found', async () => {
      mockPrisma.department.findUnique.mockResolvedValue(null);

      await expect(service.createPointValue(dto)).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });

    it('should reject if trailer model not found', async () => {
      mockPrisma.department.findUnique.mockResolvedValue(mockProductionDept);
      mockPrisma.trailerModel.findUnique.mockResolvedValue(null);

      await expect(service.createPointValue(dto)).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });

  // =========================================================================
  // updatePointValue
  // =========================================================================
  describe('updatePointValue', () => {
    it('should update a point value', async () => {
      mockPrisma.pointValue.findUnique.mockResolvedValue({ id: 1 });
      mockPrisma.pointValue.update.mockResolvedValue({ id: 1, points: 4.0 });

      const result = await service.updatePointValue(1, { points: 4.0 });
      expect(result.points).toBe(4.0);
    });

    it('should throw AppError if not found', async () => {
      mockPrisma.pointValue.findUnique.mockResolvedValue(null);

      await expect(service.updatePointValue(999, { points: 4.0 })).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });

    it('should update effectiveTo date', async () => {
      mockPrisma.pointValue.findUnique.mockResolvedValue({ id: 1 });
      mockPrisma.pointValue.update.mockResolvedValue({
        id: 1,
        effectiveTo: '2026-06-30',
      });

      await service.updatePointValue(1, { effectiveTo: '2026-06-30' });
      expect(mockPrisma.pointValue.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ effectiveTo: expect.any(Date) }),
        }),
      );
    });
  });

  // =========================================================================
  // findDollarRates
  // =========================================================================
  describe('findDollarRates', () => {
    it('should return rates with no filters', async () => {
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([]);
      mockPrisma.deptDollarRate.count.mockResolvedValue(0);
      const result = await service.findDollarRates({});
      expect(result.items).toEqual([]);
      expect(result.total).toBe(0);
    });

    it('should filter by departmentId', async () => {
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([]);
      await service.findDollarRates({ departmentId: 5 });
      expect(mockPrisma.deptDollarRate.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { departmentId: 5 } }),
      );
    });
  });

  // =========================================================================
  // createDollarRate
  // =========================================================================
  describe('createDollarRate', () => {
    const dto = { departmentId: 1, dollarPerPoint: 12.5, effectiveFrom: '2026-01-01' };

    it('should create a dollar rate', async () => {
      mockPrisma.department.findUnique.mockResolvedValue({
        id: 1,
        displayName: 'XP Jig Weld',
      });
      mockPrisma.deptDollarRate.create.mockResolvedValue({ id: 1, ...dto });

      const result = await service.createDollarRate(dto);
      expect(result).toEqual({ id: 1, ...dto });
    });

    it('should reject if department not found', async () => {
      mockPrisma.department.findUnique.mockResolvedValue(null);

      await expect(service.createDollarRate(dto)).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });

  // =========================================================================
  // findPayrollRecords
  // =========================================================================
  describe('findPayrollRecords', () => {
    it('should return records with no filters', async () => {
      mockPrisma.payrollRecord.findMany.mockResolvedValue([]);
      mockPrisma.payrollRecord.count.mockResolvedValue(0);
      const result = await service.findPayrollRecords({});
      expect(result.items).toEqual([]);
      expect(result.total).toBe(0);
    });

    it('should filter by userId, departmentId, weekStartDate', async () => {
      mockPrisma.payrollRecord.findMany.mockResolvedValue([]);
      await service.findPayrollRecords({
        userId: 10,
        departmentId: 1,
        weekStartDate: '2026-03-22',
      });
      expect(mockPrisma.payrollRecord.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            userId: BigInt(10),
            departmentId: 1,
            weekStartDate: expect.any(Date),
          },
        }),
      );
    });
  });

  // =========================================================================
  // findWeeklyReport
  // =========================================================================
  describe('findWeeklyReport', () => {
    it('should reject if week_start is not a Sunday', async () => {
      // 2026-03-25 is a Wednesday
      await expect(service.findWeeklyReport('2026-03-25')).rejects.toMatchObject({
        errorCode: ErrorCode.INVALID_WEEK_START,
      });
      await expect(service.findWeeklyReport('2026-03-25')).rejects.toThrow(
        'not a Sunday',
      );
    });

    it('should return weekly report for a valid Sunday', async () => {
      // 2026-03-22 is a Sunday. One paid step for worker 10 in XP_JIG.
      mockPrisma.productionStepPayout.findMany.mockResolvedValue([
        payoutRow(10, 1, 'XP_JIG', 'XP Jig Weld', 1, 3.5),
      ]);
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([
        {
          departmentId: 1,
          dollarPerPoint: new Prisma.Decimal(12.5),
          effectiveFrom: new Date('2026-01-01'),
        },
      ]);
      mockPrisma.payrollRecord.findFirst.mockResolvedValue(null);

      const result = await service.findWeeklyReport('2026-03-22');

      expect(result.weekStartDate).toBe('2026-03-22');
      expect(result.isLocked).toBe(false);
      expect(result.workers).toHaveLength(1);
      expect(result.workers[0].totalPoints).toBe(3.5);
      expect(result.workers[0].totalGrossPay).toBe(43.75); // 3.5 * 12.5
      expect(result.workers[0].totalStepsCompleted).toBe(1);
    });

    it('folds a manual adjustment into the worker gross and lists it', async () => {
      mockPrisma.productionStepPayout.findMany.mockResolvedValue([
        payoutRow(10, 1, 'XP_JIG', 'XP Jig Weld', 1, 100),
      ]);
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([
        {
          departmentId: 1,
          dollarPerPoint: new Prisma.Decimal(1),
          effectiveFrom: new Date('2026-01-01'),
        },
      ]);
      mockPrisma.payrollRecord.findFirst.mockResolvedValue(null);
      mockPrisma.payrollAdjustment.findMany.mockResolvedValue([
        {
          id: BigInt(7),
          userId: BigInt(10),
          dollars: new Prisma.Decimal(50),
          note: 'bonus',
          effectiveDate: new Date('2026-03-23'),
          user: { fullName: 'W10', email: null },
        },
      ]);

      const result = await service.findWeeklyReport('2026-03-22');
      const w = result.workers.find((x: any) => x.userId.toString() === '10') as any;
      expect(w.adjustmentsTotal).toBe(50);
      expect(w.adjustments).toHaveLength(1);
      expect(w.totalGrossPay).toBe(150); // 100 base + 50 adjustment
    });

    it('shows a worker who has only a manual adjustment this week', async () => {
      mockPrisma.productionStepPayout.findMany.mockResolvedValue([]);
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([]);
      mockPrisma.payrollRecord.findFirst.mockResolvedValue(null);
      mockPrisma.payrollAdjustment.findMany.mockResolvedValue([
        {
          id: BigInt(8),
          userId: BigInt(20),
          dollars: new Prisma.Decimal(-30),
          note: 'deduction',
          effectiveDate: new Date('2026-03-24'),
          user: { fullName: 'W20', email: null },
        },
      ]);

      const result = await service.findWeeklyReport('2026-03-22');
      expect(result.workers).toHaveLength(1);
      expect(result.workers[0]).toMatchObject({
        fullName: 'W20',
        totalGrossPay: -30,
        totalStepsCompleted: 0,
      });
      expect((result.workers[0] as any).adjustments).toHaveLength(1);
    });

    it('collapses a base + adjustment payout on the same step into one line', async () => {
      // e.g. paint base $70 + >30ft/non-gray adjustment $20 → $90 on one step.
      mockPrisma.productionStepPayout.findMany.mockResolvedValue([
        payoutRow(10, 1, 'PAINT_B', 'Paint Booth B', 5, 70),
        payoutRow(10, 1, 'PAINT_B', 'Paint Booth B', 5, 20),
      ]);
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([
        {
          departmentId: 1,
          dollarPerPoint: new Prisma.Decimal(1),
          effectiveFrom: new Date('2026-01-01'),
        },
      ]);
      mockPrisma.payrollRecord.findFirst.mockResolvedValue(null);

      const result = await service.findWeeklyReport('2026-03-22');

      expect(result.workers[0].totalPoints).toBe(90);
      expect(result.workers[0].totalGrossPay).toBe(90);
      expect(result.workers[0].totalStepsCompleted).toBe(1);
    });

    it('should show locked status when week is locked', async () => {
      mockPrisma.productionStepPayout.findMany.mockResolvedValue([]);
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([]);
      mockPrisma.payrollRecord.findFirst.mockResolvedValue({
        isLocked: true,
        lockedAt: new Date('2026-03-29T10:00:00Z'),
        lockedByUser: { id: BigInt(1), fullName: 'Boss' },
      });

      const result = await service.findWeeklyReport('2026-03-22');
      expect(result.isLocked).toBe(true);
    });

    it('should aggregate multiple workers across departments', async () => {
      mockPrisma.productionStepPayout.findMany.mockResolvedValue([
        {
          ...payoutRow(10, 1, 'XP_JIG', 'XP Jig Weld', 1, 3.5),
          user: { id: BigInt(10), fullName: 'Alice', email: 'alice@test.com' },
        },
        {
          ...payoutRow(20, 9, 'PAINT_PREP', 'Paint Preparation', 2, 2.0),
          user: { id: BigInt(20), fullName: 'Bob', email: 'bob@test.com' },
        },
      ]);
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([
        {
          departmentId: 1,
          dollarPerPoint: new Prisma.Decimal(12.5),
          effectiveFrom: new Date('2026-01-01'),
        },
        {
          departmentId: 9,
          dollarPerPoint: new Prisma.Decimal(10.0),
          effectiveFrom: new Date('2026-01-01'),
        },
      ]);
      mockPrisma.payrollRecord.findFirst.mockResolvedValue(null);

      const result = await service.findWeeklyReport('2026-03-22');

      expect(result.workers).toHaveLength(2);
      // Sorted by points desc: Alice (3.5) first, Bob (2.0) second
      expect(result.workers[0].fullName).toBe('Alice');
      expect(result.workers[0].totalGrossPay).toBe(43.75);
      expect(result.workers[1].fullName).toBe('Bob');
      expect(result.workers[1].totalGrossPay).toBe(20.0);
    });
  });

  // =========================================================================
  // lockWeek
  // =========================================================================
  describe('lockWeek', () => {
    it('should reject non-Sunday week_start', async () => {
      await expect(service.lockWeek('2026-03-25', BigInt(1))).rejects.toMatchObject({
        errorCode: ErrorCode.INVALID_WEEK_START,
      });
    });

    it('should reject if week already locked', async () => {
      mockPrisma.payrollRecord.findFirst.mockResolvedValue({ id: BigInt(1) });

      await expect(service.lockWeek('2026-03-22', BigInt(1))).rejects.toMatchObject({
        errorCode: ErrorCode.PAYROLL_WEEK_LOCKED,
      });
    });

    it('should lock a week and generate payroll records', async () => {
      mockPrisma.payrollRecord.findFirst.mockResolvedValue(null); // Not locked yet

      // Transaction mocks — $transaction passes mockPrisma as tx. Two paid
      // steps for worker 10 in dept 1 (distinct step ids → 2 trailers).
      mockPrisma.productionStepPayout.findMany.mockResolvedValue([
        payoutRow(10, 1, 'XP_JIG', 'XP Jig Weld', 1, 3.5),
        payoutRow(10, 1, 'XP_JIG', 'XP Jig Weld', 2, 3.5),
      ]);
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([
        {
          departmentId: 1,
          dollarPerPoint: new Prisma.Decimal(12.5),
          effectiveFrom: new Date('2026-01-01'),
        },
      ]);
      mockPrisma.payrollRecord.upsert.mockResolvedValue({
        id: BigInt(1),
        userId: BigInt(10),
        departmentId: 1,
        totalPoints: new Prisma.Decimal(7),
        trailersCompleted: 2,
        grossPay: new Prisma.Decimal(87.5),
        isLocked: true,
        lockedAt: new Date(),
      });

      const result = await service.lockWeek('2026-03-22', BigInt(1));

      expect(result.isLocked).toBe(true);
      expect(result.recordsLocked).toBe(1);
      expect(mockPrisma.payrollRecord.upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          create: expect.objectContaining({
            isLocked: true,
            totalPoints: expect.any(Prisma.Decimal),
          }),
        }),
      );
    });

    it('locks a rework-only week with no payouts → no payroll records', async () => {
      // Rework is uncompensated, so it produces no payout rows. Nothing to pay
      // means no payroll records are written.
      mockPrisma.payrollRecord.findFirst.mockResolvedValue(null);
      mockPrisma.productionStepPayout.findMany.mockResolvedValue([]);
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([]);

      const result = await service.lockWeek('2026-03-22', BigInt(1));

      expect(mockPrisma.payrollRecord.upsert).not.toHaveBeenCalled();
      expect(result.recordsLocked).toBe(0);
    });
  });

  // =========================================================================
  // getWorkerSummary
  // =========================================================================
  describe('getWorkerSummary', () => {
    it('should throw AppError if user not found', async () => {
      mockPrisma.user.findUnique.mockResolvedValue(null);

      await expect(service.getWorkerSummary(BigInt(999))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });

    it('should return current week summary with points and earnings', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: BigInt(10),
        fullName: 'John Doe',
        primaryDepartmentId: 1,
      });
      mockPrisma.productionStep.findMany.mockResolvedValue([
        {
          departmentId: 1,
          pointsAwarded: new Prisma.Decimal(3.5),
          isRework: false,
          department: { id: 1, code: 'XP_JIG', displayName: 'XP Jig Weld' },
        },
        {
          departmentId: 1,
          pointsAwarded: new Prisma.Decimal(0),
          isRework: true,
          department: { id: 1, code: 'XP_JIG', displayName: 'XP Jig Weld' },
        },
      ]);
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([
        {
          departmentId: 1,
          dollarPerPoint: new Prisma.Decimal(12.5),
          effectiveFrom: new Date('2026-01-01'),
        },
      ]);

      const result = await service.getWorkerSummary(BigInt(10));

      expect(result.userId).toBe(BigInt(10));
      expect(result.totalPoints).toBe(3.5);
      expect(result.projectedEarnings).toBe(43.75);
      expect(result.stepsCompleted).toBe(2);
      expect(result.reworkCount).toBe(1);
      expect(result.departments).toHaveLength(1);
      expect(result.departments[0].reworks).toBe(1);
    });

    it('should return zero earnings with no completed steps', async () => {
      mockPrisma.user.findUnique.mockResolvedValue({
        id: BigInt(10),
        fullName: 'John Doe',
        primaryDepartmentId: 1,
      });
      mockPrisma.productionStep.findMany.mockResolvedValue([]);
      mockPrisma.deptDollarRate.findMany.mockResolvedValue([]);

      const result = await service.getWorkerSummary(BigInt(10));

      expect(result.totalPoints).toBe(0);
      expect(result.projectedEarnings).toBe(0);
      expect(result.stepsCompleted).toBe(0);
      expect(result.reworkCount).toBe(0);
    });
  });
});
