import { Injectable } from '@nestjs/common';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { AuditLogService } from './audit-log.service';

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLogService: AuditLogService,
  ) {}

  // ===========================================================================
  // Workflow Templates
  // ===========================================================================
  async getWorkflowTemplates() {
    const templates = await this.prisma.workflowTemplate.findMany({
      select: {
        id: true,
        series: true,
        departmentId: true,
        stepOrder: true,
        department: {
          select: {
            code: true,
            displayName: true,
            isQcStep: true,
          },
        },
      },
      orderBy: [{ series: 'asc' }, { stepOrder: 'asc' }],
    });

    return templates.map((t) => ({
      id: t.id,
      series: t.series,
      department_id: t.departmentId,
      department_code: t.department.code,
      department_name: t.department.displayName,
      step_order: t.stepOrder,
      is_qc_step: t.department.isQcStep,
    }));
  }

  // ===========================================================================
  // Trailer Models
  // ===========================================================================
  async getTrailerModels() {
    return this.prisma.trailerModel.findMany({
      select: {
        id: true,
        code: true,
        displayName: true,
        series: true,
        weightRating: true,
      },
      orderBy: [{ series: 'asc' }, { id: 'asc' }],
    });
  }

  // ===========================================================================
  // Departments
  // ===========================================================================
  async getDepartments() {
    return this.prisma.department.findMany({
      select: {
        id: true,
        code: true,
        displayName: true,
        isQcStep: true,
        completionType: true,
        stallThresholdHours: true,
        createdAt: true,
      },
      orderBy: { id: 'asc' },
    });
  }

  async updateDepartment(
    id: number,
    stallThresholdHours: number,
    userId?: number,
    ipAddress?: string,
  ) {
    const existing = await this.prisma.department.findUnique({
      where: { id },
      select: { id: true, stallThresholdHours: true },
    });

    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `Department ${id} not found`);
    }

    const updated = await this.prisma.department.update({
      where: { id },
      data: { stallThresholdHours },
      select: {
        id: true,
        code: true,
        displayName: true,
        isQcStep: true,
        completionType: true,
        stallThresholdHours: true,
        createdAt: true,
      },
    });

    await this.auditLogService.create({
      userId: userId ?? null,
      entityType: 'department',
      entityId: id,
      action: 'UPDATE',
      oldValues: { stallThresholdHours: existing.stallThresholdHours },
      newValues: { stallThresholdHours },
      ipAddress: ipAddress ?? null,
    });

    return updated;
  }

  // ===========================================================================
  // Weekly Production Report
  // ===========================================================================
  async getWeeklyProductionReport(weekStart: string) {
    const weekDate = new Date(weekStart);
    if (weekDate.getUTCDay() !== 0) {
      throw new AppError(
        ErrorCode.INVALID_WEEK_START,
        'The provided week_start date is not a Sunday',
      );
    }

    const weekEnd = new Date(weekDate);
    weekEnd.setUTCDate(weekEnd.getUTCDate() + 7);

    // Fetch completed production steps for the week
    const steps = await this.prisma.productionStep.findMany({
      where: {
        status: 'complete',
        isRework: false,
        completedAt: {
          gte: weekDate,
          lt: weekEnd,
        },
      },
      select: {
        id: true,
        trailerId: true,
        departmentId: true,
        pointsAwarded: true,
        completedAt: true,
        completedByUserId: true,
        trailer: {
          select: {
            soNumber: true,
            trailerModel: {
              select: { displayName: true, series: true },
            },
          },
        },
        department: {
          select: { displayName: true, code: true },
        },
        completedByUser: {
          select: { id: true, fullName: true },
        },
      },
      orderBy: { completedAt: 'desc' },
    });

    // Aggregate by worker
    const workerMap = new Map<
      string,
      { userId: bigint; fullName: string; totalPoints: number; stepsCompleted: number }
    >();

    for (const step of steps) {
      if (!step.completedByUser) continue;
      const key = step.completedByUser.id.toString();
      const existing = workerMap.get(key);
      const points = Number(step.pointsAwarded);
      if (existing) {
        existing.totalPoints += points;
        existing.stepsCompleted += 1;
      } else {
        workerMap.set(key, {
          userId: step.completedByUser.id,
          fullName: step.completedByUser.fullName,
          totalPoints: points,
          stepsCompleted: 1,
        });
      }
    }

    return {
      weekStart: weekStart,
      weekEnd: weekEnd.toISOString().split('T')[0],
      totalStepsCompleted: steps.length,
      totalPoints: steps.reduce((sum, s) => sum + Number(s.pointsAwarded), 0),
      steps: steps.map((s) => ({
        stepId: s.id,
        soNumber: s.trailer.soNumber,
        model: s.trailer.trailerModel.displayName,
        series: s.trailer.trailerModel.series,
        department: s.department.displayName,
        workerName: s.completedByUser?.fullName ?? null,
        pointsAwarded: Number(s.pointsAwarded),
        completedAt: s.completedAt,
      })),
      workerSummary: Array.from(workerMap.values()).sort(
        (a, b) => b.totalPoints - a.totalPoints,
      ),
    };
  }

  async lockAndSendWeeklyReport(weekStart: string, userId: number, ipAddress?: string) {
    const weekDate = new Date(weekStart);
    if (weekDate.getUTCDay() !== 0) {
      throw new AppError(
        ErrorCode.INVALID_WEEK_START,
        'The provided week_start date is not a Sunday',
      );
    }

    // Check if already locked
    const existingLocked = await this.prisma.payrollRecord.findFirst({
      where: {
        weekStartDate: weekDate,
        isLocked: true,
      },
      select: { id: true },
    });

    if (existingLocked) {
      throw new AppError(
        ErrorCode.PAYROLL_WEEK_LOCKED,
        'Payroll for this week has been locked',
      );
    }

    // Lock all payroll records for this week
    const result = await this.prisma.payrollRecord.updateMany({
      where: {
        weekStartDate: weekDate,
        isLocked: false,
      },
      data: {
        isLocked: true,
        lockedByUserId: BigInt(userId),
        lockedAt: new Date(),
      },
    });

    await this.auditLogService.create({
      userId,
      entityType: 'payroll_week',
      entityId: 0, // Week-level operation
      action: 'LOCK',
      newValues: { weekStart, recordsLocked: result.count },
      ipAddress: ipAddress ?? null,
    });

    return {
      weekStart,
      recordsLocked: result.count,
      lockedAt: new Date().toISOString(),
    };
  }
}
