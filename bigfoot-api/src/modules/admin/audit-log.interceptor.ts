import {
  Injectable,
  Logger,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable, tap } from 'rxjs';
import { Request } from 'express';
import { Prisma } from '@prisma/client';
import { AuditLogService } from './audit-log.service';
import { PrismaService } from '../../prisma/prisma.service';
import { JwtPayload } from '../../common/decorators/current-user.decorator';

/**
 * Maps HTTP methods to audit actions.
 * Only POST, PATCH, PUT, DELETE are logged — GET is read-only.
 */
const METHOD_ACTION_MAP: Record<string, string> = {
  POST: 'CREATE',
  PATCH: 'UPDATE',
  PUT: 'UPDATE',
  DELETE: 'DELETE',
};

/**
 * Singularises a plural URL segment heuristically. Handles the three plural
 * shapes we use:
 *   • -ies   → -y         (deliveries → delivery, factories → factory)
 *   • -ses   → unchanged  (statuses, passes — keep the -es)
 *   • -ches / -shes / -xes / -zes → strip "es" (batches → batch)
 *   • -s     → strip "s"  (trailers → trailer, users → user)
 *
 * Returns the word unchanged if no rule applies (e.g. "qc", "info").
 */
function singularise(word: string): string {
  if (word.endsWith('ies')) return word.slice(0, -3) + 'y';
  if (word.endsWith('ses')) return word;
  if (
    word.endsWith('ches') ||
    word.endsWith('shes') ||
    word.endsWith('xes') ||
    word.endsWith('zes')
  ) {
    return word.slice(0, -2);
  }
  if (word.endsWith('s') && !word.endsWith('ss')) {
    return word.slice(0, -1);
  }
  return word;
}

/**
 * Extracts entity type and entity ID from the request path.
 *
 * The parser walks segments until it hits the first numeric ID; everything
 * before that ID is the resource path. Multi-segment resources concatenate
 * with underscores so the entity type matches the database column the
 * mobile filter dropdown queries by. Hyphens become underscores throughout.
 *
 * Examples:
 *   /trailers/123                       → { entityType: 'trailer',           entityId: 123n }
 *   /trailers/123/qb-pdf                → { entityType: 'trailer',           entityId: 123n }
 *   /qc/inspections                     → { entityType: 'qc_inspection',     entityId: null }
 *   /qc/inspections/45                  → { entityType: 'qc_inspection',     entityId: 45n  }
 *   /qc/inspections/45/send-customer-sms→ { entityType: 'qc_inspection',     entityId: 45n  }
 *   /qc/checklist-items                 → { entityType: 'qc_checklist_item', entityId: null }
 *   /deliveries/batches/10/depart       → { entityType: 'delivery_batch',    entityId: 10n  }
 *   /deliveries/10                      → { entityType: 'delivery',          entityId: 10n  }
 *   /users/5/reactivate                 → { entityType: 'user',              entityId: 5n   }
 */
