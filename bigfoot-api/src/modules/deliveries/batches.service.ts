import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  Prisma,
  DeliveryBatchStatus,
  DeliveryStatus,
  DeliveryType,
  TrailerStatus,
  BatchType,
} from '@prisma/client';
import { CreateBatchDto, UpdateBatchDto } from './dto';
import { NotificationsService } from '../notifications/notifications.service';

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
          trailerModel: { select: { displayName: true, series: true } },
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
  // POST /deliveries/batches — create a new batch
  // ---------------------------------------------------------------------------
  async create(dto: CreateBatchDto, createdByUserId: bigint) {
    return this.prisma.deliveryBatch.create({
      data: {
        batchNumber: dto.batchNumber,
        batchType: dto.batchType as BatchType,
        driverUserId: dto.driverUserId ? BigInt(dto.driverUserId) : null,
        destinationLocationId: dto.destinationLocationId ?? null,
        destinationName: dto.destinationName ?? null,
        createdByUserId,
        status: DeliveryBatchStatus.building,
      },
      select: batchSelect,
    });
  }

  // ---------------------------------------------------------------------------
  // PATCH /deliveries/batches/:id — update batch (add/remove trailers)
  // ---------------------------------------------------------------------------
  async update(id: bigint, dto: UpdateBatchDto, createdByUserId: bigint) {
    const batch = await this.prisma.deliveryBatch.findUnique({
      where: { id },
      select: { id: true, status: true, batchType: true },
    });

    if (!batch) {
      throw new NotFoundException({
        code: 'NOT_FOUND',
        message: `Delivery batch with id ${id} not found`,
      });
    }

    if (batch.status !== DeliveryBatchStatus.building) {
      throw new BadRequestException({
        code: 'BATCH_NOT_BUILDING',
        message: `Cannot modify batch — status is "${batch.status}", must be "building"`,
      });
    }

    return this.prisma.$transaction(async (tx) => {
      // Update batch metadata
      const data: Prisma.DeliveryBatchUpdateInput = {};
      if (dto.driverUserId !== undefined) data.driverUser = dto.driverUserId ? { connect: { id: BigInt(dto.driverUserId) } } : { disconnect: true };
      if (dto.destinationLocationId !== undefined) data.destinationLocation = dto.destinationLocationId ? { connect: { id: dto.destinationLocationId } } : { disconnect: true };
      if (dto.destinationName !== undefined) data.destinationName = dto.destinationName;

      if (Object.keys(data).length > 0) {
        await tx.deliveryBatch.update({ where: { id }, data });
      }

      // Add trailers — batch-fetch for validation, batch-insert for creation
      if (dto.addTrailerIds?.length) {
        const trailerIdBigints = dto.addTrailerIds.map((t) => BigInt(t));
        const trailers = await tx.trailer.findMany({
          where: { id: { in: trailerIdBigints } },
          select: { id: true, status: true },
        });

        const found = new Map(trailers.map((t) => [t.id.toString(), t.status]));
        for (const trailerId of dto.addTrailerIds) {
          const status = found.get(BigInt(trailerId).toString());
          if (status === undefined) {
            throw new NotFoundException({
              code: 'NOT_FOUND',
              message: `Trailer with id ${trailerId} not found`,
            });
          }
          if (status !== TrailerStatus.ready_for_delivery) {
            throw new BadRequestException({
              code: 'DELIVERY_NOT_DISPATCHABLE',
              message: `Trailer ${trailerId} status is "${status}" — must be "ready_for_delivery"`,
            });
          }
        }

        const deliveryType = batch.batchType === BatchType.dealer
          ? DeliveryType.stack_to_dealer
          : DeliveryType.stack_to_location;

        await tx.delivery.createMany({
          data: trailerIdBigints.map((trailerId) => ({
            trailerId,
            deliveryBatchId: id,
            deliveryType,
            status: DeliveryStatus.scheduled,
            createdByUserId,
          })),
        });
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

      return tx.deliveryBatch.findUnique({
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
      throw new NotFoundException({
        code: 'NOT_FOUND',
        message: `Delivery batch with id ${id} not found`,
      });
    }

    if (batch.status !== DeliveryBatchStatus.building && batch.status !== DeliveryBatchStatus.scheduled) {
      throw new BadRequestException({
        code: 'BAD_REQUEST',
        message: `Batch status is "${batch.status}" — must be "building" or "scheduled" to dispatch`,
      });
    }

    if (batch.deliveries.length === 0) {
      throw new BadRequestException({
        code: 'BAD_REQUEST',
        message: 'Cannot dispatch an empty batch',
      });
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

      return tx.deliveryBatch.findUnique({
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
}
