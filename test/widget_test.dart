import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/app/app.dart';

import 'helpers/fake_cloud.dart';

Future<void> _launch(WidgetTester tester, FakeCloud cloud) async {
  await tester.pumpWidget(AlienReaderApp(cloudAuth: cloud.auth));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));

  // Let the splash fade out and its timers finish.
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('without stored tokens the app opens on login', (tester) async {
    final cloud = FakeCloud((_) => null);

    await _launch(tester, cloud);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(cloud.requests, isEmpty);
  });

  testWidgets('with stored tokens the app opens home without waiting', (
    tester,
  ) async {
    // The backend never answers in time; startup must not block on it.
    final cloud = FakeCloud((_) => null, signedIn: true);

    await _launch(tester, cloud);

    expect(find.text('Welcome back'), findsNothing);
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('an unverified account can get back to the code screen', (
    tester,
  ) async {
    var verified = false;
    final cloud = FakeCloud(
      (r) => switch (r.url.path) {
        '/auth/me' => jsonResponse({
          ...userJson(),
          'email_verified': verified,
        }),
        '/auth/verify-email/request' => jsonResponse({'ok': true}),
        '/auth/verify-email/confirm' => () {
          verified = true;
          return jsonResponse(userJson());
        }(),
        _ => null,
      },
      signedIn: true,
    );
    await _launch(tester, cloud);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Verify your email (alice@example.com) to pair a reader.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Verify now'));
    await tester.pumpAndSettle();
    expect(find.text('Check your email'), findsOneWidget);

    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();
    expect(cloud.paths, contains('POST /auth/verify-email/request'));

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.text('Check your email'), findsNothing);
    expect(find.text('Email verified.'), findsOneWidget);
    expect(find.text('Verify now'), findsNothing);
  });

  testWidgets('a verified account sees no banner', (tester) async {
    final cloud = FakeCloud(
      (r) => r.url.path == '/auth/me' ? jsonResponse(userJson()) : null,
      signedIn: true,
    );
    await _launch(tester, cloud);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Verify now'), findsNothing);
  });
}
