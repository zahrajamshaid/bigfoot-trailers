import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { SmsService } from '../notifications/sms.service';

@Injectable()
export class SmsQueueProcessor implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SmsQueueProcessor.name);
  private processing = false;
  private intervalRef: ReturnType<typeof setInterval> | null = null;

  constructor(private readonly smsService: SmsService) {}

  onModuleInit() {
    // Process queued SMS every 30 seconds
    this.intervalRef = setInterval(() => this.processQueue(), 30_000);
    this.logger.log('SMS queue processor started (30s interval)');
  }

  onModuleDestroy() {
    if (this.intervalRef) {
      clearInterval(this.intervalRef);
      this.intervalRef = null;
    }
  }

  async processQueue() {
    if (this.processing) return;
    this.processing = true;

    try {
      const count = await this.smsService.processQueuedMessages();
      if (count > 0) {
        this.logger.log(`Processed ${count} queued SMS messages`);
      }
    } catch (err: any) {
      this.logger.error(`SMS queue processing failed: ${err?.message}`);
    } finally {
      this.processing = false;
    }
  }
}
