import { Injectable } from '@nestjs/common';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import {
  Prisma,
  DeliveryStatus,
  DeliveryBatchStatus,
  DeliveryType,
  TrailerStatus,
  SmsType,
  SmsStatus,
  NotificationType,
  PhotoType,
  PaymentMethod,
} from '@prisma/client';
import {
  QueryDeliveriesDto,
  CreateDeliveryDto,
  CompleteDeliveryDto,
  CompleteFactoryPickupDto,
  FailDeliveryDto,
  UploadDeliveryPhotosDto,
} from './dto';
import { NotificationsService } from '../notifications/notifications.service';
import { StorageService } from '../storage/storage.service';

// Shared select for delivery queries
const deliverySelect = {
  id: true,
  trailerId: true,
  deliveryBatchId: true,
  deliveryType: true,
  driverUserId: true,
  destinationLocationId: true,
  customerDeliveryAddress: true,
  contactPhone: true,
  balanceDue: true,
  paymentCollected: true,
  paymentMethod: true,
  status: true,
  tcAccepted: true,
  departedAt: true,
  deliveredAt: true,
  failReason: true,
  pickedUpByName: true,
  createdAt: true,
  trailer: {
    select: {
      id: true,
      soNumber: true,
      trailerModel: { select: { id: true, displayName: true, series: true } },
      customer: { select: { id: true, name: true, smsPhone: true, smsOptOut: true } },
    },
  },
  driverUser: { select: { id: true, fullName: true } },
  destinationLocation: {
    select: { id: true, name: true, city: true, state: true, address: true },
  },
  deliveryPhotos: {
    select: {
      id: true,
      storageUrl: true,
      storageKey: true,
      photoType: true,
      takenAt: true,
    },
  },
} satisfies Prisma.DeliverySelect;

