/// Typed error codes matching the backend ErrorCode enum.
enum ErrorCode {
  stepNotActive('STEP_NOT_ACTIVE'),
  stepAlreadyComplete('STEP_ALREADY_COMPLETE'),
  reworkPointsMustBeZero('REWORK_POINTS_MUST_BE_ZERO'),
  qcPhotoRequired('QC_PHOTO_REQUIRED'),
  qcChecklistIncomplete('QC_CHECKLIST_INCOMPLETE'),
  qcInvalidReworkTarget('QC_INVALID_REWORK_TARGET'),
  qcReworkTargetRequired('QC_REWORK_TARGET_REQUIRED'),
  qcOnlyInspector('QC_ONLY_INSPECTOR'),
  customerLocked('CUSTOMER_LOCKED'),
  payrollWeekLocked('PAYROLL_WEEK_LOCKED'),
  invalidWeekStart('INVALID_WEEK_START'),
  deliveryNotDispatchable('DELIVERY_NOT_DISPATCHABLE'),
  batchNotBuilding('BATCH_NOT_BUILDING'),
  locationReceiptWrongLocation('LOCATION_RECEIPT_WRONG_LOCATION'),
  presignInvalidFileType('PRESIGN_INVALID_FILE_TYPE'),
  badRequest('BAD_REQUEST'),
  unauthorized('UNAUTHORIZED'),
  forbidden('FORBIDDEN'),
  stepReversalNotAuthorized('STEP_REVERSAL_NOT_AUTHORIZED'),
  notFound('NOT_FOUND'),
  soNumberExists('SO_NUMBER_EXISTS'),
  tooManyRequests('TOO_MANY_REQUESTS'),
  internalError('INTERNAL_ERROR');

  const ErrorCode(this.value);
  final String value;

  static ErrorCode? fromString(String? code) {
    if (code == null) return null;
    for (final e in values) {
      if (e.value == code) return e;
    }
    return null;
  }
}

/// User-friendly display messages per error code.
const Map<ErrorCode, String> errorMessages = {
  ErrorCode.stepNotActive: 'This step is not ready for completion yet',
  ErrorCode.stepAlreadyComplete: 'This step has already been completed',
  ErrorCode.reworkPointsMustBeZero: 'Rework steps cannot award points',
  ErrorCode.qcPhotoRequired: 'At least one photo is required',
  ErrorCode.qcChecklistIncomplete: 'Answer all checklist items before submitting',
  ErrorCode.qcInvalidReworkTarget: 'This department is not in the trailer\'s workflow',
  ErrorCode.qcReworkTargetRequired: 'Please select a department for rework',
  ErrorCode.qcOnlyInspector: 'Only QC inspectors can submit inspections',
  ErrorCode.customerLocked: 'Cannot change customer after invoicing',
  ErrorCode.payrollWeekLocked: 'This week\'s payroll has already been locked',
  ErrorCode.invalidWeekStart: 'Please select a Sunday as the week start',
  ErrorCode.deliveryNotDispatchable: 'This trailer is not ready for delivery',
  ErrorCode.batchNotBuilding: 'Cannot modify a batch that is not being built',
  ErrorCode.locationReceiptWrongLocation: 'Your location doesn\'t match the delivery destination',
  ErrorCode.presignInvalidFileType: 'This file type is not allowed',
  ErrorCode.badRequest: 'Invalid request',
  ErrorCode.unauthorized: 'Please sign in again',
  ErrorCode.forbidden: 'You don\'t have permission for this action',
  ErrorCode.stepReversalNotAuthorized: 'Only the completing worker or a manager can reverse this step',
  ErrorCode.notFound: 'The requested item was not found',
  ErrorCode.soNumberExists: 'A trailer with this SO number already exists',
  ErrorCode.tooManyRequests: 'Too many attempts. Please wait a minute.',
  ErrorCode.internalError: 'Something went wrong. Please try again.',
};

/// Exception thrown when the API returns success=false.
class ApiException implements Exception {
  final ErrorCode? code;
  final String message;
  final int? statusCode;
  final dynamic details;

  const ApiException({
    this.code,
    required this.message,
    this.statusCode,
    this.details,
  });

  /// Builds from the API error envelope.
  factory ApiException.fromResponse(Map<String, dynamic> error, int? status) {
    final code = ErrorCode.fromString(error['code'] as String?);
    final serverMessage = error['message'] as String?;
    return ApiException(
      code: code,
      message: serverMessage ??
          (code != null ? errorMessages[code]! : 'An unknown error occurred'),
      statusCode: status,
      details: error['details'],
    );
  }

  /// User-facing display message.
  String get displayMessage {
    if (code != null && errorMessages.containsKey(code)) {
      return errorMessages[code]!;
    }
    return message;
  }

  @override
  String toString() => 'ApiException(code: ${code?.value}, message: $message)';
}

/// Exception for network/connectivity failures.
class NetworkException implements Exception {
  final String message;
  const NetworkException(this.message);

  @override
  String toString() => 'NetworkException($message)';
}
