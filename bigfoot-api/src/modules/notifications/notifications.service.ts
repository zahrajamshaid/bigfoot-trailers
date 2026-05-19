import { Injectable } from '@nestjs/common';
import { PushService } from './push.service';
import { SmsService } from './sms.service';
import { NotificationsGateway, WsEvent } from './notifications.gateway';
import { PrismaService } from '../../prisma/prisma.service';
import { AppError, ErrorCode } from '../../common/errors';

// ---------------------------------------------------------------------------
// Payload interfaces for each notification scenario
// ---------------------------------------------------------------------------

export interface StepCompletedPayload {
  stepId: bigint;
  trailerId: bigint;
  soNumber: string;
  departmentId: number;
  departmentName: string;
  nextStepId?: bigint | null;
  nextDepartmentId?: number | null;
  nextDepartmentName?: string | null;
  /** True when the next step is in a QC department — drives the qc_ready push. */
  nextDepartmentIsQc?: boolean;
  completedByUserId: bigint;
  pointsAwarded: number;
}

export interface StepReversedPayload {
  stepId: bigint;
  trailerId: bigint;
  soNumber: string;
  departmentId: number;
  departmentName: string;
  reversedByUserId: bigint;
}

export interface QcPassPayload {
  inspectionId: bigint;
  trailerId: bigint;
  soNumber: string;
  qcStep: string;
  qcDepartmentId: number;
  nextStepId?: bigint | null;
  nextDepartmentId?: number | null;
  nextDepartmentName?: string | null;
  isFinalQc: boolean;
  trailerStatus: string;
}

export interface QcFailPayload {
  inspectionId: bigint;
  trailerId: bigint;
  soNumber: string;
  qcStep: string;
  qcDepartmentId: number;
  failNotes: string;
  reworkTargetDeptId: number;
  reworkTargetDepartment: string;
  reworkStepId: bigint;
}

export interface DeliveryDispatchedPayload {
  deliveryId: bigint;
  trailerId: bigint;
  soNumber: string;
  driverUserId?: bigint | null;
}

export interface DeliveryCompletePayload {
  deliveryId: bigint;
  trailerId: bigint;
  soNumber: string;
  balanceDue: string;
  paymentCollected: string;
}

export interface PointsUpdatedPayload {
  userId: bigint;
  trailerId: bigint;
  soNumber: string;
  departmentName: string;
  pointsAwarded: number;
}

export interface TrailerStalledPayload {
  trailerId: bigint;
  soNumber: string;
  departmentId: number;
  departmentName: string;
  hoursStalled: number;
  stallAlertId: bigint;
}

export interface QueueReorderedPayload {
  departmentId: number;
  departmentName: string;
}

export interface PriorityChangedPayload {
  trailerId: bigint;
  soNumber: string;
  globalPriority: number;
  isHot: boolean;
}

@Injectable()
export class NotificationsService {
  constructor(
    private readonly pushService: PushService,
    private readonly smsService: SmsService,
    private readonly gateway: NotificationsGateway,
    private readonly prisma: PrismaService,
  ) {}

  // =========================================================================
  // NOTIFICATION HISTORY — authenticated user push history
  // =========================================================================
  async getHistory(userId: bigint, page = 1, limit = 100) {
    const safePage = Number.isFinite(page) && page > 0 ? page : 1;
    const safeLimit = Number.isFinite(limit) ? Math.min(Math.max(limit, 1), 200) : 100;

    const skip = (safePage - 1) * safeLimit;

    const [items, total] = await Promise.all([
      this.prisma.pushNotification.findMany({
        where: { recipientUserId: userId },
        orderBy: { createdAt: 'desc' },
        skip,
        take: safeLimit,
      }),
      this.prisma.pushNotification.count({
        where: { recipientUserId: userId },
      }),
    ]);

    return {
      items: items.map((n) => ({
        id: n.id.toString(),
        type: n.notificationType,
        title: n.title,
        body: n.body,
        isRead: n.isRead,
        timestamp: n.createdAt.toISOString(),
      })),
      page: safePage,
      limit: safeLimit,
      total,
      unreadCount: items.filter((n) => !n.isRead).length,
    };
  }

