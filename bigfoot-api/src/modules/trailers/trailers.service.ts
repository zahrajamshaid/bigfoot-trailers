import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  diffFields,
  humanAction,
  summarize,
  Lookups,
} from '../../common/audit/audit-humanizer';
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
import { PaintBoothCode } from './dto/paint-booth.dto';

// trailer.sizeFt is a free-form string ("24" / "26ft" / "20'"); pull the
// leading number and return it as feet. Mirrors the helper in the workflow
// generator so we can enforce the same PAINT_A 25ft cap on manual swaps.
function parsePaintLengthFt(sizeFt: string | null | undefined): number | null {
  if (!sizeFt) return null;
  const m = String(sizeFt).match(/(\d+(?:\.\d+)?)/);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) ? n : null;
}
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
  intendedStockLocationId: true,
  createdByUserId: true,
  color: true,
  sizeFt: true,
  optionsNotes: true,
  specialNote: true,
  qbSoPdfStorageUrl: true,
  qbSoPdfStorageKey: true,
  qbSoId: true,
  qbInvoicedAt: true,
  qbSoDate: true,
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
  intendedStockLocation: {
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
  // VIN is searchable, so the list has to be able to show what it matched.
  vinNumber: true,
  color: true,
  sizeFt: true,
  optionsNotes: true,
  specialNote: true,
  status: true,
  saleStatus: true,
  soldToName: true,
  globalPriority: true,
  isStockBuild: true,
  intendedStockLocationId: true,
  isHot: true,
  createdAt: true,
  trailerModel: {
    select: { id: true, code: true, displayName: true, series: true },
  },
  intendedStockLocation: {
    select: { id: true, code: true, name: true, shortLabel: true },
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
    const andClauses: Prisma.TrailerWhereInput[] = [];
    if (query.status) where.status = query.status as TrailerStatus;
    if (query.isHot !== undefined) where.isHot = query.isHot;
    if (query.customerId) where.customerId = BigInt(query.customerId);
    if (query.locationId) {
      // Stock builds now stay at the factory until delivered, so the trailer's
      // intended yard (e.g. JAX) doesn't match currentLocationId. The yard
      // chip should still pick them up — operators expect "JAX" to mean
      // "everything earmarked for JAX", not just "what's physically there".
      andClauses.push({
        OR: [
          { currentLocationId: query.locationId },
          { intendedStockLocationId: query.locationId },
        ],
      });
    }
    // Independent current vs. intended-stock filters. Unlike `locationId`
    // (which OR's across both relations), these AND together — picking
    // `currentLocationCode=MULBERRY` and `intendedStockLocationCode=
    // TAPPAHANNOCK` returns exactly the stock builds at Mulberry that
    // are bound for VA, which is what the new Mulberry-ready dashboard
    // tile drills into.
    if (query.currentLocationCode) {
      andClauses.push({
        currentLocation: { code: query.currentLocationCode },
      });
    }
    if (query.intendedStockLocationCode) {
      andClauses.push({
        intendedStockLocation: { code: query.intendedStockLocationCode },
      });
    }
    if (query.isStockBuild !== undefined) {
      where.isStockBuild = query.isStockBuild;
    }
    if (query.saleStatus) where.saleStatus = query.saleStatus as TrailerSaleStatus;

    // The dashboard tile's set, defined in exactly one place. Pushed as an AND
    // clause so it is authoritative — nothing the caller sends can widen or
    // narrow it, which is what let the tile and its list disagree before.
    if (query.readyForPickupAtMulberry) {
      andClauses.push(TrailersService.mulberryCustomerPickupWhere());
    }
    // Delivered trailers are history — they belong in Completed Deliveries,
    // not the active inventory list. Hide them by default so location /
    // status chips show only what's still in play. The caller can opt back
    // in by passing `status=delivered` explicitly. `completedSince` (the
    // dashboard "completed this week" tile) is also exempt — it's a
    // history view by design.
    if (query.status !== TrailerStatus.delivered && !query.completedSince) {
      andClauses.push({ status: { not: TrailerStatus.delivered } });
    }
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
        // VIN is searchable — that's the point of storing it in its own column.
        { vinNumber: { contains: term, mode: 'insensitive' } },
        { soldToName: { contains: term, mode: 'insensitive' } },
        { customer: { name: { contains: term, mode: 'insensitive' } } },
        { customer: { company: { contains: term, mode: 'insensitive' } } },
      ];
    }
    // A Mulberry stock-build with no customer attached is open inventory at
    // the factory — it shouldn't surface as "ready" for a customer pickup
    // until someone claims it. We only apply this exclusion when the caller
    // is filtering specifically for `ready_for_delivery`; queries that ask
    // for all trailers (e.g. the inventory screen) still see them.
    //
    // Since 2026-06-14 every stock build is built at Mulberry regardless of
    // destination, so a Mulberry currentLocation no longer means "destined
    // for Mulberry." We additionally require intent to be Mulberry (or
    // unset) before hiding — a stock build destined for TAL / JAX / VA IS
    // ready, transport just hasn't dispatched the stack_to_location yet.
    //
    // `includeOpenStock=true` opts out. Set by the delivery-creation form
    // so a sales user can book a delivery for a Mulberry stock trailer
    // that hasn't been sold yet — the exclusion was hiding those from the
    // picker (SO 6862 was the report), which made otherwise-eligible
    // trailers un-bookable without a data workaround.
    if (
      query.status === TrailerStatus.ready_for_delivery &&
      !query.includeOpenStock
    ) {
      where.NOT = {
        ...(where.NOT as Prisma.TrailerWhereInput | undefined),
        isStockBuild: true,
        customerId: null,
        soldToName: null,
        currentLocation: { code: 'MULBERRY' },
        OR: [
          { intendedStockLocationId: null },
          { intendedStockLocation: { code: 'MULBERRY' } },
        ],
      };
    }

    if (query.completedSince) {
      // Drilldown for the "Completed this week" dashboard tile. We match on
      // the Delivery row rather than trailer.updatedAt so a record edit
      // after delivery doesn't shift a trailer into the window.
      where.deliveries = {
        ...(where.deliveries as Prisma.DeliveryListRelationFilter | undefined),
        some: {
          status: DeliveryStatus.delivered,
          deliveredAt: { gte: new Date(query.completedSince) },
        },
      };
    }

    if (andClauses.length > 0) {
      where.AND = andClauses;
    }

    const [rawTrailers, total] = await this.prisma.$transaction([
      this.prisma.trailer.findMany({
        where,
        select: TRAILER_LIST_SELECT,
        orderBy: [{ isHot: 'desc' }, { globalPriority: 'asc' }, { createdAt: 'desc' }],
        skip,
        take: limit,
      }),
      this.prisma.trailer.count({ where }),
    ]);

    // Decorate each row with the same ownership classification the queue
    // payload carries — saleStatus='sold' is a customer trailer, anything
    // else is stock; buyerName falls back to soldToName when no customer
    // record is attached. Centralising this here keeps the mobile chip
    // dumb: it just trusts isCustomerOrder + buyerName.
    const trailers = rawTrailers.map((t) => ({
      ...t,
      isCustomerOrder: t.saleStatus === 'sold',
      buyerName: t.customer?.name ?? t.soldToName ?? null,
    }));

    return { trailers, total, page, limit };
  }

  // ---------------------------------------------------------------------------
  // GET /trailers/mulberry-ready-shipping
  // ---------------------------------------------------------------------------
  // Powers two dashboard tiles. Counts trailers physically at Mulberry that
  // are ready_for_delivery, split by what they're waiting on:
  //   - stockByYard:        stock builds with an intendedStockLocation (the
  //                         four satellite yards) — these are stack-to-yard
  //                         loads transport needs to plan.
  //   - customerPickupsAtMulberry: customer-order trailers (no
  //                         intendedStockLocation by definition) parked at
  //                         Mulberry waiting on a factory_pickup.
  //
  // Only the four satellite yards (JAX / TAPPAHANNOCK / TAL / ATL) appear
  // in stockByYard. Anything intended for Mulberry itself (or unset) falls
  // into the customer-pickup bucket.
  // ---------------------------------------------------------------------------
  /**
   * THE canonical definition of "customer pickup waiting at Mulberry".
   *
   * The dashboard tile's count and the list you get when you tap it MUST be
   * the same set. They used to be two hand-written filter sets — the tile
   * counted server-side while the client re-sent four separate query params
   * (status + location + isStockBuild + saleStatus) to rebuild the same query.
   * Any drift between them (an older app build, a typo'd param) silently
   * produced a tile that disagreed with its own list. Both now call this.
   *
   * saleStatus must be `sold`: a customer-order build that isn't formally sold
   * is in limbo, not a pickup.
   */
  static mulberryCustomerPickupWhere(): Prisma.TrailerWhereInput {
    return {
      status: TrailerStatus.ready_for_delivery,
      isStockBuild: false,
      saleStatus: TrailerSaleStatus.sold,
      currentLocation: { code: 'MULBERRY' },
    };
  }

  async getMulberryReadyShipping() {
    const YARD_CODES = ['JACKSONVILLE', 'TAPPAHANNOCK', 'TALLAHASSEE', 'ATLANTA'];

    const [stockGrouped, customerPickups] = await Promise.all([
      // Stock builds at Mulberry ready, grouped by intended yard.
      this.prisma.trailer.findMany({
        where: {
          status: TrailerStatus.ready_for_delivery,
          isStockBuild: true,
          currentLocation: { code: 'MULBERRY' },
          intendedStockLocation: { code: { in: YARD_CODES } },
        },
        select: { intendedStockLocation: { select: { code: true } } },
      }),
      // Customer-order pickups at Mulberry — counted through the SAME filter
      // the list uses, so the tile can never disagree with what it opens.
      this.prisma.trailer.count({
        where: TrailersService.mulberryCustomerPickupWhere(),
      }),
    ]);

    const byYard: Record<string, number> = Object.fromEntries(
      YARD_CODES.map((c) => [c, 0]),
    );
    for (const row of stockGrouped) {
      const code = row.intendedStockLocation?.code;
      if (code && code in byYard) byYard[code] += 1;
    }
    const totalStock = Object.values(byYard).reduce((a, b) => a + b, 0);

    return {
      stockByYard: byYard,
      totalStock,
      customerPickupsAtMulberry: customerPickups,
    };
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

    // VIN must be unique across trailers. Check up-front so the operator gets
    // a clear 409 instead of a raw Postgres unique-constraint 500.
    if (dto.vinNumber) {
      const vinClash = await this.prisma.trailer.findUnique({
        where: { vinNumber: dto.vinNumber },
        select: { soNumber: true },
      });
      if (vinClash) {
        throw new AppError(
          ErrorCode.VIN_EXISTS,
          `VIN ${dto.vinNumber} is already on trailer SO ${vinClash.soNumber}`,
        );
      }
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

    // Every trailer — customer or stock — is physically built at the factory.
    // Stock builds capture their destination yard in intendedStockLocationId
    // so the trailer surfaces in Mulberry inventory the moment FINAL_QC
    // passes; it only moves to the destination once a stack_to_location
    // delivery is dispatched + completed.
    const currentLocationId = factory.id;
    let intendedStockLocationId: number | null = null;
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
      intendedStockLocationId = stockLocation.id;
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
          intendedStockLocationId,
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
          // is, by definition, sold. Record the sale timestamp so the
          // Health Check → Sales counts read off soldAt instead of
          // createdAt/updatedAt (both of which drift for a variety of
          // reasons — see production-report.service.buildPeriodSnapshot).
          saleStatus:
            dto.customerId || dto.soldToName?.trim()
              ? TrailerSaleStatus.sold
              : TrailerSaleStatus.available,
          soldAt:
            dto.customerId || dto.soldToName?.trim() ? new Date() : null,
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
        // saleStatus is read alongside the other fields so the update can
        // detect a real sale-flip (available → sold or sold → available)
        // and sync `soldAt` accordingly. Without this the sales counts on
        // Health Check still drift on unrelated edits.
        saleStatus: true,
        trailerModel: { select: { series: true } },
      },
    });
    if (!existing) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${id} not found`);
    }

    // VIN — unique across trailers. An empty string clears it (back to null)
    // rather than storing '', which would collide on the second one. Resolved
    // here; written onto `data` once that's declared below.
    let nextVin: string | null | undefined;
    if (dto.vinNumber !== undefined) {
      const vin = dto.vinNumber.trim();
      if (vin === '') {
        nextVin = null;
      } else {
        const vinClash = await this.prisma.trailer.findUnique({
          where: { vinNumber: vin },
          select: { id: true, soNumber: true },
        });
        if (vinClash && vinClash.id !== id) {
          throw new AppError(
            ErrorCode.VIN_EXISTS,
            `VIN ${vin} is already on trailer SO ${vinClash.soNumber}`,
          );
        }
        nextVin = vin;
      }
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

    // Stock-build flag drives intendedStockLocationId (the destination yard
    // the trailer is built for). currentLocationId is *never* touched here —
    // the trailer stays at the factory until a stack_to_location delivery
    // physically moves it.
    const data: Prisma.TrailerUpdateInput = {};
    if (nextVin !== undefined) data.vinNumber = nextVin;
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
        data.intendedStockLocation = { connect: { id: stockLocation.id } };
      } else if (dto.isStockBuild === true && existing.isStockBuild === false) {
        // Toggled ON without a destination — caller must supply one.
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          'stockLocationId is required when enabling isStockBuild',
        );
      }
    } else if (dto.isStockBuild === false && existing.isStockBuild === true) {
      // Toggled OFF — drop the intended destination so it doesn't leak into
      // a future stack_to_location delivery default.
      data.intendedStockLocation = { disconnect: true };
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

    // Sync soldAt off the FINAL saleStatus, only when it's a real
    // transition. Skipping the "already sold, still sold" case matters —
    // otherwise a later address/status edit that also happened to touch
    // the sale-related paths would re-stamp soldAt and rewrite history.
    // Available → sold sets soldAt = now (the sale event).
    // Sold → available clears soldAt (the un-sale — safer than leaving
    // a stale timestamp on a trailer that's no longer sold, and lets a
    // subsequent re-sale get its own fresh timestamp).
    if (data.saleStatus !== undefined && data.saleStatus !== existing.saleStatus) {
      data.soldAt = data.saleStatus === TrailerSaleStatus.sold ? new Date() : null;
    }

    // Detect a real series change (workflow → workflow with a different
    // series). Same-series model swaps (e.g. XP_14ET → XP_17K) don't touch
    // production_steps. Transitions involving the inventory series have no
    // sensible automatic step mapping — those require a manual fix.
    // existing.trailerModel can be undefined under test mocks that don't
    // include the relation; treat that as "unknown old series" and skip
    // the reconcile rather than crashing.
    const oldSeries = existing.trailerModel?.series ?? null;
    const seriesChanged =
      newSeries !== null &&
      oldSeries !== null &&
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
  // PATCH /trailers/:id/paint-booth — owner / production_manager swap
  //
  // Moves the trailer's paint production_step between PAINT_A and PAINT_B.
  // Useful when the production manager needs to rebalance a tight queue,
  // or to override the size-based auto-routing for a specific build.
  //
  // Validation:
  //   - Trailer must have a paint step (anything inventory-only doesn't, and
  //     gn_dump builds are already on PAINT_B and can be swapped to A here).
  //   - Length cap is *only enforced when the target is PAINT_A*: PAINT_A
  //     physically can't fit ≥25ft trailers, so we reject that swap.
  //     Moving to PAINT_B is always allowed regardless of length.
  // ---------------------------------------------------------------------------
  async setPaintBooth(id: bigint, code: PaintBoothCode) {
    const trailer = await this.prisma.trailer.findUnique({
      where: { id },
      select: { id: true, soNumber: true, sizeFt: true },
    });
    if (!trailer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${id} not found`);
    }

    if (code === PaintBoothCode.PAINT_A) {
      const len = parsePaintLengthFt(trailer.sizeFt);
      if (len !== null && len >= 25) {
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          `PAINT_A only fits trailers under 25ft (this trailer is ${len}ft). Route to PAINT_B.`,
        );
      }
    }

    const targetBooth = await this.prisma.department.findUnique({
      where: { code },
      select: { id: true, code: true },
    });
    if (!targetBooth) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Paint booth department "${code}" missing — seed misconfiguration.`,
      );
    }

    const paintStep = await this.prisma.productionStep.findFirst({
      where: {
        trailerId: id,
        department: { code: { in: ['PAINT_A', 'PAINT_B'] } },
      },
      select: { id: true, departmentId: true },
    });
    if (!paintStep) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'Trailer has no paint production_step — model may be inventory-only.',
      );
    }

    if (paintStep.departmentId !== targetBooth.id) {
      await this.prisma.productionStep.update({
        where: { id: paintStep.id },
        data: { departmentId: targetBooth.id },
      });
    }

    return this.prisma.trailer.findUnique({
      where: { id },
      select: TRAILER_DETAIL_SELECT,
    });
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
        // saleStatus is read so we can decide whether this call is a real
        // sale-flip (transition) that should stamp soldAt, or a no-op
        // re-save that shouldn't rewrite it.
        saleStatus: true,
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

    const nextSaleStatus = dto.saleStatus as TrailerSaleStatus;
    const data: Prisma.TrailerUpdateInput = {
      saleStatus: nextSaleStatus,
      // A buyer name only belongs on a sold trailer — clear it otherwise.
      soldToName:
        dto.saleStatus === TrailerSaleStatusDto.SOLD ? (soldToName ?? null) : null,
    };
    // Stamp soldAt on real transitions only. Available → sold sets the
    // sale timestamp; sold → anything else clears it (a subsequent re-
    // sale gets a fresh stamp). Same-status no-op is left alone so the
    // original sale time isn't rewritten by a redundant save.
    if (nextSaleStatus !== existing.saleStatus) {
      data.soldAt = nextSaleStatus === TrailerSaleStatus.sold ? new Date() : null;
    }

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

    // NOTE: there used to be an "inverse" block here that flipped a
    // ready_for_delivery trailer to `delivered` whenever its sale status
    // moved off `sold`, on the theory that a reverted stock trailer should
    // go back to "parked delivered at the yard." That was wrong on two
    // counts:
    //   1. It fired on ANY non-sold transition, not just sold → not-sold.
    //      Marking an open-stock (available) trailer at a yard as
    //      `sale_pending` tripped it and silently sent the trailer to
    //      `delivered` — the SO 6588 bug the operator reported (a ready
    //      trailer marked sale_pending vanished from the yard).
    //   2. Even for a genuine sold → available revert, `delivered` is the
    //      wrong status. Per the yard-inventory rule, open stock sitting at
    //      a yard must be `ready_for_delivery` (that's what makes it show
    //      on the Stock Inventory tile + be movable between yards). A
    //      trailer whose sale was cancelled is open stock again, so it
    //      should STAY ready_for_delivery, not hide as delivered.
    // So the correct behaviour is simply: leave `status` alone on a sale-
    // status change. The delivery-completion flow is the only thing that
    // should ever set `status = delivered`.

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
      } else {
        // No live delivery — record the pickup as a fresh factory_pickup
        // row already in the delivered state. Without this, "Mark Picked Up"
        // silently flips trailer.status to delivered with no entry in the
        // deliveries history, so two-leg flows (stack_to_location to a yard,
        // then customer pickup at that yard) look like one event.
        await tx.delivery.create({
          data: {
            trailerId: id,
            deliveryType: DeliveryType.factory_pickup,
            status: DeliveryStatus.delivered,
            deliveredAt: now,
            createdByUserId: completedByUserId,
          },
        });
      }

      await tx.trailer.update({
        where: { id },
        data: { status: TrailerStatus.delivered },
      });

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

    // Plain English: every audit row gets a human verb, a one-line summary and
    // the full field-by-field diff, with ids resolved to names. Without this
    // the History tab is a wall of "Updated" that tells nobody anything.
    const lookups = await this.buildAuditLookups(auditLogs);
    const enrichedAuditLogs = auditLogs.map((row) => {
      const changes = diffFields(row.oldValues, row.newValues, lookups);
      return {
        ...row,
        actionLabel: humanAction(row.action),
        summary: summarize(row.action, 'trailer', row.oldValues, row.newValues, changes),
        changes,
        userName: row.user?.fullName ?? 'System',
      };
    });

    return { steps, qcInspections, deliveries, auditLogs: enrichedAuditLogs };
  }

  /**
   * Resolve the ids referenced by a batch of audit rows to names, in one pass
   * per table (no N+1), so the history can say "Mulberry" instead of "3".
   */
  private async buildAuditLookups(
    rows: { oldValues: unknown; newValues: unknown }[],
  ): Promise<Lookups> {
    const collect = (keys: string[]): Set<string> => {
      const out = new Set<string>();
      for (const r of rows) {
        for (const bag of [r.oldValues, r.newValues]) {
          const v = (bag ?? null) as Record<string, unknown> | null;
          if (!v) continue;
          for (const k of keys) {
            const val = v[k];
            if (val !== null && val !== undefined) out.add(String(val));
          }
        }
      }
      return out;
    };

    const locIds = [...collect([
      'currentLocationId',
      'intendedStockLocationId',
      'stockLocationId',
    ])].map(Number).filter((n) => Number.isFinite(n));
    const deptIds = [...collect(['departmentId'])].map(Number).filter((n) => Number.isFinite(n));
    const modelIds = [...collect(['trailerModelId'])].map(Number).filter((n) => Number.isFinite(n));
    const custIds = [...collect(['customerId'])].filter((s) => /^\d+$/.test(s));

    const [locs, depts, models, customers] = await Promise.all([
      locIds.length
        ? this.prisma.location.findMany({
            where: { id: { in: locIds } },
            select: { id: true, name: true, code: true },
          })
        : [],
      deptIds.length
        ? this.prisma.department.findMany({
            where: { id: { in: deptIds } },
            select: { id: true, code: true, displayName: true },
          })
        : [],
      modelIds.length
        ? this.prisma.trailerModel.findMany({
            where: { id: { in: modelIds } },
            select: { id: true, code: true },
          })
        : [],
      custIds.length
        ? this.prisma.customer.findMany({
            where: { id: { in: custIds.map((s) => BigInt(s)) } },
            select: { id: true, name: true, company: true },
          })
        : [],
    ]);

    return {
      locations: new Map(locs.map((l) => [l.id, l.name || l.code])),
      departments: new Map(depts.map((d) => [d.id, d.displayName || d.code])),
      models: new Map(models.map((m) => [m.id, m.code])),
      customers: new Map(
        customers.map((c) => [String(c.id), c.company || c.name]),
      ),
    };
  }
}
