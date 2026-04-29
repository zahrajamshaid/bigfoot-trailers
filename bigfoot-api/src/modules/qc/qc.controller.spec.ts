import { Test, TestingModule } from '@nestjs/testing';
import { QcController } from './qc.controller';
import { QcService } from './qc.service';

const mockQcService = {
  findChecklistItems: jest.fn(),
  createChecklistItem: jest.fn(),
  updateChecklistItem: jest.fn(),
  submitInspection: jest.fn(),
  findInspection: jest.fn(),
  findInspectionsByStep: jest.fn(),
};

describe('QcController', () => {
  let controller: QcController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [QcController],
      providers: [{ provide: QcService, useValue: mockQcService }],
    }).compile();

    controller = module.get<QcController>(QcController);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  it('findChecklistItems delegates to service', async () => {
    const query = { departmentId: 15 };
    mockQcService.findChecklistItems.mockResolvedValue([]);

    await controller.findChecklistItems(query);

    expect(mockQcService.findChecklistItems).toHaveBeenCalledWith(query);
  });

  it('createChecklistItem delegates to service', async () => {
    const dto = { departmentId: 15, itemLabel: 'Check welds' };
    mockQcService.createChecklistItem.mockResolvedValue({ id: 1, ...dto });

    await controller.createChecklistItem(dto);

    expect(mockQcService.createChecklistItem).toHaveBeenCalledWith(dto);
  });

  it('updateChecklistItem delegates to service', async () => {
    const dto = { itemLabel: 'Updated' };
    mockQcService.updateChecklistItem.mockResolvedValue({ id: 1, ...dto });

    await controller.updateChecklistItem(1, dto);

    expect(mockQcService.updateChecklistItem).toHaveBeenCalledWith(1, dto);
  });

  it('submitInspection delegates to service with BigInt userId', async () => {
    const dto = {
      productionStepId: 200,
      result: 'pass' as any,
      checklistResults: [],
      photoStorageKeys: ['photo.jpg'],
    };
    const requester = { sub: 10, email: 'test@test.com', role: 'qc_inspector', departmentId: null, iat: 0, exp: 0 };
    mockQcService.submitInspection.mockResolvedValue({ inspectionId: BigInt(500) });

    await controller.submitInspection(dto, requester);

    expect(mockQcService.submitInspection).toHaveBeenCalledWith(dto, BigInt(10));
  });

  it('findInspection delegates to service with BigInt id', async () => {
    mockQcService.findInspection.mockResolvedValue({ id: BigInt(500) });

    await controller.findInspection(500);

    expect(mockQcService.findInspection).toHaveBeenCalledWith(BigInt(500));
  });

  it('findInspectionsByStep delegates to service with BigInt stepId', async () => {
    mockQcService.findInspectionsByStep.mockResolvedValue([]);

    await controller.findInspectionsByStep(200);

    expect(mockQcService.findInspectionsByStep).toHaveBeenCalledWith(BigInt(200));
  });
});
