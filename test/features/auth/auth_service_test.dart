import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/features/auth/data/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService Unit Tests', () {
    late AuthService authService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      authService = AuthService();
    });

    test(
      'register succeeds with valid username, email, and password',
      () async {
        final account = await authService.register(
          username: 'alice',
          password: 'password123',
          email: 'alice@alieninnovations.com',
        );

        expect(account.username, equals('alice'));
        expect(account.email, equals('alice@alieninnovations.com'));
        expect(account.phone, isNull);
        expect(account.passwordHash, isNot(contains('password123')));
        expect(account.salt, isNotEmpty);

        final isLogged = await authService.isLoggedIn();
        expect(isLogged, isTrue);

        final currentUser = await authService.getCurrentUser();
        expect(currentUser?.username, equals('alice'));
      },
    );

    test('register succeeds with phone number instead of email', () async {
      final account = await authService.register(
        username: 'bob_user',
        password: 'securePass99',
        phone: '+1 555 123 4567',
      );

      expect(account.username, equals('bob_user'));
      expect(account.phone, equals('+1 555 123 4567'));
      expect(account.email, isNull);
    });

    test('register fails when neither email nor phone is provided', () async {
      expect(
        () => authService.register(
          username: 'no_contact',
          password: 'password123',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('register rejects duplicate username (case-insensitive)', () async {
      await authService.register(
        username: 'charlie',
        password: 'password123',
        email: 'charlie@example.com',
      );

      expect(
        () => authService.register(
          username: 'CHARLIE',
          password: 'anotherPassword',
          email: 'charlie2@example.com',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('register rejects passwords shorter than 6 characters', () async {
      expect(
        () => authService.register(
          username: 'short_pass_user',
          password: '123',
          email: 'test@example.com',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test(
      'login succeeds with correct password and fails with wrong password',
      () async {
        await authService.register(
          username: 'david',
          password: 'mySecretPassword',
          email: 'david@example.com',
        );

        // Wrong password
        expect(
          () => authService.login(username: 'david', password: 'wrongPassword'),
          throwsA(isA<AuthException>()),
        );

        // Non-existent user
        expect(
          () => authService.login(
            username: 'unknown_user',
            password: 'somePassword',
          ),
          throwsA(isA<AuthException>()),
        );

        // Correct password
        final loggedIn = await authService.login(
          username: 'david',
          password: 'mySecretPassword',
        );
        expect(loggedIn.username, equals('david'));
        expect(await authService.isLoggedIn(), isTrue);
      },
    );

    test(
      'recoverPassword resets password when contact method matches',
      () async {
        await authService.register(
          username: 'eve',
          password: 'oldPassword1',
          email: 'eve@example.com',
          phone: '1234567890',
        );

        // Mismatched contact method
        expect(
          () => authService.recoverPassword(
            username: 'eve',
            contactMethod: 'wrong@example.com',
            newPassword: 'newPassword123',
          ),
          throwsA(isA<AuthException>()),
        );

        // Valid recovery with registered email
        await authService.recoverPassword(
          username: 'eve',
          contactMethod: 'eve@example.com',
          newPassword: 'newPassword123',
        );

        // Verify login with new password succeeds
        final loggedIn = await authService.login(
          username: 'eve',
          password: 'newPassword123',
        );
        expect(loggedIn.username, equals('eve'));

        // Verify login with old password fails
        expect(
          () => authService.login(username: 'eve', password: 'oldPassword1'),
          throwsA(isA<AuthException>()),
        );
      },
    );

    test('logout clears the active session', () async {
      await authService.register(
        username: 'frank',
        password: 'password123',
        email: 'frank@example.com',
      );

      expect(await authService.isLoggedIn(), isTrue);

      await authService.logout();

      expect(await authService.isLoggedIn(), isFalse);
      expect(await authService.getCurrentUser(), isNull);
    });
  });
}
