import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../../prisma/prisma.service';

/**
 * Periodically prunes log tables that would otherwise grow unbounded —
 * audit_log (written on every mutating request) and sms_log (one row per
 * outbound SMS). Retention defaults to 90 days; override with
 * AUDIT_LOG_RETENTION_DAYS in the environment.
 *
 * Runs daily at 03:00 server-time. Using a fixed time of day keeps the
 * delete off the production hot path even if the API is replicated later.
 */
@Injectable()
export class LogPruningService {
  private readonly logger = new Logger(LogPruningService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  /** Retention window in days, read once per invocation so env changes
   *  take effect on the next run without a restart. */
  private get retentionDays(): number {
    const raw = this.config.get<string>('AUDIT_LOG_RETENTION_DAYS');
    const parsed = raw ? parseInt(raw, 10) : NaN;
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 90;
  }

  @Cron(CronExpression.EVERY_DAY_AT_3AM, { name: 'log-pruning' })
  async pruneOldLogs(): Promise<void> {
    const cutoff = new Date(
      Date.now() - this.retentionDays * 24 * 60 * 60 * 1000,
    );

    try {
      // audit_log uses createdAt; sms_log uses sentAt — both indexed,
      // but the column names differ in the schema.
      const [audit, sms] = await Promise.all([
        this.prisma.auditLog.deleteMany({
          where: { createdAt: { lt: cutoff } },
        }),
        this.prisma.smsLog.deleteMany({
          where: { sentAt: { lt: cutoff } },
        }),
      ]);
      this.logger.log(
        `Pruned logs older than ${this.retentionDays} days (cutoff ${cutoff.toISOString()}): ` +
          `audit_log=${audit.count}, sms_log=${sms.count}`,
      );
    } catch (err) {
      // Never let a failing prune crash the API. Log and try again
      // tomorrow — disk pressure builds over weeks, not hours.
      this.logger.error(
        `Log pruning failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }
}
