import { HttpException } from '@nestjs/common';
import {
  ErrorCode,
  ERROR_HTTP_STATUS,
  ERROR_DEFAULT_MESSAGE,
} from './error-codes';

/**
 * Typed application error — throw from any service.
 *
 * Usage:
 *   throw new AppError(ErrorCode.STEP_NOT_ACTIVE);
 *   throw new AppError(ErrorCode.SO_NUMBER_EXISTS, 'SO-1234 already taken');
 *   throw new AppError(ErrorCode.QC_CHECKLIST_INCOMPLETE, undefined, { missing: [3, 7] });
 */
export class AppError extends HttpException {
  public readonly errorCode: ErrorCode;

  constructor(
    code: ErrorCode,
    message?: string,
    details?: unknown,
  ) {
    const status = ERROR_HTTP_STATUS[code];
    const body: Record<string, unknown> = {
      code,
      message: message ?? ERROR_DEFAULT_MESSAGE[code],
    };
    if (details !== undefined) {
      body['details'] = details;
    }
    super(body, status);
    this.errorCode = code;
  }
}
