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

const PAINT_A_CODE = 'PAINT_A';
const PAINT_B_CODE = 'PAINT_B';

@Injectable()
export class WorkflowGeneratorService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Reads workflow_templates for the given series and atomically creates
   * all 12 production_steps rows inside the provided transaction client.
   *
   * - First non-QC step → status = active, becameActiveAt = now
   * - All subsequent steps → status = waiting
   *
   * Paint booth routing:
   * - gooseneck_dump → always PAINT_B (template value, no override)
   * - all other series → PAINT_A or PAINT_B, picking whichever has the
   *   smaller active+waiting queue at the moment this trailer is created.
   *   Tie-breaks to PAINT_A.
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
      include: { department: { select: { id: true, code: true, isQcStep: true } } },
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

    // For non-GN/Dump series, resolve which paint booth this trailer should
    // go to based on current queue depth. Resolved once per trailer so all
    // production_steps land in the same booth.
    const paintBoothDeptId =
      series === TrailerSeries.gooseneck_dump
        ? null
        : await this.pickLighterPaintBooth(tx);

    const now = new Date();
    let firstActiveStepId: bigint | null = null;

    // Create all 12 production steps
    for (const template of templates) {
      // First non-QC step (step_order=1) is always a production step → active
      const isFirstStep = template.stepOrder === 1;
      const status: ProductionStepStatus = isFirstStep
        ? ProductionStepStatus.active
        : ProductionStepStatus.waiting;

      const isPaintBoothStep =
        template.department.code === PAINT_A_CODE ||
        template.department.code === PAINT_B_CODE;
      const departmentId =
        isPaintBoothStep && paintBoothDeptId !== null
          ? paintBoothDeptId
          : template.departmentId;

      const step = await tx.productionStep.create({
        data: {
          trailerId,
          departmentId,
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

  /**
   * Returns the department ID of whichever paint booth (A or B) currently
   * has fewer active+waiting production_steps assigned to it. Ties go to A.
   *
   * If either booth is missing from the departments table the lookup falls
   * back to the other booth; if both are missing it throws — that's a seed
   * misconfiguration the caller should hear about.
   */
  private async pickLighterPaintBooth(
    tx: Prisma.TransactionClient,
  ): Promise<number> {
    const booths = await tx.department.findMany({
      where: { code: { in: [PAINT_A_CODE, PAINT_B_CODE] } },
      select: { id: true, code: true },
    });

    const paintA = booths.find((b) => b.code === PAINT_A_CODE);
    const paintB = booths.find((b) => b.code === PAINT_B_CODE);

    if (!paintA && !paintB) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'PAINT_A and PAINT_B departments are missing — seed misconfiguration',
      );
    }
    if (!paintA) return paintB!.id;
    if (!paintB) return paintA.id;

    const [countA, countB] = await Promise.all([
      tx.productionStep.count({
        where: {
          departmentId: paintA.id,
          status: {
            in: [ProductionStepStatus.active, ProductionStepStatus.waiting],
          },
        },
      }),
      tx.productionStep.count({
        where: {
          departmentId: paintB.id,
          status: {
            in: [ProductionStepStatus.active, ProductionStepStatus.waiting],
          },
        },
      }),
    ]);

    return countB < countA ? paintB.id : paintA.id;
  }
}
