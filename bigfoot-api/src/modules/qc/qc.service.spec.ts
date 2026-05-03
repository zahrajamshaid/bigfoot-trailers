import { Test, TestingModule } from '@nestjs/testing';
import {
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { QcService } from './qc.service';
import { ReworkRoutingService } from './rework-routing.service';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { QcResultDto } from './dto';

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const mockQcStep = {
  id: BigInt(200),
  trailerId: BigInt(1),
  departmentId: 15, // QC_1
  stepOrder: 2,
  status: 'active',
  department: { id: 15, code: 'QC_1', displayName: 'Quality Control 1', isQcStep: true },
};

const mockFinalQcStep = {
  id: BigInt(212),
  trailerId: BigInt(1),
  departmentId: 20, // FINAL_QC
  stepOrder: 12,
  status: 'active',
  department: { id: 20, code: 'FINAL_QC', displayName: 'Final QC', isQcStep: true },
};

const mockProductionStep = {
  id: BigInt(199),
  trailerId: BigInt(1),
  departmentId: 1, // XP_JIG — not a QC step
  stepOrder: 1,
  status: 'active',
  department: { id: 1, code: 'XP_JIG', displayName: 'XP Jig Weld', isQcStep: false },
};

const mockTrailer = {
  id: BigInt(1),
  soNumber: 'SO-1001',
  status: 'in_production',
  trailerModel: { series: 'xp' },
  customer: { smsPhone: '+1234567890', smsOptOut: false },
};

const mockChecklistItems = [
  { id: 1 },
  { id: 2 },
  { id: 3 },
];

const baseInspectionDto = {
  productionStepId: 200,
  result: QcResultDto.PASS,
  checklistResults: [
    { checklistItemId: 1, passed: true },
    { checklistItemId: 2, passed: true },
    { checklistItemId: 3, passed: true },
  ],
  photoStorageKeys: ['qc/photo1.jpg'],
};

const nextStep = {
  id: BigInt(201),
  department: { id: 3, displayName: 'XP Finish Weld' },
};

// ---------------------------------------------------------------------------
// Prisma mock
// ---------------------------------------------------------------------------

const mockPrisma = {
  qcChecklistItem: {
    findMany: jest.fn(),
    findUnique: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  },
  productionStep: {
    findUnique: jest.fn(),
    findFirst: jest.fn(),
    update: jest.fn(),
    aggregate: jest.fn(),
  },
  trailer: {
    findUnique: jest.fn(),
    update: jest.fn(),
  },
  qcInspection: {
    findUnique: jest.fn(),
    findMany: jest.fn(),
    count: jest.fn(),
    create: jest.fn(),
    update: jest.fn(),
  },
  qcChecklistResult: {
    createMany: jest.fn(),
  },
  qcPhoto: {
    createMany: jest.fn(),
  },
  user: {
    findMany: jest.fn(),
  },
  pushNotification: {
    createMany: jest.fn(),
  },
  smsLog: {
    create: jest.fn(),
  },
  department: {
    findUnique: jest.fn(),
  },
  $transaction: jest.fn(),
};

const mockReworkRouting = {
  routeRework: jest.fn(),
};

const mockNotificationsService = {
  onQcPass: jest.fn().mockResolvedValue(undefined),
  onQcFail: jest.fn().mockResolvedValue(undefined),
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('QcService', () => {
  let service: QcService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        QcService,
        { provide: PrismaService, useValue: mockPrisma },
        { provide: ReworkRoutingService, useValue: mockReworkRouting },
        { provide: NotificationsService, useValue: mockNotificationsService },
      ],
    }).compile();

    service = module.get<QcService>(QcService);
    jest.clearAllMocks();
  });

  // =========================================================================
  // findChecklistItems
  // =========================================================================
  describe('findChecklistItems', () => {
    it('should return all checklist items with no filters', async () => {
      const items = [
        { id: 1, departmentId: 15, itemLabel: 'Check welds', sortOrder: 0, isActive: true },
      ];
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue(items);

      const result = await service.findChecklistItems({});

      expect(result).toEqual(items);
      expect(mockPrisma.qcChecklistItem.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: {},
        }),
      );
    });

    it('should apply departmentId filter', async () => {
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue([]);

      await service.findChecklistItems({ departmentId: 15 });

      expect(mockPrisma.qcChecklistItem.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { departmentId: 15 },
        }),
      );
    });

    it('should apply series filter', async () => {
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue([]);

      await service.findChecklistItems({ series: 'xp' as any });

      expect(mockPrisma.qcChecklistItem.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { appliesToSeries: { in: ['xp', 'all'] }, requiresAddonKey: null },
        }),
      );
    });
  });

  // =========================================================================
  // createChecklistItem
  // =========================================================================
  describe('createChecklistItem', () => {
    it('should create a checklist item for a valid QC department', async () => {
      mockPrisma.department.findUnique.mockResolvedValue({ id: 15, isQcStep: true, displayName: 'Quality Control 1' });
      mockPrisma.qcChecklistItem.create.mockResolvedValue({
        id: 1,
        departmentId: 15,
        itemLabel: 'Check welds',
        sortOrder: 0,
        isActive: true,
      });

      const result = await service.createChecklistItem({
        departmentId: 15,
        itemLabel: 'Check welds',
      });

      expect(result.id).toBe(1);
      expect(mockPrisma.qcChecklistItem.create).toHaveBeenCalled();
    });

    it('should throw if department does not exist', async () => {
      mockPrisma.department.findUnique.mockResolvedValue(null);

      await expect(
        service.createChecklistItem({ departmentId: 999, itemLabel: 'X' }),
      ).rejects.toThrow(BadRequestException);
    });

    it('should throw if department is not a QC department', async () => {
      mockPrisma.department.findUnique.mockResolvedValue({ id: 1, isQcStep: false, displayName: 'XP Jig Weld' });

      await expect(
        service.createChecklistItem({ departmentId: 1, itemLabel: 'X' }),
      ).rejects.toThrow(BadRequestException);
    });
  });

  // =========================================================================
  // updateChecklistItem
  // =========================================================================
  describe('updateChecklistItem', () => {
    it('should update an existing checklist item', async () => {
      mockPrisma.qcChecklistItem.findUnique.mockResolvedValue({ id: 1 });
      mockPrisma.qcChecklistItem.update.mockResolvedValue({
        id: 1,
        itemLabel: 'Updated label',
        isActive: true,
      });

      const result = await service.updateChecklistItem(1, { itemLabel: 'Updated label' });

      expect(result.itemLabel).toBe('Updated label');
    });

    it('should deactivate a checklist item', async () => {
      mockPrisma.qcChecklistItem.findUnique.mockResolvedValue({ id: 1 });
      mockPrisma.qcChecklistItem.update.mockResolvedValue({
        id: 1,
        isActive: false,
      });

      const result = await service.updateChecklistItem(1, { isActive: false });

      expect(result.isActive).toBe(false);
    });

    it('should throw NotFoundException for non-existent item', async () => {
      mockPrisma.qcChecklistItem.findUnique.mockResolvedValue(null);

      await expect(
        service.updateChecklistItem(999, { itemLabel: 'X' }),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // =========================================================================
  // submitInspection — PASS path
  // =========================================================================
  describe('submitInspection — PASS', () => {
    it('should pass a QC inspection and advance next step to active', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(mockQcStep);
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailer);
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue(mockChecklistItems);
      mockPrisma.qcInspection.count.mockResolvedValue(0);

      mockPrisma.$transaction.mockImplementation(async (fn: any) => {
        const tx = {
          qcInspection: {
            create: jest.fn().mockResolvedValue({ id: BigInt(500) }),
            update: jest.fn(),
          },
          qcChecklistResult: { createMany: jest.fn() },
          qcPhoto: { createMany: jest.fn() },
          productionStep: {
            update: jest.fn(),
            findFirst: jest.fn().mockResolvedValue(nextStep),
            aggregate: jest.fn().mockResolvedValue({ _max: { queuePosition: 2 } }),
          },
          trailer: { update: jest.fn() },
          smsLog: { create: jest.fn() },
          user: { findMany: jest.fn() },
          pushNotification: { createMany: jest.fn() },
        };
        return fn(tx);
      });

      const result = await service.submitInspection(baseInspectionDto, BigInt(10));

      expect(result.result).toBe('pass');
      expect(result.inspectionId).toBe(BigInt(500));
      expect((result as any).nextStepId).toBe(BigInt(201));
      expect((result as any).nextDepartment).toBe('XP Finish Weld');
    });

    it('should throw STEP_NOT_ACTIVE if step is not active', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue({
        ...mockQcStep,
        status: 'waiting',
      });

      await expect(
        service.submitInspection(baseInspectionDto, BigInt(10)),
      ).rejects.toThrow(BadRequestException);
    });

    it('should throw if step is not a QC step', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(mockProductionStep);

      await expect(
        service.submitInspection(baseInspectionDto, BigInt(10)),
      ).rejects.toThrow(BadRequestException);
    });

    it('should throw if step does not exist', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(null);

      await expect(
        service.submitInspection(baseInspectionDto, BigInt(10)),
      ).rejects.toThrow(NotFoundException);
    });

    it('should throw QC_CHECKLIST_INCOMPLETE if not all items answered', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(mockQcStep);
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailer);
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue([
        { id: 1 },
        { id: 2 },
        { id: 3 },
        { id: 4 }, // extra item not in DTO
      ]);

      const incompleteDto = {
        ...baseInspectionDto,
        checklistResults: [
          { checklistItemId: 1, passed: true },
          { checklistItemId: 2, passed: true },
          { checklistItemId: 3, passed: true },
          // missing item 4
        ],
      };

      await expect(
        service.submitInspection(incompleteDto, BigInt(10)),
      ).rejects.toThrow(BadRequestException);
    });
  });

  // =========================================================================
  // submitInspection — FINAL_QC PASS
  // =========================================================================
  describe('submitInspection — FINAL_QC PASS', () => {
    it('should set trailer status to ready_for_delivery and queue SMS', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(mockFinalQcStep);
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailer);
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue(mockChecklistItems);
      mockPrisma.qcInspection.count.mockResolvedValue(0);

      let trailerUpdateCalled = false;
      let smsCreated = false;

      mockPrisma.$transaction.mockImplementation(async (fn: any) => {
        const tx = {
          qcInspection: {
            create: jest.fn().mockResolvedValue({ id: BigInt(600) }),
            update: jest.fn(),
          },
          qcChecklistResult: { createMany: jest.fn() },
          qcPhoto: { createMany: jest.fn() },
          productionStep: { update: jest.fn() },
          trailer: {
            update: jest.fn().mockImplementation(() => {
              trailerUpdateCalled = true;
            }),
          },
          smsLog: {
            create: jest.fn().mockImplementation(() => {
              smsCreated = true;
            }),
          },
          user: { findMany: jest.fn() },
          pushNotification: { createMany: jest.fn() },
        };
        return fn(tx);
      });

      const dto = {
        ...baseInspectionDto,
        productionStepId: 212,
      };

      const result = await service.submitInspection(dto, BigInt(10));

      expect(result.result).toBe('pass');
      expect((result as any).isFinalQc).toBe(true);
      expect((result as any).trailerStatus).toBe('ready_for_delivery');
      expect((result as any).smsReady).toBe(true);
      expect(trailerUpdateCalled).toBe(true);
      expect(smsCreated).toBe(true);
    });

    it('should not queue SMS if customer opted out', async () => {
      const optedOutTrailer = {
        ...mockTrailer,
        customer: { smsPhone: '+1234567890', smsOptOut: true },
      };

      mockPrisma.productionStep.findUnique.mockResolvedValue(mockFinalQcStep);
      mockPrisma.trailer.findUnique.mockResolvedValue(optedOutTrailer);
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue(mockChecklistItems);
      mockPrisma.qcInspection.count.mockResolvedValue(0);

      let smsCreated = false;

      mockPrisma.$transaction.mockImplementation(async (fn: any) => {
        const tx = {
          qcInspection: {
            create: jest.fn().mockResolvedValue({ id: BigInt(601) }),
            update: jest.fn(),
          },
          qcChecklistResult: { createMany: jest.fn() },
          qcPhoto: { createMany: jest.fn() },
          productionStep: { update: jest.fn() },
          trailer: { update: jest.fn() },
          smsLog: {
            create: jest.fn().mockImplementation(() => {
              smsCreated = true;
            }),
          },
          user: { findMany: jest.fn() },
          pushNotification: { createMany: jest.fn() },
        };
        return fn(tx);
      });

      const dto = { ...baseInspectionDto, productionStepId: 212 };
      const result = await service.submitInspection(dto, BigInt(10));

      expect((result as any).smsReady).toBe(false);
      expect(smsCreated).toBe(false);
    });
  });

  // =========================================================================
  // submitInspection — FAIL path
  // =========================================================================
  describe('submitInspection — FAIL', () => {
    const failDto = {
      ...baseInspectionDto,
      result: QcResultDto.FAIL,
      failNotes: 'Paint bubbling near left fender',
      reworkTargetDepartmentId: 1, // XP_JIG
    };

    it('should route rework to the specified department', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(mockQcStep);
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailer);
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue(mockChecklistItems);
      mockPrisma.qcInspection.count.mockResolvedValue(0);

      mockPrisma.$transaction.mockImplementation(async (fn: any) => {
        const tx = {
          qcInspection: {
            create: jest.fn().mockResolvedValue({ id: BigInt(700) }),
            update: jest.fn(),
          },
          qcChecklistResult: { createMany: jest.fn() },
          qcPhoto: { createMany: jest.fn() },
          productionStep: { update: jest.fn() },
          user: {
            findMany: jest.fn().mockResolvedValue([{ id: BigInt(5) }]),
          },
          pushNotification: { createMany: jest.fn() },
          trailer: { update: jest.fn() },
          smsLog: { create: jest.fn() },
        };

        mockReworkRouting.routeRework.mockResolvedValue({
          reworkStepId: BigInt(199),
          reworkTargetDeptId: 1,
          reworkTargetDepartment: 'XP Jig Weld',
          reworkQueuePosition: 1,
        });

        return fn(tx);
      });

      const result = await service.submitInspection(failDto, BigInt(10));

      expect(result.result).toBe('fail');
      expect((result as any).reworkTargetDepartment).toBe('XP Jig Weld');
      expect((result as any).reworkTargetDeptId).toBe(1);
      expect((result as any).reworkQueuePosition).toBe(1);
      expect((result as any).notificationSentTo).toEqual(['production_manager']);
    });

    it('should throw QC_REWORK_TARGET_REQUIRED if missing on fail', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(mockQcStep);
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailer);
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue(mockChecklistItems);

      const noTargetDto = {
        ...baseInspectionDto,
        result: QcResultDto.FAIL,
        failNotes: 'Bad welds',
        // reworkTargetDepartmentId intentionally omitted
      };

      await expect(
        service.submitInspection(noTargetDto, BigInt(10)),
      ).rejects.toThrow(BadRequestException);
    });

    it('should throw if fail_notes is missing on fail', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(mockQcStep);
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailer);
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue(mockChecklistItems);

      const noNotesDto = {
        ...baseInspectionDto,
        result: QcResultDto.FAIL,
        reworkTargetDepartmentId: 1,
        // failNotes intentionally omitted
      };

      await expect(
        service.submitInspection(noNotesDto, BigInt(10)),
      ).rejects.toThrow(BadRequestException);
    });

    it('should send push notification to production_manager on fail', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(mockQcStep);
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailer);
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue(mockChecklistItems);
      mockPrisma.qcInspection.count.mockResolvedValue(0);

      let notificationData: any = null;

      mockPrisma.$transaction.mockImplementation(async (fn: any) => {
        const tx = {
          qcInspection: {
            create: jest.fn().mockResolvedValue({ id: BigInt(701) }),
            update: jest.fn(),
          },
          qcChecklistResult: { createMany: jest.fn() },
          qcPhoto: { createMany: jest.fn() },
          productionStep: { update: jest.fn() },
          user: {
            findMany: jest.fn().mockResolvedValue([{ id: BigInt(5) }, { id: BigInt(6) }]),
          },
          pushNotification: {
            createMany: jest.fn().mockImplementation((args: any) => {
              notificationData = args;
            }),
          },
          trailer: { update: jest.fn() },
          smsLog: { create: jest.fn() },
        };

        mockReworkRouting.routeRework.mockResolvedValue({
          reworkStepId: BigInt(199),
          reworkTargetDeptId: 1,
          reworkTargetDepartment: 'XP Jig Weld',
          reworkQueuePosition: 1,
        });

        return fn(tx);
      });

      await service.submitInspection(failDto, BigInt(10));

      expect(notificationData).not.toBeNull();
      expect(notificationData.data).toHaveLength(2); // 2 production managers
      expect(notificationData.data[0].notificationType).toBe('qc_fail');
    });

    it('should increment attempt number on subsequent inspections', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(mockQcStep);
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailer);
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue(mockChecklistItems);
      mockPrisma.qcInspection.count.mockResolvedValue(2); // 2 previous inspections

      let createdAttemptNumber: number | null = null;

      mockPrisma.$transaction.mockImplementation(async (fn: any) => {
        const tx = {
          qcInspection: {
            create: jest.fn().mockImplementation((args: any) => {
              createdAttemptNumber = args.data.attemptNumber;
              return { id: BigInt(702) };
            }),
            update: jest.fn(),
          },
          qcChecklistResult: { createMany: jest.fn() },
          qcPhoto: { createMany: jest.fn() },
          productionStep: { update: jest.fn() },
          user: { findMany: jest.fn().mockResolvedValue([{ id: BigInt(5) }]) },
          pushNotification: { createMany: jest.fn() },
          trailer: { update: jest.fn() },
          smsLog: { create: jest.fn() },
        };

        mockReworkRouting.routeRework.mockResolvedValue({
          reworkStepId: BigInt(199),
          reworkTargetDeptId: 1,
          reworkTargetDepartment: 'XP Jig Weld',
          reworkQueuePosition: 1,
        });

        return fn(tx);
      });

      await service.submitInspection(failDto, BigInt(10));

      expect(createdAttemptNumber).toBe(3);
    });
  });

  // =========================================================================
  // submitInspection — Multiple fail/rework cycles
  // =========================================================================
  describe('submitInspection — multiple fail/rework cycles', () => {
    it('should handle a second fail on the same QC step after rework', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(mockQcStep);
      mockPrisma.trailer.findUnique.mockResolvedValue(mockTrailer);
      mockPrisma.qcChecklistItem.findMany.mockResolvedValue(mockChecklistItems);
      mockPrisma.qcInspection.count.mockResolvedValue(1); // 1 previous fail

      mockPrisma.$transaction.mockImplementation(async (fn: any) => {
        const tx = {
          qcInspection: {
            create: jest.fn().mockResolvedValue({ id: BigInt(800) }),
            update: jest.fn(),
          },
          qcChecklistResult: { createMany: jest.fn() },
          qcPhoto: { createMany: jest.fn() },
          productionStep: { update: jest.fn() },
          user: { findMany: jest.fn().mockResolvedValue([{ id: BigInt(5) }]) },
          pushNotification: { createMany: jest.fn() },
          trailer: { update: jest.fn() },
          smsLog: { create: jest.fn() },
        };

        // Route to a DIFFERENT department this time
        mockReworkRouting.routeRework.mockResolvedValue({
          reworkStepId: BigInt(203),
          reworkTargetDeptId: 9, // PAINT_PREP
          reworkTargetDepartment: 'Paint Preparation',
          reworkQueuePosition: 1,
        });

        return fn(tx);
      });

      const failDto = {
        ...baseInspectionDto,
        result: QcResultDto.FAIL,
        failNotes: 'Surface not properly prepped',
        reworkTargetDepartmentId: 9, // PAINT_PREP
      };

      const result = await service.submitInspection(failDto, BigInt(10));

      expect(result.result).toBe('fail');
      expect((result as any).reworkTargetDepartment).toBe('Paint Preparation');
      expect((result as any).reworkTargetDeptId).toBe(9);
    });
  });

  // =========================================================================
  // findInspection
  // =========================================================================
  describe('findInspection', () => {
    it('should return a single inspection with results and photos', async () => {
      const mockInspection = {
        id: BigInt(500),
        result: 'pass',
        failNotes: null,
        attemptNumber: 1,
        isFinalQc: false,
        inspectedAt: new Date(),
        inspectorUser: { id: BigInt(10), fullName: 'Inspector Bob' },
        reworkTargetDept: null,
        reworkSentToStep: null,
        productionStep: { stepOrder: 2, department: { code: 'QC_1', displayName: 'Quality Control 1' } },
        checklistResults: [{ id: BigInt(1), passed: true, note: null, checklistItem: { id: 1, itemLabel: 'Check welds' } }],
        photos: [{ id: BigInt(1), storageUrl: 'qc/photo1.jpg', storageKey: 'qc/photo1.jpg', takenAt: new Date() }],
      };

      mockPrisma.qcInspection.findUnique.mockResolvedValue(mockInspection);

      const result = await service.findInspection(BigInt(500));

      expect(result.id).toBe(BigInt(500));
      expect(result.checklistResults).toHaveLength(1);
      expect(result.photos).toHaveLength(1);
    });

    it('should throw NotFoundException for non-existent inspection', async () => {
      mockPrisma.qcInspection.findUnique.mockResolvedValue(null);

      await expect(service.findInspection(BigInt(999))).rejects.toThrow(NotFoundException);
    });
  });

  // =========================================================================
  // findInspectionsByStep
  // =========================================================================
  describe('findInspectionsByStep', () => {
    it('should return all inspections for a step', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue({ id: BigInt(200) });
      mockPrisma.qcInspection.findMany.mockResolvedValue([
        { id: BigInt(500), result: 'fail', attemptNumber: 1 },
        { id: BigInt(501), result: 'pass', attemptNumber: 2 },
      ]);

      const result = await service.findInspectionsByStep(BigInt(200));

      expect(result).toHaveLength(2);
      expect(result[0].result).toBe('fail');
      expect(result[1].result).toBe('pass');
    });

    it('should throw NotFoundException for non-existent step', async () => {
      mockPrisma.productionStep.findUnique.mockResolvedValue(null);

      await expect(service.findInspectionsByStep(BigInt(999))).rejects.toThrow(NotFoundException);
    });
  });
});
