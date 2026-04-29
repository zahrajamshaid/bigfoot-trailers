import { Test, TestingModule } from '@nestjs/testing';
import { ReportGeneratorProcessor } from './report-generator.processor';
import { PrismaService } from '../../prisma/prisma.service';

describe('ReportGeneratorProcessor', () => {
  let processor: ReportGeneratorProcessor;

  const mockPrisma = {
    payrollRecord: {
      findFirst: jest.fn(),
      upsert: jest.fn(),
    },
    productionStep: {
      findMany: jest.fn(),
    },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ReportGeneratorProcessor,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    processor = module.get<ReportGeneratorProcessor>(ReportGeneratorProcessor);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(processor).toBeDefined();
  });

  describe('generateWeeklyRecords', () => {
    it('should skip if week is already locked', async () => {
      mockPrisma.payrollRecord.findFirst.mockResolvedValue({ id: 1n });

      const count = await processor.generateWeeklyRecords();

      expect(count).toBe(0);
      expect(mockPrisma.productionStep.findMany).not.toHaveBeenCalled();
    });

    it('should upsert payroll records for completed steps', async () => {
      mockPrisma.payrollRecord.findFirst.mockResolvedValue(null);
      mockPrisma.productionStep.findMany.mockResolvedValue([
        {
          completedByUserId: 10n,
          departmentId: 1,
          pointsAwarded: { toNumber: () => 5 },
          trailerId: 100n,
        },
        {
          completedByUserId: 10n,
          departmentId: 1,
          pointsAwarded: { toNumber: () => 3 },
          trailerId: 101n,
        },
        {
          completedByUserId: 20n,
          departmentId: 2,
          pointsAwarded: { toNumber: () => 7 },
          trailerId: 100n,
        },
      ]);
      mockPrisma.payrollRecord.upsert.mockResolvedValue({});

      const count = await processor.generateWeeklyRecords();

      // 2 unique (userId, departmentId) combinations
      expect(count).toBe(2);
      expect(mockPrisma.payrollRecord.upsert).toHaveBeenCalledTimes(2);
    });

    it('should return 0 when no steps are completed', async () => {
      mockPrisma.payrollRecord.findFirst.mockResolvedValue(null);
      mockPrisma.productionStep.findMany.mockResolvedValue([]);

      const count = await processor.generateWeeklyRecords();
      expect(count).toBe(0);
    });

    it('should handle errors gracefully', async () => {
      mockPrisma.payrollRecord.findFirst.mockRejectedValue(new Error('DB error'));

      const count = await processor.generateWeeklyRecords();
      expect(count).toBe(0);
    });

    it('should skip steps with null completedByUserId', async () => {
      mockPrisma.payrollRecord.findFirst.mockResolvedValue(null);
      mockPrisma.productionStep.findMany.mockResolvedValue([
        {
          completedByUserId: null,
          departmentId: 1,
          pointsAwarded: { toNumber: () => 5 },
          trailerId: 100n,
        },
      ]);

      const count = await processor.generateWeeklyRecords();
      expect(count).toBe(0);
      expect(mockPrisma.payrollRecord.upsert).not.toHaveBeenCalled();
    });
  });
});