@Injectable()
export class DeliveriesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsService: NotificationsService,
    private readonly storage: StorageService,
  ) {}

  // ---------------------------------------------------------------------------
  // When a batched delivery reaches a terminal state, flip the parent batch to
  // "complete" once none of its deliveries are still open. Keeps the batch
  // status correct whether trailers are completed all-at-once or one-by-one.
  // ---------------------------------------------------------------------------
  private async reconcileBatchCompletion(tx: Prisma.TransactionClient, batchId: bigint) {
    const open = await tx.delivery.count({
      where: {
        deliveryBatchId: batchId,
        status: { in: [DeliveryStatus.scheduled, DeliveryStatus.in_transit] },
      },
    });
    if (open === 0) {
      await tx.deliveryBatch.updateMany({
        where: { id: batchId, status: { not: DeliveryBatchStatus.complete } },
        data: { status: DeliveryBatchStatus.complete, completedAt: new Date() },
      });
    }
  }

  // ---------------------------------------------------------------------------
  // GET /deliveries — list with filters
  // ---------------------------------------------------------------------------
  async findAll(query: QueryDeliveriesDto) {
    const where: Prisma.DeliveryWhereInput = {};

    if (query.status) where.status = query.status as DeliveryStatus;
    if (query.deliveryType) where.deliveryType = query.deliveryType as DeliveryType;
    if (query.driverUserId) where.driverUserId = BigInt(query.driverUserId);

    if (query.dateFrom || query.dateTo) {
      where.createdAt = {};
      if (query.dateFrom) where.createdAt.gte = new Date(query.dateFrom);
      if (query.dateTo) {
        const endDate = new Date(query.dateTo);
        endDate.setUTCDate(endDate.getUTCDate() + 1);
        where.createdAt.lt = endDate;
      }
    }

    return this.prisma.delivery.findMany({
      where,
      select: deliverySelect,
      orderBy: { createdAt: 'desc' },
    });
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries — create delivery
  // ---------------------------------------------------------------------------
  async create(dto: CreateDeliveryDto, createdByUserId: bigint) {
    // Validate trailer exists and is ready_for_delivery
    const trailer = await this.prisma.trailer.findUnique({
      where: { id: BigInt(dto.trailerId) },
      select: { id: true, status: true },
    });

    if (!trailer) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Trailer with id ${dto.trailerId} not found`,
      );
    }

    if (trailer.status !== TrailerStatus.ready_for_delivery) {
      throw new AppError(
        ErrorCode.DELIVERY_NOT_DISPATCHABLE,
        `Trailer status is "${trailer.status}" — must be "ready_for_delivery"`,
      );
    }

    const deliveryType = dto.deliveryType as DeliveryType;
    const trailerId = BigInt(dto.trailerId);

    // A factory pickup is recorded in one step — the customer collects the
    // trailer at the factory, so the delivery is created already delivered
    // and the trailer is moved to "delivered" in the same transaction.
    if (deliveryType === DeliveryType.factory_pickup) {
      return this.prisma.$transaction(async (tx) => {
        const delivery = await tx.delivery.create({
          data: {
            trailerId,
            deliveryType,
            balanceDue:
              dto.balanceDue != null ? new Prisma.Decimal(dto.balanceDue) : null,
            paymentCollected:
              dto.paymentCollected != null
                ? new Prisma.Decimal(dto.paymentCollected)
                : null,
            pickedUpByName: dto.pickedUpByName?.trim() || null,
            contactPhone: dto.contactPhone?.trim() || null,
            createdByUserId,
            status: DeliveryStatus.delivered,
            deliveredAt: new Date(),
          },
          select: deliverySelect,
        });

        await tx.trailer.update({
          where: { id: trailerId },
          data: { status: TrailerStatus.delivered },
        });

        return delivery;
      });
    }

    return this.prisma.delivery.create({
      data: {
        trailerId,
        deliveryType,
        driverUserId: dto.driverUserId ? BigInt(dto.driverUserId) : null,
        destinationLocationId: dto.destinationLocationId ?? null,
        customerDeliveryAddress: dto.customerDeliveryAddress ?? null,
        contactPhone: dto.contactPhone?.trim() || null,
        balanceDue: dto.balanceDue != null ? new Prisma.Decimal(dto.balanceDue) : null,
        deliveryBatchId: dto.deliveryBatchId ? BigInt(dto.deliveryBatchId) : null,
        createdByUserId,
        status: DeliveryStatus.scheduled,
      },
      select: deliverySelect,
    });
  }

  // ---------------------------------------------------------------------------
  // GET /deliveries/:id — single delivery detail
  // ---------------------------------------------------------------------------
  async findOne(id: bigint) {
    const delivery = await this.prisma.delivery.findUnique({
      where: { id },
      select: {
        ...deliverySelect,
        signatureUrl: true,
        gpsLat: true,
        gpsLng: true,
        tcAcceptedAt: true,
        createdByUser: { select: { id: true, fullName: true } },
        locationReceipts: {
          select: {
            id: true,
            notes: true,
            receivedAt: true,
            receivedByUser: { select: { id: true, fullName: true } },
            location: { select: { id: true, name: true } },
          },
        },
      },
    });

    if (!delivery) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery with id ${id} not found`);
    }

    return delivery;
  }

  // ---------------------------------------------------------------------------
  // PATCH /deliveries/:id/depart — driver marks en_route
  // ---------------------------------------------------------------------------
  async markDeparted(id: bigint) {
    const delivery = await this.prisma.delivery.findUnique({
      where: { id },
      select: {
        id: true,
        status: true,
        trailerId: true,
        trailer: {
          select: {
            id: true,
            soNumber: true,
            customer: { select: { smsPhone: true, smsOptOut: true } },
          },
        },
      },
    });

    if (!delivery) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery with id ${id} not found`);
    }

    if (delivery.status !== DeliveryStatus.scheduled) {
      throw new AppError(
        ErrorCode.DELIVERY_NOT_DISPATCHABLE,
        `Delivery status is "${delivery.status}" — must be "scheduled" to depart`,
      );
    }

    const result = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.delivery.update({
        where: { id },
        data: {
          status: DeliveryStatus.in_transit,
          departedAt: new Date(),
        },
        select: deliverySelect,
      });

      // Update trailer status
      await tx.trailer.update({
        where: { id: delivery.trailerId },
        data: { status: TrailerStatus.in_transit },
      });

      // Send driver_en_route SMS
      const customer = delivery.trailer.customer;
      if (customer?.smsPhone && !customer.smsOptOut) {
        await tx.smsLog.create({
          data: {
            trailerId: delivery.trailerId,
            deliveryId: id,
            recipientPhone: customer.smsPhone,
            smsType: SmsType.driver_en_route,
            messageBody: `Your trailer ${delivery.trailer.soNumber} is on its way! The driver has departed.`,
            status: SmsStatus.queued,
          },
        });
      }

      return updated;
    });

    // WebSocket: DELIVERY_DISPATCHED (after transaction committed)
    this.notificationsService.onDeliveryDispatched({
      deliveryId: result.id,
      trailerId: delivery.trailerId,
      soNumber: delivery.trailer.soNumber,
      driverUserId: result.driverUserId ?? null,
    });

    return result;
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/:id/complete — driver marks delivered
  // ---------------------------------------------------------------------------
  async markComplete(id: bigint, dto: CompleteDeliveryDto) {
    const delivery = await this.prisma.delivery.findUnique({
      where: { id },
      select: {
        id: true,
        status: true,
        trailerId: true,
        balanceDue: true,
        deliveryBatchId: true,
        destinationLocationId: true,
        trailer: {
          select: {
            id: true,
            soNumber: true,
            customer: { select: { smsPhone: true, smsOptOut: true } },
          },
        },
      },
    });

    if (!delivery) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery with id ${id} not found`);
    }

    // A single delivery is completed straight from "scheduled" (no depart step);
    // a batched delivery arrives here as "in_transit" after the batch dispatched.
    if (
      delivery.status !== DeliveryStatus.scheduled &&
      delivery.status !== DeliveryStatus.in_transit
    ) {
      throw new AppError(
        ErrorCode.DELIVERY_NOT_DISPATCHABLE,
        `Delivery status is "${delivery.status}" — must be "scheduled" or "in_transit" to complete`,
      );
    }

    const balanceDue = Number(delivery.balanceDue ?? 0);
    const paymentCollected = dto.paymentCollected ?? 0;

    const result = await this.prisma.$transaction(async (tx) => {
      const data: Prisma.DeliveryUpdateInput = {
        status: DeliveryStatus.delivered,
        deliveredAt: new Date(),
      };

      if (dto.paymentCollected != null)
        data.paymentCollected = new Prisma.Decimal(dto.paymentCollected);
      if (dto.paymentMethod) data.paymentMethod = dto.paymentMethod as PaymentMethod;
      if (dto.tcAccepted !== undefined) {
        data.tcAccepted = dto.tcAccepted;
        if (dto.tcAccepted) data.tcAcceptedAt = new Date();
      }
      if (dto.signatureUrl) data.signatureUrl = dto.signatureUrl;
      if (dto.gpsLat != null) data.gpsLat = new Prisma.Decimal(dto.gpsLat);
      if (dto.gpsLng != null) data.gpsLng = new Prisma.Decimal(dto.gpsLng);

      const updated = await tx.delivery.update({
        where: { id },
        data,
        select: deliverySelect,
      });

      // Create proof-of-delivery photos
      if (dto.photoStorageKeys?.length) {
        await tx.deliveryPhoto.createMany({
          data: dto.photoStorageKeys.map((key) => ({
            deliveryId: id,
            storageUrl: key,
            storageKey: key,
            photoType: PhotoType.proof_of_delivery,
          })),
        });
      }

      // Update trailer status. A delivery to a BF stock location leaves the
      // trailer as ready_for_delivery (it's now available stock at that yard);
      // a delivery to a customer / dealer address is terminal — delivered.
      if (delivery.destinationLocationId != null) {
        await tx.trailer.update({
          where: { id: delivery.trailerId },
          data: {
            status: TrailerStatus.ready_for_delivery,
            currentLocationId: delivery.destinationLocationId,
          },
        });
      } else {
        await tx.trailer.update({
          where: { id: delivery.trailerId },
          data: { status: TrailerStatus.delivered },
        });
      }

      // If this delivery is part of a batch, complete the batch once every
      // sibling delivery is also done.
      if (delivery.deliveryBatchId != null) {
        await this.reconcileBatchCompletion(tx, delivery.deliveryBatchId);
      }

      // Send delivery_complete SMS
      const customer = delivery.trailer.customer;
      if (customer?.smsPhone && !customer.smsOptOut) {
        await tx.smsLog.create({
          data: {
            trailerId: delivery.trailerId,
            deliveryId: id,
            recipientPhone: customer.smsPhone,
            smsType: SmsType.delivery_complete,
            messageBody: `Your trailer ${delivery.trailer.soNumber} has been delivered!`,
            status: SmsStatus.queued,
          },
        });
      }

      // Notify every active transport_manager that the delivery is complete.
      const transportManagers = await tx.user.findMany({
        where: { role: 'transport_manager', isActive: true },
        select: { id: true },
      });

      if (transportManagers.length > 0) {
        await tx.pushNotification.createMany({
          data: transportManagers.map((tm) => ({
            recipientUserId: tm.id,
            trailerId: delivery.trailerId,
            notificationType: NotificationType.delivery_complete,
            title: `Delivery Complete — ${delivery.trailer.soNumber}`,
            body: `Trailer ${delivery.trailer.soNumber} has been delivered.`,
          })),
        });

        // If a balance was outstanding and not fully collected, flag it too.
        if (balanceDue > 0 && paymentCollected < balanceDue) {
          await tx.pushNotification.createMany({
            data: transportManagers.map((tm) => ({
              recipientUserId: tm.id,
              trailerId: delivery.trailerId,
              notificationType: NotificationType.payment_not_collected,
              title: `Payment Not Collected — ${delivery.trailer.soNumber}`,
              body: `Balance due: $${balanceDue.toFixed(2)}, collected: $${paymentCollected.toFixed(2)}`,
            })),
          });
        }
      }

      return updated;
    });

    // WebSocket: DELIVERY_COMPLETE (after transaction committed)
    await this.notificationsService.onDeliveryComplete({
      deliveryId: result.id,
      trailerId: delivery.trailerId,
      soNumber: delivery.trailer.soNumber,
      balanceDue: balanceDue.toFixed(2),
      paymentCollected: paymentCollected.toFixed(2),
    });

    return result;
  }

  // ---------------------------------------------------------------------------
  // PATCH /deliveries/:id/fail — mark delivery failed
  // ---------------------------------------------------------------------------
  async markFailed(id: bigint, dto: FailDeliveryDto) {
    const delivery = await this.prisma.delivery.findUnique({
      where: { id },
      select: { id: true, status: true, trailerId: true, deliveryBatchId: true },
    });

    if (!delivery) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery with id ${id} not found`);
    }

    if (
      delivery.status === DeliveryStatus.delivered ||
      delivery.status === DeliveryStatus.failed
    ) {
      throw new AppError(
        ErrorCode.DELIVERY_NOT_DISPATCHABLE,
        `Delivery is already "${delivery.status}" — cannot mark as failed`,
      );
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.delivery.update({
        where: { id },
        data: {
          status: DeliveryStatus.failed,
          failReason: dto.failReason,
        },
        select: deliverySelect,
      });

      // The trailer never made it out — return it to the ready pool so it can
      // be put on another delivery.
      await tx.trailer.update({
        where: { id: delivery.trailerId },
        data: { status: TrailerStatus.ready_for_delivery },
      });

      // A failed trailer still counts as "resolved" for the batch — once no
      // deliveries are open the batch is complete.
      if (delivery.deliveryBatchId != null) {
        await this.reconcileBatchCompletion(tx, delivery.deliveryBatchId);
      }

      return updated;
    });
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/:id/photos — upload proof/damage photos
  // ---------------------------------------------------------------------------
  async uploadPhotos(id: bigint, dto: UploadDeliveryPhotosDto) {
    const delivery = await this.prisma.delivery.findUnique({
      where: { id },
      select: { id: true },
    });

    if (!delivery) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery with id ${id} not found`);
    }

    await this.prisma.deliveryPhoto.createMany({
      data: dto.storageKeys.map((key) => ({
        deliveryId: id,
        storageUrl: key,
        storageKey: key,
        photoType: dto.photoType as PhotoType,
      })),
    });

    return { deliveryId: id, photosAdded: dto.storageKeys.length };
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/factory-pickup/:id/complete — office completes pickup
  // ---------------------------------------------------------------------------
  async completeFactoryPickup(id: bigint, dto: CompleteFactoryPickupDto) {
    const delivery = await this.prisma.delivery.findUnique({
      where: { id },
      select: { id: true, status: true, deliveryType: true, trailerId: true },
    });

    if (!delivery) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery with id ${id} not found`);
    }

    if (delivery.deliveryType !== DeliveryType.factory_pickup) {
      throw new AppError(
        ErrorCode.DELIVERY_NOT_DISPATCHABLE,
        `Delivery type is "${delivery.deliveryType}" — must be "factory_pickup"`,
      );
    }

    if (delivery.status !== DeliveryStatus.scheduled) {
      throw new AppError(
        ErrorCode.DELIVERY_NOT_DISPATCHABLE,
        `Delivery status is "${delivery.status}" — must be "scheduled" to complete a factory pickup`,
      );
    }

    return this.prisma.$transaction(async (tx) => {
      const data: Prisma.DeliveryUpdateInput = {
        status: DeliveryStatus.delivered,
        deliveredAt: new Date(),
      };
      if (dto.pickedUpByName) data.pickedUpByName = dto.pickedUpByName;
      if (dto.paymentCollected != null) {
        data.paymentCollected = new Prisma.Decimal(dto.paymentCollected);
      }

      const updated = await tx.delivery.update({
        where: { id },
        data,
        select: deliverySelect,
      });

      await tx.trailer.update({
        where: { id: delivery.trailerId },
        data: { status: TrailerStatus.delivered },
      });

      return updated;
    });
  }

  // ---------------------------------------------------------------------------
  // DELETE /deliveries/:id — remove a delivery, free the trailer
  // ---------------------------------------------------------------------------
  async remove(id: bigint) {
    const delivery = await this.prisma.delivery.findUnique({
      where: { id },
      select: { id: true, trailerId: true },
    });

    if (!delivery) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery with id ${id} not found`);
    }

    // Snapshot delivery photo keys before the tx wipes the rows so we can
    // delete from Spaces immediately after the DB commit (best-effort —
    // orphan-cleanup catches anything that fails).
    const photos = await this.prisma.deliveryPhoto.findMany({
      where: { deliveryId: id },
      select: { storageKey: true },
    });
    const storageKeys = photos.map((p) => p.storageKey);

    await this.prisma.$transaction(async (tx) => {
      // Drop dependent rows first — photos cascade anyway, location receipts
      // do not, and SMS logs are history so they're kept but unlinked.
      await tx.deliveryPhoto.deleteMany({ where: { deliveryId: id } });
      await tx.locationReceipt.deleteMany({ where: { deliveryId: id } });
      await tx.smsLog.updateMany({
        where: { deliveryId: id },
        data: { deliveryId: null },
      });
      await tx.delivery.delete({ where: { id } });

      // Free the trailer: back to ready_for_delivery, parked wherever its most
      // recent *remaining* delivered delivery left it (i.e. where it was
      // before this delivery). If nothing else moved it, its location stands.
      const lastDelivered = await tx.delivery.findFirst({
        where: {
          trailerId: delivery.trailerId,
          status: DeliveryStatus.delivered,
          destinationLocationId: { not: null },
        },
        orderBy: { deliveredAt: 'desc' },
        select: { destinationLocationId: true },
      });

      await tx.trailer.update({
        where: { id: delivery.trailerId },
        data: {
          status: TrailerStatus.ready_for_delivery,
          ...(lastDelivered?.destinationLocationId != null
            ? { currentLocationId: lastDelivered.destinationLocationId }
            : {}),
        },
      });
    });

    // Best-effort Spaces cleanup after the DB commit.
    await this.storage.deleteObjects(storageKeys);

    return { deleted: true };
  }

  // ---------------------------------------------------------------------------
  // GET /deliveries/stock-inventory — trailers currently parked at each yard
  // ---------------------------------------------------------------------------
  // A trailer is "stock" at a location if its most recent *delivered* delivery
  // landed at that location. Once it is delivered out again (to a customer, or
  // a different yard) it drops off that yard's list automatically.
  async getStockInventory() {
    const latestPerTrailer = await this.prisma.delivery.findMany({
      where: { status: DeliveryStatus.delivered },
      distinct: ['trailerId'],
      orderBy: [{ trailerId: 'asc' }, { deliveredAt: 'desc' }],
      select: {
        id: true,
        deliveredAt: true,
        destinationLocation: {
          select: { id: true, code: true, name: true, city: true, state: true },
        },
        trailer: {
          select: {
            id: true,
            soNumber: true,
            trailerModel: { select: { displayName: true, series: true } },
          },
        },
        driverUser: { select: { id: true, fullName: true } },
        createdByUser: { select: { id: true, fullName: true } },
      },
    });

    // Group the at-a-yard trailers by their location.
    const byLocation = new Map<
      number,
      {
        location: { id: number; code: string; name: string; city: string; state: string };
        trailers: Array<{
          deliveryId: string;
          trailerId: string;
          soNumber: string;
          model: string | null;
          deliveredAt: Date | null;
          deliveredBy: string | null;
        }>;
      }
    >();

    for (const d of latestPerTrailer) {
      if (!d.destinationLocation) continue; // delivered to a customer address — not stock
      const loc = d.destinationLocation;
      let entry = byLocation.get(loc.id);
      if (!entry) {
        entry = { location: loc, trailers: [] };
        byLocation.set(loc.id, entry);
      }
      entry.trailers.push({
        deliveryId: d.id.toString(),
        trailerId: d.trailer.id.toString(),
        soNumber: d.trailer.soNumber,
        model: d.trailer.trailerModel?.displayName ?? null,
        deliveredAt: d.deliveredAt,
        deliveredBy: (d.driverUser ?? d.createdByUser)?.fullName ?? null,
      });
    }

    return Array.from(byLocation.values())
      .map((entry) => ({
        ...entry,
        // Newest arrivals first within each yard.
        trailers: entry.trailers.sort(
          (a, b) => (b.deliveredAt?.getTime() ?? 0) - (a.deliveredAt?.getTime() ?? 0),
        ),
        count: entry.trailers.length,
      }))
      .sort((a, b) => a.location.name.localeCompare(b.location.name));
  }
}
