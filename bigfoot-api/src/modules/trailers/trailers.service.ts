import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { WorkflowGeneratorService } from './workflow-generator.service';
import { AppError, ErrorCode } from '../../common/errors';
import { CreateTrailerDto } from './dto/create-trailer.dto';
import { UpdateTrailerDto } from './dto/update-trailer.dto';
import { QueryTrailersDto } from './dto/query-trailers.dto';
import { CreateAddonDto } from './dto/addon.dto';
import { SetPriorityDto } from './dto/priority.dto';
import { ToggleHotDto } from './dto/hot.dto';
import { UploadQbPdfDto } from './dto/qb-pdf.dto';
import {
  UpdateSaleStatusDto,
  TrailerSaleStatusDto,
  FulfilmentType,
} from './dto/sale-status.dto';
import {
  Prisma,
  TrailerStatus,
  TrailerSaleStatus,
  TrailerSeries,
  DeliveryStatus,
  DeliveryType,
  CustomerType,
} from '@prisma/client';

/** Select shape for trailer detail — includes model, customer, location, and current step info. */
const TRAILER_DETAIL_SELECT = {
  id: true,
  soNumber: true,
  vinNumber: true,
  trailerModelId: true,
  customerId: true,
  currentLocationId: true,
  createdByUserId: true,
  color: true,
  sizeFt: true,
  optionsNotes: true,
  specialNote: true,
  qbSoPdfStorageUrl: true,
  qbSoPdfStorageKey: true,
  qbSoId: true,
  qbInvoicedAt: true,
  status: true,
  saleStatus: true,
  soldToName: true,
  globalPriority: true,
  isStockBuild: true,
  isHot: true,
  customerLocked: true,
  createdAt: true,
  updatedAt: true,
  trailerModel: {
    select: { id: true, code: true, displayName: true, series: true, weightRating: true },
  },
  customer: {
    select: { id: true, name: true, company: true, smsPhone: true, customerType: true },
  },
  currentLocation: {
    select: { id: true, code: true, name: true },
  },
  addons: {
    select: { id: true, addonName: true, notes: true, addedAt: true },
    orderBy: { addedAt: 'asc' as const },
  },
} satisfies Prisma.TrailerSelect;

/** Lighter select for list views — but rich enough that the trailer card
 *  in the mobile list can show department / location / notes without a
 *  follow-up detail fetch. */
const TRAILER_LIST_SELECT = {
  id: true,
  soNumber: true,
  color: true,
  sizeFt: true,
  optionsNotes: true,
  specialNote: true,
  status: true,
  saleStatus: true,
  soldToName: true,
  globalPriority: true,
  isStockBuild: true,
  isHot: true,
  createdAt: true,
  trailerModel: {
    select: { id: true, code: true, displayName: true, series: true },
  },
  customer: {
    select: {
      id: true,
      name: true,
      company: true,
      customerType: true,
      smsPhone: true,
      email: true,
    },
  },
  currentLocation: {
    select: {
      id: true,
      code: true,
      name: true,
      city: true,
      state: true,
      shortLabel: true,
    },
  },
  // Only the active step — used to render the current department on the card.
  productionSteps: {
    where: { status: 'active' as const },
    select: {
      id: true,
      stepOrder: true,
      status: true,
      departmentId: true,
      department: { select: { id: true, code: true, displayName: true } },
    },
    take: 1,
  },
} satisfies Prisma.TrailerSelect;

