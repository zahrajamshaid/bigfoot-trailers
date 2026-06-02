import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { AppError, ErrorCode } from '../../common/errors';
import { Prisma } from '@prisma/client';
import {
  CreatePointValueDto,
  UpdatePointValueDto,
  QueryPointValuesDto,
  CreateDollarRateDto,
  QueryDollarRatesDto,
  QueryPayrollRecordsDto,
} from './dto';

@Injectable()
export class PayrollService {
  constructor(private readonly prisma: PrismaService) {}

  // ---------------------------------------------------------------------------
  // GET /payroll/point-values — list point values matrix
  // ---------------------------------------------------------------------------
  async findPointValues(query: QueryPointValuesDto) {
    const where: Prisma.PointValueWhereInput = {};

    if (query.trailerModelId) where.trailerModelId = query.trailerModelId;
    if (query.departmentId) where.departmentId = query.departmentId;

    const page = Math.max(1, query.page ?? 1);
    const limit = Math.min(200, Math.max(1, query.limit ?? 100));

    const [items, total] = await this.prisma.$transaction([
      this.prisma.pointValue.findMany({
        where,
        select: {
          id: true,
          trailerModelId: true,
          departmentId: true,
          points: true,
          effectiveFrom: true,
          effectiveTo: true,
          trailerModel: { select: { id: true, displayName: true, series: true } },
          department: { select: { id: true, code: true, displayName: true } },
        },
        orderBy: [
          { trailerModelId: 'asc' },
          { departmentId: 'asc' },
          { effectiveFrom: 'desc' },
        ],
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.pointValue.count({ where }),
    ]);

    return { items, total, page, limit, totalPages: Math.ceil(total / limit) };
  }

  // ---------------------------------------------------------------------------
  // POST /payroll/point-values — create point value entry
  // ---------------------------------------------------------------------------
  async createPointValue(dto: CreatePointValueDto) {
    // Validate the department is a production (non-QC) department
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

    if (dept.isQcStep) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `Department "${dept.displayName}" is a QC department — QC departments do not award points, so no point value can be set for it`,
      );
    }

    // Validate trailer model exists
    const model = await this.prisma.trailerModel.findUnique({
      where: { id: dto.trailerModelId },
      select: { id: true },
    });

    if (!model) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Trailer model with id ${dto.trailerModelId} not found`,
      );
    }

    return this.prisma.pointValue.create({
      data: {
        trailerModelId: dto.trailerModelId,
        departmentId: dto.departmentId,
        points: new Prisma.Decimal(dto.points),
        effectiveFrom: new Date(dto.effectiveFrom),
      },
      select: {
        id: true,
        trailerModelId: true,
        departmentId: true,
        points: true,
        effectiveFrom: true,
        effectiveTo: true,
        trailerModel: { select: { id: true, displayName: true, series: true } },
        department: { select: { id: true, code: true, displayName: true } },
      },
    });
  }

  // ---------------------------------------------------------------------------
  // PATCH /payroll/point-values/:id — update point value
  // ---------------------------------------------------------------------------
  async updatePointValue(id: number, dto: UpdatePointValueDto) {
    const existing = await this.prisma.pointValue.findUnique({
      where: { id },
      select: { id: true },
    });

    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `Point value with id ${id} not found`);
    }

    const data: Prisma.PointValueUpdateInput = {};
    if (dto.points !== undefined) data.points = new Prisma.Decimal(dto.points);
    if (dto.effectiveTo !== undefined) data.effectiveTo = new Date(dto.effectiveTo);

    return this.prisma.pointValue.update({
      where: { id },
      data,
      select: {
        id: true,
        trailerModelId: true,
        departmentId: true,
        points: true,
        effectiveFrom: true,
        effectiveTo: true,
        trailerModel: { select: { id: true, displayName: true, series: true } },
        department: { select: { id: true, code: true, displayName: true } },
      },
    });
  }

  // ---------------------------------------------------------------------------
  // GET /payroll/dollar-rates — list department dollar-per-point rates
  // ---------------------------------------------------------------------------
  async findDollarRates(query: QueryDollarRatesDto) {
    const where: Prisma.DeptDollarRateWhereInput = {};

    if (query.departmentId) where.departmentId = query.departmentId;

    const page = Math.max(1, query.page ?? 1);
    const limit = Math.min(200, Math.max(1, query.limit ?? 100));

    const [items, total] = await this.prisma.$transaction([
      this.prisma.deptDollarRate.findMany({
        where,
        select: {
          id: true,
          departmentId: true,
          dollarPerPoint: true,
          effectiveFrom: true,
          effectiveTo: true,
          department: { select: { id: true, code: true, displayName: true } },
        },
        orderBy: [{ departmentId: 'asc' }, { effectiveFrom: 'desc' }],
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.deptDollarRate.count({ where }),
    ]);

    return { items, total, page, limit, totalPages: Math.ceil(total / limit) };
  }

  // ---------------------------------------------------------------------------
  // POST /payroll/dollar-rates — create dollar rate entry
  // ---------------------------------------------------------------------------
  async createDollarRate(dto: CreateDollarRateDto) {
    const dept = await this.prisma.department.findUnique({
      where: { id: dto.departmentId },
      select: { id: true, displayName: true },
    });

    if (!dept) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Department with id ${dto.departmentId} not found`,
      );
    }

    return this.prisma.deptDollarRate.create({
      data: {
        departmentId: dto.departmentId,
        dollarPerPoint: new Prisma.Decimal(dto.dollarPerPoint),
        effectiveFrom: new Date(dto.effectiveFrom),
      },
      select: {
        id: true,
        departmentId: true,
        dollarPerPoint: true,
        effectiveFrom: true,
        effectiveTo: true,
        department: { select: { id: true, code: true, displayName: true } },
      },
    });
  }

  // ---------------------------------------------------------------------------
  // GET /payroll/records — get payroll records with filters
  // ---------------------------------------------------------------------------
  async findPayrollRecords(query: QueryPayrollRecordsDto) {
    const where: Prisma.PayrollRecordWhereInput = {};

    if (query.userId) where.userId = BigInt(query.userId);
    if (query.departmentId) where.departmentId = query.departmentId;
    if (query.weekStartDate) where.weekStartDate = new Date(query.weekStartDate);

    const page = Math.max(1, query.page ?? 1);
    const limit = Math.min(200, Math.max(1, query.limit ?? 100));

    const [items, total] = await this.prisma.$transaction([
      this.prisma.payrollRecord.findMany({
        where,
        select: {
          id: true,
          userId: true,
          departmentId: true,
          weekStartDate: true,
          totalPoints: true,
          trailersCompleted: true,
          grossPay: true,
          isLocked: true,
          lockedAt: true,
          createdAt: true,
          user: { select: { id: true, fullName: true, email: true } },
          department: { select: { id: true, code: true, displayName: true } },
          lockedByUser: { select: { id: true, fullName: true } },
        },
        orderBy: [{ weekStartDate: 'desc' }, { userId: 'asc' }, { departmentId: 'asc' }],
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.payrollRecord.count({ where }),
    ]);

    return { items, total, page, limit, totalPages: Math.ceil(total / limit) };
  }

  // ---------------------------------------------------------------------------
  // GET /payroll/records/week/:week_start — full weekly report
  // ---------------------------------------------------------------------------
  async findWeeklyReport(weekStart: string) {
    // Validate week_start is a Sunday
    const weekStartDate = new Date(weekStart);
    if (weekStartDate.getUTCDay() !== 0) {
      throw new AppError(
        ErrorCode.INVALID_WEEK_START,
        `The provided week_start date "${weekStart}" is not a Sunday`,
      );
    }

    // Calculate week end (Saturday)
    const weekEndDate = new Date(weekStartDate);
    weekEndDate.setUTCDate(weekEndDate.getUTCDate() + 6);

    // Find all completed production steps in this week (non-QC departments only)
    const completedSteps = await this.prisma.productionStep.findMany({
      where: {
        completedAt: {
          gte: weekStartDate,
          lt: new Date(weekEndDate.getTime() + 86400000), // end of Saturday
        },
        completedByUserId: { not: null },
        department: { isQcStep: false },
      },
      select: {
        id: true,
        completedByUserId: true,
        departmentId: true,
        pointsAwarded: true,
        isRework: true,
        // Pull the trailer's SO + size + model so the weekly report shows
        // each worker which builds they touched (the team uses this to
        // reconcile pay against the QB orders).
        trailer: {
          select: {
            id: true,
            soNumber: true,
            sizeFt: true,
            trailerModel: {
              select: { id: true, displayName: true, code: true },
            },
          },
        },
        department: { select: { id: true, code: true, displayName: true } },
        completedByUser: { select: { id: true, fullName: true, email: true } },
      },
    });

    // Aggregate per worker → per department → list of trailers touched.
    interface TrailerLine {
      trailerId: string;
      soNumber: string;
      sizeFt: string | null;
      modelName: string | null;
      points: number;
      isRework: boolean;
    }
    const workerMap = new Map<
      string,
      {
        userId: bigint;
        fullName: string;
        email: string | null;
        departments: Map<
          number,
          {
            departmentId: number;
            departmentCode: string;
            departmentName: string;
            totalPoints: number;
            stepsCompleted: number;
            reworkCount: number;
            // Distinct trailers the worker touched in this dept this week.
            // De-duped by trailerId; points accumulate when the same trailer
            // came back through the dept (rework or otherwise).
            trailers: Map<string, TrailerLine>;
          }
        >;
      }
    >();

    for (const step of completedSteps) {
      const userId = step.completedByUserId!;
      const key = userId.toString();

      if (!workerMap.has(key)) {
        workerMap.set(key, {
          userId,
          fullName: step.completedByUser!.fullName,
          email: step.completedByUser!.email,
          departments: new Map(),
        });
      }

      const worker = workerMap.get(key)!;
      const deptId = step.departmentId;

      if (!worker.departments.has(deptId)) {
        worker.departments.set(deptId, {
          departmentId: deptId,
          departmentCode: step.department.code,
          departmentName: step.department.displayName,
          totalPoints: 0,
          stepsCompleted: 0,
          reworkCount: 0,
          trailers: new Map(),
        });
      }

      const deptRecord = worker.departments.get(deptId)!;
      const pts = Number(step.pointsAwarded);
      deptRecord.stepsCompleted += 1;
      deptRecord.totalPoints += pts;
      if (step.isRework) deptRecord.reworkCount += 1;

      // Test mocks sometimes return a step without the full trailer
      // relation populated. Defensive defaults keep the aggregation working
      // and the prod payload includes everything the select asks for.
      if (step.trailer) {
        const trailerKey = step.trailer.id.toString();
        const existing = deptRecord.trailers.get(trailerKey);
        if (existing) {
          existing.points += pts;
          if (step.isRework) existing.isRework = true;
        } else {
          deptRecord.trailers.set(trailerKey, {
            trailerId: trailerKey,
            soNumber: step.trailer.soNumber ?? '',
            sizeFt: step.trailer.sizeFt ?? null,
            modelName:
              step.trailer.trailerModel?.displayName ??
              step.trailer.trailerModel?.code ??
              null,
            points: pts,
            isRework: step.isRework,
          });
        }
      }
    }

    // Look up dollar rates for earnings calculation
    const dollarRates = await this.prisma.deptDollarRate.findMany({
      where: {
        effectiveFrom: { lte: weekEndDate },
        OR: [{ effectiveTo: null }, { effectiveTo: { gte: weekStartDate } }],
      },
      orderBy: { effectiveFrom: 'desc' },
    });

    // Build a map: departmentId -> dollarPerPoint (most recent effective rate)
    const rateMap = new Map<number, number>();
    for (const rate of dollarRates) {
      if (!rateMap.has(rate.departmentId)) {
        rateMap.set(rate.departmentId, Number(rate.dollarPerPoint));
      }
    }

    // Check if the week is locked
    const lockedRecord = await this.prisma.payrollRecord.findFirst({
      where: { weekStartDate: weekStartDate, isLocked: true },
      select: {
        isLocked: true,
        lockedAt: true,
        lockedByUser: { select: { id: true, fullName: true } },
      },
    });

    // Build the report
    const workers = Array.from(workerMap.values()).map((worker) => {
      const departments = Array.from(worker.departments.values()).map((dept) => {
        const dollarPerPoint = rateMap.get(dept.departmentId) ?? 0;
        // Flatten the trailers map → sorted list (SO ascending) and round
        // each line's accumulated points to 2dp for the API payload.
        const trailers = Array.from(dept.trailers.values())
          .map((t) => ({
            trailerId: t.trailerId,
            soNumber: t.soNumber,
            sizeFt: t.sizeFt,
            modelName: t.modelName,
            points: +t.points.toFixed(2),
            isRework: t.isRework,
          }))
          .sort((a, b) =>
              (a.soNumber ?? '').localeCompare(b.soNumber ?? ''));
        return {
          departmentId: dept.departmentId,
          departmentCode: dept.departmentCode,
          departmentName: dept.departmentName,
          totalPoints: dept.totalPoints,
          stepsCompleted: dept.stepsCompleted,
          reworkCount: dept.reworkCount,
          dollarPerPoint,
          grossPay: +(dept.totalPoints * dollarPerPoint).toFixed(2),
          trailers,
        };
      });

      const totalPoints = departments.reduce((sum, d) => sum + d.totalPoints, 0);
      const totalGrossPay = departments.reduce((sum, d) => sum + d.grossPay, 0);
      const totalStepsCompleted = departments.reduce(
        (sum, d) => sum + d.stepsCompleted,
        0,
      );
      const totalReworkCount = departments.reduce((sum, d) => sum + d.reworkCount, 0);

      return {
        userId: worker.userId,
        fullName: worker.fullName,
        email: worker.email,
        totalPoints: +totalPoints.toFixed(2),
        totalGrossPay: +totalGrossPay.toFixed(2),
        totalStepsCompleted,
        totalReworkCount,
        departments,
      };
    });

    // Sort by total points descending
    workers.sort((a, b) => b.totalPoints - a.totalPoints);

    return {
      weekStartDate: weekStart,
      weekEndDate: weekEndDate.toISOString().split('T')[0],
      isLocked: lockedRecord?.isLocked ?? false,
      lockedAt: lockedRecord?.lockedAt ?? null,
      lockedBy: lockedRecord?.lockedByUser ?? null,
      workers,
    };
  }

  // ---------------------------------------------------------------------------
  // POST /payroll/records/lock/:week_start — lock a week's payroll
  // ---------------------------------------------------------------------------
  async lockWeek(weekStart: string, lockedByUserId: bigint) {
    // Validate week_start is a Sunday
    const weekStartDate = new Date(weekStart);
    if (weekStartDate.getUTCDay() !== 0) {
      throw new AppError(
        ErrorCode.INVALID_WEEK_START,
        `The provided week_start date "${weekStart}" is not a Sunday`,
      );
    }

    // Check if already locked
    const existingLocked = await this.prisma.payrollRecord.findFirst({
      where: { weekStartDate: weekStartDate, isLocked: true },
      select: { id: true },
    });

    if (existingLocked) {
      throw new AppError(
        ErrorCode.PAYROLL_WEEK_LOCKED,
        `Payroll for week starting ${weekStart} is already locked`,
      );
    }

    // Calculate week end
    const weekEndDate = new Date(weekStartDate);
    weekEndDate.setUTCDate(weekEndDate.getUTCDate() + 6);

    // Generate/update payroll records from completed steps, then lock them
    return this.prisma.$transaction(async (tx) => {
      // Find all completed production steps in this week (non-QC only)
      const completedSteps = await tx.productionStep.findMany({
        where: {
          completedAt: {
            gte: weekStartDate,
            lt: new Date(weekEndDate.getTime() + 86400000),
          },
          completedByUserId: { not: null },
          department: { isQcStep: false },
        },
        select: {
          completedByUserId: true,
          departmentId: true,
          pointsAwarded: true,
          isRework: true,
        },
      });

      // Aggregate per (user, department)
      const aggregation = new Map<
        string,
        {
          userId: bigint;
          departmentId: number;
          totalPoints: number;
          trailersCompleted: number;
        }
      >();

      for (const step of completedSteps) {
        const key = `${step.completedByUserId!}_${step.departmentId}`;
        if (!aggregation.has(key)) {
          aggregation.set(key, {
            userId: step.completedByUserId!,
            departmentId: step.departmentId,
            totalPoints: 0,
            trailersCompleted: 0,
          });
        }
        const agg = aggregation.get(key)!;
        agg.totalPoints += Number(step.pointsAwarded);
        agg.trailersCompleted += 1;
      }

      // Look up dollar rates
      const dollarRates = await tx.deptDollarRate.findMany({
        where: {
          effectiveFrom: { lte: weekEndDate },
          OR: [{ effectiveTo: null }, { effectiveTo: { gte: weekStartDate } }],
        },
        orderBy: { effectiveFrom: 'desc' },
      });

      const rateMap = new Map<number, number>();
      for (const rate of dollarRates) {
        if (!rateMap.has(rate.departmentId)) {
          rateMap.set(rate.departmentId, Number(rate.dollarPerPoint));
        }
      }

      // Upsert payroll records and lock them
      const records = [];
      for (const agg of aggregation.values()) {
        const dollarPerPoint = rateMap.get(agg.departmentId) ?? 0;
        const grossPay = +(agg.totalPoints * dollarPerPoint).toFixed(2);

        const record = await tx.payrollRecord.upsert({
          where: {
            userId_departmentId_weekStartDate: {
              userId: agg.userId,
              departmentId: agg.departmentId,
              weekStartDate: weekStartDate,
            },
          },
          create: {
            userId: agg.userId,
            departmentId: agg.departmentId,
            weekStartDate: weekStartDate,
            totalPoints: new Prisma.Decimal(agg.totalPoints),
            trailersCompleted: agg.trailersCompleted,
            grossPay: new Prisma.Decimal(grossPay),
            isLocked: true,
            lockedByUserId: lockedByUserId,
            lockedAt: new Date(),
          },
          update: {
            totalPoints: new Prisma.Decimal(agg.totalPoints),
            trailersCompleted: agg.trailersCompleted,
            grossPay: new Prisma.Decimal(grossPay),
            isLocked: true,
            lockedByUserId: lockedByUserId,
            lockedAt: new Date(),
          },
          select: {
            id: true,
            userId: true,
            departmentId: true,
            totalPoints: true,
            trailersCompleted: true,
            grossPay: true,
            isLocked: true,
            lockedAt: true,
          },
        });
        records.push(record);
      }

      return {
        weekStartDate: weekStart,
        isLocked: true,
        lockedAt: new Date(),
        recordsLocked: records.length,
        records,
      };
    });
  }

  // ---------------------------------------------------------------------------
  // GET /payroll/worker/:user_id/summary — real-time current week summary
  // ---------------------------------------------------------------------------
  async getWorkerSummary(userId: bigint) {
    // Validate user exists
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, fullName: true, primaryDepartmentId: true },
    });

    if (!user) {
      throw new AppError(ErrorCode.NOT_FOUND, `User with id ${userId} not found`);
    }

    // Calculate current week's Sunday
    const now = new Date();
    const dayOfWeek = now.getUTCDay(); // 0=Sunday
    const weekStartDate = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - dayOfWeek),
    );
    const weekEndDate = new Date(weekStartDate);
    weekEndDate.setUTCDate(weekEndDate.getUTCDate() + 6);

    // Find all completed production steps for this user this week (non-QC only)
    const completedSteps = await this.prisma.productionStep.findMany({
      where: {
        completedByUserId: userId,
        completedAt: {
          gte: weekStartDate,
          lt: new Date(weekEndDate.getTime() + 86400000),
        },
        department: { isQcStep: false },
      },
      select: {
        departmentId: true,
        pointsAwarded: true,
        isRework: true,
        department: { select: { id: true, code: true, displayName: true } },
      },
    });

    // Aggregate
    let totalPoints = 0;
    let stepsCompleted = 0;
    let reworkCount = 0;
    const departmentBreakdown = new Map<
      number,
      {
        departmentId: number;
        code: string;
        name: string;
        points: number;
        steps: number;
        reworks: number;
      }
    >();

    for (const step of completedSteps) {
      totalPoints += Number(step.pointsAwarded);
      stepsCompleted += 1;
      if (step.isRework) reworkCount += 1;

      const deptId = step.departmentId;
      if (!departmentBreakdown.has(deptId)) {
        departmentBreakdown.set(deptId, {
          departmentId: deptId,
          code: step.department.code,
          name: step.department.displayName,
          points: 0,
          steps: 0,
          reworks: 0,
        });
      }
      const dept = departmentBreakdown.get(deptId)!;
      dept.points += Number(step.pointsAwarded);
      dept.steps += 1;
      if (step.isRework) dept.reworks += 1;
    }

    // Look up dollar rates for projected earnings
    const dollarRates = await this.prisma.deptDollarRate.findMany({
      where: {
        effectiveFrom: { lte: weekEndDate },
        OR: [{ effectiveTo: null }, { effectiveTo: { gte: weekStartDate } }],
      },
      orderBy: { effectiveFrom: 'desc' },
    });

    const rateMap = new Map<number, number>();
    for (const rate of dollarRates) {
      if (!rateMap.has(rate.departmentId)) {
        rateMap.set(rate.departmentId, Number(rate.dollarPerPoint));
      }
    }

    let projectedEarnings = 0;
    const departments = Array.from(departmentBreakdown.values()).map((dept) => {
      const dollarPerPoint = rateMap.get(dept.departmentId) ?? 0;
      const earnings = +(dept.points * dollarPerPoint).toFixed(2);
      projectedEarnings += earnings;
      return { ...dept, dollarPerPoint, projectedEarnings: earnings };
    });

    return {
      userId: user.id,
      fullName: user.fullName,
      weekStartDate: weekStartDate.toISOString().split('T')[0],
      totalPoints: +totalPoints.toFixed(2),
      projectedEarnings: +projectedEarnings.toFixed(2),
      stepsCompleted,
      reworkCount,
      departments,
    };
  }
}
