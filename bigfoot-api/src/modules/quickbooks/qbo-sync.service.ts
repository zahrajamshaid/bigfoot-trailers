import { Injectable, Logger } from '@nestjs/common';
import { SalesOrderLine, SalesOrderLineKind, SalesOrderStatus } from '@prisma/client';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { QboApiClient } from './qbo-api.client';

/** What a catalog import did — surfaced to the caller so nothing is silent. */
export interface CatalogImportResult {
  total: number;
  modelsLinked: number;
  optionsCreated: number;
  optionsUpdated: number;
  feesCreated: number;
  feesUpdated: number;
  /** Items that look like a trailer model but have no model in the app yet. */
  unmatched: string[];
}

/** Shape of a QBO Estimate we read back for the import (subset). */
interface QboImportEstimate {
  Id: string;
  DocNumber?: string;
  TotalAmt?: number;
  TxnStatus?: string;
  TxnTaxDetail?: { TotalTax?: number };
  CustomerRef?: { value: string; name?: string };
  Line?: Array<{
    DetailType?: string;
    Description?: string;
    Amount?: number;
    SalesItemLineDetail?: {
      ItemRef?: { value?: string; name?: string };
      Qty?: number;
      UnitPrice?: number;
    };
  }>;
}

/**
 * Pushes app entities into QuickBooks: customers, catalog items (models /
 * options / fees), and Sales Orders → Estimates. Every "ensure*" method is
 * idempotent — it adopts an existing QBO record by lookup before creating,
 * and stores the returned qbo id back on the local row so subsequent pushes
 * reuse it (no duplicates).
 *
 * The estimate push is the payoff: it references the synced item ids, sends
 * the spec/option/fee lines, and reads QBO's computed tax + total back — we
 * never compute tax in-app.
 */
