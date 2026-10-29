import 'cloud_api_service.dart';

/// Account as returned by `GET /auth/me` (`UserOut`).
class CloudUser {
  const CloudUser({
    required this.id,
    required this.name,
    required this.email,
    required this.emailVerified,
  });

  factory CloudUser.fromJson(Map<String, dynamic> json) => CloudUser(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    emailVerified: json['email_verified'] as bool? ?? false,
  );

  final int id;
  final String name;
  final String email;
  final bool emailVerified;
}

/// Account operations against the Naadh cloud API.
class CloudAuthService {
  CloudAuthService({CloudApiService? api})
    : api = api ?? CloudApiService.instance;

  final CloudApiService api;

  /// True when a token pair is stored. Does not contact the server.
  Future<bool> get isLoggedIn => api.hasTokens();

  Future<CloudUser> register(String name, String email, String password) async {
    final body = await api.post(
      '/auth/register',
      json: {'name': name.trim(), 'email': email.trim(), 'password': password},
    );
    return CloudUser.fromJson(body as Map<String, dynamic>);
  }

  /// OAuth2 password form: the email goes in the `username` field.
  Future<CloudUser> login(String email, String password) async {
    final body = await api.post(
      '/auth/login',
      form: {'username': email.trim(), 'password': password},
    );
    await api.saveTokens(body as Map<String, dynamic>);
    return getCurrentUser();
  }

  /// Revokes the refresh token server-side (best effort) and always clears
  /// the local tokens.
  Future<void> logout() async {
    try {
      final refresh = await api.refreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        await api.post('/auth/logout', json: {'refresh_token': refresh});
      }
    } catch (_) {
      // Offline or already revoked: local sign-out still proceeds.
    } finally {
      await api.clearTokens();
    }
  }

  Future<CloudUser> getCurrentUser() async {
    final body = await api.get('/auth/me');
    return CloudUser.fromJson(body as Map<String, dynamic>);
  }

  Future<void> requestEmailVerification(String email) =>
      api.post('/auth/verify-email/request', json: {'email': email.trim()});

  Future<CloudUser> confirmEmailVerification(String token) async {
    final body = await api.post(
      '/auth/verify-email/confirm',
      json: {'token': token.trim()},
    );
    return CloudUser.fromJson(body as Map<String, dynamic>);
  }

  Future<void> requestPasswordReset(String email) =>
      api.post('/auth/password-reset/request', json: {'email': email.trim()});

  Future<void> confirmPasswordReset(String token, String newPassword) =>
      api.post(
        '/auth/password-reset/confirm',
        json: {'token': token.trim(), 'new_password': newPassword},
      );

  /// Deletes the account, then clears local tokens.
  Future<void> deleteAccount(String password) async {
    await api.post(
      '/auth/account/delete',
      json: {'password': password},
      auth: true,
    );
    await api.clearTokens();
  }

  Future<void> refreshTokens() => api.refreshTokens();
}
