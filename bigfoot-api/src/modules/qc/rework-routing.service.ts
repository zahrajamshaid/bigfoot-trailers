import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { AppError, ErrorCode } from '../../common/errors';
import { ProductionStepStatus, Prisma } from '@prisma/client';

export interface ReworkResult {
  reworkStepId: bigint;
  reworkTargetDeptId: number;
  reworkTargetDepartment: string;
  reworkQueuePosition: number;
}

@Injectable()
export class ReworkRoutingService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Validates the rework target department is valid for this trailer's series,
   * then routes the trailer to that department at queue position #1.
   *
   * Must be called inside a transaction for atomicity.
   */
  async routeRework(
    trailerId: bigint,
    targetDepartmentId: number,
    failNotes: string | null,
    tx: Prisma.TransactionClient,
  ): Promise<ReworkResult> {
    // 1. Get the trailer's series from its model (for error context)
    const trailer = await tx.trailer.findUnique({
      where: { id: trailerId },
      select: {
        trailerModel: { select: { series: true } },
      },
    });

    if (!trailer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${trailerId} not found`);
    }

    // 2. Validate the target against the trailer's OWN production steps.
    //
    // A valid rework target is any department this trailer actually has a
    // production step in — that set *is* the trailer's real workflow. It can
    // legitimately diverge from the series' workflow_templates: the paint
    // booth swap (PAINT_A ⇄ PAINT_B) and the wire/hydraulics swap repoint a
    // step's department without touching the template. Validating against the
    // template instead rejected any trailer sitting on the "other" side of one
    // of those swaps — e.g. a Yeti moved to PAINT_B when the template names
    // PAINT_A — with "this department is not in the trailer's workflow", even
    // though PAINT_B is exactly where the trailer physically is. Checking the
    // production step directly fixes that permanently and generally.
    const reworkStep = await tx.productionStep.findFirst({
      where: {
        trailerId,
        departmentId: targetDepartmentId,
      },
      select: {
        id: true,
        reworkCount: true,
        department: {
          select: { id: true, code: true, displayName: true, isQcStep: true },
        },
      },
    });

    if (!reworkStep) {
      throw new AppError(
        ErrorCode.QC_INVALID_REWORK_TARGET,
        `Department ${targetDepartmentId} is not part of trailer ${trailerId}'s workflow (series ${trailer.trailerModel.series})`,
      );
    }

    // 4. Bump existing active steps in this department down by 1 position
    //    to make room at position #1
    await tx.productionStep.updateMany({
      where: {
        departmentId: targetDepartmentId,
        status: ProductionStepStatus.active,
        queuePosition: { not: null },
      },
      data: {
        queuePosition: { increment: 1 },
      },
    });

    // 5. Set the rework step: is_rework=TRUE, rework_count+1, status=active, queue_position=1
    await tx.productionStep.update({
      where: { id: reworkStep.id },
      data: {
        isRework: true,
        reworkCount: reworkStep.reworkCount + 1,
        status: ProductionStepStatus.active,
        queuePosition: 1,
        becameActiveAt: new Date(),
        completedAt: null,
        completedByUserId: null,
        pointsAwarded: 0,
      },
    });

    return {
      reworkStepId: reworkStep.id,
      reworkTargetDeptId: reworkStep.department.id,
      reworkTargetDepartment: reworkStep.department.displayName,
      reworkQueuePosition: 1,
    };
  }
}
