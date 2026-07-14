import { Injectable, Logger } from '@nestjs/common';
import { Prisma, SalesOrderStatus } from '@prisma/client';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import {
  FeatureFlag,
  FeatureFlagsService,
} from '../../common/config/feature-flags.service';
import { QboSyncService } from '../quickbooks/qbo-sync.service';
import { QboApiClient } from '../quickbooks/qbo-api.client';
import { TrailersService } from '../trailers/trailers.service';
import { AuditLogService } from '../admin/audit-log.service';
import {
  ConfiguratorService,
  ComposedOrder,
} from './configurator.service';
import {
  CreateSalesOrderDto,
  PreviewSalesOrderDto,
} from './dto/create-sales-order.dto';

/**
 * Sales Order lifecycle: draft (from the configurator) → approved. Approval
 * is where the SO number is allocated (== the trailer number) and, in a later
 * slice, where the QBO Estimate push + trailer creation fire. This slice
 * ships the configurator-to-draft flow + read; the approve method allocates
 * the number and flips status, with QBO push wired in Slice 3.
 */
@Injectable()
export class SalesOrdersService {
  private readonly logger = new Logger('SalesOrders');

  constructor(
    private readonly prisma: PrismaService,
    private readonly configurator: ConfiguratorService,
    private readonly flags: FeatureFlagsService,
    private readonly qboSync: QboSyncService,
    private readonly qboClient: QboApiClient,
    private readonly trailers: TrailersService,
    private readonly audit: AuditLogService,
  ) {}

