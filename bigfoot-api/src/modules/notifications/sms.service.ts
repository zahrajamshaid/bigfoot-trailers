import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../../prisma/prisma.service';
import { SmsStatus, SmsType } from '@prisma/client';

// ---------------------------------------------------------------------------
// Twilio client — lazy-loaded for graceful degradation.
// Minimal structural type covering only the surface this service uses.
// ---------------------------------------------------------------------------
interface TwilioClient {
  messages: {
    create(opts: { to: string; from?: string; body: string }): Promise<{ sid: string }>;
  };
}

let twilioClient: TwilioClient | null = null;

export interface SmsPayload {
  trailerId?: bigint;
  deliveryId?: bigint;
  recipientPhone: string;
  smsType: SmsType;
  messageBody: string;
}

@Injectable()
export class SmsService implements OnModuleInit {
  private readonly logger = new Logger(SmsService.name);
  private twilioInitialised = false;

  constructor(
    private readonly configService: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  async onModuleInit() {
    try {
      const accountSid = this.configService.get<string>('TWILIO_ACCOUNT_SID');
      const authToken = this.configService.get<string>('TWILIO_AUTH_TOKEN');

      if (accountSid && authToken) {
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        const twilio = require('twilio');
        twilioClient =
          typeof twilio === 'function'
            ? twilio(accountSid, authToken)
            : twilio.default(accountSid, authToken);
        this.twilioInitialised = true;
        this.logger.log('Twilio client initialised');
      } else {
        this.logger.warn('Twilio credentials not configured — SMS disabled');
      }
    } catch {
      this.logger.warn('twilio not available — SMS disabled');
    }
  }

  // -------------------------------------------------------------------------
  // Queue an SMS — creates SmsLog with status=queued
  // -------------------------------------------------------------------------
  async queueSms(payload: SmsPayload): Promise<bigint> {
    const record = await this.prisma.smsLog.create({
      data: {
        trailerId: payload.trailerId ?? null,
        deliveryId: payload.deliveryId ?? null,
        recipientPhone: payload.recipientPhone,
        smsType: payload.smsType,
        messageBody: payload.messageBody,
        status: SmsStatus.queued,
      },
      select: { id: true },
    });

    return record.id;
  }

  // -------------------------------------------------------------------------
  // Send a single SMS by SmsLog id — called by SmsQueueProcessor
  // -------------------------------------------------------------------------
  async sendById(smsLogId: bigint): Promise<void> {
    const smsLog = await this.prisma.smsLog.findUnique({
      where: { id: smsLogId },
      select: {
        id: true,
        recipientPhone: true,
        messageBody: true,
        status: true,
      },
    });

    if (!smsLog || smsLog.status !== SmsStatus.queued) return;

    if (!this.twilioInitialised || !twilioClient) {
      this.logger.warn(`SMS ${smsLogId} skipped — Twilio not initialised`);
      return;
    }

    const fromNumber = this.configService.get<string>('TWILIO_FROM_NUMBER');

    try {
      const message = await twilioClient.messages.create({
        to: smsLog.recipientPhone,
        from: fromNumber,
        body: smsLog.messageBody,
      });

      await this.prisma.smsLog.update({
        where: { id: smsLogId },
        data: {
          twilioSid: message.sid,
          status: SmsStatus.sent,
          sentAt: new Date(),
        },
      });
    } catch (err) {
      this.logger.error(`SMS ${smsLogId} failed: ${(err as Error)?.message}`);
      await this.prisma.smsLog.update({
        where: { id: smsLogId },
        data: { status: SmsStatus.failed },
      });
    }
  }

  // -------------------------------------------------------------------------
  // Send immediately (bypasses queue) — used for manual dispatch
  // -------------------------------------------------------------------------
  async sendImmediately(smsLogId: bigint): Promise<void> {
    return this.sendById(smsLogId);
  }

  // -------------------------------------------------------------------------
  // Process all queued SMS (called by BullMQ processor)
  // -------------------------------------------------------------------------
  async processQueuedMessages(): Promise<number> {
    const queued = await this.prisma.smsLog.findMany({
      where: { status: SmsStatus.queued },
      select: { id: true },
      orderBy: { id: 'asc' },
      take: 50,
    });

    let sent = 0;
    for (const sms of queued) {
      try {
        await this.sendById(sms.id);
        sent++;
      } catch {
        // Individual failures already logged in sendById
      }
    }

    return sent;
  }

  // -------------------------------------------------------------------------
  // Update SMS status from Twilio webhook (delivery callback)
  // -------------------------------------------------------------------------
  async updateStatus(twilioSid: string, status: 'delivered' | 'failed'): Promise<void> {
    const smsStatus = status === 'delivered' ? SmsStatus.delivered : SmsStatus.failed;

    await this.prisma.smsLog.updateMany({
      where: { twilioSid },
      data: { status: smsStatus },
    });
  }
}
