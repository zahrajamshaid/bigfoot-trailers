import { Injectable } from '@nestjs/common';
import { PushService } from './push.service';
import { SmsService } from './sms.service';
import { NotificationsGateway, WsEvent } from './notifications.gateway';
import { NotificationType, SmsType } from '@prisma/client';

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
  ) {}

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
      this.gateway.emitToDepartment(payload.nextDepartmentId, WsEvent.STEP_COMPLETED, data);
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