function parseEntityFromPath(path: string): {
  entityType: string;
  entityId: bigint | null;
} {
  // Strip the global `/v1`, `/v2`, … API prefix (set in main.ts via
  // setGlobalPrefix) as well as any `/api/` mount, otherwise every
  // entityType ends up prefixed with `v1_` (e.g. `v1_qc_inspection`)
  // and the mobile dropdown filters never match.
  const clean = path
    .split('?')[0]
    .replace(/^\/api\//, '/')
    .replace(/^\/v\d+(?:\/|$)/, '/')
    .replace(/^\//, '');
  const segments = clean.split('/').filter(Boolean);

  const resourceSegments: string[] = [];
  let entityId: bigint | null = null;
  for (const seg of segments) {
    const num = Number(seg);
    if (!Number.isNaN(num) && Number.isInteger(num) && resourceSegments.length > 0) {
      entityId = BigInt(num);
      // Everything after the numeric ID is an action verb (e.g. "depart",
      // "send-customer-sms") and shouldn't shape the entity type.
      break;
    }
    resourceSegments.push(seg);
  }

  const entityType = resourceSegments
    .map((seg) => singularise(seg).replace(/-/g, '_'))
    .join('_') || 'unknown';

  return { entityType, entityId };
}

/**
 * Recursively converts BigInts to strings so the result is JSON-safe.
 * The Postgres `Json` column type Prisma writes to can't carry BigInts —
 * we lose absolute precision in the very rare 53-bit overflow case, but
 * the IDs were never meant to round-trip from the audit log anyway.
 * Returns the same value for non-BigInt primitives and recurses through
 * plain objects + arrays. Dates serialise as ISO strings via JSON
 * defaults; that's already the desired shape.
 */
function sanitiseForJson(value: unknown): unknown {
  if (typeof value === 'bigint') return value.toString();
  if (Array.isArray(value)) return value.map(sanitiseForJson);
  if (value !== null && typeof value === 'object' && !(value instanceof Date)) {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = sanitiseForJson(v);
    }
    return out;
  }
  return value;
}

/**
 * Coerces something that might be a string / number / bigint into a
 * BigInt, or null when it isn't a parseable integer. We use this for the
 * various id-shaped keys responses might carry (`id`, `inspectionId`,
 * `deliveryId`, `batchId`, …) — different controllers return different
 * conventions and we don't want one stylistic choice to silently drop
 * the audit log row.
 */
function tryParseBigInt(value: unknown): bigint | null {
  if (value == null) return null;
  if (typeof value === 'bigint') return value;
  if (typeof value === 'number' && Number.isInteger(value)) return BigInt(value);
  if (typeof value === 'string' && /^\d+$/.test(value)) return BigInt(value);
  return null;
}

/**
 * Entity types we can snapshot before a write, so an UPDATE records what the
 * row looked like BEFORE as well as after. Without a `before` every update
 * logged the whole entity as if it had been set from nothing — which is why
 * the history read as a wall of meaningless "Updated" rows.
 *
 * A bare findUnique (no `include`) returns scalar columns only, so relation
 * objects never leak into the diff.
 */
const SNAPSHOTTABLE: Record<string, string> = {
  trailer: 'trailer',
  delivery: 'delivery',
  delivery_batch: 'deliveryBatch',
  user: 'user',
  department: 'department',
  customer: 'customer',
  sales_order: 'salesOrder',
};

@Injectable()
export class AuditLogInterceptor implements NestInterceptor {
  private readonly logger = new Logger(AuditLogInterceptor.name);

  constructor(
    private readonly auditLogService: AuditLogService,
    private readonly prisma: PrismaService,
  ) {}

  /** Scalar snapshot of a row, or null if we can't take one. */
  private async snapshot(
    entityType: string,
    entityId: bigint | null,
  ): Promise<Record<string, unknown> | null> {
    const model = SNAPSHOTTABLE[entityType];
    if (!model || !entityId) return null;
    try {
      const delegate = (
        this.prisma as unknown as Record<
          string,
          { findUnique: (a: unknown) => Promise<Record<string, unknown> | null> }
        >
      )[model];
      if (!delegate?.findUnique) return null;
      return await delegate.findUnique({ where: { id: entityId } });
    } catch {
      // Auditing must never break the request it is observing.
      return null;
    }
  }

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<Request>();
    const method = request.method;

    const action = METHOD_ACTION_MAP[method];
    if (!action) {
      // GET, OPTIONS, HEAD — skip
      return next.handle();
    }

    const user = request.user as JwtPayload | undefined;
    const { entityType, entityId } = parseEntityFromPath(request.path);
    const ipAddress =
      (request.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ??
      request.ip ??
      null;

    // Snapshot BEFORE the handler runs. Kicked off now, awaited in the tap —
    // it must not add latency to the response path.
    const beforePromise: Promise<Record<string, unknown> | null> =
      action === 'UPDATE' || action === 'DELETE'
        ? this.snapshot(entityType, entityId)
        : Promise.resolve(null);

    return next.handle().pipe(
      tap({
        next: (responseBody: unknown) => {
          // Fire-and-forget — don't block the response
          let rawNewValues =
            responseBody && typeof responseBody === 'object'
              ? (responseBody as Record<string, unknown>)
              : null;

          // The global ResponseEnvelopeInterceptor (registered in main.ts via
          // useGlobalInterceptors) wraps every response in
          // { success, data, meta } before this APP_INTERCEPTOR sees it on
          // the way out. Unwrap so the rest of the logic looks at the
          // controller's actual payload, where the `id` / `*Id` keys live.
          if (
            rawNewValues &&
            'success' in rawNewValues &&
            'data' in rawNewValues &&
            'meta' in rawNewValues &&
            rawNewValues.data &&
            typeof rawNewValues.data === 'object'
          ) {
            rawNewValues = rawNewValues.data as Record<string, unknown>;
          }

          // For CREATE, the entity ID isn't in the path — it comes from
          // the response. Different controllers use different conventions
          // (`id`, `inspectionId`, `deliveryId`, …), so try the plain `id`
          // first and then fall back to any key shaped like `<word>Id`.
          let resolvedEntityId = entityId;
          if (action === 'CREATE' && !resolvedEntityId && rawNewValues) {
            resolvedEntityId =
              tryParseBigInt(rawNewValues['id']) ??
              tryParseBigInt(
                rawNewValues[
                  Object.keys(rawNewValues).find((k) => /Id$/.test(k)) ?? ''
                ],
              );
          }

          if (!resolvedEntityId) return; // Can't log without an entity ID

          // Resolve the before-snapshot, then take a matching AFTER snapshot so
          // the two sides are the same shape (scalar columns only). A symmetric
          // pair is what lets the humanizer report just the fields that really
          // changed, instead of dumping the whole entity as "set from nothing".
          void (async () => {
            const before = await beforePromise;
            const after =
              before !== null
                ? await this.snapshot(entityType, resolvedEntityId)
                : null;

            // Sanitise BigInts (and nested objects' BigInts) before handing
            // to Prisma. Without this the Json column write throws a
            // TypeError on inspectionId / trailerId fields, which the
            // catch below would silently swallow.
            const oldValues = before
              ? (sanitiseForJson(before) as Prisma.InputJsonValue)
              : null;
            const newValues = after
              ? (sanitiseForJson(after) as Prisma.InputJsonValue)
              : rawNewValues
                ? (sanitiseForJson(rawNewValues) as Prisma.InputJsonValue)
                : null;

            await this.auditLogService.create({
              userId: user?.sub ?? null,
              entityType,
              entityId: resolvedEntityId,
              action,
              oldValues,
              newValues,
              ipAddress,
            });
          })().catch((err) => {
              // Never block business logic on an audit-log write — but
              // surface the failure to the app logs so a recurring miss
              // doesn't go invisible for weeks like the BigInt issue did.
              this.logger.warn(
                `audit log write failed for ${entityType}#${resolvedEntityId} ${action}: ${
                  (err as Error)?.message ?? err
                }`,
              );
            });
        },
      }),
    );
  }
}
