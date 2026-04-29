import { Injectable } from '@nestjs/common';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import {
  Prisma,
  DeliveryStatus,
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
  FailDeliveryDto,
  UploadDeliveryPhotosDto,
} from './dto';
import { NotificationsService } from '../notifications/notifications.service';

// Shared select for delivery queries
const deliverySelect = {
  id: true,
  trailerId: true,
  deliveryBatchId: true,
  deliveryType: true,
  driverUserId: true,
  destinationLocationId: true,
  customerDeliveryAddress: true,
  balanceDue: true,
  paymentCollected: true,
  paymentMethod: true,
  status: true,
  tcAccepted: true,
  departedAt: true,
  deliveredAt: true,
  failReason: true,
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
  destinationLocation: { select: { id: true, name: true, city: true, state: true } },
  deliveryPhotos: {
    select: { id: true, storageUrl: true, storageKey: true, photoType: true, takenAt: true },
  },
} satisfies Prisma.DeliverySelect;

@Injectable()
export class DeliveriesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsService: NotificationsService,
  ) {}

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
      throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${dto.trailerId} not found`);
    }

    if (trailer.status !== TrailerStatus.ready_for_delivery) {
      throw new AppError(ErrorCode.DELIVERY_NOT_DISPATCHABLE, `Trailer status is "${trailer.status}" — must be "ready_for_delivery"`);
    }

    return this.prisma.delivery.create({
      data: {
        trailerId: BigInt(dto.trailerId),
        deliveryType: dto.deliveryType as DeliveryType,
        driverUserId: dto.driverUserId ? BigInt(dto.driverUserId) : null,
        destinationLocationId: dto.destinationLocationId ?? null,
        customerDeliveryAddress: dto.customerDeliveryAddress ?? null,
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
      throw new AppError(ErrorCode.DELIVERY_NOT_DISPATCHABLE, `Delivery status is "${delivery.status}" — must be "scheduled" to depart`);
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

    if (delivery.status !== DeliveryStatus.in_transit) {
      throw new AppError(ErrorCode.DELIVERY_NOT_DISPATCHABLE, `Delivery status is "${delivery.status}" — must be "in_transit" to complete`);
    }

    const balanceDue = Number(delivery.balanceDue ?? 0);
    const paymentCollected = dto.paymentCollected ?? 0;

    const result = await this.prisma.$transaction(async (tx) => {
      const data: Prisma.DeliveryUpdateInput = {
        status: DeliveryStatus.delivered,
        deliveredAt: new Date(),
      };

      if (dto.paymentCollected != null) data.paymentCollected = new Prisma.Decimal(dto.paymentCollected);
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

      // Update trailer status
      await tx.trailer.update({
        where: { id: delivery.trailerId },
        data: { status: TrailerStatus.delivered },
      });

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

      // If payment not collected and there's a balance due, notify transport_manager
      if (balanceDue > 0 && paymentCollected < balanceDue) {
        const transportManagers = await tx.user.findMany({
          where: { role: 'transport_manager', isActive: true },
          select: { id: true },
        });

        if (transportManagers.length > 0) {
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
      select: { id: true, status: true },
    });

    if (!delivery) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery with id ${id} not found`);
    }

    if (delivery.status === DeliveryStatus.delivered || delivery.status === DeliveryStatus.failed) {
      throw new AppError(ErrorCode.DELIVERY_NOT_DISPATCHABLE, `Delivery is already "${delivery.status}" — cannot mark as failed`);
    }

    return this.prisma.delivery.update({
      where: { id },
      data: {
        status: DeliveryStatus.failed,
        failReason: dto.failReason,
      },
      select: deliverySelect,
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
  async completeFactoryPickup(id: bigint) {
    const delivery = await this.prisma.delivery.findUnique({
      where: { id },
      select: { id: true, status: true, deliveryType: true, trailerId: true },
    });

    if (!delivery) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery with id ${id} not found`);
    }

    if (delivery.deliveryType !== DeliveryType.factory_pickup) {
      throw new AppError(ErrorCode.DELIVERY_NOT_DISPATCHABLE, `Delivery type is "${delivery.deliveryType}" — must be "factory_pickup"`);
    }

    if (delivery.status !== DeliveryStatus.scheduled) {
      throw new AppError(ErrorCode.DELIVERY_NOT_DISPATCHABLE, `Delivery status is "${delivery.status}" — must be "scheduled" to complete a factory pickup`);
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.delivery.update({
        where: { id },
        data: {
          status: DeliveryStatus.delivered,
          deliveredAt: new Date(),
        },
        select: deliverySelect,
      });

      await tx.trailer.update({
        where: { id: delivery.trailerId },
        data: { status: TrailerStatus.delivered },
      });

      return updated;
    });
  }
}
