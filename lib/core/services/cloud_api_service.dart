import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Base URL of the Naadh cloud API, injected at build time with
/// `--dart-define=NAADH_API_BASE_URL=...`. Never hard-coded.
const String kCloudApiBaseUrl = String.fromEnvironment('NAADH_API_BASE_URL');

/// Error returned by the cloud API, with the server's message when it sent one.
class CloudApiException implements Exception {
  const CloudApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// The refresh token was rejected; local tokens have been cleared and the
/// user has to log in again.
class SessionExpiredException extends CloudApiException {
  const SessionExpiredException()
    : super('Your session has expired. Please log in again.', statusCode: 401);
}

/// Persists the token pair. Tokens never leave this store except as the
/// Authorization header or the refresh/logout request body.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// HTTP client for the Naadh cloud API.
///
/// Attaches the Bearer token to authenticated calls, refreshes an expired
/// access token once (`POST /auth/refresh`) and retries, and on refresh
/// failure clears the tokens and emits [onSessionExpired].
class CloudApiService {
  CloudApiService({http.Client? client, TokenStore? tokens, String? baseUrl})
    : _client = client ?? http.Client(),
      _tokens = tokens ?? SecureTokenStore(),
      _baseUrl = baseUrl ?? kCloudApiBaseUrl;

  /// Shared instance used by the app's cloud services.
  static final CloudApiService instance = CloudApiService();

  static const _accessKey = 'naadh_access_token';
  static const _refreshKey = 'naadh_refresh_token';
  static const _expiresAtKey = 'naadh_access_expires_at';

  /// Generous because the backend host has a cold-start delay.
  static const Duration timeout = Duration(seconds: 60);

  final http.Client _client;
  final TokenStore _tokens;
  final String _baseUrl;

  final _sessionExpired = StreamController<void>.broadcast();
  Future<String>? _refreshing;

  /// Fires when stored tokens are no longer accepted.
  Stream<void> get onSessionExpired => _sessionExpired.stream;

  bool get isConfigured => _baseUrl.isNotEmpty;

  // ─── Tokens ───────────────────────────────────────────────────────

  Future<bool> hasTokens() async {
    try {
      final refresh = await _tokens.read(_refreshKey);
      return refresh != null && refresh.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<String?> refreshToken() => _tokens.read(_refreshKey);

  /// Stores a `TokenOut` response body.
  Future<void> saveTokens(Map<String, dynamic> tokenOut) async {
    final access = tokenOut['access_token'] as String;
    final refresh = tokenOut['refresh_token'] as String;
    final expiresIn = (tokenOut['expires_in'] as num?)?.toInt() ?? 0;
    // Refresh slightly early so a request never races the expiry.
    final expiresAt = DateTime.now().add(Duration(seconds: expiresIn - 30));
    await _tokens.write(_accessKey, access);
    await _tokens.write(_refreshKey, refresh);
    await _tokens.write(_expiresAtKey, expiresAt.toIso8601String());
  }

  Future<void> clearTokens() async {
    for (final key in [_accessKey, _refreshKey, _expiresAtKey]) {
      try {
        await _tokens.delete(key);
      } catch (_) {}
    }
  }

  Future<bool> _accessExpired() async {
    final raw = await _tokens.read(_expiresAtKey);
    final at = raw == null ? null : DateTime.tryParse(raw);
    return at == null || DateTime.now().isAfter(at);
  }

  /// Exchanges the refresh token for a new pair. Concurrent callers share one
  /// request. Throws [SessionExpiredException] when the server refuses.
  Future<String> refreshTokens() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _doRefresh() async {
    final refresh = await _tokens.read(_refreshKey);
    if (refresh == null || refresh.isEmpty) {
      await _expire();
      throw const SessionExpiredException();
    }
    final http.Response res;
    try {
      res = await _client
          .post(
            _uri('/auth/refresh'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const CloudApiException(
        'The server is taking too long to respond. Please try again.',
      );
    } catch (_) {
      throw const CloudApiException(
        'Could not reach the server. Check your internet connection.',
      );
    }
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await saveTokens(body);
      return body['access_token'] as String;
    }
    if (res.statusCode == 400 ||
        res.statusCode == 401 ||
        res.statusCode == 403 ||
        res.statusCode == 422) {
      await _expire();
      throw const SessionExpiredException();
    }
    throw _errorFrom(res);
  }

  Future<void> _expire() async {
    await clearTokens();
    _sessionExpired.add(null);
  }

  // ─── Requests ─────────────────────────────────────────────────────

  Future<dynamic> get(String path, {bool auth = true}) =>
      _send('GET', path, auth: auth);

  Future<dynamic> post(
    String path, {
    Object? json,
    Map<String, String>? form,
    bool auth = false,
  }) => _send('POST', path, json: json, form: form, auth: auth);

  Future<dynamic> delete(String path, {bool auth = true}) =>
      _send('DELETE', path, auth: auth);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? json,
    Map<String, String>? form,
    required bool auth,
  }) async {
    if (!isConfigured) {
      throw const CloudApiException(
        'The app was built without a server address '
        '(NAADH_API_BASE_URL).',
      );
    }

    String? token;
    if (auth) {
      token = await _tokens.read(_accessKey);
      if (token == null || await _accessExpired()) {
        token = await refreshTokens();
      }
    }

    var res = await _request(
      method,
      path,
      json: json,
      form: form,
      token: token,
    );
    if (auth && res.statusCode == 401) {
      // Retry once with a fresh token. A 401 after a successful refresh is
      // about the request itself (e.g. a wrong password), so it falls
      // through to the normal error below instead of ending the session.
      token = await refreshTokens();
      res = await _request(method, path, json: json, form: form, token: token);
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      try {
        return jsonDecode(res.body);
      } catch (_) {
        return null;
      }
    }
    throw _errorFrom(res);
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Object? json,
    Map<String, String>? form,
    String? token,
  }) async {
    final request = http.Request(method, _uri(path));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';
    if (form != null) {
      request.bodyFields = form;
    } else if (json != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(json);
    }
    try {
      final streamed = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const CloudApiException(
        'The server is taking too long to respond. Please try again.',
      );
    } catch (_) {
      throw const CloudApiException(
        'Could not reach the server. Check your internet connection.',
      );
    }
  }

  Uri _uri(String path) {
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    return Uri.parse('$base$path');
  }

  /// Turns a FastAPI error body (`{"detail": "..."}` or a validation list)
  /// into a readable message.
  CloudApiException _errorFrom(http.Response res) {
    String? message;
    try {
      final body = jsonDecode(res.body);
      final detail = body is Map ? body['detail'] : null;
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        message = detail
            .map((e) => e is Map ? e['msg']?.toString() : null)
            .whereType<String>()
            .join('\n');
      }
    } catch (_) {}
    if (message == null || message.isEmpty) {
      message = res.statusCode >= 500
          ? 'The server ran into a problem. Please try again shortly.'
          : 'Request failed (${res.statusCode}).';
    }
    return CloudApiException(message, statusCode: res.statusCode);
  }

  void dispose() {
    _sessionExpired.close();
    _client.close();
  }
}

/// In-memory [TokenStore] for tests.
class MemoryTokenStore implements TokenStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
