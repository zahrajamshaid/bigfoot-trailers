import { Test, TestingModule } from '@nestjs/testing';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { AuditLogService } from './audit-log.service';
import { ProductionReportService } from './production-report.service';

describe('AdminController', () => {
  let controller: AdminController;

  const mockAdminService = {
    getWorkflowTemplates: jest.fn(),
    getDepartments: jest.fn(),
    updateDepartment: jest.fn(),
    getWeeklyProductionReport: jest.fn(),
    lockAndSendWeeklyReport: jest.fn(),
  };

  const mockAuditLogService = {
    findAll: jest.fn(),
    findByEntity: jest.fn(),
  };

  const mockProductionReportService = {
    getCostMatrix: jest.fn(),
    upsertStageCost: jest.fn(),
    getWeeklyReport: jest.fn(),
  };

  const mockUser = {
    sub: 1,
    email: 'admin@test.com',
    role: 'owner',
    departmentId: null,
    extraDepartmentIds: [],
    iat: 0,
    exp: 0,
  };
  const mockReq = { ip: '127.0.0.1' } as any;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [AdminController],
      providers: [
        { provide: AdminService, useValue: mockAdminService },
        { provide: AuditLogService, useValue: mockAuditLogService },
        {
          provide: ProductionReportService,
          useValue: mockProductionReportService,
        },
      ],
    }).compile();

    controller = module.get<AdminController>(AdminController);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  describe('getWorkflowTemplates', () => {
    it('should delegate to adminService.getWorkflowTemplates', async () => {
      const mockTemplates = [{ id: 1, series: 'xp', step_order: 1 }];
      mockAdminService.getWorkflowTemplates.mockResolvedValue(mockTemplates);

      const result = await controller.getWorkflowTemplates();
      expect(result).toEqual(mockTemplates);
    });
  });

  describe('getDepartments', () => {
    it('should delegate to adminService.getDepartments', async () => {
      const mockDepts = [{ id: 1, code: 'XP_JIG' }];
      mockAdminService.getDepartments.mockResolvedValue(mockDepts);

      const result = await controller.getDepartments();
      expect(result).toEqual(mockDepts);
    });
  });

  describe('updateDepartment', () => {
    it('should delegate to adminService.updateDepartment', async () => {
      const mockResult = { id: 1, stallThresholdHours: 72 };
      mockAdminService.updateDepartment.mockResolvedValue(mockResult);

      const result = await controller.updateDepartment(
        1,
        { stallThresholdHours: 72 },
        mockUser,
        mockReq,
      );

      expect(mockAdminService.updateDepartment).toHaveBeenCalledWith(
        1,
        72,
        1,
        '127.0.0.1',
      );
      expect(result).toEqual(mockResult);
    });
  });

  describe('queryAuditLog', () => {
    it('should delegate to auditLogService.findAll', async () => {
      const mockResult = { items: [], total: 0, page: 1, limit: 50, totalPages: 0 };
      mockAuditLogService.findAll.mockResolvedValue(mockResult);

      const result = await controller.queryAuditLog({ entityType: 'trailer' });
      expect(mockAuditLogService.findAll).toHaveBeenCalledWith({ entityType: 'trailer' });
      expect(result).toEqual(mockResult);
    });
  });

  describe('getEntityAuditLog', () => {
    it('should delegate to auditLogService.findByEntity', async () => {
      const mockHistory = [{ id: 1n, action: 'CREATE' }];
      mockAuditLogService.findByEntity.mockResolvedValue(mockHistory);

      const result = await controller.getEntityAuditLog('trailer', 100);
      expect(mockAuditLogService.findByEntity).toHaveBeenCalledWith('trailer', 100, {
        page: undefined,
        limit: undefined,
      });
      expect(result).toEqual(mockHistory);
    });
  });

  describe('getWeeklyProductionReport', () => {
    it('should delegate to adminService.getWeeklyProductionReport', async () => {
      const mockReport = { weekStart: '2026-03-22', totalStepsCompleted: 10 };
      mockAdminService.getWeeklyProductionReport.mockResolvedValue(mockReport);

      const result = await controller.getWeeklyProductionReport({
        weekStart: '2026-03-22',
      });
      expect(result).toEqual(mockReport);
    });
  });

  describe('sendWeeklyProductionReport', () => {
    it('should delegate to adminService.lockAndSendWeeklyReport', async () => {
      const mockResult = { weekStart: '2026-03-22', recordsLocked: 5 };
      mockAdminService.lockAndSendWeeklyReport.mockResolvedValue(mockResult);

      const result = await controller.sendWeeklyProductionReport(
        { weekStart: '2026-03-22' },
        mockUser,
        mockReq,
      );

      expect(mockAdminService.lockAndSendWeeklyReport).toHaveBeenCalledWith(
        '2026-03-22',
        1,
        '127.0.0.1',
      );
      expect(result).toEqual(mockResult);
    });
  });
});
