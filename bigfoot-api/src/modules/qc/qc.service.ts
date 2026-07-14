import { Injectable } from '@nestjs/common';
import { AppError, ErrorCode } from '../../common/errors';
import { toQcSeriesScope } from '../../common/qc-series-scope';
import { PrismaService } from '../../prisma/prisma.service';
import { ReworkRoutingService } from './rework-routing.service';
import { NotificationsService } from '../notifications/notifications.service';
import { SmsService } from '../notifications/sms.service';
import {
  CreateChecklistItemDto,
  UpdateChecklistItemDto,
  QueryChecklistItemsDto,
  QcSeriesScopeDto,
  SubmitInspectionDto,
} from './dto';
import {
  Prisma,
  QcResult,
  QcSeriesScope,
  ProductionStepStatus,
  TrailerStatus,
  NotificationType,
  SmsType,
  SmsStatus,
} from '@prisma/client';

@Injectable()
export class QcService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly reworkRouting: ReworkRoutingService,
    private readonly notificationsService: NotificationsService,
    private readonly smsService: SmsService,
  ) {}

  // ---------------------------------------------------------------------------
  // GET /qc/checklist-items — list with optional filters
  //
  // When `trailerId` is provided, the result includes option-gated items
  // (requires_addon_key IS NOT NULL) filtered by the trailer's addons:
  //   • always-items    (requires_addon_key IS NULL)
  //   • wildcard-items  (requires_addon_key = '*') when trailer has ≥1 addon
  //   • addon-specific  (requires_addon_key IN trailer.addons.addonName)
  // When `trailerId` is absent, only always-items are returned to preserve
  // existing admin UI behavior.
  // ---------------------------------------------------------------------------
  async findChecklistItems(query: QueryChecklistItemsDto) {
    const where: Prisma.QcChecklistItemWhereInput = {};

    if (query.departmentId) where.departmentId = query.departmentId;
    if (query.series) {
      // Include cross-series items (scope = all) alongside series-specific items
      where.appliesToSeries =
        query.series === QcSeriesScopeDto.ALL
          ? (query.series as QcSeriesScope)
          : { in: [query.series as QcSeriesScope, QcSeriesScope.all] };
    }

    if (query.trailerId !== undefined) {
      const trailer = await this.prisma.trailer.findUnique({
        where: { id: BigInt(query.trailerId) },
        select: {
          addons: { select: { addonName: true } },
          trailerModel: { select: { series: true } },
        },
      });
      if (!trailer) {
        throw new AppError(
          ErrorCode.NOT_FOUND,
          `Trailer with id ${query.trailerId} not found`,
        );
      }

      // Derive the scope from the trailer itself — never rely on the caller to
      // send `series`. Clients drop series they don't recognise (e.g. cxp), and
      // without a scope filter EVERY series' checks come back, so each item
      // renders once per scope (the "checklist shown 4×" bug). This wins over
      // any client-supplied series.
      const scope = toQcSeriesScope(trailer.trailerModel.series);
      if (scope) {
        where.appliesToSeries = { in: [scope, QcSeriesScope.all] };
      }

      const addonKeys = trailer.addons.map((a) => a.addonName);
      const addonClauses: Prisma.QcChecklistItemWhereInput[] = [
        { requiresAddonKey: null },
      ];
      if (addonKeys.length > 0) {
        addonClauses.push({ requiresAddonKey: '*' });
        addonClauses.push({ requiresAddonKey: { in: addonKeys } });
      }
      where.OR = addonClauses;
    } else {
      where.requiresAddonKey = null;
    }

    return this.prisma.qcChecklistItem.findMany({
      where,
      select: {
        id: true,
        departmentId: true,
        appliesToSeries: true,
        itemLabel: true,
        sortOrder: true,
        isActive: true,
        requiresAddonKey: true,
        createdAt: true,
        department: { select: { id: true, code: true, displayName: true } },
      },
      orderBy: [{ departmentId: 'asc' }, { sortOrder: 'asc' }],
    });
  }

  // ---------------------------------------------------------------------------
  // POST /qc/checklist-items — create checklist item
  // ---------------------------------------------------------------------------
  async createChecklistItem(dto: CreateChecklistItemDto) {
    // Validate the department is a QC department
    const dept = await this.prisma.department.findUnique({
      where: { id: dto.departmentId },
      select: { id: true, isQcStep: true, displayName: true },
    });

    if (!dept) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Department with id ${dto.departmentId} not found`,
      );
    }

    if (!dept.isQcStep) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `Department "${dept.displayName}" is not a QC department`,
      );
    }

    return this.prisma.qcChecklistItem.create({
      data: {
        departmentId: dto.departmentId,
        appliesToSeries: (dto.appliesToSeries as QcSeriesScope) ?? QcSeriesScope.all,
        itemLabel: dto.itemLabel,
        sortOrder: dto.sortOrder ?? 0,
        requiresAddonKey: dto.requiresAddonKey ?? null,
      },
      select: {
        id: true,
        departmentId: true,
        appliesToSeries: true,
        itemLabel: true,
        sortOrder: true,
        isActive: true,
        requiresAddonKey: true,
        createdAt: true,
        department: { select: { id: true, code: true, displayName: true } },
      },
    });
  }

  // ---------------------------------------------------------------------------
  // PATCH /qc/checklist-items/:id — update or deactivate
  // ---------------------------------------------------------------------------
  async updateChecklistItem(id: number, dto: UpdateChecklistItemDto) {
    const existing = await this.prisma.qcChecklistItem.findUnique({
      where: { id },
      select: { id: true },
    });

    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `Checklist item with id ${id} not found`);
    }

    const data: Prisma.QcChecklistItemUpdateInput = {};
    if (dto.itemLabel !== undefined) data.itemLabel = dto.itemLabel;
    if (dto.sortOrder !== undefined) data.sortOrder = dto.sortOrder;
    if (dto.isActive !== undefined) data.isActive = dto.isActive;

    return this.prisma.qcChecklistItem.update({
      where: { id },
      data,
      select: {
        id: true,
        departmentId: true,
        appliesToSeries: true,
        itemLabel: true,
        sortOrder: true,
        isActive: true,
        requiresAddonKey: true,
        createdAt: true,
        department: { select: { id: true, code: true, displayName: true } },
      },
    });
  }

  // ---------------------------------------------------------------------------
  // POST /qc/inspections — submit QC inspection (pass or fail)
  // ---------------------------------------------------------------------------
  async submitInspection(dto: SubmitInspectionDto, inspectorUserId: bigint) {
    // 1. Validate the production step exists, is a QC step, and is active
    const step = await this.prisma.productionStep.findUnique({
      where: { id: BigInt(dto.productionStepId) },
      select: {
        id: true,
        trailerId: true,
        departmentId: true,
        stepOrder: true,
        status: true,
        department: {
          select: { id: true, code: true, displayName: true, isQcStep: true },
        },
      },
    });

    if (!step) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Production step with id ${dto.productionStepId} not found`,
      );
    }

    if (!step.department.isQcStep) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `Step ${dto.productionStepId} is not a QC step — use production step completion instead`,
      );
    }

    if (step.status !== ProductionStepStatus.active) {
      throw new AppError(
        ErrorCode.STEP_NOT_ACTIVE,
        `QC step ${dto.productionStepId} is not currently active (status: ${step.status})`,
      );
    }

    // 1a. A photo is REQUIRED on every QC step — you can't sign off a stage you
    //     didn't photograph. (The error code existed but was never enforced.)
    if (!dto.photoStorageKeys || dto.photoStorageKeys.length === 0) {
      throw new AppError(
        ErrorCode.QC_PHOTO_REQUIRED,
        'Take at least one photo of this stage before submitting the inspection',
      );
    }

    // 2. Validate checklist completeness — all active items for this dept/series must be answered
    const trailer = await this.prisma.trailer.findUnique({
      where: { id: step.trailerId },
      select: {
        id: true,
        soNumber: true,
        status: true,
        addons: { select: { addonName: true } },
        trailerModel: { select: { series: true } },
        customer: { select: { smsPhone: true, smsOptOut: true } },
      },
    });

    if (!trailer) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Trailer not found for step ${dto.productionStepId}`,
      );
    }

    const addonKeys = trailer.addons.map((a) => a.addonName);
    const checklistWhere: Prisma.QcChecklistItemWhereInput = {
      departmentId: step.departmentId,
      isActive: true,
      appliesToSeries: {
        in: [trailer.trailerModel.series as unknown as QcSeriesScope, QcSeriesScope.all],
      },
      OR: [{ requiresAddonKey: null }],
    };

    if (addonKeys.length > 0) {
      checklistWhere.OR = [
        { requiresAddonKey: null },
        { requiresAddonKey: '*' },
        { requiresAddonKey: { in: addonKeys } },
      ];
    }

    const activeChecklistItems = await this.prisma.qcChecklistItem.findMany({
      where: checklistWhere,
      select: { id: true },
    });

    // Validate all active checklist items are answered
    const answeredItemIds = new Set(dto.checklistResults.map((r) => r.checklistItemId));
    const missingItems = activeChecklistItems.filter(
      (item) => !answeredItemIds.has(item.id),
    );

    if (missingItems.length > 0) {
      throw new AppError(
        ErrorCode.QC_CHECKLIST_INCOMPLETE,
        `Missing checklist results for items: ${missingItems.map((i) => i.id).join(', ')}`,
      );
    }

    // 3. Validate fail-specific requirements
    const isFail = dto.result === 'fail';
    if (isFail) {
      if (!dto.reworkTargetDepartmentId) {
        throw new AppError(
          ErrorCode.QC_REWORK_TARGET_REQUIRED,
          'A rework target department must be selected when the QC result is a fail',
        );
      }
      if (!dto.failNotes) {
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          'Failure notes must be provided when the QC result is a fail',
        );
      }
    }

    // 4. Determine attempt number
    const previousInspections = await this.prisma.qcInspection.count({
      where: { productionStepId: step.id },
    });
    const attemptNumber = previousInspections + 1;

    // 5. Determine if this is FINAL_QC
    const isFinalQc = step.department.code === 'FINAL_QC';

    // 6. Execute in transaction
    const result = await this.prisma.$transaction(async (tx) => {
      // Create the inspection record
      const inspection = await tx.qcInspection.create({
        data: {
          productionStepId: step.id,
          trailerId: step.trailerId,
          inspectorUserId,
          result: dto.result as QcResult,
          failNotes: isFail ? dto.failNotes! : null,
          attemptNumber,
          isFinalQc,
        },
        select: { id: true },
      });

      // Create checklist results
      await tx.qcChecklistResult.createMany({
        data: dto.checklistResults.map((r) => ({
          qcInspectionId: inspection.id,
          checklistItemId: r.checklistItemId,
          passed: r.passed,
          note: r.note ?? null,
        })),
      });

      // Create photo records
      await tx.qcPhoto.createMany({
        data: dto.photoStorageKeys.map((key) => ({
          qcInspectionId: inspection.id,
          trailerId: step.trailerId,
          storageUrl: key, // URL can be derived from key; store key as URL for now
          storageKey: key,
        })),
      });

      // Mark the QC step as complete
      await tx.productionStep.update({
        where: { id: step.id },
        data: {
          status: ProductionStepStatus.complete,
          completedByUserId: inspectorUserId,
          completedAt: new Date(),
        },
      });

      if (isFail) {
        // --- FAIL PATH ---
        const reworkResult = await this.reworkRouting.routeRework(
          step.trailerId,
          dto.reworkTargetDepartmentId!,
          dto.failNotes!,
          tx,
        );

        // Store rework references on the inspection
        await tx.qcInspection.update({
          where: { id: inspection.id },
          data: {
            reworkTargetDeptId: reworkResult.reworkTargetDeptId,
            reworkSentToStepId: reworkResult.reworkStepId,
          },
        });

        // Send qc_fail push notification to all production_managers
        const productionManagers = await tx.user.findMany({
          where: { role: 'production_manager', isActive: true },
          select: { id: true },
        });

        if (productionManagers.length > 0) {
          await tx.pushNotification.createMany({
            data: productionManagers.map((pm) => ({
              recipientUserId: pm.id,
              trailerId: step.trailerId,
              notificationType: NotificationType.qc_fail,
              title: `QC Fail — ${trailer.soNumber}`,
              body: `${step.department.displayName} failed. Rework sent to ${reworkResult.reworkTargetDepartment}. Notes: ${dto.failNotes}`,
            })),
          });
        }

        return {
          inspectionId: inspection.id,
          result: 'fail' as const,
          reworkTargetDepartment: reworkResult.reworkTargetDepartment,
          reworkTargetDeptId: reworkResult.reworkTargetDeptId,
          reworkStepId: reworkResult.reworkStepId,
          reworkQueuePosition: reworkResult.reworkQueuePosition,
          notificationSentTo: ['production_manager'],
        };
      } else {
        // --- PASS PATH ---
        if (isFinalQc) {
          // FINAL_QC pass: set trailer status to ready_for_delivery
          await tx.trailer.update({
            where: { id: step.trailerId },
            data: { status: TrailerStatus.ready_for_delivery },
          });

          // Queue SMS (don't dispatch — inspector must manually tap)
          let smsReady = false;
          if (trailer.customer?.smsPhone && !trailer.customer.smsOptOut) {
            await tx.smsLog.create({
              data: {
                trailerId: step.trailerId,
                recipientPhone: trailer.customer.smsPhone,
                smsType: SmsType.trailer_complete,
                messageBody: `Your trailer ${trailer.soNumber} is complete and ready for pickup/delivery!`,
                status: SmsStatus.queued,
              },
            });
            smsReady = true;
          }

          return {
            inspectionId: inspection.id,
            result: 'pass' as const,
            isFinalQc: true,
            trailerStatus: 'ready_for_delivery',
            smsReady,
            smsActionRequired: smsReady
              ? "Tap 'Send Customer Notification' to dispatch SMS"
              : undefined,
          };
        } else {
          // Normal QC pass: advance next step to active
          const nextStep = await tx.productionStep.findFirst({
            where: {
              trailerId: step.trailerId,
              stepOrder: step.stepOrder + 1,
            },
            select: {
              id: true,
              department: { select: { id: true, displayName: true } },
            },
          });

          if (nextStep) {
            // Find next queue position for the target department
            const maxPosition = await tx.productionStep.aggregate({
              where: {
                departmentId: nextStep.department.id,
                status: ProductionStepStatus.active,
              },
              _max: { queuePosition: true },
            });
            const nextQueuePosition = (maxPosition._max.queuePosition ?? 0) + 1;

            await tx.productionStep.update({
              where: { id: nextStep.id },
              data: {
                status: ProductionStepStatus.active,
                queuePosition: nextQueuePosition,
                becameActiveAt: new Date(),
              },
            });
          }

          // Update trailer status to in_production if still pending
          if (trailer.status === TrailerStatus.pending_production) {
            await tx.trailer.update({
              where: { id: step.trailerId },
              data: { status: TrailerStatus.in_production },
            });
          }

          return {
            inspectionId: inspection.id,
            result: 'pass' as const,
            isFinalQc: false,
            nextStepId: nextStep?.id ?? null,
            nextDepartment: nextStep?.department.displayName ?? null,
            trailerStatus:
              trailer.status === TrailerStatus.pending_production
                ? 'in_production'
                : trailer.status,
          };
        }
      }
    });

    // --- WebSocket + Push notifications (after transaction committed) ---
    if (result.result === 'fail') {
      await this.notificationsService.onQcFail({
        inspectionId: result.inspectionId,
        trailerId: step.trailerId,
        soNumber: trailer.soNumber,
        qcStep: step.department.code,
        qcDepartmentId: step.departmentId,
        failNotes: dto.failNotes!,
        reworkTargetDeptId: result.reworkTargetDeptId,
        reworkTargetDepartment: result.reworkTargetDepartment,
        reworkStepId: result.reworkStepId,
      });
    } else {
      await this.notificationsService.onQcPass({
        inspectionId: result.inspectionId,
        trailerId: step.trailerId,
        soNumber: trailer.soNumber,
        qcStep: step.department.code,
        qcDepartmentId: step.departmentId,
        nextStepId: 'nextStepId' in result ? result.nextStepId : null,
        nextDepartmentId:
          'nextStepId' in result && result.nextStepId
            ? ((
                await this.prisma.productionStep.findUnique({
                  where: { id: result.nextStepId as bigint },
                  select: { departmentId: true },
                })
              )?.departmentId ?? null)
            : null,
        nextDepartmentName:
          'nextDepartment' in result ? (result.nextDepartment as string) : null,
        isFinalQc: result.isFinalQc ?? false,
        trailerStatus: result.trailerStatus ?? trailer.status,
      });
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // GET /qc/stats — dashboard summary for QC inspectors
  // ---------------------------------------------------------------------------
  async getQcStats() {
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);
    // 30-day rolling window for the bigger "QC fail rate" tile on the
    // manager dashboard. Today-only is too volatile (0 inspections → 0%,
    // or 1 fail out of 1 → 100%); 30 days smooths it out.
    const startOf30dWindow = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

    const [
      readyForInspection,
      reworkQueue,
      inspectionsToday,
      failsToday,
      inspections30d,
      fails30d,
    ] = await this.prisma.$transaction([
      // "Ready for inspection" = QC steps the trailer has actually reached
      // and are waiting on the inspector (status `active`). `waiting` QC
      // steps belong to trailers still at an earlier production stage.
      this.prisma.productionStep.count({
        where: {
          status: ProductionStepStatus.active,
          department: { isQcStep: true },
        },
      }),
      // "Rework queue" — actively-being-redone steps. The rework-routing
      // service flips the targeted earlier step to status='active' and
      // sets isRework=true (rather than using the ProductionStepStatus
      // .rework enum value, which the schema carries but the runtime
      // doesn't actually set). The previous query keyed off the unused
      // enum value, which is why this card always read 0.
      this.prisma.productionStep.count({
        where: {
          isRework: true,
          status: ProductionStepStatus.active,
        },
      }),
      this.prisma.qcInspection.count({
        where: { inspectedAt: { gte: startOfToday } },
      }),
      this.prisma.qcInspection.count({
        where: {
          inspectedAt: { gte: startOfToday },
          result: QcResult.fail,
        },
      }),
      this.prisma.qcInspection.count({
        where: { inspectedAt: { gte: startOf30dWindow } },
      }),
      this.prisma.qcInspection.count({
        where: {
          inspectedAt: { gte: startOf30dWindow },
          result: QcResult.fail,
        },
      }),
    ]);

    // Rates ship as percentages (0–100) so the UI can render them with a
    // plain `%` suffix. Previously these were 0–1 fractions, which made
    // "25%" render as "0.2%" on the dashboard. New mobile build also
    // populates qcFailRate (the 30-day rolling rate behind the manager
    // dashboard tile) — backend returns 0 when no inspections exist.
    const failRateToday =
      inspectionsToday > 0 ? (failsToday / inspectionsToday) * 100 : 0;
    const qcFailRate =
      inspections30d > 0 ? (fails30d / inspections30d) * 100 : 0;

    return {
      readyForInspection,
      inspectionsToday,
      // failsToday paired with inspectionsToday lets the daily tile show
      // "0.0% · 0/0" honestly. The percent alone is misleading when the
      // sample size is zero (or one).
      failsToday,
      failRateToday,
      qcFailRate,
      // Raw 30-day counts so the dashboard tile can render "5.2% · 3 of 58"
      // alongside the percent. The percent alone hides the sample size —
      // 100% off 1 inspection means something very different from 100%
      // off 200 inspections, and operators want both at a glance.
      qcFailRateInspections: inspections30d,
      qcFailRateFails: fails30d,
      reworkQueue,
    };
  }

  // ---------------------------------------------------------------------------
  // GET /qc/rework-queue — drilldown behind the dashboard rework tile.
  //
  // Returns the active production_steps where isRework=true — the trailers
  // QC bumped back to an earlier department that haven't been redone yet.
  // Ordered by becameActiveAt asc so the oldest rework sits at the top.
  // ---------------------------------------------------------------------------
  async getReworkQueue() {
    return this.prisma.productionStep.findMany({
      where: {
        isRework: true,
        status: ProductionStepStatus.active,
      },
      orderBy: [
        { becameActiveAt: 'asc' },
        { queuePosition: 'asc' },
      ],
      select: {
        id: true,
        stepOrder: true,
        queuePosition: true,
        reworkCount: true,
        becameActiveAt: true,
        department: { select: { code: true, displayName: true } },
        trailer: {
          select: {
            id: true,
            soNumber: true,
            isHot: true,
            globalPriority: true,
            trailerModel: { select: { displayName: true, series: true } },
            customer: { select: { name: true } },
            soldToName: true,
          },
        },
      },
      take: 200,
    });
  }

  // ---------------------------------------------------------------------------
  // GET /qc/failed-inspections — drilldown behind the dashboard fail-rate
  //
  // Returns failed QcInspection rows over a rolling window (default 30 days)
  // with the trailer, inspector, and rework-target context the mobile
  // screen needs to render a useful list. Newest first.
  // ---------------------------------------------------------------------------
  async getFailedInspections(days: number) {
    const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    return this.prisma.qcInspection.findMany({
      where: {
        result: QcResult.fail,
        inspectedAt: { gte: cutoff },
      },
      orderBy: { inspectedAt: 'desc' },
      select: {
        id: true,
        inspectedAt: true,
        failNotes: true,
        attemptNumber: true,
        isFinalQc: true,
        trailer: {
          select: {
            id: true,
            soNumber: true,
            trailerModel: { select: { displayName: true, series: true } },
            customer: { select: { name: true } },
            soldToName: true,
          },
        },
        inspectorUser: { select: { id: true, fullName: true } },
        reworkTargetDept: { select: { code: true, displayName: true } },
        productionStep: {
          select: {
            stepOrder: true,
            department: { select: { code: true, displayName: true } },
          },
        },
      },
      take: 200,
    });
  }

  // ---------------------------------------------------------------------------
  // POST /qc/inspections/:id/send-customer-sms — manually dispatch the
  // trailer_complete SMS queued when a FINAL_QC pass was recorded.
  // ---------------------------------------------------------------------------
  async sendCustomerSms(inspectionId: bigint) {
    const inspection = await this.prisma.qcInspection.findUnique({
      where: { id: inspectionId },
      select: {
        id: true,
        trailerId: true,
        result: true,
        isFinalQc: true,
        smsSentAt: true,
      },
    });

    if (!inspection) {
      throw new AppError(ErrorCode.NOT_FOUND, `Inspection ${inspectionId} not found`);
    }
    if (inspection.result !== QcResult.pass || !inspection.isFinalQc) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'Customer SMS can only be sent for FINAL_QC pass inspections',
      );
    }
    if (inspection.smsSentAt) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'Customer SMS for this inspection has already been sent',
      );
    }

    const queued = await this.prisma.smsLog.findFirst({
      where: {
        trailerId: inspection.trailerId,
        smsType: SmsType.trailer_complete,
        status: SmsStatus.queued,
      },
      orderBy: { id: 'desc' },
      select: { id: true },
    });

    if (!queued) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'No customer SMS is queued for this trailer — the customer may have opted out of texts or has no phone number on file',
      );
    }

    await this.smsService.sendImmediately(queued.id);

    const dispatched = await this.prisma.smsLog.findUnique({
      where: { id: queued.id },
      select: { status: true },
    });

    if (dispatched?.status === SmsStatus.failed) {
      throw new AppError(
        ErrorCode.INTERNAL_ERROR,
        'SMS dispatch failed — see server logs for details',
      );
    }

    await this.prisma.qcInspection.update({
      where: { id: inspectionId },
      data: { smsSentAt: new Date() },
    });

    return {
      smsLogId: queued.id.toString(),
      status: dispatched?.status ?? SmsStatus.queued,
      sentAt: new Date().toISOString(),
    };
  }

  // ---------------------------------------------------------------------------
  // GET /qc/inspections/:id — single inspection with results and photos
  // ---------------------------------------------------------------------------
  async findInspection(id: bigint) {
    const inspection = await this.prisma.qcInspection.findUnique({
      where: { id },
      select: {
        id: true,
        productionStepId: true,
        trailerId: true,
        result: true,
        failNotes: true,
        attemptNumber: true,
        isFinalQc: true,
        inspectedAt: true,
        smsSentAt: true,
        inspectorUser: { select: { id: true, fullName: true } },
        reworkTargetDept: { select: { id: true, code: true, displayName: true } },
        reworkSentToStep: { select: { id: true, stepOrder: true } },
        productionStep: {
          select: {
            stepOrder: true,
            trailerId: true,
            department: { select: { code: true, displayName: true } },
          },
        },
        checklistResults: {
          select: {
            id: true,
            passed: true,
            note: true,
            checklistItem: { select: { id: true, itemLabel: true } },
          },
          orderBy: { checklistItem: { sortOrder: 'asc' } },
        },
        photos: {
          select: { id: true, storageUrl: true, storageKey: true, takenAt: true },
          orderBy: { takenAt: 'asc' },
        },
      },
    });

    if (!inspection) {
      throw new AppError(ErrorCode.NOT_FOUND, `QC inspection with id ${id} not found`);
    }

    // Upstream worker self-checks: all ProductionStepChecks recorded on the
    // completed (non-QC) steps of this trailer, grouped by department.
    const upstreamChecks = await this.prisma.productionStepCheck.findMany({
      where: {
        productionStep: {
          trailerId: inspection.productionStep.trailerId,
          department: { isQcStep: false },
        },
      },
      select: {
        id: true,
        passed: true,
        note: true,
        createdAt: true,
        checklistItem: { select: { id: true, itemLabel: true, sortOrder: true } },
        checkedByUser: { select: { id: true, fullName: true } },
        productionStep: {
          select: {
            id: true,
            department: { select: { id: true, code: true, displayName: true } },
          },
        },
      },
      orderBy: [
        { productionStep: { department: { id: 'asc' } } },
        { checklistItem: { sortOrder: 'asc' } },
      ],
    });

    return { ...inspection, upstreamChecks };
  }

  // ---------------------------------------------------------------------------
  // GET /qc/inspections/step/:step_id — all inspections for a step
  // ---------------------------------------------------------------------------
  async findInspectionsByStep(stepId: bigint) {
    const step = await this.prisma.productionStep.findUnique({
      where: { id: stepId },
      select: { id: true },
    });

    if (!step) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Production step with id ${stepId} not found`,
      );
    }

    return this.prisma.qcInspection.findMany({
      where: { productionStepId: stepId },
      select: {
        id: true,
        result: true,
        failNotes: true,
        attemptNumber: true,
        isFinalQc: true,
        inspectedAt: true,
        inspectorUser: { select: { id: true, fullName: true } },
        reworkTargetDept: { select: { id: true, code: true, displayName: true } },
        checklistResults: {
          select: {
            id: true,
            passed: true,
            note: true,
            checklistItem: { select: { id: true, itemLabel: true } },
          },
        },
        photos: {
          select: { id: true, storageUrl: true, storageKey: true, takenAt: true },
        },
      },
      orderBy: { attemptNumber: 'asc' },
    });
  }
}
