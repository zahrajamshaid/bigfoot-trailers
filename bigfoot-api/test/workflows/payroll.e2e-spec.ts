/**
 * PAYROLL E2E — Points aggregation and week locking.
 *
 * Complete multiple trailers with different models/workers in the same week,
 * then verify weekly report aggregation and payroll locking.
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

/** Returns the current week's Sunday as YYYY-MM-DD. */
function getCurrentWeekSunday(): string {
  const now = new Date();
  const dayOfWeek = now.getUTCDay();
  const sunday = new Date(
    Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate() - dayOfWeek,
    ),
  );
  return sunday.toISOString().split('T')[0];
}

describe('Payroll Aggregation (e2e)', () => {
  let ctx: TestContext;
  let prisma: PrismaService;
  let httpServer: any;
  let owner: TestUser;
  let qcInspector: TestUser;
  let workerAlpha: TestUser;
  let workerBeta: TestUser;
  let checklistItemMap: Map<string, number>;
  let xpModelId: number;
  let yetiModelId: number;
  let weekStart: string;

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
    workerAlpha = await createAndLogin(prisma, httpServer, 'worker', {
      fullName: 'Worker Alpha',
    });
    workerBeta = await createAndLogin(prisma, httpServer, 'worker', {
      fullName: 'Worker Beta',
    });

    const models = await prisma.trailerModel.findMany({
      select: { id: true, code: true },
    });
    const modelMap = new Map(models.map((m) => [m.code, m.id]));
    xpModelId = modelMap.get('XP_14ET')!;
    yetiModelId = modelMap.get('YETI_15K')!;

    weekStart = getCurrentWeekSunday();
  }, 60_000);

  afterAll(async () => {
    await cleanupTransactionalData(prisma);
    await ctx.app.close();
  });

  // ── Weekly production report aggregation ──────────────────────────────────

  it('should aggregate points across multiple trailers per worker', async () => {
    // Worker Alpha completes 2 XP trailers (5 pts per production step)
    for (let i = 1; i <= 2; i++) {
      const res = await request(httpServer)
        .post('/v1/trailers')
        .set('Authorization', `Bearer ${owner.token}`)
        .send({ soNumber: `E2E-PAYROLL-A${i}`, trailerModelId: xpModelId })
        .expect(201);

      const trailerId = BigInt(res.body.data.trailer.id);
      await completeFullWorkflow(
        prisma, httpServer, trailerId, workerAlpha.id,
        qcInspector.token, checklistItemMap, 5,
      );
    }

    // Worker Beta completes 1 Yeti trailer (3 pts per production step)
    const yetiRes = await request(httpServer)
      .post('/v1/trailers')
      .set('Authorization', `Bearer ${owner.token}`)
      .send({ soNumber: 'E2E-PAYROLL-B1', trailerModelId: yetiModelId })
      .expect(201);

    const yetiTrailerId = BigInt(yetiRes.body.data.trailer.id);
    await completeFullWorkflow(
      prisma, httpServer, yetiTrailerId, workerBeta.id,
      qcInspector.token, checklistItemMap, 3,
    );

    // GET /payroll/records/week/:week_start
    const reportRes = await request(httpServer)
      .get(`/v1/payroll/records/week/${weekStart}`)
      .set('Authorization', `Bearer ${owner.token}`)
      .expect(200);

    const report = reportRes.body.data;
    expect(report.weekStartDate).toBe(weekStart);
    expect(report.isLocked).toBe(false);

    // Worker Alpha: 2 trailers × 6 production steps × 5 pts = 60 total points
    const wAlpha = report.workers.find(
      (w: any) => w.fullName === 'Worker Alpha',
    );
    expect(wAlpha).toBeTruthy();
    expect(wAlpha.totalPoints).toBe(60);
    expect(wAlpha.totalStepsCompleted).toBe(12); // 6 prod × 2 trailers

    // Worker Beta: 1 trailer × 6 production steps × 3 pts = 18 total points
    const wBeta = report.workers.find(
      (w: any) => w.fullName === 'Worker Beta',
    );
    expect(wBeta).toBeTruthy();
    expect(wBeta.totalPoints).toBe(18);
    expect(wBeta.totalStepsCompleted).toBe(6);

    // Report is sorted by totalPoints descending
    const workerPoints = report.workers.map((w: any) => w.totalPoints);
    const sorted = [...workerPoints].sort((a: number, b: number) => b - a);
    expect(workerPoints).toEqual(sorted);
  });

  // ── Payroll week lock ─────────────────────────────────────────────────────

  it('should lock the week and generate payroll records', async () => {
    // Lock the week (trailers completed above are in this week)
    const lockRes = await request(httpServer)
      .post(`/v1/payroll/records/lock/${weekStart}`)
      .set('Authorization', `Bearer ${owner.token}`)
      .expect(200);

    expect(lockRes.body.data.isLocked).toBe(true);
    expect(lockRes.body.data.recordsLocked).toBeGreaterThan(0);

    // Verify the weekly report now shows isLocked = true
    const reportRes = await request(httpServer)
      .get(`/v1/payroll/records/week/${weekStart}`)
      .set('Authorization', `Bearer ${owner.token}`)
      .expect(200);

    expect(reportRes.body.data.isLocked).toBe(true);
    expect(reportRes.body.data.lockedBy).toBeTruthy();

    // Verify payroll records were created in the database
    const records = await prisma.payrollRecord.findMany({
      where: { weekStartDate: new Date(weekStart) },
      select: {
        userId: true,
        totalPoints: true,
        trailersCompleted: true,
        isLocked: true,
      },
    });
    expect(records.length).toBeGreaterThan(0);
    expect(records.every((r) => r.isLocked === true)).toBe(true);

    // Worker Alpha should have records for each department worked
    const alphaRecords = records.filter(
      (r) => Number(r.userId) === Number(workerAlpha.id),
    );
    expect(alphaRecords.length).toBeGreaterThan(0);
    const alphaTotalPoints = alphaRecords.reduce(
      (sum, r) => sum + Number(r.totalPoints),
      0,
    );
    expect(alphaTotalPoints).toBe(60);
  });

  // ── PAYROLL_WEEK_LOCKED error ─────────────────────────────────────────────

  it('should reject re-locking an already locked week', async () => {
    const res = await request(httpServer)
      .post(`/v1/payroll/records/lock/${weekStart}`)
      .set('Authorization', `Bearer ${owner.token}`)
      .expect(400);

    expect(res.body.error.code).toBe('PAYROLL_WEEK_LOCKED');
  });

  // ── INVALID_WEEK_START error ──────────────────────────────────────────────

  it('should reject non-Sunday week start', async () => {
    // Pick a Monday
    const monday = new Date(weekStart);
    monday.setUTCDate(monday.getUTCDate() + 1);
    const mondayStr = monday.toISOString().split('T')[0];

    const res = await request(httpServer)
      .get(`/v1/payroll/records/week/${mondayStr}`)
      .set('Authorization', `Bearer ${owner.token}`)
      .expect(400);

    expect(res.body.error.code).toBe('INVALID_WEEK_START');
  });
});
