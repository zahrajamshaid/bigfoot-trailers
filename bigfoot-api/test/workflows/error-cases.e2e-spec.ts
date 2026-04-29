/**
 * ERROR CASES E2E — Verify correct error codes for invalid operations.
 *
 * Covers:
 *   - STEP_NOT_ACTIVE          — QC inspection on a waiting step
 *   - QC_REWORK_TARGET_REQUIRED — QC fail without rework_target_department_id
 *   - QC_INVALID_REWORK_TARGET  — QC fail with department not in series workflow
 *   - DELIVERY_NOT_DISPATCHABLE — Delivery for non-ready trailer
 *   - SO_NUMBER_EXISTS          — Duplicate SO number on trailer creation
 *   - PAYROLL_WEEK_LOCKED       — (tested in payroll.e2e-spec.ts)
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
import {
  completeProductionStep,
  getActiveStep,
  submitQcInspection,
} from '../helpers/workflow.helper';

describe('Error Cases (e2e)', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let httpServer: any;
  let owner: TestUser;
  let qcInspector: TestUser;
  let worker: TestUser;
  let transportManager: TestUser;
  let checklistItemMap: Map<string, number>;
  let xpModelId: number;

  beforeAll(async () => {
    ctx = await createTestApp();
    prisma = ctx.prisma;
    httpServer = ctx.httpServer;

    await seedReferenceData(prisma);
    await cleanupTransactionalData(prisma);
    checklistItemMap = await seedTestChecklistItems(prisma);

    owner = await createAndLogin(prisma, httpServer, 'owner', {
      fullName: 'E2E Owner',
    });
    qcInspector = await createAndLogin(prisma, httpServer, 'qc_inspector', {
      fullName: 'E2E QC Inspector',
    });
    worker = await createAndLogin(prisma, httpServer, 'worker', {
      fullName: 'E2E Worker',
    });
    transportManager = await createAndLogin(prisma, httpServer, 'transport_manager', {
      fullName: 'E2E Transport Mgr',
    });

    const xpModel = await prisma.trailerModel.findFirst({
      where: { code: 'XP_14ET' },
      select: { id: true },
    });
    xpModelId = xpModel!.id;
  }, 60_000);

  afterAll(async () => {
    await cleanupTransactionalData(prisma);
    await ctx.app.close();
  });

  // ── STEP_NOT_ACTIVE ───────────────────────────────────────────────────────

  describe('STEP_NOT_ACTIVE', () => {
    it('should reject QC inspection on a waiting step', async () => {
      // Create trailer — step 1 (XP_JIG) is active, step 2 (QC_1) is waiting
      const createRes = await request(httpServer)
        .post('/v1/trailers')
        .set('Authorization', `Bearer ${owner.token}`)
        .send({ soNumber: 'E2E-ERR-STEP-NA', trailerModelId: xpModelId })
        .expect(201);

      const trailerId = BigInt(createRes.body.data.trailer.id);

      // Find QC_1 step (step_order=2, should be 'waiting')
      const qcStep = await prisma.productionStep.findFirst({
        where: { trailerId, stepOrder: 2 },
        select: { id: true, status: true },
      });
      expect(qcStep!.status).toBe('waiting');

      // Try to submit QC inspection on the waiting step
      const res = await submitQcInspection(httpServer, qcInspector.token, {
        stepId: qcStep!.id,
        result: 'pass',
        checklistItemId: checklistItemMap.get('QC_1')!,
      });

      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe('STEP_NOT_ACTIVE');
    });
  });

  // ── QC_REWORK_TARGET_REQUIRED ─────────────────────────────────────────────

  describe('QC_REWORK_TARGET_REQUIRED', () => {
    it('should reject QC fail without rework_target_department_id', async () => {
      const createRes = await request(httpServer)
        .post('/v1/trailers')
        .set('Authorization', `Bearer ${owner.token}`)
        .send({ soNumber: 'E2E-ERR-REWORK-REQ', trailerModelId: xpModelId })
        .expect(201);

      const trailerId = BigInt(createRes.body.data.trailer.id);

      // Complete XP_JIG (step 1) so QC_1 becomes active
      let active = await getActiveStep(prisma, trailerId);
      await completeProductionStep(prisma, active!.id, worker.id);

      active = await getActiveStep(prisma, trailerId);
      expect(active!.departmentCode).toBe('QC_1');

      // Fail QC_1 WITHOUT reworkTargetDepartmentId
      const res = await request(httpServer)
        .post('/v1/qc/inspections')
        .set('Authorization', `Bearer ${qcInspector.token}`)
        .send({
          productionStepId: Number(active!.id),
          result: 'fail',
          failNotes: 'Bad weld',
          checklistResults: [
            { checklistItemId: checklistItemMap.get('QC_1')!, passed: false },
          ],
          photoStorageKeys: ['e2e/photo.jpg'],
          // reworkTargetDepartmentId intentionally omitted
        })
        .expect(400);

      expect(res.body.error.code).toBe('QC_REWORK_TARGET_REQUIRED');
    });
  });

  // ── QC_INVALID_REWORK_TARGET ──────────────────────────────────────────────

  describe('QC_INVALID_REWORK_TARGET', () => {
    it('should reject QC fail with a department not in this series workflow', async () => {
      const createRes = await request(httpServer)
        .post('/v1/trailers')
        .set('Authorization', `Bearer ${owner.token}`)
        .send({ soNumber: 'E2E-ERR-INVALID-DEPT', trailerModelId: xpModelId })
        .expect(201);

      const trailerId = BigInt(createRes.body.data.trailer.id);

      // Complete XP_JIG so QC_1 becomes active
      let active = await getActiveStep(prisma, trailerId);
      await completeProductionStep(prisma, active!.id, worker.id);

      active = await getActiveStep(prisma, trailerId);
      expect(active!.departmentCode).toBe('QC_1');

      // Get GN_WELD department — NOT in XP's workflow
      const gnWeldDept = await prisma.department.findFirst({
        where: { code: 'GN_WELD' },
        select: { id: true },
      });

      const res = await submitQcInspection(httpServer, qcInspector.token, {
        stepId: active!.id,
        result: 'fail',
        checklistItemId: checklistItemMap.get('QC_1')!,
        failNotes: 'Bad weld — routing to invalid dept',
        reworkTargetDepartmentId: gnWeldDept!.id,
      });

      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe('QC_INVALID_REWORK_TARGET');
    });
  });

  // ── DELIVERY_NOT_DISPATCHABLE ─────────────────────────────────────────────

  describe('DELIVERY_NOT_DISPATCHABLE', () => {
    it('should reject delivery creation for a non-ready trailer', async () => {
      // Create trailer — it starts as pending_production
      const createRes = await request(httpServer)
        .post('/v1/trailers')
        .set('Authorization', `Bearer ${owner.token}`)
        .send({ soNumber: 'E2E-ERR-NOT-DISPATCH', trailerModelId: xpModelId })
        .expect(201);

      const trailerId = createRes.body.data.trailer.id;

      // Try to create delivery — trailer is NOT ready_for_delivery
      const res = await request(httpServer)
        .post('/v1/deliveries')
        .set('Authorization', `Bearer ${transportManager.token}`)
        .send({
          trailerId,
          deliveryType: 'single_pull',
        })
        .expect(400);

      expect(res.body.error.code).toBe('DELIVERY_NOT_DISPATCHABLE');
    });
  });

  // ── SO_NUMBER_EXISTS ──────────────────────────────────────────────────────

  describe('SO_NUMBER_EXISTS', () => {
    it('should reject duplicate SO number', async () => {
      // Create first trailer
      await request(httpServer)
        .post('/v1/trailers')
        .set('Authorization', `Bearer ${owner.token}`)
        .send({ soNumber: 'E2E-ERR-DUP-SO', trailerModelId: xpModelId })
        .expect(201);

      // Try to create a second trailer with the same SO number
      const res = await request(httpServer)
        .post('/v1/trailers')
        .set('Authorization', `Bearer ${owner.token}`)
        .send({ soNumber: 'E2E-ERR-DUP-SO', trailerModelId: xpModelId })
        .expect(409);

      expect(res.body.error.code).toBe('SO_NUMBER_EXISTS');
    });
  });

  // ── Role-based access ─────────────────────────────────────────────────────

  describe('Role-based access', () => {
    it('should reject trailer creation by worker role', async () => {
      const res = await request(httpServer)
        .post('/v1/trailers')
        .set('Authorization', `Bearer ${worker.token}`)
        .send({ soNumber: 'E2E-ERR-ROLE', trailerModelId: xpModelId })
        .expect(403);

      expect(res.body.error.code).toBe('FORBIDDEN');
    });

    it('should reject delivery creation by worker role', async () => {
      const res = await request(httpServer)
        .post('/v1/deliveries')
        .set('Authorization', `Bearer ${worker.token}`)
        .send({ trailerId: 1, deliveryType: 'single_pull' })
        .expect(403);

      expect(res.body.error.code).toBe('FORBIDDEN');
    });

    it('should reject audit log access by non-owner', async () => {
      const res = await request(httpServer)
        .get('/v1/admin/audit-log')
        .set('Authorization', `Bearer ${qcInspector.token}`)
        .expect(403);

      expect(res.body.error.code).toBe('FORBIDDEN');
    });
  });
});
