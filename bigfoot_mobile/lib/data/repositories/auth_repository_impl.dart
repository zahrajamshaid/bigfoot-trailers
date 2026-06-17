import 'dart:convert';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/token_refresher.dart';
import '../../core/storage/secure_storage.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/user.dart';

class AuthRepositoryImpl implements AuthRepository {
  final DioClient _api;
  final SecureStorage _storage;
  final TokenRefresher _refresher;

  AuthRepositoryImpl({
    required DioClient api,
    required SecureStorage storage,
    required TokenRefresher refresher,
  })  : _api = api,
        _storage = storage,
        _refresher = refresher;

  @override
  Future<AuthResult> login(String email, String password) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.login,
      data: {'email': email, 'password': password},
      fromJson: (d) => d as Map<String, dynamic>,
    );

    final data = response.data!;
    final accessToken = data['accessToken'] as String;
    final refreshToken = data['refreshToken'] as String;

    await _storage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );

    final user = _decodeUserFromToken(accessToken);
    return AuthResult(user: user, accessToken: accessToken, refreshToken: refreshToken);
  }

  @override
  Future<AuthResult> refreshTokens(String refreshToken) async {
    // Delegate to the shared single-flight refresher (it reads the current
    // refresh token from storage itself and persists the rotated pair) so the
    // proactive timer and the 401 interceptor never refresh concurrently. The
    // [refreshToken] argument is intentionally unused for that reason.
    final tokens = await _refresher.refresh();

    final user = _decodeUserFromToken(tokens.accessToken);
    return AuthResult(
      user: user,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
  }

  @override
  Future<void> logout(String refreshToken) async {
    await _api.post(
      ApiEndpoints.logout,
      data: {'refreshToken': refreshToken},
    );
    await _storage.clearTokens();
  }

  @override
  Future<void> registerPushToken(String token) async {
    await _api.patch<Map<String, dynamic>>(
      ApiEndpoints.authPushToken,
      data: {'pushToken': token},
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }

  User _decodeUserFromToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return const User(id: 0, email: '', name: '', role: 'worker');
    }

    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final map = json.decode(decoded) as Map<String, dynamic>;

    int? asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    List<int> asIntList(dynamic v) {
      if (v is List) {
        return v.map(asInt).whereType<int>().toList(growable: false);
      }
      return const <int>[];
    }

    return User(
      id: asInt(map['sub']) ?? 0,
      email: map['email'] as String? ?? '',
      name: (map['name'] ?? map['fullName'] ?? '').toString(),
      role: map['role'] as String? ?? 'worker',
      departmentId: asInt(map['departmentId'] ?? map['department_id']),
      extraDepartmentIds:
          asIntList(map['extraDepartmentIds'] ?? map['extra_department_ids']),
      locationId: asInt(map['locationId'] ?? map['location_id']),
    );
  }
}
