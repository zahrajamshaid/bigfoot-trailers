import { Test, TestingModule } from '@nestjs/testing';
import { DeliveriesController } from './deliveries.controller';
import { DeliveriesService } from './deliveries.service';
import { BatchesService } from './batches.service';

const mockDeliveriesService = {
  findAll: jest.fn(),
  create: jest.fn(),
  findOne: jest.fn(),
  markDeparted: jest.fn(),
  markComplete: jest.fn(),
  markFailed: jest.fn(),
  uploadPhotos: jest.fn(),
  completeFactoryPickup: jest.fn(),
};

const mockBatchesService = {
  findAll: jest.fn(),
  create: jest.fn(),
  update: jest.fn(),
  dispatch: jest.fn(),
};

describe('DeliveriesController', () => {
  let controller: DeliveriesController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [DeliveriesController],
      providers: [
        { provide: DeliveriesService, useValue: mockDeliveriesService },
        { provide: BatchesService, useValue: mockBatchesService },
      ],
    }).compile();

    controller = module.get<DeliveriesController>(DeliveriesController);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  it('findAll delegates to service', async () => {
    mockDeliveriesService.findAll.mockResolvedValue([]);
    await controller.findAll({ status: 'scheduled' as any });
    expect(mockDeliveriesService.findAll).toHaveBeenCalledWith({ status: 'scheduled' });
  });

  it('create delegates to service with BigInt userId', async () => {
    const dto = { trailerId: 1, deliveryType: 'single_pull' as any };
    const requester = {
      sub: 10,
      email: 'tm@test.com',
      role: 'transport_manager',
      departmentId: null,
      iat: 0,
      exp: 0,
    };
    mockDeliveriesService.create.mockResolvedValue({ id: BigInt(100) });

    await controller.create(dto, requester);
    expect(mockDeliveriesService.create).toHaveBeenCalledWith(dto, BigInt(10));
  });

  it('findOne delegates to service with BigInt id', async () => {
    mockDeliveriesService.findOne.mockResolvedValue({ id: BigInt(100) });
    await controller.findOne(100);
    expect(mockDeliveriesService.findOne).toHaveBeenCalledWith(BigInt(100));
  });

  it('markDeparted delegates to service with BigInt id', async () => {
    mockDeliveriesService.markDeparted.mockResolvedValue({ status: 'in_transit' });
    await controller.markDeparted(100);
    expect(mockDeliveriesService.markDeparted).toHaveBeenCalledWith(BigInt(100));
  });

  it('markComplete delegates to service with BigInt id', async () => {
    const dto = { paymentCollected: 5000 };
    mockDeliveriesService.markComplete.mockResolvedValue({ status: 'delivered' });
    await controller.markComplete(100, dto);
    expect(mockDeliveriesService.markComplete).toHaveBeenCalledWith(BigInt(100), dto);
  });

  it('markFailed delegates to service with BigInt id', async () => {
    const dto = { failReason: 'Road closed' };
    mockDeliveriesService.markFailed.mockResolvedValue({ status: 'failed' });
    await controller.markFailed(100, dto);
    expect(mockDeliveriesService.markFailed).toHaveBeenCalledWith(BigInt(100), dto);
  });

  it('uploadPhotos delegates to service', async () => {
    const dto = { storageKeys: ['a.jpg'], photoType: 'proof_of_delivery' as any };
    mockDeliveriesService.uploadPhotos.mockResolvedValue({ photosAdded: 1 });
    await controller.uploadPhotos(100, dto);
    expect(mockDeliveriesService.uploadPhotos).toHaveBeenCalledWith(BigInt(100), dto);
  });

  it('completeFactoryPickup delegates to service', async () => {
    mockDeliveriesService.completeFactoryPickup.mockResolvedValue({
      status: 'delivered',
    });
    const dto = { pickedUpByName: 'Jane Hauler' };
    await controller.completeFactoryPickup(100, dto);
    expect(mockDeliveriesService.completeFactoryPickup).toHaveBeenCalledWith(
      BigInt(100),
      dto,
    );
  });

  it('findBatches delegates to batchesService', async () => {
    mockBatchesService.findAll.mockResolvedValue([]);
    await controller.findBatches();
    expect(mockBatchesService.findAll).toHaveBeenCalled();
  });

  it('createBatch delegates to batchesService with BigInt userId', async () => {
    const dto = { batchNumber: 'B-001', batchType: 'dealer' as any };
    const requester = {
      sub: 10,
      email: 'tm@test.com',
      role: 'transport_manager',
      departmentId: null,
      iat: 0,
      exp: 0,
    };
    mockBatchesService.create.mockResolvedValue({ id: BigInt(1) });
    await controller.createBatch(dto, requester);
    expect(mockBatchesService.create).toHaveBeenCalledWith(dto, BigInt(10));
  });

  it('updateBatch delegates to batchesService', async () => {
    const dto = { addTrailerIds: [5] };
    const requester = {
      sub: 10,
      email: 'tm@test.com',
      role: 'transport_manager',
      departmentId: null,
      iat: 0,
      exp: 0,
    };
    mockBatchesService.update.mockResolvedValue({ id: BigInt(1) });
    await controller.updateBatch(1, dto, requester);
    expect(mockBatchesService.update).toHaveBeenCalledWith(BigInt(1), dto, BigInt(10));
  });

  it('dispatchBatch delegates to batchesService', async () => {
    mockBatchesService.dispatch.mockResolvedValue({ status: 'in_transit' });
    await controller.dispatchBatch(1);
    expect(mockBatchesService.dispatch).toHaveBeenCalledWith(BigInt(1));
  });
});
