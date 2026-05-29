import { Test, TestingModule } from '@nestjs/testing';
import { ErrorCode } from '../../common/errors';
import { WorkflowGeneratorService } from './workflow-generator.service';
import { PrismaService } from '../../prisma/prisma.service';

// ---------------------------------------------------------------------------
// Department fixture — maps code to a stable test id
// ---------------------------------------------------------------------------
const DEPT: Record<string, { id: number; code: string; isQcStep: boolean }> = {
  XP_JIG: { id: 1, code: 'XP_JIG', isQcStep: false },
  XP_FIN: { id: 2, code: 'XP_FIN', isQcStep: false },
  YETI_JIG: { id: 3, code: 'YETI_JIG', isQcStep: false },
  YETI_FIN: { id: 4, code: 'YETI_FIN', isQcStep: false },
  DO_JIG: { id: 5, code: 'DO_JIG', isQcStep: false },
  DO_FIN: { id: 6, code: 'DO_FIN', isQcStep: false },
  GN_WELD: { id: 7, code: 'GN_WELD', isQcStep: false },
  GN_FIN: { id: 8, code: 'GN_FIN', isQcStep: false },
  PAINT_PREP: { id: 9, code: 'PAINT_PREP', isQcStep: false },
  PAINT_A: { id: 10, code: 'PAINT_A', isQcStep: false },
  PAINT_B: { id: 11, code: 'PAINT_B', isQcStep: false },
  HYDRAULICS: { id: 12, code: 'HYDRAULICS', isQcStep: false },
  WIRE: { id: 13, code: 'WIRE', isQcStep: false },
  WOOD: { id: 14, code: 'WOOD', isQcStep: false },
  QC_1: { id: 15, code: 'QC_1', isQcStep: true },
  QC_2: { id: 16, code: 'QC_2', isQcStep: true },
  QC_3: { id: 17, code: 'QC_3', isQcStep: true },
  QC_4: { id: 18, code: 'QC_4', isQcStep: true },
  QC_5: { id: 19, code: 'QC_5', isQcStep: true },
  FINAL_QC: { id: 20, code: 'FINAL_QC', isQcStep: true },
};

// ---------------------------------------------------------------------------
// Workflow template definitions per series (matches seed.ts exactly)
// ---------------------------------------------------------------------------
const SERIES_TEMPLATES: Record<string, { deptCode: string; stepOrder: number }[]> = {
  xp: [
    { deptCode: 'XP_JIG', stepOrder: 1 },
    { deptCode: 'QC_1', stepOrder: 2 },
    { deptCode: 'XP_FIN', stepOrder: 3 },
    { deptCode: 'QC_2', stepOrder: 4 },
    { deptCode: 'PAINT_PREP', stepOrder: 5 },
    { deptCode: 'QC_3', stepOrder: 6 },
    { deptCode: 'PAINT_A', stepOrder: 7 },
    { deptCode: 'QC_4', stepOrder: 8 },
    { deptCode: 'WIRE', stepOrder: 9 },
    { deptCode: 'QC_5', stepOrder: 10 },
    { deptCode: 'WOOD', stepOrder: 11 },
    { deptCode: 'FINAL_QC', stepOrder: 12 },
  ],
  yeti: [
    { deptCode: 'YETI_JIG', stepOrder: 1 },
    { deptCode: 'QC_1', stepOrder: 2 },
    { deptCode: 'YETI_FIN', stepOrder: 3 },
    { deptCode: 'QC_2', stepOrder: 4 },
    { deptCode: 'PAINT_PREP', stepOrder: 5 },
    { deptCode: 'QC_3', stepOrder: 6 },
    { deptCode: 'PAINT_A', stepOrder: 7 },
    { deptCode: 'QC_4', stepOrder: 8 },
    { deptCode: 'WIRE', stepOrder: 9 },
    { deptCode: 'QC_5', stepOrder: 10 },
    { deptCode: 'WOOD', stepOrder: 11 },
    { deptCode: 'FINAL_QC', stepOrder: 12 },
  ],
  deck_over: [
    { deptCode: 'DO_JIG', stepOrder: 1 },
    { deptCode: 'QC_1', stepOrder: 2 },
    { deptCode: 'DO_FIN', stepOrder: 3 },
    { deptCode: 'QC_2', stepOrder: 4 },
    { deptCode: 'PAINT_PREP', stepOrder: 5 },
    { deptCode: 'QC_3', stepOrder: 6 },
    { deptCode: 'PAINT_A', stepOrder: 7 },
    { deptCode: 'QC_4', stepOrder: 8 },
    { deptCode: 'WIRE', stepOrder: 9 },
    { deptCode: 'QC_5', stepOrder: 10 },
    { deptCode: 'WOOD', stepOrder: 11 },
    { deptCode: 'FINAL_QC', stepOrder: 12 },
  ],
  gooseneck_dump: [
    { deptCode: 'GN_WELD', stepOrder: 1 },
    { deptCode: 'QC_1', stepOrder: 2 },
    { deptCode: 'GN_FIN', stepOrder: 3 },
    { deptCode: 'QC_2', stepOrder: 4 },
    { deptCode: 'PAINT_PREP', stepOrder: 5 },
    { deptCode: 'QC_3', stepOrder: 6 },
    { deptCode: 'PAINT_B', stepOrder: 7 },
    { deptCode: 'QC_4', stepOrder: 8 },
    { deptCode: 'HYDRAULICS', stepOrder: 9 },
    { deptCode: 'QC_5', stepOrder: 10 },
    { deptCode: 'WOOD', stepOrder: 11 },
    { deptCode: 'FINAL_QC', stepOrder: 12 },
  ],
};

