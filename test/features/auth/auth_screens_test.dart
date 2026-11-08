import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alien_reader_app/core/services/auth_service_cloud.dart';
import 'package:alien_reader_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:alien_reader_app/features/auth/presentation/login_screen.dart';
import 'package:alien_reader_app/features/auth/presentation/register_screen.dart';
import 'package:alien_reader_app/features/auth/presentation/verify_email_screen.dart';

import '../../helpers/fake_cloud.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
}

void main() {
  testWidgets('login shows the API error message', (tester) async {
    final cloud = FakeCloud(
      (r) => jsonResponse({'detail': 'Incorrect email or password'}, 401),
    );
    await _pump(tester, LoginScreen(auth: cloud.auth, onLoggedIn: (_) {}));

    await tester.enterText(find.byType(TextField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextField).at(1), 'nope');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect email or password'), findsOneWidget);
  });

  testWidgets('login success hands the user to the app', (tester) async {
    CloudUser? loggedIn;
    final cloud = FakeCloud((r) {
      if (r.url.path == '/auth/login') return jsonResponse(tokenJson('1'));
      if (r.url.path == '/auth/me') return jsonResponse(userJson());
      return null;
    });
    await _pump(
      tester,
      LoginScreen(auth: cloud.auth, onLoggedIn: (u) => loggedIn = u),
    );

    await tester.enterText(find.byType(TextField).at(0), 'alice@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password1');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(loggedIn?.name, 'Alice');
  });

  testWidgets('login password field toggles visibility', (tester) async {
    await _pump(
      tester,
      LoginScreen(auth: FakeCloud((_) => null).auth, onLoggedIn: (_) {}),
    );
    EditableText password() =>
        tester.widget<EditableText>(find.byType(EditableText).at(1));

    expect(password().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(password().obscureText, isFalse);
  });

  testWidgets('register checks length and matching passwords locally', (
    tester,
  ) async {
    final cloud = FakeCloud((_) => null);
    await _pump(tester, RegisterScreen(auth: cloud.auth));

    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.enterText(find.byType(TextField).at(1), 'alice@example.com');
    // Nine characters: one short of the backend's minimum.
    await tester.enterText(find.byType(TextField).at(2), 'ninechars');
    await tester.tap(find.text('Register'));
    await tester.pump();
    expect(
      find.text('Password must be at least 10 characters.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).at(2), 'longenough');
    await tester.enterText(find.byType(TextField).at(3), 'different1');
    await tester.tap(find.text('Register'));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(cloud.requests, isEmpty);
  });

  Future<void> registerAlice(WidgetTester tester) async {
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.enterText(find.byType(TextField).at(1), 'alice@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'longenough');
    await tester.enterText(find.byType(TextField).at(3), 'longenough');
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
  }

  testWidgets('register asks for the emailed code, then signs in', (
    tester,
  ) async {
    final cloud = FakeCloud(
      (r) => switch (r.url.path) {
        '/auth/register' => jsonResponse(userJson(), 201),
        '/auth/verify-email/confirm' => jsonResponse(userJson()),
        '/auth/login' => jsonResponse(tokenJson('1')),
        '/auth/me' => jsonResponse(userJson()),
        _ => null,
      },
    );
    CloudUser? signedIn;
    await _pump(
      tester,
      LoginScreen(auth: cloud.auth, onLoggedIn: (u) => signedIn = u),
    );
    await registerAlice(tester);

    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.text('We sent a 6-digit code to alice@example.com.'),
      findsOneWidget,
    );

    // Spaces and other characters are dropped; only 6 digits are kept.
    await tester.enterText(find.byType(TextField), '123 4567');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '123456',
    );
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    final confirm = cloud.requests.singleWhere(
      (r) => r.url.path == '/auth/verify-email/confirm',
    );
    expect(jsonDecode(confirm.body), {
      'email': 'alice@example.com',
      'otp': '123456',
    });
    expect(cloud.paths.last, 'GET /auth/me');
    expect(signedIn?.email, 'alice@example.com');
  });

  testWidgets('a short code is caught before calling the server', (
    tester,
  ) async {
    final cloud = FakeCloud((_) => null);
    await _pump(
      tester,
      VerifyEmailScreen(
        email: 'alice@example.com',
        auth: cloud.auth,
        onVerified: (_) async {},
      ),
    );
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Verify'));
    await tester.pump();
    expect(
      find.text('Enter all 6 digits of the code from your email.'),
      findsOneWidget,
    );
    expect(cloud.requests, isEmpty);
  });

  testWidgets('a wrong code is announced and the field is cleared', (
    tester,
  ) async {
    final cloud = FakeCloud(
      (r) => r.url.path == '/auth/verify-email/confirm'
          ? jsonResponse({'detail': 'That code is wrong or has expired'}, 400)
          : null,
    );
    var verified = false;
    await _pump(
      tester,
      VerifyEmailScreen(
        email: 'alice@example.com',
        auth: cloud.auth,
        onVerified: (_) async => verified = true,
      ),
    );
    await tester.enterText(find.byType(TextField), '999999');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(verified, isFalse);
    expect(find.text('That code is wrong or has expired'), findsOneWidget);
    // TalkBack reads the banner out as soon as it appears.
    expect(
      find.ancestor(
        of: find.text('That code is wrong or has expired'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    // The field does not repeat the message; the banner carries it.
    expect(find.text('Check the code and try again.'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('resend asks for a new code and says so', (tester) async {
    final cloud = FakeCloud(
      (r) => r.url.path == '/auth/verify-email/request'
          ? jsonResponse({'ok': true})
          : null,
    );
    await _pump(
      tester,
      VerifyEmailScreen(
        email: 'alice@example.com',
        auth: cloud.auth,
        onVerified: (_) async {},
      ),
    );
    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();
    final request = cloud.requests.single;
    expect(request.url.path, '/auth/verify-email/request');
    expect(jsonDecode(request.body), {'email': 'alice@example.com'});
    expect(
      find.text('A new code was sent to alice@example.com.'),
      findsOneWidget,
    );
  });

  testWidgets('leaving the code screen returns to login with the email', (
    tester,
  ) async {
    final cloud = FakeCloud(
      (r) =>
          r.url.path == '/auth/register' ? jsonResponse(userJson(), 201) : null,
    );
    await _pump(tester, LoginScreen(auth: cloud.auth, onLoggedIn: (_) {}));
    await registerAlice(tester);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(
      find.textContaining('Your email is not verified yet.'),
      findsOneWidget,
    );
  });

  testWidgets('forgot password always shows the neutral message', (
    tester,
  ) async {
    final cloud = FakeCloud(
      (r) => jsonResponse({'detail': 'No such user'}, 404),
    );
    await _pump(tester, ForgotPasswordScreen(auth: cloud.auth));

    await tester.enterText(find.byType(TextField), 'nobody@example.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(
      find.text("If an account exists, we've sent a reset link."),
      findsOneWidget,
    );
    expect(find.text('No such user'), findsNothing);
  });
}
