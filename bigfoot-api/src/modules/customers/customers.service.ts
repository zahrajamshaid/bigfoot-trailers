import { Injectable, Logger } from '@nestjs/common';
import { CustomerType, Prisma, TrailerStatus } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { AppError, ErrorCode } from '../../common/errors';
import {
  FeatureFlag,
  FeatureFlagsService,
} from '../../common/config/feature-flags.service';
import { QboSyncService } from '../quickbooks/qbo-sync.service';
import { CreateCustomerDto, UpdateCustomerDto, QueryCustomersDto } from './dto';

const CUSTOMER_SELECT = {
  id: true,
  name: true,
  company: true,
  smsPhone: true,
  email: true,
  billingAddress: true,
  deliveryAddress: true,
  customerType: true,
  smsOptOut: true,
  qbCustomerId: true,
  taxExempt: true,
  resaleCertNo: true,
  qbSyncState: true,
  qbLastSyncedAt: true,
  qbSyncError: true,
  notes: true,
  stockLocationId: true,
  createdAt: true,
  updatedAt: true,
  stockLocation: {
    select: {
      id: true,
      code: true,
      name: true,
      city: true,
      state: true,
      shortLabel: true,
    },
  },
} satisfies Prisma.CustomerSelect;

@Injectable()
export class CustomersService {
  private readonly logger = new Logger('Customers');

  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly flags: FeatureFlagsService,
    private readonly qboSync: QboSyncService,
  ) {}

  /** Pull every QuickBooks customer into the app (upsert by qbCustomerId). */
  importFromQbo() {
    return this.qboSync.importCustomersFromQbo();
  }

  private stockCityFromCustomerName(name: string): string | null {
    const match = name.trim().match(/^(.*)\s+stock$/i);
    if (!match) return null;
    const city = match[1]?.trim().toLowerCase();
    return city && city.length > 0 ? city : null;
  }

  private async buildStockLocationCountMap(stockCities: Set<string>) {
    if (stockCities.size === 0) {
      return new Map<string, number>();
    }

    const locations = await this.prisma.location.findMany({
      select: { id: true, city: true },
    });

    const locationIdByCity = new Map<string, number>();
    for (const loc of locations) {
      const city = loc.city.trim().toLowerCase();
      if (stockCities.has(city) && !locationIdByCity.has(city)) {
        locationIdByCity.set(city, loc.id);
      }
    }

    const locationIds = [...locationIdByCity.values()];
    if (locationIds.length === 0) {
      return new Map<string, number>();
    }

    const grouped = await this.prisma.trailer.groupBy({
      by: ['currentLocationId'],
      where: {
        isStockBuild: true,
        status: { not: TrailerStatus.delivered },
        currentLocationId: { in: locationIds },
      },
      _count: { _all: true },
    });

    const countsByLocationId = new Map<number, number>();
    for (const row of grouped) {
      countsByLocationId.set(row.currentLocationId, row._count._all);
    }

    const countsByCity = new Map<string, number>();
    for (const [city, locationId] of locationIdByCity.entries()) {
      countsByCity.set(city, countsByLocationId.get(locationId) ?? 0);
    }

    return countsByCity;
  }

  private async addActiveTrailerCountsToCustomers(
    customers: Array<Prisma.CustomerGetPayload<{ select: typeof CUSTOMER_SELECT }>>,
  ) {
    if (customers.length === 0) return [];

    const customerIds = customers.map((c) => c.id);
    const directGrouped = await this.prisma.trailer.groupBy({
      by: ['customerId'],
      where: {
        customerId: { in: customerIds },
        status: { not: TrailerStatus.delivered },
      },
      _count: { _all: true },
    });

    const directCounts = new Map<string, number>();
    for (const row of directGrouped) {
      if (row.customerId != null) {
        directCounts.set(row.customerId.toString(), row._count._all);
      }
    }

    const stockCityByCustomerId = new Map<string, string>();
    const stockCities = new Set<string>();
    for (const c of customers) {
      if (c.customerType !== CustomerType.stock_location) continue;
      const city = this.stockCityFromCustomerName(c.name);
      if (!city) continue;
      stockCityByCustomerId.set(c.id.toString(), city);
      stockCities.add(city);
    }

    const stockCountsByCity = await this.buildStockLocationCountMap(stockCities);

    return customers.map((c) => {
      const idKey = c.id.toString();
      let activeTrailerCount = directCounts.get(idKey) ?? 0;

      const stockCity = stockCityByCustomerId.get(idKey);
      if (stockCity) {
        activeTrailerCount += stockCountsByCity.get(stockCity) ?? 0;
      }

      return {
        ...c,
        activeTrailerCount,
      };
    });
  }

  private async getActiveTrailerCountForCustomer(customer: {
    id: bigint;
    name: string;
    customerType: CustomerType;
  }) {
    const directCount = await this.prisma.trailer.count({
      where: {
        customerId: customer.id,
        status: { not: TrailerStatus.delivered },
      },
    });

    if (customer.customerType !== CustomerType.stock_location) {
      return directCount;
    }

    const stockCity = this.stockCityFromCustomerName(customer.name);
    if (!stockCity) {
      return directCount;
    }

    const stockCountsByCity = await this.buildStockLocationCountMap(new Set([stockCity]));
    return directCount + (stockCountsByCity.get(stockCity) ?? 0);
  }

  async findAll(query: QueryCustomersDto) {
    const page = query.page ?? 1;
    const limit = query.limit ?? 50;

    const where: Prisma.CustomerWhereInput = {};
    if (query.customerType) {
      // Caller asked for a specific type — honour it.
      where.customerType = query.customerType;
    } else if (query.excludeStockLocations) {
      // Trailer-create picker explicitly opts out of stock yards so they
      // can't be assigned as a trailer customer (stock destinations are
      // handled by the dedicated chip widget instead).
      where.customerType = { not: CustomerType.stock_location };
    }
    // Otherwise no type filter — the customers screen sees every type.
    if (query.search) {
      const s = query.search.trim();
      where.OR = [
        { name: { contains: s, mode: 'insensitive' } },
        { company: { contains: s, mode: 'insensitive' } },
        { email: { contains: s, mode: 'insensitive' } },
        { smsPhone: { contains: s } },
      ];
    }

    const [items, total] = await this.prisma.$transaction([
      this.prisma.customer.findMany({
        where,
        select: CUSTOMER_SELECT,
        orderBy: [{ name: 'asc' }],
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.customer.count({ where }),
    ]);

    const itemsWithCounts = await this.addActiveTrailerCountsToCustomers(items);

    return {
      items: itemsWithCounts,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  async findOne(id: bigint) {
    const customer = await this.prisma.customer.findUnique({
      where: { id },
      select: {
        ...CUSTOMER_SELECT,
        trailers: {
          select: {
            id: true,
            soNumber: true,
            vinNumber: true,
            status: true,
            createdAt: true,
            trailerModel: { select: { code: true, displayName: true } },
          },
          orderBy: { createdAt: 'desc' },
          take: 50,
        },
      },
    });
    if (!customer) {
      throw new AppError(ErrorCode.NOT_FOUND, `Customer ${id} not found`);
    }

    const activeTrailerCount = await this.getActiveTrailerCountForCustomer({
      id: customer.id,
      name: customer.name,
      customerType: customer.customerType,
    });

    // Trailer history — the customer's trailers (newest first). Maps to the
    // mobile CustomerTrailerHistoryItem contract (trailerId/soNumber/vin/status).
    const trailerHistory = customer.trailers.map((t) => ({
      trailerId: t.id,
      soNumber: t.soNumber,
      vinNumber: t.vinNumber,
      model: t.trailerModel?.displayName ?? t.trailerModel?.code ?? null,
      status: t.status,
      createdAt: t.createdAt,
    }));

    // Delivery history — every delivery for this customer's trailers.
    const deliveries = await this.prisma.delivery.findMany({
      where: { trailer: { customerId: id } },
      select: {
        id: true,
        trailerId: true,
        deliveryType: true,
        status: true,
        deliveredAt: true,
        scheduledDate: true,
      },
      orderBy: [{ deliveredAt: 'desc' }, { id: 'desc' }],
      take: 50,
    });
    const deliveryHistory = deliveries.map((d) => ({
      deliveryId: d.id,
      trailerId: d.trailerId,
      deliveryType: d.deliveryType,
      status: d.status,
      deliveredAt: d.deliveredAt,
    }));

    return {
      ...customer,
      activeTrailerCount,
      trailerHistory,
      deliveryHistory,
    };
  }

  async create(dto: CreateCustomerDto) {
    await this.validateStockLocation(dto.customerType, dto.stockLocationId);
    const customer = await this.prisma.customer.create({
      data: dto,
      select: CUSTOMER_SELECT,
    });
    // Sync to QuickBooks on create — "created through the app just like in
    // QBO". Non-blocking: a QBO failure leaves the local customer intact with
    // qbSyncState=error (surfaced in the UI + retryable), never fails create.
    if (this.flags.isEnabled(FeatureFlag.QBO_SYNC)) {
      try {
        await this.qboSync.ensureCustomer(customer.id);
      } catch (e) {
        this.logger.error(
          `QBO customer sync failed for ${customer.id}: ${e instanceof Error ? e.message : e}`,
        );
        await this.prisma.customer.update({
          where: { id: customer.id },
          data: {
            qbSyncState: 'error',
            qbSyncError: (e instanceof Error ? e.message : 'sync failed').slice(0, 500),
          },
        });
      }
      return this.findOne(customer.id); // re-fetch to include qbCustomerId + state
    }
    return customer;
  }

  async update(id: bigint, dto: UpdateCustomerDto) {
    await this.assertExists(id);
    if (dto.customerType !== undefined || dto.stockLocationId !== undefined) {
      // For partial updates we can't tell intent from the dto alone — fetch
      // the existing type so the validator sees the eventual state.
      const current = await this.prisma.customer.findUnique({
        where: { id },
        select: { customerType: true, stockLocationId: true },
      });
      const nextType = dto.customerType ?? current?.customerType;
      const nextLoc =
        dto.stockLocationId !== undefined
          ? dto.stockLocationId
          : (current?.stockLocationId ?? null);
      await this.validateStockLocation(nextType, nextLoc ?? undefined);
    }
    return this.prisma.customer.update({
      where: { id },
      data: dto,
      select: CUSTOMER_SELECT,
    });
  }

  /**
   * Stock-location customers must point at a real yard. End-user / dealer
   * customers must NOT carry a stock-location FK (the field would be
   * meaningless and confusing in queries).
   */
  private async validateStockLocation(
    customerType: CustomerType | undefined,
    stockLocationId: number | undefined,
  ) {
    if (customerType === CustomerType.stock_location) {
      if (!stockLocationId) {
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          'stockLocationId is required when customerType is "stock_location".',
        );
      }
      const loc = await this.prisma.location.findUnique({
        where: { id: stockLocationId },
        select: { id: true, isActive: true },
      });
      if (!loc || !loc.isActive) {
        throw new AppError(
          ErrorCode.BAD_REQUEST,
          `Location ${stockLocationId} is invalid or inactive.`,
        );
      }
    } else if (stockLocationId) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'stockLocationId is only valid for customerType="stock_location".',
      );
    }
  }

  async remove(id: bigint, opts?: { cascadeTrailers?: boolean }) {
    await this.assertExists(id);

    const trailers = await this.prisma.trailer.findMany({
      where: { customerId: id },
      select: { id: true },
    });

    if (trailers.length > 0 && !opts?.cascadeTrailers) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `Cannot delete customer ${id} — ${trailers.length} trailer(s) reference ` +
          `this customer. Pass cascadeTrailers=true to delete them too.`,
      );
    }

    const trailerIds = trailers.map((t) => t.id);

    // Collect every Spaces key tied to these trailers BEFORE the tx wipes
    // the rows. We delete from S3 only after the DB commit so a transient
    // Spaces failure can't roll back the customer delete; orphan-cleanup
    // catches anything that slips through.
    let storageKeys: string[] = [];
    if (trailerIds.length > 0) {
      const trailerWhere = { trailerId: { in: trailerIds } };
      const [pdfTrailers, qcPhotos, deliveryPhotos] = await Promise.all([
        this.prisma.trailer.findMany({
          where: { id: { in: trailerIds }, qbSoPdfStorageKey: { not: null } },
          select: { qbSoPdfStorageKey: true },
        }),
        this.prisma.qcPhoto.findMany({
          where: trailerWhere,
          select: { storageKey: true },
        }),
        this.prisma.deliveryPhoto.findMany({
          where: { delivery: { trailerId: { in: trailerIds } } },
          select: { storageKey: true },
        }),
      ]);
      storageKeys = [
        ...pdfTrailers
          .map((t) => t.qbSoPdfStorageKey)
          .filter((k): k is string => k != null),
        ...qcPhotos.map((p) => p.storageKey),
        ...deliveryPhotos.map((p) => p.storageKey),
      ];
    }

    await this.prisma.$transaction(async (tx) => {
      if (trailerIds.length > 0) {
        // Mirrors TrailersService.deleteTrailer cascade. Kept inline to
        // avoid a CustomersModule -> TrailersModule import cycle.
        const trailerWhere = { trailerId: { in: trailerIds } };
        await tx.stallAlert.deleteMany({ where: trailerWhere });
        await tx.pushNotification.deleteMany({ where: trailerWhere });
        await tx.smsLog.deleteMany({ where: trailerWhere });
        await tx.locationReceipt.deleteMany({ where: trailerWhere });
        await tx.delivery.deleteMany({ where: trailerWhere });
        await tx.workerMessage.deleteMany({ where: trailerWhere });
        await tx.qcPhoto.deleteMany({ where: trailerWhere });
        await tx.qcInspection.deleteMany({ where: trailerWhere });
        await tx.productionStep.deleteMany({ where: trailerWhere });
        await tx.trailer.deleteMany({ where: { id: { in: trailerIds } } });
      }
      await tx.customer.delete({ where: { id } });
    });

    // Best-effort Spaces cleanup after the DB commit.
    await this.storage.deleteObjects(storageKeys);

    return { success: true, deletedTrailerCount: trailerIds.length };
  }

  private async assertExists(id: bigint) {
    const exists = await this.prisma.customer.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!exists) {
      throw new AppError(ErrorCode.NOT_FOUND, `Customer ${id} not found`);
    }
  }
}