/** Build mock workflow_template rows for a given series */
function buildTemplateRows(series: string) {
  return SERIES_TEMPLATES[series].map((t) => ({
    id: t.stepOrder,
    series,
    departmentId: DEPT[t.deptCode].id,
    stepOrder: t.stepOrder,
    department: DEPT[t.deptCode],
  }));
}

// ---------------------------------------------------------------------------
// Mock transaction client
// ---------------------------------------------------------------------------
let createdSteps: any[] = [];
let stepIdCounter = 100;

/** Default queue depths used when a test doesn't override them. */
let paintAQueueDepth = 0;
let paintBQueueDepth = 0;

const mockTx = {
  workflowTemplate: {
    findMany: jest.fn(),
  },
  productionStep: {
    create: jest.fn().mockImplementation(({ data }) => {
      const id = BigInt(stepIdCounter++);
      createdSteps.push({ id, ...data });
      return Promise.resolve({ id });
    }),
    count: jest.fn().mockImplementation(({ where }: any) => {
      if (where?.departmentId === DEPT.PAINT_A.id) {
        return Promise.resolve(paintAQueueDepth);
      }
      if (where?.departmentId === DEPT.PAINT_B.id) {
        return Promise.resolve(paintBQueueDepth);
      }
      return Promise.resolve(0);
    }),
  },
  department: {
    findMany: jest.fn().mockImplementation(({ where }: any) => {
      const codes: string[] = where?.code?.in ?? [];
      const matched = codes
        .filter((c) => c in DEPT)
        .map((c) => ({ id: DEPT[c].id, code: c }));
      return Promise.resolve(matched);
    }),
  },
};

