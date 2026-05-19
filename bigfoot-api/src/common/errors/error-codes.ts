/**
 * Typed error codes from API Spec v1.3 Section 14.
 *
 * Each entry maps to a fixed HTTP status code so services throw
 * `new AppError(ErrorCode.STEP_NOT_ACTIVE)` and the exception filter
 * resolves the status automatically.
 */

export enum ErrorCode {
  // ── 400 Bad Request ──────────────────────────────────────────────────────
  STEP_NOT_ACTIVE = 'STEP_NOT_ACTIVE',
  STEP_ALREADY_COMPLETE = 'STEP_ALREADY_COMPLETE',
  REWORK_POINTS_MUST_BE_ZERO = 'REWORK_POINTS_MUST_BE_ZERO',
  QC_PHOTO_REQUIRED = 'QC_PHOTO_REQUIRED',
  QC_CHECKLIST_INCOMPLETE = 'QC_CHECKLIST_INCOMPLETE',
  QC_INVALID_REWORK_TARGET = 'QC_INVALID_REWORK_TARGET',
  QC_REWORK_TARGET_REQUIRED = 'QC_REWORK_TARGET_REQUIRED',
  QC_ONLY_INSPECTOR = 'QC_ONLY_INSPECTOR',
  CUSTOMER_LOCKED = 'CUSTOMER_LOCKED',
  PAYROLL_WEEK_LOCKED = 'PAYROLL_WEEK_LOCKED',
  INVALID_WEEK_START = 'INVALID_WEEK_START',
  DELIVERY_NOT_DISPATCHABLE = 'DELIVERY_NOT_DISPATCHABLE',
  BATCH_NOT_BUILDING = 'BATCH_NOT_BUILDING',
  LOCATION_RECEIPT_WRONG_LOCATION = 'LOCATION_RECEIPT_WRONG_LOCATION',
  PRESIGN_INVALID_FILE_TYPE = 'PRESIGN_INVALID_FILE_TYPE',
  BAD_REQUEST = 'BAD_REQUEST',

  // ── 401 Unauthorized ────────────────────────────────────────────────────
  UNAUTHORIZED = 'UNAUTHORIZED',

  // ── 403 Forbidden ────────────────────────────────────────────────────────
  FORBIDDEN = 'FORBIDDEN',
  STEP_REVERSAL_NOT_AUTHORIZED = 'STEP_REVERSAL_NOT_AUTHORIZED',

  // ── 404 Not Found ────────────────────────────────────────────────────────
  NOT_FOUND = 'NOT_FOUND',

  // ── 409 Conflict ─────────────────────────────────────────────────────────
  SO_NUMBER_EXISTS = 'SO_NUMBER_EXISTS',

  // ── 429 Too Many Requests ────────────────────────────────────────────────
  TOO_MANY_REQUESTS = 'TOO_MANY_REQUESTS',

  // ── 500 Internal ─────────────────────────────────────────────────────────
  INTERNAL_ERROR = 'INTERNAL_ERROR',
}

/** Maps each ErrorCode to its canonical HTTP status. */
export const ERROR_HTTP_STATUS: Record<ErrorCode, number> = {
  // 400
  [ErrorCode.STEP_NOT_ACTIVE]: 400,
  [ErrorCode.STEP_ALREADY_COMPLETE]: 400,
  [ErrorCode.REWORK_POINTS_MUST_BE_ZERO]: 400,
  [ErrorCode.QC_PHOTO_REQUIRED]: 400,
  [ErrorCode.QC_CHECKLIST_INCOMPLETE]: 400,
  [ErrorCode.QC_INVALID_REWORK_TARGET]: 400,
  [ErrorCode.QC_REWORK_TARGET_REQUIRED]: 400,
  [ErrorCode.QC_ONLY_INSPECTOR]: 400,
  [ErrorCode.CUSTOMER_LOCKED]: 400,
  [ErrorCode.PAYROLL_WEEK_LOCKED]: 400,
  [ErrorCode.INVALID_WEEK_START]: 400,
  [ErrorCode.DELIVERY_NOT_DISPATCHABLE]: 400,
  [ErrorCode.BATCH_NOT_BUILDING]: 400,
  [ErrorCode.LOCATION_RECEIPT_WRONG_LOCATION]: 400,
  [ErrorCode.PRESIGN_INVALID_FILE_TYPE]: 400,
  [ErrorCode.BAD_REQUEST]: 400,
  // 401
  [ErrorCode.UNAUTHORIZED]: 401,
  // 403
  [ErrorCode.FORBIDDEN]: 403,
  [ErrorCode.STEP_REVERSAL_NOT_AUTHORIZED]: 403,
  // 404
  [ErrorCode.NOT_FOUND]: 404,
  // 409
  [ErrorCode.SO_NUMBER_EXISTS]: 409,
  // 429
  [ErrorCode.TOO_MANY_REQUESTS]: 429,
  // 500
  [ErrorCode.INTERNAL_ERROR]: 500,
};

/** Human-readable default messages per error code. */
export const ERROR_DEFAULT_MESSAGE: Record<ErrorCode, string> = {
  [ErrorCode.STEP_NOT_ACTIVE]: 'Cannot complete a step that is not currently active',
  [ErrorCode.STEP_ALREADY_COMPLETE]: 'Step has already been marked complete',
  [ErrorCode.REWORK_POINTS_MUST_BE_ZERO]: 'Rework steps cannot award points',
  [ErrorCode.QC_PHOTO_REQUIRED]: 'At least one photo is required per QC inspection',
  [ErrorCode.QC_CHECKLIST_INCOMPLETE]:
    'All checklist items must be answered before submission',
  [ErrorCode.QC_INVALID_REWORK_TARGET]:
    "The rework target department is not in this trailer's workflow",
  [ErrorCode.QC_REWORK_TARGET_REQUIRED]:
    'A rework target department must be selected when the QC result is a fail',
  [ErrorCode.QC_ONLY_INSPECTOR]:
    'Only a QC inspector or production manager can submit QC inspections',
  [ErrorCode.CUSTOMER_LOCKED]:
    'Cannot change customer after QuickBooks invoice has been created',
  [ErrorCode.PAYROLL_WEEK_LOCKED]: 'Payroll for this week has already been locked',
  [ErrorCode.INVALID_WEEK_START]: 'The week start date must be a Sunday',
  [ErrorCode.DELIVERY_NOT_DISPATCHABLE]: 'Trailer is not in ready_for_delivery status',
  [ErrorCode.BATCH_NOT_BUILDING]: 'Cannot modify a batch that is not in building status',
  [ErrorCode.LOCATION_RECEIPT_WRONG_LOCATION]:
    "Receiving user's location does not match delivery destination",
  [ErrorCode.PRESIGN_INVALID_FILE_TYPE]:
    'The requested file type is not a permitted upload category',
  [ErrorCode.BAD_REQUEST]: 'Invalid request',
  [ErrorCode.UNAUTHORIZED]: 'Authentication required',
  [ErrorCode.FORBIDDEN]: 'You do not have permission to perform this action',
  [ErrorCode.STEP_REVERSAL_NOT_AUTHORIZED]:
    'Only the completing worker or a production manager can reverse a step',
  [ErrorCode.NOT_FOUND]: 'The requested resource was not found',
  [ErrorCode.SO_NUMBER_EXISTS]: 'A trailer with this SO number already exists',
  [ErrorCode.TOO_MANY_REQUESTS]: 'Too many requests — please try again later',
  [ErrorCode.INTERNAL_ERROR]: 'An unexpected error occurred',
};
