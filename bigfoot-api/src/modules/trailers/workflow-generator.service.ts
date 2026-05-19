import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { TrailerSeries, ProductionStepStatus, Prisma } from '@prisma/client';
import { AppError, ErrorCode } from '../../common/errors';

export interface GeneratedStepsSummary {
  trailerId: bigint;
  series: TrailerSeries;
  totalSteps: number;
  firstActiveStepId: bigint;
}

@Injectable()
export class WorkflowGeneratorService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Reads workflow_templates for the given series and atomically creates
   * all 12 production_steps rows inside the provided transaction client.
   *
   * - First non-QC step → status = active, becameActiveAt = now
   * - All subsequent steps → status = waiting
   */
  async generateSteps(
    trailerId: bigint,
    series: TrailerSeries,
    tx: Prisma.TransactionClient,
  ): Promise<GeneratedStepsSummary> {
    // Fetch the ordered workflow templates for this series
    const templates = await tx.workflowTemplate.findMany({
      where: { series },
      orderBy: { stepOrder: 'asc' },
      include: { department: { select: { id: true, isQcStep: true } } },
    });

    if (templates.length === 0) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `No workflow templates found for series "${series}"`,
      );
    }

    if (templates.length !== 12) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `Expected 12 workflow templates for series "${series}", found ${templates.length}`,
      );
    }

    const now = new Date();
    let firstActiveStepId: bigint | null = null;

    // Create all 12 production steps
    for (const template of templates) {
      // First non-QC step (step_order=1) is always a production step → active
      const isFirstStep = template.stepOrder === 1;
      const status: ProductionStepStatus = isFirstStep
        ? ProductionStepStatus.active
        : ProductionStepStatus.waiting;

      const step = await tx.productionStep.create({
        data: {
          trailerId,
          departmentId: template.departmentId,
          stepOrder: template.stepOrder,
          status,
          queuePosition: isFirstStep ? 1 : null,
          becameActiveAt: isFirstStep ? now : null,
        },
        select: { id: true },
      });

      if (isFirstStep) {
        firstActiveStepId = step.id;
      }
    }

    return {
      trailerId,
      series,
      totalSteps: templates.length,
      firstActiveStepId: firstActiveStepId!,
    };
  }
}
