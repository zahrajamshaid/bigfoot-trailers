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
    // findAll/findByEntity now enrich the response by batch-loading the
    // related entities. Tests mock these so the enrichment short-circuits
    // (returns empty lookups) — assertions still cover the core filter/
    // pagination logic, plus the new entity-label tests cover enrichment
    // directly.
    trailer: { findMany: jest.fn().mockResolvedValue([]) },
    productionStep: { findMany: jest.fn().mockResolvedValue([]) },
    qcInspection: { findMany: jest.fn().mockResolvedValue([]) },
    delivery: { findMany: jest.fn().mockResolvedValue([]) },
    deliveryBatch: { findMany: jest.fn().mockResolvedValue([]) },
    department: { findMany: jest.fn().mockResolvedValue([]) },
    user: { findMany: jest.fn().mockResolvedValue([]) },
    systemAnnouncement: { findMany: jest.fn().mockResolvedValue([]) },
    $transaction: jest.fn(),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [AuditLogService, { provide: PrismaService, useValue: mockPrisma }],
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
        { id: 1n, entityType: 'trailer', entityId: 100n, action: 'CREATE', createdAt: new Date(), oldValues: null, newValues: null },
      ];
      mockPrisma.auditLog.findMany.mockResolvedValue(mockItems);
      mockPrisma.auditLog.count.mockResolvedValue(1);

      const result = await service.findAll({ page: 1, limit: 50 });

      expect(result.items).toHaveLength(1);
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
        { id: 1n, entityType: 'trailer', entityId: 100n, action: 'UPDATE', oldValues: null, newValues: null },
      ];
      mockPrisma.auditLog.findMany.mockResolvedValue(mockEntries);
      mockPrisma.$transaction.mockResolvedValue([mockEntries, mockEntries.length]);

      const result = await service.findByEntity('trailer', 100);

      expect(result.items).toHaveLength(mockEntries.length);
      expect(result.total).toBe(mockEntries.length);
      expect(mockPrisma.auditLog.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { entityType: 'trailer', entityId: 100n },
          orderBy: { createdAt: 'desc' },
        }),
      );
    });
  });

  // ===========================================================================
  // enrich — the human-readable layer (entityLabel, summary, actionLabel)
  // ===========================================================================
  describe('enrich', () => {
    it('labels a trailer UPDATE with its SO number + status diff', async () => {
      mockPrisma.auditLog.findMany.mockResolvedValue([
        {
          id: 1n,
          userId: 10n,
          entityType: 'trailer',
          entityId: 233n,
          action: 'UPDATE',
          oldValues: { status: 'in_production' },
          newValues: { status: 'ready_for_delivery' },
          ipAddress: null,
          createdAt: new Date('2026-06-18T12:00:00Z'),
          user: { id: 10n, fullName: 'Admin Owner', email: null },
        },
      ]);
      mockPrisma.auditLog.count.mockResolvedValue(1);
      mockPrisma.trailer.findMany.mockResolvedValue([
        { id: 233n, soNumber: '6715' },
      ]);

      const result = await service.findAll({});

      const row = result.items[0] as any;
      expect(row.entityLabel).toBe('SO 6715');
      expect(row.actionLabel).toBe('Updated');
      expect(row.summary).toBe('Status: in_production → ready_for_delivery');
    });

    it('labels a QC inspection CREATE with the SO + dept + pass result', async () => {
      mockPrisma.auditLog.findMany.mockResolvedValue([
        {
          id: 2n,
          userId: 11n,
          entityType: 'qc_inspection',
          entityId: 999n,
          action: 'CREATE',
          oldValues: null,
          newValues: { result: 'pass', attemptNumber: 1 },
          ipAddress: null,
          createdAt: new Date(),
          user: { id: 11n, fullName: 'Dev QC Inspector', email: null },
        },
      ]);
      mockPrisma.auditLog.count.mockResolvedValue(1);
      mockPrisma.qcInspection.findMany.mockResolvedValue([
        {
          id: 999n,
          trailer: { soNumber: '6912' },
          productionStep: { department: { code: 'QC_3' } },
        },
      ]);

      const result = await service.findAll({});

      const row = result.items[0] as any;
      expect(row.entityLabel).toBe('SO 6912 — QC_3 QC');
      expect(row.summary).toBe('Passed (attempt 1)');
    });

    it('labels a QC fail with the rework target', async () => {
      mockPrisma.auditLog.findMany.mockResolvedValue([
        {
          id: 3n,
          userId: 11n,
          entityType: 'qc_inspection',
          entityId: 1000n,
          action: 'CREATE',
          oldValues: null,
          newValues: { result: 'fail', attemptNumber: 2, reworkTargetDeptCode: 'WIRE' },
          ipAddress: null,
          createdAt: new Date(),
          user: { id: 11n, fullName: 'Dev QC Inspector', email: null },
        },
      ]);
      mockPrisma.auditLog.count.mockResolvedValue(1);
      mockPrisma.qcInspection.findMany.mockResolvedValue([
        {
          id: 1000n,
          trailer: { soNumber: '6877' },
          productionStep: { department: { code: 'QC_3' } },
        },
      ]);

      const result = await service.findAll({});

      const row = result.items[0] as any;
      expect(row.summary).toBe('Failed (attempt 2) → sent to WIRE');
    });

    it('falls back to entityType #id when the entity has been deleted', async () => {
      mockPrisma.auditLog.findMany.mockResolvedValue([
        {
          id: 4n,
          userId: null,
          entityType: 'trailer',
          entityId: 9999n,
          action: 'DELETE',
          oldValues: { soNumber: 'GONE' },
          newValues: null,
          ipAddress: null,
          createdAt: new Date(),
          user: null,
        },
      ]);
      mockPrisma.auditLog.count.mockResolvedValue(1);
      mockPrisma.trailer.findMany.mockResolvedValue([]); // deleted — no row

      const result = await service.findAll({});

      const row = result.items[0] as any;
      expect(row.entityLabel).toBe('Trailer #9999');
      expect(row.actionLabel).toBe('Deleted');
    });

    it('translates trailer.jumped_to_step into a readable verb', async () => {
      mockPrisma.auditLog.findMany.mockResolvedValue([
        {
          id: 5n,
          userId: 1n,
          entityType: 'trailer',
          entityId: 233n,
          action: 'trailer.jumped_to_step',
          oldValues: null,
          newValues: null,
          ipAddress: null,
          createdAt: new Date(),
          user: { id: 1n, fullName: 'Admin Owner', email: null },
        },
      ]);
      mockPrisma.auditLog.count.mockResolvedValue(1);
      mockPrisma.trailer.findMany.mockResolvedValue([
        { id: 233n, soNumber: '6715' },
      ]);

      const result = await service.findAll({});

      const row = result.items[0] as any;
      expect(row.entityLabel).toBe('SO 6715');
      expect(row.actionLabel).toBe('Jumped to step');
    });

    it('skips lookups for empty buckets — no Prisma calls for unused types', async () => {
      mockPrisma.auditLog.findMany.mockResolvedValue([
        {
          id: 6n,
          userId: 1n,
          entityType: 'trailer',
          entityId: 1n,
          action: 'CREATE',
          oldValues: null,
          newValues: null,
          ipAddress: null,
          createdAt: new Date(),
          user: { id: 1n, fullName: 'X', email: null },
        },
      ]);
      mockPrisma.auditLog.count.mockResolvedValue(1);
      mockPrisma.trailer.findMany.mockResolvedValue([
        { id: 1n, soNumber: 'X-1' },
      ]);

      await service.findAll({});

      expect(mockPrisma.trailer.findMany).toHaveBeenCalledTimes(1);
      // No QC / delivery / batch / dept lookups because none of those entity
      // types appeared in the items list.
      expect(mockPrisma.qcInspection.findMany).not.toHaveBeenCalled();
      expect(mockPrisma.delivery.findMany).not.toHaveBeenCalled();
      expect(mockPrisma.deliveryBatch.findMany).not.toHaveBeenCalled();
      expect(mockPrisma.department.findMany).not.toHaveBeenCalled();
    });
  });
});
