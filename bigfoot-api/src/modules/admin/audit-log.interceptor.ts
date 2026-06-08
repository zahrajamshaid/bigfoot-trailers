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

@Injectable()
export class AuditLogInterceptor implements NestInterceptor {
  private readonly logger = new Logger(AuditLogInterceptor.name);

  constructor(private readonly auditLogService: AuditLogService) {}

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

    return next.handle().pipe(
      tap({
        next: (responseBody: unknown) => {
          // Fire-and-forget — don't block the response
          const rawNewValues =
            responseBody && typeof responseBody === 'object'
              ? (responseBody as Record<string, unknown>)
              : null;

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

          // Temporary diagnostic — surfaces the interceptor's view of the
          // request so a recurring "audit log empty" issue can be debugged
          // from container logs without redeploying.
          this.logger.debug(
            `audit-log trace: path=${request.path} method=${method} entityType=${entityType} entityId=${entityId ?? 'null'} resolvedEntityId=${resolvedEntityId ?? 'null'} responseKeys=${rawNewValues ? Object.keys(rawNewValues).join(',') : 'null'}`,
          );

          if (!resolvedEntityId) {
            this.logger.warn(
              `audit-log: no entity id for ${method} ${request.path} (type=${entityType}) — response keys: ${rawNewValues ? Object.keys(rawNewValues).join(',') : 'null'}`,
            );
            return;
          }

          // Sanitise BigInts (and nested objects' BigInts) before handing
          // to Prisma. Without this the Json column write throws a
          // TypeError on inspectionId / trailerId fields, which the
          // catch below would silently swallow.
          const newValues = rawNewValues
            ? (sanitiseForJson(rawNewValues) as Prisma.InputJsonValue)
            : null;

          this.auditLogService
            .create({
              userId: user?.sub ?? null,
              entityType,
              entityId: resolvedEntityId,
              action,
              oldValues: null, // Interceptor doesn't have pre-update state
              newValues,
              ipAddress,
            })
            .catch((err) => {
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
