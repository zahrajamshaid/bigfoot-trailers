/**
 * HAPPY PATH E2E — Complete 12-step workflow for all 4 trailer series.
 *
 * For each series: create trailer → alternate (production complete + QC pass)
 * × 6 → verify trailer reaches ready_for_delivery.
 *
 * Gooseneck is verified to use GN_FIN, PAINT_B, and HYDRAULICS.
 */
import * as request from 'supertest';
import { PrismaService } from '../../src/prisma/prisma.service';
import { createTestApp, TestContext } from '../helpers/test-app.helper';
import {
  seedReferenceData,
  seedTestChecklistItems,
  cleanupTransactionalData,
} from '../helpers/test-db.helper';
import { createAndLogin, TestUser } from '../helpers/auth.helper';
import { completeFullWorkflow } from '../helpers/workflow.helper';

describe('Happy Path — Full Workflow (e2e)', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let httpServer: any;
  let owner: TestUser;
  let qcInspector: TestUser;
  let worker: TestUser;
  let checklistItemMap: Map<string, number>;

  // Resolved model IDs
  let xpModelId: number;
  let yetiModelId: number;
  let doModelId: number;
  let gnModelId: number;

  beforeAll(async () => {
    ctx = await createTestApp();
    prisma = ctx.prisma;
    httpServer = ctx.httpServer;

    await seedReferenceData(prisma);
    await cleanupTransactionalData(prisma);
    checklistItemMap = await seedTestChecklistItems(prisma);

    // Create test users
    owner = await createAndLogin(prisma, httpServer, 'owner', {
      fullName: 'E2E Owner',
    });
    qcInspector = await createAndLogin(prisma, httpServer, 'qc_inspector', {
      fullName: 'E2E QC Inspector',
    });
    worker = await createAndLogin(prisma, httpServer, 'worker', {
      fullName: 'E2E Worker',
    });

    // Resolve model IDs
    const models = await prisma.trailerModel.findMany({
      select: { id: true, code: true },
    });
    const modelMap = new Map(models.map((m) => [m.code, m.id]));
    xpModelId = modelMap.get('XP_14ET')!;
    yetiModelId = modelMap.get('YETI_15K')!;
    doModelId = modelMap.get('DO_STANDARD')!;
    gnModelId = modelMap.get('GN_STANDARD')!;
  }, 60_000);

  afterAll(async () => {
    await cleanupTransactionalData(prisma);
    await ctx.app.close();
  });

  // ── Helper: create trailer and fetch its steps ────────────────────────────

  async function createTrailerAndGetSteps(soNumber: string, trailerModelId: number) {
    const createRes = await request(httpServer)
      .post('/v1/trailers')
      .set('Authorization', `Bearer ${owner.token}`)
      .send({ soNumber, trailerModelId })
      .expect(201);

    const trailerId = BigInt(createRes.body.data.trailer.id);

    const stepsRes = await request(httpServer)
      .get(`/v1/trailers/${Number(trailerId)}/steps`)
      .set('Authorization', `Bearer ${owner.token}`)
      .expect(200);

    return { trailerId, steps: stepsRes.body.data };
  }

  // ── XP Series ─────────────────────────────────────────────────────────────

  describe('XP Series', () => {
    it('should complete all 12 steps and reach ready_for_delivery', async () => {
      const { trailerId, steps } = await createTrailerAndGetSteps(
        'E2E-XP-HAPPY',
        xpModelId,
      );

      // 12 steps generated
      expect(steps).toHaveLength(12);

      // Correct department order
      const expectedDepts = [
        'XP_JIG',
        'QC_1',
        'XP_FIN',
        'QC_2',
        'PAINT_PREP',
        'QC_3',
        'PAINT_A',
        'QC_4',
        'WIRE',
        'QC_5',
        'WOOD',
        'FINAL_QC',
      ];
      for (let i = 0; i < expectedDepts.length; i++) {
        expect(steps[i].department.code).toBe(expectedDepts[i]);
        expect(steps[i].stepOrder).toBe(i + 1);
      }

      // First step is active, rest are waiting
      expect(steps[0].status).toBe('active');
      expect(steps[1].status).toBe('waiting');

      // Complete full workflow
      const finalStatus = await completeFullWorkflow(
        prisma,
        httpServer,
        trailerId,
        worker.id,
        qcInspector.token,
        checklistItemMap,
      );

      expect(finalStatus).toBe('ready_for_delivery');

      // All 12 steps should now be complete
      const finalSteps = await prisma.productionStep.findMany({
        where: { trailerId },
        select: { status: true },
      });
      expect(finalSteps).toHaveLength(12);
      expect(finalSteps.every((s) => s.status === 'complete')).toBe(true);
    });
  });

  // ── Yeti Series ───────────────────────────────────────────────────────────

  describe('Yeti Series', () => {
    it('should complete all 12 steps and reach ready_for_delivery', async () => {
      const { trailerId, steps } = await createTrailerAndGetSteps(
        'E2E-YETI-HAPPY',
        yetiModelId,
      );

      expect(steps).toHaveLength(12);
      expect(steps[0].department.code).toBe('YETI_JIG');
      expect(steps[2].department.code).toBe('YETI_FIN');

      const finalStatus = await completeFullWorkflow(
        prisma,
        httpServer,
        trailerId,
        worker.id,
        qcInspector.token,
        checklistItemMap,
      );

      expect(finalStatus).toBe('ready_for_delivery');
    });
  });

  // ── Deck Over Series ──────────────────────────────────────────────────────

  describe('Deck Over Series', () => {
    it('should complete all 12 steps and reach ready_for_delivery', async () => {
      const { trailerId, steps } = await createTrailerAndGetSteps(
        'E2E-DO-HAPPY',
        doModelId,
      );

      expect(steps).toHaveLength(12);
      expect(steps[0].department.code).toBe('DO_JIG');
      expect(steps[2].department.code).toBe('DO_FIN');

      const finalStatus = await completeFullWorkflow(
        prisma,
        httpServer,
        trailerId,
        worker.id,
        qcInspector.token,
        checklistItemMap,
      );

      expect(finalStatus).toBe('ready_for_delivery');
    });
  });

  // ── Gooseneck / Dump Series ───────────────────────────────────────────────

  describe('Gooseneck Series', () => {
    it('should use GN_FIN, PAINT_B, HYDRAULICS and reach ready_for_delivery', async () => {
      const { trailerId, steps } = await createTrailerAndGetSteps(
        'E2E-GN-HAPPY',
        gnModelId,
      );

      expect(steps).toHaveLength(12);

      // Verify Gooseneck-specific department order
      const expectedDepts = [
        'GN_WELD',
        'QC_1',
        'GN_FIN',
        'QC_2',
        'PAINT_PREP',
        'QC_3',
        'PAINT_B',
        'QC_4',
        'HYDRAULICS',
        'QC_5',
        'WOOD',
        'FINAL_QC',
      ];
      for (let i = 0; i < expectedDepts.length; i++) {
        expect(steps[i].department.code).toBe(expectedDepts[i]);
      }

      // Assert the three GN-specific departments
      expect(steps[2].department.code).toBe('GN_FIN'); // GN Finish Weld (new v1.3)
      expect(steps[6].department.code).toBe('PAINT_B'); // Paint Booth B (not A)
      expect(steps[8].department.code).toBe('HYDRAULICS'); // Hydraulics (not Wire)

      const finalStatus = await completeFullWorkflow(
        prisma,
        httpServer,
        trailerId,
        worker.id,
        qcInspector.token,
        checklistItemMap,
      );

      expect(finalStatus).toBe('ready_for_delivery');

      // Verify trailer detail also reflects ready_for_delivery
      const detailRes = await request(httpServer)
        .get(`/v1/trailers/${Number(trailerId)}`)
        .set('Authorization', `Bearer ${owner.token}`)
        .expect(200);

      expect(detailRes.body.data.status).toBe('ready_for_delivery');
    });
  });
});