// ---------------------------------------------------------------------------
// Prisma mock (only needed for module compilation — actual DB calls go through tx)
// ---------------------------------------------------------------------------
const mockPrisma = {};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
describe('WorkflowGeneratorService', () => {
  let service: WorkflowGeneratorService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        WorkflowGeneratorService,
        { provide: PrismaService, useValue: mockPrisma },
      ],
    }).compile();

    service = module.get<WorkflowGeneratorService>(WorkflowGeneratorService);
    jest.clearAllMocks();
    createdSteps = [];
    stepIdCounter = 100;
    paintAQueueDepth = 0;
    paintBQueueDepth = 0;
  });

  // =========================================================================
  // XP Series
  // =========================================================================
  describe('XP series', () => {
    it('should generate exactly 12 steps in correct department order', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('xp'));

      const result = await service.generateSteps(BigInt(1), 'xp' as any, mockTx as any);

      expect(result.totalSteps).toBe(12);
      expect(result.series).toBe('xp');
      expect(createdSteps).toHaveLength(12);

      // Verify department order matches spec:
      // XP_JIG → QC_1 → XP_FIN → QC_2 → PAINT_PREP → QC_3 → PAINT_A → QC_4 → WIRE → QC_5 → WOOD → FINAL_QC
      const expectedDeptIds = [1, 15, 2, 16, 9, 17, 10, 18, 13, 19, 14, 20];
      expect(createdSteps.map((s) => s.departmentId)).toEqual(expectedDeptIds);
    });

    it('should set first step (XP_JIG) to active and rest to waiting', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('xp'));

      await service.generateSteps(BigInt(1), 'xp' as any, mockTx as any);

      // Step 1 (XP_JIG) — active
      expect(createdSteps[0].status).toBe('active');
      expect(createdSteps[0].queuePosition).toBe(1);
      expect(createdSteps[0].becameActiveAt).toBeInstanceOf(Date);

      // All other steps — waiting
      for (let i = 1; i < 12; i++) {
        expect(createdSteps[i].status).toBe('waiting');
        expect(createdSteps[i].queuePosition).toBeNull();
        expect(createdSteps[i].becameActiveAt).toBeNull();
      }
    });

    it('should use PAINT_A and WIRE (not PAINT_B or HYDRAULICS)', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('xp'));

      await service.generateSteps(BigInt(1), 'xp' as any, mockTx as any);

      const deptIds = createdSteps.map((s) => s.departmentId);
      expect(deptIds).toContain(DEPT.PAINT_A.id);
      expect(deptIds).toContain(DEPT.WIRE.id);
      expect(deptIds).not.toContain(DEPT.PAINT_B.id);
      expect(deptIds).not.toContain(DEPT.HYDRAULICS.id);
    });
  });

  // =========================================================================
  // Yeti Series
  // =========================================================================
  describe('Yeti series', () => {
    it('should generate 12 steps starting with YETI_JIG', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('yeti'));

      const result = await service.generateSteps(BigInt(2), 'yeti' as any, mockTx as any);

      expect(result.totalSteps).toBe(12);
      expect(createdSteps).toHaveLength(12);

      // YETI_JIG → QC_1 → YETI_FIN → QC_2 → PAINT_PREP → QC_3 → PAINT_A → QC_4 → WIRE → QC_5 → WOOD → FINAL_QC
      const expectedDeptIds = [3, 15, 4, 16, 9, 17, 10, 18, 13, 19, 14, 20];
      expect(createdSteps.map((s) => s.departmentId)).toEqual(expectedDeptIds);
    });

    it('should set first step (YETI_JIG) to active', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('yeti'));

      await service.generateSteps(BigInt(2), 'yeti' as any, mockTx as any);

      expect(createdSteps[0].departmentId).toBe(DEPT.YETI_JIG.id);
      expect(createdSteps[0].status).toBe('active');
    });

    it('should use PAINT_A and WIRE (not PAINT_B or HYDRAULICS)', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('yeti'));

      await service.generateSteps(BigInt(2), 'yeti' as any, mockTx as any);

      const deptIds = createdSteps.map((s) => s.departmentId);
      expect(deptIds).toContain(DEPT.PAINT_A.id);
      expect(deptIds).toContain(DEPT.WIRE.id);
      expect(deptIds).not.toContain(DEPT.PAINT_B.id);
      expect(deptIds).not.toContain(DEPT.HYDRAULICS.id);
    });
  });

  // =========================================================================
  // Deck Over Series
  // =========================================================================
  describe('Deck Over series', () => {
    it('should generate 12 steps starting with DO_JIG', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('deck_over'));

      const result = await service.generateSteps(
        BigInt(3),
        'deck_over' as any,
        mockTx as any,
      );

      expect(result.totalSteps).toBe(12);

      // DO_JIG → QC_1 → DO_FIN → QC_2 → PAINT_PREP → QC_3 → PAINT_A → QC_4 → WIRE → QC_5 → WOOD → FINAL_QC
      const expectedDeptIds = [5, 15, 6, 16, 9, 17, 10, 18, 13, 19, 14, 20];
      expect(createdSteps.map((s) => s.departmentId)).toEqual(expectedDeptIds);
    });

    it('should set first step (DO_JIG) to active', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('deck_over'));

      await service.generateSteps(BigInt(3), 'deck_over' as any, mockTx as any);

      expect(createdSteps[0].departmentId).toBe(DEPT.DO_JIG.id);
      expect(createdSteps[0].status).toBe('active');
    });
  });

  // =========================================================================
  // Gooseneck/Dump Series
  // =========================================================================
  describe('Gooseneck/Dump series', () => {
    it('should generate 12 steps with GN_WELD, GN_FIN, PAINT_B, HYDRAULICS', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(
        buildTemplateRows('gooseneck_dump'),
      );

      const result = await service.generateSteps(
        BigInt(4),
        'gooseneck_dump' as any,
        mockTx as any,
      );

      expect(result.totalSteps).toBe(12);

      // GN_WELD → QC_1 → GN_FIN → QC_2 → PAINT_PREP → QC_3 → PAINT_B → QC_4 → HYDRAULICS → QC_5 → WOOD → FINAL_QC
      const expectedDeptIds = [7, 15, 8, 16, 9, 17, 11, 18, 12, 19, 14, 20];
      expect(createdSteps.map((s) => s.departmentId)).toEqual(expectedDeptIds);
    });

    it('should use PAINT_B and HYDRAULICS (not PAINT_A or WIRE)', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(
        buildTemplateRows('gooseneck_dump'),
      );

      await service.generateSteps(BigInt(4), 'gooseneck_dump' as any, mockTx as any);

      const deptIds = createdSteps.map((s) => s.departmentId);
      expect(deptIds).toContain(DEPT.PAINT_B.id);
      expect(deptIds).toContain(DEPT.HYDRAULICS.id);
      expect(deptIds).not.toContain(DEPT.PAINT_A.id);
      expect(deptIds).not.toContain(DEPT.WIRE.id);
    });

    it('should set first step (GN_WELD) to active', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(
        buildTemplateRows('gooseneck_dump'),
      );

      await service.generateSteps(BigInt(4), 'gooseneck_dump' as any, mockTx as any);

      expect(createdSteps[0].departmentId).toBe(DEPT.GN_WELD.id);
      expect(createdSteps[0].status).toBe('active');
    });
  });

  // =========================================================================
  // Common behaviour across all series
  // =========================================================================
  describe('common behaviour', () => {
    it('should assign correct stepOrder to each created step', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('xp'));

      await service.generateSteps(BigInt(1), 'xp' as any, mockTx as any);

      for (let i = 0; i < 12; i++) {
        expect(createdSteps[i].stepOrder).toBe(i + 1);
      }
    });

    it('should always have 6 QC steps and 6 production steps', async () => {
      for (const series of ['xp', 'yeti', 'deck_over', 'gooseneck_dump']) {
        createdSteps = [];
        stepIdCounter = 100;
        mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows(series));

        await service.generateSteps(BigInt(1), series as any, mockTx as any);

        // QC steps are at even positions (2,4,6,8,10,12)
        const qcSteps = createdSteps.filter((s) =>
          [15, 16, 17, 18, 19, 20].includes(s.departmentId),
        );
        const prodSteps = createdSteps.filter(
          (s) => ![15, 16, 17, 18, 19, 20].includes(s.departmentId),
        );
        expect(qcSteps).toHaveLength(6);
        expect(prodSteps).toHaveLength(6);
      }
    });

    it('should always end with FINAL_QC at step 12', async () => {
      for (const series of ['xp', 'yeti', 'deck_over', 'gooseneck_dump']) {
        createdSteps = [];
        stepIdCounter = 100;
        mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows(series));

        await service.generateSteps(BigInt(1), series as any, mockTx as any);

        const lastStep = createdSteps[11];
        expect(lastStep.departmentId).toBe(DEPT.FINAL_QC.id);
        expect(lastStep.stepOrder).toBe(12);
      }
    });

    it('should return firstActiveStepId', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('xp'));

      const result = await service.generateSteps(BigInt(1), 'xp' as any, mockTx as any);

      expect(result.firstActiveStepId).toBe(BigInt(100)); // first step gets id 100
    });

    it('should pass trailerId to every created step', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('xp'));

      await service.generateSteps(BigInt(42), 'xp' as any, mockTx as any);

      for (const step of createdSteps) {
        expect(step.trailerId).toBe(BigInt(42));
      }
    });

    it('should throw BAD_REQUEST if no templates found', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue([]);

      await expect(
        service.generateSteps(BigInt(1), 'xp' as any, mockTx as any),
      ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
    });

    it('should throw BAD_REQUEST if template count is not 12', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(
        buildTemplateRows('xp').slice(0, 6), // only 6 templates
      );

      await expect(
        service.generateSteps(BigInt(1), 'xp' as any, mockTx as any),
      ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
    });
  });

  // =========================================================================
  // Paint booth load-balancing (XP / Yeti / Deck Over)
  // =========================================================================
  describe('paint booth load-balancing', () => {
    const NON_GN_SERIES = ['xp', 'yeti', 'deck_over'] as const;

    it.each(NON_GN_SERIES)(
      '%s: routes to PAINT_B when its queue is lighter',
      async (series) => {
        mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows(series));
        paintAQueueDepth = 5;
        paintBQueueDepth = 2;

        await service.generateSteps(BigInt(1), series as any, mockTx as any);

        const paintStep = createdSteps[6]; // step_order 7
        expect(paintStep.departmentId).toBe(DEPT.PAINT_B.id);
      },
    );

    it.each(NON_GN_SERIES)(
      '%s: routes to PAINT_A when its queue is lighter',
      async (series) => {
        mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows(series));
        paintAQueueDepth = 1;
        paintBQueueDepth = 4;

        await service.generateSteps(BigInt(1), series as any, mockTx as any);

        const paintStep = createdSteps[6];
        expect(paintStep.departmentId).toBe(DEPT.PAINT_A.id);
      },
    );

    it.each(NON_GN_SERIES)(
      '%s: ties go to PAINT_A',
      async (series) => {
        mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows(series));
        paintAQueueDepth = 3;
        paintBQueueDepth = 3;

        await service.generateSteps(BigInt(1), series as any, mockTx as any);

        const paintStep = createdSteps[6];
        expect(paintStep.departmentId).toBe(DEPT.PAINT_A.id);
      },
    );

    it('gooseneck_dump always uses PAINT_B regardless of queue depth', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(
        buildTemplateRows('gooseneck_dump'),
      );
      // Set PAINT_B as the heavier queue — load balancer would normally
      // pick PAINT_A, but GN/Dump must skip the picker.
      paintAQueueDepth = 0;
      paintBQueueDepth = 100;

      await service.generateSteps(
        BigInt(1),
        'gooseneck_dump' as any,
        mockTx as any,
      );

      const paintStep = createdSteps[6];
      expect(paintStep.departmentId).toBe(DEPT.PAINT_B.id);
      // And the picker is never invoked for GN/Dump
      expect(mockTx.department.findMany).not.toHaveBeenCalled();
      expect(mockTx.productionStep.count).not.toHaveBeenCalled();
    });

    it('throws BAD_REQUEST if both PAINT_A and PAINT_B departments are missing', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('xp'));
      mockTx.department.findMany.mockResolvedValueOnce([]);

      await expect(
        service.generateSteps(BigInt(1), 'xp' as any, mockTx as any),
      ).rejects.toMatchObject({ errorCode: ErrorCode.BAD_REQUEST });
    });

    it('falls back to the only available booth when one is missing', async () => {
      mockTx.workflowTemplate.findMany.mockResolvedValue(buildTemplateRows('xp'));
      // Only PAINT_B is present in the departments table.
      mockTx.department.findMany.mockResolvedValueOnce([
        { id: DEPT.PAINT_B.id, code: 'PAINT_B' },
      ]);
      paintAQueueDepth = 0;
      paintBQueueDepth = 50;

      await service.generateSteps(BigInt(1), 'xp' as any, mockTx as any);

      const paintStep = createdSteps[6];
      expect(paintStep.departmentId).toBe(DEPT.PAINT_B.id);
    });
  });
});
