import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';

/// Each foreground heartbeat represents ~this many seconds of use — the first
/// ping of a day seeds the counter with it.
const HEARTBEAT_SECONDS = 60;
/// Gaps between heartbeats longer than this are treated as "the app was
/// backgrounded / idle" and are NOT counted as active time. Keeps a phone left
/// on the login screen overnight from reading as 8h of use. ~2.5× the client's
/// 60s heartbeat interval.
const GAP_CAP_SECONDS = 150;

/// UTC midnight for the calendar day a timestamp falls in — the bucket key.
function startOfUtcDay(now: Date): Date {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

/// Parse a YYYY-MM-DD (or ISO) string to a UTC-midnight Date, or null.
function parseDay(value: string | undefined): Date | null {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : startOfUtcDay(d);
}

@Injectable()
export class ActivityService {
  constructor(private readonly prisma: PrismaService) {}

  // ---------------------------------------------------------------------------
  // POST /activity/heartbeat — every authenticated user, ~every 60s while the
  // app is foregrounded. Rolls the ping into today's per-user row: extends
  // lastSeenAt and adds the (gap-capped) elapsed time to activeSeconds.
  // ---------------------------------------------------------------------------
  async recordHeartbeat(userId: bigint): Promise<{ ok: true }> {
    const now = new Date();
    const day = startOfUtcDay(now);

    const existing = await this.prisma.userActivityDaily.findUnique({
      where: { userId_day: { userId, day } },
      select: { lastSeenAt: true },
    });

    if (!existing) {
      try {
        await this.prisma.userActivityDaily.create({
          data: {
            userId,
            day,
            firstSeenAt: now,
            lastSeenAt: now,
            activeSeconds: HEARTBEAT_SECONDS,
            pingCount: 1,
          },
        });
        return { ok: true };
      } catch (e) {
        // Two heartbeats raced to create the day's row — fall through to update.
        if (!(e instanceof Prisma.PrismaClientKnownRequestError) || e.code !== 'P2002') {
          throw e;
        }
      }
    }

    const last = existing?.lastSeenAt ?? now;
    const gapSec = Math.max(0, Math.floor((now.getTime() - last.getTime()) / 1000));
    const add = Math.min(gapSec, GAP_CAP_SECONDS);

    await this.prisma.userActivityDaily.update({
      where: { userId_day: { userId, day } },
      data: {
        lastSeenAt: now,
        activeSeconds: { increment: add },
        pingCount: { increment: 1 },
      },
    });
    return { ok: true };
  }

  // ---------------------------------------------------------------------------
  // GET /activity/summary — owner/office. Per-user usage over [from, to]
  // (default: the last 7 days), busiest first.
  // ---------------------------------------------------------------------------
  async getSummary(fromStr?: string, toStr?: string) {
    const { from, to } = this.resolveRange(fromStr, toStr);

    const grouped = await this.prisma.userActivityDaily.groupBy({
      by: ['userId'],
      where: { day: { gte: from, lte: to } },
      _sum: { activeSeconds: true },
      _count: { day: true },
      _max: { lastSeenAt: true },
    });

    const users = await this.prisma.user.findMany({
      where: { id: { in: grouped.map((g) => g.userId) } },
      select: { id: true, fullName: true, role: true },
    });
    const byId = new Map(users.map((u) => [u.id.toString(), u]));

    const rows = grouped
      .map((g) => {
        const u = byId.get(g.userId.toString());
        return {
          userId: g.userId.toString(),
          fullName: u?.fullName ?? 'Unknown',
          role: u?.role ?? null,
          daysActive: g._count.day,
          totalActiveSeconds: g._sum.activeSeconds ?? 0,
          lastSeenAt: g._max.lastSeenAt,
        };
      })
      .sort((a, b) => b.totalActiveSeconds - a.totalActiveSeconds);

    return {
      from: from.toISOString().slice(0, 10),
      to: to.toISOString().slice(0, 10),
      users: rows,
    };
  }

  // ---------------------------------------------------------------------------
  // GET /activity/summary/:userId — owner/office. One user's day-by-day usage.
  // ---------------------------------------------------------------------------
  async getUserDaily(userId: bigint, fromStr?: string, toStr?: string) {
    const { from, to } = this.resolveRange(fromStr, toStr);
    const days = await this.prisma.userActivityDaily.findMany({
      where: { userId, day: { gte: from, lte: to } },
      orderBy: { day: 'desc' },
      select: {
        day: true,
        activeSeconds: true,
        firstSeenAt: true,
        lastSeenAt: true,
        pingCount: true,
      },
    });
    return {
      from: from.toISOString().slice(0, 10),
      to: to.toISOString().slice(0, 10),
      days: days.map((d) => ({
        day: d.day.toISOString().slice(0, 10),
        activeSeconds: d.activeSeconds,
        firstSeenAt: d.firstSeenAt,
        lastSeenAt: d.lastSeenAt,
        pingCount: d.pingCount,
      })),
    };
  }

  /// Resolve the [from, to] window, defaulting to the last 7 days (inclusive).
  private resolveRange(
    fromStr?: string,
    toStr?: string,
  ): {
    from: Date;
    to: Date;
  } {
    const to = parseDay(toStr) ?? startOfUtcDay(new Date());
    const from = parseDay(fromStr) ?? new Date(to.getTime() - 6 * 24 * 60 * 60 * 1000); // 7-day window
    return { from, to };
  }
}
