/**
 * QC REWORK E2E — QC fail → rework → re-inspect paths.
 *
 * 1. Single rework: QC_1 fails XP_JIG → XP_JIG rework at #1 priority
 *    → complete rework (0 pts) → QC_1 re-inspect passes → workflow continues.
 *
 * 2. Multi-rework: Same step fails QC 3 times before passing.
 *    Verify rework_count=3 and 0 points each time.
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

describe('QC Rework Workflow (e2e)', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let httpServer: any;
  let owner: TestUser;
  let qcInspector: TestUser;
  let worker: TestUser;
  let checklistItemMap: Map<string, number>;
  let xpModelId: number;
  let xpJigDeptId: number;

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

    const xpModel = await prisma.trailerModel.findFirst({
      where: { code: 'XP_14ET' },
      select: { id: true },
    });
    xpModelId = xpModel!.id;

    const xpJigDept = await prisma.department.findFirst({
      where: { code: 'XP_JIG' },
      select: { id: true },
    });
    xpJigDeptId = xpJigDept!.id;
  }, 60_000);

  afterAll(async () => {
    await cleanupTransactionalData(prisma);
    await ctx.app.close();
  });

  // ── Single QC Fail + Rework ───────────────────────────────────────────────

  describe('Single QC Fail + Rework', () => {
    it('should rework XP_JIG after QC_1 fail, then pass QC_1 and continue', async () => {
      // 1. Create XP trailer
      const createRes = await request(httpServer)
        .post('/v1/trailers')
        .set('Authorization', `Bearer ${owner.token}`)
        .send({ soNumber: 'E2E-REWORK-SINGLE', trailerModelId: xpModelId })
        .expect(201);
      const trailerId = BigInt(createRes.body.data.trailer.id);

      // 2. Complete step 1 (XP_JIG) — production step
      let active = await getActiveStep(prisma, trailerId);
      expect(active!.departmentCode).toBe('XP_JIG');
      await completeProductionStep(prisma, active!.id, worker.id, 5);

      // 3. QC_1 should now be active
      active = await getActiveStep(prisma, trailerId);
      expect(active!.departmentCode).toBe('QC_1');
      const qc1StepId = active!.id;

      // 4. QC_1 FAILS — routing to XP_JIG
      const failRes = await submitQcInspection(httpServer, qcInspector.token, {
        stepId: qc1StepId,
        result: 'fail',
        checklistItemId: checklistItemMap.get('QC_1')!,
        failNotes: 'Weld porosity detected on left rail',
        reworkTargetDepartmentId: xpJigDeptId,
      });

      expect(failRes.status).toBe(200);
      expect(failRes.body.data.result).toBe('fail');
      expect(failRes.body.data.reworkTargetDeptId).toBe(xpJigDeptId);
      expect(failRes.body.data.reworkQueuePosition).toBe(1);
      expect(failRes.body.data.notificationSentTo).toContain('production_manager');

      // 5. Verify XP_JIG is active with isRework=true at queue position 1
      const xpJigStep = await prisma.productionStep.findFirst({
        where: { trailerId, departmentId: xpJigDeptId },
        select: {
          id: true,
          status: true,
          isRework: true,
          reworkCount: true,
          queuePosition: true,
          stepOrder: true,
        },
      });

      expect(xpJigStep!.status).toBe('active');
      expect(xpJigStep!.isRework).toBe(true);
      expect(xpJigStep!.reworkCount).toBe(1);
      expect(xpJigStep!.queuePosition).toBe(1);
      expect(xpJigStep!.stepOrder).toBe(1); // Still step 1 in the workflow

      // 6. Complete XP_JIG rework — should award 0 points
      await completeProductionStep(prisma, xpJigStep!.id, worker.id, 5);

      const completedRework = await prisma.productionStep.findUnique({
        where: { id: xpJigStep!.id },
        select: { pointsAwarded: true },
      });
      expect(Number(completedRework!.pointsAwarded)).toBe(0); // Rework = 0 points

      // 7. QC_1 should be active again (re-inspection at normal queue position)
      active = await getActiveStep(prisma, trailerId);
      expect(active!.departmentCode).toBe('QC_1');

      // 8. QC_1 PASSES this time
      const passRes = await submitQcInspection(httpServer, qcInspector.token, {
        stepId: active!.id,
        result: 'pass',
        checklistItemId: checklistItemMap.get('QC_1')!,
      });

      expect(passRes.status).toBe(200);
      expect(passRes.body.data.result).toBe('pass');

      // 9. Workflow continues — XP_FIN (step 3) should now be active
      active = await getActiveStep(prisma, trailerId);
      expect(active!.departmentCode).toBe('XP_FIN');
      expect(active!.stepOrder).toBe(3);
    });
  });

  // ── Multi-Rework (3 consecutive fails) ────────────────────────────────────

  describe('Multi-Rework', () => {
    it('should handle 3 consecutive QC fails before passing, rework_count=3 with 0 points each', async () => {
      // Create XP trailer
      const createRes = await request(httpServer)
        .post('/v1/trailers')
        .set('Authorization', `Bearer ${owner.token}`)
        .send({ soNumber: 'E2E-MULTI-REWORK', trailerModelId: xpModelId })
        .expect(201);
      const trailerId = BigInt(createRes.body.data.trailer.id);

      // Complete XP_JIG (step 1) with 5 points
      let active = await getActiveStep(prisma, trailerId);
      await completeProductionStep(prisma, active!.id, worker.id, 5);

      // Fail QC_1 three times, each time routing back to XP_JIG
      for (let failNum = 1; failNum <= 3; failNum++) {
        // QC_1 is active
        active = await getActiveStep(prisma, trailerId);
        expect(active!.departmentCode).toBe('QC_1');

        // Fail QC_1 → route to XP_JIG
        const failRes = await submitQcInspection(
          httpServer,
          qcInspector.token,
          {
            stepId: active!.id,
            result: 'fail',
            checklistItemId: checklistItemMap.get('QC_1')!,
            failNotes: `Defect found — fail #${failNum}`,
            reworkTargetDepartmentId: xpJigDeptId,
          },
        );
        expect(failRes.status).toBe(200);

        // Verify rework step state
        const reworkStep = await prisma.productionStep.findFirst({
          where: { trailerId, departmentId: xpJigDeptId },
          select: {
            id: true,
            isRework: true,
            reworkCount: true,
            queuePosition: true,
          },
        });
        expect(reworkStep!.isRework).toBe(true);
        expect(reworkStep!.reworkCount).toBe(failNum);
        expect(reworkStep!.queuePosition).toBe(1); // Always #1 priority

        // Complete rework (should get 0 points despite passing 5)
        await completeProductionStep(prisma, reworkStep!.id, worker.id, 5);

        const completed = await prisma.productionStep.findUnique({
          where: { id: reworkStep!.id },
          select: { pointsAwarded: true },
        });
        expect(Number(completed!.pointsAwarded)).toBe(0);
      }

      // Verify final rework_count = 3
      const finalXpJig = await prisma.productionStep.findFirst({
        where: { trailerId, departmentId: xpJigDeptId },
        select: { reworkCount: true },
      });
      expect(finalXpJig!.reworkCount).toBe(3);

      // QC_1 should be active now — pass it this time
      active = await getActiveStep(prisma, trailerId);
      expect(active!.departmentCode).toBe('QC_1');

      const passRes = await submitQcInspection(httpServer, qcInspector.token, {
        stepId: active!.id,
        result: 'pass',
        checklistItemId: checklistItemMap.get('QC_1')!,
      });
      expect(passRes.status).toBe(200);
      expect(passRes.body.data.result).toBe('pass');

      // Workflow resumes normally — XP_FIN should be next
      active = await getActiveStep(prisma, trailerId);
      expect(active!.departmentCode).toBe('XP_FIN');

      // Verify total QC inspections against QC_1: 4 (3 fail + 1 pass)
      const qc1Step = await prisma.productionStep.findFirst({
        where: { trailerId, stepOrder: 2 },
        select: { id: true },
      });
      const inspections = await prisma.qcInspection.findMany({
        where: { productionStepId: qc1Step!.id },
        select: { result: true, attemptNumber: true },
        orderBy: { attemptNumber: 'asc' },
      });
      expect(inspections).toHaveLength(4);
      expect(inspections[0].result).toBe('fail');
      expect(inspections[1].result).toBe('fail');
      expect(inspections[2].result).toBe('fail');
      expect(inspections[3].result).toBe('pass');
      expect(inspections[3].attemptNumber).toBe(4);
    });
  });
});
