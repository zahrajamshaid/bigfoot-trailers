import { Injectable } from '@nestjs/common';
import { Prisma, SalesOrderLineKind } from '@prisma/client';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import {
  SpecAttributes,
  mergeSpec,
  parseSpec,
  renderSpecDescription,
} from './spec-attributes';

/**
 * The configurator engine: given a model + selected options + fees, compose
 * the Sales Order lines exactly as they'll print (model line 1 with the
 * rendered spec description, then option lines, then fee lines) and compute an
 * in-app price PREVIEW.
 *
 * Important: the in-app subtotal is for DISPLAY ONLY. Tax + the authoritative
 * total come from QuickBooks once the order is pushed (Slice 3). We never
 * treat in-app tax as truth.
 */
export interface ComposeInput {
  modelId: number;
  optionIds: number[];
  /** Explicit fee ids; when omitted, auto-add fees are applied (quick mode). */
  feeIds?: number[];
  autoAddFees?: boolean;
}

export interface ComposedLine {
  kind: SalesOrderLineKind;
  refId: number | null;
  qboItemId: string | null;
  description: string;
  qty: number;
  rate: number;
  taxable: boolean;
  sortOrder: number;
}

export interface ComposedOrder {
  lines: ComposedLine[];
  /** In-app preview subtotal (sum of qty×rate). Tax comes from QBO later. */
  previewSubtotal: number;
}

@Injectable()
export class ConfiguratorService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Compose the full line set for a configuration. Pure-ish: reads catalog
   * rows, produces lines. Does not persist.
   */
  async compose(input: ComposeInput): Promise<ComposedOrder> {
    const model = await this.prisma.trailerModel.findUnique({
      where: { id: input.modelId },
    });
    if (!model) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer model ${input.modelId} not found`);
    }

    const options = input.optionIds.length
      ? await this.prisma.option.findMany({
          where: { id: { in: input.optionIds }, active: true },
        })
      : [];

    // Validate every requested option applies to this model (empty
    // applicableModelIds = applies to all).
    for (const opt of options) {
      if (
        opt.applicableModelIds.length > 0 &&
        !opt.applicableModelIds.includes(model.id)
      ) {
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          `Option "${opt.name}" is not available on model ${model.code}`,
        );
      }
    }

    // Base spec from the model, overlaid with each selected option's overrides.
    const baseSpec = parseSpec(model.spec) ?? { typeModel: model.code };
    let effectiveSpec: SpecAttributes = baseSpec;
    for (const opt of options) {
      effectiveSpec = mergeSpec(
        effectiveSpec,
        opt.specOverrides as Partial<SpecAttributes> | null,
      );
    }

    const lines: ComposedLine[] = [];
    let sort = 0;

    // Line 1 — the model, with the rendered spec description.
    lines.push({
      kind: SalesOrderLineKind.model,
      refId: model.id,
      qboItemId: model.qboItemId ?? null,
      description: renderSpecDescription(effectiveSpec),
      qty: 1,
      rate: model.basePrice ? Number(model.basePrice) : 0,
      taxable: true,
      sortOrder: sort++,
    });

    // Option lines.
    for (const opt of options) {
      lines.push({
        kind: SalesOrderLineKind.option,
        refId: opt.id,
        qboItemId: opt.qboItemId ?? null,
        description: opt.description ?? opt.name,
        qty: 1,
        rate: Number(opt.price),
        taxable: opt.taxable,
        sortOrder: sort++,
      });
    }

    // Fees — explicit list, or the auto-add set for the model + globals.
    const fees = await this.resolveFees(model.id, input);
    for (const fee of fees) {
      lines.push({
        kind: SalesOrderLineKind.fee,
        refId: fee.id,
        qboItemId: fee.qboItemId ?? null,
        description: fee.name,
        qty: 1,
        rate: Number(fee.amount),
        taxable: fee.taxable,
        sortOrder: sort++,
      });
    }

    const previewSubtotal = lines.reduce((sum, l) => sum + l.qty * l.rate, 0);
    return { lines, previewSubtotal: round2(previewSubtotal) };
  }

  private async resolveFees(modelId: number, input: ComposeInput) {
    if (input.feeIds && input.feeIds.length > 0) {
      return this.prisma.feeSchedule.findMany({
        where: { id: { in: input.feeIds }, active: true },
      });
    }
    if (input.autoAddFees) {
      return this.prisma.feeSchedule.findMany({
        where: {
          active: true,
          autoAdd: true,
          OR: [{ scope: 'global' }, { scope: 'model', modelId }],
        },
      });
    }
    return [];
  }

  /** Convert composed lines into Prisma create-input for persistence. */
  toLineCreateInput(
    salesOrderId: bigint,
    lines: ComposedLine[],
  ): Prisma.SalesOrderLineCreateManyInput[] {
    return lines.map((l) => ({
      salesOrderId,
      kind: l.kind,
      refId: l.refId,
      qboItemId: l.qboItemId,
      description: l.description,
      qty: new Prisma.Decimal(l.qty),
      rate: new Prisma.Decimal(l.rate),
      taxable: l.taxable,
      sortOrder: l.sortOrder,
    }));
  }
}

function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}
