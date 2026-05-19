import { Injectable, NestMiddleware, Logger } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';

/**
 * HTTP request logger — logs method, path, status, duration, user_id.
 *
 * Applied as NestJS middleware (runs before guards/interceptors) so it
 * captures the true response status including error responses.
 */
@Injectable()
export class RequestLoggerMiddleware implements NestMiddleware {
  private readonly logger = new Logger('HTTP');

  use(req: Request, res: Response, next: NextFunction): void {
    const start = Date.now();
    const { method, originalUrl } = req;

    res.on('finish', () => {
      const duration = Date.now() - start;
      const status = res.statusCode;
      const userId =
        (req as Request & { user?: { sub?: string | number } }).user?.sub ?? 'anon';

      const logLine = `${method} ${originalUrl} ${status} ${duration}ms user=${userId}`;

      if (status >= 500) {
        this.logger.error(logLine);
      } else if (status >= 400) {
        this.logger.warn(logLine);
      } else {
        this.logger.log(logLine);
      }
    });

    next();
  }
}
