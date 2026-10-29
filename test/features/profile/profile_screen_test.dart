import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/core/constants/app_strings.dart';
import 'package:alien_reader_app/features/auth/data/services/auth_service.dart';
import 'package:alien_reader_app/features/device/data/models/saved_device.dart';
import 'package:alien_reader_app/features/device/data/services/device_storage_service.dart';
import 'package:alien_reader_app/features/device/domain/reader_device.dart';
import 'package:alien_reader_app/features/profile/presentation/profile_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, {VoidCallback? onSignOut}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await AuthService().register(
      username: 'alice',
      password: 'password123',
      email: 'alice@example.com',
    );
    await DeviceStorageService().saveDevice(
      SavedDevice(
        deviceId: 'NAADH-000123',
        setupStatus: DeviceSetupStatus.configured,
        createdAt: DateTime(2026),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileScreen(
            status: ReaderConnectionStatus.connected,
            onSignOut: onSignOut,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows name, email, devices, account actions and version', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('My Devices'), findsOneWidget);
    expect(find.text('NAADH-000123'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Delete account'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Naadh v${AppStrings.appVersion}'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
  });

  testWidgets('delete account with correct password signs out', (tester) async {
    var signedOut = false;
    await pump(tester, onSignOut: () => signedOut = true);

    await tester.scrollUntilVisible(
      find.text('Delete account'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'wrong-pass');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Current password is incorrect.'), findsOneWidget);
    expect(signedOut, isFalse);

    await tester.enterText(find.byType(TextField), 'password123');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
    expect(await AuthService().findUser('alice'), isNull);
  });

  testWidgets(
    'sections appear in order: Devices, Appearance, Usage, Account, version',
    (tester) async {
      await pump(tester);

      final titles = [
        'My Devices',
        'Appearance',
        'Usage & Storage',
        'Account',
        'Naadh v${AppStrings.appVersion}',
      ];
      final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: titles[i]);
      }
      expect(find.text('Log out'), findsOneWidget);
    },
  );

  testWidgets('change password dialog has three fields', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();

    expect(find.text('Current password'), findsOneWidget);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm new password'), findsOneWidget);
  });
}
