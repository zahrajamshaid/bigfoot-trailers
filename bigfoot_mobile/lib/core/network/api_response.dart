import 'api_exception.dart';

/// Parses the standard API response envelope:
/// `{ success: bool, data: T, error: { code, message, details }, meta: { ... } }`
class ApiResponse<T> {
  final bool success;
  final T? data;
  final Map<String, dynamic>? meta;

  const ApiResponse({required this.success, this.data, this.meta});

  /// Parses a raw JSON map into an ApiResponse.
  /// [fromJson] converts the `data` field to T.
  /// Throws [ApiException] when `success` is false.
  factory ApiResponse.fromJson(
    Map<String, dynamic> json, {
    T Function(dynamic)? fromJson,
    int? statusCode,
  }) {
    final success = json['success'] as bool? ?? false;

    if (!success) {
      final error = json['error'] as Map<String, dynamic>? ?? {};
      throw ApiException.fromResponse(error, statusCode);
    }

    return ApiResponse(
      success: true,
      data: fromJson != null ? fromJson(json['data']) : json['data'] as T?,
      meta: json['meta'] as Map<String, dynamic>?,
    );
  }
}

/// Pagination metadata returned by list endpoints.
class PaginationMeta {
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  const PaginationMeta({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic> json) {
    return PaginationMeta(
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 25,
      total: json['total'] as int? ?? 0,
      totalPages: json['totalPages'] as int? ?? 1,
    );
  }

  bool get hasNextPage => page < totalPages;
}
