import { Test, TestingModule } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
import { TrailersService } from './trailers.service';
import { WorkflowGeneratorService } from './workflow-generator.service';
import { StorageService } from '../storage/storage.service';
import { PrismaService } from '../../prisma/prisma.service';

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const mockTrailer = {
  id: BigInt(1),
  soNumber: 'SO-1001',
  vinNumber: null,
  trailerModelId: 1,
  customerId: BigInt(100),
  currentLocationId: 1,
  createdByUserId: BigInt(10),
  color: 'Red',
  sizeFt: '16ft',
  optionsNotes: 'Winch + tongue box',
  qbSoPdfStorageUrl: null,
  qbSoPdfStorageKey: null,
  qbSoId: null,
  qbInvoicedAt: null,
  status: 'pending_production',
  globalPriority: 9999,
  isStockBuild: false,
  isHot: false,
  customerLocked: false,
  createdAt: new Date('2026-01-01'),
  updatedAt: new Date('2026-01-01'),
  trailerModel: {
    id: 1,
    code: 'XP_14ET',
    displayName: '14K ET XP',
    series: 'xp',
    weightRating: '14,000 lb',
  },
  customer: {
    id: BigInt(100),
    name: 'John Doe',
    company: null,
    smsPhone: '+1234567890',
    customerType: 'end_user',
  },
  currentLocation: { id: 1, code: 'MULBERRY', name: 'Bigfoot Trailers Mulberry' },
  addons: [],
};

const mockAddon = {
  id: BigInt(50),
  addonName: 'Winch',
  notes: null,
  addedAt: new Date('2026-01-02'),
};

// ---------------------------------------------------------------------------
// Prisma mock
// ---------------------------------------------------------------------------

const mockPrisma = {
  trailer: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    count: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  },
  trailerModel: {
    findUnique: jest.fn(),
  },
  customer: {
    findUnique: jest.fn(),
  },
  location: {
    findFirst: jest.fn(),
    findUnique: jest.fn(),
  },
  trailerAddon: {
    create: jest.fn(),
    findFirst: jest.fn(),
    delete: jest.fn(),
  },
  productionStep: {
    findMany: jest.fn(),
  },
  qcInspection: {
    findMany: jest.fn(),
  },
  delivery: {
    findMany: jest.fn(),
  },
  auditLog: {
    findMany: jest.fn(),
  },
  $transaction: jest.fn(),
};

