import { Injectable } from '@nestjs/common';
import {
  Prisma,
  ProductionStepStatus,
  QcSeriesScope,
  TrailerStatus,
} from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { AppError } from '../../common/errors/app-error';
import { ErrorCode } from '../../common/errors/error-codes';
import { StepCheckResultDto } from './dto/complete-step.dto';

@Injectable()
export class ProductionService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsService: NotificationsService,
  ) {}

  // =========================================================================
  // GET /production/departments
  // =========================================================================
  async getDepartments() {
    return this.prisma.department.findMany({
      orderBy: { id: 'asc' },
    });
  }

  // =========================================================================
  // GET /production/stalled-count
  // =========================================================================
  // Counts unresolved StallAlerts. Returns a single { count } object so the
  // dashboard tile can render `0` without juggling shapes when nothing is
  // stalled. Cheap (one indexed COUNT) — safe to fan-out from the dashboard.
  async getStalledCount(): Promise<{ count: number }> {
    const count = await this.prisma.stallAlert.count({
      where: { resolvedAt: null },
    });
    return { count };
  }

  // =========================================================================
  // GET /production/queue/:dept_id
  // =========================================================================
  async getQueueByDepartment(deptId: number, includeWaiting = false) {
    // Verify department exists
    const dept = await this.prisma.department.findUnique({
      where: { id: deptId },
    });
    if (!dept) throw new AppError(ErrorCode.NOT_FOUND, 'Department not found');

    return this._buildQueueItems(deptId, includeWaiting);
  }

  // =========================================================================
  // GET /production/queue/all
  // =========================================================================
  async getAllQueues() {
    const departments = await this.prisma.department.findMany({
      where: { isQcStep: false },
      orderBy: { id: 'asc' },
    });

    const result: Record<string, unknown>[] = [];
    for (const dept of departments) {
      const items = await this._buildQueueItems(dept.id);
      result.push({
        departmentId: dept.id,
        departmentName: dept.displayName,
        departmentCode: dept.code,
        queue: items,
      });
    }
    return result;
  }

  // =========================================================================
  // GET /production/trailers/:trailer_id/upstream-checks
  // Aggregated worker self-check results for every completed non-QC step on
  // this trailer. Surfaced to the QC manager during inspection.
  // =========================================================================
  async getUpstreamChecksForTrailer(trailerId: bigint) {
    return this.prisma.productionStepCheck.findMany({
      where: {
        productionStep: {
          trailerId,
          department: { isQcStep: false },
        },
      },
      select: {
        id: true,
        passed: true,
        note: true,
        createdAt: true,
        checklistItem: {
          select: { id: true, itemLabel: true, sortOrder: true },
        },
        checkedByUser: { select: { id: true, fullName: true } },
        productionStep: {
          select: {
            id: true,
            completedAt: true,
            department: {
              select: { id: true, code: true, displayName: true },
            },
          },
        },
      },
      orderBy: [
        { productionStep: { department: { id: 'asc' } } },
        { checklistItem: { sortOrder: 'asc' } },
      ],
    });
  }

  // =========================================================================
  // GET /production/steps/:step_id/checklist-items
  // Upstream self-check items for the step's department, filtered by the
  // trailer's series + addons (same pattern used by QcService).
  // =========================================================================
  async getChecklistItemsForStep(stepId: bigint) {
    const step = await this.prisma.productionStep.findUnique({
      where: { id: stepId },
      select: {
        id: true,
        departmentId: true,
        department: { select: { isQcStep: true } },
        trailer: {
          select: {
            trailerModel: { select: { series: true } },
            addons: { select: { addonName: true } },
          },
        },
      },
    });
    if (!step) throw new AppError(ErrorCode.NOT_FOUND, 'Production step not found');

    // QC steps manage their checklist through /qc/checklist-items.
    if (step.department.isQcStep) return [];

    const series = step.trailer.trailerModel.series as unknown as QcSeriesScope;
    const addonKeys = step.trailer.addons.map((a) => a.addonName);

    const addonClauses: Prisma.QcChecklistItemWhereInput[] = [{ requiresAddonKey: null }];
    if (addonKeys.length > 0) {
      addonClauses.push({ requiresAddonKey: '*' });
      addonClauses.push({ requiresAddonKey: { in: addonKeys } });
    }

    return this.prisma.qcChecklistItem.findMany({
      where: {
        departmentId: step.departmentId,
        isActive: true,
        appliesToSeries: { in: [series, QcSeriesScope.all] },
        OR: addonClauses,
      },
      select: {
        id: true,
        departmentId: true,
        appliesToSeries: true,
        itemLabel: true,
        sortOrder: true,
        requiresAddonKey: true,
      },
      orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
    });
  }

  // =========================================================================
  // POST /production/steps/:step_id/complete
  // =========================================================================
  async completeStep(
    stepId: bigint,
    completedByUserId: bigint,
    notes?: string,
    checklistResults?: StepCheckResultDto[],
  ) {
    const step = await this.prisma.productionStep.findUnique({
      where: { id: stepId },
      include: {
        trailer: {
          include: {
            trailerModel: true,
            addons: { select: { addonName: true } },
          },
        },
        department: true,
      },
    });

    if (!step) throw new AppError(ErrorCode.NOT_FOUND, 'Production step not found');
    if (step.status === ProductionStepStatus.complete) {
      throw new AppError(ErrorCode.STEP_ALREADY_COMPLETE);
    }
    if (step.status !== ProductionStepStatus.active) {
      throw new AppError(ErrorCode.STEP_NOT_ACTIVE);
    }

    // ── Worker self-check validation ────────────────────────────────────────
    // If the step's department has active upstream checklist items for this
    // trailer's series/addons, every one must be answered. Results are stored
    // in production_step_checks and become visible to the QC manager.
    const expectedItems = step.department.isQcStep
      ? []
      : await this.prisma.qcChecklistItem.findMany({
          where: {
            departmentId: step.departmentId,
            isActive: true,
            appliesToSeries: {
              in: [
                step.trailer.trailerModel.series as unknown as QcSeriesScope,
                QcSeriesScope.all,
              ],
            },
            OR: (() => {
              const addonKeys = step.trailer.addons.map((a) => a.addonName);
              const clauses: Prisma.QcChecklistItemWhereInput[] = [
                { requiresAddonKey: null },
              ];
              if (addonKeys.length > 0) {
                clauses.push({ requiresAddonKey: '*' });
                clauses.push({ requiresAddonKey: { in: addonKeys } });
              }
              return clauses;
            })(),
          },
          select: { id: true },
        });

    const answered = new Set((checklistResults ?? []).map((r) => r.checklistItemId));
    const missing = expectedItems.filter((i) => !answered.has(i.id));
    if (missing.length > 0) {
      throw new AppError(
        ErrorCode.QC_CHECKLIST_INCOMPLETE,
        `Missing self-check results for items: ${missing.map((i) => i.id).join(', ')}`,
      );
    }

    // Look up points for this model + department (0 for rework)
    let pointsAwarded = 0;
    if (!step.isRework) {
      const pointValue = await this.prisma.pointValue.findFirst({
        where: {
          trailerModelId: step.trailer.trailerModelId,
          departmentId: step.departmentId,
          effectiveFrom: { lte: new Date() },
          OR: [{ effectiveTo: null }, { effectiveTo: { gte: new Date() } }],
        },
        orderBy: { effectiveFrom: 'desc' },
      });
      if (pointValue) {
        pointsAwarded = Number(pointValue.points);
      }
    }

    // Completion always advances by workflow template order from the current
    // step position. For rework steps this means re-entering the normal flow
    // from that department forward (e.g. XP_JIG -> QC_1 -> XP_FIN ...).
    const nextTemplate = await this.prisma.workflowTemplate.findFirst({
      where: {
        series: step.trailer.trailerModel.series,
        stepOrder: { gt: step.stepOrder },
      },
      orderBy: { stepOrder: 'asc' },
      include: { department: true },
    });

    // Execute in transaction
    const result = await this.prisma.$transaction(async (tx) => {
      // 1. Mark step complete
      await tx.productionStep.update({
        where: { id: stepId },
        data: {
          status: ProductionStepStatus.complete,
          completedAt: new Date(),
          completedByUserId,
          pointsAwarded: new Prisma.Decimal(pointsAwarded),
        },
      });

      // 1b. Persist worker self-check results (upsert in case of retry)
      if (checklistResults && checklistResults.length > 0) {
        for (const r of checklistResults) {
          await tx.productionStepCheck.upsert({
            where: {
              productionStepId_checklistItemId: {
                productionStepId: stepId,
                checklistItemId: r.checklistItemId,
              },
            },
            create: {
              productionStepId: stepId,
              checklistItemId: r.checklistItemId,
              passed: r.passed,
              note: r.note ?? null,
              checkedByUserId: completedByUserId,
            },
            update: {
              passed: r.passed,
              note: r.note ?? null,
              checkedByUserId: completedByUserId,
            },
          });
        }
      }

      // 2. Resolve any stall alerts for this step
      await tx.stallAlert.updateMany({
        where: { productionStepId: stepId, resolvedAt: null },
        data: { resolvedAt: new Date() },
      });

      let nextStepId: bigint | null = null;
      let nextDepartmentName: string | null = null;
      let nextDepartmentId: number | null = null;

      if (nextTemplate) {
        // Find or create the next production step for this trailer
        const existingNext = await tx.productionStep.findFirst({
          where: {
            trailerId: step.trailerId,
            departmentId: nextTemplate.departmentId,
            stepOrder: nextTemplate.stepOrder,
          },
        });

        const canActivateExisting =
          existingNext &&
          (existingNext.status === ProductionStepStatus.waiting ||
            (step.isRework && existingNext.status === ProductionStepStatus.complete));

        if (canActivateExisting) {
          // Activate (or reopen) the next step.
          // Rework path may reopen a previously completed step so the trailer
          // can re-enter the queue from this point in the workflow.
          const maxPos = await tx.productionStep.aggregate({
            where: {
              departmentId: nextTemplate.departmentId,
              status: ProductionStepStatus.active,
            },
            _max: { queuePosition: true },
          });

          await tx.productionStep.update({
            where: { id: existingNext.id },
            data: {
              status: ProductionStepStatus.active,
              becameActiveAt: new Date(),
              queuePosition: (maxPos._max.queuePosition ?? 0) + 1,
              completedAt: null,
              completedByUserId: null,
              // If we reopened a previously completed step, clear old points.
              pointsAwarded:
                existingNext.status === ProductionStepStatus.complete
                  ? new Prisma.Decimal(0)
                  : undefined,
            },
          });
          nextStepId = existingNext.id;
        }

        nextDepartmentName = nextTemplate.department.displayName;
        nextDepartmentId = nextTemplate.departmentId;
      }

      // 3. Update trailer status if this was the final step
      let trailerStatus = step.trailer.status;
      if (!nextTemplate) {
        trailerStatus = TrailerStatus.ready_for_delivery;
        await tx.trailer.update({
          where: { id: step.trailerId },
          data: { status: TrailerStatus.ready_for_delivery },
        });
      } else if (step.trailer.status === TrailerStatus.pending_production) {
        trailerStatus = TrailerStatus.in_production;
        await tx.trailer.update({
          where: { id: step.trailerId },
          data: { status: TrailerStatus.in_production },
        });
      }

      return {
        completedStepId: Number(stepId),
        pointsAwarded,
        nextStepId: nextStepId ? Number(nextStepId) : null,
        nextDepartment: nextDepartmentName,
        trailerStatus,
        // For notifications
        _nextDepartmentId: nextDepartmentId,
        _nextStepId: nextStepId,
      };
    });

    // Fire notifications (outside transaction)
    await this.notificationsService.onStepCompleted({
      stepId,
      trailerId: step.trailerId,
      soNumber: step.trailer.soNumber,
      departmentId: step.departmentId,
      departmentName: step.department.displayName,
      nextStepId: result._nextStepId,
      nextDepartmentId: result._nextDepartmentId,
      nextDepartmentName: result.nextDepartment,
      nextDepartmentIsQc: nextTemplate?.department.isQcStep ?? false,
      completedByUserId,
      pointsAwarded,
    });

    // When a jig step finishes, the trailer leaves the jig queue. Check the
    // remaining count and ping production managers if the line is running
    // thin — they need to enter more work orders before the welders run dry.
    await this.notificationsService.onPossibleJigQueueLow(step.departmentId);

    if (pointsAwarded > 0) {
      this.notificationsService.onPointsUpdated({
        userId: completedByUserId,
        trailerId: step.trailerId,
        soNumber: step.trailer.soNumber,
        departmentName: step.department.displayName,
        pointsAwarded,
      });
    }

    // Return only the fields the mobile app expects
    return {
      completedStepId: result.completedStepId,
      pointsAwarded: result.pointsAwarded,
      nextStepId: result.nextStepId,
      nextDepartment: result.nextDepartment,
      trailerStatus: result.trailerStatus,
    };
  }

  // =========================================================================
  // POST /production/steps/:step_id/reverse
  // =========================================================================
  async reverseStep(stepId: bigint, reversedByUserId: bigint, userRole: string) {
    const step = await this.prisma.productionStep.findUnique({
      where: { id: stepId },
      include: {
        trailer: true,
        department: true,
      },
    });

    if (!step) throw new AppError(ErrorCode.NOT_FOUND, 'Production step not found');
    if (step.status !== ProductionStepStatus.complete) {
      throw new AppError(
        ErrorCode.STEP_NOT_ACTIVE,
        'Only completed steps can be reversed',
      );
    }

    // Authorization: only the completing worker or a manager/owner can reverse
    const isManagerOrOwner = userRole === 'production_manager' || userRole === 'owner';
    if (!isManagerOrOwner && step.completedByUserId !== reversedByUserId) {
      throw new AppError(ErrorCode.STEP_REVERSAL_NOT_AUTHORIZED);
    }

    await this.prisma.$transaction(async (tx) => {
      // Get max queue position in this department
      const maxPos = await tx.productionStep.aggregate({
        where: {
          departmentId: step.departmentId,
          status: ProductionStepStatus.active,
        },
        _max: { queuePosition: true },
      });

      // Re-activate the step
      await tx.productionStep.update({
        where: { id: stepId },
        data: {
          status: ProductionStepStatus.active,
          completedAt: null,
          completedByUserId: null,
          pointsAwarded: new Prisma.Decimal(0),
          becameActiveAt: new Date(),
          queuePosition: (maxPos._max.queuePosition ?? 0) + 1,
        },
      });

      // Record the reversal
      await tx.stepReversal.create({
        data: {
          productionStepId: stepId,
          reversedByUserId,
        },
      });

      // If a next step was activated, set it back to waiting
      const nextStep = await tx.productionStep.findFirst({
        where: {
          trailerId: step.trailerId,
          stepOrder: { gt: step.stepOrder },
          status: ProductionStepStatus.active,
        },
        orderBy: { stepOrder: 'asc' },
      });

      if (nextStep) {
        await tx.productionStep.update({
          where: { id: nextStep.id },
          data: {
            status: ProductionStepStatus.waiting,
            becameActiveAt: null,
            queuePosition: null,
          },
        });
      }
    });

    // Fire notification
    await this.notificationsService.onStepReversed({
      stepId,
      trailerId: step.trailerId,
      soNumber: step.trailer.soNumber,
      departmentId: step.departmentId,
      departmentName: step.department.displayName,
      reversedByUserId,
    });

    return { success: true };
  }

  // =========================================================================
  // POST /production/trailers/:trailer_id/jump-to-step
  //
  // Admin override that places the trailer at an arbitrary production step.
  // Earlier steps are coerced to `complete`, the target becomes `active`,
  // later steps are reset to `waiting`. Used when the physical state of a
  // trailer drifts from what the workflow has recorded (e.g. a step was
  // tapped on the wrong trailer, or work happened off-app and needs to be
  // back-filled).
  // =========================================================================
  async jumpToStep(
    trailerId: bigint,
    targetStepId: bigint,
    adminUserId: bigint,
    reason?: string,
  ) {
    const target = await this.prisma.productionStep.findUnique({
      where: { id: targetStepId },
      include: {
        trailer: { select: { id: true, soNumber: true, status: true } },
        department: { select: { id: true, displayName: true, isQcStep: true } },
      },
    });
    if (!target) {
      throw new AppError(ErrorCode.NOT_FOUND, 'Production step not found');
    }
    if (target.trailerId !== trailerId) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `Step ${targetStepId} does not belong to trailer ${trailerId}`,
      );
    }

    const allSteps = await this.prisma.productionStep.findMany({
      where: { trailerId },
      orderBy: { stepOrder: 'asc' },
    });
    if (allSteps.length === 0) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Trailer ${trailerId} has no production steps`,
      );
    }

    const upstream = allSteps.filter((s) => s.stepOrder < target.stepOrder);
    const downstream = allSteps.filter((s) => s.stepOrder > target.stepOrder);

    // Reversal records get one row per rolled-back step so the trailer
    // history shows every change the admin override made.
    const rolledBackStepIds: bigint[] = downstream
      .filter((s) => s.status !== ProductionStepStatus.waiting)
      .map((s) => s.id);

    // Forward jump: any upstream step that wasn't already complete will be
    // forced complete. Workers in those departments need a WS push so their
    // queue screens drop the trailer immediately.
    const forcedCompleteUpstreamIds: bigint[] = upstream
      .filter((s) => s.status !== ProductionStepStatus.complete)
      .map((s) => s.id);

    // Pre-fetch every department name involved in this jump so each WS event
    // carries the correct department name (not the target's).
    const affectedDeptIds = new Set<number>([
      target.departmentId,
      ...downstream.map((s) => s.departmentId),
      ...upstream.map((s) => s.departmentId),
    ]);
    const deptRows = await this.prisma.department.findMany({
      where: { id: { in: [...affectedDeptIds] } },
      select: { id: true, displayName: true },
    });
    const deptNameById = new Map<number, string>(
      deptRows.map((d) => [d.id, d.displayName]),
    );

    const now = new Date();

    await this.prisma.$transaction(async (tx) => {
      // Steps before the target: anything not already complete becomes
      // complete-by-admin-override (no points, admin recorded as completer).
      // Already-complete steps are left alone so real completion history
      // (worker, timestamp, points) is preserved.
      for (const s of upstream) {
        if (s.status === ProductionStepStatus.complete) continue;
        await tx.productionStep.update({
          where: { id: s.id },
          data: {
            status: ProductionStepStatus.complete,
            completedAt: now,
            completedByUserId: adminUserId,
            queuePosition: null,
            becameActiveAt: s.becameActiveAt ?? now,
            pointsAwarded: new Prisma.Decimal(0),
          },
        });
      }

      // Target step: activate (or reactivate if previously complete).
      const maxPos = await tx.productionStep.aggregate({
        where: {
          departmentId: target.departmentId,
          status: ProductionStepStatus.active,
          id: { not: target.id },
        },
        _max: { queuePosition: true },
      });

      await tx.productionStep.update({
        where: { id: target.id },
        data: {
          status: ProductionStepStatus.active,
          becameActiveAt: now,
          queuePosition: (maxPos._max.queuePosition ?? 0) + 1,
          completedAt: null,
          completedByUserId: null,
          pointsAwarded: new Prisma.Decimal(0),
        },
      });

      // Steps after the target: reset to waiting and record a reversal row
      // for each one that was active or complete (so the rollback is visible
      // in the trailer history tab).
      for (const s of downstream) {
        if (s.status !== ProductionStepStatus.waiting) {
          await tx.stepReversal.create({
            data: {
              productionStepId: s.id,
              reversedByUserId: adminUserId,
              reason: reason ?? `Admin jump to step ${target.stepOrder}`,
            },
          });
          await tx.productionStep.update({
            where: { id: s.id },
            data: {
              status: ProductionStepStatus.waiting,
              completedAt: null,
              completedByUserId: null,
              becameActiveAt: null,
              queuePosition: null,
              pointsAwarded: new Prisma.Decimal(0),
            },
          });
        }
      }

      // Resolve any open stall alerts on the new active step — its clock
      // has just been reset.
      await tx.stallAlert.updateMany({
        where: { productionStepId: target.id, resolvedAt: null },
        data: { resolvedAt: now },
      });

      // Trailer status follows the new active step. Anything past
      // pending_production gets pulled back to in_production since the
      // trailer is no longer at its previous workflow checkpoint.
      const nextTrailerStatus =
        target.trailer.status === TrailerStatus.delivered
          ? TrailerStatus.in_production
          : TrailerStatus.in_production;
      if (target.trailer.status !== nextTrailerStatus) {
        await tx.trailer.update({
          where: { id: trailerId },
          data: { status: nextTrailerStatus },
        });
      }

      await tx.auditLog.create({
        data: {
          userId: adminUserId,
          entityType: 'trailer',
          entityId: trailerId,
          action: 'trailer.jumped_to_step',
          oldValues: {
            previouslyActiveStepIds: allSteps
              .filter((s) => s.status === ProductionStepStatus.active)
              .map((s) => s.id.toString()),
          },
          newValues: {
            targetStepId: target.id.toString(),
            targetStepOrder: target.stepOrder,
            departmentId: target.departmentId,
            departmentName: target.department.displayName,
            rolledBackStepIds: rolledBackStepIds.map((id) => id.toString()),
            reason: reason ?? null,
          },
        },
      });
    });

    // Notifications outside the transaction — reuse the existing
    // step-completed / step-reversed events so any open queue or trailer
    // detail screens refresh. Each event is routed to the *affected* dept
    // (not the target's), so workers in every involved queue get a push.
    await this.notificationsService.onStepCompleted({
      stepId: target.id,
      trailerId,
      soNumber: target.trailer.soNumber,
      departmentId: target.departmentId,
      departmentName: target.department.displayName,
      nextStepId: target.id,
      nextDepartmentId: target.departmentId,
      nextDepartmentName: target.department.displayName,
      nextDepartmentIsQc: target.department.isQcStep,
      completedByUserId: adminUserId,
      pointsAwarded: 0,
    });

    // Departments whose queues lost the trailer (downstream rollback OR
    // upstream forced-complete) get a STEP_REVERSED push so their open queue
    // screens drop the entry. We dedupe by departmentId so each dept gets a
    // single push even if multiple of its steps changed.
    const droppedFromDeptIds = new Set<number>();
    for (const s of downstream) {
      if (rolledBackStepIds.includes(s.id)) droppedFromDeptIds.add(s.departmentId);
    }
    for (const s of upstream) {
      if (
        forcedCompleteUpstreamIds.includes(s.id) &&
        s.status === ProductionStepStatus.active
      ) {
        droppedFromDeptIds.add(s.departmentId);
      }
    }
    droppedFromDeptIds.delete(target.departmentId); // already covered above

    for (const deptId of droppedFromDeptIds) {
      // Pick a representative stepId from this dept for the payload (the
      // event consumer cares about dept + trailer, not the specific stepId).
      const stepInDept =
        downstream.find((s) => s.departmentId === deptId) ??
        upstream.find((s) => s.departmentId === deptId);
      if (!stepInDept) continue;

      await this.notificationsService.onStepReversed({
        stepId: stepInDept.id,
        trailerId,
        soNumber: target.trailer.soNumber,
        departmentId: deptId,
        departmentName: deptNameById.get(deptId) ?? '',
        reversedByUserId: adminUserId,
      });
    }

    return {
      success: true,
      activeStepId: Number(target.id),
      targetDepartment: target.department.displayName,
      rolledBackStepIds: rolledBackStepIds.map((id) => Number(id)),
    };
  }

  // =========================================================================
  // PATCH /production/queue/:dept_id/reorder
  // =========================================================================
  async reorderQueue(deptId: number, stepIds: number[]) {
    const dept = await this.prisma.department.findUnique({
      where: { id: deptId },
    });
    if (!dept) throw new AppError(ErrorCode.NOT_FOUND, 'Department not found');

    // Update queue positions atomically
    await this.prisma.$transaction(
      stepIds.map((id, index) =>
        this.prisma.productionStep.update({
          where: { id: BigInt(id) },
          data: { queuePosition: index + 1 },
        }),
      ),
    );

    this.notificationsService.onQueueReordered({
      departmentId: deptId,
      departmentName: dept.displayName,
    });

    return { success: true };
  }

  // =========================================================================
  // Private helpers
  // =========================================================================

  /** Build the queue item response for a department. */
  private async _buildQueueItems(deptId: number, includeWaiting = false) {
    const statuses = includeWaiting
      ? [ProductionStepStatus.active, ProductionStepStatus.waiting]
      : [ProductionStepStatus.active];

    const steps = await this.prisma.productionStep.findMany({
      where: {
        departmentId: deptId,
        status: { in: statuses },
      },
      include: {
        trailer: {
          include: {
            trailerModel: true,
            customer: true,
          },
        },
        // stallThresholdHours travels with each queue item so the mobile
        // tile renders against the live dept setting instead of a baked-in
        // 24/48h. Admin edits to the dept's threshold show up next refresh.
        department: {
          select: { code: true, displayName: true, stallThresholdHours: true },
        },
        reworkedFromInspections: {
          orderBy: { inspectedAt: 'desc' },
          take: 1,
          select: { failNotes: true },
        },
      },
      // Primary sort still keeps `active` ahead of `waiting`; everything
      // else is decided by the tiered post-fetch comparator below so the
      // mobile + any future tool gets the same priority order out of the
      // box, without each client re-implementing it.
      orderBy: [
        { status: 'asc' },
        { queuePosition: 'asc' },
        { trailer: { globalPriority: 'asc' } },
      ],
    });

    // For waiting items, resolve the trailer's currently-active step so
    // the UI can show "currently at: <upstream stage>".
    const waitingTrailerIds = steps
      .filter((s) => s.status === ProductionStepStatus.waiting)
      .map((s) => s.trailerId);

    const currentStageByTrailer = new Map<string, { code: string; name: string }>();
    if (waitingTrailerIds.length > 0) {
      const activeSteps = await this.prisma.productionStep.findMany({
        where: {
          trailerId: { in: waitingTrailerIds },
          status: ProductionStepStatus.active,
        },
        include: {
          department: { select: { code: true, displayName: true } },
        },
      });
      for (const s of activeSteps) {
        currentStageByTrailer.set(s.trailerId.toString(), {
          code: s.department.code,
          name: s.department.displayName,
        });
      }
    }

    const now = new Date();

    const items = steps.map((step) => {
      const hoursInQueue = step.becameActiveAt
        ? (now.getTime() - step.becameActiveAt.getTime()) / (1000 * 60 * 60)
        : null;

      const reworkFailNotes = step.isRework
        ? (step.reworkedFromInspections[0]?.failNotes ?? null)
        : null;

      const isActive = step.status === ProductionStepStatus.active;
      const currentStage = isActive
        ? { code: step.department.code, name: step.department.displayName }
        : (currentStageByTrailer.get(step.trailerId.toString()) ?? null);

      const threshold = step.department.stallThresholdHours || 48;
      const stallLevel =
        hoursInQueue == null
          ? 0
          : hoursInQueue >= threshold * 2
            ? 2
            : hoursInQueue >= threshold
              ? 1
              : 0;

      return {
        stepId: step.id,
        trailerId: step.trailerId,
        soNumber: step.trailer.soNumber,
        modelName: step.trailer.trailerModel.displayName,
        series: step.trailer.trailerModel.series,
        color: step.trailer.color,
        sizeFt: step.trailer.sizeFt,
        customerName: step.trailer.customer?.name ?? null,
        optionsNotes: step.trailer.optionsNotes,
        qbSoPdfUrl: step.trailer.qbSoPdfStorageUrl,
        qbSoPdfStorageKey: step.trailer.qbSoPdfStorageKey,
        isHot: step.trailer.isHot,
        isRework: step.isRework,
        reworkCount: step.reworkCount,
        reworkFailNotes,
        queuePosition: step.queuePosition ?? 0,
        becameActiveAt: step.becameActiveAt,
        hoursInQueue: hoursInQueue ? Math.round(hoursInQueue * 100) / 100 : null,
        globalPriority: step.trailer.globalPriority,
        status: step.status,
        currentStageCode: currentStage?.code ?? null,
        currentStageName: currentStage?.name ?? null,
        stallThresholdHours: step.department.stallThresholdHours,
        // Internal — used only for the tiered sort below, not returned in
        // the API shape (Nest strips fields that don't appear in the DTO,
        // and existing clients don't care).
        _stallLevel: stallLevel,
      };
    });

    // Tiered priority sort applied server-side so every client renders the
    // same order regardless of how recent its build is:
    //   1. status — `active` always ahead of `waiting`;
    //   2. rework trailers (failed-QC items needing immediate action);
    //   3. hot trailers;
    //   4. trailers with an explicit globalPriority (< the 9999 default —
    //      lower number wins inside this tier);
    //   5. stalled trailers (critical/red before warning/yellow);
    //   6. oldest becameActiveAt first — a unit sitting three days outranks
    //      a unit that arrived five minutes ago. Unstamped rows sink.
    items.sort((a, b) => {
      // 1. active before waiting
      if (a.status !== b.status) {
        return a.status === ProductionStepStatus.active ? -1 : 1;
      }
      // 2. rework
      if (a.isRework !== b.isRework) return a.isRework ? -1 : 1;
      // 3. hot
      if (a.isHot !== b.isHot) return a.isHot ? -1 : 1;
      // 4. explicit globalPriority
      const aHas = a.globalPriority < 9999;
      const bHas = b.globalPriority < 9999;
      if (aHas !== bHas) return aHas ? -1 : 1;
      if (aHas && bHas && a.globalPriority !== b.globalPriority) {
        return a.globalPriority - b.globalPriority;
      }
      // 5. stalled (critical first)
      if (a._stallLevel !== b._stallLevel) return b._stallLevel - a._stallLevel;
      // 6. oldest first
      const aAt = a.becameActiveAt?.getTime();
      const bAt = b.becameActiveAt?.getTime();
      if (aAt == null && bAt == null) return 0;
      if (aAt == null) return 1;
      if (bAt == null) return -1;
      return aAt - bAt;
    });

    // Strip the internal sort helper before returning.
    return items.map(({ _stallLevel: _drop, ...rest }) => rest);
  }
}