  // =========================================================================
  // DELETE NOTIFICATION — remove a single notification from the user history
  // =========================================================================
  async deleteNotification(userId: bigint, notificationId: bigint) {
    // Scope the delete to the requesting user so one user can never remove
    // another's notifications. deleteMany returns a count instead of throwing
    // on no match, letting us return a clean 404 ourselves.
    const result = await this.prisma.pushNotification.deleteMany({
      where: { id: notificationId, recipientUserId: userId },
    });

    if (result.count === 0) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Notification with id ${notificationId} not found`,
      );
    }

    return { deleted: true };
  }

  // =========================================================================
  // STEP_COMPLETED — fires on dept channel + next QC dept channel
  // =========================================================================
  async onStepCompleted(payload: StepCompletedPayload) {
    const data = {
      stepId: payload.stepId.toString(),
      trailerId: payload.trailerId.toString(),
      soNumber: payload.soNumber,
      departmentName: payload.departmentName,
      nextStepId: payload.nextStepId?.toString() ?? null,
      nextDepartmentName: payload.nextDepartmentName ?? null,
      completedByUserId: payload.completedByUserId.toString(),
      pointsAwarded: payload.pointsAwarded,
    };

    // Emit to the completing department
    this.gateway.emitToDepartment(payload.departmentId, WsEvent.STEP_COMPLETED, data);

    // Also emit to the next department (the QC dept)
    if (payload.nextDepartmentId) {
      this.gateway.emitToDepartment(
        payload.nextDepartmentId,
        WsEvent.STEP_COMPLETED,
        data,
      );
    }

    // Push notification to QC inspectors when the next step is QC. WS pushes
    // refresh open queues, but inspectors with the app backgrounded only
    // hear about it via Firebase.
    if (
      payload.nextDepartmentIsQc &&
      payload.nextDepartmentId &&
      payload.nextStepId &&
      payload.nextDepartmentName
    ) {
      await this.pushService.sendQcReady(
        payload.trailerId,
        payload.soNumber,
        payload.nextDepartmentName,
        payload.nextDepartmentId,
        payload.nextStepId,
      );
    }
  }

  // =========================================================================
  // STEP_REVERSED
  // =========================================================================
  async onStepReversed(payload: StepReversedPayload) {
    const data = {
      stepId: payload.stepId.toString(),
      trailerId: payload.trailerId.toString(),
      soNumber: payload.soNumber,
      departmentName: payload.departmentName,
      reversedByUserId: payload.reversedByUserId.toString(),
    };

    this.gateway.emitToDepartment(payload.departmentId, WsEvent.STEP_REVERSED, data);
  }

  // =========================================================================
  // QC_PASS — fires on QC dept channel + next production dept channel
  // =========================================================================
  async onQcPass(payload: QcPassPayload) {
    const data = {
      inspectionId: payload.inspectionId.toString(),
      trailerId: payload.trailerId.toString(),
      soNumber: payload.soNumber,
      qcStep: payload.qcStep,
      nextStepId: payload.nextStepId?.toString() ?? null,
      nextDepartmentName: payload.nextDepartmentName ?? null,
      isFinalQc: payload.isFinalQc,
      trailerStatus: payload.trailerStatus,
    };

    this.gateway.emitToDepartment(payload.qcDepartmentId, WsEvent.QC_PASS, data);

    if (payload.nextDepartmentId) {
      this.gateway.emitToDepartment(payload.nextDepartmentId, WsEvent.QC_PASS, data);
    }

    // If final QC, also emit TRAILER_READY
    if (payload.isFinalQc) {
      this.gateway.emitToAlerts(WsEvent.TRAILER_READY, {
        trailerId: payload.trailerId.toString(),
        soNumber: payload.soNumber,
        trailerStatus: 'ready_for_delivery',
      });
    }
  }

  // =========================================================================
  // QC_FAIL — fires on BOTH target dept AND alerts channel + push
  // =========================================================================
  async onQcFail(payload: QcFailPayload) {
    const data = {
      inspectionId: payload.inspectionId.toString(),
      qcStep: payload.qcStep,
      failNotes: payload.failNotes,
      reworkTargetDeptId: payload.reworkTargetDeptId,
      reworkTargetDepartment: payload.reworkTargetDepartment,
      reworkStepId: payload.reworkStepId.toString(),
      trailerId: payload.trailerId.toString(),
      soNumber: payload.soNumber,
    };

    // Emit to target department AND alerts (per spec section 10.4)
    this.gateway.emitToDepartment(payload.reworkTargetDeptId, WsEvent.QC_FAIL, data);
    this.gateway.emitToAlerts(WsEvent.QC_FAIL, data);

    // Push notification to production_managers
    await this.pushService.sendQcFail(
      payload.trailerId,
      payload.soNumber,
      payload.qcStep,
      payload.failNotes,
      payload.reworkTargetDepartment,
      payload.reworkTargetDeptId,
    );
  }

  // =========================================================================
  // TRAILER_READY — emitted via onQcPass when isFinalQc === true
  // =========================================================================

  // =========================================================================
  // QUEUE_REORDERED
  // =========================================================================
  onQueueReordered(payload: QueueReorderedPayload) {
    this.gateway.emitToDepartment(payload.departmentId, WsEvent.QUEUE_REORDERED, {
      departmentId: payload.departmentId,
      departmentName: payload.departmentName,
    });
  }

  // =========================================================================
  // PRIORITY_CHANGED
  // =========================================================================
  onPriorityChanged(payload: PriorityChangedPayload) {
    this.gateway.emitToAlerts(WsEvent.PRIORITY_CHANGED, {
      trailerId: payload.trailerId.toString(),
      soNumber: payload.soNumber,
      globalPriority: payload.globalPriority,
      isHot: payload.isHot,
    });
  }

  // =========================================================================
  // TRAILER_STALLED — alerts channel + push to PM + owner
  // =========================================================================
  async onTrailerStalled(payload: TrailerStalledPayload) {
    const data = {
      trailerId: payload.trailerId.toString(),
      soNumber: payload.soNumber,
      departmentId: payload.departmentId,
      departmentName: payload.departmentName,
      hoursStalled: payload.hoursStalled,
      stallAlertId: payload.stallAlertId.toString(),
    };

    this.gateway.emitToAlerts(WsEvent.TRAILER_STALLED, data);
    this.gateway.emitToDepartment(payload.departmentId, WsEvent.TRAILER_STALLED, data);

    await this.pushService.sendTrailerStalled(
      payload.trailerId,
      payload.soNumber,
      payload.departmentName,
      payload.hoursStalled,
    );
  }

  // =========================================================================
  // DELIVERY_DISPATCHED
  // =========================================================================
  onDeliveryDispatched(payload: DeliveryDispatchedPayload) {
    this.gateway.emitToAlerts(WsEvent.DELIVERY_DISPATCHED, {
      deliveryId: payload.deliveryId.toString(),
      trailerId: payload.trailerId.toString(),
      soNumber: payload.soNumber,
    });

    if (payload.driverUserId) {
      this.gateway.emitToUser(payload.driverUserId, WsEvent.DELIVERY_DISPATCHED, {
        deliveryId: payload.deliveryId.toString(),
        trailerId: payload.trailerId.toString(),
        soNumber: payload.soNumber,
      });
    }
  }

  // =========================================================================
  // DELIVERY_COMPLETE — alerts channel + push if underpaid
  // =========================================================================
  async onDeliveryComplete(payload: DeliveryCompletePayload) {
    const data = {
      deliveryId: payload.deliveryId.toString(),
      trailerId: payload.trailerId.toString(),
      soNumber: payload.soNumber,
    };

    this.gateway.emitToAlerts(WsEvent.DELIVERY_COMPLETE, data);

    // If underpaid, push notification handled by caller (already in delivery service)
    const balanceDue = parseFloat(payload.balanceDue);
    const paymentCollected = parseFloat(payload.paymentCollected);

    if (balanceDue > 0 && paymentCollected < balanceDue) {
      await this.pushService.sendPaymentNotCollected(
        payload.trailerId,
        payload.soNumber,
        payload.balanceDue,
        payload.paymentCollected,
      );
    }
  }

  // =========================================================================
  // POINTS_UPDATED
  // =========================================================================
  onPointsUpdated(payload: PointsUpdatedPayload) {
    this.gateway.emitToUser(payload.userId, WsEvent.POINTS_UPDATED, {
      trailerId: payload.trailerId.toString(),
      soNumber: payload.soNumber,
      departmentName: payload.departmentName,
      pointsAwarded: payload.pointsAwarded,
    });
  }

  // =========================================================================
  // WORKER_MESSAGE — push to salesperson
  // =========================================================================
  async onWorkerMessage(
    recipientUserId: bigint,
    trailerId: bigint,
    soNumber: string,
    fromUserName: string,
    messageText: string,
  ) {
    this.gateway.emitToUser(recipientUserId, WsEvent.WORKER_MESSAGE, {
      trailerId: trailerId.toString(),
      soNumber,
      fromUserName,
      messageText,
    });

    await this.pushService.sendWorkerMessage(
      recipientUserId,
      trailerId,
      soNumber,
      fromUserName,
      messageText,
    );
  }
}
