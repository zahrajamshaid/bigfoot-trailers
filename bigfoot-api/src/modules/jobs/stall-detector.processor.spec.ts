import { Test, TestingModule } from '@nestjs/testing';
import { StallDetectorProcessor } from './stall-detector.processor';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';

describe('StallDetectorProcessor', () => {
  let processor: StallDetectorProcessor;

  const mockPrisma = {
    productionStep: { findMany: jest.fn() },
    stallAlert: {
      findFirst: jest.fn(),
      create: jest.fn(),
    },
  };

  const mockNotificationsService = {
    onTrailerStalled: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        StallDetectorProcessor,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: NotificationsService, useValue: mockNotificationsService },
      ],
    }).compile();

    processor = module.get<StallDetectorProcessor>(StallDetectorProcessor);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(processor).toBeDefined();
  });

  describe('detectStalls', () => {
    it('should detect a stalled step and create alert', async () => {
      const stalledTime = new Date(Date.now() - 60 * 60 * 1000 * 50); // 50 hours ago
      mockPrisma.productionStep.findMany.mockResolvedValue([
        {
          id: BigInt(1),
          trailerId: BigInt(100),
          departmentId: 9,
          becameActiveAt: stalledTime,
          department: {
            id: 9,
            displayName: 'Paint Prep',
            stallThresholdHours: 48,
          },
          trailer: { id: BigInt(100), soNumber: 'SO-1001' },
        },
      ]);
      mockPrisma.stallAlert.findFirst.mockResolvedValue(null); // No existing alert
      mockPrisma.stallAlert.create.mockResolvedValue({ id: BigInt(1) });
      mockNotificationsService.onTrailerStalled.mockResolvedValue(undefined);

      await processor.detectStalls();

      expect(mockPrisma.stallAlert.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            trailerId: BigInt(100),
            productionStepId: BigInt(1),
            departmentId: 9,
          }),
        }),
      );
      expect(mockNotificationsService.onTrailerStalled).toHaveBeenCalledWith(
        expect.objectContaining({
          trailerId: BigInt(100),
          soNumber: 'SO-1001',
          departmentName: 'Paint Prep',
        }),
      );
    });

    it('should skip steps that have not exceeded threshold', async () => {
      const recentTime = new Date(Date.now() - 60 * 60 * 1000 * 10); // 10 hours ago
      mockPrisma.productionStep.findMany.mockResolvedValue([
        {
          id: BigInt(1),
          trailerId: BigInt(100),
          departmentId: 9,
          becameActiveAt: recentTime,
          department: {
            id: 9,
            displayName: 'Paint Prep',
            stallThresholdHours: 48,
          },
          trailer: { id: BigInt(100), soNumber: 'SO-1001' },
        },
      ]);

      await processor.detectStalls();

      expect(mockPrisma.stallAlert.create).not.toHaveBeenCalled();
    });

    it('should skip if alert already exists for step', async () => {
      const stalledTime = new Date(Date.now() - 60 * 60 * 1000 * 50);
      mockPrisma.productionStep.findMany.mockResolvedValue([
        {
          id: BigInt(1),
          trailerId: BigInt(100),
          departmentId: 9,
          becameActiveAt: stalledTime,
          department: { id: 9, displayName: 'Paint Prep', stallThresholdHours: 48 },
          trailer: { id: BigInt(100), soNumber: 'SO-1001' },
        },
      ]);
      mockPrisma.stallAlert.findFirst.mockResolvedValue({ id: BigInt(99) }); // Already alerted

      await processor.detectStalls();

      expect(mockPrisma.stallAlert.create).not.toHaveBeenCalled();
      expect(mockNotificationsService.onTrailerStalled).not.toHaveBeenCalled();
    });

    it('should handle no active steps gracefully', async () => {
      mockPrisma.productionStep.findMany.mockResolvedValue([]);
      await processor.detectStalls();
      expect(mockPrisma.stallAlert.create).not.toHaveBeenCalled();
    });
  });
});
