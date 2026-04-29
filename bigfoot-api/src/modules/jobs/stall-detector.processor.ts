import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from '../notifications/notifications.service';
import { Prisma } from '@prisma/client';

@Injectable()
export class StallDetectorProcessor implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(StallDetectorProcessor.name);
  private processing = false;
  private intervalRef: ReturnType<typeof setInterval> | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsService: NotificationsService,
  ) {}

  onModuleInit() {
    // Check for stalled steps every 10 minutes
    this.intervalRef = setInterval(() => this.detectStalls(), 10 * 60_000);
    this.logger.log('Stall detector started (10m interval)');
  }

  onModuleDestroy() {
    if (this.intervalRef) {
      clearInterval(this.intervalRef);
      this.intervalRef = null;
    }
  }

  async detectStalls() {
    if (this.processing) return;
    this.processing = true;

    try {
      const now = new Date();

      // Find all active steps with their department thresholds
      const activeSteps = await this.prisma.productionStep.findMany({
        where: {
          status: 'active',
          becameActiveAt: { not: null },
        },
        select: {
          id: true,
          trailerId: true,
          departmentId: true,
          becameActiveAt: true,
          department: {
            select: {
              id: true,
              displayName: true,
              stallThresholdHours: true,
            },
          },
          trailer: {
            select: {
              id: true,
              soNumber: true,
            },
          },
        },
      });

      for (const step of activeSteps) {
        if (!step.becameActiveAt || !step.department.stallThresholdHours) continue;

        const hoursActive =
          (now.getTime() - step.becameActiveAt.getTime()) / (1000 * 60 * 60);

        if (hoursActive < step.department.stallThresholdHours) continue;

        // Skip if we already have an unresolved alert for this step
        const existingAlert = await this.prisma.stallAlert.findFirst({
          where: {
            productionStepId: step.id,
            resolvedAt: null,
          },
          select: { id: true },
        });

        if (existingAlert) continue;

        // Create stall alert record
        const alert = await this.prisma.stallAlert.create({
          data: {
            trailerId: step.trailerId,
            productionStepId: step.id,
            departmentId: step.departmentId,
            hoursStalled: new Prisma.Decimal(hoursActive.toFixed(1)),
          },
          select: { id: true },
        });

        // Emit WebSocket event + push notification
        await this.notificationsService.onTrailerStalled({
          trailerId: step.trailerId,
          soNumber: step.trailer.soNumber,
          departmentId: step.departmentId,
          departmentName: step.department.displayName,
          hoursStalled: hoursActive,
          stallAlertId: alert.id,
        });

        this.logger.warn(
          `Stall detected: ${step.trailer.soNumber} in ${step.department.displayName} (${hoursActive.toFixed(1)}h)`,
        );
      }
    } catch (err: any) {
      this.logger.error(`Stall detection failed: ${err?.message}`);
    } finally {
      this.processing = false;
    }
  }
}
