import 'package:dio/dio.dart';

import '../constants/api_endpoints.dart';
import '../storage/secure_storage.dart';

/// Thrown when a token refresh cannot be completed (no stored token, network
/// failure, or a malformed/401 response from the server).
class TokenRefreshFailure implements Exception {
  final String message;
  const TokenRefreshFailure(this.message);

  @override
  String toString() => 'TokenRefreshFailure: $message';
}

/// The freshly-rotated token pair returned by [TokenRefresher.refresh].
class RefreshedTokens {
  final String accessToken;
  final String refreshToken;

  const RefreshedTokens({
    required this.accessToken,
    required this.refreshToken,
  });
}

/// Single source of truth for refreshing the JWT pair.
///
/// The backend rotates refresh tokens and treats reuse of an already-rotated
/// token as a theft attempt — terminating *every* session for the user. The app
/// has two independent triggers for a refresh: the proactive timer in
/// `AuthViewModel` and the reactive 401 handler in `AuthInterceptor`. If both
/// fire at once they can present the same token twice and trip that protection,
/// logging the user out "for no reason".
///
/// Funnelling every refresh through this class fixes that: a single in-flight
/// [Future] coalesces concurrent callers so the network only ever sees one
/// rotation at a time. Sequential refreshes each read the newly-rotated token
/// from storage, so they never replay a revoked one.
///
/// Uses its own interceptor-free [Dio] so a refresh never re-enters the auth
/// interceptor (which would loop).
class TokenRefresher {
  final SecureStorage _storage;
  final Dio _dio;

  Future<RefreshedTokens>? _inFlight;

  TokenRefresher({
    required SecureStorage storage,
    required String baseUrl,
  })  : _storage = storage,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          contentType: 'application/json',
        ));

  /// Refreshes the token pair, coalescing concurrent callers into one request.
  Future<RefreshedTokens> refresh() {
    // Set synchronously (before any await) so overlapping callers share it.
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _doRefresh();
    _inFlight = future;
    // Release the slot once settled so the *next* (sequential) refresh starts
    // fresh and reads the newly-rotated token from storage.
    future.whenComplete(() => _inFlight = null);
    return future;
  }

  Future<RefreshedTokens> _doRefresh() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const TokenRefreshFailure('No refresh token stored');
    }

    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.refresh,
        data: {'refreshToken': refreshToken},
      );
    } on DioException catch (e) {
      throw TokenRefreshFailure(
        'Refresh request failed: ${e.response?.statusCode ?? e.message}',
      );
    }

    final data = response.data?['data'] as Map<String, dynamic>?;
    final newAccess = data?['accessToken'] as String?;
    final newRefresh = data?['refreshToken'] as String?;

    if (newAccess == null || newRefresh == null) {
      throw const TokenRefreshFailure('Malformed refresh response');
    }

    await _storage.saveTokens(accessToken: newAccess, refreshToken: newRefresh);
    return RefreshedTokens(accessToken: newAccess, refreshToken: newRefresh);
  }
}
