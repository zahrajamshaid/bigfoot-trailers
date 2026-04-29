import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { NotificationsService } from './notifications.service';
import { CreateWorkerMessageDto } from './dto';

@Injectable()
export class MessagesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notificationsService: NotificationsService,
  ) {}

  // ---------------------------------------------------------------------------
  // POST /messages — worker sends message from floor
  // ---------------------------------------------------------------------------
  async create(dto: CreateWorkerMessageDto, fromUserId: bigint) {
    // Validate trailer exists
    const trailer = await this.prisma.trailer.findUnique({
      where: { id: BigInt(dto.trailerId) },
      select: { id: true, soNumber: true },
    });

    if (!trailer) {
      throw new NotFoundException({
        code: 'NOT_FOUND',
        message: `Trailer with id ${dto.trailerId} not found`,
      });
    }

    // Validate recipient exists and is a salesperson
    const recipient = await this.prisma.user.findUnique({
      where: { id: BigInt(dto.toUserId) },
      select: { id: true, role: true, fullName: true },
    });

    if (!recipient) {
      throw new NotFoundException({
        code: 'NOT_FOUND',
        message: `User with id ${dto.toUserId} not found`,
      });
    }

    // Look up sender name
    const sender = await this.prisma.user.findUnique({
      where: { id: fromUserId },
      select: { fullName: true },
    });

    // Create message
    const message = await this.prisma.workerMessage.create({
      data: {
        trailerId: BigInt(dto.trailerId),
        fromUserId,
        toUserId: BigInt(dto.toUserId),
        messageText: dto.messageText,
      },
      select: {
        id: true,
        trailerId: true,
        messageText: true,
        isRead: true,
        sentAt: true,
        fromUser: { select: { id: true, fullName: true } },
        toUser: { select: { id: true, fullName: true } },
        trailer: { select: { id: true, soNumber: true } },
      },
    });

    // Send push notification to recipient (worker_message type)
    await this.notificationsService.onWorkerMessage(
      BigInt(dto.toUserId),
      BigInt(dto.trailerId),
      trailer.soNumber,
      sender?.fullName ?? 'Unknown',
      dto.messageText,
    );

    return message;
  }
}
