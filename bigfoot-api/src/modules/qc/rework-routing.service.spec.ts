import { Test, TestingModule } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
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
      providers: [ReworkRoutingService, { provide: PrismaService, useValue: mockPrisma }],
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
      productionStep: {
        findFirst: jest.fn().mockResolvedValue({
          id: BigInt(199),
          reworkCount: 0,
          department: {
            id: 1,
            code: 'XP_JIG',
            displayName: 'XP Jig Weld',
            isQcStep: false,
          },
        }),
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
        findFirst: jest.fn().mockResolvedValue({
          id: BigInt(199),
          reworkCount: 2,
          department: {
            id: 1,
            code: 'XP_JIG',
            displayName: 'XP Jig Weld',
            isQcStep: false,
          },
        }),
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

  it('should throw QC_INVALID_REWORK_TARGET if department is not part of the trailer workflow', async () => {
    const tx = createMockTx({
      productionStep: {
        findFirst: jest.fn().mockResolvedValue(null), // Trailer has no step there
        updateMany: jest.fn(),
        update: jest.fn(),
      },
    });

    await expect(service.routeRework(BigInt(1), 999, 'Bad', tx)).rejects.toMatchObject({
      errorCode: ErrorCode.QC_INVALID_REWORK_TARGET,
    });
  });

  it('should route rework to PAINT_B even when the series template names PAINT_A', async () => {
    // Regression: a Yeti trailer manually moved to booth B has a PAINT_B
    // production step while the yeti template lists PAINT_A. Rework must
    // follow the trailer's actual step (PAINT_B), not the template, and must
    // NOT throw "department not in workflow".
    const tx = createMockTx({
      productionStep: {
        findFirst: jest.fn().mockResolvedValue({
          id: BigInt(707),
          reworkCount: 0,
          department: {
            id: 42,
            code: 'PAINT_B',
            displayName: 'Paint Booth B',
            isQcStep: false,
          },
        }),
        updateMany: jest.fn(),
        update: jest.fn(),
      },
    });

    const result = await service.routeRework(BigInt(498), 42, 'Runs in paint', tx);

    expect(result.reworkStepId).toBe(BigInt(707));
    expect(result.reworkTargetDeptId).toBe(42);
    expect(result.reworkTargetDepartment).toBe('Paint Booth B');
    expect(result.reworkQueuePosition).toBe(1);
  });

  it('should throw if trailer not found', async () => {
    const tx = createMockTx({
      trailer: {
        findUnique: jest.fn().mockResolvedValue(null),
      },
    });

    await expect(service.routeRework(BigInt(999), 1, 'Bad', tx)).rejects.toMatchObject({
      errorCode: ErrorCode.NOT_FOUND,
    });
  });

  it('should throw if no production step found for trailer in target dept', async () => {
    const tx = createMockTx({
      productionStep: {
        findFirst: jest.fn().mockResolvedValue(null),
        updateMany: jest.fn(),
        update: jest.fn(),
      },
    });

    await expect(service.routeRework(BigInt(1), 1, 'Bad', tx)).rejects.toMatchObject({
      errorCode: ErrorCode.QC_INVALID_REWORK_TARGET,
    });
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
