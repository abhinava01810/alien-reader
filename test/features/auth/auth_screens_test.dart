import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alien_reader_app/core/services/auth_service_cloud.dart';
import 'package:alien_reader_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:alien_reader_app/features/auth/presentation/login_screen.dart';
import 'package:alien_reader_app/features/auth/presentation/register_screen.dart';

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

  testWidgets('register success returns to login with a verify message', (
    tester,
  ) async {
    final cloud = FakeCloud(
      (r) =>
          r.url.path == '/auth/register' ? jsonResponse(userJson(), 201) : null,
    );
    await _pump(tester, LoginScreen(auth: cloud.auth, onLoggedIn: (_) {}));

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.enterText(find.byType(TextField).at(1), 'alice@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'longenough');
    await tester.enterText(find.byType(TextField).at(3), 'longenough');
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(
      find.text('Check your email to verify your account.'),
      findsOneWidget,
    );
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
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
