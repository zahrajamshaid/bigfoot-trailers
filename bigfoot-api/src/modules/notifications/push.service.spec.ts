import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { PushService } from './push.service';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationType } from '@prisma/client';

describe('PushService', () => {
  let service: PushService;

  const mockPrisma: Record<string, any> = {
    pushNotification: {
      createMany: jest.fn(),
    },
    user: {
      findMany: jest.fn(),
      updateMany: jest.fn(),
    },
  };

  const mockConfigService = {
    get: jest.fn().mockReturnValue(null), // No Firebase config — FCM disabled
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        PushService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: ConfigService, useValue: mockConfigService },
      ],
    }).compile();

    service = module.get<PushService>(PushService);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  describe('send', () => {
    it('should persist push notification records', async () => {
      mockPrisma.pushNotification.createMany.mockResolvedValue({ count: 2 });
      mockPrisma.user.findMany.mockResolvedValue([]);

      await service.send({
        recipientUserIds: [BigInt(1), BigInt(2)],
        trailerId: BigInt(100),
        notificationType: NotificationType.qc_fail,
        title: 'Test',
        body: 'Test body',
      });

      expect(mockPrisma.pushNotification.createMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.arrayContaining([
            expect.objectContaining({
              recipientUserId: BigInt(1),
              notificationType: NotificationType.qc_fail,
            }),
            expect.objectContaining({
              recipientUserId: BigInt(2),
            }),
          ]),
        }),
      );
    });

    it('should skip if no recipients', async () => {
      await service.send({
        recipientUserIds: [],
        notificationType: NotificationType.qc_fail,
        title: 'Test',
        body: 'Test',
      });

      expect(mockPrisma.pushNotification.createMany).not.toHaveBeenCalled();
    });
  });

  describe('sendQcFail', () => {
    it('should look up production_managers and send', async () => {
      mockPrisma.user.findMany.mockResolvedValue([
        { id: BigInt(10) },
        { id: BigInt(11) },
      ]);
      mockPrisma.pushNotification.createMany.mockResolvedValue({ count: 2 });

      await service.sendQcFail(
        BigInt(100),
        'SO-1001',
        'QC_1',
        'Paint bubbling',
        'XP Jig Weld',
        1,
      );

      expect(mockPrisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { role: 'production_manager', isActive: true },
        }),
      );
      expect(mockPrisma.pushNotification.createMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.arrayContaining([
            expect.objectContaining({
              recipientUserId: BigInt(10),
              notificationType: NotificationType.qc_fail,
              title: 'QC Fail — SO-1001',
            }),
          ]),
        }),
      );
    });
  });

  describe('sendTrailerStalled', () => {
    it('should send to production_manager + owner', async () => {
      mockPrisma.user.findMany.mockResolvedValue([{ id: BigInt(10) }]);
      mockPrisma.pushNotification.createMany.mockResolvedValue({ count: 1 });

      await service.sendTrailerStalled(BigInt(100), 'SO-1001', 'Paint Prep', 52.5);

      expect(mockPrisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { role: { in: ['production_manager', 'owner'] }, isActive: true },
        }),
      );
      expect(mockPrisma.pushNotification.createMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.arrayContaining([
            expect.objectContaining({
              notificationType: NotificationType.trailer_stalled,
            }),
          ]),
        }),
      );
    });
  });

  describe('sendWorkerMessage', () => {
    it('should send to specific user', async () => {
      mockPrisma.pushNotification.createMany.mockResolvedValue({ count: 1 });
      mockPrisma.user.findMany.mockResolvedValue([]);

      await service.sendWorkerMessage(
        BigInt(20),
        BigInt(100),
        'SO-1001',
        'John Worker',
        'Need more paint',
      );

      expect(mockPrisma.pushNotification.createMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.arrayContaining([
            expect.objectContaining({
              recipientUserId: BigInt(20),
              notificationType: NotificationType.worker_message,
              title: 'Message from John Worker',
            }),
          ]),
        }),
      );
    });
  });

  describe('sendPaymentNotCollected', () => {
    it('should send to transport_managers', async () => {
      mockPrisma.user.findMany.mockResolvedValue([{ id: BigInt(30) }]);
      mockPrisma.pushNotification.createMany.mockResolvedValue({ count: 1 });

      await service.sendPaymentNotCollected(BigInt(100), 'SO-1001', '5000.00', '1000.00');

      expect(mockPrisma.user.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { role: 'transport_manager', isActive: true },
        }),
      );
      expect(mockPrisma.pushNotification.createMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.arrayContaining([
            expect.objectContaining({
              notificationType: NotificationType.payment_not_collected,
              title: 'Payment Not Collected — SO-1001',
            }),
          ]),
        }),
      );
    });
  });
});
