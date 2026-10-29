import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/core/constants/app_strings.dart';
import 'package:alien_reader_app/features/device/data/models/saved_device.dart';
import 'package:alien_reader_app/features/device/data/services/device_storage_service.dart';
import 'package:alien_reader_app/features/device/domain/reader_device.dart';
import 'package:alien_reader_app/features/profile/presentation/profile_screen.dart';

import '../../helpers/fake_cloud.dart';

/// Backend that knows one account whose password is `password123`.
FakeCloud _backend() => FakeCloud((r) {
  switch ('${r.method} ${r.url.path}') {
    case 'GET /auth/me':
      return jsonResponse(userJson(name: 'Alice Cloud'));
    case 'POST /auth/password-reset/request':
      return http.Response('', 200);
    case 'POST /auth/account/delete':
      final ok = jsonDecode(r.body)['password'] == 'password123';
      return ok
          ? http.Response('', 204)
          : jsonResponse({'detail': 'Incorrect password'}, 400);
  }
  return null;
}, signedIn: true);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FakeCloud> pump(WidgetTester tester, {VoidCallback? onSignOut}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cloud = _backend();
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
            userName: 'local-name',
            status: ReaderConnectionStatus.connected,
            cloudAuth: cloud.auth,
            onSignOut: onSignOut,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cloud;
  }

  testWidgets('shows the name and email from /auth/me', (tester) async {
    await pump(tester);

    expect(find.text('Alice Cloud'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('local-name'), findsNothing);
    expect(find.text('NAADH-000123'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('sections appear in order with the version last', (tester) async {
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
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('change password sends a reset email', (tester) async {
    final cloud = await pump(tester);

    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(find.textContaining('alice@example.com'), findsWidgets);

    await tester.tap(find.text('Send link'));
    await tester.pumpAndSettle();

    expect(cloud.paths, contains('POST /auth/password-reset/request'));
    expect(jsonDecode(cloud.requests.last.body), {
      'email': 'alice@example.com',
    });
    expect(
      find.text('Check alice@example.com for a reset link.'),
      findsOneWidget,
    );
  });

  testWidgets('delete account needs the right password, then signs out', (
    tester,
  ) async {
    var signedOut = false;
    final cloud = await pump(tester, onSignOut: () => signedOut = true);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'wrong-pass');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect password'), findsOneWidget);
    expect(signedOut, isFalse);

    await tester.enterText(find.byType(TextField), 'password123');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
    expect(cloud.tokens.values, isEmpty);
  });

  testWidgets('log out asks for confirmation first', (tester) async {
    var signedOut = false;
    await pump(tester, onSignOut: () => signedOut = true);

    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(signedOut, isFalse);

    await tester.tap(find.text('SIGN OUT'));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
  });
}
