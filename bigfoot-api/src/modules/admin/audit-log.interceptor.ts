import {
  Injectable,
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
  const clean = path
    .split('?')[0]
    .replace(/^\/api\//, '/')
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

@Injectable()
export class AuditLogInterceptor implements NestInterceptor {
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
          const newValues =
            responseBody && typeof responseBody === 'object'
              ? (responseBody as Record<string, unknown>)
              : null;

          // For CREATE, the entity ID comes from the response
          let resolvedEntityId = entityId;
          if (action === 'CREATE' && !resolvedEntityId && newValues?.id != null) {
            resolvedEntityId = BigInt(newValues.id as string | number | bigint);
          }

          if (!resolvedEntityId) return; // Can't log without an entity ID

          this.auditLogService
            .create({
              userId: user?.sub ?? null,
              entityType,
              entityId: resolvedEntityId,
              action,
              oldValues: null, // Interceptor doesn't have pre-update state
              newValues: newValues as Prisma.InputJsonValue | null,
              ipAddress,
            })
            .catch(() => {
              // Silently ignore audit log failures — never block business logic
            });
        },
      }),
    );
  }
}
