import 'package:dio/dio.dart';
import 'api_exception.dart';
import 'api_response.dart';

/// Configured Dio HTTP client for the Bigfoot API.
class DioClient {
  late final Dio dio;

  DioClient({
    String baseUrl = 'http://10.0.2.2:3000/v1', // Android emulator → host
    List<Interceptor> interceptors = const [],
  }) {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
        responseType: ResponseType.json,
      ),
    );

    dio.interceptors.addAll(interceptors);
  }

  // ── GET ────────────────────────────────────────────────────────────────
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
      );
      return ApiResponse.fromJson(
        response.data!,
        fromJson: fromJson,
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ── POST ───────────────────────────────────────────────────────────────
  Future<ApiResponse<T>> post<T>(
    String path, {
    dynamic data,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        path,
        data: data,
      );
      return ApiResponse.fromJson(
        response.data!,
        fromJson: fromJson,
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ── PATCH ──────────────────────────────────────────────────────────────
  Future<ApiResponse<T>> patch<T>(
    String path, {
    dynamic data,
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await dio.patch<Map<String, dynamic>>(
        path,
        data: data,
      );
      return ApiResponse.fromJson(
        response.data!,
        fromJson: fromJson,
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ── DELETE ─────────────────────────────────────────────────────────────
  Future<ApiResponse<T>> delete<T>(
    String path, {
    T Function(dynamic)? fromJson,
  }) async {
    try {
      final response = await dio.delete<Map<String, dynamic>>(path);
      return ApiResponse.fromJson(
        response.data!,
        fromJson: fromJson,
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  // ── Error mapping ──────────────────────────────────────────────────────
  Exception _handleDioError(DioException e) {
    if (e.response?.data is Map<String, dynamic>) {
      return ApiException.fromResponse(
        (e.response!.data as Map<String, dynamic>)['error']
                as Map<String, dynamic>? ??
            e.response!.data as Map<String, dynamic>,
        e.response?.statusCode,
      );
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkException('Request timed out. Please try again.');
      case DioExceptionType.connectionError:
        return const NetworkException(
            'Unable to reach the server. Check your connection.');
      default:
        return NetworkException(e.message ?? 'An unexpected error occurred');
    }
  }
}
