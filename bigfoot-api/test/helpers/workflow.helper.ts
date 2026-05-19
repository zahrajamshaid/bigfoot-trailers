/**
 * E2E Workflow Helpers — simulate production step completion (the production
 * controller is a TODO stub) and submit QC inspections via the real API.
 */
import * as request from 'supertest';
import { PrismaService } from '../../src/prisma/prisma.service';

// ── Types ───────────────────────────────────────────────────────────────────

export interface ActiveStepInfo {
  id: bigint;
  stepOrder: number;
  departmentId: number;
  departmentCode: string;
  isQcStep: boolean;
}

// ── Production step completion (DB-level simulation) ────────────────────────

/**
 * Simulates the not-yet-implemented POST /production/steps/:id/complete.
 *
 * 1. Marks the step as complete with the given userId and points.
 * 2. Activates the next step in the workflow (step_order + 1).
 * 3. Transitions the trailer from pending_production → in_production.
 *
 * Rework steps always award 0 points regardless of the `points` argument.
 */
export async function completeProductionStep(
  prisma: PrismaService,
  stepId: bigint,
  userId: bigint,
  points: number = 0,
): Promise<void> {
  const step = await prisma.productionStep.findUnique({
    where: { id: stepId },
    select: {
      id: true,
      status: true,
      isRework: true,
      trailerId: true,
      stepOrder: true,
      departmentId: true,
    },
  });

  if (!step) throw new Error(`Production step ${stepId} not found`);
  if (step.status !== 'active') {
    throw new Error(`Production step ${stepId} is not active (status: ${step.status})`);
  }

  const pointsToAward = step.isRework ? 0 : points;

  // Mark step complete
  await prisma.productionStep.update({
    where: { id: stepId },
    data: {
      status: 'complete' as any,
      completedByUserId: userId,
      completedAt: new Date(),
      pointsAwarded: pointsToAward,
    },
  });

  // Activate the next step in this trailer's workflow
  const nextStep = await prisma.productionStep.findFirst({
    where: { trailerId: step.trailerId, stepOrder: step.stepOrder + 1 },
    select: { id: true, departmentId: true },
  });

  if (nextStep) {
    const maxPos = await prisma.productionStep.aggregate({
      where: { departmentId: nextStep.departmentId, status: 'active' as any },
      _max: { queuePosition: true },
    });

    await prisma.productionStep.update({
      where: { id: nextStep.id },
      data: {
        status: 'active' as any,
        queuePosition: (maxPos._max.queuePosition ?? 0) + 1,
        becameActiveAt: new Date(),
      },
    });
  }

  // Transition trailer out of pending_production
  const trailer = await prisma.trailer.findUnique({
    where: { id: step.trailerId },
    select: { status: true },
  });
  if (trailer?.status === 'pending_production') {
    await prisma.trailer.update({
      where: { id: step.trailerId },
      data: { status: 'in_production' as any },
    });
  }
}

// ── Active step lookup ──────────────────────────────────────────────────────

/**
 * Returns the current active step for a trailer (lowest step_order if multiple
 * are active, e.g. during rework).  Returns null when all steps are complete.
 */
export async function getActiveStep(
  prisma: PrismaService,
  trailerId: bigint,
): Promise<ActiveStepInfo | null> {
  const step = await prisma.productionStep.findFirst({
    where: { trailerId, status: 'active' as any },
    select: {
      id: true,
      stepOrder: true,
      departmentId: true,
      department: { select: { code: true, isQcStep: true } },
    },
    orderBy: { stepOrder: 'asc' },
  });

  if (!step) return null;

  return {
    id: step.id,
    stepOrder: step.stepOrder,
    departmentId: step.departmentId,
    departmentCode: step.department.code,
    isQcStep: step.department.isQcStep,
  };
}

// ── QC inspection submission (via HTTP API) ─────────────────────────────────

/**
 * Submits a QC inspection through the real POST /v1/qc/inspections endpoint.
 * Returns the raw supertest Response so callers can assert on status + body.
 */
export async function submitQcInspection(
  httpServer: any,
  token: string,
  params: {
    stepId: bigint;
    result: 'pass' | 'fail';
    checklistItemId: number;
    failNotes?: string;
    reworkTargetDepartmentId?: number;
  },
): Promise<request.Response> {
  const body: Record<string, any> = {
    productionStepId: Number(params.stepId),
    result: params.result,
    checklistResults: [
      {
        checklistItemId: params.checklistItemId,
        passed: params.result === 'pass',
      },
    ],
    photoStorageKeys: ['e2e/test-photo.jpg'],
  };

  if (params.result === 'fail') {
    body.failNotes = params.failNotes ?? 'E2E test failure';
    body.reworkTargetDepartmentId = params.reworkTargetDepartmentId;
  }

  return request(httpServer)
    .post('/v1/qc/inspections')
    .set('Authorization', `Bearer ${token}`)
    .send(body);
}

// ── Full workflow completion ─────────────────────────────────────────────────

/**
 * Drives a trailer through all 12 steps:
 *   production complete → QC pass → production complete → QC pass → … → FINAL_QC pass.
 *
 * Production steps are completed via the DB helper (endpoint not yet built).
 * QC steps are completed via the real HTTP API.
 *
 * Returns the final trailer status (should be 'ready_for_delivery').
 */
export async function completeFullWorkflow(
  prisma: PrismaService,
  httpServer: any,
  trailerId: bigint,
  workerId: bigint,
  qcToken: string,
  checklistItemMap: Map<string, number>,
  pointsPerStep: number = 0,
): Promise<string> {
  for (let stepNum = 1; stepNum <= 12; stepNum++) {
    const active = await getActiveStep(prisma, trailerId);
    if (!active) {
      throw new Error(`No active step found at iteration ${stepNum}`);
    }

    if (active.isQcStep) {
      // QC step — submit pass through the real API
      const checklistItemId = checklistItemMap.get(active.departmentCode);
      if (!checklistItemId) {
        throw new Error(
          `No checklist item seeded for QC department ${active.departmentCode}`,
        );
      }

      const res = await submitQcInspection(httpServer, qcToken, {
        stepId: active.id,
        result: 'pass',
        checklistItemId,
      });

      if (res.status !== 200) {
        throw new Error(
          `QC pass failed at step ${stepNum} (${active.departmentCode}): ${JSON.stringify(res.body)}`,
        );
      }
    } else {
      // Production step — complete via DB
      await completeProductionStep(prisma, active.id, workerId, pointsPerStep);
    }
  }

  const trailer = await prisma.trailer.findUnique({
    where: { id: trailerId },
    select: { status: true },
  });

  return trailer?.status ?? 'unknown';
}
