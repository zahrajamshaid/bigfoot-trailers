import { Injectable } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { AppError, ErrorCode } from '../../common/errors';
import { PushService } from '../notifications/push.service';
import { CreateTicketDto, CreateMessageDto } from './dto';

// Roles that see every ticket + can reply/resolve. Office is included here
// explicitly (it also bypasses the RolesGuard, but the service needs to know
// it's an admin so it gets the full list, not just its own tickets).
const ADMIN_ROLES: UserRole[] = [
  UserRole.owner,
  UserRole.office,
  UserRole.production_manager,
];

@Injectable()
export class SupportService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly push: PushService,
  ) {}

  private isAdmin(role: string): boolean {
    return (ADMIN_ROLES as string[]).includes(role);
  }

  // ---------------------------------------------------------------------------
  // Create a ticket + its first message, then notify the admin tier.
  // ---------------------------------------------------------------------------
  async createTicket(reporterUserId: bigint, dto: CreateTicketDto) {
    const ticket = await this.prisma.$transaction(async (tx) => {
      const created = await tx.supportTicket.create({
        data: {
          reporterUserId,
          subject: dto.subject.trim(),
          messages: {
            create: { senderUserId: reporterUserId, body: dto.body.trim() },
          },
        },
        select: { id: true, subject: true },
      });
      return created;
    });

    const reporter = await this.prisma.user.findUnique({
      where: { id: reporterUserId },
      select: { fullName: true },
    });

    // Notify owner/office/PM (never the reporter, even if they're an admin).
    const admins = await this.prisma.user.findMany({
      where: {
        role: { in: ADMIN_ROLES },
        isActive: true,
        id: { not: reporterUserId },
      },
      select: { id: true },
    });
    if (admins.length > 0) {
      // Best-effort: a push hiccup must never fail the report.
      try {
        await this.push.sendSupportTicketOpened(
          ticket.id,
          ticket.subject,
          reporter?.fullName ?? 'Someone',
          admins.map((a) => a.id),
        );
      } catch {
        // swallowed — the ticket is saved; admins still see it in the inbox
      }
    }

    return this.getTicket(reporterUserId, 'reporter-self', ticket.id);
  }

  // ---------------------------------------------------------------------------
  // List tickets: admins see all, everyone else sees only their own.
  // ---------------------------------------------------------------------------
  async listTickets(userId: bigint, role: string) {
    const tickets = await this.prisma.supportTicket.findMany({
      where: this.isAdmin(role) ? {} : { reporterUserId: userId },
      orderBy: { updatedAt: 'desc' },
      select: {
        id: true,
        subject: true,
        status: true,
        createdAt: true,
        updatedAt: true,
        reporter: { select: { id: true, fullName: true, role: true } },
        messages: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          select: { body: true, createdAt: true, senderUserId: true },
        },
        _count: { select: { messages: true } },
      },
    });

    return tickets.map((t) => ({
      id: t.id.toString(),
      subject: t.subject,
      status: t.status,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
      reporterName: t.reporter.fullName,
      reporterId: t.reporter.id.toString(),
      messageCount: t._count.messages,
      lastMessage: t.messages[0]
        ? {
            preview: t.messages[0].body.slice(0, 140),
            at: t.messages[0].createdAt,
            fromReporter: t.messages[0].senderUserId === t.reporter.id,
          }
        : null,
    }));
  }

  // ---------------------------------------------------------------------------
  // One ticket + its full thread. Reporter or admin only.
  // ---------------------------------------------------------------------------
  async getTicket(userId: bigint, role: string, ticketId: bigint) {
    const ticket = await this.prisma.supportTicket.findUnique({
      where: { id: ticketId },
      select: {
        id: true,
        subject: true,
        status: true,
        reporterUserId: true,
        createdAt: true,
        updatedAt: true,
        reporter: { select: { id: true, fullName: true, role: true } },
        messages: {
          orderBy: { createdAt: 'asc' },
          select: {
            id: true,
            body: true,
            createdAt: true,
            senderUserId: true,
            sender: { select: { id: true, fullName: true, role: true } },
          },
        },
      },
    });

    if (!ticket) {
      throw new AppError(ErrorCode.NOT_FOUND, `Ticket ${ticketId} not found`);
    }
    // 'reporter-self' is an internal caller from createTicket right after
    // creation — the reporter always owns their fresh ticket.
    const isOwner = ticket.reporterUserId === userId;
    if (role !== 'reporter-self' && !isOwner && !this.isAdmin(role)) {
      throw new AppError(ErrorCode.FORBIDDEN, 'Not allowed to view this ticket');
    }

    return {
      id: ticket.id.toString(),
      subject: ticket.subject,
      status: ticket.status,
      createdAt: ticket.createdAt,
      updatedAt: ticket.updatedAt,
      reporterId: ticket.reporter.id.toString(),
      reporterName: ticket.reporter.fullName,
      messages: ticket.messages.map((m) => ({
        id: m.id.toString(),
        body: m.body,
        at: m.createdAt,
        senderId: m.senderUserId.toString(),
        senderName: m.sender.fullName,
        fromReporter: m.senderUserId === ticket.reporterUserId,
      })),
    };
  }

  // ---------------------------------------------------------------------------
  // Post a message on the thread. Reporter or admin. Reopens a resolved ticket
  // and notifies the other side.
  // ---------------------------------------------------------------------------
  async addMessage(
    userId: bigint,
    role: string,
    ticketId: bigint,
    dto: CreateMessageDto,
  ) {
    const ticket = await this.prisma.supportTicket.findUnique({
      where: { id: ticketId },
      select: { id: true, subject: true, reporterUserId: true, status: true },
    });
    if (!ticket) {
      throw new AppError(ErrorCode.NOT_FOUND, `Ticket ${ticketId} not found`);
    }
    const isOwner = ticket.reporterUserId === userId;
    const admin = this.isAdmin(role);
    if (!isOwner && !admin) {
      throw new AppError(ErrorCode.FORBIDDEN, 'Not allowed to post on this ticket');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.supportTicketMessage.create({
        data: { ticketId, senderUserId: userId, body: dto.body.trim() },
      });
      // A new message reopens a resolved ticket and always bumps updatedAt.
      await tx.supportTicket.update({
        where: { id: ticketId },
        data: { status: 'open', updatedAt: new Date() },
      });
    });

    const sender = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { fullName: true },
    });

    // Notify the other side: an admin reply → the reporter; a reporter message
    // → the admin tier (minus the reporter).
    try {
      let recipientIds: bigint[];
      if (admin && !isOwner) {
        recipientIds = [ticket.reporterUserId];
      } else {
        const admins = await this.prisma.user.findMany({
          where: {
            role: { in: ADMIN_ROLES },
            isActive: true,
            id: { not: userId },
          },
          select: { id: true },
        });
        recipientIds = admins.map((a) => a.id);
      }
      if (recipientIds.length > 0) {
        await this.push.sendSupportTicketReply(
          ticket.id,
          ticket.subject,
          sender?.fullName ?? 'Someone',
          recipientIds,
        );
      }
    } catch {
      // swallowed — message is saved regardless
    }

    return this.getTicket(userId, role, ticketId);
  }

  // ---------------------------------------------------------------------------
  // Resolve / reopen — admins only.
  // ---------------------------------------------------------------------------
  async setStatus(
    userId: bigint,
    role: string,
    ticketId: bigint,
    status: 'open' | 'resolved',
  ) {
    if (!this.isAdmin(role)) {
      throw new AppError(ErrorCode.FORBIDDEN, 'Only admins can change ticket status');
    }
    const ticket = await this.prisma.supportTicket.findUnique({
      where: { id: ticketId },
      select: { id: true },
    });
    if (!ticket) {
      throw new AppError(ErrorCode.NOT_FOUND, `Ticket ${ticketId} not found`);
    }
    await this.prisma.supportTicket.update({
      where: { id: ticketId },
      data: { status },
    });
    return this.getTicket(userId, role, ticketId);
  }

  // Delete a ticket + its whole thread (messages cascade). Admins only — used
  // to clear out stale / test conversations.
  async deleteTicket(role: string, ticketId: bigint): Promise<{ deleted: true }> {
    if (!this.isAdmin(role)) {
      throw new AppError(ErrorCode.FORBIDDEN, 'Only admins can delete tickets');
    }
    const ticket = await this.prisma.supportTicket.findUnique({
      where: { id: ticketId },
      select: { id: true },
    });
    if (!ticket) {
      throw new AppError(ErrorCode.NOT_FOUND, `Ticket ${ticketId} not found`);
    }
    await this.prisma.supportTicket.delete({ where: { id: ticketId } });
    return { deleted: true };
  }

  // Unresolved-ticket count for the admin dashboard badge.
  async openCount(): Promise<{ count: number }> {
    const count = await this.prisma.supportTicket.count({
      where: { status: 'open' },
    });
    return { count };
  }
}
