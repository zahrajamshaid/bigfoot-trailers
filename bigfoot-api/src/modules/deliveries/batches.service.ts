import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  Prisma,
  DeliveryBatchStatus,
  DeliveryStatus,
  DeliveryType,
  TrailerStatus,
  BatchType,
  PhotoType,
  NotificationType,
} from '@prisma/client';
import { CreateBatchDto, UpdateBatchDto, CompleteBatchDto } from './dto';
import { NotificationsService } from '../notifications/notifications.service';
import { AppError, ErrorCode } from '../../common/errors';

const batchSelect = {
  id: true,
  batchNumber: true,
  batchType: true,
  status: true,
  driverUserId: true,
  destinationLocationId: true,
  destinationName: true,
  departedAt: true,
  completedAt: true,
  createdAt: true,
  driverUser: { select: { id: true, fullName: true } },
  destinationLocation: { select: { id: true, name: true, city: true, state: true } },
  createdByUser: { select: { id: true, fullName: true } },
  deliveries: {
    select: {
      id: true,
      trailerId: true,
      status: true,
      trailer: {
        select: {
          id: true,
          soNumber: true,
          trailerModel: { select: { id: true, displayName: true, series: true } },
        },
      },
    },
  },
} satisfies Prisma.DeliveryBatchSelect;

