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
 * Extracts entity type and entity ID from the request path.
 * Examples:
 *   /trailers/123       → { entityType: 'trailer', entityId: 123 }
 *   /qc/inspections/45  → { entityType: 'qc_inspection', entityId: 45 }
 *   /deliveries/10/mark-complete → { entityType: 'delivery', entityId: 10 }
 */
function parseEntityFromPath(path: string): {
  entityType: string;
  entityId: bigint | null;
} {
  // Remove query string and leading /api or /
  const clean = path
    .split('?')[0]
    .replace(/^\/api\//, '/')
    .replace(/^\//, '');
  const segments = clean.split('/').filter(Boolean);

  let entityType = segments[0] ?? 'unknown';
  let entityId: bigint | null = null;

  // Walk segments to find the last numeric ID that follows a resource name
  for (let i = 0; i < segments.length; i++) {
    const num = Number(segments[i]);
    if (!Number.isNaN(num) && Number.isInteger(num) && i > 0) {
      // The segment before the number is the resource name
      entityType = segments[i - 1];
      entityId = BigInt(num);
    }
  }

  // Singularize common plural resource names
  if (entityType.endsWith('ies')) {
    entityType = entityType.slice(0, -3) + 'y'; // deliveries → delivery
  } else if (entityType.endsWith('ses')) {
    // keep as-is (e.g. "statuses")
  } else if (entityType.endsWith('s') && !entityType.endsWith('ss')) {
    entityType = entityType.slice(0, -1); // trailers → trailer
  }

  // Replace hyphens with underscores for consistency
  entityType = entityType.replace(/-/g, '_');

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
