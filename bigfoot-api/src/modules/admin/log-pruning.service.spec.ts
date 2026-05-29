import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { LogPruningService } from './log-pruning.service';
import { PrismaService } from '../../prisma/prisma.service';

describe('LogPruningService', () => {
  let service: LogPruningService;
  const mockPrisma = {
    auditLog: { deleteMany: jest.fn() },
    smsLog: { deleteMany: jest.fn() },
  };
  const mockConfig = { get: jest.fn() };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        LogPruningService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: ConfigService, useValue: mockConfig },
      ],
    }).compile();

    service = module.get<LogPruningService>(LogPruningService);
    jest.clearAllMocks();
  });

  describe('pruneOldLogs', () => {
    it('uses the AUDIT_LOG_RETENTION_DAYS env var when set', async () => {
      mockConfig.get.mockReturnValue('30');
      mockPrisma.auditLog.deleteMany.mockResolvedValue({ count: 5 });
      mockPrisma.smsLog.deleteMany.mockResolvedValue({ count: 2 });

      await service.pruneOldLogs();

      const auditCall = mockPrisma.auditLog.deleteMany.mock.calls[0][0];
      const cutoff = auditCall.where.createdAt.lt as Date;
      const ageDays = (Date.now() - cutoff.getTime()) / (1000 * 60 * 60 * 24);
      expect(ageDays).toBeGreaterThan(29.9);
      expect(ageDays).toBeLessThan(30.1);
    });

    it('defaults to 90 days when AUDIT_LOG_RETENTION_DAYS is unset', async () => {
      mockConfig.get.mockReturnValue(undefined);
      mockPrisma.auditLog.deleteMany.mockResolvedValue({ count: 0 });
      mockPrisma.smsLog.deleteMany.mockResolvedValue({ count: 0 });

      await service.pruneOldLogs();

      const auditCall = mockPrisma.auditLog.deleteMany.mock.calls[0][0];
      const cutoff = auditCall.where.createdAt.lt as Date;
      const ageDays = (Date.now() - cutoff.getTime()) / (1000 * 60 * 60 * 24);
      expect(ageDays).toBeGreaterThan(89.9);
      expect(ageDays).toBeLessThan(90.1);
    });

    it('defaults to 90 days when AUDIT_LOG_RETENTION_DAYS is malformed', async () => {
      mockConfig.get.mockReturnValue('not-a-number');
      mockPrisma.auditLog.deleteMany.mockResolvedValue({ count: 0 });
      mockPrisma.smsLog.deleteMany.mockResolvedValue({ count: 0 });

      await service.pruneOldLogs();

      const auditCall = mockPrisma.auditLog.deleteMany.mock.calls[0][0];
      const cutoff = auditCall.where.createdAt.lt as Date;
      const ageDays = (Date.now() - cutoff.getTime()) / (1000 * 60 * 60 * 24);
      expect(ageDays).toBeGreaterThan(89.9);
      expect(ageDays).toBeLessThan(90.1);
    });

    it('defaults to 90 days when AUDIT_LOG_RETENTION_DAYS is non-positive', async () => {
      mockConfig.get.mockReturnValue('0');
      mockPrisma.auditLog.deleteMany.mockResolvedValue({ count: 0 });
      mockPrisma.smsLog.deleteMany.mockResolvedValue({ count: 0 });

      await service.pruneOldLogs();

      const auditCall = mockPrisma.auditLog.deleteMany.mock.calls[0][0];
      const cutoff = auditCall.where.createdAt.lt as Date;
      const ageDays = (Date.now() - cutoff.getTime()) / (1000 * 60 * 60 * 24);
      expect(ageDays).toBeGreaterThan(89.9);
    });

    it('prunes both audit_log and sms_log in parallel', async () => {
      mockConfig.get.mockReturnValue('90');
      mockPrisma.auditLog.deleteMany.mockResolvedValue({ count: 100 });
      mockPrisma.smsLog.deleteMany.mockResolvedValue({ count: 50 });

      await service.pruneOldLogs();

      expect(mockPrisma.auditLog.deleteMany).toHaveBeenCalledTimes(1);
      expect(mockPrisma.smsLog.deleteMany).toHaveBeenCalledTimes(1);
    });

    it('does not throw when delete fails — failure is logged, not propagated', async () => {
      mockConfig.get.mockReturnValue('90');
      mockPrisma.auditLog.deleteMany.mockRejectedValue(
        new Error('connection timeout'),
      );
      mockPrisma.smsLog.deleteMany.mockResolvedValue({ count: 0 });

      await expect(service.pruneOldLogs()).resolves.toBeUndefined();
    });
  });
});
