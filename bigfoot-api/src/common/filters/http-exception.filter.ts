import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { Prisma } from '@prisma/client';
import { ErrorCode } from '../errors/error-codes';

interface ErrorResponseBody {
  success: false;
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
  meta: {
    timestamp: string;
    path: string;
    method: string;
  };
}

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const { status, code, message, details } = this.resolve(exception);

    // Log server errors with full stack; client errors at warn level
    if (status >= 500) {
      this.logger.error(
        `${request.method} ${request.url} → ${status} ${code}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    } else if (status >= 400) {
      this.logger.warn(
        `${request.method} ${request.url} → ${status} ${code}: ${message}`,
      );
    }

    const body: ErrorResponseBody = {
      success: false,
      error: {
        code,
        message,
        ...(details !== undefined && { details }),
      },
      meta: {
        timestamp: new Date().toISOString(),
        path: request.url,
        method: request.method,
      },
    };

    response.status(status).json(body);
  }

  // ── Resolver ────────────────────────────────────────────────────────────

  private resolve(exception: unknown): {
    status: number;
    code: string;
    message: string;
    details?: unknown;
  } {
    // ── NestJS HttpException (includes AppError which extends HttpException) ──
    if (exception instanceof HttpException) {
      return this.resolveHttpException(exception);
    }

    // ── Prisma known request errors (constraint violations, etc.) ─────────
    if (exception instanceof Prisma.PrismaClientKnownRequestError) {
      return this.resolvePrismaError(exception);
    }

    // ── Prisma validation errors (invalid query shape) ────────────────────
    if (exception instanceof Prisma.PrismaClientValidationError) {
      this.logger.error('Prisma validation error', exception.message);
      return {
        status: 400,
        code: ErrorCode.INTERNAL_ERROR,
        message: 'Invalid database query',
      };
    }

    // ── Generic Error ─────────────────────────────────────────────────────
    if (exception instanceof Error) {
      this.logger.error(`Unhandled exception: ${exception.message}`, exception.stack);
      return {
        status: 500,
        code: ErrorCode.INTERNAL_ERROR,
        message: 'An unexpected error occurred',
      };
    }

    // ── Unknown throw type ────────────────────────────────────────────────
    this.logger.error('Unknown exception type', String(exception));
    return {
      status: 500,
      code: ErrorCode.INTERNAL_ERROR,
      message: 'An unexpected error occurred',
    };
  }

  private resolveHttpException(exception: HttpException) {
    const status = exception.getStatus();
    const exceptionResponse = exception.getResponse();

    let code: string = this.statusToCode(status);
    let message: string = exception.message;
    let details: unknown = undefined;

    if (typeof exceptionResponse === 'string') {
      message = exceptionResponse;
    } else if (typeof exceptionResponse === 'object' && exceptionResponse !== null) {
      const resp = exceptionResponse as Record<string, unknown>;
      code = (resp['code'] as string) || code;
      message = (resp['message'] as string) || message;
      details = resp['details'] || resp['errors'];

      // class-validator returns message as string[] — normalize
      if (Array.isArray(resp['message'])) {
        message = 'Validation failed';
        details = resp['message'];
      }
    }

    return { status, code, message, details };
  }

  private resolvePrismaError(exception: Prisma.PrismaClientKnownRequestError) {
    switch (exception.code) {
      // Unique constraint violation
      case 'P2002': {
        const target = (exception.meta as Record<string, unknown>)?.['target'];
        return {
          status: 409,
          code: ErrorCode.SO_NUMBER_EXISTS,
          message: `Unique constraint violation on ${Array.isArray(target) ? target.join(', ') : 'field'}`,
        };
      }
      // Foreign key constraint violation
      case 'P2003':
        return {
          status: 400,
          code: 'FOREIGN_KEY_VIOLATION',
          message: 'Referenced record does not exist',
        };
      // Record not found
      case 'P2025':
        return {
          status: 404,
          code: ErrorCode.NOT_FOUND,
          message: 'The requested record was not found',
        };
      default:
        this.logger.error(`Prisma error ${exception.code}`, exception.message);
        return {
          status: 500,
          code: ErrorCode.INTERNAL_ERROR,
          message: 'A database error occurred',
        };
    }
  }

  private statusToCode(status: number): string {
    const map: Record<number, string> = {
      400: 'BAD_REQUEST',
      401: ErrorCode.UNAUTHORIZED,
      403: ErrorCode.FORBIDDEN,
      404: ErrorCode.NOT_FOUND,
      409: 'CONFLICT',
      422: 'UNPROCESSABLE_ENTITY',
      429: ErrorCode.TOO_MANY_REQUESTS,
      500: ErrorCode.INTERNAL_ERROR,
    };
    return map[status] || 'UNKNOWN_ERROR';
  }
}
