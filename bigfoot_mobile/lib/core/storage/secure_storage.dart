import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/platform_support.dart';

/// Token persistence.
///
/// On mobile this is backed solely by `flutter_secure_storage` (OS keystore /
/// keychain). On **desktop** `flutter_secure_storage_windows` has proven
/// unreliable across app restarts — writes can silently fail to persist, or a
/// post-restart read returns null — which logged users out on every launch and
/// stripped the auth header off write requests (e.g. updating a trailer).
///
/// To make desktop sessions durable we additionally mirror the tokens into
/// `shared_preferences`, which is a plain file in the app-support directory and
/// persists reliably on Windows/macOS/Linux. Reads prefer secure storage and
/// fall back to the mirror; writes go to both. The mirror is desktop-only so we
/// never drop plaintext tokens into prefs on a shared phone. Web keeps using
/// prefs directly (no secure storage implementation there).
class SecureStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  /// Desktop builds mirror tokens into shared_preferences for durability.
  final bool _useMirror = PlatformSupport.isDesktop;

  SecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  // ── Access token ───────────────────────────────────────────────────────
  Future<String?> getAccessToken() => _read(_accessTokenKey);

  Future<void> setAccessToken(String token) => _write(_accessTokenKey, token);

  // ── Refresh token ──────────────────────────────────────────────────────
  Future<String?> getRefreshToken() => _read(_refreshTokenKey);

  Future<void> setRefreshToken(String token) =>
      _write(_refreshTokenKey, token);

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
    } catch (e) {
      _log('clearTokens (secure storage)', e);
    }

    if (_useMirror) {
      final prefs = await _prefs();
      await Future.wait([
        prefs.remove(_accessTokenKey),
        prefs.remove(_refreshTokenKey),
      ]);
    }
  }

  Future<bool> hasTokens() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // ── Internals ────────────────────────────────────────────────────────────

  Future<String?> _read(String key) async {
    if (kIsWeb) {
      final prefs = await _prefs();
      return prefs.getString(key);
    }

    String? value;
    try {
      value = await _storage.read(key: key);
    } catch (e) {
      _log('read "$key" (secure storage)', e);
      value = null;
    }

    if (value != null && value.isNotEmpty) return value;

    // Secure storage came back empty — on desktop fall back to the durable
    // mirror, which survives the cases where the Windows backend silently
    // dropped the value.
    if (_useMirror) {
      final prefs = await _prefs();
      final mirrored = prefs.getString(key);
      if (mirrored != null && mirrored.isNotEmpty) {
        // Re-seed secure storage so it can serve future reads if/when it
        // starts behaving again. Best-effort.
        try {
          await _storage.write(key: key, value: mirrored);
        } catch (_) {}
        return mirrored;
      }
    }

    return value;
  }

  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await _prefs();
      await prefs.setString(key, value);
      return;
    }

    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      _log('write "$key" (secure storage)', e);
    }

    if (_useMirror) {
      final prefs = await _prefs();
      await prefs.setString(key, value);
    }
  }

  void _log(String op, Object error) {
    if (kDebugMode) {
      debugPrint('SecureStorage: $op failed: $error');
    }
  }
}
