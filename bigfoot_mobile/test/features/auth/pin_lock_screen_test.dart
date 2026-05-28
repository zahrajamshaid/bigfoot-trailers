import 'package:bigfoot_mobile/core/security/pin_storage.dart';
import 'package:bigfoot_mobile/features/auth/view/pin_lock_screen.dart';
import 'package:bigfoot_mobile/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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
        default:
          return null;
      }
    },
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: child,
  );
}

Future<void> _tapDigits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.text(digit).first);
    await tester.pump();
  }
  // Allow the async _verifyPin to settle.
  await tester.pumpAndSettle();
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

  testWidgets('renders title + subtitle from localizations',
      (tester) async {
    await tester.pumpWidget(_wrap(
      PinLockScreen(
        pinStorage: pinStorage,
        onSuccess: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Enter PIN'), findsOneWidget);
    expect(find.text('Enter your 4-digit PIN to unlock'), findsOneWidget);
  });

  testWidgets('correct PIN triggers onSuccess', (tester) async {
    await pinStorage.setPin('1234');
    var unlocked = false;

    await tester.pumpWidget(_wrap(
      PinLockScreen(
        pinStorage: pinStorage,
        onSuccess: () => unlocked = true,
      ),
    ));
    await tester.pumpAndSettle();

    await _tapDigits(tester, '1234');

    expect(unlocked, isTrue);
  });

  testWidgets('wrong PIN shows incorrect message and clears entry',
      (tester) async {
    await pinStorage.setPin('1234');
    var unlocked = false;

    await tester.pumpWidget(_wrap(
      PinLockScreen(
        pinStorage: pinStorage,
        onSuccess: () => unlocked = true,
      ),
    ));
    await tester.pumpAndSettle();

    await _tapDigits(tester, '9999');

    expect(unlocked, isFalse);
    expect(find.text('Incorrect PIN'), findsOneWidget);
    // After a failure the user must be able to try again with a fresh 4
    // digits — i.e. dots are reset. We verify that by entering the correct
    // PIN next and seeing onSuccess.
    await _tapDigits(tester, '1234');
    expect(unlocked, isTrue);
  });

  testWidgets('verify never accepts a 4-digit PIN when none is set',
      (tester) async {
    // Guarantee no PIN has been stored.
    var unlocked = false;

    await tester.pumpWidget(_wrap(
      PinLockScreen(
        pinStorage: pinStorage,
        onSuccess: () => unlocked = true,
      ),
    ));
    await tester.pumpAndSettle();

    await _tapDigits(tester, '0000');

    // The fresh-install state must NOT let "0000" through; the previous
    // stub screen did, which is the bug this test guards against.
    expect(unlocked, isFalse);
    expect(find.text('Incorrect PIN'), findsOneWidget);
  });

  testWidgets('backspace removes the last entered digit', (tester) async {
    await pinStorage.setPin('1234');
    var unlocked = false;

    await tester.pumpWidget(_wrap(
      PinLockScreen(
        pinStorage: pinStorage,
        onSuccess: () => unlocked = true,
      ),
    ));
    await tester.pumpAndSettle();

    // Enter wrong three digits, backspace one, then finish with the right
    // PIN — exercises both the backspace path and "did not auto-verify
    // until 4 digits" behavior.
    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('9'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.tap(find.text('3'));
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();

    expect(unlocked, isTrue);
  });

  testWidgets('sign-out button fires onSignOut and is hidden without it',
      (tester) async {
    var signedOut = false;
    await tester.pumpWidget(_wrap(
      PinLockScreen(
        pinStorage: pinStorage,
        onSuccess: () {},
        onSignOut: () => signedOut = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sign out instead'), findsOneWidget);
    await tester.tap(find.text('Sign out instead'));
    await tester.pump();
    expect(signedOut, isTrue);

    // Without the callback, the link should not render — login screens
    // that don't yet have an auth viewmodel handy can omit it.
    await tester.pumpWidget(_wrap(
      PinLockScreen(
        pinStorage: pinStorage,
        onSuccess: () {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Sign out instead'), findsNothing);
  });

  testWidgets('numpad fits a narrow 320x568 viewport without overflow',
      (tester) async {
    // iPhone SE 1st-gen logical size — the narrowest mainstream phone.
    // The screen scrolls, so the test simply asserts the build doesn't
    // throw a RenderFlex overflow.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(
      PinLockScreen(
        pinStorage: pinStorage,
        onSuccess: () {},
        onSignOut: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Confirm at least one numpad button rendered.
    expect(find.text('5'), findsOneWidget);
  });
}
