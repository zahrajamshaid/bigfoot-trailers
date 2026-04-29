import { Test, TestingModule } from '@nestjs/testing';
import {
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { BatchesService } from './batches.service';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';

// ---------------------------------------------------------------------------
// Mock Prisma
// ---------------------------------------------------------------------------

const mockPrisma: Record<string, any> = {
  deliveryBatch: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  },
  delivery: {
    create: jest.fn(),
    deleteMany: jest.fn(),
    updateMany: jest.fn(),
  },
  trailer: {
    findUnique: jest.fn(),
    updateMany: jest.fn(),
  },
  $transaction: jest.fn(),
};

mockPrisma.$transaction.mockImplementation((fn: (tx: any) => Promise<any>) => fn(mockPrisma));

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
    mockPrisma.$transaction.mockImplementation((fn: (tx: any) => Promise<any>) => fn(mockPrisma));
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
    it('should create a batch', async () => {
      mockPrisma.deliveryBatch.create.mockResolvedValue({
        id: BigInt(1),
        batchNumber: 'B-001',
        status: 'building',
      });

      const result = await service.create({
        batchNumber: 'B-001',
        batchType: 'dealer' as any,
        driverUserId: 5,
      }, BigInt(10));

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
    });
  });

  // =========================================================================
  // update
  // =========================================================================
  describe('update', () => {
    it('should add trailers to a building batch', async () => {
      mockPrisma.deliveryBatch.findUnique
        .mockResolvedValueOnce({ id: BigInt(1), status: 'building', batchType: 'dealer' })
        .mockResolvedValueOnce({ id: BigInt(1), status: 'building' }); // final select
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(5), status: 'ready_for_delivery' });
      mockPrisma.delivery.create.mockResolvedValue({});

      const result = await service.update(BigInt(1), { addTrailerIds: [5] }, BigInt(10));

      expect(mockPrisma.delivery.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            trailerId: BigInt(5),
            deliveryBatchId: BigInt(1),
            deliveryType: 'stack_to_dealer',
          }),
        }),
      );
    });

    it('should use stack_to_location type for bf_location batches', async () => {
      mockPrisma.deliveryBatch.findUnique
        .mockResolvedValueOnce({ id: BigInt(1), status: 'building', batchType: 'bf_location' })
        .mockResolvedValueOnce({ id: BigInt(1) });
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(5), status: 'ready_for_delivery' });
      mockPrisma.delivery.create.mockResolvedValue({});

      await service.update(BigInt(1), { addTrailerIds: [5] }, BigInt(10));

      expect(mockPrisma.delivery.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            deliveryType: 'stack_to_location',
          }),
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
      ).rejects.toThrow('must be "building"');
    });

    it('should throw NotFoundException for unknown batch', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue(null);

      await expect(
        service.update(BigInt(999), {}, BigInt(10)),
      ).rejects.toThrow(NotFoundException);
    });

    it('should throw DELIVERY_NOT_DISPATCHABLE if trailer not ready', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: 'building',
        batchType: 'dealer',
      });
      mockPrisma.trailer.findUnique.mockResolvedValue({ id: BigInt(5), status: 'in_production' });

      await expect(
        service.update(BigInt(1), { addTrailerIds: [5] }, BigInt(10)),
      ).rejects.toThrow('ready_for_delivery');
    });

    it('should remove deliveries from batch', async () => {
      mockPrisma.deliveryBatch.findUnique
        .mockResolvedValueOnce({ id: BigInt(1), status: 'building', batchType: 'dealer' })
        .mockResolvedValueOnce({ id: BigInt(1) });
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
      mockPrisma.deliveryBatch.findUnique
        .mockResolvedValueOnce({
          id: BigInt(1),
          status: 'building',
          deliveries: [
            { id: BigInt(50), trailerId: BigInt(5) },
            { id: BigInt(51), trailerId: BigInt(6) },
          ],
        })
        .mockResolvedValueOnce({ id: BigInt(1), status: 'in_transit' }); // final select
      mockPrisma.deliveryBatch.update.mockResolvedValue({});
      mockPrisma.delivery.updateMany.mockResolvedValue({ count: 2 });
      mockPrisma.trailer.updateMany.mockResolvedValue({ count: 2 });

      const result = await service.dispatch(BigInt(1));

      expect(mockPrisma.deliveryBatch.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ status: 'in_transit' }),
        }),
      );
      expect(mockPrisma.delivery.updateMany).toHaveBeenCalled();
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

      await expect(service.dispatch(BigInt(1))).rejects.toThrow('empty batch');
    });

    it('should throw if batch already in_transit', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue({
        id: BigInt(1),
        status: 'complete',
        deliveries: [{ id: BigInt(50), trailerId: BigInt(5) }],
      });

      await expect(service.dispatch(BigInt(1))).rejects.toThrow(BadRequestException);
    });

    it('should throw NotFoundException for unknown batch', async () => {
      mockPrisma.deliveryBatch.findUnique.mockResolvedValue(null);
      await expect(service.dispatch(BigInt(999))).rejects.toThrow(NotFoundException);
    });
  });
});
