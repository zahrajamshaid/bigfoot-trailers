import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import {
  diffFields,
  humanAction,
  summarize,
} from '../../common/audit/audit-humanizer';
import { Prisma } from '@prisma/client';

export interface CreateAuditLogEntry {
  userId?: number | bigint | null;
  entityType: string;
  entityId: number | bigint;
  action: string;
  oldValues?: Prisma.InputJsonValue | null;
  newValues?: Prisma.InputJsonValue | null;
  ipAddress?: string | null;
}

export interface QueryAuditLogParams {
  entityType?: string;
  entityId?: number;
  userId?: number;
  from?: string;
  to?: string;
  page?: number;
  limit?: number;
  /// Free-text filter. Numeric → SO number lookup; otherwise matches on
  /// user.fullName + action (ILIKE). See QueryAuditLogDto for details.
  q?: string;
}

const auditLogSelect = {
  id: true,
  userId: true,
  entityType: true,
  entityId: true,
  action: true,
  oldValues: true,
  newValues: true,
  ipAddress: true,
  createdAt: true,
  user: { select: { id: true, fullName: true, email: true } },
} satisfies Prisma.AuditLogSelect;

// Raw row coming out of Prisma with the select above.
type RawAuditLogItem = Prisma.AuditLogGetPayload<{ select: typeof auditLogSelect }>;

// Enriched row sent to the client: same shape + three human-readable fields.
type EnrichedAuditLogItem = RawAuditLogItem & {
  /// Stable, human label for the thing that changed (e.g. "SO 6715",
  /// "SO 6715 — QC_3", "Batch OPEN-BATCH-TROPIC"). Falls back to the raw
  /// `entityType #entityId` when the entity has been deleted / can't be resolved.
  entityLabel: string;
  /// One-line description of *what* the action did, derived from
  /// action + old/new values when possible (e.g. "Status: in_production →
  /// ready_for_delivery"). Falls back to a generic "Created / Updated /
  /// Deleted" verb.
  summary: string;
  /// The action rendered as a verb the admin recognises (CREATE → "Created",
  /// trailer.jumped_to_step → "Jumped to step", etc).
  actionLabel: string;
};

