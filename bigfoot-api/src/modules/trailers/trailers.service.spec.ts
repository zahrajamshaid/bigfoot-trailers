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
    findFirst: jest.fn(),
    update: jest.fn(),
  },
  department: {
    findUnique: jest.fn(),
  },
  qcInspection: {
    findMany: jest.fn(),
  },
  delivery: {
    findMany: jest.fn(),
    findFirst: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
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

    it('hides Mulberry-destined stock-builds-without-customer when status=ready_for_delivery', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);
      mockPrisma.trailer.findMany.mockResolvedValue([]);
      mockPrisma.trailer.count.mockResolvedValue(0);

      await service.findAll({ status: 'ready_for_delivery' as any });

      // findMany is called as the first leg of the $transaction; the spec
      // can introspect the where clause directly because the service builds
      // it eagerly and passes both calls to $transaction.
      const findManyCall = mockPrisma.trailer.findMany.mock.calls[0]?.[0];
      // The exclusion fires when ALL conditions are true: stock build with
      // no customer/soldTo, sitting at Mulberry, AND destined for Mulberry
      // (or unset). Stock builds destined for a satellite yard fail the
      // OR sub-clause and stay visible.
      expect(findManyCall.where.NOT).toMatchObject({
        isStockBuild: true,
        customerId: null,
        soldToName: null,
        currentLocation: { code: 'MULBERRY' },
        OR: [
          { intendedStockLocationId: null },
          { intendedStockLocation: { code: 'MULBERRY' } },
        ],
      });
    });

    it('does not apply the Mulberry exclusion on other statuses', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);
      mockPrisma.trailer.findMany.mockResolvedValue([]);
      mockPrisma.trailer.count.mockResolvedValue(0);

      await service.findAll({ status: 'in_production' as any });

      const findManyCall = mockPrisma.trailer.findMany.mock.calls[0]?.[0];
      expect(findManyCall.where.NOT).toBeUndefined();
    });

    it('location filter matches currentLocationId OR intendedStockLocationId', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);
      mockPrisma.trailer.findMany.mockResolvedValue([]);
      mockPrisma.trailer.count.mockResolvedValue(0);

      const JAX_ID = 4;
      await service.findAll({ locationId: JAX_ID });

      const where = mockPrisma.trailer.findMany.mock.calls[0]?.[0]?.where;
      // The OR group lives inside an AND clause so it composes cleanly with
      // the implicit delivered-trailer exclusion + future filters.
      expect(where.AND).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            OR: [
              { currentLocationId: JAX_ID },
              { intendedStockLocationId: JAX_ID },
            ],
          }),
        ]),
      );
      // currentLocationId is no longer set as a top-level scalar — that
      // would AND with the OR group and re-introduce the old behavior.
      expect(where.currentLocationId).toBeUndefined();
    });

    it('hides delivered trailers by default — they belong in Completed Deliveries', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);
      mockPrisma.trailer.findMany.mockResolvedValue([]);
      mockPrisma.trailer.count.mockResolvedValue(0);

      await service.findAll({});

      const where = mockPrisma.trailer.findMany.mock.calls[0]?.[0]?.where;
      expect(where.AND).toEqual(
        expect.arrayContaining([
          { status: { not: 'delivered' } },
        ]),
      );
    });

    it('keeps delivered trailers visible when explicitly filtered for delivered', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);
      mockPrisma.trailer.findMany.mockResolvedValue([]);
      mockPrisma.trailer.count.mockResolvedValue(0);

      await service.findAll({ status: 'delivered' as any });

      const where = mockPrisma.trailer.findMany.mock.calls[0]?.[0]?.where;
      // No AND clause means the default exclusion was skipped.
      expect(where.AND).toBeUndefined();
      expect(where.status).toBe('delivered');
    });

    it('keeps delivered trailers visible for the completedSince dashboard tile', async () => {
      mockPrisma.$transaction.mockResolvedValue([[], 0]);
      mockPrisma.trailer.findMany.mockResolvedValue([]);
      mockPrisma.trailer.count.mockResolvedValue(0);

      await service.findAll({ completedSince: '2026-06-01' });

      const where = mockPrisma.trailer.findMany.mock.calls[0]?.[0]?.where;
      expect(where.AND).toBeUndefined();
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

    it('should allow creating without customerId (stock build) — keeps trailer at factory, records intended destination', async () => {
      const FACTORY_ID = 1;
      const STOCK_DEST_ID = 5; // a satellite yard, e.g. Tappahannock
      const stockDto = {
        soNumber: 'SO-3001',
        trailerModelId: 1,
        isStockBuild: true,
        stockLocationId: STOCK_DEST_ID,
      };

      mockPrisma.trailer.findUnique.mockResolvedValue(null);
      mockPrisma.trailerModel.findUnique.mockResolvedValue({ id: 1, series: 'xp' });
      mockPrisma.location.findFirst.mockResolvedValue({ id: FACTORY_ID });
      mockPrisma.location.findUnique.mockResolvedValue({
        id: STOCK_DEST_ID,
        isActive: true,
      });

      const createSpy = jest.fn().mockResolvedValue({
        ...mockTrailer,
        customerId: null,
        isStockBuild: true,
        intendedStockLocationId: STOCK_DEST_ID,
      });
      mockPrisma.$transaction.mockImplementation(async (fn: any) => {
        const txClient = {
          trailer: { create: createSpy },
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
      // Trailer is born at the factory regardless of stockLocationId — the
      // destination yard goes into intendedStockLocationId so transport can
      // schedule a stack_to_location delivery once production completes.
      expect(createSpy).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            currentLocationId: FACTORY_ID,
            intendedStockLocationId: STOCK_DEST_ID,
            isStockBuild: true,
          }),
        }),
      );
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
  // setWireHydraulic — step-9 override (WIRE <-> HYDRAULICS)
  // =========================================================================
  describe('setWireHydraulic', () => {
    const wireDept = { id: 30, code: 'WIRE' };

    beforeEach(() => {
      mockPrisma.trailer.findUnique.mockResolvedValue({
        id: BigInt(1),
        soNumber: 'SO-1001',
      });
      mockPrisma.department.findUnique.mockResolvedValue(wireDept);
    });

    it('repoints the step-9 department, preserving the step itself', async () => {
      mockPrisma.productionStep.findFirst.mockResolvedValue({
        id: BigInt(90),
        departmentId: 31, // currently HYDRAULICS
        status: 'waiting',
      });

      await service.setWireHydraulic(BigInt(1), 'WIRE' as never);

      // Same step row is updated — status/queue position are untouched.
      expect(mockPrisma.productionStep.update).toHaveBeenCalledWith({
        where: { id: BigInt(90) },
        data: { departmentId: 30 },
      });
    });

    it('is a no-op when it is already on the target department', async () => {
      mockPrisma.productionStep.findFirst.mockResolvedValue({
        id: BigInt(90),
        departmentId: 30, // already WIRE
        status: 'waiting',
      });

      await service.setWireHydraulic(BigInt(1), 'WIRE' as never);

      expect(mockPrisma.productionStep.update).not.toHaveBeenCalled();
    });

    it('refuses once the wire/hydraulics step is complete', async () => {
      mockPrisma.productionStep.findFirst.mockResolvedValue({
        id: BigInt(90),
        departmentId: 31,
        status: 'complete',
      });

      await expect(
        service.setWireHydraulic(BigInt(1), 'WIRE' as never),
      ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
      expect(mockPrisma.productionStep.update).not.toHaveBeenCalled();
    });

    it('rejects a trailer with no wire/hydraulics step (inventory-only)', async () => {
      mockPrisma.productionStep.findFirst.mockResolvedValue(null);

      await expect(
        service.setWireHydraulic(BigInt(1), 'WIRE' as never),
      ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
    });

    it('404s on a missing trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(
        service.setWireHydraulic(BigInt(999), 'WIRE' as never),
      ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
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

  // =========================================================================
  // markCompleted — auto-creates a factory_pickup row when none open
  // =========================================================================
  describe('markCompleted', () => {
    beforeEach(() => {
      mockPrisma.$transaction.mockImplementation(
        (fn: (tx: any) => Promise<any>) => fn(mockPrisma),
      );
    });

    it('completes the open delivery when one exists — no new row created', async () => {
      mockPrisma.trailer.findUnique
        .mockResolvedValueOnce({ id: BigInt(1), status: 'ready_for_delivery' })
        .mockResolvedValueOnce(mockTrailer); // post-update fetch
      mockPrisma.delivery.findFirst.mockResolvedValue({ id: BigInt(500) });
      mockPrisma.delivery.update.mockResolvedValue({});
      mockPrisma.trailer.update.mockResolvedValue({});

      await service.markCompleted(BigInt(1), BigInt(10));

      expect(mockPrisma.delivery.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: BigInt(500) },
          data: expect.objectContaining({ status: 'delivered' }),
        }),
      );
      expect(mockPrisma.delivery.create).not.toHaveBeenCalled();
      expect(mockPrisma.trailer.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { status: 'delivered' } }),
      );
    });

    it('auto-creates a factory_pickup row when no live delivery exists', async () => {
      // Trailer is at a yard with no open delivery — the "Mark Picked Up"
      // click needs to register as a delivery row so the pickup shows in
      // Completed Deliveries alongside the prior inbound leg.
      mockPrisma.trailer.findUnique
        .mockResolvedValueOnce({ id: BigInt(1), status: 'ready_for_delivery' })
        .mockResolvedValueOnce(mockTrailer);
      mockPrisma.delivery.findFirst.mockResolvedValue(null);
      mockPrisma.delivery.create.mockResolvedValue({ id: BigInt(700) });
      mockPrisma.trailer.update.mockResolvedValue({});

      await service.markCompleted(BigInt(1), BigInt(10));

      expect(mockPrisma.delivery.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            trailerId: BigInt(1),
            deliveryType: 'factory_pickup',
            status: 'delivered',
            createdByUserId: BigInt(10),
          }),
        }),
      );
      expect(mockPrisma.delivery.update).not.toHaveBeenCalled();
      expect(mockPrisma.trailer.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { status: 'delivered' } }),
      );
    });

    it('is a no-op for already-delivered trailers', async () => {
      mockPrisma.trailer.findUnique
        .mockResolvedValueOnce({ id: BigInt(1), status: 'delivered' })
        .mockResolvedValueOnce(mockTrailer);

      await service.markCompleted(BigInt(1), BigInt(10));

      expect(mockPrisma.$transaction).not.toHaveBeenCalled();
      expect(mockPrisma.delivery.create).not.toHaveBeenCalled();
      expect(mockPrisma.delivery.update).not.toHaveBeenCalled();
    });
  });
});
