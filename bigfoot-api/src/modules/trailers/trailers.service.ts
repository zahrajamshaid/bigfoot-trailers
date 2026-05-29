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
import { UpdateSaleStatusDto, TrailerSaleStatusDto } from './dto/sale-status.dto';
import { Prisma, TrailerStatus, TrailerSaleStatus, DeliveryStatus } from '@prisma/client';

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

    // Atomic transaction: create trailer + generate all 12 workflow steps
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
          status: TrailerStatus.pending_production,
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

      const stepsSummary = await this.workflowGenerator.generateSteps(
        trailer.id,
        model.series,
        tx,
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

    // Trailer model — must exist (workflow steps are NOT regenerated on change)
    if (dto.trailerModelId !== undefined) {
      const model = await this.prisma.trailerModel.findUnique({
        where: { id: dto.trailerModelId },
        select: { id: true },
      });
      if (!model) {
        throw new AppError(
          ErrorCode.NOT_FOUND,
          `Trailer model with id ${dto.trailerModelId} not found`,
        );
      }
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

    return this.prisma.trailer.update({
      where: { id },
      data,
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
      select: { id: true, customerId: true, status: true },
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

    return this.prisma.trailer.update({
      where: { id },
      data,
      select: TRAILER_DETAIL_SELECT,
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
