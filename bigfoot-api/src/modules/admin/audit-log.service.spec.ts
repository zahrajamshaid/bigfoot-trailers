import { Test, TestingModule } from '@nestjs/testing';
import { AuditLogService } from './audit-log.service';
import { PrismaService } from '../../prisma/prisma.service';

describe('AuditLogService', () => {
  let service: AuditLogService;

  const mockPrisma = {
    auditLog: {
      create: jest.fn(),
      findMany: jest.fn(),
      count: jest.fn(),
    },
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuditLogService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<AuditLogService>(AuditLogService);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ===========================================================================
  // create
  // ===========================================================================
  describe('create', () => {
    it('should create an audit log entry', async () => {
      mockPrisma.auditLog.create.mockResolvedValue({ id: 1n });

      await service.create({
        userId: 10,
        entityType: 'trailer',
        entityId: 100,
        action: 'CREATE',
        newValues: { soNumber: 'SO-1001' },
        ipAddress: '192.168.1.1',
      });

      expect(mockPrisma.auditLog.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          userId: 10n,
          entityType: 'trailer',
          entityId: 100n,
          action: 'CREATE',
          ipAddress: '192.168.1.1',
        }),
        select: { id: true },
      });
    });

    it('should handle null userId', async () => {
      mockPrisma.auditLog.create.mockResolvedValue({ id: 2n });

      await service.create({
        entityType: 'department',
        entityId: 5,
        action: 'UPDATE',
      });

      expect(mockPrisma.auditLog.create).toHaveBeenCalledWith({
        data: expect.objectContaining({
          userId: null,
          entityType: 'department',
          entityId: 5n,
        }),
        select: { id: true },
      });
    });

    it('should use transaction client when provided', async () => {
      const mockTx = {
        auditLog: { create: jest.fn().mockResolvedValue({ id: 3n }) },
      };

      await service.create(
        {
          userId: 1,
          entityType: 'trailer',
          entityId: 50,
          action: 'UPDATE',
        },
        mockTx as any,
      );

      expect(mockTx.auditLog.create).toHaveBeenCalled();
      expect(mockPrisma.auditLog.create).not.toHaveBeenCalled();
    });
  });

  // ===========================================================================
  // findAll
  // ===========================================================================
  describe('findAll', () => {
    it('should return paginated audit log entries', async () => {
      const mockItems = [
        { id: 1n, entityType: 'trailer', action: 'CREATE', createdAt: new Date() },
      ];
      mockPrisma.auditLog.findMany.mockResolvedValue(mockItems);
      mockPrisma.auditLog.count.mockResolvedValue(1);

      const result = await service.findAll({ page: 1, limit: 50 });

      expect(result.items).toEqual(mockItems);
      expect(result.total).toBe(1);
      expect(result.page).toBe(1);
      expect(result.totalPages).toBe(1);
    });

    it('should apply entity type filter', async () => {
      mockPrisma.auditLog.findMany.mockResolvedValue([]);
      mockPrisma.auditLog.count.mockResolvedValue(0);

      await service.findAll({ entityType: 'trailer' });

      expect(mockPrisma.auditLog.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ entityType: 'trailer' }),
        }),
      );
    });

    it('should apply date range filters', async () => {
      mockPrisma.auditLog.findMany.mockResolvedValue([]);
      mockPrisma.auditLog.count.mockResolvedValue(0);

      await service.findAll({ from: '2026-01-01', to: '2026-01-31' });

      expect(mockPrisma.auditLog.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            createdAt: {
              gte: new Date('2026-01-01'),
              lte: new Date('2026-01-31'),
            },
          }),
        }),
      );
    });

    it('should cap limit at 200', async () => {
      mockPrisma.auditLog.findMany.mockResolvedValue([]);
      mockPrisma.auditLog.count.mockResolvedValue(0);

      await service.findAll({ limit: 500 });

      expect(mockPrisma.auditLog.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ take: 200 }),
      );
    });

    it('should default to page 1 and limit 50', async () => {
      mockPrisma.auditLog.findMany.mockResolvedValue([]);
      mockPrisma.auditLog.count.mockResolvedValue(0);

      await service.findAll({});

      expect(mockPrisma.auditLog.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ skip: 0, take: 50 }),
      );
    });
  });

  // ===========================================================================
  // findByEntity
  // ===========================================================================
  describe('findByEntity', () => {
    it('should return audit log for a specific entity', async () => {
      const mockEntries = [
        { id: 1n, entityType: 'trailer', entityId: 100n, action: 'UPDATE' },
      ];
      mockPrisma.auditLog.findMany.mockResolvedValue(mockEntries);

      const result = await service.findByEntity('trailer', 100);

      expect(result).toEqual(mockEntries);
      expect(mockPrisma.auditLog.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { entityType: 'trailer', entityId: 100n },
          orderBy: { createdAt: 'desc' },
        }),
      );
    });
  });
});
