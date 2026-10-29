import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_account.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  AuthService();

  static const String _usersPrefsKey = 'alien_reader_registered_users';
  static const String _activeUserPrefsKey = 'alien_reader_active_user';
  static const String _sessionUserNameKey = 'alien_reader_user_name';

  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt:$password');
    return sha256.convert(bytes).toString();
  }

  static String generateSalt([int length = 16]) {
    final random = Random.secure();
    final values = List<int>.generate(length, (_) => random.nextInt(256));
    return base64Url.encode(values);
  }

  Future<List<UserAccount>> getAllUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_usersPrefsKey);
    if (rawJson == null || rawJson.isEmpty) return [];

    try {
      final list = jsonDecode(rawJson) as List<dynamic>;
      return list
          .map((item) => UserAccount.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<UserAccount?> findUser(String username) async {
    final users = await getAllUsers();
    final normalized = username.trim().toLowerCase();
    for (final u in users) {
      if (u.username.trim().toLowerCase() == normalized) {
        return u;
      }
    }
    return null;
  }

  Future<UserAccount?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_activeUserPrefsKey);
    if (rawJson == null || rawJson.isEmpty) {
      // Check legacy session user name
      final legacyName = prefs.getString(_sessionUserNameKey);
      if (legacyName != null && legacyName.isNotEmpty) {
        return findUser(legacyName);
      }
      return null;
    }

    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      return UserAccount.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isLoggedIn() async {
    final user = await getCurrentUser();
    return user != null;
  }

  Future<UserAccount> register({
    required String username,
    required String password,
    String? email,
    String? phone,
  }) async {
    final trimmedUser = username.trim();
    if (trimmedUser.isEmpty) {
      throw const AuthException('Username is required.');
    }
    if (trimmedUser.length < 3) {
      throw const AuthException('Username must be at least 3 characters.');
    }
    final usernameRegex = RegExp(r'^[a-zA-Z0-9_\.\-]+$');
    if (!usernameRegex.hasMatch(trimmedUser)) {
      throw const AuthException(
        'Username can only contain letters, numbers, underscores, dashes, and periods.',
      );
    }

    // Check unique username
    final existing = await findUser(trimmedUser);
    if (existing != null) {
      throw const AuthException(
        'This username is already registered. Please choose another or sign in.',
      );
    }

    // Contact/recovery requirement: require at least one valid recovery method
    final trimmedEmail = email?.trim();
    final trimmedPhone = phone?.trim();

    final hasEmail = trimmedEmail != null && trimmedEmail.isNotEmpty;
    final hasPhone = trimmedPhone != null && trimmedPhone.isNotEmpty;

    if (!hasEmail && !hasPhone) {
      throw const AuthException(
        'Please provide at least one contact method (email or phone number) for account recovery.',
      );
    }

    if (hasEmail) {
      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
      if (!emailRegex.hasMatch(trimmedEmail)) {
        throw const AuthException('Please enter a valid email address.');
      }
    }

    if (hasPhone) {
      final phoneDigits = trimmedPhone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
      if (phoneDigits.length < 7) {
        throw const AuthException('Please enter a valid phone number.');
      }
    }

    if (password.length < 6) {
      throw const AuthException('Password must be at least 6 characters.');
    }

    final salt = generateSalt();
    final hash = hashPassword(password, salt);

    final account = UserAccount(
      username: trimmedUser,
      email: hasEmail ? trimmedEmail : null,
      phone: hasPhone ? trimmedPhone : null,
      passwordHash: hash,
      salt: salt,
      createdAt: DateTime.now(),
    );

    final users = await getAllUsers();
    users.add(account);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _usersPrefsKey,
      jsonEncode(users.map((u) => u.toJson()).toList()),
    );

    // Persist as current active session
    await _setActiveUser(account);

    return account;
  }

  Future<UserAccount> login({
    required String username,
    required String password,
  }) async {
    final trimmedUser = username.trim();
    if (trimmedUser.isEmpty) {
      throw const AuthException('Please enter your username.');
    }
    if (password.isEmpty) {
      throw const AuthException('Please enter your password.');
    }

    final user = await findUser(trimmedUser);
    if (user == null) {
      throw const AuthException('Invalid username or password.');
    }

    final computedHash = hashPassword(password, user.salt);
    if (computedHash != user.passwordHash) {
      throw const AuthException('Invalid username or password.');
    }

    await _setActiveUser(user);
    return user;
  }

  Future<void> recoverPassword({
    required String username,
    required String contactMethod,
    required String newPassword,
  }) async {
    final trimmedUser = username.trim();
    final trimmedContact = contactMethod.trim();

    if (trimmedUser.isEmpty) {
      throw const AuthException('Please enter your username.');
    }
    if (trimmedContact.isEmpty) {
      throw const AuthException('Please enter your registered email or phone.');
    }
    if (newPassword.length < 6) {
      throw const AuthException('New password must be at least 6 characters.');
    }

    final user = await findUser(trimmedUser);
    if (user == null) {
      throw const AuthException('Account not found.');
    }

    final emailMatches =
        user.email != null &&
        user.email!.trim().toLowerCase() == trimmedContact.toLowerCase();

    final userPhoneClean = user.phone?.replaceAll(RegExp(r'\D'), '');
    final inputPhoneClean = trimmedContact.replaceAll(RegExp(r'\D'), '');
    final phoneMatches =
        userPhoneClean != null &&
        userPhoneClean.isNotEmpty &&
        inputPhoneClean.isNotEmpty &&
        userPhoneClean == inputPhoneClean;

    if (!emailMatches && !phoneMatches) {
      throw const AuthException(
        'Recovery details do not match the registered contact method for this account.',
      );
    }

    final newSalt = generateSalt();
    final newHash = hashPassword(newPassword, newSalt);

    final updatedUser = user.copyWith(passwordHash: newHash, salt: newSalt);

    final users = await getAllUsers();
    final index = users.indexWhere(
      (u) => u.username.toLowerCase() == user.username.toLowerCase(),
    );
    if (index >= 0) {
      users[index] = updatedUser;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _usersPrefsKey,
      jsonEncode(users.map((u) => u.toJson()).toList()),
    );
  }

  /// Changes the password of the signed-in account after checking the
  /// current one.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = await _verifiedCurrentUser(currentPassword);
    if (newPassword.length < 6) {
      throw const AuthException('New password must be at least 6 characters.');
    }
    final newSalt = generateSalt();
    final updated = user.copyWith(
      passwordHash: hashPassword(newPassword, newSalt),
      salt: newSalt,
    );
    final users = await getAllUsers();
    final index = users.indexWhere(
      (u) => u.username.toLowerCase() == user.username.toLowerCase(),
    );
    if (index >= 0) users[index] = updated;
    await _saveUsers(users);
    await _setActiveUser(updated);
  }

  /// Removes the signed-in account from this phone after checking the
  /// password, then signs out. Saved documents are not touched.
  Future<void> deleteAccount({required String password}) async {
    final user = await _verifiedCurrentUser(password);
    final users = await getAllUsers();
    users.removeWhere(
      (u) => u.username.toLowerCase() == user.username.toLowerCase(),
    );
    await _saveUsers(users);
    await logout();
  }

  Future<UserAccount> _verifiedCurrentUser(String password) async {
    final current = await getCurrentUser();
    if (current == null) {
      throw const AuthException('You are not signed in.');
    }
    final user = await findUser(current.username) ?? current;
    if (hashPassword(password, user.salt) != user.passwordHash) {
      throw const AuthException('Current password is incorrect.');
    }
    return user;
  }

  Future<void> _saveUsers(List<UserAccount> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _usersPrefsKey,
      jsonEncode(users.map((u) => u.toJson()).toList()),
    );
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeUserPrefsKey);
    await prefs.remove(_sessionUserNameKey);
  }

  Future<void> _setActiveUser(UserAccount user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeUserPrefsKey, jsonEncode(user.toJson()));
    await prefs.setString(_sessionUserNameKey, user.username);
  }
}
