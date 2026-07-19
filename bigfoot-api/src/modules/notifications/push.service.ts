import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationType } from '@prisma/client';

// ---------------------------------------------------------------------------
// Firebase Admin — lazy-loaded to allow graceful degradation when
// firebase-admin is not installed or credentials are missing.
// Minimal structural types covering only the surface this service uses.
// ---------------------------------------------------------------------------
interface FirebaseMessaging {
  send(message: {
    token: string;
    notification: { title: string; body: string };
    data?: Record<string, string>;
  }): Promise<string>;
}

interface FirebaseAdmin {
  apps?: unknown[];
  initializeApp(config: { credential: unknown }): void;
  credential: { cert(serviceAccount: Record<string, string>): unknown };
  messaging(): FirebaseMessaging;
}

let firebaseAdmin: FirebaseAdmin | null = null;

// ---------------------------------------------------------------------------
// Push notification payloads
// ---------------------------------------------------------------------------
export interface PushPayload {
  recipientUserIds: bigint[];
  trailerId?: bigint;
  notificationType: NotificationType;
  title: string;
  body: string;
  data?: Record<string, string>;
}

@Injectable()
export class PushService implements OnModuleInit {
  private readonly logger = new Logger(PushService.name);
  private fcmInitialised = false;

  constructor(
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  async onModuleInit() {
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const admin: FirebaseAdmin = require('firebase-admin');
      firebaseAdmin = admin;
      const projectId = this.configService.get<string>('FIREBASE_PROJECT_ID');
      const clientEmail = this.configService.get<string>('FIREBASE_CLIENT_EMAIL');
      const privateKey = this.configService.get<string>('FIREBASE_PRIVATE_KEY');

      if (projectId && clientEmail && privateKey) {
        if (!admin.apps?.length) {
          admin.initializeApp({
            credential: admin.credential.cert({
              projectId,
              clientEmail,
              privateKey: privateKey.replace(/\\n/g, '\n'),
            }),
          });
        }
        this.fcmInitialised = true;
        this.logger.log('Firebase Admin SDK initialised');
      } else {
        this.logger.warn(
          'Firebase credentials not configured — push notifications disabled',
        );
      }
    } catch {
      this.logger.warn('firebase-admin not available — push notifications disabled');
    }
  }

  // -------------------------------------------------------------------------
  // Send push + persist PushNotification rows
  // -------------------------------------------------------------------------
  async send(payload: PushPayload): Promise<void> {
    if (payload.recipientUserIds.length === 0) return;

    // 1. Persist push notification records in the database
    await this.prisma.pushNotification.createMany({
      data: payload.recipientUserIds.map((userId) => ({
        recipientUserId: userId,
        trailerId: payload.trailerId ?? null,
        notificationType: payload.notificationType,
        title: payload.title,
        body: payload.body,
      })),
    });

    // 2. Send via FCM if initialised
    if (!this.fcmInitialised || !firebaseAdmin) return;

    // Look up push tokens for recipients
    const users = await this.prisma.user.findMany({
      where: {
        id: { in: payload.recipientUserIds },
        pushToken: { not: null },
        isActive: true,
      },
      select: { id: true, pushToken: true },
    });

    const messaging = firebaseAdmin.messaging();
    const invalidTokenUserIds: bigint[] = [];

    for (const user of users) {
      if (!user.pushToken) continue;

      try {
        await messaging.send({
          token: user.pushToken,
          notification: { title: payload.title, body: payload.body },
          data: payload.data,
        });
      } catch (err) {
        // Handle invalid/expired FCM tokens gracefully
        const fcmError = err as { code?: string; errorInfo?: { code?: string } };
        const errorCode = fcmError?.code ?? fcmError?.errorInfo?.code ?? '';
        if (
          errorCode === 'messaging/registration-token-not-registered' ||
          errorCode === 'messaging/invalid-registration-token'
        ) {
          this.logger.warn(`Invalid FCM token for user ${user.id} — clearing`);
          invalidTokenUserIds.push(user.id);
        } else {
          this.logger.error(
            `FCM send failed for user ${user.id}: ${(err as Error)?.message}`,
          );
        }
      }
    }

    // Clear invalid tokens
    if (invalidTokenUserIds.length > 0) {
      await this.prisma.user.updateMany({
        where: { id: { in: invalidTokenUserIds } },
        data: { pushToken: null },
      });
    }
  }

  // -------------------------------------------------------------------------
  // Convenience methods for each notification type
  // -------------------------------------------------------------------------

  /**
   * QC Ready → all active QC inspectors (any department).
   *
   * Fires when a trailer reaches a QC step, so inspectors get notified even
   * when the app is backgrounded. Production managers / owners deliberately
   * NOT included — they have the dashboard for that.
   */
  async sendQcReady(
    trailerId: bigint,
    soNumber: string,
    qcDepartmentName: string,
    qcDepartmentId: number,
    stepId: bigint,
  ) {
    const inspectors = await this.prisma.user.findMany({
      where: { role: 'qc_inspector', isActive: true },
      select: { id: true },
    });

    if (inspectors.length === 0) return;

    await this.send({
      recipientUserIds: inspectors.map((u) => u.id),
      trailerId,
      notificationType: NotificationType.qc_ready,
      title: `Ready for QC — ${soNumber}`,
      body: `${qcDepartmentName} inspection ready to start.`,
      data: {
        trailerId: trailerId.toString(),
        soNumber,
        qcDepartmentId: qcDepartmentId.toString(),
        stepId: stepId.toString(),
      },
    });
  }

