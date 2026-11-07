import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:alien_reader_app/features/device/data/models/provisioning_models.dart';
import 'package:alien_reader_app/features/device/data/services/setup_pairing_service.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

SetupPairingService _service(
  http.Response? Function(http.Request) route, {
  List<http.Request>? log,
}) {
  return SetupPairingService(
    baseUrl: 'http://reader.test:8000/',
    client: MockClient((request) async {
      log?.add(request);
      return route(request) ?? http.Response('{}', 404);
    }),
  );
}

void main() {
  group('startSession', () {
    test('posts to /api/setup/session with no secret', () async {
      final log = <http.Request>[];
      final service = _service(
        (r) => _json({'pending_id': 'p-1', 'expires_in': 120}, 202),
        log: log,
      );

      final session = await service.startSession();

      expect(session.pendingId, 'p-1');
      expect(session.expiresInSeconds, 120);
      expect(session.token, isNull);
      expect(log.single.method, 'POST');
      expect(
        log.single.url.toString(),
        'http://reader.test:8000/api/setup/session',
      );
      expect(jsonDecode(log.single.body), isEmpty);
      expect(log.single.headers.containsKey('Authorization'), isFalse);
    });

    test('accepts an immediate token', () async {
      final service = _service((r) => _json({'token': 'abc'}));
      expect((await service.startSession()).token, 'abc');
    });

    test('a reply without pending_id or token is an error', () async {
      final service = _service((r) => _json({'ok': true}));
      await expectLater(
        service.startSession(),
        throwsA(isA<SetupNetworkException>()),
      );
    });

    test('429 is a rate-limit error', () async {
      final service = _service((r) => http.Response('', 429));
      await expectLater(
        service.startSession(),
        throwsA(isA<SetupRateLimitException>()),
      );
    });

    test('a refused connection is reported as unreachable', () async {
      final service = SetupPairingService(
        baseUrl: 'http://reader.test',
        client: MockClient((_) async => throw const SocketException('down')),
      );
      await expectLater(
        service.startSession(),
        throwsA(
          isA<DeviceUnreachableException>().having(
            (e) => e.message,
            'message',
            contains('NAADH-Setup'),
          ),
        ),
      );
    });
  });

  group('pollSession', () {
    test('pending, then approved with a token', () async {
      var calls = 0;
      final log = <http.Request>[];
      final service = _service((r) {
        calls++;
        return calls < 3
            ? _json({'status': 'pending'}, 202)
            : _json({'token': 'tok-9'});
      }, log: log);

      expect(await service.pollSession('p 1'), isA<PollPending>());
      expect(await service.pollSession('p 1'), isA<PollPending>());
      final result = await service.pollSession('p 1');

      expect(result, isA<PollApproved>());
      expect((result as PollApproved).token, 'tok-9');
      expect(log.first.method, 'GET');
      expect(log.first.url.path, '/api/setup/session/p%201');
    });

    test('410 means the pairing window expired', () async {
      final service = _service((r) => http.Response('', 410));
      expect(await service.pollSession('p-1'), isA<PollExpired>());
    });

    test('403 and a denied status mean refused', () async {
      expect(
        await _service((r) => http.Response('', 403)).pollSession('p'),
        isA<PollDenied>(),
      );
      expect(
        await _service((r) => _json({'status': 'denied'})).pollSession('p'),
        isA<PollDenied>(),
      );
    });

    test('a server error is surfaced, not treated as pending', () async {
      final service = _service((r) => http.Response('', 500));
      await expectLater(
        service.pollSession('p-1'),
        throwsA(isA<SetupNetworkException>()),
      );
    });
  });

  group('getNetworks', () {
    test(
      'sends the bearer token and returns strongest first, de-duplicated',
      () async {
        final log = <http.Request>[];
        final service = _service(
          (r) => _json({
            'networks': [
              {'ssid': 'Cafe', 'signal_strength': 40, 'security': 'OPEN'},
              {'ssid': 'Home', 'signal_strength': 90, 'security': 'WPA2'},
              {'ssid': 'Home', 'signal_strength': 30, 'security': 'WPA2'},
              {'ssid': '', 'signal_strength': 99, 'security': 'WPA2'},
            ],
          }),
          log: log,
        );

        final networks = await service.getNetworks('tok-1');

        expect(log.single.headers['Authorization'], 'Bearer tok-1');
        expect(networks.map((n) => n.ssid), ['Home', 'Cafe']);
        expect(networks.last.isOpen, isTrue);
      },
    );

    test('also accepts a bare list', () async {
      final service = _service(
        (r) => _json([
          {'ssid': 'A', 'signal_strength': 10, 'security': 'WPA2'},
        ]),
      );
      expect((await service.getNetworks('t')).single.ssid, 'A');
    });

    test('401 means the session ended', () async {
      final service = _service((r) => http.Response('', 401));
      await expectLater(
        service.getNetworks('t'),
        throwsA(isA<SetupAuthException>()),
      );
    });
  });

  group('submitWifi', () {
    test('sends ssid and password with the token', () async {
      final log = <http.Request>[];
      final service = _service(
        (r) => _json({'success': true, 'message': 'Applying'}),
        log: log,
      );

      final result = await service.submitWifi(
        'tok-1',
        ssid: 'Home',
        password: 'hunter2hunter2',
      );

      expect(result.message, 'Applying');
      expect(log.single.url.path, '/api/setup/wifi');
      expect(log.single.headers['Authorization'], 'Bearer tok-1');
      final body = jsonDecode(log.single.body) as Map<String, dynamic>;
      expect(body['ssid'], 'Home');
      expect(body['password'], 'hunter2hunter2');
      expect(body['hidden'], false);
    });

    test('a 2xx reply without a success field counts as accepted', () async {
      final service = _service((r) => _json({'status': 'CONNECTING'}));
      await service.submitWifi('t', ssid: 'Home', password: 'password1');
    });

    test('success:false is an error', () async {
      final service = _service(
        (r) => _json({'success': false, 'message': 'Bad passphrase'}),
      );
      await expectLater(
        service.submitWifi('t', ssid: 'Home', password: 'password1'),
        throwsA(
          isA<SetupNetworkException>().having(
            (e) => e.message,
            'message',
            'Bad passphrase',
          ),
        ),
      );
    });

    test('errors never contain the password', () async {
      const password = 'super-secret-passphrase';
      for (final reply in <http.Response>[
        http.Response('$password echoed', 500),
        http.Response('', 401),
        http.Response('', 429),
      ]) {
        final service = _service((r) => reply);
        try {
          await service.submitWifi('t', ssid: 'Home', password: password);
          fail('expected an error');
        } catch (e) {
          expect(e.toString(), isNot(contains(password)));
        }
      }
    });
  });

  group('manual device address', () {
    test('adds http:// and the reader port when missing', () {
      expect(
        PairingConfig.normalizeAddress('192.168.1.16'),
        'http://192.168.1.16:8000',
      );
      expect(
        PairingConfig.normalizeAddress(' http://192.168.1.16:8000/ '),
        'http://192.168.1.16:8000',
      );
      expect(
        PairingConfig.normalizeAddress('reader.local:9000'),
        'http://reader.local:9000',
      );
      expect(PairingConfig.normalizeAddress(''), isNull);
      expect(PairingConfig.normalizeAddress('ftp://x'), isNull);
    });

    test('reports the real failure, not the hotspot', () async {
      final service = SetupPairingService(
        baseUrl: 'http://192.168.1.250:8000',
        viaHotspot: false,
        client: MockClient(
          (_) async => throw const SocketException(
            'Connection failed',
            osError: OSError('Connection refused', 111),
          ),
        ),
      );
      await expectLater(
        service.startSession(),
        throwsA(
          isA<DeviceUnreachableException>()
              .having(
                (e) => e.message,
                'message',
                contains('Connection refused'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('192.168.1.250:8000'),
              )
              .having(
                (e) => e.message,
                'message',
                isNot(contains('NAADH-Setup')),
              ),
        ),
      );
    });

    test('the hotspot path keeps its hotspot advice', () async {
      final service = SetupPairingService(
        client: MockClient(
          (_) async => throw const SocketException('Network is unreachable'),
        ),
      );
      await expectLater(
        service.startSession(),
        throwsA(
          isA<DeviceUnreachableException>().having(
            (e) => e.message,
            'message',
            contains('NAADH-Setup'),
          ),
        ),
      );
    });
  });
}
