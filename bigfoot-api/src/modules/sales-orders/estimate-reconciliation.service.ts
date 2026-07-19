import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { SalesOrderStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { QboApiClient } from '../quickbooks/qbo-api.client';
import { AuditLogService } from '../admin/audit-log.service';
import { NotificationsService } from '../notifications/notifications.service';
import {
  FeatureFlag,
  FeatureFlagsService,
} from '../../common/config/feature-flags.service';
import { SalesOrdersService } from './sales-orders.service';

export interface ReconcileSummary {
  checked: number;
  converted: number;
  stillPending: number;
  failed: number;
}

/**
 * Nightly reconciliation of estimate acceptance FROM QuickBooks.
 *
 * A customer can accept their estimate two ways: by phoning the office (a
 * person clicks Accept in the app) or by clicking the accept link in the QBO
 * email. The second path happens entirely inside QuickBooks — the app never
 * hears about it. This job closes that gap: once a night it asks QBO for the
 * status of every estimate we're still waiting on, and for each one the
 * customer has accepted it converts the Sales Order into a production trailer
 * and notifies the office.
 *
 * "Still waiting on" = approved, pushed to QBO (has a qboEstimateId), and not
 * yet accepted/converted here. Once converted, an SO leaves that set, so the
 * job never touches it again.
 *
 * Inert unless QBO sync is enabled. Every estimate is handled independently in
 * its own try/catch, and the cron never throws — one bad estimate (or a QBO
 * blip) must not stop the rest or crash the scheduler.
 */
@Injectable()
export class EstimateReconciliationService {
  private readonly logger = new Logger(EstimateReconciliationService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly qboClient: QboApiClient,
    private readonly salesOrders: SalesOrdersService,
    private readonly notifications: NotificationsService,
    private readonly audit: AuditLogService,
    private readonly flags: FeatureFlagsService,
  ) {}

  // 03:30 — after log-pruning (03:00), off the daytime hot path.
  @Cron(CronExpression.EVERY_DAY_AT_3AM, { name: 'estimate-acceptance-reconcile' })
  async nightly(): Promise<void> {
    if (!this.flags.isEnabled(FeatureFlag.QBO_SYNC)) return;
    try {
      const summary = await this.reconcileOnce();
      this.logger.log(
        `Estimate reconciliation: checked ${summary.checked}, converted ` +
          `${summary.converted}, still pending ${summary.stillPending}, failed ${summary.failed}`,
      );
    } catch (err) {
      // reconcileOnce already swallows per-estimate errors; this only catches a
      // total failure (e.g. QBO auth down). Log and try again tomorrow.
      this.logger.error(
        `Estimate reconciliation run failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }

  /**
   * Do one reconciliation pass and return what happened. Exposed so the office
   * can trigger it on demand (POST /sales-orders/reconcile-acceptance) instead
   * of waiting for the nightly run.
   */
  async reconcileOnce(): Promise<ReconcileSummary> {
    const open = await this.prisma.salesOrder.findMany({
      where: {
        status: SalesOrderStatus.approved,
        qboEstimateId: { not: null },
        acceptedAt: null,
        trailerId: null,
      },
      select: {
        id: true,
        soNumber: true,
        qboEstimateId: true,
        salesRepUserId: true,
        createdByUserId: true,
        customer: { select: { name: true } },
      },
    });

    const summary: ReconcileSummary = {
      checked: open.length,
      converted: 0,
      stillPending: 0,
      failed: 0,
    };

    for (const so of open) {
      try {
        const est = await this.qboClient.getEstimate(so.qboEstimateId!);
        if (est.TxnStatus !== 'Accepted') {
          summary.stillPending += 1;
          continue;
        }

        // The person who raised the estimate is credited with its conversion —
        // traceable, and no synthetic "system" user needed. accept() writes its
        // own sales_order.converted entry; this one records WHY it happened
        // (the customer accepted in QBO, we detected it), so the trail is honest.
        const actor = so.salesRepUserId ?? so.createdByUserId;
        await this.audit.create({
          userId: Number(actor),
          entityType: 'sales_order',
          entityId: Number(so.id),
          action: 'sales_order.accepted_via_qbo',
          oldValues: { status: SalesOrderStatus.approved },
          newValues: {
            source: 'qbo_nightly_reconciliation',
            qboEstimateId: so.qboEstimateId,
            txnStatus: est.TxnStatus,
          },
        });

        // Already Accepted in QBO — don't push it back.
        const converted = await this.salesOrders.accept(so.id, actor, {
          skipQboAccept: true,
        });

        await this.notifications.onEstimateAccepted({
          soId: so.id,
          soNumber: so.soNumber ?? String(so.id),
          customerName: so.customer.name,
          trailerId: converted.trailerId ? BigInt(converted.trailerId) : undefined,
        });

        summary.converted += 1;
      } catch (err) {
        summary.failed += 1;
        this.logger.error(
          `Reconcile failed for SO ${so.soNumber ?? so.id} (QBO estimate ` +
            `${so.qboEstimateId}): ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }

    return summary;
  }
}