  /** QC Fail → production_manager only */
  async sendQcFail(
    trailerId: bigint,
    soNumber: string,
    qcStep: string,
    failNotes: string,
    reworkTargetDepartment: string,
    reworkTargetDeptId: number,
  ) {
    const managers = await this.prisma.user.findMany({
      where: { role: 'production_manager', isActive: true },
      select: { id: true },
    });

    await this.send({
      recipientUserIds: managers.map((m) => m.id),
      trailerId,
      notificationType: NotificationType.qc_fail,
      title: `QC Fail — ${soNumber}`,
      body: `${qcStep} failed. Rework sent to ${reworkTargetDepartment}. Notes: ${failNotes}`,
      data: {
        trailerId: trailerId.toString(),
        soNumber,
        reworkTargetDeptId: reworkTargetDeptId.toString(),
      },
    });
  }

  /** Jig Queue Low → production_manager only */
  async sendJigQueueLow(
    deptCode: string,
    deptName: string,
    count: number,
  ): Promise<void> {
    const managers = await this.prisma.user.findMany({
      where: { role: 'production_manager', isActive: true },
      select: { id: true },
    });
    if (managers.length === 0) return;
    const noun = count === 1 ? 'trailer' : 'trailers';
    await this.send({
      recipientUserIds: managers.map((m) => m.id),
      notificationType: NotificationType.jig_queue_low,
      title: `Low ${deptName} queue`,
      body:
        `Only ${count} ${noun} left in ${deptName}. ` +
        'Enter more work orders to keep the line fed.',
      data: {
        deptCode,
        count: count.toString(),
      },
    });
  }

  /** Trailer Stalled → production_manager + owner */
  async sendTrailerStalled(
    trailerId: bigint,
    soNumber: string,
    departmentName: string,
    hoursStalled: number,
  ) {
    const recipients = await this.prisma.user.findMany({
      where: { role: { in: ['production_manager', 'owner'] }, isActive: true },
      select: { id: true },
    });

    await this.send({
      recipientUserIds: recipients.map((r) => r.id),
      trailerId,
      notificationType: NotificationType.trailer_stalled,
      title: `Trailer Stalled — ${soNumber}`,
      body: `${departmentName} has been stalled for ${hoursStalled.toFixed(1)} hours`,
      data: { trailerId: trailerId.toString(), soNumber },
    });
  }

  /** Worker Message → assigned salesperson */
  async sendWorkerMessage(
    recipientUserId: bigint,
    trailerId: bigint,
    soNumber: string,
    fromUserName: string,
    messageText: string,
  ) {
    await this.send({
      recipientUserIds: [recipientUserId],
      trailerId,
      notificationType: NotificationType.worker_message,
      title: `Message from ${fromUserName}`,
      body: `${soNumber}: ${messageText.substring(0, 200)}`,
      data: { trailerId: trailerId.toString(), soNumber },
    });
  }

  /** Payment Not Collected → transport_manager */
  async sendPaymentNotCollected(
    trailerId: bigint,
    soNumber: string,
    balanceDue: string,
    paymentCollected: string,
  ) {
    const managers = await this.prisma.user.findMany({
      where: { role: 'transport_manager', isActive: true },
      select: { id: true },
    });

    await this.send({
      recipientUserIds: managers.map((m) => m.id),
      trailerId,
      notificationType: NotificationType.payment_not_collected,
      title: `Payment Not Collected — ${soNumber}`,
      body: `Balance due: $${balanceDue}, collected: $${paymentCollected}`,
      data: { trailerId: trailerId.toString(), soNumber },
    });
  }

  /**
   * A customer accepted their estimate in QuickBooks and the nightly
   * reconciliation converted it into a production trailer. Tell the office +
   * owner so they know a new build just landed without anyone touching the app.
   *
   * trailerId is optional: on the rare estimate whose model didn't resolve to a
   * local model, the SO is marked accepted but no trailer is created — the
   * office still needs to hear about it (and finish it by hand).
   */
  async sendEstimateAccepted(
    soNumber: string,
    customerName: string,
    trailerId?: bigint,
  ) {
    const recipients = await this.prisma.user.findMany({
      where: { role: { in: ['office', 'owner'] }, isActive: true },
      select: { id: true },
    });

    await this.send({
      recipientUserIds: recipients.map((r) => r.id),
      trailerId,
      notificationType: NotificationType.estimate_accepted,
      title: `Estimate accepted — ${soNumber}`,
      body: trailerId
        ? `${customerName} accepted their estimate. It's been converted to a build.`
        : `${customerName} accepted their estimate — no matching model, needs a manual build.`,
      data: {
        soNumber,
        customerName,
        ...(trailerId ? { trailerId: trailerId.toString() } : {}),
      },
    });
  }
}
