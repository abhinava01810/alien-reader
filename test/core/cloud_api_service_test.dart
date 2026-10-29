import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:alien_reader_app/core/services/cloud_api_service.dart';
import 'package:alien_reader_app/core/services/device_cloud_service.dart';
import 'package:alien_reader_app/core/services/usage_cloud_service.dart';

import '../helpers/fake_cloud.dart';

void main() {
  test('login posts a form with username and stores tokens', () async {
    final cloud = FakeCloud((r) {
      if (r.url.path == '/auth/login') return jsonResponse(tokenJson('1'));
      if (r.url.path == '/auth/me') return jsonResponse(userJson());
      return null;
    });

    final user = await cloud.auth.login(' alice@example.com ', 'pw12345678');

    final login = cloud.requests.first;
    expect(login.headers['content-type'], contains('x-www-form-urlencoded'));
    expect(login.bodyFields, {
      'username': 'alice@example.com',
      'password': 'pw12345678',
    });
    expect(cloud.requests[1].headers['Authorization'], 'Bearer access-1');
    expect(user.name, 'Alice');
    expect(await cloud.auth.isLoggedIn, isTrue);
  });

  test('a 401 triggers one refresh and a retry with the new token', () async {
    var meCalls = 0;
    final cloud = FakeCloud((r) {
      if (r.url.path == '/auth/me') {
        meCalls++;
        return r.headers['Authorization'] == 'Bearer access-2'
            ? jsonResponse(userJson())
            : jsonResponse({'detail': 'expired'}, 401);
      }
      if (r.url.path == '/auth/refresh') {
        expect(jsonDecode(r.body), {'refresh_token': 'refresh-1'});
        return jsonResponse(tokenJson('2'));
      }
      return null;
    }, signedIn: true);

    final user = await cloud.auth.getCurrentUser();

    expect(user.email, 'alice@example.com');
    expect(meCalls, 2);
    expect(cloud.paths, ['GET /auth/me', 'POST /auth/refresh', 'GET /auth/me']);
    expect(cloud.tokens.values['naadh_refresh_token'], 'refresh-2');
  });

  test('an expired access token is refreshed before the request', () async {
    final cloud = FakeCloud((r) {
      if (r.url.path == '/auth/refresh') return jsonResponse(tokenJson('2'));
      if (r.url.path == '/devices') return jsonResponse([]);
      return null;
    }, signedIn: true);
    cloud.tokens.values['naadh_access_expires_at'] = DateTime.now()
        .subtract(const Duration(minutes: 1))
        .toIso8601String();

    await DeviceCloudService(api: cloud.api).getDevices();

    expect(cloud.paths, ['POST /auth/refresh', 'GET /devices']);
    expect(cloud.requests.last.headers['Authorization'], 'Bearer access-2');
  });

  test('a rejected refresh clears tokens and signals session expiry', () async {
    final cloud = FakeCloud((r) {
      if (r.url.path == '/auth/me') return jsonResponse({'detail': 'x'}, 401);
      if (r.url.path == '/auth/refresh') {
        return jsonResponse({'detail': 'Invalid refresh token'}, 401);
      }
      return null;
    }, signedIn: true);
    var expired = 0;
    cloud.api.onSessionExpired.listen((_) => expired++);

    await expectLater(
      cloud.auth.getCurrentUser(),
      throwsA(isA<SessionExpiredException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(cloud.tokens.values, isEmpty);
    expect(expired, 1);
  });

  test('a 401 that survives a fresh token is a normal error', () async {
    final cloud = FakeCloud((r) {
      if (r.url.path == '/auth/account/delete') {
        return jsonResponse({'detail': 'Incorrect password'}, 401);
      }
      if (r.url.path == '/auth/refresh') return jsonResponse(tokenJson('2'));
      return null;
    }, signedIn: true);

    await expectLater(
      cloud.auth.deleteAccount('wrong'),
      throwsA(
        isA<CloudApiException>()
            .having((e) => e.message, 'message', 'Incorrect password')
            .having((e) => e, 'type', isNot(isA<SessionExpiredException>())),
      ),
    );
    expect(cloud.tokens.values, isNotEmpty);
  });

  test('validation errors are joined into one message', () async {
    final cloud = FakeCloud(
      (r) => jsonResponse({
        'detail': [
          {
            'loc': ['body', 'email'],
            'msg': 'value is not a valid email',
            'type': 'x',
          },
        ],
      }, 422),
    );

    await expectLater(
      cloud.auth.register('A', 'bad', 'password1'),
      throwsA(
        isA<CloudApiException>().having(
          (e) => e.message,
          'message',
          'value is not a valid email',
        ),
      ),
    );
  });

  test('logout revokes the refresh token and clears local tokens', () async {
    final cloud = FakeCloud(
      (r) => r.url.path == '/auth/logout' ? http.Response('', 204) : null,
      signedIn: true,
    );

    await cloud.auth.logout();

    expect(jsonDecode(cloud.requests.single.body), {
      'refresh_token': 'refresh-1',
    });
    expect(cloud.tokens.values, isEmpty);
  });

  test('usage sends counts only', () async {
    final cloud = FakeCloud(
      (r) => jsonResponse({
        'id': 9,
        'device_id': 3,
        'word_count': 120,
        'input_tokens': 200,
        'output_tokens': 40,
        'processing_ms': 900,
        'summary_used': true,
        'created_at': '2026-01-01T00:00:00Z',
      }, 201),
      signedIn: true,
    );

    await UsageCloudService(api: cloud.api).logUsage(
      deviceId: 3,
      wordCount: 120,
      inputTokens: 200,
      outputTokens: 40,
      processingMs: 900,
      summaryUsed: true,
    );

    expect(jsonDecode(cloud.requests.single.body).keys.toSet(), {
      'device_id',
      'word_count',
      'input_tokens',
      'output_tokens',
      'processing_ms',
      'summary_used',
    });
  });

  test('missing base URL fails with a clear message', () async {
    final api = CloudApiService(tokens: MemoryTokenStore(), baseUrl: '');
    await expectLater(
      api.get('/auth/me', auth: false),
      throwsA(isA<CloudApiException>()),
    );
  });
}
