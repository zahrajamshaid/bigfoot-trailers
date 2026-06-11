import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { CreateAnnouncementDto, UpdateAnnouncementDto } from './dto';

/**
 * Parses an ISO datetime → Date or null. Used for the optional `expiresAt`
 * field on create/update so a missing or malformed value resolves cleanly
 * to null instead of throwing.
 */
function parseISODate(value: string | null | undefined): Date | null {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

const adminSelect = {
  id: true,
  title: true,
  body: true,
  postedByUserId: true,
  isActive: true,
  expiresAt: true,
  createdAt: true,
  postedByUser: { select: { id: true, fullName: true, email: true } },
} satisfies Prisma.SystemAnnouncementSelect;

@Injectable()
export class AnnouncementsService {
  constructor(private readonly prisma: PrismaService) {}

  // ---------------------------------------------------------------------------
  // GET /announcements/pending — every authenticated user
  //
  // Returns active, unexpired announcements the caller hasn't acked. Oldest
  // first so the mobile shell shows them one at a time in creation order.
  // ---------------------------------------------------------------------------
  async getPendingForUser(userId: bigint) {
    const now = new Date();
    return this.prisma.systemAnnouncement.findMany({
      where: {
        isActive: true,
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
        acks: { none: { userId } },
      },
      orderBy: { createdAt: 'asc' },
      select: {
        id: true,
        title: true,
        body: true,
        createdAt: true,
        postedByUser: { select: { fullName: true } },
      },
    });
  }

  // ---------------------------------------------------------------------------
  // POST /announcements/:id/ack — every authenticated user
  //
  // Idempotent: re-acks are absorbed by the unique constraint.
  // ---------------------------------------------------------------------------
  async ack(announcementId: bigint, userId: bigint): Promise<{ acked: true }> {
    const exists = await this.prisma.systemAnnouncement.findUnique({
      where: { id: announcementId },
      select: { id: true },
    });
    if (!exists) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Announcement ${announcementId} not found.`,
      );
    }

    try {
      await this.prisma.systemAnnouncementAck.create({
        data: { announcementId, userId },
      });
    } catch (e) {
      // P2002 = unique-constraint violation — already acked. No-op.
      if (
        !(e instanceof Prisma.PrismaClientKnownRequestError) ||
        e.code !== 'P2002'
      ) {
        throw e;
      }
    }
    return { acked: true };
  }

  // ---------------------------------------------------------------------------
  // POST /admin/announcements — owner + production_manager
  // ---------------------------------------------------------------------------
  async create(dto: CreateAnnouncementDto, postedByUserId: bigint) {
    return this.prisma.systemAnnouncement.create({
      data: {
        title: dto.title?.trim() || null,
        body: dto.body.trim(),
        expiresAt: parseISODate(dto.expiresAt),
        postedByUserId,
      },
      select: adminSelect,
    });
  }

  // ---------------------------------------------------------------------------
  // GET /admin/announcements — owner + production_manager
  //
  // Includes per-row ack count + total eligible user count so the admin
  // screen can show "X of Y acknowledged" without a separate request.
  // ---------------------------------------------------------------------------
  async findAllForAdmin() {
    const [rows, totalUsers] = await Promise.all([
      this.prisma.systemAnnouncement.findMany({
        orderBy: { createdAt: 'desc' },
        select: {
          ...adminSelect,
          _count: { select: { acks: true } },
        },
      }),
      this.prisma.user.count({ where: { isActive: true } }),
    ]);
    return rows.map((row) => {
      const { _count, ...rest } = row;
      return {
        ...rest,
        ackCount: _count.acks,
        totalUsers,
      };
    });
  }

  // ---------------------------------------------------------------------------
  // PATCH /admin/announcements/:id — owner + production_manager
  // ---------------------------------------------------------------------------
  async update(id: bigint, dto: UpdateAnnouncementDto) {
    const existing = await this.prisma.systemAnnouncement.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!existing) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Announcement ${id} not found.`,
      );
    }

    const data: Prisma.SystemAnnouncementUpdateInput = {};
    if (dto.title !== undefined) data.title = dto.title?.trim() || null;
    if (dto.body !== undefined) data.body = dto.body.trim();
    if (dto.isActive !== undefined) data.isActive = dto.isActive;
    if (dto.expiresAt !== undefined) {
      data.expiresAt = parseISODate(dto.expiresAt);
    }

    return this.prisma.systemAnnouncement.update({
      where: { id },
      data,
      select: adminSelect,
    });
  }

  // ---------------------------------------------------------------------------
  // DELETE /admin/announcements/:id — owner + production_manager
  //
  // Hard delete with ON DELETE CASCADE on the ack rows. Use the update
  // endpoint with isActive=false if you want to keep the audit trail.
  // ---------------------------------------------------------------------------
  async remove(id: bigint): Promise<{ deleted: true }> {
    const existing = await this.prisma.systemAnnouncement.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!existing) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Announcement ${id} not found.`,
      );
    }
    await this.prisma.systemAnnouncement.delete({ where: { id } });
    return { deleted: true };
  }
}
