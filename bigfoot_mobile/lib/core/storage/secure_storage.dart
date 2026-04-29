import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure token persistence using flutter_secure_storage.
class SecureStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  SecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  // ── Access token ───────────────────────────────────────────────────────
  Future<String?> getAccessToken() async {
    if (kIsWeb) {
      final prefs = await _prefs();
      return prefs.getString(_accessTokenKey);
    }
    try {
      return await _storage.read(key: _accessTokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> setAccessToken(String token) async {
    if (kIsWeb) {
      final prefs = await _prefs();
      await prefs.setString(_accessTokenKey, token);
      return;
    }
    try {
      await _storage.write(key: _accessTokenKey, value: token);
    } catch (_) {}
  }

  // ── Refresh token ──────────────────────────────────────────────────────
  Future<String?> getRefreshToken() async {
    if (kIsWeb) {
      final prefs = await _prefs();
      return prefs.getString(_refreshTokenKey);
    }
    try {
      return await _storage.read(key: _refreshTokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> setRefreshToken(String token) async {
    if (kIsWeb) {
      final prefs = await _prefs();
      await prefs.setString(_refreshTokenKey, token);
      return;
    }
    try {
      await _storage.write(key: _refreshTokenKey, value: token);
    } catch (_) {}
  }

  // ── Tokens together ────────────────────────────────────────────────────
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      setAccessToken(accessToken),
      setRefreshToken(refreshToken),
    ]);
  }

  // ── Clear ──────────────────────────────────────────────────────────────
  Future<void> clearTokens() async {
    if (kIsWeb) {
      final prefs = await _prefs();
      await Future.wait([
        prefs.remove(_accessTokenKey),
        prefs.remove(_refreshTokenKey),
      ]);
      return;
    }
    try {
      await Future.wait([
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
      ]);
    } catch (_) {}
  }

  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
