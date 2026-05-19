import { Test, TestingModule } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
import { LocationReceiptsService } from './location-receipts.service';
import { PrismaService } from '../../prisma/prisma.service';

const mockPrisma = {
  user: {
    findUnique: jest.fn(),
  },
  delivery: {
    findUnique: jest.fn(),
  },
  locationReceipt: {
    create: jest.fn(),
  },
};

const mockDeliveryWithLocation = {
  id: BigInt(100),
  trailerId: BigInt(1),
  destinationLocationId: 3,
  destinationLocation: { id: 3, name: 'Dallas Lot' },
};

describe('LocationReceiptsService', () => {
  let service: LocationReceiptsService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        LocationReceiptsService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<LocationReceiptsService>(LocationReceiptsService);
    jest.clearAllMocks();
  });

  it('should create a location receipt when location matches', async () => {
    mockPrisma.user.findUnique.mockResolvedValue({ primaryLocationId: 3 });
    mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryWithLocation);
    mockPrisma.locationReceipt.create.mockResolvedValue({
      id: BigInt(1),
      deliveryId: BigInt(100),
      trailerId: BigInt(1),
    });

    const result = await service.create(
      { deliveryId: 100, trailerId: 1, notes: 'Good condition' },
      BigInt(10),
    );

    expect(result.id).toBe(BigInt(1));
    expect(mockPrisma.locationReceipt.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          deliveryId: BigInt(100),
          trailerId: BigInt(1),
          locationId: 3,
          notes: 'Good condition',
        }),
      }),
    );
  });

  it('should throw LOCATION_RECEIPT_WRONG_LOCATION if location mismatch', async () => {
    mockPrisma.user.findUnique.mockResolvedValue({ primaryLocationId: 5 }); // User at location 5
    mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryWithLocation); // Destination is 3

    await expect(
      service.create({ deliveryId: 100, trailerId: 1 }, BigInt(10)),
    ).rejects.toMatchObject({ errorCode: ErrorCode.LOCATION_RECEIPT_WRONG_LOCATION });
  });

  it('should throw LOCATION_RECEIPT_WRONG_LOCATION if user has no location', async () => {
    mockPrisma.user.findUnique.mockResolvedValue({ primaryLocationId: null });
    mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryWithLocation);

    await expect(
      service.create({ deliveryId: 100, trailerId: 1 }, BigInt(10)),
    ).rejects.toMatchObject({ errorCode: ErrorCode.LOCATION_RECEIPT_WRONG_LOCATION });
  });

  it('should throw NotFoundException if delivery not found', async () => {
    mockPrisma.user.findUnique.mockResolvedValue({ primaryLocationId: 3 });
    mockPrisma.delivery.findUnique.mockResolvedValue(null);

    await expect(
      service.create({ deliveryId: 999, trailerId: 1 }, BigInt(10)),
    ).rejects.toMatchObject({ errorCode: ErrorCode.NOT_FOUND });
  });

  it('should throw if trailer does not match delivery', async () => {
    mockPrisma.user.findUnique.mockResolvedValue({ primaryLocationId: 3 });
    mockPrisma.delivery.findUnique.mockResolvedValue(mockDeliveryWithLocation);

    await expect(
      service.create({ deliveryId: 100, trailerId: 999 }, BigInt(10)), // wrong trailer
    ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
  });

  it('should throw if delivery has no destination location', async () => {
    mockPrisma.user.findUnique.mockResolvedValue({ primaryLocationId: 3 });
    mockPrisma.delivery.findUnique.mockResolvedValue({
      ...mockDeliveryWithLocation,
      destinationLocationId: null,
      destinationLocation: null,
    });

    await expect(
      service.create({ deliveryId: 100, trailerId: 1 }, BigInt(10)),
    ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
  });
});
