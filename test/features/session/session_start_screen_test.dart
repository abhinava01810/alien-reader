import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/features/session/presentation/session_start_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionStartScreen Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders Welcome to Naadh branding and tabs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionStartScreen(onSessionStarted: (user, token) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Naadh'), findsOneWidget);
      expect(
        find.text('Alien Innovations • Smart Document Reader'),
        findsOneWidget,
      );
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('SIGN IN'), findsOneWidget);
    });

    testWidgets('shows validation error when signing in with empty fields', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionStartScreen(onSessionStarted: (user, token) {}),
        ),
      );
      await tester.pumpAndSettle();

      final signInBtn = find.text('SIGN IN');
      await tester.ensureVisible(signInBtn);
      await tester.tap(signInBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter your username.'), findsOneWidget);
    });

    testWidgets('switching to Create Account reveals registration form', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionStartScreen(onSessionStarted: (user, token) {}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Username *'), findsOneWidget);
      expect(find.text('Email Address (optional)'), findsOneWidget);
      expect(find.text('Phone Number (optional)'), findsOneWidget);
      expect(find.text('Password *'), findsOneWidget);
      expect(find.text('Confirm Password *'), findsOneWidget);
      expect(find.text('CREATE ACCOUNT'), findsOneWidget);
    });

    testWidgets('registration validates contact requirement', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionStartScreen(onSessionStarted: (user, token) {}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      // Enter only username
      await tester.enterText(
        find.widgetWithText(TextField, 'Username *'),
        'newuser',
      );

      final createBtn = find.text('CREATE ACCOUNT');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Please provide at least one contact method (email or phone) for account recovery.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('successful registration triggers onSessionStarted', (
      WidgetTester tester,
    ) async {
      String? startedUser;

      await tester.pumpWidget(
        MaterialApp(
          home: SessionStartScreen(
            onSessionStarted: (user, token) {
              startedUser = user;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Username *'),
        'validuser',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Email Address (optional)'),
        'valid@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password *'),
        'password123',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm Password *'),
        'password123',
      );

      final createBtn = find.text('CREATE ACCOUNT');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(startedUser, equals('validuser'));
    });
  });
}