@Injectable()
export class BatchesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsService: NotificationsService,
  ) {}

  // ---------------------------------------------------------------------------
  // GET /deliveries/batches — list batches
  // ---------------------------------------------------------------------------
  async findAll() {
    return this.prisma.deliveryBatch.findMany({
      select: batchSelect,
      orderBy: { createdAt: 'desc' },
    });
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/batches — create a new batch (optionally with trailers)
  // ---------------------------------------------------------------------------
  async create(dto: CreateBatchDto, createdByUserId: bigint) {
    const batchType = dto.batchType as BatchType;

    return this.prisma.$transaction(async (tx) => {
      const batch = await tx.deliveryBatch.create({
        data: {
          batchNumber: dto.batchNumber,
          batchType,
          driverUserId: dto.driverUserId ? BigInt(dto.driverUserId) : null,
          destinationLocationId: dto.destinationLocationId ?? null,
          destinationName: dto.destinationName ?? null,
          createdByUserId,
          status: DeliveryBatchStatus.building,
        },
        select: { id: true },
      });

      // Trailers picked in the create dialog are all added in this same
      // transaction — the batch is never left half-built.
      if (dto.trailerIds?.length) {
        await this.addTrailersTx(
          tx,
          batch.id,
          batchType,
          dto.trailerIds,
          createdByUserId,
          dto.destinationLocationId ?? null,
        );
      }

      return tx.deliveryBatch.findUniqueOrThrow({
        where: { id: batch.id },
        select: batchSelect,
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Shared helper — validate trailers are ready_for_delivery and create one
  // scheduled delivery per trailer, all attached to the batch.
  // ---------------------------------------------------------------------------
  private async addTrailersTx(
    tx: Prisma.TransactionClient,
    batchId: bigint,
    batchType: BatchType,
    trailerIds: number[],
    createdByUserId: bigint,
    destinationLocationId: number | null,
  ) {
    const trailerIdBigints = trailerIds.map((t) => BigInt(t));
    const trailers = await tx.trailer.findMany({
      where: { id: { in: trailerIdBigints } },
      select: { id: true, status: true },
    });

    const found = new Map(trailers.map((t) => [t.id.toString(), t.status]));
    for (const trailerId of trailerIds) {
      const status = found.get(BigInt(trailerId).toString());
      if (status === undefined) {
        throw new AppError(ErrorCode.NOT_FOUND, `Trailer with id ${trailerId} not found`);
      }
      if (status !== TrailerStatus.ready_for_delivery) {
        throw new AppError(
          ErrorCode.DELIVERY_NOT_DISPATCHABLE,
          `Trailer ${trailerId} status is "${status}" — must be "ready_for_delivery"`,
        );
      }
    }

    const deliveryType =
      batchType === BatchType.dealer
        ? DeliveryType.stack_to_dealer
        : DeliveryType.stack_to_location;

    await tx.delivery.createMany({
      data: trailerIdBigints.map((trailerId) => ({
        trailerId,
        deliveryBatchId: batchId,
        deliveryType,
        destinationLocationId,
        status: DeliveryStatus.scheduled,
        createdByUserId,
      })),
    });
  }

  // ---------------------------------------------------------------------------
  // PATCH /deliveries/batches/:id — update batch (add/remove trailers)
  // ---------------------------------------------------------------------------
  async update(id: bigint, dto: UpdateBatchDto, createdByUserId: bigint) {
    const batch = await this.prisma.deliveryBatch.findUnique({
      where: { id },
      select: {
        id: true,
        status: true,
        batchType: true,
        destinationLocationId: true,
      },
    });

    if (!batch) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery batch with id ${id} not found`);
    }

    if (batch.status !== DeliveryBatchStatus.building) {
      throw new AppError(
        ErrorCode.BATCH_NOT_BUILDING,
        `Cannot modify batch — status is "${batch.status}", must be "building"`,
      );
    }

    return this.prisma.$transaction(async (tx) => {
      // Update batch metadata
      const data: Prisma.DeliveryBatchUpdateInput = {};
      if (dto.driverUserId !== undefined)
        data.driverUser = dto.driverUserId
          ? { connect: { id: BigInt(dto.driverUserId) } }
          : { disconnect: true };
      if (dto.destinationLocationId !== undefined)
        data.destinationLocation = dto.destinationLocationId
          ? { connect: { id: dto.destinationLocationId } }
          : { disconnect: true };
      if (dto.destinationName !== undefined) data.destinationName = dto.destinationName;

      if (Object.keys(data).length > 0) {
        await tx.deliveryBatch.update({ where: { id }, data });
      }

      // The destination the batch's deliveries should carry — the new value
      // if it's being changed in this request, otherwise the existing one.
      const effectiveDestination =
        dto.destinationLocationId !== undefined
          ? (dto.destinationLocationId ?? null)
          : batch.destinationLocationId;

      // If the destination changed, keep the existing scheduled deliveries
      // in sync so trailer routing on completion stays correct.
      if (dto.destinationLocationId !== undefined) {
        await tx.delivery.updateMany({
          where: { deliveryBatchId: id, status: DeliveryStatus.scheduled },
          data: { destinationLocationId: effectiveDestination },
        });
      }

      // Add trailers — same validation + insert path as batch creation.
      if (dto.addTrailerIds?.length) {
        await this.addTrailersTx(
          tx,
          id,
          batch.batchType,
          dto.addTrailerIds,
          createdByUserId,
          effectiveDestination,
        );
      }

      // Remove deliveries from batch
      if (dto.removeDeliveryIds?.length) {
        await tx.delivery.deleteMany({
          where: {
            id: { in: dto.removeDeliveryIds.map((did) => BigInt(did)) },
            deliveryBatchId: id,
            status: DeliveryStatus.scheduled,
          },
        });
      }

      return tx.deliveryBatch.findUniqueOrThrow({
        where: { id },
        select: batchSelect,
      });
    });
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/batches/:id/depart — dispatch batch
  // ---------------------------------------------------------------------------
  async dispatch(id: bigint) {
    const batch = await this.prisma.deliveryBatch.findUnique({
      where: { id },
      select: {
        id: true,
        status: true,
        deliveries: { select: { id: true, trailerId: true } },
      },
    });

    if (!batch) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery batch with id ${id} not found`);
    }

    if (
      batch.status !== DeliveryBatchStatus.building &&
      batch.status !== DeliveryBatchStatus.scheduled
    ) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `Batch status is "${batch.status}" — must be "building" or "scheduled" to dispatch`,
      );
    }

    if (batch.deliveries.length === 0) {
      throw new AppError(ErrorCode.BAD_REQUEST, 'Cannot dispatch an empty batch');
    }

    const result = await this.prisma.$transaction(async (tx) => {
      await tx.deliveryBatch.update({
        where: { id },
        data: {
          status: DeliveryBatchStatus.in_transit,
          departedAt: new Date(),
        },
      });

      // Mark all deliveries in the batch as in_transit
      await tx.delivery.updateMany({
        where: { deliveryBatchId: id, status: DeliveryStatus.scheduled },
        data: {
          status: DeliveryStatus.in_transit,
          departedAt: new Date(),
        },
      });

      // Mark all trailers as in_transit
      const trailerIds = batch.deliveries.map((d) => d.trailerId);
      if (trailerIds.length > 0) {
        await tx.trailer.updateMany({
          where: { id: { in: trailerIds } },
          data: { status: TrailerStatus.in_transit },
        });
      }

      return tx.deliveryBatch.findUniqueOrThrow({
        where: { id },
        select: batchSelect,
      });
    });

    // WebSocket: DELIVERY_DISPATCHED for each delivery in the batch
    for (const delivery of batch.deliveries) {
      this.notificationsService.onDeliveryDispatched({
        deliveryId: delivery.id,
        trailerId: delivery.trailerId,
        soNumber: `batch-${id}`,
        driverUserId: null,
      });
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // POST /deliveries/batches/:id/complete — mark the whole batch delivered
  // ---------------------------------------------------------------------------
  // One action completes every trailer in the batch: the batch goes to
  // "complete", each in-transit delivery to "delivered", and each trailer to
  // "delivered". Optional proof photos are attached to every delivery.
  async complete(id: bigint, dto: CompleteBatchDto) {
    const batch = await this.prisma.deliveryBatch.findUnique({
      where: { id },
      select: {
        id: true,
        batchNumber: true,
        status: true,
        destinationLocationId: true,
        deliveries: {
          select: {
            id: true,
            trailerId: true,
            status: true,
            trailer: { select: { soNumber: true } },
          },
        },
      },
    });

    if (!batch) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery batch with id ${id} not found`);
    }

    if (batch.status === DeliveryBatchStatus.complete) {
      throw new AppError(ErrorCode.BAD_REQUEST, 'Batch is already complete');
    }

    // A batch can be completed straight from "building" (no separate dispatch
    // step required) — every open delivery is delivered. Already failed or
    // delivered deliveries are left as-is.
    const deliverable = batch.deliveries.filter(
      (d) =>
        d.status === DeliveryStatus.scheduled || d.status === DeliveryStatus.in_transit,
    );

    if (deliverable.length === 0) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        'Batch has no in-transit deliveries to complete',
      );
    }

    const deliveryIds = deliverable.map((d) => d.id);
    const trailerIds = deliverable.map((d) => d.trailerId);

    const result = await this.prisma.$transaction(async (tx) => {
      const now = new Date();

      await tx.deliveryBatch.update({
        where: { id },
        data: { status: DeliveryBatchStatus.complete, completedAt: now },
      });

      await tx.delivery.updateMany({
        where: { id: { in: deliveryIds } },
        data: {
          status: DeliveryStatus.delivered,
          deliveredAt: now,
          destinationLocationId: batch.destinationLocationId,
        },
      });

      // A batch landing at a BF stock location leaves its trailers as
      // ready_for_delivery (available stock at that yard); a dealer batch
      // (destination by name only) is terminal — delivered.
      if (batch.destinationLocationId != null) {
        await tx.trailer.updateMany({
          where: { id: { in: trailerIds } },
          data: {
            status: TrailerStatus.ready_for_delivery,
            currentLocationId: batch.destinationLocationId,
          },
        });
      } else {
        await tx.trailer.updateMany({
          where: { id: { in: trailerIds } },
          data: { status: TrailerStatus.delivered },
        });
      }

      // Optional proof-of-delivery photos — attached to every delivery.
      if (dto.photoStorageKeys?.length) {
        await tx.deliveryPhoto.createMany({
          data: deliveryIds.flatMap((deliveryId) =>
            dto.photoStorageKeys!.map((key) => ({
              deliveryId,
              storageUrl: key,
              storageKey: key,
              photoType: PhotoType.proof_of_delivery,
            })),
          ),
        });
      }

      // One batch-level notification per active transport manager.
      const transportManagers = await tx.user.findMany({
        where: { role: 'transport_manager', isActive: true },
        select: { id: true },
      });

      if (transportManagers.length > 0) {
        await tx.pushNotification.createMany({
          data: transportManagers.map((tm) => ({
            recipientUserId: tm.id,
            notificationType: NotificationType.delivery_complete,
            title: `Batch Delivered — ${batch.batchNumber}`,
            body: `${deliverable.length} trailer(s) in batch ${batch.batchNumber} marked delivered.`,
          })),
        });
      }

      return tx.deliveryBatch.findUniqueOrThrow({
        where: { id },
        select: batchSelect,
      });
    });

    // WebSocket: DELIVERY_COMPLETE per delivery so every list refreshes.
    for (const d of deliverable) {
      await this.notificationsService.onDeliveryComplete({
        deliveryId: d.id,
        trailerId: d.trailerId,
        soNumber: d.trailer?.soNumber ?? `#${d.trailerId}`,
        balanceDue: '0.00',
        paymentCollected: '0.00',
      });
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // DELETE /deliveries/batches/:id — delete a batch
  // ---------------------------------------------------------------------------
  // Removes the batch and every delivery attached to it. Any trailer still
  // tied up by a not-yet-delivered delivery is freed back to
  // ready_for_delivery; trailers already delivered are left untouched.
  async deleteBatch(id: bigint) {
    const batch = await this.prisma.deliveryBatch.findUnique({
      where: { id },
      select: {
        id: true,
        deliveries: { select: { id: true, trailerId: true, status: true } },
      },
    });

    if (!batch) {
      throw new AppError(ErrorCode.NOT_FOUND, `Delivery batch with id ${id} not found`);
    }

    const deliveryIds = batch.deliveries.map((d) => d.id);
    const trailersToFree = batch.deliveries
      .filter((d) => d.status !== DeliveryStatus.delivered)
      .map((d) => d.trailerId);

    await this.prisma.$transaction(async (tx) => {
      if (deliveryIds.length > 0) {
        // Photos cascade with the delivery, but location receipts do not and
        // SMS logs are history — unlink them rather than delete.
        await tx.deliveryPhoto.deleteMany({
          where: { deliveryId: { in: deliveryIds } },
        });
        await tx.locationReceipt.deleteMany({
          where: { deliveryId: { in: deliveryIds } },
        });
        await tx.smsLog.updateMany({
          where: { deliveryId: { in: deliveryIds } },
          data: { deliveryId: null },
        });
        await tx.delivery.deleteMany({ where: { id: { in: deliveryIds } } });
      }

      if (trailersToFree.length > 0) {
        await tx.trailer.updateMany({
          where: { id: { in: trailersToFree } },
          data: { status: TrailerStatus.ready_for_delivery },
        });
      }

      await tx.deliveryBatch.delete({ where: { id } });
    });

    return { deleted: true };
  }
}
