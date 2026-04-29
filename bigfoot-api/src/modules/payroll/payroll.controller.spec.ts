import { Test, TestingModule } from '@nestjs/testing';
import { PayrollController } from './payroll.controller';
import { PayrollService } from './payroll.service';

const mockPayrollService = {
  findPointValues: jest.fn(),
  createPointValue: jest.fn(),
  updatePointValue: jest.fn(),
  findDollarRates: jest.fn(),
  createDollarRate: jest.fn(),
  findPayrollRecords: jest.fn(),
  findWeeklyReport: jest.fn(),
  lockWeek: jest.fn(),
  getWorkerSummary: jest.fn(),
};

describe('PayrollController', () => {
  let controller: PayrollController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [PayrollController],
      providers: [{ provide: PayrollService, useValue: mockPayrollService }],
    }).compile();

    controller = module.get<PayrollController>(PayrollController);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  it('findPointValues delegates to service', async () => {
    const query = { trailerModelId: 1 };
    mockPayrollService.findPointValues.mockResolvedValue([]);

    await controller.findPointValues(query);

    expect(mockPayrollService.findPointValues).toHaveBeenCalledWith(query);
  });

  it('createPointValue delegates to service', async () => {
    const dto = { trailerModelId: 1, departmentId: 1, points: 3.5, effectiveFrom: '2026-01-01' };
    mockPayrollService.createPointValue.mockResolvedValue({ id: 1, ...dto });

    await controller.createPointValue(dto);

    expect(mockPayrollService.createPointValue).toHaveBeenCalledWith(dto);
  });

  it('updatePointValue delegates to service', async () => {
    const dto = { points: 4.0 };
    mockPayrollService.updatePointValue.mockResolvedValue({ id: 1, ...dto });

    await controller.updatePointValue(1, dto);

    expect(mockPayrollService.updatePointValue).toHaveBeenCalledWith(1, dto);
  });

  it('findDollarRates delegates to service', async () => {
    const query = { departmentId: 1 };
    mockPayrollService.findDollarRates.mockResolvedValue([]);

    await controller.findDollarRates(query);

    expect(mockPayrollService.findDollarRates).toHaveBeenCalledWith(query);
  });

  it('createDollarRate delegates to service', async () => {
    const dto = { departmentId: 1, dollarPerPoint: 12.5, effectiveFrom: '2026-01-01' };
    mockPayrollService.createDollarRate.mockResolvedValue({ id: 1, ...dto });

    await controller.createDollarRate(dto);

    expect(mockPayrollService.createDollarRate).toHaveBeenCalledWith(dto);
  });

  it('findPayrollRecords delegates to service', async () => {
    const query = { userId: 10 };
    mockPayrollService.findPayrollRecords.mockResolvedValue([]);

    await controller.findPayrollRecords(query);

    expect(mockPayrollService.findPayrollRecords).toHaveBeenCalledWith(query);
  });

  it('findWeeklyReport delegates to service', async () => {
    mockPayrollService.findWeeklyReport.mockResolvedValue({ weekStartDate: '2026-03-22' });

    await controller.findWeeklyReport('2026-03-22');

    expect(mockPayrollService.findWeeklyReport).toHaveBeenCalledWith('2026-03-22');
  });

  it('lockWeek delegates to service with BigInt userId', async () => {
    const requester = { sub: 1, email: 'owner@test.com', role: 'owner', departmentId: null, iat: 0, exp: 0 };
    mockPayrollService.lockWeek.mockResolvedValue({ isLocked: true });

    await controller.lockWeek('2026-03-22', requester);

    expect(mockPayrollService.lockWeek).toHaveBeenCalledWith('2026-03-22', BigInt(1));
  });

  it('getWorkerSummary delegates to service with BigInt userId', async () => {
    mockPayrollService.getWorkerSummary.mockResolvedValue({ userId: BigInt(10) });

    await controller.getWorkerSummary(10);

    expect(mockPayrollService.getWorkerSummary).toHaveBeenCalledWith(BigInt(10));
  });
});
