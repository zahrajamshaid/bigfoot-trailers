import { Test, TestingModule } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
import { DeliveriesService } from './deliveries.service';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { StorageService } from '../storage/storage.service';
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

mockPrisma.$transaction.mockImplementation((fn: (tx: any) => Promise<any>) =>
  fn(mockPrisma),
);

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
        { provide: StorageService, useValue: { deleteObjects: jest.fn() } },
      ],
    }).compile();

    service = module.get<DeliveriesService>(DeliveriesService);
    jest.clearAllMocks();
    mockPrisma.$transaction.mockImplementation((fn: (tx: any) => Promise<any>) =>
      fn(mockPrisma),
    );
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
      await service.findAll({
        status: 'scheduled' as any,
        deliveryType: 'single_pull' as any,
        driverUserId: 5,
      });
      expect(mockPrisma.delivery.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {
            status: 'scheduled',
            deliveryType: 'single_pull',
            driverUserId: BigInt(5),
          },
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

      const result = await service.create(
        {
          trailerId: 1,
          deliveryType: 'single_pull' as any,
          driverUserId: 5,
        },
        BigInt(10),
      );

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
      ).rejects.toMatchObject({ errorCode: ErrorCode.DELIVERY_NOT_DISPATCHABLE });
    });

    it('should throw AppError if trailer not found', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(null);

      await expect(
        service.create(
          { trailerId: 999, deliveryType: 'single_pull' as any },
          BigInt(10),
        ),
      ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
    });

    it('should create factory_pickup delivery type', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailerReady);
      mockPrisma.delivery.create.mockResolvedValue({ id: BigInt(100) });

      await service.create(
        { trailerId: 1, deliveryType: 'factory_pickup' as any },
        BigInt(10),
      );
      expect(mockPrisma.delivery.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({ deliveryType: 'factory_pickup' }),
        }),
      );
    });

    it('should persist scheduledDate on a single_pull delivery', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailerReady);
      mockPrisma.delivery.create.mockResolvedValue({ id: BigInt(100) });

      await service.create(
        {
          trailerId: 1,
          deliveryType: 'single_pull' as any,
          scheduledDate: '2026-07-15',
        },
        BigInt(10),
      );

      const callArgs = mockPrisma.delivery.create.mock.calls[0][0];
      const persisted: Date = callArgs.data.scheduledDate;
      expect(persisted).toBeInstanceOf(Date);
      // ISO YYYY-MM-DD parses as UTC midnight; format back the UTC date
      // portion to assert what the DATE column will store.
      expect(persisted.toISOString().slice(0, 10)).toBe('2026-07-15');
    });

    it('should pass scheduledDate=null when DTO omits it', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailerReady);
      mockPrisma.delivery.create.mockResolvedValue({ id: BigInt(100) });

      await service.create(
        { trailerId: 1, deliveryType: 'single_pull' as any },
        BigInt(10),
      );

      const callArgs = mockPrisma.delivery.create.mock.calls[0][0];
      expect(callArgs.data.scheduledDate).toBeNull();
    });

    it('should create stack_to_dealer delivery type', async () => {
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailerReady);
      mockPrisma.delivery.create.mockResolvedValue({ id: BigInt(100) });

      await service.create(
        {
          trailerId: 1,
          deliveryType: 'stack_to_dealer' as any,
          destinationLocationId: 3,
        },
        BigInt(10),
      );

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

    it('should throw AppError', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(null);
      await expect(service.findOne(BigInt(999))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });

  // =========================================================================
  // markDeparted
  // =========================================================================
  describe('markDeparted', () => {
    it('should mark delivery as in_transit and send SMS', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryScheduled);
      mockPrisma.delivery.update.mockResolvedValue({
        ...mockDeliveryScheduled,
        status: 'in_transit',
      });
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
      await expect(service.markDeparted(BigInt(101))).rejects.toMatchObject({
        errorCode: ErrorCode.DELIVERY_NOT_DISPATCHABLE,
      });
    });

    it('should throw AppError', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(null);
      await expect(service.markDeparted(BigInt(999))).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
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

    it('should send delivery_complete but NOT payment_not_collected when fully paid', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryInTransit);
      mockPrisma.delivery.update.mockResolvedValue({ status: 'delivered' });
      mockPrisma.trailer.update.mockResolvedValue({});
      mockPrisma.smsLog.create.mockResolvedValue({});
      mockPrisma.user.findMany.mockResolvedValue([{ id: BigInt(20) }]);
      mockPrisma.pushNotification.createMany.mockResolvedValue({ count: 1 });

      await service.markComplete(BigInt(101), {
        paymentCollected: 5000, // full amount
      });

      const types = mockPrisma.pushNotification.createMany.mock.calls.flatMap(
        (call: any[]) => call[0].data.map((n: any) => n.notificationType),
      );
      expect(types).toContain('delivery_complete');
      expect(types).not.toContain('payment_not_collected');
    });

    it('should complete a scheduled single delivery directly (no depart step)', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryScheduled);
      mockPrisma.delivery.update.mockResolvedValue({ status: 'delivered' });
      mockPrisma.trailer.update.mockResolvedValue({});
      mockPrisma.smsLog.create.mockResolvedValue({});
      mockPrisma.user.findMany.mockResolvedValue([]);

      const result = await service.markComplete(BigInt(100), {});

      expect(result.status).toBe('delivered');
      expect(mockPrisma.trailer.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: { status: 'delivered' } }),
      );
    });

    it('should throw if delivery already delivered', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryDelivered);
      await expect(service.markComplete(BigInt(102), {})).rejects.toMatchObject({
        errorCode: ErrorCode.DELIVERY_NOT_DISPATCHABLE,
      });
    });
  });

  // =========================================================================
  // markFailed
  // =========================================================================
  describe('markFailed', () => {
    it('should mark delivery as failed', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryInTransit);
      mockPrisma.delivery.update.mockResolvedValue({
        status: 'failed',
        failReason: 'Road closed',
      });

      const result = await service.markFailed(BigInt(101), { failReason: 'Road closed' });
      expect(result.status).toBe('failed');
    });

    it('should throw if already delivered', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryDelivered);
      await expect(
        service.markFailed(BigInt(102), { failReason: 'test' }),
      ).rejects.toMatchObject({ errorCode: ErrorCode.DELIVERY_NOT_DISPATCHABLE });
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

    it('should throw AppError', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(null);
      await expect(
        service.uploadPhotos(BigInt(999), {
          storageKeys: ['a.jpg'],
          photoType: 'damage' as any,
        }),
      ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
    });
  });

  // =========================================================================
  // completeFactoryPickup
  // =========================================================================
  describe('completeFactoryPickup', () => {
    it('should complete a factory pickup', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockFactoryPickup);
      mockPrisma.delivery.update.mockResolvedValue({
        ...mockFactoryPickup,
        status: 'delivered',
      });
      mockPrisma.trailer.update.mockResolvedValue({});

      const result = await service.completeFactoryPickup(BigInt(103), {});
      expect(result.status).toBe('delivered');
    });

    it('should record picked-up-by name and amount collected', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockFactoryPickup);
      mockPrisma.delivery.update.mockResolvedValue({
        ...mockFactoryPickup,
        status: 'delivered',
      });
      mockPrisma.trailer.update.mockResolvedValue({});

      await service.completeFactoryPickup(BigInt(103), {
        pickedUpByName: 'Jane Hauler',
        paymentCollected: 250,
      });

      const updateArg = mockPrisma.delivery.update.mock.calls[0][0];
      expect(updateArg.data.pickedUpByName).toBe('Jane Hauler');
      expect(Number(updateArg.data.paymentCollected)).toBe(250);
    });

    it('should throw if not a factory_pickup type', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryScheduled);
      await expect(service.completeFactoryPickup(BigInt(100), {})).rejects.toMatchObject({
        errorCode: ErrorCode.DELIVERY_NOT_DISPATCHABLE,
      });
    });

    it('should throw if not scheduled', async () => {
      mockPrisma.delivery.findUnique.mockResolvedValue({
        ...mockFactoryPickup,
        status: 'delivered',
      });
      await expect(service.completeFactoryPickup(BigInt(103), {})).rejects.toMatchObject({
        errorCode: ErrorCode.DELIVERY_NOT_DISPATCHABLE,
      });
    });
  });
});
