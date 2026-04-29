import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { SmsService } from './sms.service';
import { PrismaService } from '../../prisma/prisma.service';
import { SmsType, SmsStatus } from '@prisma/client';

describe('SmsService', () => {
  let service: SmsService;

  const mockPrisma: Record<string, any> = {
    smsLog: {
      create: jest.fn(),
      findUnique: jest.fn(),
      findMany: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
    },
  };

  const mockConfigService = {
    get: jest.fn().mockReturnValue(null), // No Twilio config — SMS disabled
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        SmsService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: ConfigService, useValue: mockConfigService },
      ],
    }).compile();

    service = module.get<SmsService>(SmsService);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  describe('queueSms', () => {
    it('should create an SmsLog record with queued status', async () => {
      mockPrisma.smsLog.create.mockResolvedValue({ id: BigInt(1) });

      const result = await service.queueSms({
        trailerId: BigInt(100),
        recipientPhone: '+1234567890',
        smsType: SmsType.trailer_complete,
        messageBody: 'Your trailer is ready!',
      });

      expect(result).toBe(BigInt(1));
      expect(mockPrisma.smsLog.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            trailerId: BigInt(100),
            recipientPhone: '+1234567890',
            smsType: SmsType.trailer_complete,
            status: SmsStatus.queued,
          }),
        }),
      );
    });

    it('should handle optional deliveryId', async () => {
      mockPrisma.smsLog.create.mockResolvedValue({ id: BigInt(2) });

      await service.queueSms({
        trailerId: BigInt(100),
        deliveryId: BigInt(50),
        recipientPhone: '+1234567890',
        smsType: SmsType.driver_en_route,
        messageBody: 'Driver en route',
      });

      expect(mockPrisma.smsLog.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            deliveryId: BigInt(50),
          }),
        }),
      );
    });
  });

  describe('sendById', () => {
    it('should skip if SMS not found', async () => {
      mockPrisma.smsLog.findUnique.mockResolvedValue(null);
      await service.sendById(BigInt(999));
      expect(mockPrisma.smsLog.update).not.toHaveBeenCalled();
    });

    it('should skip if SMS not in queued status', async () => {
      mockPrisma.smsLog.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: SmsStatus.sent,
      });
      await service.sendById(BigInt(1));
      expect(mockPrisma.smsLog.update).not.toHaveBeenCalled();
    });

    it('should not send when Twilio is not initialised', async () => {
      mockPrisma.smsLog.findUnique.mockResolvedValue({
        id: BigInt(1),
        recipientPhone: '+1234567890',
        messageBody: 'Test',
        status: SmsStatus.queued,
      });

      // Service has no Twilio init (credentials not set)
      await service.sendById(BigInt(1));

      // Should NOT update status (Twilio not init)
      expect(mockPrisma.smsLog.update).not.toHaveBeenCalled();
    });
  });

  describe('processQueuedMessages', () => {
    it('should process all queued messages', async () => {
      mockPrisma.smsLog.findMany.mockResolvedValue([
        { id: BigInt(1) },
        { id: BigInt(2) },
      ]);
      // sendById will skip because Twilio not init, but we mock findUnique
      mockPrisma.smsLog.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: SmsStatus.queued,
        recipientPhone: '+1234567890',
        messageBody: 'Test',
      });

      const count = await service.processQueuedMessages();

      expect(mockPrisma.smsLog.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { status: SmsStatus.queued },
          take: 50,
        }),
      );
      expect(count).toBe(2);
    });

    it('should return 0 if no queued messages', async () => {
      mockPrisma.smsLog.findMany.mockResolvedValue([]);
      const count = await service.processQueuedMessages();
      expect(count).toBe(0);
    });
  });

  describe('updateStatus', () => {
    it('should update status to delivered', async () => {
      mockPrisma.smsLog.updateMany.mockResolvedValue({ count: 1 });

      await service.updateStatus('SM123', 'delivered');

      expect(mockPrisma.smsLog.updateMany).toHaveBeenCalledWith({
        where: { twilioSid: 'SM123' },
        data: { status: SmsStatus.delivered },
      });
    });

    it('should update status to failed', async () => {
      mockPrisma.smsLog.updateMany.mockResolvedValue({ count: 1 });

      await service.updateStatus('SM456', 'failed');

      expect(mockPrisma.smsLog.updateMany).toHaveBeenCalledWith({
        where: { twilioSid: 'SM456' },
        data: { status: SmsStatus.failed },
      });
    });
  });
});
