import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { TrailerSeries, ProductionStepStatus, Prisma } from '@prisma/client';
import { AppError, ErrorCode } from '../../common/errors';

export interface GeneratedStepsSummary {
  trailerId: bigint;
  series: TrailerSeries;
  totalSteps: number;
  // Null for inventory-only models — no production steps, nothing to start.
  firstActiveStepId: bigint | null;
}

const PAINT_A_CODE = 'PAINT_A';
const PAINT_B_CODE = 'PAINT_B';

// PAINT_A is the smaller booth — only fits trailers under this length.
// Anything at or above goes to PAINT_B regardless of queue balance.
const PAINT_A_MAX_FT = 25;

// trailer.sizeFt is a free-form string (we backfilled out the trailing "ft"
// suffix). Parse it tolerantly: pull the first integer/decimal we see; if
// nothing parses, return null and let queue-balance pick.
function parseSizeFt(sizeFt: string | null | undefined): number | null {
  if (!sizeFt) return null;
  const m = String(sizeFt).match(/(\d+(?:\.\d+)?)/);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) ? n : null;
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
    sizeFt?: string | null,
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

    // Paint booth routing:
    //   gn_dump → always PAINT_B (template default, no override)
    //   length ≥ PAINT_A_MAX_FT → force PAINT_B (PAINT_A is physically smaller)
    //   otherwise → queue-balance pick between A and B
    // Resolved once per trailer so every paint step lands in the same booth.
    const lengthFt = parseSizeFt(sizeFt);
    const forcePaintB =
      lengthFt !== null && lengthFt >= PAINT_A_MAX_FT;

    // gooseneck_dump + gooseneck_yeti both hardcode PAINT_B via the
    // workflow template, so we leave paintBoothDeptId null for them and
    // let template.departmentId carry through.
    const isGooseneck =
      series === TrailerSeries.gooseneck_dump ||
      series === TrailerSeries.gooseneck_yeti;
    let paintBoothDeptId: number | null = null;
    if (!isGooseneck) {
      paintBoothDeptId = forcePaintB
        ? await this.resolvePaintBoothId(tx, PAINT_B_CODE)
        : await this.pickLighterPaintBooth(tx);
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
  // Returns the requested booth's department id. Falls back to the other
  // booth if the requested one is missing (seed-misconfiguration tolerance —
  // matches the pickLighterPaintBooth behaviour).
  private async resolvePaintBoothId(
    tx: Prisma.TransactionClient,
    preferredCode: 'PAINT_A' | 'PAINT_B',
  ): Promise<number> {
    const booths = await tx.department.findMany({
      where: { code: { in: [PAINT_A_CODE, PAINT_B_CODE] } },
      select: { id: true, code: true },
    });
    const preferred = booths.find((b) => b.code === preferredCode);
    if (preferred) return preferred.id;
    const fallback = booths.find((b) => b.code !== preferredCode);
    if (!fallback) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'PAINT_A and PAINT_B departments are missing — seed misconfiguration',
      );
    }
    return fallback.id;
  }

  private async pickLighterPaintBooth(tx: Prisma.TransactionClient): Promise<number> {
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
