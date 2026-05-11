import 'dart:async';
import 'dart:ui' show VoidCallback;
import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';
import '../constants/api_endpoints.dart';

/// Dio interceptor that:
/// 1. Attaches JWT Bearer token to every request.
/// 2. On 401, tries to refresh tokens and retries the original request.
/// 3. If refresh also fails, clears tokens and invokes [onAuthExpired].
class AuthInterceptor extends QueuedInterceptor {
  final SecureStorage _storage;
  final Dio _dio; // Separate Dio instance for refresh (avoid interceptor loop)
  final VoidCallback? onAuthExpired;

  bool _isRefreshing = false;
  final _pendingRequests = <({Completer<Response> completer, RequestOptions options})>[];

  AuthInterceptor({
    required SecureStorage storage,
    required String baseUrl,
    this.onAuthExpired,
  })  : _storage = storage,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          contentType: 'application/json',
        ));

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuth'] == true) {
      handler.next(options);
      return;
    }

    final token = await _storage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.requestOptions.extra['skipAuth'] == true) {
      return handler.next(err);
    }

    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Don't retry auth endpoints — let login/refresh errors surface directly
    final path = err.requestOptions.path;
    if (path == ApiEndpoints.refresh ||
        path == ApiEndpoints.login ||
        path == ApiEndpoints.logout) {
      if (path == ApiEndpoints.refresh) {
        await _storage.clearTokens();
        onAuthExpired?.call();
      }
      return handler.next(err);
    }

    if (_isRefreshing) {
      // Queue this request until refresh completes
      final completer = Completer<Response>();
      _pendingRequests.add((completer: completer, options: err.requestOptions));
      try {
        final response = await completer.future;
        return handler.resolve(response);
      } catch (e) {
        return handler.next(err);
      }
    }

    _isRefreshing = true;

    try {
      final refreshToken = await _storage.getRefreshToken();
      if (refreshToken == null) {
        await _storage.clearTokens();
        onAuthExpired?.call();
        return handler.next(err);
      }

      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.refresh,
        data: {'refreshToken': refreshToken},
      );

      final data = response.data?['data'] as Map<String, dynamic>?;
      final newAccess = data?['accessToken'] as String?;
      final newRefresh = data?['refreshToken'] as String?;

      if (newAccess == null || newRefresh == null) {
        throw Exception('Invalid refresh response');
      }

      await _storage.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );

      // Retry original request
      err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
      final retryResponse = await _dio.fetch(err.requestOptions);
      handler.resolve(retryResponse);

      // Resolve all queued requests
      for (final pending in _pendingRequests) {
        pending.options.headers['Authorization'] = 'Bearer $newAccess';
        _dio.fetch(pending.options).then(
          pending.completer.complete,
          onError: pending.completer.completeError,
        );
      }
    } catch (_) {
      await _storage.clearTokens();
      onAuthExpired?.call();

      // Reject all queued requests
      for (final pending in _pendingRequests) {
        pending.completer.completeError(err);
      }

      handler.next(err);
    } finally {
      _isRefreshing = false;
      _pendingRequests.clear();
    }
  }
}
