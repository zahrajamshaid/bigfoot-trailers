import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
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
      items,
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
      items,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }
}
