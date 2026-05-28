import 'package:bigfoot_mobile/core/security/pin_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backs flutter_secure_storage's MethodChannel with an in-memory map so
/// PinStorage can be exercised in unit tests without the platform plugin.
void _installFakeSecureStorage(Map<String, String> store) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall call) async {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final key = args?['key'] as String?;
      switch (call.method) {
        case 'read':
          return store[key!];
        case 'write':
          store[key!] = args!['value'] as String;
          return null;
        case 'delete':
          store.remove(key);
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
        case 'containsKey':
          return store.containsKey(key);
        default:
          return null;
      }
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> store;
  late PinStorage pinStorage;

  setUp(() {
    store = <String, String>{};
    _installFakeSecureStorage(store);
    pinStorage = PinStorage();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  group('PinStorage.isEnabled', () {
    test('returns false on a fresh install', () async {
      expect(await pinStorage.isEnabled(), isFalse);
    });

    test('flips to true once a PIN is set', () async {
      await pinStorage.setPin('1234');
      expect(await pinStorage.isEnabled(), isTrue);
    });

    test('flips back to false after disable', () async {
      await pinStorage.setPin('1234');
      await pinStorage.disable();
      expect(await pinStorage.isEnabled(), isFalse);
    });
  });

  group('PinStorage.verify', () {
    test('returns false when no PIN has ever been set', () async {
      expect(await pinStorage.verify('1234'), isFalse);
    });

    test('returns true for the matching PIN', () async {
      await pinStorage.setPin('4827');
      expect(await pinStorage.verify('4827'), isTrue);
    });

    test('returns false for a wrong PIN', () async {
      await pinStorage.setPin('4827');
      expect(await pinStorage.verify('1234'), isFalse);
    });

    test('returns false after disable wipes the hash', () async {
      await pinStorage.setPin('4827');
      await pinStorage.disable();
      // Even with the correct PIN the user can't sneak past — the hash
      // is gone, so we can't compare. This is the security-critical
      // property the lock screen's "Sign out" escape relies on.
      expect(await pinStorage.verify('4827'), isFalse);
    });

    test('setting a new PIN replaces the old one cleanly', () async {
      await pinStorage.setPin('1111');
      await pinStorage.setPin('9999');
      expect(await pinStorage.verify('1111'), isFalse);
      expect(await pinStorage.verify('9999'), isTrue);
    });
  });

  group('PinStorage hashing', () {
    test('stores a hash, not the raw PIN', () async {
      await pinStorage.setPin('1234');
      expect(store.values.any((v) => v == '1234'), isFalse,
          reason: 'raw PIN must never be persisted');
    });

    test('uses a fresh salt for each setPin call', () async {
      await pinStorage.setPin('1234');
      final firstHash = store['pin_lock_hash'];
      final firstSalt = store['pin_lock_salt'];
      // setPin twice with the same PIN should produce different stored
      // hashes thanks to fresh salts — this is what makes a stolen
      // database of hashes resistant to a rainbow over "1234".
      await pinStorage.setPin('1234');
      expect(store['pin_lock_salt'], isNot(equals(firstSalt)));
      expect(store['pin_lock_hash'], isNot(equals(firstHash)));
      // Both verifications must still pass against the latest salt+hash.
      expect(await pinStorage.verify('1234'), isTrue);
    });
  });
}
