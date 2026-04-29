import 'dart:convert';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../core/storage/secure_storage.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/user.dart';

class AuthRepositoryImpl implements AuthRepository {
  final DioClient _api;
  final SecureStorage _storage;

  AuthRepositoryImpl({required DioClient api, required SecureStorage storage})
      : _api = api,
        _storage = storage;

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
    final response = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.refresh,
      data: {'refreshToken': refreshToken},
      fromJson: (d) => d as Map<String, dynamic>,
    );

    final data = response.data!;
    final accessToken = data['accessToken'] as String;
    final newRefresh = data['refreshToken'] as String;

    await _storage.saveTokens(
      accessToken: accessToken,
      refreshToken: newRefresh,
    );

    final user = _decodeUserFromToken(accessToken);
    return AuthResult(user: user, accessToken: accessToken, refreshToken: newRefresh);
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

    return User(
      id: map['sub'] as int? ?? 0,
      email: map['email'] as String? ?? '',
      name: map['name'] as String? ?? '',
      role: map['role'] as String? ?? 'worker',
    );
  }
}
