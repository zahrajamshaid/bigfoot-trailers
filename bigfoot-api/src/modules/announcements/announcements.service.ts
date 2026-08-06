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
  frequency: true,
  expiresAt: true,
  createdAt: true,
  postedByUser: { select: { id: true, fullName: true, email: true } },
} satisfies Prisma.SystemAnnouncementSelect;

/// Start of the current UTC day / week (Sunday). Matches the UTC day/week
/// boundaries the production reports use, so "daily" / "weekly" recurrence
/// lines up with the rest of the app rather than the server's local zone.
function startOfUtcDay(now: Date): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}
function startOfUtcWeek(now: Date): Date {
  return new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - now.getUTCDay()),
  );
}

/// Given an announcement's recurrence + the caller's most recent ack, decide
/// whether it should surface again. `once` hides permanently after the first
/// ack; `every_login` always surfaces (the client suppresses re-showing within
/// a single session); `daily` / `weekly` re-surface once the ack falls before
/// the current day / week boundary.
function isPendingByFrequency(
  frequency: string,
  lastAckedAt: Date | null,
  now: Date,
): boolean {
  if (!lastAckedAt) return true;
  switch (frequency) {
    case 'every_login':
      return true;
    case 'daily':
      return lastAckedAt < startOfUtcDay(now);
    case 'weekly':
      return lastAckedAt < startOfUtcWeek(now);
    case 'once':
    default:
      return false;
  }
}

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
    // Pull every active, unexpired announcement plus THIS user's ack (if any),
    // then filter by each row's recurrence rule. We can't express "re-show if
    // the ack is older than today/this week" purely in a Prisma `where`, so the
    // per-user ack is joined and the frequency decision is made in code.
    const rows = await this.prisma.systemAnnouncement.findMany({
      where: {
        isActive: true,
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
      orderBy: { createdAt: 'asc' },
      select: {
        id: true,
        title: true,
        body: true,
        frequency: true,
        createdAt: true,
        postedByUser: { select: { fullName: true } },
        acks: {
          where: { userId },
          orderBy: { ackedAt: 'desc' },
          take: 1,
          select: { ackedAt: true },
        },
      },
    });

    return rows
      .filter((row) =>
        isPendingByFrequency(row.frequency, row.acks[0]?.ackedAt ?? null, now),
      )
      .map(({ acks: _acks, ...rest }) => rest);
  }

  // ---------------------------------------------------------------------------
  // POST /announcements/:id/ack — every authenticated user
  //
  // Upserts the ack, refreshing `ackedAt`. For `once` announcements the row
  // simply exists (and hides it forever); for `daily` / `weekly` the refreshed
  // timestamp is what lets the announcement re-surface after the next day / week
  // boundary. One row per (announcement, user) via the unique constraint.
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

    await this.prisma.systemAnnouncementAck.upsert({
      where: { announcementId_userId: { announcementId, userId } },
      create: { announcementId, userId },
      update: { ackedAt: new Date() },
    });
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
        frequency: dto.frequency ?? 'once',
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
      throw new AppError(ErrorCode.NOT_FOUND, `Announcement ${id} not found.`);
    }

    const data: Prisma.SystemAnnouncementUpdateInput = {};
    if (dto.title !== undefined) data.title = dto.title?.trim() || null;
    if (dto.body !== undefined) data.body = dto.body.trim();
    if (dto.frequency !== undefined) data.frequency = dto.frequency;
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
      throw new AppError(ErrorCode.NOT_FOUND, `Announcement ${id} not found.`);
    }
    await this.prisma.systemAnnouncement.delete({ where: { id } });
    return { deleted: true };
  }
}
