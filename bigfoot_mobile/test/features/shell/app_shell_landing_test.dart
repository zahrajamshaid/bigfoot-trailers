import 'package:flutter_test/flutter_test.dart';

import 'package:bigfoot_mobile/data/models/user.dart';
import 'package:bigfoot_mobile/features/shell/view/app_shell.dart';

/// Where each role lands after logging in.
///
/// The bug this pins: every role was dropped on `/dashboard`, but `/dashboard`
/// is not a nav tab for a worker or a driver. A welder logging in landed on the
/// points-heavy dashboard instead of the queue they came to work from.
///
/// The rule is now: **you land on your own first tab**, so the screen you get is
/// always the tab that's highlighted. If someone reorders `_tabsForRole` without
/// updating `landingPathForRole`, this test fails.
void main() {
  group('AppShell.landingPathForRole', () {
    test('a worker lands on their QUEUE, not the points screen', () {
      expect(AppShell.landingPathForRole(UserRole.worker), '/production');
    });

    test('a driver lands on their deliveries', () {
      expect(AppShell.landingPathForRole(UserRole.driver), '/deliveries');
    });

    test('roles whose first tab IS the dashboard still land there', () {
      for (final role in [
        UserRole.owner,
        UserRole.productionManager,
        UserRole.transportManager,
        UserRole.qcInspector,
        UserRole.office,
        UserRole.sales,
        UserRole.purchasing,
        UserRole.parts,
      ]) {
        expect(
          AppShell.landingPathForRole(role),
          '/dashboard',
          reason: '$role\'s first tab is the dashboard',
        );
      }
    });

    test('an unknown role degrades to the dashboard rather than crashing', () {
      expect(AppShell.landingPathForRole('something_new'), '/dashboard');
    });

    test('no role ever lands on the payroll/points screen', () {
      for (final role in [
        UserRole.owner,
        UserRole.productionManager,
        UserRole.transportManager,
        UserRole.qcInspector,
        UserRole.worker,
        UserRole.driver,
        UserRole.office,
        UserRole.sales,
        UserRole.purchasing,
        UserRole.parts,
      ]) {
        expect(AppShell.landingPathForRole(role), isNot('/payroll'));
      }
    });
  });
}
