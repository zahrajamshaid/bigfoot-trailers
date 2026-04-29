import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';

/**
 * Strip HTML tags from all string values in request body.
 * Prevents stored XSS via API inputs. Applied globally.
 */
@Injectable()
export class SanitizeMiddleware implements NestMiddleware {
  use(req: Request, _res: Response, next: NextFunction): void {
    if (req.body && typeof req.body === 'object') {
      req.body = this.sanitize(req.body);
    }
    next();
  }

  private sanitize(value: unknown): unknown {
    if (typeof value === 'string') {
      return this.stripHtml(value);
    }
    if (Array.isArray(value)) {
      return value.map((item) => this.sanitize(item));
    }
    if (value !== null && typeof value === 'object') {
      const sanitized: Record<string, unknown> = {};
      for (const [key, val] of Object.entries(value)) {
        sanitized[key] = this.sanitize(val);
      }
      return sanitized;
    }
    return value;
  }

  private stripHtml(input: string): string {
    return input.replace(/<[^>]*>/g, '');
  }
}
