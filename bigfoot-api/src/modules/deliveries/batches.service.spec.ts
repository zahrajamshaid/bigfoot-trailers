import { Test, TestingModule } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
import { BatchesService } from './batches.service';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';

// ---------------------------------------------------------------------------
// Mock Prisma — $transaction runs the callback with the same mock as `tx`.
// ---------------------------------------------------------------------------

const mockPrisma: Record<string, any> = {
  deliveryBatch: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    findUniqueOrThrow: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  },
  delivery: {
    create: jest.fn(),
    createMany: jest.fn(),
    deleteMany: jest.fn(),
    updateMany: jest.fn(),
  },
  trailer: {
    findMany: jest.fn(),
    updateMany: jest.fn(),
  },
  deliveryPhoto: { createMany: jest.fn() },
  user: { findMany: jest.fn() },
  pushNotification: { createMany: jest.fn() },
  $transaction: jest.fn(),
};

const mockNotificationsService = {
  onDeliveryDispatched: jest.fn(),
  onDeliveryComplete: jest.fn(),
};

describe('BatchesService', () => {
  let service: BatchesService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        BatchesService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: NotificationsService, useValue: mockNotificationsService },
      ],
    }).compile();

    service = module.get<BatchesService>(BatchesService);
    jest.clearAllMocks();
    mockPrisma.$transaction.mockImplementation((fn: (tx: any) => Promise<any>) =>
      fn(mockPrisma),
    );
    // Sensible defaults so methods that fan out don't trip over undefined.
    mockPrisma.user.findMany.mockResolvedValue([]);
  });

  // =========================================================================
  // findAll
  // =========================================================================
  describe('findAll', () => {
    it('should return all batches', async () => {
      mockPrisma.deliveryBatch.findMany.mockResolvedValue([]);
      const result = await service.findAll();
      expect(result).toEqual([]);
    });
  });

  // =========================================================================
  // create
  // =========================================================================
  describe('create', () => {
    it('should create a batch with no trailers', async () => {
      mockPrisma.deliveryBatch.create.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.deliveryBatch.findUniqueOrThrow.mockResolvedValue({
        id: BigInt(1),
        batchNumber: 'B-001',
        status: 'building',
      });

      const result = await service.create(
        { batchNumber: 'B-001', batchType: 'dealer' as any, driverUserId: 5 },
        BigInt(10),
      );

      expect(result.status).toBe('building');
      expect(mockPrisma.deliveryBatch.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            batchNumber: 'B-001',
            batchType: 'dealer',
            status: 'building',
          }),
        }),
      );
      expect(mockPrisma.delivery.createMany).not.toHaveBeenCalled();
    });

    it('should add the selected trailers when trailerIds are given', async () => {
      mockPrisma.deliveryBatch.create.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.trailer.findMany.mockResolvedValue([
        { id: BigInt(7), status: 'ready_for_delivery' },
      ]);
      mockPrisma.delivery.createMany.mockResolvedValue({ count: 1 });
      mockPrisma.deliveryBatch.findUniqueOrThrow.mockResolvedValue({
        id: BigInt(1),
        batchNumber: 'B-002',
        status: 'building',
      });

      await service.create(
        { batchNumber: 'B-002', batchType: 'dealer' as any, trailerIds: [7] },
        BigInt(10),
      );

      expect(mockPrisma.delivery.createMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.arrayContaining([
            expect.objectContaining({
              trailerId: BigInt(7),
              deliveryBatchId: BigInt(1),
              deliveryType: 'stack_to_dealer',
              status: 'scheduled',
            }),
          ]),
        }),
      );
    });

    it('should reject a trailer that is not ready_for_delivery', async () => {
      mockPrisma.deliveryBatch.create.mockResolvedValue({ id: BigInt(1) });
      mockPrisma.trailer.findMany.mockResolvedValue([
        { id: BigInt(7), status: 'in_production' },
      ]);

      await expect(
        service.create(
          { batchNumber: 'B-003', batchType: 'dealer' as any, trailerIds: [7] },
          BigInt(10),
        ),
      ).rejects.toMatchObject({ errorCode: ErrorCode.DELIVERY_NOT_DISPATCHABLE });
    });
  });

  // =========================================================================
  // update
  // =========================================================================
  describe('update', () => {
    it('should add trailers to a building batch', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: 'building',
        batchType: 'dealer',
        destinationLocationId: null,
      });
      mockPrisma.deliveryBatch.findUniqueOrThrow.mockResolvedValue({
        id: BigInt(1),
        status: 'building',
      });
      mockPrisma.trailer.findMany.mockResolvedValue([
        { id: BigInt(5), status: 'ready_for_delivery' },
      ]);
      mockPrisma.delivery.createMany.mockResolvedValue({ count: 1 });

      await service.update(BigInt(1), { addTrailerIds: [5] }, BigInt(10));

      expect(mockPrisma.delivery.createMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.arrayContaining([
            expect.objectContaining({
              trailerId: BigInt(5),
              deliveryBatchId: BigInt(1),
              deliveryType: 'stack_to_dealer',
            }),
          ]),
        }),
      );
    });

    it('should use stack_to_location type for bf_location batches', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: 'building',
        batchType: 'bf_location',
        destinationLocationId: null,
      });
      mockPrisma.deliveryBatch.findUniqueOrThrow.mockResolvedValue({
        id: BigInt(1),
      });
      mockPrisma.trailer.findMany.mockResolvedValue([
        { id: BigInt(5), status: 'ready_for_delivery' },
      ]);
      mockPrisma.delivery.createMany.mockResolvedValue({ count: 1 });

      await service.update(BigInt(1), { addTrailerIds: [5] }, BigInt(10));

      expect(mockPrisma.delivery.createMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.arrayContaining([
            expect.objectContaining({ deliveryType: 'stack_to_location' }),
          ]),
        }),
      );
    });

    it('should throw BATCH_NOT_BUILDING if batch is not in building status', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: 'in_transit',
      });

      await expect(
        service.update(BigInt(1), { addTrailerIds: [5] }, BigInt(10)),
      ).rejects.toMatchObject({ errorCode: ErrorCode.BATCH_NOT_BUILDING });
    });

    it('should throw NotFoundException for unknown batch', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue(null);

      await expect(service.update(BigInt(999), {}, BigInt(10))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });

    it('should throw DELIVERY_NOT_DISPATCHABLE if trailer not ready', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: 'building',
        batchType: 'dealer',
        destinationLocationId: null,
      });
      mockPrisma.trailer.findMany.mockResolvedValue([
        { id: BigInt(5), status: 'in_production' },
      ]);

      await expect(
        service.update(BigInt(1), { addTrailerIds: [5] }, BigInt(10)),
      ).rejects.toMatchObject({ errorCode: ErrorCode.DELIVERY_NOT_DISPATCHABLE });
    });

    it('should remove deliveries from batch', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: 'building',
        batchType: 'dealer',
        destinationLocationId: null,
      });
      mockPrisma.deliveryBatch.findUniqueOrThrow.mockResolvedValue({
        id: BigInt(1),
      });
      mockPrisma.delivery.deleteMany.mockResolvedValue({ count: 1 });

      await service.update(BigInt(1), { removeDeliveryIds: [50] }, BigInt(10));

      expect(mockPrisma.delivery.deleteMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            deliveryBatchId: BigInt(1),
            status: 'scheduled',
          }),
        }),
      );
    });
  });

  // =========================================================================
  // dispatch
  // =========================================================================
  describe('dispatch', () => {
    it('should dispatch a batch with deliveries', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: 'building',
        deliveries: [
          { id: BigInt(50), trailerId: BigInt(5) },
          { id: BigInt(51), trailerId: BigInt(6) },
        ],
      });
      mockPrisma.deliveryBatch.findUniqueOrThrow.mockResolvedValue({
        id: BigInt(1),
        status: 'in_transit',
      });
      mockPrisma.deliveryBatch.update.mockResolvedValue({});
      mockPrisma.delivery.updateMany.mockResolvedValue({ count: 2 });
      mockPrisma.trailer.updateMany.mockResolvedValue({ count: 2 });

      await service.dispatch(BigInt(1));

      expect(mockPrisma.deliveryBatch.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ status: 'in_transit' }),
        }),
      );
      expect(mockPrisma.trailer.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: { in: [BigInt(5), BigInt(6)] } },
          data: { status: 'in_transit' },
        }),
      );
    });

    it('should throw if batch is empty', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: 'building',
        deliveries: [],
      });

      await expect(service.dispatch(BigInt(1))).rejects.toMatchObject({
        errorCode: ErrorCode.BAD_REQUEST,
      });
    });

    it('should throw if batch already complete', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: 'complete',
        deliveries: [{ id: BigInt(50), trailerId: BigInt(5) }],
      });

      await expect(service.dispatch(BigInt(1))).rejects.toMatchObject({
        errorCode: ErrorCode.BAD_REQUEST,
      });
    });

    it('should throw NotFoundException for unknown batch', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue(null);
      await expect(service.dispatch(BigInt(999))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });

  // =========================================================================
  // complete
  // =========================================================================
  describe('complete', () => {
    it('should deliver every open trailer and complete the batch', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        batchNumber: 'B-001',
        status: 'in_transit',
        destinationLocationId: 3,
        deliveries: [
          {
            id: BigInt(50),
            trailerId: BigInt(5),
            status: 'in_transit',
            trailer: { soNumber: 'SO-5' },
          },
        ],
      });
      mockPrisma.deliveryBatch.update.mockResolvedValue({});
      mockPrisma.delivery.updateMany.mockResolvedValue({ count: 1 });
      mockPrisma.trailer.updateMany.mockResolvedValue({ count: 1 });
      mockPrisma.deliveryBatch.findUniqueOrThrow.mockResolvedValue({
        id: BigInt(1),
        status: 'complete',
      });

      const result = await service.complete(BigInt(1), {});

      expect(result.status).toBe('complete');
      expect(mockPrisma.deliveryBatch.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ status: 'complete' }),
        }),
      );
      expect(mockPrisma.delivery.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ status: 'delivered' }),
        }),
      );
      // Destination is a BF location → trailers go back to ready_for_delivery.
      expect(mockPrisma.trailer.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            status: 'ready_for_delivery',
            currentLocationId: 3,
          }),
        }),
      );
      expect(mockNotificationsService.onDeliveryComplete).toHaveBeenCalledTimes(1);
    });

    it('should mark trailers delivered when the batch has no BF location', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        batchNumber: 'B-002',
        status: 'in_transit',
        destinationLocationId: null,
        deliveries: [
          {
            id: BigInt(60),
            trailerId: BigInt(6),
            status: 'in_transit',
            trailer: { soNumber: 'SO-6' },
          },
        ],
      });
      mockPrisma.deliveryBatch.update.mockResolvedValue({});
      mockPrisma.delivery.updateMany.mockResolvedValue({ count: 1 });
      mockPrisma.trailer.updateMany.mockResolvedValue({ count: 1 });
      mockPrisma.deliveryBatch.findUniqueOrThrow.mockResolvedValue({
        id: BigInt(1),
        status: 'complete',
      });

      await service.complete(BigInt(1), {});

      expect(mockPrisma.trailer.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: { status: 'delivered' },
        }),
      );
    });

    it('should throw if the batch is already complete', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        batchNumber: 'B-003',
        status: 'complete',
        destinationLocationId: null,
        deliveries: [],
      });

      await expect(service.complete(BigInt(1), {})).rejects.toMatchObject({
        errorCode: ErrorCode.BAD_REQUEST,
      });
    });

    it('should throw if there are no open deliveries to complete', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        batchNumber: 'B-004',
        status: 'in_transit',
        destinationLocationId: null,
        deliveries: [
          {
            id: BigInt(70),
            trailerId: BigInt(7),
            status: 'delivered',
            trailer: { soNumber: 'SO-7' },
          },
        ],
      });

      await expect(service.complete(BigInt(1), {})).rejects.toMatchObject({
        errorCode: ErrorCode.BAD_REQUEST,
      });
    });

    it('should throw NotFoundException for unknown batch', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue(null);
      await expect(service.complete(BigInt(999), {})).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });
});
