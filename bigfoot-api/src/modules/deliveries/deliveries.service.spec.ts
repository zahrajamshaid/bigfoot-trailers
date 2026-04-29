import { Test, TestingModule } from '@nestjs/testing';
import {
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { DeliveriesService } from './deliveries.service';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { Prisma } from '@prisma/client';

// ---------------------------------------------------------------------------
// Mock Prisma
// ---------------------------------------------------------------------------

const mockPrisma: Record<string, any> = {
  delivery: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  },
  trailer: {
    findUnique: jest.fn(),
    update: jest.fn(),
  },
  smsLog: {
    create: jest.fn(),
  },
  deliveryPhoto: {
    createMany: jest.fn(),
  },
  pushNotification: {
    createMany: jest.fn(),
  },
  user: {
    findMany: jest.fn(),
  },
  $transaction: jest.fn(),
};

mockPrisma.$transaction.mockImplementation((fn: (tx: any) => Promise<any>) => fn(mockPrisma));

const mockNotificationsService = {
  onDeliveryDispatched: jest.fn(),
  onDeliveryComplete: jest.fn().mockResolvedValue(undefined),
};

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const mockTrailerReady = { id: BigInt(1), status: 'ready_for_delivery' };
const mockTrailerInProd = { id: BigInt(2), status: 'in_production' };

const mockDeliveryScheduled = {
  id: BigInt(100),
  status: 'scheduled',
  trailerId: BigInt(1),
  deliveryType: 'single_pull',
  balanceDue: new Prisma.Decimal(5000),
  trailer: {
    id: BigInt(1),
    soNumber: 'SO-1001',
    customer: { smsPhone: '+1234567890', smsOptOut: false },
  },
};

const mockDeliveryInTransit = {
  ...mockDeliveryScheduled,
  id: BigInt(101),
  status: 'in_transit',
};

const mockDeliveryDelivered = {
  ...mockDeliveryScheduled,
  id: BigInt(102),
  status: 'delivered',
};

const mockFactoryPickup = {
  id: BigInt(103),
  status: 'scheduled',
  deliveryType: 'factory_pickup',
  trailerId: BigInt(1),
};