const mockWorkflowGenerator = {
  generateSteps: jest.fn(),
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('TrailersService', () => {
  let service: TrailersService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        TrailersService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: WorkflowGeneratorService, useValue: mockWorkflowGenerator },
        { provide: StorageService, useValue: { deleteObjects: jest.fn() } },
      ],
    }).compile();

    service = module.get<TrailersService>(TrailersService);
    jest.clearAllMocks();
  });

  // =========================================================================
  // findAll
  // =========================================================================
  describe('findAll', () => {
    it('should return paginated trailers', async () => {
      mockPrisma.$transaction.mockResolvedValue([[mockTrailer], 1]);

      const result = await service.findAll({ page: 1, limit: 25 });

      expect(result.trailers).toHaveLength(1);
      expect(result.total).toBe(1);
      expect(result.page).toBe(1);
      expect(result.limit).toBe(25);
    });

    it('should default to page 1 and limit 25', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);

      const result = await service.findAll({});

      expect(result.page).toBe(1);
      expect(result.limit).toBe(25);
    });

    it('should apply status filter', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);

      await service.findAll({ status: 'in_production' as any });

      expect(mockPrisma.$transaction).toHaveBeenCalled();
    });

    it('should apply series filter via trailerModel relation', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);

      await service.findAll({ series: 'xp' as any });

      expect(mockPrisma.$transaction).toHaveBeenCalled();
    });

    it('should apply isHot filter', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);

      await service.findAll({ isHot: true });

      expect(mockPrisma.$transaction).toHaveBeenCalled();
    });
  });

  // =========================================================================
  // create
  // =========================================================================
  describe('create', () => {
    const createDto = {
      soNumber: 'SO-2001',
      trailerModelId: 1,
      color: 'Blue',
      sizeFt: '18ft',
      customerId: 100,
    };

    it('should create a trailer and generate 12 workflow steps atomically', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null); // SO not taken
      mockPrisma.trailerModel.findUnique.mockResolvedValue({ id: 1, series: 'xp' });
      mockPrisma.customer.findUnique.mockResolvedValue({ id: BigInt(100) });
      mockPrisma.location.findFirst.mockResolvedValue({ id: 1 });

      mockPrisma.$transaction.mockImplementation(async (fn: any) => {
        const txClient = {
          trailer: { create: jest.fn().mockResolvedValue(mockTrailer) },
        };
        mockWorkflowGenerator.generateSteps.mockResolvedValue({
          trailerId: BigInt(1),
          series: 'xp',
          totalSteps: 12,
          firstActiveStepId: BigInt(100),
        });
        return fn(txClient);
      });

      const result = await service.create(createDto, BigInt(10));

      expect(result.trailer).toBeDefined();
      expect(result.stepsSummary.totalSteps).toBe(12);
      expect(mockWorkflowGenerator.generateSteps).toHaveBeenCalled();
    });

    it('should throw AppError for duplicate SO number', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(99) });

      await expect(service.create(createDto, BigInt(10))).rejects.toMatchObject({
        errorCode: ErrorCode.SO_NUMBER_EXISTS,
      });
    });

    it('should throw AppError for invalid trailer model', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);
      mockPrisma.trailerModel.findUnique.mockResolvedValue(null);

      await expect(service.create(createDto, BigInt(10))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });

    it('should throw AppError for invalid customer id', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);
      mockPrisma.trailerModel.findUnique.mockResolvedValue({ id: 1, series: 'xp' });
      mockPrisma.customer.findUnique.mockResolvedValue(null);

      await expect(service.create(createDto, BigInt(10))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });

    it('should allow creating without customerId (stock build)', async () => {
      const stockDto = {
        soNumber: 'SO-3001',
        trailerModelId: 1,
        isStockBuild: true,
        stockLocationId: 1,
      };

      mockPrisma.trailer.findUnique.mockResolvedValue(null);
      mockPrisma.trailerModel.findUnique.mockResolvedValue({ id: 1, series: 'xp' });
      mockPrisma.location.findFirst.mockResolvedValue({ id: 1 });
      mockPrisma.location.findUnique.mockResolvedValue({ id: 1, isActive: true });

      mockPrisma.$transaction.mockImplementation(async (fn: any) => {
        const txClient = {
          trailer: {
            create: jest.fn().mockResolvedValue({
              ...mockTrailer,
              customerId: null,
              isStockBuild: true,
            }),
          },
        };
        mockWorkflowGenerator.generateSteps.mockResolvedValue({
          trailerId: BigInt(1),
          series: 'xp',
          totalSteps: 12,
          firstActiveStepId: BigInt(100),
        });
        return fn(txClient);
      });

      const result = await service.create(stockDto, BigInt(10));

      expect(result.trailer).toBeDefined();
    });

    it('should throw AppError if no factory location exists', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);
      mockPrisma.trailerModel.findUnique.mockResolvedValue({ id: 1, series: 'xp' });
      mockPrisma.location.findFirst.mockResolvedValue(null);

      await expect(
        service.create({ soNumber: 'SO-4001', trailerModelId: 1 }, BigInt(10)),
      ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
    });
  });

  // =========================================================================
  // findOne
  // =========================================================================
  describe('findOne', () => {
    it('should return full trailer detail', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({
        ...mockTrailer,
        productionSteps: [],
      });

      const result = await service.findOne(BigInt(1));

      expect(result.soNumber).toBe('SO-1001');
      expect(result.trailerModel.code).toBe('XP_14ET');
    });

    it('should throw AppError for non-existent trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(service.findOne(BigInt(999))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });

  // =========================================================================
  // update
  // =========================================================================
  describe('update', () => {
    it('should update color and notes', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.trailer.update.mockResolvedValue({ ...mockTrailer, color: 'Green' });

      await service.update(BigInt(1), {
        color: 'Green',
        optionsNotes: 'Updated',
      });

      expect(mockPrisma.trailer.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ color: 'Green', optionsNotes: 'Updated' }),
        }),
      );
    });

    it('should update status', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.trailer.update.mockResolvedValue({ ...mockTrailer, status: 'on_hold' });

      await service.update(BigInt(1), { status: 'on_hold' as any });

      expect(mockPrisma.trailer.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ status: 'on_hold' }),
        }),
      );
    });

    it('should throw AppError for non-existent trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(service.update(BigInt(999), { color: 'Red' })).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });

  // =========================================================================
  // setPriority
  // =========================================================================
  describe('setPriority', () => {
    it('should update globalPriority', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.trailer.update.mockResolvedValue({ ...mockTrailer, globalPriority: 5 });

      await service.setPriority(BigInt(1), { globalPriority: 5 });

      expect(mockPrisma.trailer.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: { globalPriority: 5 },
        }),
      );
    });

    it('should throw AppError for non-existent trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(
        service.setPriority(BigInt(999), { globalPriority: 1 }),
      ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
    });
  });

  // =========================================================================
  // toggleHot
  // =========================================================================
  describe('toggleHot', () => {
    it('should toggle isHot to true', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.trailer.update.mockResolvedValue({ ...mockTrailer, isHot: true });

      await service.toggleHot(BigInt(1), { isHot: true });

      expect(mockPrisma.trailer.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: { isHot: true },
        }),
      );
    });

    it('should throw AppError for non-existent trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(service.toggleHot(BigInt(999), { isHot: true })).rejects.toMatchObject(
        { errorCode: ErrorCode.NOT_FOUND },
      );
    });
  });

  // =========================================================================
  // addAddon / removeAddon
  // =========================================================================
  describe('addAddon', () => {
    it('should add an addon to a trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.trailerAddon.create.mockResolvedValue(mockAddon);

      const result = await service.addAddon(BigInt(1), { addonName: 'Winch' });

      expect(result.addonName).toBe('Winch');
      expect(mockPrisma.trailerAddon.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ trailerId: BigInt(1), addonName: 'Winch' }),
        }),
      );
    });

    it('should throw AppError for non-existent trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(
        service.addAddon(BigInt(999), { addonName: 'X' }),
      ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
    });
  });

  describe('removeAddon', () => {
    it('should remove an addon', async () => {
      mockPrisma.trailerAddon.findFirst.mockResolvedValue({ id: BigInt(50) });

      const result = await service.removeAddon(BigInt(1), BigInt(50));

      expect(result.deleted).toBe(true);
      expect(mockPrisma.trailerAddon.delete).toHaveBeenCalledWith({
        where: { id: BigInt(50) },
      });
    });

    it('should throw AppError if addon does not belong to trailer', async () => {
      mockPrisma.trailerAddon.findFirst.mockResolvedValue(null);

      await expect(service.removeAddon(BigInt(1), BigInt(999))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });

  // =========================================================================
  // uploadQbPdf
  // =========================================================================
  describe('uploadQbPdf', () => {
    it('should attach QB PDF storage key and URL', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.trailer.update.mockResolvedValue({
        ...mockTrailer,
        qbSoPdfStorageKey: 'trailers/SO-1001/qb-so.pdf',
        qbSoPdfStorageUrl: 'https://spaces.example.com/trailers/SO-1001/qb-so.pdf',
      });

      await service.uploadQbPdf(BigInt(1), {
        storageKey: 'trailers/SO-1001/qb-so.pdf',
        storageUrl: 'https://spaces.example.com/trailers/SO-1001/qb-so.pdf',
      });

      expect(mockPrisma.trailer.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: {
            qbSoPdfStorageKey: 'trailers/SO-1001/qb-so.pdf',
            qbSoPdfStorageUrl: 'https://spaces.example.com/trailers/SO-1001/qb-so.pdf',
          },
        }),
      );
    });

    it('should throw AppError for non-existent trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(
        service.uploadQbPdf(BigInt(999), { storageKey: 'x', storageUrl: 'x' }),
      ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
    });
  });

  // =========================================================================
  // getSteps
  // =========================================================================
  describe('getSteps', () => {
    it('should return all production steps for a trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.productionStep.findMany.mockResolvedValue([
        { id: BigInt(100), stepOrder: 1, status: 'active', departmentId: 1 },
        { id: BigInt(101), stepOrder: 2, status: 'waiting', departmentId: 15 },
      ]);

      const result = await service.getSteps(BigInt(1));

      expect(result).toHaveLength(2);
      expect(mockPrisma.productionStep.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { trailerId: BigInt(1) },
          orderBy: { stepOrder: 'asc' },
        }),
      );
    });

    it('should throw AppError for non-existent trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(service.getSteps(BigInt(999))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });

  // =========================================================================
  // getHistory
  // =========================================================================
  describe('getHistory', () => {
    it('should return steps, QC inspections, and audit logs', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.$transaction.mockResolvedValue([
        [{ id: BigInt(100), stepOrder: 1 }], // steps
        [{ id: BigInt(200), result: 'pass' }], // qcInspections
        [{ id: BigInt(400), deliveryType: 'factory_pickup' }], // deliveries
        [{ id: BigInt(300), action: 'create' }], // auditLogs
      ]);

      const result = await service.getHistory(BigInt(1));

      expect(result.steps).toHaveLength(1);
      expect(result.qcInspections).toHaveLength(1);
      expect(result.deliveries).toHaveLength(1);
      expect(result.auditLogs).toHaveLength(1);
    });

    it('should throw AppError for non-existent trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(service.getHistory(BigInt(999))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });
});
