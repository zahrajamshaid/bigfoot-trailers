import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { Prisma } from '@prisma/client';

@Injectable()
export class ReportGeneratorProcessor implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(ReportGeneratorProcessor.name);
  private processing = false;
  private intervalRef: ReturnType<typeof setInterval> | null = null;

  constructor(private readonly prisma: PrismaService) {}

  onModuleInit() {
    // Run every 24 hours — generates/updates payroll records for the current week
    this.intervalRef = setInterval(() => this.generateWeeklyRecords(), 24 * 60 * 60_000);
    this.logger.log('Report generator started (24h interval)');
  }

  onModuleDestroy() {
    if (this.intervalRef) {
      clearInterval(this.intervalRef);
      this.intervalRef = null;
    }
  }

  /**
   * Compute the most recent Sunday (week start) relative to today.
   */
  private getCurrentWeekStart(): Date {
    const now = new Date();
    const day = now.getUTCDay(); // 0 = Sunday
    const diff = now.getUTCDate() - day;
    const sunday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), diff));
    sunday.setUTCHours(0, 0, 0, 0);
    return sunday;
  }

  /**
   * Generate or update PayrollRecord rows for the current week.
   * Aggregates completed (non-rework) production steps per worker per department.
   */
  async generateWeeklyRecords(): Promise<number> {
    if (this.processing) return 0;
    this.processing = true;

    try {
      const weekStart = this.getCurrentWeekStart();
      const weekEnd = new Date(weekStart);
      weekEnd.setUTCDate(weekEnd.getUTCDate() + 7);

      // Don't overwrite locked weeks
      const alreadyLocked = await this.prisma.payrollRecord.findFirst({
        where: { weekStartDate: weekStart, isLocked: true },
        select: { id: true },
      });
      if (alreadyLocked) {
        this.logger.log(
          `Week ${weekStart.toISOString().split('T')[0]} already locked, skipping`,
        );
        return 0;
      }

      // Aggregate completed steps grouped by worker + department
      const completedSteps = await this.prisma.productionStep.findMany({
        where: {
          status: 'complete',
          isRework: false,
          completedAt: { gte: weekStart, lt: weekEnd },
          completedByUserId: { not: null },
        },
        select: {
          completedByUserId: true,
          departmentId: true,
          pointsAwarded: true,
          trailerId: true,
        },
      });

      // Group by (userId, departmentId)
      const aggregateMap = new Map<
        string,
        {
          userId: bigint;
          departmentId: number;
          totalPoints: number;
          trailerIds: Set<string>;
        }
      >();

      for (const step of completedSteps) {
        if (!step.completedByUserId) continue;
        const key = `${step.completedByUserId}_${step.departmentId}`;
        const existing = aggregateMap.get(key);
        const points = Number(step.pointsAwarded);
        if (existing) {
          existing.totalPoints += points;
          existing.trailerIds.add(step.trailerId.toString());
        } else {
          aggregateMap.set(key, {
            userId: step.completedByUserId,
            departmentId: step.departmentId,
            totalPoints: points,
            trailerIds: new Set([step.trailerId.toString()]),
          });
        }
      }

      let upsertCount = 0;
      for (const agg of aggregateMap.values()) {
        await this.prisma.payrollRecord.upsert({
          where: {
            userId_departmentId_weekStartDate: {
              userId: agg.userId,
              departmentId: agg.departmentId,
              weekStartDate: weekStart,
            },
          },
          create: {
            userId: agg.userId,
            departmentId: agg.departmentId,
            weekStartDate: weekStart,
            totalPoints: new Prisma.Decimal(agg.totalPoints.toFixed(2)),
            trailersCompleted: agg.trailerIds.size,
            grossPay: new Prisma.Decimal('0'), // Computed when dollar rates are set
          },
          update: {
            totalPoints: new Prisma.Decimal(agg.totalPoints.toFixed(2)),
            trailersCompleted: agg.trailerIds.size,
          },
        });
        upsertCount++;
      }

      this.logger.log(
        `Weekly records generated: ${upsertCount} records for week ${weekStart.toISOString().split('T')[0]}`,
      );
      return upsertCount;
    } catch (err) {
      this.logger.error(`Report generation failed: ${(err as Error)?.message}`);
      return 0;
    } finally {
      this.processing = false;
    }
  }
}