@Injectable()
export class TrailersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly workflowGenerator: WorkflowGeneratorService,
    private readonly storage: StorageService,
  ) {}

  // ---------------------------------------------------------------------------
  // GET /trailers — list with pagination + filters
  // ---------------------------------------------------------------------------
  async findAll(query: QueryTrailersDto) {
    const page = query.page ?? 1;
    const limit = query.limit ?? 25;
    const skip = (page - 1) * limit;

    const where: Prisma.TrailerWhereInput = {};
    if (query.status) where.status = query.status as TrailerStatus;
    if (query.isHot !== undefined) where.isHot = query.isHot;
    if (query.customerId) where.customerId = BigInt(query.customerId);
    if (query.locationId) where.currentLocationId = query.locationId;
    if (query.saleStatus) where.saleStatus = query.saleStatus as TrailerSaleStatus;
    if (query.series) {
      where.trailerModel = { series: query.series };
    }
    // Hide trailers already committed to a delivery — used by the delivery /
    // batch creation forms so a trailer can't be double-booked.
    if (query.excludeOpenDeliveries) {
      where.deliveries = {
        none: {
          status: { in: [DeliveryStatus.scheduled, DeliveryStatus.in_transit] },
        },
      };
    }
    if (query.search) {
      // Match SO number OR customer name — both the linked customer record
      // (name / company) and the free-text buyer name on stock builds.
      const term = query.search;
      where.OR = [
        { soNumber: { contains: term, mode: 'insensitive' } },
        { soldToName: { contains: term, mode: 'insensitive' } },
        { customer: { name: { contains: term, mode: 'insensitive' } } },
        { customer: { company: { contains: term, mode: 'insensitive' } } },
      ];
    }

    const [trailers, total] = await this.prisma.$transaction([
      this.prisma.trailer.findMany({
        where,
        select: TRAILER_LIST_SELECT,
        orderBy: [{ isHot: 'desc' }, { globalPriority: 'asc' }, { createdAt: 'desc' }],
        skip,
        take: limit,
      }),
      this.prisma.trailer.count({ where }),
    ]);

    return { trailers, total, page, limit };
  }

  // ---------------------------------------------------------------------------
  // POST /trailers — create + generate workflow steps atomically
  // ---------------------------------------------------------------------------
  async create(dto: CreateTrailerDto, createdByUserId: bigint) {
    // Validate SO number uniqueness
    const existingSo = await this.prisma.trailer.findUnique({
      where: { soNumber: dto.soNumber },
      select: { id: true },
    });
    if (existingSo) {
      throw new AppError(
        ErrorCode.SO_NUMBER_EXISTS,
        `A trailer with SO number "${dto.soNumber}" already exists`,
      );
    }

    // Validate trailer model exists
    const model = await this.prisma.trailerModel.findUnique({
      where: { id: dto.trailerModelId },
      select: { id: true, series: true },
    });
    if (!model) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Trailer model with id ${dto.trailerModelId} not found`,
      );
    }

    // Validate customer exists if provided
    if (dto.customerId) {
      const customer = await this.prisma.customer.findUnique({
        where: { id: BigInt(dto.customerId) },
        select: { id: true },
      });
      if (!customer) {
        throw new AppError(
          ErrorCode.NOT_FOUND,
          `Customer with id ${dto.customerId} not found`,
        );
      }
    }

    // Find factory location (default for non-stock builds)
    const factory = await this.prisma.location.findFirst({
      where: { isFactory: true },
      select: { id: true },
    });
    if (!factory) {
      throw new AppError(ErrorCode.NOT_FOUND, 'No factory location found in the system');
    }

    let currentLocationId = factory.id;
    if (dto.isStockBuild) {
      if (!dto.stockLocationId) {
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          'stockLocationId is required when isStockBuild=true',
        );
      }
      const stockLocation = await this.prisma.location.findUnique({
        where: { id: dto.stockLocationId },
        select: { id: true, isActive: true },
      });
      if (!stockLocation || !stockLocation.isActive) {
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          `Stock location ${dto.stockLocationId} is invalid or inactive`,
        );
      }
      currentLocationId = stockLocation.id;
    }

    // Inventory-only models (Triple Crown, Enclosed, Misc) are tracked for
    // stock but not built on a line — no workflow_template, no production
    // steps, so the trailer is born already ready_for_delivery.
    const isInventoryOnly = model.series === 'inventory';

    // Atomic transaction: create trailer + generate all 12 workflow steps
    // (skipped for inventory-only models).
    const result = await this.prisma.$transaction(async (tx) => {
      const trailer = await tx.trailer.create({
        data: {
          soNumber: dto.soNumber,
          trailerModelId: dto.trailerModelId,
          customerId: dto.customerId ? BigInt(dto.customerId) : null,
          currentLocationId,
          createdByUserId,
          color: dto.color ?? null,
          sizeFt: dto.sizeFt ?? null,
          optionsNotes: dto.optionsNotes ?? null,
          specialNote: dto.specialNote ?? null,
          isStockBuild: dto.isStockBuild ?? false,
          qbSoId: dto.qbSoId ?? null,
          status: isInventoryOnly
            ? TrailerStatus.ready_for_delivery
            : TrailerStatus.pending_production,
          soldToName: dto.soldToName?.trim() || null,
          // A trailer created against a customer (record or free-text name)
          // is, by definition, sold.
          saleStatus:
            dto.customerId || dto.soldToName?.trim()
              ? TrailerSaleStatus.sold
              : TrailerSaleStatus.available,
        },
        select: TRAILER_DETAIL_SELECT,
      });

      const stepsSummary = isInventoryOnly
        ? {
            trailerId: trailer.id,
            series: model.series,
            totalSteps: 0,
            firstActiveStepId: null,
          }
        : await this.workflowGenerator.generateSteps(
            trailer.id,
            model.series,
            tx,
            dto.sizeFt,
          );

      return { trailer, stepsSummary };
    });

    return result;
  }

  // ---------------------------------------------------------------------------
  // GET /trailers/:id — full detail
  // ---------------------------------------------------------------------------
  async findOne(id: bigint) {
    const trailer = await this.prisma.trailer.findUnique({
      where: { id },
      select: {
        ...TRAILER_DETAIL_SELECT,
        productionSteps: {
          select: {
            id: true,
            departmentId: true,
            stepOrder: true,
            status: true,
            isRework: true,
            reworkCount: true,
            becameActiveAt: true,
            completedAt: true,
            department: {
              select: { id: true, code: true, displayName: true, isQcStep: true },
            },
          },
          orderBy: { stepOrder: 'asc' },
        },
      },
    });

    if (!trailer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${id} not found`);
    }

    return trailer;
  }

  // ---------------------------------------------------------------------------
  // PATCH /trailers/:id — update any of the create-trailer fields + status
  // ---------------------------------------------------------------------------
  async update(id: bigint, dto: UpdateTrailerDto) {
    const existing = await this.prisma.trailer.findUnique({
      where: { id },
      select: {
        id: true,
        soNumber: true,
        isStockBuild: true,
        currentLocationId: true,
        trailerModel: { select: { series: true } },
      },
    });
    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${id} not found`);
    }

    // SO number — must remain unique
    if (dto.soNumber !== undefined && dto.soNumber !== existing.soNumber) {
      const clash = await this.prisma.trailer.findUnique({
        where: { soNumber: dto.soNumber },
        select: { id: true },
      });
      if (clash && clash.id !== id) {
        throw new AppError(
          ErrorCode.SO_NUMBER_EXISTS,
          `A trailer with SO number "${dto.soNumber}" already exists`,
        );
      }
    }

    // Trailer model — must exist. When the series changes (e.g. swapping
    // an XP build to a Yeti), we re-route production_steps to match the
    // new series's workflow_template downstream — see the $transaction at
    // the bottom of this method.
    let newSeries: TrailerSeries | null = null;
    if (dto.trailerModelId !== undefined) {
      const model = await this.prisma.trailerModel.findUnique({
        where: { id: dto.trailerModelId },
        select: { id: true, series: true },
      });
      if (!model) {
        throw new AppError(
          ErrorCode.NOT_FOUND,
          `Trailer model with id ${dto.trailerModelId} not found`,
        );
      }
      newSeries = model.series;
    }

    // Customer — null clears, otherwise must exist
    if (dto.customerId !== undefined && dto.customerId !== null) {
      const customer = await this.prisma.customer.findUnique({
        where: { id: BigInt(dto.customerId) },
        select: { id: true },
      });
      if (!customer) {
        throw new AppError(
          ErrorCode.NOT_FOUND,
          `Customer with id ${dto.customerId} not found`,
        );
      }
    }

    // Stock-build flag drives currentLocationId. Recompute it only when the
    // flag is explicitly toggled OR a new stock destination is supplied.
    const data: Prisma.TrailerUpdateInput = {};
    const nextIsStockBuild = dto.isStockBuild ?? existing.isStockBuild;

    if (dto.isStockBuild !== undefined) {
      data.isStockBuild = dto.isStockBuild;
    }

    if (nextIsStockBuild) {
      if (dto.stockLocationId !== undefined) {
        const stockLocation = await this.prisma.location.findUnique({
          where: { id: dto.stockLocationId },
          select: { id: true, isActive: true },
        });
        if (!stockLocation || !stockLocation.isActive) {
          throw new AppError(
            ErrorCode.BAD_REQUEST,
            `Stock location ${dto.stockLocationId} is invalid or inactive`,
          );
        }
        data.currentLocation = { connect: { id: stockLocation.id } };
      } else if (dto.isStockBuild === true && existing.isStockBuild === false) {
        // Toggled ON without a destination — caller must supply one.
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          'stockLocationId is required when enabling isStockBuild',
        );
      }
    } else if (dto.isStockBuild === false && existing.isStockBuild === true) {
      // Toggled OFF — bring trailer back to the factory.
      const factory = await this.prisma.location.findFirst({
        where: { isFactory: true },
        select: { id: true },
      });
      if (!factory) {
        throw new AppError(
          ErrorCode.NOT_FOUND,
          'No factory location found in the system',
        );
      }
      data.currentLocation = { connect: { id: factory.id } };
    }

    if (dto.soNumber !== undefined) data.soNumber = dto.soNumber;
    if (dto.trailerModelId !== undefined) {
      data.trailerModel = { connect: { id: dto.trailerModelId } };
    }
    if (dto.customerId !== undefined) {
      if (dto.customerId === null) {
        data.customer = { disconnect: true };
      } else {
        data.customer = { connect: { id: BigInt(dto.customerId) } };
        // Attaching a customer makes the trailer sold (mirrors create()).
        data.saleStatus = TrailerSaleStatus.sold;
      }
    }

    // Free-text customer / buyer name. Non-empty marks the trailer sold;
    // an empty string clears the name and reverts it to available.
    if (dto.soldToName !== undefined) {
      const name = dto.soldToName.trim();
      data.soldToName = name || null;
      data.saleStatus = name ? TrailerSaleStatus.sold : TrailerSaleStatus.available;
    }
    if (dto.color !== undefined) data.color = dto.color;
    if (dto.sizeFt !== undefined) data.sizeFt = dto.sizeFt;
    if (dto.optionsNotes !== undefined) data.optionsNotes = dto.optionsNotes;
    if (dto.specialNote !== undefined) data.specialNote = dto.specialNote;
    if (dto.qbSoId !== undefined) data.qbSoId = dto.qbSoId;
    if (dto.status !== undefined) data.status = dto.status as TrailerStatus;

    // Detect a real series change (workflow → workflow with a different
    // series). Same-series model swaps (e.g. XP_14ET → XP_17K) don't touch
    // production_steps. Transitions involving the inventory series have no
    // sensible automatic step mapping — those require a manual fix.
    const oldSeries = existing.trailerModel.series;
    const seriesChanged =
      newSeries !== null &&
      newSeries !== oldSeries &&
      oldSeries !== TrailerSeries.inventory &&
      newSeries !== TrailerSeries.inventory;

    if (!seriesChanged) {
      return this.prisma.trailer.update({
        where: { id },
        data,
        select: TRAILER_DETAIL_SELECT,
      });
    }

    return this.prisma.$transaction(async (tx) => {
      const trailer = await tx.trailer.update({
        where: { id },
        data,
        select: TRAILER_DETAIL_SELECT,
      });
      // newSeries is non-null when seriesChanged is true (see the guard above).
      await this.reconcileStepsToSeries(tx, id, newSeries!);
      return trailer;
    });
  }

  // ---------------------------------------------------------------------------
  // Re-route an existing trailer's production_steps to match a new series'
  // workflow_template. Called after a mid-build model swap (XP → Yeti, etc.)
  // so the trailer moves into the correct department queues without losing
  // its step progress.
  //
  // For each existing step, we set department_id to the matching template
  // department by step_order. Paint booth (PAINT_A / PAINT_B) assignments
  // are preserved — we don't silently move a trailer between booths just
  // because the template defaults to one.
  // ---------------------------------------------------------------------------
  private async reconcileStepsToSeries(
    tx: Prisma.TransactionClient,
    trailerId: bigint,
    series: TrailerSeries,
  ): Promise<void> {
    const PAINT_CODES = new Set(['PAINT_A', 'PAINT_B']);
    const templates = await tx.workflowTemplate.findMany({
      where: { series },
      orderBy: { stepOrder: 'asc' },
      include: { department: { select: { id: true, code: true } } },
    });
    if (templates.length !== 12) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `Expected 12 workflow templates for series "${series}", found ${templates.length}`,
      );
    }
    const steps = await tx.productionStep.findMany({
      where: { trailerId },
      orderBy: { stepOrder: 'asc' },
      include: { department: { select: { id: true, code: true } } },
    });

    for (const s of steps) {
      const t = templates.find((x) => x.stepOrder === s.stepOrder);
      if (!t) continue;
      // Preserve paint A/B assignment: only the booth swap function should
      // ever move a step between paint booths.
      const oldIsPaint = PAINT_CODES.has(s.department.code);
      const newIsPaint = PAINT_CODES.has(t.department.code);
      if (oldIsPaint && newIsPaint) continue;
      if (s.department.id === t.department.id) continue;
      await tx.productionStep.update({
        where: { id: s.id },
        data: { departmentId: t.department.id },
      });
    }
  }

  // ---------------------------------------------------------------------------
  // PATCH /trailers/:id/priority — set global_priority
  // ---------------------------------------------------------------------------
  async setPriority(id: bigint, dto: SetPriorityDto) {
    const existing = await this.prisma.trailer.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${id} not found`);
    }

    return this.prisma.trailer.update({
      where: { id },
      data: { globalPriority: dto.globalPriority },
      select: TRAILER_DETAIL_SELECT,
    });
  }

  // ---------------------------------------------------------------------------
  // PATCH /trailers/:id/hot — toggle is_hot
  // ---------------------------------------------------------------------------
  async toggleHot(id: bigint, dto: ToggleHotDto) {
    const existing = await this.prisma.trailer.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${id} not found`);
    }

    return this.prisma.trailer.update({
      where: { id },
      data: { isHot: dto.isHot },
      select: TRAILER_DETAIL_SELECT,
    });
  }

  // ---------------------------------------------------------------------------
  // PATCH /trailers/:id/sale-status — set available / sale_pending / sold
  //
  // Marking a trailer sold requires a buyer name (free text) — unless the
  // trailer already has a customer record, in which case it is the buyer.
  // The name is stored as plain text; customer records are owned by the
  // GoHighLevel integration, not this table.
  // ---------------------------------------------------------------------------
  async updateSaleStatus(id: bigint, dto: UpdateSaleStatusDto) {
    const existing = await this.prisma.trailer.findUnique({
      where: { id },
      select: {
        id: true,
        customerId: true,
        status: true,
        createdByUserId: true,
        customer: {
          select: { id: true, customerType: true, deliveryAddress: true },
        },
      },
    });
    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${id} not found`);
    }

    const soldToName = dto.soldToName?.trim();

    if (
      dto.saleStatus === TrailerSaleStatusDto.SOLD &&
      !soldToName &&
      existing.customerId === null
    ) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'A buyer name is required to mark a trailer as sold',
      );
    }

    const data: Prisma.TrailerUpdateInput = {
      saleStatus: dto.saleStatus as TrailerSaleStatus,
      // A buyer name only belongs on a sold trailer — clear it otherwise.
      soldToName:
        dto.saleStatus === TrailerSaleStatusDto.SOLD ? (soldToName ?? null) : null,
    };

    // A stock trailer parked at one of our yards (production status
    // "delivered", last delivery landed at a Location) that is now sold needs
    // to be hauled to its buyer — flip it back to "ready_for_delivery" so a
    // delivery can be created for it.
    if (
      dto.saleStatus === TrailerSaleStatusDto.SOLD &&
      existing.status === TrailerStatus.delivered
    ) {
      const lastDelivered = await this.prisma.delivery.findFirst({
        where: { trailerId: id, status: DeliveryStatus.delivered },
        orderBy: { deliveredAt: 'desc' },
        select: { destinationLocationId: true },
      });
      if (lastDelivered?.destinationLocationId != null) {
        data.status = TrailerStatus.ready_for_delivery;
      }
    }

    // Inverse of the rule above: reverting a stock trailer out of "sold"
    // (back to available or sale_pending) should restore the "at the yard"
    // state. Without this the trailer stays in ready_for_delivery forever —
    // and Stock Inventory grouping looks correct (driven by the latest
    // delivered Delivery) but the trailer.status column reads wrong, which
    // shows up in any status-filtered list.
    //
    // Guard: only revert when there's no live delivery (scheduled /
    // in_transit / failed) more recent than the latest delivered one. If a
    // delivery is already in flight, "available" usually means the order was
    // cancelled and the trailer is being returned — we let the delivery
    // completion flow set the final status.
    if (
      dto.saleStatus !== TrailerSaleStatusDto.SOLD &&
      existing.status === TrailerStatus.ready_for_delivery
    ) {
      const lastDelivered = await this.prisma.delivery.findFirst({
        where: { trailerId: id, status: DeliveryStatus.delivered },
        orderBy: { deliveredAt: 'desc' },
        select: { id: true, deliveredAt: true, destinationLocationId: true },
      });
      if (lastDelivered?.destinationLocationId != null) {
        const newerLive = await this.prisma.delivery.findFirst({
          where: {
            trailerId: id,
            status: {
              in: [
                DeliveryStatus.scheduled,
                DeliveryStatus.in_transit,
                DeliveryStatus.failed,
              ],
            },
            createdAt: { gt: lastDelivered.deliveredAt ?? new Date(0) },
          },
          select: { id: true },
        });
        if (!newerLive) {
          data.status = TrailerStatus.delivered;
        }
      }
    }

    // Wrap the trailer update + (optional) auto-Delivery creation in one
    // transaction so we don't leave a trailer flagged sold without its
    // matching scheduled Delivery if creation fails.
    return this.prisma.$transaction(async (tx) => {
      const trailer = await tx.trailer.update({
        where: { id },
        data,
        select: TRAILER_DETAIL_SELECT,
      });

      // Only act on the sold transition when sales picked a fulfilment type.
      // If we just flipped from delivered → ready_for_delivery above, the
      // trailer is now legitimately a candidate for a scheduled Delivery.
      if (
        dto.saleStatus === TrailerSaleStatusDto.SOLD &&
        dto.fulfilmentType != null
      ) {
        // Don't double up: skip when a live (scheduled/in_transit) delivery
        // already exists. Re-runs / accidental double-clicks stay idempotent.
        const existingLive = await tx.delivery.findFirst({
          where: {
            trailerId: id,
            status: {
              in: [DeliveryStatus.scheduled, DeliveryStatus.in_transit],
            },
          },
          select: { id: true },
        });

        if (!existingLive) {
          if (dto.fulfilmentType === FulfilmentType.PICKUP) {
            await tx.delivery.create({
              data: {
                trailerId: id,
                deliveryType: DeliveryType.factory_pickup,
                status: DeliveryStatus.scheduled,
                pickedUpByName: soldToName ?? null,
                createdByUserId: existing.createdByUserId,
              },
            });
          } else {
            // DELIVERY: dealer → stack_to_dealer; everyone else → single_pull.
            const isDealer =
              existing.customer?.customerType === CustomerType.dealer;
            const address =
              dto.deliveryAddress?.trim() ||
              existing.customer?.deliveryAddress ||
              null;
            await tx.delivery.create({
              data: {
                trailerId: id,
                deliveryType: isDealer
                  ? DeliveryType.stack_to_dealer
                  : DeliveryType.single_pull,
                status: DeliveryStatus.scheduled,
                customerDeliveryAddress: address,
                createdByUserId: existing.createdByUserId,
              },
            });
          }
        }
      }

      return trailer;
    });
  }

  // ---------------------------------------------------------------------------
  // POST /trailers/:id/mark-completed — terminal completion (sales-facing)
  //
  // Drops the trailer out of every active query in one click. Completes the
  // open scheduled / in_transit Delivery (sets deliveredAt + delivered) and
  // flips trailer.status to delivered. No-op when the trailer is already
  // delivered, so the button is safe to mash.
  //
  // When more than one live Delivery exists (shouldn't happen, but defensive)
  // we complete the most recently created one.
  // ---------------------------------------------------------------------------
  async markCompleted(id: bigint, completedByUserId: bigint) {
    const trailer = await this.prisma.trailer.findUnique({
      where: { id },
      select: { id: true, status: true },
    });
    if (!trailer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${id} not found`);
    }

    if (trailer.status === TrailerStatus.delivered) {
      return this.prisma.trailer.findUnique({
        where: { id },
        select: TRAILER_DETAIL_SELECT,
      });
    }

    return this.prisma.$transaction(async (tx) => {
      const live = await tx.delivery.findFirst({
        where: {
          trailerId: id,
          status: {
            in: [DeliveryStatus.scheduled, DeliveryStatus.in_transit],
          },
        },
        orderBy: { createdAt: 'desc' },
        select: { id: true },
      });

      const now = new Date();
      if (live) {
        await tx.delivery.update({
          where: { id: live.id },
          data: {
            status: DeliveryStatus.delivered,
            deliveredAt: now,
          },
        });
      }

      await tx.trailer.update({
        where: { id },
        data: { status: TrailerStatus.delivered },
      });

      // Side note: future-us could record completedByUserId on a Delivery /
      // audit log column. Right now the field is unused — preserved in the
      // signature so the API contract is stable when we add the column.
      void completedByUserId;

      return tx.trailer.findUnique({
        where: { id },
        select: TRAILER_DETAIL_SELECT,
      });
    });
  }

  // ---------------------------------------------------------------------------
  // POST /trailers/:id/addons — add addon
  // ---------------------------------------------------------------------------
  async addAddon(trailerId: bigint, dto: CreateAddonDto) {
    const trailer = await this.prisma.trailer.findUnique({
      where: { id: trailerId },
      select: { id: true },
    });
    if (!trailer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${trailerId} not found`);
    }

    return this.prisma.trailerAddon.create({
      data: {
        trailerId,
        addonName: dto.addonName,
        notes: dto.notes ?? null,
      },
      select: { id: true, addonName: true, notes: true, addedAt: true },
    });
  }

  // ---------------------------------------------------------------------------
  // DELETE /trailers/:id/addons/:addon_id — remove addon
  // ---------------------------------------------------------------------------
  async removeAddon(trailerId: bigint, addonId: bigint) {
    const addon = await this.prisma.trailerAddon.findFirst({
      where: { id: addonId, trailerId },
      select: { id: true },
    });
    if (!addon) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Addon with id ${addonId} not found on trailer ${trailerId}`,
      );
    }

    await this.prisma.trailerAddon.delete({ where: { id: addonId } });
    return { deleted: true };
  }

  // ---------------------------------------------------------------------------
  // DELETE /trailers/:id — owner only
  //
  // Trailer has many child records, most of which DO NOT cascade in the
  // schema (see schema.prisma). We delete them manually inside a transaction
  // so a partial delete can never leave orphaned rows.
  // ---------------------------------------------------------------------------
  async deleteTrailer(trailerId: bigint) {
    const trailer = await this.prisma.trailer.findUnique({
      where: { id: trailerId },
      select: { id: true, soNumber: true, qbSoPdfStorageKey: true },
    });
    if (!trailer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${trailerId} not found`);
    }

    // Collect every Spaces key tied to this trailer BEFORE the transaction
    // wipes the rows. We delete from S3 only after the DB commit so a
    // transient Spaces failure can't roll back the user's delete.
    const [qcPhotos, deliveryPhotos] = await Promise.all([
      this.prisma.qcPhoto.findMany({
        where: { trailerId },
        select: { storageKey: true },
      }),
      this.prisma.deliveryPhoto.findMany({
        where: { delivery: { trailerId } },
        select: { storageKey: true },
      }),
    ]);
    const storageKeys = [
      ...(trailer.qbSoPdfStorageKey ? [trailer.qbSoPdfStorageKey] : []),
      ...qcPhotos.map((p) => p.storageKey),
      ...deliveryPhotos.map((p) => p.storageKey),
    ];

    await this.prisma.$transaction(async (tx) => {
      // Delete in dependency order — children first.
      await tx.stallAlert.deleteMany({ where: { trailerId } });
      await tx.pushNotification.deleteMany({ where: { trailerId } });
      await tx.smsLog.deleteMany({ where: { trailerId } });
      await tx.locationReceipt.deleteMany({ where: { trailerId } });
      // Deliveries have their own cascade-delete children (signatures, photos)
      // because Delivery FK on those tables uses onDelete: Cascade.
      await tx.delivery.deleteMany({ where: { trailerId } });
      await tx.workerMessage.deleteMany({ where: { trailerId } });
      await tx.qcPhoto.deleteMany({ where: { trailerId } });
      // QcInspection has cascading children (qc_inspection_items, qc_step_*)
      await tx.qcInspection.deleteMany({ where: { trailerId } });
      // StepReversal FK to ProductionStep historically had no cascade — so a
      // single reversed step was enough to 500 the entire delete. Schema is
      // fixed (onDelete: Cascade) but until that migration is everywhere we
      // wipe these explicitly first.
      await tx.stepReversal.deleteMany({
        where: { productionStep: { trailerId } },
      });
      // ProductionStep has cascading qc inspections too — by now those are gone
      await tx.productionStep.deleteMany({ where: { trailerId } });
      // Addons cascade automatically (FK onDelete: Cascade)
      await tx.trailer.delete({ where: { id: trailerId } });
    });

    // Best-effort Spaces cleanup; orphan-cleanup catches anything that fails.
    await this.storage.deleteObjects(storageKeys);

    return { deleted: true, soNumber: trailer.soNumber };
  }

  // ---------------------------------------------------------------------------
  // POST /trailers/:id/qb-pdf — attach QuickBooks SO PDF
  // ---------------------------------------------------------------------------
  async uploadQbPdf(trailerId: bigint, dto: UploadQbPdfDto) {
    const trailer = await this.prisma.trailer.findUnique({
      where: { id: trailerId },
      select: { id: true },
    });
    if (!trailer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${trailerId} not found`);
    }

    return this.prisma.trailer.update({
      where: { id: trailerId },
      data: {
        qbSoPdfStorageKey: dto.storageKey,
        qbSoPdfStorageUrl: dto.storageUrl,
      },
      select: TRAILER_DETAIL_SELECT,
    });
  }

  // ---------------------------------------------------------------------------
  // GET /trailers/:id/steps — all production steps
  // ---------------------------------------------------------------------------
  async getSteps(trailerId: bigint) {
    const trailer = await this.prisma.trailer.findUnique({
      where: { id: trailerId },
      select: { id: true },
    });
    if (!trailer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${trailerId} not found`);
    }

    return this.prisma.productionStep.findMany({
      where: { trailerId },
      select: {
        id: true,
        departmentId: true,
        stepOrder: true,
        status: true,
        queuePosition: true,
        isRework: true,
        reworkCount: true,
        pointsAwarded: true,
        becameActiveAt: true,
        completedAt: true,
        completedByUser: {
          select: { id: true, fullName: true },
        },
        department: {
          select: {
            id: true,
            code: true,
            displayName: true,
            isQcStep: true,
            completionType: true,
          },
        },
      },
      orderBy: { stepOrder: 'asc' },
    });
  }

  // ---------------------------------------------------------------------------
  // GET /trailers/:id/history — full audit + QC + step history
  // ---------------------------------------------------------------------------
  async getHistory(trailerId: bigint) {
    const trailer = await this.prisma.trailer.findUnique({
      where: { id: trailerId },
      select: { id: true },
    });
    if (!trailer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${trailerId} not found`);
    }

    const [steps, qcInspections, deliveries, auditLogs] = await this.prisma.$transaction([
      this.prisma.productionStep.findMany({
        where: { trailerId },
        select: {
          id: true,
          stepOrder: true,
          status: true,
          isRework: true,
          reworkCount: true,
          becameActiveAt: true,
          completedAt: true,
          department: { select: { code: true, displayName: true, isQcStep: true } },
          completedByUser: { select: { id: true, fullName: true } },
          stepReversals: {
            select: {
              id: true,
              reason: true,
              reversedAt: true,
              reversedByUser: { select: { id: true, fullName: true } },
            },
            orderBy: { reversedAt: 'desc' },
          },
        },
        orderBy: { stepOrder: 'asc' },
      }),
      this.prisma.qcInspection.findMany({
        where: { trailerId },
        select: {
          id: true,
          result: true,
          failNotes: true,
          attemptNumber: true,
          isFinalQc: true,
          inspectedAt: true,
          inspectorUser: { select: { id: true, fullName: true } },
          reworkTargetDept: { select: { id: true, code: true, displayName: true } },
          productionStep: {
            select: { stepOrder: true, department: { select: { code: true } } },
          },
          photos: {
            select: { id: true, storageUrl: true, storageKey: true, takenAt: true },
            orderBy: { takenAt: 'asc' },
          },
        },
        orderBy: { inspectedAt: 'asc' },
      }),
      this.prisma.delivery.findMany({
        where: { trailerId },
        select: {
          id: true,
          deliveryType: true,
          status: true,
          departedAt: true,
          deliveredAt: true,
          destinationLocation: { select: { code: true, name: true } },
          deliveryPhotos: {
            select: {
              id: true,
              storageUrl: true,
              storageKey: true,
              takenAt: true,
              photoType: true,
            },
            orderBy: { takenAt: 'asc' },
          },
        },
        orderBy: { createdAt: 'asc' },
      }),
      this.prisma.auditLog.findMany({
        where: { entityType: 'trailer', entityId: trailerId },
        select: {
          id: true,
          action: true,
          oldValues: true,
          newValues: true,
          createdAt: true,
          user: { select: { id: true, fullName: true } },
        },
        orderBy: { createdAt: 'desc' },
      }),
    ]);

    return { steps, qcInspections, deliveries, auditLogs };
  }
}