  /** The QuickBooks estimate PDF bytes for a synced Sales Order. */
  async getEstimatePdf(id: bigint): Promise<Buffer> {
    const so = await this.prisma.salesOrder.findUnique({
      where: { id },
      select: { qboEstimateId: true },
    });
    if (!so) throw new AppError(ErrorCode.NOT_FOUND, `Sales order ${id} not found`);
    if (!so.qboEstimateId) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'This Sales Order has not been pushed to QuickBooks yet — no PDF available',
      );
    }
    return this.qboClient.getEstimatePdf(so.qboEstimateId);
  }

  /**
   * The configurator catalog: active models (each with its applicable
   * options + which are default) + the standard fee set. Everything the
   * mobile configurator screen needs in one call.
   */
  async getCatalog() {
    const [models, options, fees] = await Promise.all([
      this.prisma.trailerModel.findMany({
        where: { isActive: true },
        orderBy: { code: 'asc' },
      }),
      this.prisma.option.findMany({ where: { active: true } }),
      this.prisma.feeSchedule.findMany({ where: { active: true } }),
    ]);
    return {
      models: models.map((m) => ({
        id: m.id,
        code: m.code,
        displayName: m.displayName,
        series: m.series,
        basePrice: m.basePrice ? Number(m.basePrice) : 0,
        hasSpec: m.spec != null,
        options: options
          .filter(
            (o) =>
              o.applicableModelIds.length === 0 ||
              o.applicableModelIds.includes(m.id),
          )
          .map((o) => ({
            id: o.id,
            name: o.name,
            description: o.description,
            price: Number(o.price),
            taxable: o.taxable,
            defaultForModel: o.defaultForModelIds.includes(m.id),
          })),
      })),
      fees: fees.map((f) => ({
        id: f.id,
        name: f.name,
        amount: Number(f.amount),
        autoAdd: f.autoAdd,
      })),
    };
  }

  /** Compose lines + subtotal for a configuration without saving. */
  preview(dto: PreviewSalesOrderDto): Promise<ComposedOrder> {
    return this.configurator.compose({
      modelId: dto.modelId,
      optionIds: dto.optionIds ?? [],
      feeIds: dto.feeIds,
      autoAddFees: dto.autoAddFees ?? false,
    });
  }

  /** Create a persisted draft Sales Order from a configuration. */
  async createDraft(dto: CreateSalesOrderDto, createdByUserId: bigint) {
    const customer = await this.resolveCustomer(dto);

    const composed = await this.configurator.compose({
      modelId: dto.modelId,
      optionIds: dto.optionIds ?? [],
      feeIds: dto.feeIds,
      autoAddFees: dto.autoAddFees ?? false,
    });

    return this.prisma.$transaction(async (tx) => {
      const so = await tx.salesOrder.create({
        data: {
          customerId: customer.id,
          status: SalesOrderStatus.draft,
          salesRepUserId: createdByUserId,
          terms: dto.terms,
          isQuickEstimate: dto.isQuickEstimate ?? !!dto.quickCustomer,
          // Build spec — carried on the estimate, applied to the trailer on
          // convert. This is what the old trailer-create form captured.
          color: dto.color,
          sizeFt: dto.sizeFt,
          optionsNotes: dto.optionsNotes,
          specialNote: dto.specialNote,
          isStockBuild: dto.isStockBuild ?? false,
          stockLocationId: dto.stockLocationId,
          subtotal: new Prisma.Decimal(composed.previewSubtotal),
          // tax + total stay 0 until QBO computes them on push
          total: new Prisma.Decimal(composed.previewSubtotal),
          createdByUserId,
        },
      });
      await tx.salesOrderLine.createMany({
        data: this.configurator.toLineCreateInput(so.id, composed.lines),
      });
      return this.findOneTx(tx, so.id);
    });
  }

  /**
   * Resolve the customer for a new estimate. Either an existing record
   * (`customerId`), or — the Quick Estimate fast lane — a minimal customer
   * created inline from just a name (+ phone/email). An existing customer with
   * the same name is reused rather than duplicated, so a quick quote can be
   * upgraded to a full Sales Order without re-entry or a duplicate record.
   */
  private async resolveCustomer(dto: CreateSalesOrderDto): Promise<{ id: bigint }> {
    if (dto.customerId) {
      const existing = await this.prisma.customer.findUnique({
        where: { id: BigInt(dto.customerId) },
        select: { id: true },
      });
      if (!existing) {
        throw new AppError(ErrorCode.NOT_FOUND, `Customer ${dto.customerId} not found`);
      }
      return existing;
    }

    const quick = dto.quickCustomer;
    if (!quick?.name?.trim()) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'Provide either customerId or quickCustomer.name',
      );
    }
    const name = quick.name.trim();

    // Reuse an exact name match instead of creating a near-duplicate.
    const match = await this.prisma.customer.findFirst({
      where: { name },
      select: { id: true },
    });
    if (match) return match;

    const created = await this.prisma.customer.create({
      data: {
        name: name.slice(0, 200),
        smsPhone: quick.phone?.trim() || null,
        email: quick.email?.trim() || null,
      },
      select: { id: true },
    });

    // Push to QuickBooks like any other customer — non-blocking, so a QBO
    // hiccup never blocks a quote. The nightly recon catches stragglers.
    if (this.flags.isEnabled(FeatureFlag.QBO_SYNC)) {
      try {
        await this.qboSync.ensureCustomer(created.id);
      } catch (e) {
        this.logger.warn(
          `Quick-estimate customer ${created.id} failed to sync to QBO: ${
            e instanceof Error ? e.message : e
          }`,
        );
        await this.prisma.customer.update({
          where: { id: created.id },
          data: { qbSyncState: 'error' },
        });
      }
    }
    return created;
  }

  async findOne(id: bigint) {
    const so = await this.prisma.salesOrder.findUnique({
      where: { id },
      include: {
        lines: { orderBy: { sortOrder: 'asc' } },
        customer: { select: { id: true, name: true, company: true } },
      },
    });
    if (!so) throw new AppError(ErrorCode.NOT_FOUND, `Sales order ${id} not found`);
    return so;
  }

  private async findOneTx(tx: Prisma.TransactionClient, id: bigint) {
    return tx.salesOrder.findUniqueOrThrow({
      where: { id },
      include: {
        lines: { orderBy: { sortOrder: 'asc' } },
        customer: { select: { id: true, name: true, company: true } },
      },
    });
  }

  async list(status?: SalesOrderStatus) {
    return this.prisma.salesOrder.findMany({
      where: status ? { status } : undefined,
      orderBy: { createdAt: 'desc' },
      include: {
        customer: { select: { id: true, name: true, company: true } },
        _count: { select: { lines: true } },
      },
      take: 100,
    });
  }

  /**
   * Approve a draft: allocate the SO number (== trailer number, single
   * sequence) and flip status. QBO Estimate push + trailer creation are
   * wired in Slice 3 — for now approval is the state gate + number allocation.
   */
  async approve(id: bigint, userId?: bigint) {
    const so = await this.prisma.salesOrder.findUnique({ where: { id } });
    if (!so) throw new AppError(ErrorCode.NOT_FOUND, `Sales order ${id} not found`);
    if (so.status !== SalesOrderStatus.draft) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `Only a draft can be approved (status is ${so.status})`,
      );
    }
    const soNumber = so.soNumber ?? (await this.allocateSoNumber());
    // 1) Commit the approval + SO-number allocation FIRST. A failing QBO push
    //    must never roll back the approval (guardrail: app is source of truth).
    await this.prisma.salesOrder.update({
      where: { id },
      data: {
        soNumber,
        status: SalesOrderStatus.approved,
        approvedAt: new Date(),
      },
    });

    // Money-touching action → audit log (Phase 2 guardrail).
    await this.audit.create({
      userId: userId != null ? Number(userId) : undefined,
      entityType: 'sales_order',
      entityId: Number(id),
      action: 'sales_order.approved',
      oldValues: { status: so.status, soNumber: so.soNumber },
      newValues: { status: SalesOrderStatus.approved, soNumber, total: Number(so.total) },
    });

    // 2) Then push to QBO as an Estimate (if QBO sync is on). On failure the
    //    SO is left approved with syncState=error + a retry path — never a
    //    500 out of approve.
    if (this.flags.isEnabled(FeatureFlag.QBO_SYNC)) {
      try {
        await this.qboSync.pushSalesOrderEstimate(id);
      } catch (e) {
        this.logger.error(
          `QBO estimate push failed for SO ${id}: ${e instanceof Error ? e.message : e}`,
        );
        // syncState=error already persisted by the sync service; swallow.
      }
    }

    return this.findOne(id);
  }

  /**
   * Pull estimates FROM QuickBooks into the app (two-way sync). Estimates
   * created directly in QBO show up as Sales Orders here. Idempotent.
   */
  async importFromQbo(userId: bigint) {
    if (!this.flags.isEnabled(FeatureFlag.QBO_SYNC)) {
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        'QuickBooks sync is disabled (QBO_SYNC_ENABLED is off)',
      );
    }
    return this.qboSync.importEstimatesFromQbo(userId);
  }

  /** Re-attempt the QBO estimate push for an approved SO (retry-chip). */
  async retrySync(id: bigint) {
    const so = await this.prisma.salesOrder.findUnique({ where: { id } });
    if (!so) throw new AppError(ErrorCode.NOT_FOUND, `Sales order ${id} not found`);
    if (this.flags.isEnabled(FeatureFlag.QBO_SYNC)) {
      await this.qboSync.pushSalesOrderEstimate(id);
    }
    return this.findOne(id);
  }

  /**
   * Email the estimate to the customer via QuickBooks — the "Send" action in
   * the QBO estimate menu. Uses the customer's email if we have one, else QBO's
   * on-file billing email. Records the send timestamp + QBO email status.
   */
  async sendEstimate(id: bigint) {
    const so = await this.prisma.salesOrder.findUnique({
      where: { id },
      select: {
        qboEstimateId: true,
        customer: { select: { email: true } },
      },
    });
    if (!so) throw new AppError(ErrorCode.NOT_FOUND, `Sales order ${id} not found`);
    if (!so.qboEstimateId) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'This Sales Order has not been pushed to QuickBooks yet — nothing to send',
      );
    }
    let est;
    try {
      est = await this.qboClient.sendEstimate(
        so.qboEstimateId,
        so.customer.email ?? undefined,
      );
    } catch (e) {
      const msg = e instanceof Error ? e.message : '';
      // QuickBooks *sandbox* companies cannot send email — the send endpoint
      // returns a System Failure / NullPointerException. This works against a
      // live company. Surface a clear message instead of the raw Java error.
      if (msg.includes('System Failure') || msg.includes('NullPointer')) {
        throw new AppError(
          ErrorCode.SERVICE_UNAVAILABLE,
          'QuickBooks could not send the email. Sandbox companies cannot send ' +
            'email — this will work once connected to your live QuickBooks company.',
        );
      }
      throw e;
    }
    await this.prisma.salesOrder.update({
      where: { id },
      data: { sentAt: new Date(), emailStatus: est.EmailStatus ?? 'EmailSent' },
    });
    return this.findOne(id);
  }

  /**
   * Convert the estimate to a Sales Order (the customer accepted). Effects:
   *   1) Mark the QBO Estimate Accepted (TxnStatus) — best-effort.
   *   2) If the model line maps to a local trailer model (by refId, or by the
   *      QBO item name matching a model code for estimates imported from QBO),
   *      create the production trailer (the work order) and move the SO into
   *      production. Estimates whose model can't be resolved (e.g. generic
   *      QBO estimates) are still converted — just without a trailer — so the
   *      action never fails with a 400.
   * Idempotent: a second convert is rejected once accepted/converted.
   */
  async accept(id: bigint, userId: bigint) {
    const so = await this.prisma.salesOrder.findUnique({
      where: { id },
      include: { lines: true, customer: true },
    });
    if (!so) throw new AppError(ErrorCode.NOT_FOUND, `Sales order ${id} not found`);
    if (so.status !== SalesOrderStatus.approved) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `Only an approved Sales Order can be converted (status is ${so.status})`,
      );
    }
    if (!so.soNumber) {
      throw new AppError(ErrorCode.BAD_REQUEST, 'Approved SO is missing its number');
    }
    if (so.trailerId || so.acceptedAt) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'This Sales Order has already been converted',
      );
    }

    // Resolve a local trailer model: direct refId (app-built), else match the
    // QBO item name to a model code (imported estimates carry no refId).
    const modelLine = so.lines.find((l) => l.kind === 'model');
    let trailerModelId: number | null = modelLine?.refId ?? null;
    if (!trailerModelId && modelLine?.itemName) {
      const m = await this.prisma.trailerModel.findFirst({
        where: { code: modelLine.itemName },
        select: { id: true },
      });
      trailerModelId = m?.id ?? null;
    }

    // 1) Mark accepted in QBO (best-effort — never blocks the conversion).
    if (this.flags.isEnabled(FeatureFlag.QBO_SYNC) && so.qboEstimateId) {
      try {
        await this.qboClient.acceptEstimate(
          so.qboEstimateId,
          so.customer.name,
          new Date().toISOString().slice(0, 10),
        );
      } catch (e) {
        this.logger.warn(
          `QBO accept failed for SO ${id} (converting anyway): ${e instanceof Error ? e.message : e}`,
        );
      }
    }

    // 2) When the model resolves, build the production trailer (work order).
    let trailerId: bigint | null = null;
    if (trailerModelId) {
      const optionNotes = so.lines
        .filter((l) => l.kind === 'option')
        .map((l) => l.description)
        .join('; ');
      // Stock build: explicit flag on the estimate, or implied by a
      // stock-location customer. Like the trailer-create form, the buyer stays
      // attached either way — a sold trailer can still sit at a yard until
      // pickup; isStockBuild + the destination yard drive the routing.
      const isStock =
        so.isStockBuild || so.customer.customerType === 'stock_location';
      const stockLocationId =
        so.stockLocationId ?? so.customer.stockLocationId ?? undefined;

      // Shop notes = what the rep typed, plus the options they picked.
      const buildNotes = [so.optionsNotes, optionNotes]
        .filter((n): n is string => !!n && n.trim().length > 0)
        .join('; ');

      const { trailer } = await this.trailers.create(
        {
          soNumber: so.soNumber,
          trailerModelId,
          customerId: Number(so.customerId),
          color: so.color ?? undefined,
          sizeFt: so.sizeFt ?? undefined,
          specialNote: so.specialNote ?? undefined,
          optionsNotes: buildNotes || undefined,
          isStockBuild: isStock,
          stockLocationId: isStock ? stockLocationId : undefined,
          qbSoId: so.qboEstimateId ?? undefined,
        },
        userId,
      );
      trailerId = trailer.id;
    } else {
      this.logger.log(
        `SO ${id} converted without a trailer (model line "${modelLine?.itemName ?? modelLine?.description ?? '?'}" matched no local model)`,
      );
    }

    // 3) Record the conversion. Only move into production when a trailer was
    //    actually created; otherwise it stays approved but flagged accepted.
    await this.prisma.salesOrder.update({
      where: { id },
      data: {
        status: trailerId ? SalesOrderStatus.in_production : so.status,
        acceptedAt: new Date(),
        trailerId,
      },
    });

    // Money-touching action → audit log (Phase 2 guardrail).
    await this.audit.create({
      userId: Number(userId),
      entityType: 'sales_order',
      entityId: Number(id),
      action: 'sales_order.converted',
      oldValues: { status: so.status },
      newValues: {
        status: trailerId ? SalesOrderStatus.in_production : so.status,
        trailerId: trailerId ? Number(trailerId) : null,
        soNumber: so.soNumber,
        total: Number(so.total),
      },
    });
    return this.findOne(id);
  }

  /**
   * Allocate the next SO number. The SO number shares the trailer number
   * space, so we take max(existing trailer soNumber, existing sales-order
   * soNumber) + 1. Numeric SO numbers only; non-numeric legacy values are
   * ignored for the max.
   */
  private async allocateSoNumber(): Promise<string> {
    const [maxTrailer, maxSo] = await Promise.all([
      this.prisma.$queryRaw<{ max: number | null }[]>`
        SELECT MAX(CAST(so_number AS INTEGER)) AS max
        FROM trailers WHERE so_number ~ '^[0-9]+$'`,
      this.prisma.$queryRaw<{ max: number | null }[]>`
        SELECT MAX(CAST(so_number AS INTEGER)) AS max
        FROM sales_orders WHERE so_number ~ '^[0-9]+$'`,
    ]);
    const next =
      Math.max(maxTrailer[0]?.max ?? 0, maxSo[0]?.max ?? 0) + 1;
    return String(next);
  }
}
