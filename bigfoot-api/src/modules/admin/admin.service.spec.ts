import { Test, TestingModule } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
import { AdminService } from './admin.service';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditLogService } from './audit-log.service';
import { Prisma } from '@prisma/client';

describe('AdminService', () => {
  let service: AdminService;

  const mockPrisma = {
    workflowTemplate: { findMany: jest.fn() },
    department: { findMany: jest.fn(), findUnique: jest.fn(), update: jest.fn() },
    productionStep: { findMany: jest.fn() },
    payrollRecord: { findFirst: jest.fn(), updateMany: jest.fn() },
  };

  const mockAuditLogService = {
    create: jest.fn().mockResolvedValue(undefined),
  };

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AdminService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: AuditLogService, useValue: mockAuditLogService },
      ],
    }).compile();

    service = module.get<AdminService>(AdminService);
    jest.clearAllMocks();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ===========================================================================
  // getWorkflowTemplates
  // ===========================================================================
  describe('getWorkflowTemplates', () => {
    it('should return formatted workflow templates', async () => {
      mockPrisma.workflowTemplate.findMany.mockResolvedValue([
        {
          id: 1,
          series: 'xp',
          departmentId: 1,
          stepOrder: 1,
          department: { code: 'XP_JIG', displayName: 'XP Jig Weld', isQcStep: false },
        },
        {
          id: 2,
          series: 'xp',
          departmentId: 2,
          stepOrder: 2,
          department: { code: 'QC_1', displayName: 'Quality Control 1', isQcStep: true },
        },
      ]);

      const result = await service.getWorkflowTemplates();

      expect(result).toEqual([
        {
          id: 1,
          series: 'xp',
          department_id: 1,
          department_code: 'XP_JIG',
          department_name: 'XP Jig Weld',
          step_order: 1,
          is_qc_step: false,
        },
        {
          id: 2,
          series: 'xp',
          department_id: 2,
          department_code: 'QC_1',
          department_name: 'Quality Control 1',
          step_order: 2,
          is_qc_step: true,
        },
      ]);
    });
  });

  // ===========================================================================
  // getDepartments
  // ===========================================================================
  describe('getDepartments', () => {
    it('should return all departments', async () => {
      const mockDepts = [
        { id: 1, code: 'XP_JIG', displayName: 'XP Jig Weld', isQcStep: false },
      ];
      mockPrisma.department.findMany.mockResolvedValue(mockDepts);

      const result = await service.getDepartments();
      expect(result).toEqual(mockDepts);
    });
  });

  // ===========================================================================
  // updateDepartment
  // ===========================================================================
  describe('updateDepartment', () => {
    it('should update stall threshold and create audit log', async () => {
      mockPrisma.department.findUnique.mockResolvedValue({
        id: 1,
        stallThresholdHours: 48,
      });
      mockPrisma.department.update.mockResolvedValue({
        id: 1,
        code: 'XP_JIG',
        displayName: 'XP Jig Weld',
        isQcStep: false,
        completionType: 'one_tap',
        stallThresholdHours: 72,
        createdAt: new Date(),
      });

      const result = await service.updateDepartment(1, 72, 10, '192.168.1.1');

      expect(result.stallThresholdHours).toBe(72);
      expect(mockPrisma.department.update).toHaveBeenCalledWith({
        where: { id: 1 },
        data: { stallThresholdHours: 72 },
        select: expect.any(Object),
      });
      expect(mockAuditLogService.create).toHaveBeenCalledWith(
        expect.objectContaining({
          entityType: 'department',
          entityId: 1,
          action: 'UPDATE',
          oldValues: { stallThresholdHours: 48 },
          newValues: { stallThresholdHours: 72 },
        }),
      );
    });

    it('should throw AppError if department does not exist', async () => {
      mockPrisma.department.findUnique.mockResolvedValue(null);

      await expect(service.updateDepartment(999, 72)).rejects.toMatchObject({
        errorCode: ErrorCode.NOT_FOUND,
      });
    });
  });

  // ===========================================================================
  // getWeeklyProductionReport
  // ===========================================================================
  describe('getWeeklyProductionReport', () => {
    it('should throw INVALID_WEEK_START if date is not a Sunday', async () => {
      // 2026-03-25 is a Wednesday
      await expect(service.getWeeklyProductionReport('2026-03-25')).rejects.toMatchObject(
        { errorCode: ErrorCode.INVALID_WEEK_START },
      );
    });

    it('should return weekly production report for a valid Sunday', async () => {
      // 2026-03-22 is a Sunday
      mockPrisma.productionStep.findMany.mockResolvedValue([
        {
          id: 1n,
          trailerId: 100n,
          departmentId: 1,
          pointsAwarded: new Prisma.Decimal('5.00'),
          completedAt: new Date('2026-03-23'),
          completedByUserId: 10n,
          trailer: {
            soNumber: 'SO-100',
            trailerModel: { displayName: 'XP Model', series: 'xp' },
          },
          department: { displayName: 'XP Jig Weld', code: 'XP_JIG' },
          completedByUser: { id: 10n, fullName: 'John Doe' },
        },
        {
          id: 2n,
          trailerId: 101n,
          departmentId: 1,
          pointsAwarded: new Prisma.Decimal('3.00'),
          completedAt: new Date('2026-03-24'),
          completedByUserId: 10n,
          trailer: {
            soNumber: 'SO-101',
            trailerModel: { displayName: 'XP Model', series: 'xp' },
          },
          department: { displayName: 'XP Jig Weld', code: 'XP_JIG' },
          completedByUser: { id: 10n, fullName: 'John Doe' },
        },
      ]);

      const result = await service.getWeeklyProductionReport('2026-03-22');

      expect(result.weekStart).toBe('2026-03-22');
      expect(result.totalStepsCompleted).toBe(2);
      expect(result.totalPoints).toBe(8);
      expect(result.steps).toHaveLength(2);
      expect(result.workerSummary).toHaveLength(1);
      expect(result.workerSummary[0].fullName).toBe('John Doe');
      expect(result.workerSummary[0].totalPoints).toBe(8);
      expect(result.workerSummary[0].stepsCompleted).toBe(2);
    });
  });

  // ===========================================================================
  // lockAndSendWeeklyReport
  // ===========================================================================
  describe('lockAndSendWeeklyReport', () => {
    it('should throw INVALID_WEEK_START if not a Sunday', async () => {
      await expect(
        service.lockAndSendWeeklyReport('2026-03-25', 1),
      ).rejects.toMatchObject({ errorCode: ErrorCode.INVALID_WEEK_START });
    });

    it('should throw PAYROLL_WEEK_LOCKED if already locked', async () => {
      mockPrisma.payrollRecord.findFirst.mockResolvedValue({ id: 1n });

      await expect(
        service.lockAndSendWeeklyReport('2026-03-22', 1),
      ).rejects.toMatchObject({ errorCode: ErrorCode.PAYROLL_WEEK_LOCKED });
    });

    it('should lock payroll records and create audit log', async () => {
      mockPrisma.payrollRecord.findFirst.mockResolvedValue(null);
      mockPrisma.payrollRecord.updateMany.mockResolvedValue({ count: 5 });

      const result = await service.lockAndSendWeeklyReport('2026-03-22', 1, '10.0.0.1');

      expect(result.weekStart).toBe('2026-03-22');
      expect(result.recordsLocked).toBe(5);
      expect(mockAuditLogService.create).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 1,
          entityType: 'payroll_week',
          action: 'LOCK',
        }),
      );
    });
  });
});