@Injectable()
export class AuditLogService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Append-only: create a single audit log entry.
   * Can be called inside or outside a transaction.
   */
  async create(entry: CreateAuditLogEntry, tx?: Prisma.TransactionClient): Promise<void> {
    const client = tx ?? this.prisma;
    await client.auditLog.create({
      data: {
        userId: entry.userId != null ? BigInt(entry.userId) : null,
        entityType: entry.entityType,
        entityId: BigInt(entry.entityId),
        action: entry.action,
        oldValues: entry.oldValues ?? Prisma.JsonNull,
        newValues: entry.newValues ?? Prisma.JsonNull,
        ipAddress: entry.ipAddress ?? null,
      },
      select: { id: true },
    });
  }

  /**
   * Query audit log with filters and pagination.
   */
  async findAll(params: QueryAuditLogParams) {
    const page = params.page ?? 1;
    const limit = Math.min(params.limit ?? 50, 200);
    const skip = (page - 1) * limit;

    const where: Prisma.AuditLogWhereInput = {};

    if (params.entityType) where.entityType = params.entityType;
    if (params.entityId) where.entityId = BigInt(params.entityId);
    if (params.userId) where.userId = BigInt(params.userId);

    if (params.from || params.to) {
      where.createdAt = {};
      if (params.from) where.createdAt.gte = new Date(params.from);
      if (params.to) where.createdAt.lte = new Date(params.to);
    }

    // Free-text search. Numeric input is treated as an SO number — we
    // resolve it to the trailer and its dependent rows (steps, QC
    // inspections, deliveries) so the search catches every entity the
    // trailer ever touched. Non-numeric falls back to ILIKE against
    // user.fullName and action.
    const q = params.q?.trim();
    if (q) {
      if (/^\d+$/.test(q)) {
        const trailer = await this.prisma.trailer.findUnique({
          where: { soNumber: q },
          select: { id: true },
        });
        if (trailer) {
          const [steps, qcs, deliveries] = await Promise.all([
            this.prisma.productionStep.findMany({
              where: { trailerId: trailer.id },
              select: { id: true },
            }),
            this.prisma.qcInspection.findMany({
              where: { trailerId: trailer.id },
              select: { id: true },
            }),
            this.prisma.delivery.findMany({
              where: { trailerId: trailer.id },
              select: { id: true },
            }),
          ]);
          where.OR = [
            { entityType: { in: ['trailer', 'production_trailer'] }, entityId: trailer.id },
            ...(steps.length
              ? [
                  {
                    entityType: { in: ['step', 'production_step'] },
                    entityId: { in: steps.map((s) => s.id) },
                  },
                ]
              : []),
            ...(qcs.length
              ? [
                  {
                    entityType: 'qc_inspection',
                    entityId: { in: qcs.map((q) => q.id) },
                  },
                ]
              : []),
            ...(deliveries.length
              ? [
                  {
                    entityType: 'delivery',
                    entityId: { in: deliveries.map((d) => d.id) },
                  },
                ]
              : []),
          ];
        } else {
          // No trailer with that SO — short-circuit to an impossible
          // condition so the count + list both return empty cleanly.
          where.id = BigInt(-1);
        }
      } else {
        where.OR = [
          { action: { contains: q, mode: 'insensitive' } },
          { user: { fullName: { contains: q, mode: 'insensitive' } } },
        ];
      }
    }

    const [items, total] = await Promise.all([
      this.prisma.auditLog.findMany({
        where,
        select: auditLogSelect,
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
      }),
      this.prisma.auditLog.count({ where }),
    ]);

    return {
      items: await this.enrich(items),
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  /**
   * Paginated audit history for a specific entity.
   * Hard-capped at 500 rows per page to prevent memory blow-ups on hot entities.
   */
  async findByEntity(
    entityType: string,
    entityId: number,
    params: { page?: number; limit?: number } = {},
  ) {
    const page = Math.max(1, params.page ?? 1);
    const limit = Math.min(500, Math.max(1, params.limit ?? 100));
    const skip = (page - 1) * limit;

    const [items, total] = await this.prisma.$transaction([
      this.prisma.auditLog.findMany({
        where: { entityType, entityId: BigInt(entityId) },
        select: auditLogSelect,
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
      }),
      this.prisma.auditLog.count({
        where: { entityType, entityId: BigInt(entityId) },
      }),
    ]);

    return {
      items: await this.enrich(items),
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  // ---------------------------------------------------------------------------
  // Enrichment
  //
  // Resolves entity ids → human-readable labels in one batch per entity type
  // (no N+1) and tacks `entityLabel`, `summary`, and `actionLabel` onto every
  // row before it leaves the API. The admin Audit Log screen consumes those
  // three fields directly — old/new JSON stays in place for forensics.
  // ---------------------------------------------------------------------------
  private async enrich(items: RawAuditLogItem[]): Promise<EnrichedAuditLogItem[]> {
    if (items.length === 0) return [];

    // Bucket entity ids by type so we can fan out one query per bucket.
    const buckets: Record<string, Set<bigint>> = {
      trailer: new Set(),
      step: new Set(),
      qc_inspection: new Set(),
      delivery: new Set(),
      delivery_batch: new Set(),
      department: new Set(),
      user: new Set(),
      announcement: new Set(),
    };

    for (const it of items) {
      const id = BigInt(it.entityId);
      switch (it.entityType) {
        case 'trailer':
        case 'production_trailer':
          buckets.trailer.add(id);
          break;
        case 'step':
        case 'production_step':
          buckets.step.add(id);
          break;
        case 'qc_inspection':
          buckets.qc_inspection.add(id);
          break;
        case 'delivery':
          buckets.delivery.add(id);
          break;
        case 'delivery_batch':
          buckets.delivery_batch.add(id);
          break;
        case 'department':
          buckets.department.add(BigInt(it.entityId));
          break;
        case 'user':
          buckets.user.add(id);
          break;
        case 'announcement':
        case 'admin_announcement':
          buckets.announcement.add(id);
          break;
      }
    }

    // Batch-load every referenced entity.
    const [trailers, steps, qcs, deliveries, batches, depts, users, announcements] =
      await Promise.all([
        buckets.trailer.size
          ? this.prisma.trailer.findMany({
              where: { id: { in: [...buckets.trailer] } },
              select: { id: true, soNumber: true },
            })
          : Promise.resolve([]),
        buckets.step.size
          ? this.prisma.productionStep.findMany({
              where: { id: { in: [...buckets.step] } },
              select: {
                id: true,
                trailer: { select: { soNumber: true } },
                department: { select: { code: true } },
              },
            })
          : Promise.resolve([]),
        buckets.qc_inspection.size
          ? this.prisma.qcInspection.findMany({
              where: { id: { in: [...buckets.qc_inspection] } },
              select: {
                id: true,
                trailer: { select: { soNumber: true } },
                productionStep: {
                  select: { department: { select: { code: true } } },
                },
              },
            })
          : Promise.resolve([]),
        buckets.delivery.size
          ? this.prisma.delivery.findMany({
              where: { id: { in: [...buckets.delivery] } },
              select: {
                id: true,
                deliveryType: true,
                trailer: { select: { soNumber: true } },
                destinationLocation: { select: { code: true } },
              },
            })
          : Promise.resolve([]),
        buckets.delivery_batch.size
          ? this.prisma.deliveryBatch.findMany({
              where: { id: { in: [...buckets.delivery_batch] } },
              select: { id: true, batchNumber: true },
            })
          : Promise.resolve([]),
        // Departments use INT ids; cast on the way in.
        buckets.department.size
          ? this.prisma.department.findMany({
              where: {
                id: { in: [...buckets.department].map((b) => Number(b)) },
              },
              select: { id: true, code: true, displayName: true },
            })
          : Promise.resolve([]),
        buckets.user.size
          ? this.prisma.user.findMany({
              where: { id: { in: [...buckets.user] } },
              select: { id: true, fullName: true, email: true },
            })
          : Promise.resolve([]),
        buckets.announcement.size
          ? this.prisma.systemAnnouncement.findMany({
              where: { id: { in: [...buckets.announcement] } },
              select: { id: true, title: true },
            })
          : Promise.resolve([]),
      ]);

    const trailerSo = new Map(trailers.map((t) => [t.id.toString(), t.soNumber]));
    const stepDesc = new Map(
      steps.map((s) => [
        s.id.toString(),
        { so: s.trailer.soNumber, dept: s.department.code },
      ]),
    );
    const qcDesc = new Map(
      qcs.map((q) => [
        q.id.toString(),
        {
          so: q.trailer.soNumber,
          dept: q.productionStep.department.code,
        },
      ]),
    );
    const deliveryDesc = new Map(
      deliveries.map((d) => [
        d.id.toString(),
        {
          so: d.trailer.soNumber,
          type: d.deliveryType as string,
          dest: d.destinationLocation?.code ?? null,
        },
      ]),
    );
    const batchNumber = new Map(
      batches.map((b) => [b.id.toString(), b.batchNumber]),
    );
    const deptDesc = new Map(
      depts.map((d) => [
        d.id.toString(),
        { code: d.code, name: d.displayName },
      ]),
    );
    const userDesc = new Map(
      users.map((u) => [
        u.id.toString(),
        { name: u.fullName, email: u.email ?? '' },
      ]),
    );
    const announcementTitle = new Map<string, string>(
      announcements.map((a) => [a.id.toString(), a.title ?? '(untitled)']),
    );

    return items.map((it) => {
      const idKey = it.entityId.toString();
      const entityLabel = buildEntityLabel(it, {
        trailerSo,
        stepDesc,
        qcDesc,
        deliveryDesc,
        batchNumber,
        deptDesc,
        userDesc,
        announcementTitle,
      }, idKey);
      // One shared humanizer for the admin log AND the trailer history, so a
      // change reads the same wherever you look at it. `changes` carries the
      // full field-by-field diff the UI can expand.
      const actionLabel = humanAction(it.action);
      const changes = diffFields(it.oldValues, it.newValues);
      const summary = summarize(
        it.action,
        it.entityType,
        it.oldValues,
        it.newValues,
        changes,
      );
      return { ...it, entityLabel, summary, actionLabel, changes };
    });
  }
}

// ---------------------------------------------------------------------------
// Pure helpers — kept outside the class so they're trivially testable and
// don't get tangled with Prisma's dependency injection lifecycle.
// ---------------------------------------------------------------------------

type LookupBundle = {
  trailerSo: Map<string, string>;
  stepDesc: Map<string, { so: string; dept: string }>;
  qcDesc: Map<string, { so: string; dept: string }>;
  deliveryDesc: Map<string, { so: string; type: string; dest: string | null }>;
  batchNumber: Map<string, string>;
  deptDesc: Map<string, { code: string; name: string }>;
  userDesc: Map<string, { name: string; email: string }>;
  announcementTitle: Map<string, string>;
};

function buildEntityLabel(
  it: { entityType: string; entityId: bigint },
  L: LookupBundle,
  idKey: string,
): string {
  switch (it.entityType) {
    case 'trailer':
    case 'production_trailer': {
      const so = L.trailerSo.get(idKey);
      return so ? `SO ${so}` : `Trailer #${idKey}`;
    }
    case 'step':
    case 'production_step': {
      const d = L.stepDesc.get(idKey);
      return d ? `SO ${d.so} — ${d.dept}` : `Step #${idKey}`;
    }
    case 'qc_inspection': {
      const d = L.qcDesc.get(idKey);
      return d ? `SO ${d.so} — ${d.dept} QC` : `QC inspection #${idKey}`;
    }
    case 'delivery': {
      const d = L.deliveryDesc.get(idKey);
      if (!d) return `Delivery #${idKey}`;
      const dest = d.dest ?? 'customer';
      return `SO ${d.so} — ${d.type} → ${dest}`;
    }
    case 'delivery_batch': {
      const n = L.batchNumber.get(idKey);
      return n ? `Batch ${n}` : `Batch #${idKey}`;
    }
    case 'department': {
      const d = L.deptDesc.get(idKey);
      return d ? `Dept ${d.code}` : `Department #${idKey}`;
    }
    case 'user': {
      const u = L.userDesc.get(idKey);
      return u ? `User ${u.name}` : `User #${idKey}`;
    }
    case 'announcement':
    case 'admin_announcement': {
      const title = L.announcementTitle.get(idKey);
      return title ? `Announcement "${title}"` : `Announcement #${idKey}`;
    }
    case 'notification':
      return `Notification #${idKey}`;
    case 'dollar_rate':
      return `Pay rate #${idKey}`;
    default:
      return `${it.entityType} #${idKey}`;
  }
}



