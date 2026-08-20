import { Injectable } from '@nestjs/common';
import { AppError, ErrorCode } from '../../common/errors';
import { PrismaService } from '../../prisma/prisma.service';
import { SupportService } from '../support/support.service';
import { SubmitAuditDto } from './dto';

/// Safety cap so a fat-fingered submit can't spawn thousands of tickets.
const MAX_REPORTS = 300;

@Injectable()
export class YardAuditService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly support: SupportService,
  ) {}

  // ---------------------------------------------------------------------------
  // POST /yard-audit — reconcile the app's inventory for a yard against the
  // physical lot. Opens ONE problem report per discrepancy:
  //   - missingTrailerIds: listed in the app at this yard, not found on the lot
  //   - extras: found on the lot, not listed by the app for this yard
  // Reports are filed as the auditor, so they show in the auditor's "My
  // reports" and notify the admins, exactly like a hand-typed report.
  // ---------------------------------------------------------------------------
  async submitAudit(auditorUserId: bigint, dto: SubmitAuditDto) {
    const location = await this.prisma.location.findUnique({
      where: { id: dto.locationId },
      select: { id: true, name: true },
    });
    if (!location) {
      throw new AppError(ErrorCode.NOT_FOUND, `Location ${dto.locationId} not found.`);
    }

    const missingIds = [...new Set(dto.missingTrailerIds ?? [])];
    const extras = (dto.extras ?? []).filter(
      (e) => (e.soNumber && e.soNumber.trim()) || (e.note && e.note.trim()),
    );

    if (missingIds.length + extras.length > MAX_REPORTS) {
      throw new AppError(
        ErrorCode.BAD_REQUEST,
        `A single audit can open at most ${MAX_REPORTS} reports.`,
      );
    }

    const auditor = await this.prisma.user.findUnique({
      where: { id: auditorUserId },
      select: { fullName: true },
    });
    const auditorName = auditor?.fullName ?? 'Someone';
    const today = new Date().toISOString().slice(0, 10);

    const ticketIds: string[] = [];

    // --- Missing: app-says-here, not-on-lot ---------------------------------
    if (missingIds.length > 0) {
      const trailers = await this.prisma.trailer.findMany({
        where: { id: { in: missingIds.map((n) => BigInt(n)) } },
        select: {
          id: true,
          soNumber: true,
          trailerModel: { select: { displayName: true } },
        },
      });
      const byId = new Map(trailers.map((t) => [t.id.toString(), t]));

      for (const id of missingIds) {
        const t = byId.get(String(id));
        const so = t?.soNumber ?? `#${id}`;
        const model = t?.trailerModel?.displayName;
        const ticket = await this.support.createTicket(auditorUserId, {
          subject: `Yard audit — SO ${so} not in ${location.name}`,
          body:
            `${auditorName} audited ${location.name} on ${today} and could not ` +
            `find SO ${so}${model ? ` (${model})` : ''} on the lot, though the app ` +
            `lists it there. Please locate the trailer or correct its location.`,
        });
        ticketIds.push(ticket.id);
      }
    }

    // --- Extras: on-lot, app-doesn't-expect-here ----------------------------
    for (const e of extras) {
      const so = e.soNumber?.trim();
      const note = e.note?.trim();
      const who = so ? `SO ${so}` : 'a trailer';
      const ticket = await this.support.createTicket(auditorUserId, {
        subject: `Yard audit — unexpected trailer in ${location.name}`,
        body:
          `${auditorName} found ${who} physically in ${location.name} on ${today} ` +
          `that the app does not list at this yard.` +
          `${note ? ` Note: ${note}` : ''} Please reconcile its record.`,
      });
      ticketIds.push(ticket.id);
    }

    // Accountability trail for the audit itself.
    await this.prisma.auditLog.create({
      data: {
        userId: auditorUserId,
        entityType: 'location',
        entityId: BigInt(location.id),
        action: 'yard_audit.submitted',
        newValues: {
          yard: location.name,
          missingReported: missingIds.length,
          extrasReported: extras.length,
          ticketIds,
        },
      },
    });

    return {
      locationId: location.id,
      locationName: location.name,
      missingReported: missingIds.length,
      extrasReported: extras.length,
      totalReported: ticketIds.length,
    };
  }
}
