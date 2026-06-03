import 'dart:io' show HttpClient, SecureSocket;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'api_exception.dart';
import 'api_response.dart';

/// Configured Dio HTTP client for the Bigfoot API.
class DioClient {
  static const String _sslPinsDefine = String.fromEnvironment('SSL_PIN_SHA256');

  late final Dio dio;
  final Set<String> _validatedPinnedHosts = <String>{};
  late final Set<String> _sslPins;

  DioClient({
    String baseUrl = 'http://10.0.2.2:3000/v1', // Android emulator → host
    List<Interceptor> interceptors = const [],
  }) {
    _sslPins = _sslPinsDefine
        .split(',')
        .map((e) => e.trim().replaceAll(':', '').toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet();

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

    // dart:io HttpClient is not supported on Flutter web — touching it
    // throws UnsupportedError at runtime, which bubbles up as a non-Dio
    // exception and surfaces as "An unexpected error occurred" on login.
    // Skip the IO adapter on web and let Dio use BrowserHttpClientAdapter.
    if (!kIsWeb) {
      final adapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.maxConnectionsPerHost = 12;
          client.idleTimeout = const Duration(seconds: 20);
          client.connectionTimeout = const Duration(seconds: 20);
          return client;
        },
      );
      dio.httpClientAdapter = adapter;
    }

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            await _validatePinnedCertificate(options.uri);
            handler.next(options);
          } catch (e) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badCertificate,
                error: e,
              ),
            );
          }
        },
      ),
    );

    dio.interceptors.addAll(interceptors);
  }

  bool get _isPinningEnabled => _sslPins.isNotEmpty;

  Future<void> _validatePinnedCertificate(Uri uri) async {
    if (!_isPinningEnabled) return;
    if (uri.scheme.toLowerCase() != 'https') return;

    final host = uri.host;
    if (host.isEmpty || _validatedPinnedHosts.contains(host)) return;

    final socket = await SecureSocket.connect(
      host,
      uri.port == 0 ? 443 : uri.port,
      timeout: const Duration(seconds: 6),
    );
    try {
      final cert = socket.peerCertificate;
      if (cert == null) {
        throw const NetworkException('SSL pinning failed: certificate missing.');
      }

      final fingerprint = sha256.convert(cert.der).toString().toUpperCase();
      if (!_sslPins.contains(fingerprint)) {
        throw const NetworkException(
          'SSL pinning validation failed for this server certificate.',
        );
      }

      _validatedPinnedHosts.add(host);
    } finally {
      await socket.close();
    }
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
