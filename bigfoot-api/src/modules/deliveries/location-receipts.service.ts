import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateLocationReceiptDto } from './dto';

@Injectable()
export class LocationReceiptsService {
  constructor(private readonly prisma: PrismaService) {}

  // ---------------------------------------------------------------------------
  // POST /location-receipts — remote location staff confirms receipt
  // ---------------------------------------------------------------------------
  async create(dto: CreateLocationReceiptDto, receivedByUserId: bigint) {
    // Look up user's primary location
    const user = await this.prisma.user.findUnique({
      where: { id: receivedByUserId },
      select: { primaryLocationId: true },
    });

    const userLocationId = user?.primaryLocationId ?? null;

    // Validate the delivery exists
    const delivery = await this.prisma.delivery.findUnique({
      where: { id: BigInt(dto.deliveryId) },
      select: {
        id: true,
        trailerId: true,
        destinationLocationId: true,
        destinationLocation: { select: { id: true, name: true } },
      },
    });

    if (!delivery) {
      throw new NotFoundException({
        code: 'NOT_FOUND',
        message: `Delivery with id ${dto.deliveryId} not found`,
      });
    }

    // Validate the trailer matches
    if (delivery.trailerId !== BigInt(dto.trailerId)) {
      throw new BadRequestException({
        code: 'BAD_REQUEST',
        message: `Trailer ${dto.trailerId} does not match delivery ${dto.deliveryId}`,
      });
    }

    // Validate user's location matches delivery destination
    if (!delivery.destinationLocationId) {
      throw new BadRequestException({
        code: 'BAD_REQUEST',
        message: `Delivery ${dto.deliveryId} does not have a destination location`,
      });
    }

    if (userLocationId !== delivery.destinationLocationId) {
      throw new BadRequestException({
        code: 'LOCATION_RECEIPT_WRONG_LOCATION',
        message: `Your location (${userLocationId}) does not match the delivery destination (${delivery.destinationLocation?.name})`,
      });
    }

    return this.prisma.locationReceipt.create({
      data: {
        deliveryId: BigInt(dto.deliveryId),
        trailerId: BigInt(dto.trailerId),
        receivedByUserId,
        locationId: delivery.destinationLocationId,
        notes: dto.notes ?? null,
      },
      select: {
        id: true,
        deliveryId: true,
        trailerId: true,
        notes: true,
        receivedAt: true,
        receivedByUser: { select: { id: true, fullName: true } },
        location: { select: { id: true, name: true } },
      },
    });
  }
}
