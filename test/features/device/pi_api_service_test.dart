// Pins how PiApiService talks to the reader: which method and URL each call
// uses, and what it does with errors. Written before making the base address
// configurable, so the default must keep behaving exactly like this.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:alien_reader_app/features/device/data/services/pi_api_service.dart';

const _default = 'http://drpi2copy1.local:8000';

/// A PiApiService whose requests are recorded and answered by [reply].
(PiApiService, List<http.Request>) _service({
  http.Response Function(http.Request r)? reply,
}) {
  final sent = <http.Request>[];
  final service = PiApiService(
    client: MockClient((r) async {
      sent.add(r);
      return reply?.call(r) ?? http.Response(jsonEncode({'ok': true}), 200);
    }),
  );
  return (service, sent);
}

void main() {
  group('default address: every call goes to drpi2copy1.local:8000', () {
    final calls = <String, Future<Object?> Function(PiApiService)>{
      'GET /status': (s) => s.getStatus(),
      'POST /session/start': (s) => s.startSession('Abhinava'),
      'POST /capture (captureImage)': (s) => s.captureImage(),
      'POST /capture (triggerCapture)': (s) => s.triggerCapture(),
      'GET /capture/3 (status)': (s) => s.getCaptureStatus(3),
      'GET /capture/3 (details)': (s) => s.getCaptureDetails(3),
      'GET /captures': (s) => s.getCaptures(),
      'POST /session/end': (s) => s.endSession(),
      'GET /status (health)': (s) => s.checkHealth(),
    };
    for (final entry in calls.entries) {
      test(entry.key, () async {
        final (service, sent) = _service();
        await entry.value(service);
        final r = sent.single;
        final expected = entry.key.split(' ');
        expect(r.method, expected[0]);
        expect(r.url.toString(), '$_default${expected[1]}');
      });
    }

    test('startSession sends the display name as JSON', () async {
      final (service, sent) = _service();
      await service.startSession('Abhinava');
      expect(jsonDecode(sent.single.body), {'display_name': 'Abhinava'});
      expect(
        sent.single.headers['Content-Type'],
        startsWith('application/json'),
      );
    });

    test('streamUrl and getFullUrl build on the default address', () {
      final (service, _) = _service();
      expect(service.streamUrl, '$_default/camera/stream');
      expect(
        service.getFullUrl('/capture/2/image'),
        '$_default/capture/2/image',
      );
    });

    test('getFullUrl leaves empty and absolute paths alone', () {
      final (service, _) = _service();
      expect(service.getFullUrl(null), '');
      expect(service.getFullUrl(''), '');
      expect(
        service.getFullUrl('http://elsewhere:9/x.jpg'),
        'http://elsewhere:9/x.jpg',
      );
    });
  });

  group('errors', () {
    test('non-200 replies throw with the status code', () async {
      final (service, _) = _service(
        reply: (_) => http.Response('{"detail":"busy"}', 409),
      );
      await expectLater(
        service.startSession('A'),
        throwsA(
          isA<Exception>().having((e) => '$e', 'message', contains('409')),
        ),
      );
      await expectLater(service.getStatus(), throwsA(isA<Exception>()));
      await expectLater(service.triggerCapture(), throwsA(isA<Exception>()));
      await expectLater(service.getCaptureStatus(1), throwsA(isA<Exception>()));
    });

    test('checkHealth is true only for a 200 and never throws', () async {
      expect(await _service().$1.checkHealth(), isTrue);
      expect(
        await _service(reply: (_) => http.Response('', 500)).$1.checkHealth(),
        isFalse,
      );
      final failing = PiApiService(
        client: MockClient((_) async => throw http.ClientException('down')),
      );
      expect(await failing.checkHealth(), isFalse);
    });
  });

  group('a supplied reader address', () {
    test('replaces the default in every call', () async {
      const reader = 'http://naadh-3f9a1c.local:8000';
      final sent = <http.Request>[];
      final service = PiApiService(
        baseUrl: () => reader,
        client: MockClient((r) async {
          sent.add(r);
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );
      await service.getStatus();
      await service.startSession('A');
      await service.triggerCapture();
      await service.getCaptureStatus(1);
      await service.getCaptureDetails(1);
      await service.getCaptures();
      await service.endSession();
      await service.checkHealth();
      expect(sent.map((r) => r.url.origin).toSet(), {
        'http://naadh-3f9a1c.local:8000',
      });
      expect(service.streamUrl, '$reader/camera/stream');
      expect(service.getFullUrl('/capture/1/image'), '$reader/capture/1/image');
    });

    test('is read on every request, so a re-pair takes effect', () async {
      var reader = 'http://192.168.1.16:8000';
      final sent = <String>[];
      final service = PiApiService(
        baseUrl: () => reader,
        client: MockClient((r) async {
          sent.add(r.url.origin);
          return http.Response('{}', 200);
        }),
      );
      await service.getStatus();
      reader = 'http://naadh-000002.local:8000';
      await service.getStatus();
      expect(sent, [
        'http://192.168.1.16:8000',
        'http://naadh-000002.local:8000',
      ]);
    });

    test('null or empty falls back to the default', () {
      expect(
        PiApiService(baseUrl: () => '').streamUrl,
        '$_default/camera/stream',
      );
      expect(PiApiService(baseUrl: null).streamUrl, '$_default/camera/stream');
    });
  });
}
