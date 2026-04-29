import { Test, TestingModule } from '@nestjs/testing';
import { BadRequestException } from '@nestjs/common';
import { ReworkRoutingService } from './rework-routing.service';
import { PrismaService } from '../../prisma/prisma.service';

// ---------------------------------------------------------------------------
// Mock Prisma
// ---------------------------------------------------------------------------

const mockPrisma = {
  // Not directly used by rework-routing (it takes tx as parameter)
};

describe('ReworkRoutingService', () => {
  let service: ReworkRoutingService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        ReworkRoutingService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<ReworkRoutingService>(ReworkRoutingService);
    jest.clearAllMocks();
  });

  // Helper to create a mock transaction client
  function createMockTx(overrides: Record<string, any> = {}) {
    return {
      trailer: {
        findUnique: jest.fn().mockResolvedValue({
          trailerModel: { series: 'xp' },
        }),
      },
      workflowTemplate: {
        findFirst: jest.fn().mockResolvedValue({
          department: { id: 1, code: 'XP_JIG', displayName: 'XP Jig Weld', isQcStep: false },
        }),
      },
      productionStep: {
        findFirst: jest.fn().mockResolvedValue({ id: BigInt(199), reworkCount: 0 }),
        updateMany: jest.fn(),
        update: jest.fn(),
      },
      ...overrides,
    } as any;
  }

  it('should route rework to a valid department and return result', async () => {
    const tx = createMockTx();

    const result = await service.routeRework(BigInt(1), 1, 'Bad welds', tx);

    expect(result.reworkStepId).toBe(BigInt(199));
    expect(result.reworkTargetDeptId).toBe(1);
    expect(result.reworkTargetDepartment).toBe('XP Jig Weld');
    expect(result.reworkQueuePosition).toBe(1);

    // Verify queue bump was called
    expect(tx.productionStep.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          departmentId: 1,
          status: 'active',
        }),
        data: { queuePosition: { increment: 1 } },
      }),
    );

    // Verify rework step updated correctly
    expect(tx.productionStep.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: BigInt(199) },
        data: expect.objectContaining({
          isRework: true,
          reworkCount: 1,
          status: 'active',
          queuePosition: 1,
          pointsAwarded: 0,
        }),
      }),
    );
  });

  it('should increment reworkCount on subsequent reworks', async () => {
    const tx = createMockTx({
      productionStep: {
        findFirst: jest.fn().mockResolvedValue({ id: BigInt(199), reworkCount: 2 }),
        updateMany: jest.fn(),
        update: jest.fn(),
      },
    });

    await service.routeRework(BigInt(1), 1, 'Bad welds again', tx);

    expect(tx.productionStep.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ reworkCount: 3 }),
      }),
    );
  });

  it('should throw QC_INVALID_REWORK_TARGET if department not in workflow', async () => {
    const tx = createMockTx({
      workflowTemplate: {
        findFirst: jest.fn().mockResolvedValue(null), // Not in workflow
      },
    });

    await expect(
      service.routeRework(BigInt(1), 999, 'Bad', tx),
    ).rejects.toThrow(BadRequestException);
  });

  it('should throw if trailer not found', async () => {
    const tx = createMockTx({
      trailer: {
        findUnique: jest.fn().mockResolvedValue(null),
      },
    });

    await expect(
      service.routeRework(BigInt(999), 1, 'Bad', tx),
    ).rejects.toThrow(BadRequestException);
  });

  it('should throw if no production step found for trailer in target dept', async () => {
    const tx = createMockTx({
      productionStep: {
        findFirst: jest.fn().mockResolvedValue(null),
        updateMany: jest.fn(),
        update: jest.fn(),
      },
    });

    await expect(
      service.routeRework(BigInt(1), 1, 'Bad', tx),
    ).rejects.toThrow(BadRequestException);
  });

  it('should reset completedAt, completedByUserId on rework step', async () => {
    const tx = createMockTx();

    await service.routeRework(BigInt(1), 1, 'Bad welds', tx);

    expect(tx.productionStep.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          completedAt: null,
          completedByUserId: null,
        }),
      }),
    );
  });

  it('should set pointsAwarded to 0 on rework step (rework is uncompensated)', async () => {
    const tx = createMockTx();

    await service.routeRework(BigInt(1), 1, 'Bad welds', tx);

    expect(tx.productionStep.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          pointsAwarded: 0,
        }),
      }),
    );
  });
});
