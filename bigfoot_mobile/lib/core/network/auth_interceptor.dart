import 'dart:ui' show VoidCallback;
import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';
import '../constants/api_endpoints.dart';
import 'token_refresher.dart';

/// Dio interceptor that:
/// 1. Attaches the JWT Bearer token to every request.
/// 2. On 401, refreshes tokens (via the shared [TokenRefresher]) and retries the
///    original request.
/// 3. If the refresh fails, clears tokens and invokes [onAuthExpired].
///
/// All refreshes go through [TokenRefresher], whose single-flight lock is shared
/// with the proactive timer in `AuthViewModel`. That coordination is what
/// prevents two concurrent refreshes from replaying a rotated token and tripping
/// the backend's "reuse → terminate all sessions" protection.
class AuthInterceptor extends QueuedInterceptor {
  final SecureStorage _storage;
  final TokenRefresher _refresher;
  final Dio _retryDio; // interceptor-free Dio for replaying the original request
  final VoidCallback? onAuthExpired;

  AuthInterceptor({
    required SecureStorage storage,
    required TokenRefresher refresher,
    required String baseUrl,
    this.onAuthExpired,
  })  : _storage = storage,
        _refresher = refresher,
        _retryDio = Dio(BaseOptions(
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

    // Don't retry auth endpoints — let login/refresh/logout errors surface.
    final path = err.requestOptions.path;
    if (path == ApiEndpoints.refresh ||
        path == ApiEndpoints.login ||
        path == ApiEndpoints.logout) {
      return handler.next(err);
    }

    try {
      final tokens = await _refresher.refresh();
      err.requestOptions.headers['Authorization'] =
          'Bearer ${tokens.accessToken}';
      final retryResponse = await _retryDio.fetch(err.requestOptions);
      handler.resolve(retryResponse);
    } catch (_) {
      await _storage.clearTokens();
      onAuthExpired?.call();
      handler.next(err);
    }
  }
}
