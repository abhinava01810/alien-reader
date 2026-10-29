import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:alien_reader_app/core/services/auth_service_cloud.dart';
import 'package:alien_reader_app/core/services/cloud_api_service.dart';

/// Route handler: return null to fall through to a 404.
typedef FakeRoute = http.Response? Function(http.Request request);

/// A [CloudApiService] backed by an in-memory token store and a scripted
/// HTTP client. Every request is recorded in [requests].
class FakeCloud {
  FakeCloud(this.route, {bool signedIn = false}) {
    api = CloudApiService(
      client: MockClient((request) async {
        requests.add(request);
        return route(request) ??
            http.Response(jsonEncode({'detail': 'Not Found'}), 404);
      }),
      tokens: tokens,
      baseUrl: 'https://api.test',
    );
    auth = CloudAuthService(api: api);
    if (signedIn) {
      tokens.values
        ..['naadh_access_token'] = 'access-1'
        ..['naadh_refresh_token'] = 'refresh-1'
        ..['naadh_access_expires_at'] = DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String();
    }
  }

  final FakeRoute route;
  final MemoryTokenStore tokens = MemoryTokenStore();
  final List<http.Request> requests = [];
  late final CloudApiService api;
  late final CloudAuthService auth;

  List<String> get paths =>
      requests.map((r) => '${r.method} ${r.url.path}').toList();
}

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> userJson({
  String name = 'Alice',
  String email = 'alice@example.com',
}) => {
  'id': 1,
  'name': name,
  'email': email,
  'email_verified': true,
  'created_at': '2026-01-01T00:00:00Z',
};

Map<String, dynamic> tokenJson(String n) => {
  'access_token': 'access-$n',
  'refresh_token': 'refresh-$n',
  'token_type': 'bearer',
  'expires_in': 900,
};
