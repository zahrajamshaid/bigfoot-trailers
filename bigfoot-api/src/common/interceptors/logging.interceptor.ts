import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
  Logger,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap, catchError } from 'rxjs/operators';
import { Request, Response } from 'express';
import { throwError } from 'rxjs';

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('HTTP');

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<Request>();
    const response = context.switchToHttp().getResponse<Response>();
    const { method, url } = request;
    const start = Date.now();

    return next.handle().pipe(
      tap(() => {
        const duration = Date.now() - start;
        const status = response.statusCode;
        const userId =
          (request as Request & { user?: { sub?: string | number } }).user?.sub ?? 'anon';
        this.logger.log(`${method} ${url} ${status} ${duration}ms user=${userId}`);
      }),
      catchError((err) => {
        const duration = Date.now() - start;
        const userId =
          (request as Request & { user?: { sub?: string | number } }).user?.sub ?? 'anon';
        this.logger.error(
          `${method} ${url} ERR ${duration}ms user=${userId} — ${(err as Error)?.message}`,
        );
        return throwError(() => err);
      }),
    );
  }
}
