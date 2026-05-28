import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's app-open PIN. The PIN itself is never stored — only a
/// salted SHA-256 hash, kept in flutter_secure_storage (Keychain on iOS,
/// EncryptedSharedPreferences on Android). The "enabled" flag lives in the
/// same secure store so wiping one wipes the other.
class PinStorage {
  static const _enabledKey = 'pin_lock_enabled';
  static const _hashKey = 'pin_lock_hash';
  static const _saltKey = 'pin_lock_salt';

  final FlutterSecureStorage _storage;

  PinStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<bool> isEnabled() async {
    final raw = await _read(_enabledKey);
    return raw == 'true';
  }

  /// Stores a hashed PIN and flips the enabled flag on. Caller is responsible
  /// for collecting + confirming the PIN before calling this.
  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hash(pin, salt);
    await Future.wait([
      _write(_saltKey, salt),
      _write(_hashKey, hash),
      _write(_enabledKey, 'true'),
    ]);
  }

  /// Returns true if the supplied PIN matches what's on file.
  Future<bool> verify(String pin) async {
    final salt = await _read(_saltKey);
    final expected = await _read(_hashKey);
    if (salt == null || expected == null) return false;
    return _hash(pin, salt) == expected;
  }

  /// Disables PIN lock and wipes the stored hash + salt.
  Future<void> disable() async {
    await Future.wait([
      _write(_enabledKey, 'false'),
      _delete(_hashKey),
      _delete(_saltKey),
    ]);
  }

  // ── Internals ────────────────────────────────────────────────────────────

  String _hash(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  String _generateSalt() {
    // 16 bytes from the current micros + identityHashCode jitter. Not a CSPRNG,
    // but the PIN space is only 10,000 anyway — the salt is here to stop a
    // device-wide rainbow of "1234" hashes, not to resist a determined attacker
    // who already has Keychain access.
    final t = DateTime.now().microsecondsSinceEpoch;
    final j = identityHashCode(Object());
    return sha256.convert(utf8.encode('$t:$j')).toString().substring(0, 32);
  }

  Future<String?> _read(String key) async {
    if (kIsWeb) {
      final prefs = await _prefs();
      return prefs.getString(key);
    }
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await _prefs();
      await prefs.setString(key, value);
      return;
    }
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  Future<void> _delete(String key) async {
    if (kIsWeb) {
      final prefs = await _prefs();
      await prefs.remove(key);
      return;
    }
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}
