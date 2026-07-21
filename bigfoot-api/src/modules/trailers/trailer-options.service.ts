import { Injectable, Logger } from '@nestjs/common';
import { ProductionStepStatus, TrailerStatus } from '@prisma/client';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditLogService } from '../admin/audit-log.service';

/**
 * Option (add-on) accountability.
 *
 * The problem this exists to solve, in Drew's words: "we are having a lot of
 * options added after it is in production, it is not getting seen, and it is
 * built completely wrong — no one knows till the very end and then it has to
 * be rebuilt."
 *
 * Three mechanisms:
 *
 *  1. ACKNOWLEDGEMENT — an option names EVERY department that has to fit part
 *     of it (D-rings might be welded at JIG and touched up at PAINT). Each of
 *     those departments must acknowledge its own part before it can complete
 *     its step. Departments that don't fit it just see it and move on.
 *
 *  2. MID-BUILD ALERT — an option added after the build started is flagged
 *     (with the step it got past) and surfaces on the admin / production-
 *     manager dashboard until the PM acknowledges it.
 *
 *  3. ROLL BACK — from that dashboard the PM can send the trailer back to a
 *     department that still needs to fit the option.
 */
@Injectable()
export class TrailerOptionsService {
  private readonly logger = new Logger('TrailerOptions');

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditLogService,
  ) {}

  /**
   * Add an option. `installDepartmentIds` is every department that has to fit
   * part of it. If the build has already started the option is flagged for the
   * production manager — it must not be possible to quietly add a D-ring after
   * weld and have nobody notice.
   */
  async addOption(
    trailerId: bigint,
    dto: {
      addonName: string;
      notes?: string;
      installDepartmentIds?: number[];
    },
    userId: bigint,
  ) {
    const trailer = await this.prisma.trailer.findUnique({
      where: { id: trailerId },
      select: { id: true, soNumber: true, status: true },
    });
    if (!trailer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer ${trailerId} not found`);
    }

    // Where is the build right now? The active step tells us what this option
    // was "added past".
    const activeStep = await this.prisma.productionStep.findFirst({
      where: { trailerId, status: ProductionStepStatus.active },
      select: {
        stepOrder: true,
        departmentId: true,
        department: { select: { code: true } },
      },
    });

    // EVERY option lands on the production manager's review box. An option can
    // only ever be added to a trailer that already exists (nothing attaches
    // addons at create time), so anything added here is a change to an order
    // that was already placed — the shop wants to see all of them, not only the
    // ones added after the line started. A trailer still sitting in
    // pending_production is exactly the case that was silently skipped before.
    const addedAfterOrder = true;

    // De-dupe: the same department twice is one responsibility, not two.
    const deptIds = [...new Set(dto.installDepartmentIds ?? [])];

    const addon = await this.prisma.trailerAddon.create({
      data: {
        trailerId,
        addonName: dto.addonName,
        notes: dto.notes,
        addedByUserId: userId,
        addedDuringProduction: addedAfterOrder,
        // Where the build actually was, when it was already on the line. Null
        // for a trailer that hasn't started — there's no step it "got past".
        addedAtStepOrder: activeStep?.stepOrder ?? null,
        addedAtDepartmentId: activeStep?.departmentId ?? null,
        departments: {
          create: deptIds.map((departmentId) => ({ departmentId })),
        },
      },
      include: {
        departments: {
          include: { department: { select: { id: true, code: true, displayName: true } } },
        },
      },
    });

    await this.audit.create({
      userId: Number(userId),
      entityType: 'trailer',
      entityId: Number(trailerId),
      // The audit distinguishes the two cases even though both now alert:
      // "during production" means the line had already started on it.
      action: activeStep ? 'option.added_during_production' : 'option.added',
      newValues: {
        option: dto.addonName,
        fittedBy: addon.departments.map((d) => d.department.code).join(', ') || null,
        addedPastStep: activeStep?.department.code ?? null,
      },
    });

    this.logger.warn(
      activeStep
        ? `Option "${dto.addonName}" added to SO ${trailer.soNumber} DURING production ` +
            `(past ${activeStep.department.code}) — flagged for the production manager`
        : `Option "${dto.addonName}" added to SO ${trailer.soNumber} before the line started ` +
            `— flagged for the production manager`,
    );
    return addon;
  }

  /** Options on a trailer, with who fits them and each department's ack state. */
  async listForTrailer(trailerId: bigint) {
    return this.prisma.trailerAddon.findMany({
      where: { trailerId },
      orderBy: { addedAt: 'asc' },
      include: {
        addedByUser: { select: { id: true, fullName: true } },
        departments: {
          include: {
            department: { select: { id: true, code: true, displayName: true } },
            acknowledgedByUser: { select: { id: true, fullName: true } },
          },
        },
      },
    });
  }

  /**
   * The options a worker sees at a given step, split into what THEY must
   * acknowledge and what they can skip.
   *
   * "The jig worker sees those options but can skip them and answer the QC
   * questions because they don't do those options. But when it gets to jig they
   * put on the D-rings, so they have to acknowledge it — then they can answer
   * the QC steps."
   */
  async listForStep(stepId: bigint) {
    const step = await this.prisma.productionStep.findUnique({
      where: { id: stepId },
      select: { trailerId: true, departmentId: true },
    });
    if (!step) throw new AppError(ErrorCode.NOT_FOUND, 'Production step not found');

    const options = await this.listForTrailer(step.trailerId);
    return options.map((o) => {
      // This department's own responsibility for this option (if any).
      const mine = o.departments.find((d) => d.departmentId === step.departmentId);
      return {
        ...o,
        // The id to POST back when acknowledging — it's the join row, because
        // each department acknowledges its own part independently.
        myAckId: mine ? mine.id : null,
        forThisDepartment: !!mine,
        mustAcknowledge: !!mine && mine.acknowledgedAt === null,
        // Everyone who has to fit it, and whether they've done their part.
        fittedBy: o.departments.map((d) => ({
          code: d.department.code,
          acknowledged: d.acknowledgedAt !== null,
          acknowledgedBy: d.acknowledgedByUser?.fullName ?? null,
        })),
      };
    });
  }

  /** A department ticks off its part: "yes, I fitted it." */
  async acknowledge(addonDeptId: bigint, userId: bigint) {
    const row = await this.prisma.trailerAddonDept.findUnique({
      where: { id: addonDeptId },
      include: {
        addon: { select: { trailerId: true, addonName: true } },
        department: { select: { code: true } },
      },
    });
    if (!row) {
      throw new AppError(ErrorCode.NOT_FOUND, `Option assignment ${addonDeptId} not found`);
    }
    if (row.acknowledgedAt) return row; // idempotent

    const updated = await this.prisma.trailerAddonDept.update({
      where: { id: addonDeptId },
      data: { acknowledgedAt: new Date(), acknowledgedByUserId: userId },
    });

    await this.audit.create({
      userId: Number(userId),
      entityType: 'trailer',
      entityId: Number(row.addon.trailerId),
      action: 'option.acknowledged',
      newValues: {
        option: row.addon.addonName,
        department: row.department.code,
      },
    });
    return updated;
  }

  /**
   * GUARD — called before a department may complete its step. Any option THIS
   * department is responsible for fitting must be acknowledged first. Other
   * departments' parts are none of its business, so they never block it.
   */
  async assertOptionsAcknowledged(
    trailerId: bigint,
    departmentId: number,
  ): Promise<void> {
    const unacknowledged = await this.prisma.trailerAddonDept.findMany({
      where: {
        departmentId,
        acknowledgedAt: null,
        addon: { trailerId },
      },
      select: { addon: { select: { addonName: true } } },
    });
    if (unacknowledged.length === 0) return;

    throw new AppError(
      ErrorCode.OPTIONS_NOT_ACKNOWLEDGED,
      `Acknowledge the option(s) this department fits before continuing: ` +
        unacknowledged.map((o) => o.addon.addonName).join(', '),
    );
  }

  /**
   * The dashboard box: options added mid-build that the production manager
   * hasn't seen yet.
   */
  async listPendingProductionManagerReview() {
    const rows = await this.prisma.trailerAddon.findMany({
      where: { addedDuringProduction: true, pmAcknowledgedAt: null },
      orderBy: { addedAt: 'desc' },
      include: {
        addedAtDepartment: { select: { id: true, code: true, displayName: true } },
        addedByUser: { select: { id: true, fullName: true } },
        departments: {
          include: { department: { select: { id: true, code: true, displayName: true } } },
        },
        trailer: {
          select: {
            id: true,
            soNumber: true,
            status: true,
            trailerModel: { select: { code: true } },
            // EVERY step, not just the active one — we need to know whether the
            // departments that still owe work have already been passed.
            productionSteps: {
              select: {
                id: true,
                stepOrder: true,
                status: true,
                departmentId: true,
                department: { select: { id: true, code: true, displayName: true } },
              },
              orderBy: { stepOrder: 'asc' },
            },
          },
        },
      },
    });

    return rows.map((r) => {
      const steps = r.trailer.productionSteps;
      const current =
        steps.find((s) => s.status === ProductionStepStatus.active) ?? null;
      // Departments that still owe work on this option.
      const outstanding = r.departments.filter((d) => d.acknowledgedAt === null);

      /**
       * The departments that will NEVER get to fit this option unless the
       * trailer is sent back: they still owe work, but the build has already
       * gone past their step (it's complete, or it sits before the active one).
       *
       * This is the case Drew described — D-rings added while the trailer is
       * past weld. Comparing against where the option was ADDED is not enough:
       * an option added at PAINT that needs JIG was already too late the moment
       * it was created.
       */
      const missed = outstanding.filter((d) => {
        const theirStep = steps.find((s) => s.departmentId === d.departmentId);
        if (!theirStep) return false; // that dept isn't on this trailer's line
        if (theirStep.status === ProductionStepStatus.complete) return true;
        return !!current && theirStep.stepOrder < current.stepOrder;
      });
      return {
        id: r.id,
        option: r.addonName,
        notes: r.notes,
        trailerId: r.trailer.id,
        soNumber: r.trailer.soNumber,
        model: r.trailer.trailerModel.code,
        addedBy: r.addedByUser?.fullName ?? 'Unknown',
        addedAt: r.addedAt,
        addedPastDepartment: r.addedAtDepartment?.code ?? null,
        // Everyone who has to fit it + whether they've done it.
        fittedBy: r.departments.map((d) => ({
          id: d.department.id,
          code: d.department.code,
          acknowledged: d.acknowledgedAt !== null,
        })),
        // Still-outstanding departments.
        outstandingDepartments: outstanding.map((d) => d.department.code),

        /**
         * Every step on this trailer's line, so the production manager can move
         * the build BACK to a stage that was missed, or FORWARD past one — the
         * jump-to-step endpoint takes a stepId and handles both directions.
         * `owes` marks the stages that still have to fit this option.
         */
        steps: steps.map((s) => ({
          stepId: Number(s.id),
          stepOrder: s.stepOrder,
          code: s.department.code,
          name: s.department.displayName,
          status: s.status,
          isCurrent: s.id === current?.id,
          owes: outstanding.some((d) => d.departmentId === s.departmentId),
        })),

        /**
         * Where to send the build back to — the earliest stage that was missed.
         * Named, not just an opaque step id: callers (and humans reading logs)
         * should see "send back to XP_JIG", never "send back to step 529".
         */
        ...(() => {
          const first = missed
            .map((d) => steps.find((s) => s.departmentId === d.departmentId))
            .filter((s): s is (typeof steps)[number] => !!s)
            .sort((a, b) => a.stepOrder - b.stepOrder)[0];
          return {
            rollbackStepId: first ? Number(first.id) : null,
            rollbackDepartment: first
              ? {
                  code: first.department.code,
                  name: first.department.displayName,
                }
              : null,
          };
        })(),
        /**
         * Departments the build has ALREADY PASSED that still owe work. These
         * are what a roll-back has to target — they will never see the option
         * otherwise. Ordered so the earliest missed stage comes first.
         */
        missedDepartments: missed
          .map((d) => ({
            code: d.department.code,
            stepOrder:
              steps.find((s) => s.departmentId === d.departmentId)?.stepOrder ?? 0,
          }))
          .sort((a, b) => a.stepOrder - b.stepOrder)
          .map((d) => d.code),
        currentStepId: current?.id ?? null,
        currentDepartment: current?.department ?? null,
        /**
         * The signal that matters: a department that still has to fit this
         * option has already been passed. Left alone, the trailer gets built
         * wrong — this is the whole reason the box exists.
         */
        needsRollback: missed.length > 0,
      };
    });
  }

  /** PM has seen it → clears off the dashboard. */
  async productionManagerAcknowledge(addonId: bigint, userId: bigint) {
    const addon = await this.prisma.trailerAddon.findUnique({
      where: { id: addonId },
      select: { id: true, trailerId: true, addonName: true },
    });
    if (!addon) throw new AppError(ErrorCode.NOT_FOUND, `Option ${addonId} not found`);

    const updated = await this.prisma.trailerAddon.update({
      where: { id: addonId },
      data: { pmAcknowledgedAt: new Date(), pmAcknowledgedByUserId: userId },
    });

    await this.audit.create({
      userId: Number(userId),
      entityType: 'trailer',
      entityId: Number(addon.trailerId),
      action: 'option.reviewed_by_manager',
      newValues: { option: addon.addonName },
    });
    return updated;
  }
}
