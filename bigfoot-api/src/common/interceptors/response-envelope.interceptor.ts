import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import { Request } from 'express';

export interface EnvelopedResponse<T> {
  success: true;
  data: T;
  meta: {
    timestamp: string;
    path: string;
    method: string;
  };
}

@Injectable()
export class ResponseEnvelopeInterceptor<T>
  implements NestInterceptor<T, EnvelopedResponse<T>>
{
  intercept(
    context: ExecutionContext,
    next: CallHandler<T>,
  ): Observable<EnvelopedResponse<T>> {
    const request = context.switchToHttp().getRequest<Request>();

    return next.handle().pipe(
      map((data) => ({
        success: true as const,
        data,
        meta: {
          timestamp: new Date().toISOString(),
          path: request.url,
          method: request.method,
        },
      })),
    );
  }
}