@Injectable()
export class QboSyncService {
  private readonly logger = new Logger('QboSync');
  private cachedIncomeAccountId: string | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly client: QboApiClient,
  ) {}

  /** QBO single-quote escaping for query string literals. */
  private esc(v: string): string {
    return v.replace(/'/g, "\\'");
  }

  private async incomeAccountRef(): Promise<string> {
    if (this.cachedIncomeAccountId) return this.cachedIncomeAccountId;
    const id = await this.client.firstIncomeAccountId();
    if (!id) {
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        'No Income account in QuickBooks to attach items to',
      );
    }
    this.cachedIncomeAccountId = id;
    return id;
  }

  /**
   * Ensure a QBO Item (Product/Service) exists for a name; return its id.
   * Adopts an existing item of the same name; otherwise creates a Service
   * item priced + taxed as given.
   */
  async ensureItem(
    name: string,
    unitPrice: number,
    taxable: boolean,
  ): Promise<string> {
    const trimmed = name.slice(0, 100);
    const found = await this.client.query<{ Id: string }>(
      'Item',
      `SELECT * FROM Item WHERE Name = '${this.esc(trimmed)}'`,
    );
    if (found[0]?.Id) return found[0].Id;

    const incomeRef = await this.incomeAccountRef();
    const item = await this.client.createItem({
      Name: trimmed,
      Type: 'Service',
      IncomeAccountRef: { value: incomeRef },
      UnitPrice: unitPrice,
      Taxable: taxable,
    });
    this.logger.log(`Created QBO item "${trimmed}" (${item.Id})`);
    return item.Id;
  }

  /**
   * Ensure the customer exists in QBO; return its id. If the local row has a
   * qbCustomerId, reuse it. Else adopt a same-DisplayName QBO customer, or
   * create one — persisting the id + sync state back locally.
   */
  async ensureCustomer(customerId: bigint): Promise<string> {
    const c = await this.prisma.customer.findUnique({ where: { id: customerId } });
    if (!c) throw new AppError(ErrorCode.NOT_FOUND, `Customer ${customerId} not found`);
    if (c.qbCustomerId) return c.qbCustomerId;

    const displayName = (c.company || c.name).slice(0, 100);
    const existing = await this.client.query<{ Id: string }>(
      'Customer',
      `SELECT * FROM Customer WHERE DisplayName = '${this.esc(displayName)}'`,
    );
    let qbId = existing[0]?.Id;
    if (!qbId) {
      const created = await this.client.createCustomer({
        DisplayName: displayName,
        CompanyName: c.company ?? undefined,
        PrimaryEmailAddr: c.email ? { Address: c.email } : undefined,
        PrimaryPhone: c.smsPhone ? { FreeFormNumber: c.smsPhone } : undefined,
      });
      qbId = created.Id;
      this.logger.log(`Created QBO customer "${displayName}" (${qbId})`);
    }
    await this.prisma.customer.update({
      where: { id: customerId },
      data: {
        qbCustomerId: qbId,
        qbSyncState: 'synced',
        qbLastSyncedAt: new Date(),
        qbSyncError: null,
      },
    });
    return qbId;
  }

  /**
   * Import customers FROM QuickBooks into the local app — so every QBO
   * customer is viewable/selectable in the app. Upserts by qbCustomerId
   * (idempotent; re-running refreshes, never duplicates).
   */
  async importCustomersFromQbo(): Promise<{
    total: number;
    created: number;
    updated: number;
  }> {
    const qboCustomers = await this.client.listCustomers();
    let created = 0;
    let updated = 0;
    for (const qc of qboCustomers) {
      const name = (qc.DisplayName || qc.CompanyName || 'Unknown').slice(0, 200);
      const billingAddress = qc.BillAddr
        ? [
            qc.BillAddr.Line1,
            qc.BillAddr.City,
            qc.BillAddr.CountrySubDivisionCode,
            qc.BillAddr.PostalCode,
          ]
            .filter(Boolean)
            .join(', ')
        : null;
      const data = {
        name,
        company: qc.CompanyName ?? null,
        email: qc.PrimaryEmailAddr?.Address ?? null,
        smsPhone: qc.PrimaryPhone?.FreeFormNumber ?? null,
        billingAddress,
        taxExempt: qc.Taxable === false,
        qbCustomerId: qc.Id,
        qbSyncState: 'synced' as const,
        qbLastSyncedAt: new Date(),
        qbSyncError: null,
      };
      const existing = await this.prisma.customer.findFirst({
        where: { qbCustomerId: qc.Id },
        select: { id: true },
      });
      if (existing) {
        await this.prisma.customer.update({ where: { id: existing.id }, data });
        updated++;
      } else {
        await this.prisma.customer.create({ data });
        created++;
      }
    }
    this.logger.log(
      `Imported ${qboCustomers.length} QBO customers (${created} new, ${updated} updated)`,
    );
    return { total: qboCustomers.length, created, updated };
  }

  /**
   * Import the CATALOG from QuickBooks — Slice 1. Pulls every active QBO
   * Product/Service and folds it into the app's catalog:
   *
   *   • matches an existing TrailerModel (by code, against the item's Name or
   *     SKU) → links qboItemId + pulls the price into basePrice. Models are
   *     never CREATED from QBO: a model needs a `series` (which drives the
   *     whole production workflow) and QBO has no such concept, so an
   *     unmatched model-looking item is reported, not guessed at.
   *   • looks like a fee (Tag & Title, Registration, Disposal, …) → FeeSchedule
   *   • anything else → Option
   *
   * Idempotent: keyed on qboItemId first, then name — re-running updates
   * prices in place and creates zero duplicates.
   */
  async importCatalogFromQbo(): Promise<CatalogImportResult> {
    const items = await this.client.listItems();
    const models = await this.prisma.trailerModel.findMany({
      select: { id: true, code: true, displayName: true },
    });
    // Normalise for matching: DO_10K / do-10k / "DO 10K" all collapse the same.
    const norm = (s: string) => s.toUpperCase().replace(/[^A-Z0-9]/g, '');
    const modelByCode = new Map(models.map((m) => [norm(m.code), m]));

    const result: CatalogImportResult = {
      total: items.length,
      modelsLinked: 0,
      optionsCreated: 0,
      optionsUpdated: 0,
      feesCreated: 0,
      feesUpdated: 0,
      unmatched: [],
    };

    for (const item of items) {
      const name = (item.Name ?? item.FullyQualifiedName ?? '').trim();
      if (!name) continue;
      const price = Number(item.UnitPrice ?? 0);
      const taxable = item.Taxable ?? true;

      // 1) Trailer model? Match the item name or SKU to a known model code.
      const model =
        modelByCode.get(norm(name)) ??
        (item.Sku ? modelByCode.get(norm(item.Sku)) : undefined);
      if (model) {
        await this.prisma.trailerModel.update({
          where: { id: model.id },
          data: { qboItemId: item.Id, basePrice: price },
        });
        result.modelsLinked++;
        continue;
      }

      // 2) Fee?
      if (QboSyncService.looksLikeFee(name)) {
        const existing = await this.prisma.feeSchedule.findFirst({
          where: { OR: [{ qboItemId: item.Id }, { name }] },
          select: { id: true },
        });
        if (existing) {
          await this.prisma.feeSchedule.update({
            where: { id: existing.id },
            data: { qboItemId: item.Id, name, amount: price, taxable, active: true },
          });
          result.feesUpdated++;
        } else {
          await this.prisma.feeSchedule.create({
            // autoAdd defaults false on import — Drew decides which fees are
            // standard; flipping a flag is safer than surprise charges.
            data: {
              qboItemId: item.Id,
              name,
              amount: price,
              taxable,
              autoAdd: false,
              scope: 'global',
            },
          });
          result.feesCreated++;
        }
        continue;
      }

      // 3) Otherwise it's an option.
      const existingOpt = await this.prisma.option.findFirst({
        where: { OR: [{ qboItemId: item.Id }, { name }] },
        select: { id: true },
      });
      if (existingOpt) {
        await this.prisma.option.update({
          where: { id: existingOpt.id },
          data: {
            qboItemId: item.Id,
            name,
            description: item.Description ?? undefined,
            price,
            taxable,
            active: true,
          },
        });
        result.optionsUpdated++;
      } else {
        await this.prisma.option.create({
          data: {
            qboItemId: item.Id,
            name: name.slice(0, 150),
            description: item.Description ?? null,
            price,
            taxable,
            // Empty = applies to every model. Drew narrows this per model in
            // the catalog UI; guessing applicability here would be wrong.
            applicableModelIds: [],
            defaultForModelIds: [],
            active: true,
          },
        });
        result.optionsCreated++;
      }
    }

    this.logger.log(
      `QBO catalog import: ${result.total} items → ${result.modelsLinked} models linked, ` +
        `options ${result.optionsCreated}+/${result.optionsUpdated}~, ` +
        `fees ${result.feesCreated}+/${result.feesUpdated}~`,
    );
    return result;
  }

  /** Fee-looking item names (paperwork lines, not build content). */
  private static looksLikeFee(name: string): boolean {
    return /\bfee\b|tag\s*(and|&)\s*title|registration|disposal|temp\s*tag/i.test(
      name,
    );
  }

  /** Find a local customer by its QBO id, creating a minimal one if absent. */
  private async ensureLocalCustomerByQboId(
    qboCustomerId: string | undefined,
    displayName: string | undefined,
  ): Promise<bigint> {
    const existing = qboCustomerId
      ? await this.prisma.customer.findFirst({
          where: { qbCustomerId: qboCustomerId },
          select: { id: true },
        })
      : null;
    if (existing) return existing.id;
    const created = await this.prisma.customer.create({
      data: {
        name: (displayName || 'QuickBooks customer').slice(0, 200),
        qbCustomerId: qboCustomerId ?? null,
        qbSyncState: 'synced',
        qbLastSyncedAt: new Date(),
      },
      select: { id: true },
    });
    return created.id;
  }

  /**
   * Import estimates FROM QuickBooks into the app — so an estimate created in
   * QBO shows up as a Sales Order in the app (two-way sync). Upserts by
   * qboEstimateId (idempotent): rows we pushed are refreshed, brand-new QBO
   * estimates are created. Lines are replaced from QBO each run. One bad
   * estimate never aborts the batch.
   */
  async importEstimatesFromQbo(
    createdByUserId: bigint,
  ): Promise<{ total: number; created: number; updated: number; failed: number }> {
    const estimates = await this.client.query<QboImportEstimate>(
      'Estimate',
      'SELECT * FROM Estimate MAXRESULTS 1000',
    );
    let created = 0;
    let updated = 0;
    let failed = 0;

    for (const est of estimates) {
      try {
        const customerId = await this.ensureLocalCustomerByQboId(
          est.CustomerRef?.value,
          est.CustomerRef?.name,
        );
        const lines = (est.Line ?? [])
          .filter(
            (l) => l.DetailType === 'SalesItemLineDetail' && l.SalesItemLineDetail,
          )
          .map((l, i) => ({
            kind: (i === 0 ? 'model' : 'option') as SalesOrderLineKind,
            refId: null,
            qboItemId: l.SalesItemLineDetail?.ItemRef?.value ?? null,
            itemName: l.SalesItemLineDetail?.ItemRef?.name ?? null,
            description:
              l.Description ?? l.SalesItemLineDetail?.ItemRef?.name ?? '',
            qty: l.SalesItemLineDetail?.Qty ?? 1,
            rate: l.SalesItemLineDetail?.UnitPrice ?? 0,
            taxable: true,
            sortOrder: i,
          }));
        const total = est.TotalAmt ?? 0;
        const tax = est.TxnTaxDetail?.TotalTax ?? 0;
        const base = {
          customerId,
          soNumber: est.DocNumber ?? null,
          qboEstimateId: est.Id,
          qboDocNumber: est.DocNumber ?? null,
          status: 'approved' as SalesOrderStatus,
          subtotal: total - tax,
          taxAmount: tax,
          total,
          syncState: 'synced' as const,
          syncError: null,
        };

        const existing = await this.prisma.salesOrder.findFirst({
          where: { qboEstimateId: est.Id },
          select: { id: true },
        });
        if (existing) {
          await this.prisma.$transaction([
            this.prisma.salesOrderLine.deleteMany({
              where: { salesOrderId: existing.id },
            }),
            this.prisma.salesOrder.update({
              where: { id: existing.id },
              data: base,
            }),
            this.prisma.salesOrderLine.createMany({
              data: lines.map((l) => ({ ...l, salesOrderId: existing.id })),
            }),
          ]);
          updated++;
        } else {
          const so = await this.prisma.salesOrder.create({
            data: { ...base, createdByUserId },
            select: { id: true },
          });
          if (lines.length) {
            await this.prisma.salesOrderLine.createMany({
              data: lines.map((l) => ({ ...l, salesOrderId: so.id })),
            });
          }
          created++;
        }
      } catch (e) {
        failed++;
        this.logger.warn(
          `Import of QBO estimate ${est.Id} failed: ${e instanceof Error ? e.message : e}`,
        );
      }
    }

    this.logger.log(
      `Imported ${estimates.length} QBO estimates (${created} new, ${updated} updated, ${failed} failed)`,
    );
    return { total: estimates.length, created, updated, failed };
  }

  /** The short QBO item Name for a line (model code / option / fee name). */
  private async itemNameForLine(line: SalesOrderLine): Promise<string> {
    if (line.kind === 'model' && line.refId != null) {
      const m = await this.prisma.trailerModel.findUnique({ where: { id: line.refId } });
      return m?.code ?? `model-${line.refId}`;
    }
    if (line.kind === 'option' && line.refId != null) {
      const o = await this.prisma.option.findUnique({ where: { id: line.refId } });
      return o?.name ?? `option-${line.refId}`;
    }
    if (line.kind === 'fee' && line.refId != null) {
      const f = await this.prisma.feeSchedule.findUnique({ where: { id: line.refId } });
      return f?.name ?? `fee-${line.refId}`;
    }
    return line.description.slice(0, 80);
  }

  /** Ensure the QBO item for a line + persist the id back onto the catalog row. */
  private async ensureItemForLine(line: SalesOrderLine): Promise<string> {
    if (line.qboItemId) return line.qboItemId;
    const name = await this.itemNameForLine(line);
    const itemId = await this.ensureItem(name, Number(line.rate), line.taxable);
    // Cache back onto the catalog so future estimates reuse it.
    if (line.kind === 'model' && line.refId != null) {
      await this.prisma.trailerModel.update({ where: { id: line.refId }, data: { qboItemId: itemId } });
    } else if (line.kind === 'option' && line.refId != null) {
      await this.prisma.option.update({ where: { id: line.refId }, data: { qboItemId: itemId } });
    } else if (line.kind === 'fee' && line.refId != null) {
      await this.prisma.feeSchedule.update({ where: { id: line.refId }, data: { qboItemId: itemId } });
    }
    await this.prisma.salesOrderLine.update({ where: { id: line.id }, data: { qboItemId: itemId } });
    return itemId;
  }

  /**
   * Push a Sales Order to QBO as an Estimate. Idempotent: if the SO already
   * has a qboEstimateId, we skip. On success, stores the estimate id +
   * DocNumber + QBO's computed subtotal/tax/total and flips syncState=synced.
   * On failure, flips syncState=error with the message (visible sync chip +
   * retry) and rethrows so the caller can decide whether to surface it.
   */
  async pushSalesOrderEstimate(salesOrderId: bigint): Promise<void> {
    const so = await this.prisma.salesOrder.findUnique({
      where: { id: salesOrderId },
      include: {
        lines: { orderBy: { sortOrder: 'asc' } },
        customer: { select: { email: true, taxExempt: true } },
      },
    });
    if (!so) throw new AppError(ErrorCode.NOT_FOUND, `Sales order ${salesOrderId} not found`);
    if (so.qboEstimateId) return; // already pushed — idempotent

    try {
      const customerRef = await this.ensureCustomer(so.customerId);
      const qboLines = [];
      for (const line of so.lines) {
        const itemId = await this.ensureItemForLine(line);
        // Tax: we never compute it. We tell QBO which lines are taxable and
        // let Automated Sales Tax work out the amount from the customer's
        // address. A tax-exempt customer forces every line to NON.
        const taxCode = so.customer.taxExempt
          ? 'NON'
          : line.taxable
            ? 'TAX'
            : 'NON';
        qboLines.push({
          DetailType: 'SalesItemLineDetail' as const,
          Amount: Number(line.qty) * Number(line.rate),
          Description: line.description,
          SalesItemLineDetail: {
            ItemRef: { value: itemId },
            Qty: Number(line.qty),
            UnitPrice: Number(line.rate),
            TaxCodeRef: { value: taxCode },
          },
        });
      }

      const estimate = await this.client.createEstimate({
        CustomerRef: { value: customerRef },
        // Carry the customer email onto the estimate so QBO's "Send" works
        // (its send pipeline NPEs on an estimate with no BillEmail).
        BillEmail: so.customer.email ? { Address: so.customer.email } : undefined,
        DocNumber: so.soNumber ?? undefined,
        PrivateNote: `bigfoot-so-${so.id}`, // idempotency marker
        Line: qboLines,
      });

      const total = estimate.TotalAmt ?? 0;
      const tax = estimate.TxnTaxDetail?.TotalTax ?? 0;
      await this.prisma.salesOrder.update({
        where: { id: salesOrderId },
        data: {
          qboEstimateId: estimate.Id,
          qboDocNumber: estimate.DocNumber,
          subtotal: total - tax,
          taxAmount: tax,
          total,
          syncState: 'synced',
          syncError: null,
        },
      });
      this.logger.log(
        `Pushed SO ${so.id} → QBO Estimate ${estimate.Id} (Doc ${estimate.DocNumber}, total ${total})`,
      );
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'QBO push failed';
      await this.prisma.salesOrder.update({
        where: { id: salesOrderId },
        data: { syncState: 'error', syncError: msg.slice(0, 500) },
      });
      throw e;
    }
  }
}