describe('DeliveriesService', () => {
  let service: DeliveriesService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        DeliveriesService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: NotificationsService, useValue: mockNotificationsService },
      ],
    }).compile();

    service = module.get<DeliveriesService>(DeliveriesService);
    jest.clearAllMocks();
    mockPrisma.$transaction.mockImplementation((fn: (tx: any) => Promise<any>) => fn(mockPrisma));
  });

  // =========================================================================
  // findAll
  // =========================================================================
  describe('findAll', () => {
    it('should return deliveries with no filters', async () => {
      mockPrisma.delivery.findMany.mockResolvedValue([]);
      const result = await service.findAll({});
      expect(result).toEqual([]);
      expect(mockPrisma.delivery.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: {} }),
      );
    });

    it('should apply status, type, and driver filters', async () => {
      mockPrisma.delivery.findMany.mockResolvedValue([]);
      await service.findAll({ status: 'scheduled' as any, deliveryType: 'single_pull' as any, driverUserId: 5 });
      expect(mockPrisma.delivery.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { status: 'scheduled', deliveryType: 'single_pull', driverUserId: BigInt(5) },
        }),
      );
    });

    it('should apply date range filter', async () => {
      mockPrisma.delivery.findMany.mockResolvedValue([]);
      await service.findAll({ dateFrom: '2026-03-01', dateTo: '2026-03-31' });
      const call = mockPrisma.delivery.findMany.mock.calls[0][0];
      expect(call.where.createdAt.gte).toEqual(new Date('2026-03-01'));
      expect(call.where.createdAt.lt).toBeDefined();
    });
  });

  // =========================================================================
  // create
  // =========================================================================
  describe('create', () => {
    it('should create a single_pull delivery for a ready trailer', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailerReady);
      mockPrisma.delivery.create.mockResolvedValue({ id: BigInt(100) });

      const result = await service.create({
        trailerId: 1,
        deliveryType: 'single_pull' as any,
        driverUserId: 5,
      }, BigInt(10));

      expect(result.id).toBe(BigInt(100));
      expect(mockPrisma.delivery.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            trailerId: BigInt(1),
            deliveryType: 'single_pull',
            status: 'scheduled',
          }),
        }),
      );
    });

    it('should throw DELIVERY_NOT_DISPATCHABLE if trailer not ready_for_delivery', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailerInProd);

      await expect(
        service.create({ trailerId: 2, deliveryType: 'single_pull' as any }, BigInt(10)),
      ).rejects.toThrow('ready_for_delivery');
    });

    it('should throw NotFoundException if trailer not found', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(
        service.create({ trailerId: 999, deliveryType: 'single_pull' as any }, BigInt(10)),
      ).rejects.toThrow(NotFoundException);
    });

    it('should create factory_pickup delivery type', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailerReady);
      mockPrisma.delivery.create.mockResolvedValue({ id: BigInt(100) });

      await service.create({ trailerId: 1, deliveryType: 'factory_pickup' as any }, BigInt(10));
      expect(mockPrisma.delivery.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ deliveryType: 'factory_pickup' }),
        }),
      );
    });

    it('should create stack_to_dealer delivery type', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailerReady);
      mockPrisma.delivery.create.mockResolvedValue({ id: BigInt(100) });

      await service.create({
        trailerId: 1,
        deliveryType: 'stack_to_dealer' as any,
        destinationLocationId: 3,
      }, BigInt(10));

      expect(mockPrisma.delivery.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ deliveryType: 'stack_to_dealer' }),
        }),
      );
    });
  });

  // =========================================================================
  // findOne
  // =========================================================================
  describe('findOne', () => {
    it('should return delivery detail', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue({ id: BigInt(100) });
      const result = await service.findOne(BigInt(100));
      expect(result.id).toBe(BigInt(100));
    });

    it('should throw NotFoundException', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(null);
      await expect(service.findOne(BigInt(999))).rejects.toThrow(NotFoundException);
    });
  });

  // =========================================================================
  // markDeparted
  // =========================================================================
  describe('markDeparted', () => {
    it('should mark delivery as in_transit and send SMS', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryScheduled);
      mockPrisma.delivery.update.mockResolvedValue({ ...mockDeliveryScheduled, status: 'in_transit' });
      mockPrisma.trailer.update.mockResolvedValue({});
      mockPrisma.smsLog.create.mockResolvedValue({});

      const result = await service.markDeparted(BigInt(100));

      expect(result.status).toBe('in_transit');
      expect(mockPrisma.trailer.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: { status: 'in_transit' },
        }),
      );
      expect(mockPrisma.smsLog.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            smsType: 'driver_en_route',
          }),
        }),
      );
    });

    it('should not send SMS if customer opted out', async () => {
      const noSmsDelivery = {
        ...mockDeliveryScheduled,
        trailer: {
          ...mockDeliveryScheduled.trailer,
          customer: { smsPhone: '+1234', smsOptOut: true },
        },
      };
      mockPrisma.delivery.findUnique.mockResolvedValue(noSmsDelivery);
      mockPrisma.delivery.update.mockResolvedValue({ status: 'in_transit' });
      mockPrisma.trailer.update.mockResolvedValue({});

      await service.markDeparted(BigInt(100));
      expect(mockPrisma.smsLog.create).not.toHaveBeenCalled();
    });

    it('should throw if delivery not scheduled', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryInTransit);
      await expect(service.markDeparted(BigInt(101))).rejects.toThrow(BadRequestException);
    });

    it('should throw NotFoundException', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(null);
      await expect(service.markDeparted(BigInt(999))).rejects.toThrow(NotFoundException);
    });
  });

  // =========================================================================
  // markComplete
  // =========================================================================
  describe('markComplete', () => {
    it('should complete delivery with payment and photos', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryInTransit);
      mockPrisma.delivery.update.mockResolvedValue({ status: 'delivered' });
      mockPrisma.deliveryPhoto.createMany.mockResolvedValue({ count: 2 });
      mockPrisma.trailer.update.mockResolvedValue({});
      mockPrisma.smsLog.create.mockResolvedValue({});
      mockPrisma.user.findMany.mockResolvedValue([]); // no transport managers

      const result = await service.markComplete(BigInt(101), {
        paymentCollected: 5000,
        paymentMethod: 'cash' as any,
        photoStorageKeys: ['photo1.jpg', 'photo2.jpg'],
      });

      expect(result.status).toBe('delivered');
      expect(mockPrisma.deliveryPhoto.createMany).toHaveBeenCalled();
      expect(mockPrisma.trailer.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { status: 'delivered' } }),
      );
    });

    it('should send payment_not_collected push if balance not fully paid', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryInTransit);
      mockPrisma.delivery.update.mockResolvedValue({ status: 'delivered' });
      mockPrisma.trailer.update.mockResolvedValue({});
      mockPrisma.smsLog.create.mockResolvedValue({});
      mockPrisma.user.findMany.mockResolvedValue([{ id: BigInt(20) }]);
      mockPrisma.pushNotification.createMany.mockResolvedValue({ count: 1 });

      await service.markComplete(BigInt(101), {
        paymentCollected: 1000, // less than 5000 balance
      });

      expect(mockPrisma.pushNotification.createMany).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.arrayContaining([
            expect.objectContaining({
              notificationType: 'payment_not_collected',
            }),
          ]),
        }),
      );
    });

    it('should NOT send payment_not_collected when fully paid', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryInTransit);
      mockPrisma.delivery.update.mockResolvedValue({ status: 'delivered' });
      mockPrisma.trailer.update.mockResolvedValue({});
      mockPrisma.smsLog.create.mockResolvedValue({});
      mockPrisma.user.findMany.mockResolvedValue([{ id: BigInt(20) }]);

      await service.markComplete(BigInt(101), {
        paymentCollected: 5000, // full amount
      });

      expect(mockPrisma.pushNotification.createMany).not.toHaveBeenCalled();
    });

    it('should throw if delivery not in_transit', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryScheduled);
      await expect(service.markComplete(BigInt(100), {})).rejects.toThrow(BadRequestException);
    });
  });

  // =========================================================================
  // markFailed
  // =========================================================================
  describe('markFailed', () => {
    it('should mark delivery as failed', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryInTransit);
      mockPrisma.delivery.update.mockResolvedValue({ status: 'failed', failReason: 'Road closed' });

      const result = await service.markFailed(BigInt(101), { failReason: 'Road closed' });
      expect(result.status).toBe('failed');
    });

    it('should throw if already delivered', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryDelivered);
      await expect(
        service.markFailed(BigInt(102), { failReason: 'test' }),
      ).rejects.toThrow(BadRequestException);
    });
  });

  // =========================================================================
  // uploadPhotos
  // =========================================================================
  describe('uploadPhotos', () => {
    it('should upload photos to a delivery', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue({ id: BigInt(100) });
      mockPrisma.deliveryPhoto.createMany.mockResolvedValue({ count: 2 });

      const result = await service.uploadPhotos(BigInt(100), {
        storageKeys: ['a.jpg', 'b.jpg'],
        photoType: 'proof_of_delivery' as any,
      });

      expect(result.photosAdded).toBe(2);
    });

    it('should throw NotFoundException', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(null);
      await expect(
        service.uploadPhotos(BigInt(999), { storageKeys: ['a.jpg'], photoType: 'damage' as any }),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // =========================================================================
  // completeFactoryPickup
  // =========================================================================
  describe('completeFactoryPickup', () => {
    it('should complete a factory pickup', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockFactoryPickup);
      mockPrisma.delivery.update.mockResolvedValue({ ...mockFactoryPickup, status: 'delivered' });
      mockPrisma.trailer.update.mockResolvedValue({});

      const result = await service.completeFactoryPickup(BigInt(103));
      expect(result.status).toBe('delivered');
    });

    it('should throw if not a factory_pickup type', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryScheduled);
      await expect(service.completeFactoryPickup(BigInt(100))).rejects.toThrow('factory_pickup');
    });

    it('should throw if not scheduled', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue({ ...mockFactoryPickup, status: 'delivered' });
      await expect(service.completeFactoryPickup(BigInt(103))).rejects.toThrow(BadRequestException);
    });
  });
});
