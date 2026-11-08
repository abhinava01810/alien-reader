// Pins RaspberryPiDevice's current behaviour (session start and its 409
// recovery, capture trigger, polling) before the reader address becomes
// configurable. The device file itself is not changed by that work.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:alien_reader_app/features/device/data/raspberry_pi_device.dart';
import 'package:alien_reader_app/features/device/data/services/pi_api_service.dart';
import 'package:alien_reader_app/features/device/domain/reader_device.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

/// A device whose reader answers each request with the next scripted reply
/// for that path. Requests are recorded as "METHOD /path".
(RaspberryPiDevice, List<String>) _device(Map<String, List<Object>> script) {
  final sent = <String>[];
  final device = RaspberryPiDevice(
    apiService: PiApiService(
      client: MockClient((r) async {
        final key = '${r.method} ${r.url.path}';
        sent.add(key);
        final queue = script[key];
        if (queue == null || queue.isEmpty) {
          return _json({'detail': 'none'}, 404);
        }
        final next = queue.length > 1 ? queue.removeAt(0) : queue.first;
        if (next is Exception) throw next;
        return next as http.Response;
      }),
    ),
  );
  return (device, sent);
}

void main() {
  group('startSession', () {
    test('success: connected, session id kept', () async {
      final (device, _) = _device({
        'POST /session/start': [
          _json({'success': true, 'session_id': 's1', 'access_token': 't1'}),
        ],
      });
      final statuses = <ReaderConnectionStatus>[];
      device.status.listen(statuses.add);
      await device.startSession('Abhinava');
      await Future<void>.delayed(Duration.zero);
      expect(device.sessionId, 's1');
      expect(statuses, [
        ReaderConnectionStatus.connecting,
        ReaderConnectionStatus.connected,
      ]);
    });

    test('409: ends the open session and retries once', () async {
      final (device, sent) = _device({
        'POST /session/start': [
          _json({
            'detail': 'Device is currently being used by another user.',
          }, 409),
          _json({'success': true, 'session_id': 's2'}),
        ],
        'POST /session/end': [
          _json({'success': true}),
        ],
      });
      await device.startSession('Abhinava');
      expect(sent, [
        'POST /session/start',
        'POST /session/end',
        'POST /session/start',
      ]);
      expect(device.sessionId, 's2');
    });

    test('other errors: rethrown, disconnected, no retry', () async {
      final (device, sent) = _device({
        'POST /session/start': [
          _json({'detail': 'boom'}, 500),
        ],
      });
      await expectLater(device.startSession('A'), throwsA(isA<Exception>()));
      expect(sent, ['POST /session/start']);
      expect(device.sessionId, isNull);
    });
  });

  group('triggerCaptureAsync', () {
    test('returns the reader reply on success', () async {
      final (device, _) = _device({
        'POST /capture': [
          _json({
            'success': true,
            'page_number': 4,
            'status': 'QUEUED',
            'image_url': '/capture/4/image',
          }),
        ],
      });
      final r = await device.triggerCaptureAsync();
      expect(r['page_number'], 4);
      expect(device.lastTriggeredPage, r);
    });

    test('throws the reader message when success is false', () async {
      final (device, _) = _device({
        'POST /capture': [
          _json({'success': false, 'message': 'No camera'}),
        ],
      });
      await expectLater(
        device.triggerCaptureAsync(),
        throwsA(
          isA<Exception>().having((e) => '$e', 'm', contains('No camera')),
        ),
      );
    });
  });

  group('pollPageUntilReady', () {
    Future<Map<String, dynamic>> poll(
      RaspberryPiDevice d, {
      List<String>? seen,
      int maxAttempts = 150,
    }) => d.pollPageUntilReady(
      2,
      pollInterval: Duration.zero,
      maxAttempts: maxAttempts,
      onStatusUpdate: seen?.add,
    );

    test('reports each status and returns the READY page', () async {
      final (device, sent) = _device({
        'GET /capture/2': [
          _json({'status': 'QUEUED'}),
          _json({'status': 'processing'}),
          _json({'status': 'READY', 'text': 'hello'}),
        ],
      });
      final seen = <String>[];
      final page = await poll(device, seen: seen);
      expect(page['text'], 'hello');
      expect(seen, ['QUEUED', 'PROCESSING', 'READY']);
      expect(device.lastCapture, page);
      expect(sent.toSet(), {'GET /capture/2'});
    });

    test('network errors are skipped, polling continues', () async {
      final (device, _) = _device({
        'GET /capture/2': [
          http.ClientException('blip'),
          _json({'status': 'READY'}),
        ],
      });
      expect((await poll(device))['status'], 'READY');
    });

    test('FAILED with reason text_not_detected: OcrFailureException', () async {
      final (device, _) = _device({
        'GET /capture/2': [
          _json({
            'status': 'FAILED',
            'reason': 'text_not_detected',
            'message': 'Move the page closer.',
          }),
        ],
      });
      await expectLater(
        poll(device),
        throwsA(
          isA<OcrFailureException>().having(
            (e) => e.message,
            'message',
            'Move the page closer.',
          ),
        ),
      );
    });

    test('FAILED with a message: that message', () async {
      final (device, _) = _device({
        'GET /capture/2': [
          _json({'status': 'FAILED', 'message': 'Camera error'}),
        ],
      });
      await expectLater(
        poll(device),
        throwsA(
          isA<Exception>().having((e) => '$e', 'm', contains('Camera error')),
        ),
      );
    });

    test('FAILED with only an error field: generic message (current behaviour; '
        'the reader sends "error", which is not read yet)', () async {
      final (device, _) = _device({
        'GET /capture/2': [
          _json({'status': 'FAILED', 'error': 'Text not detected.'}),
        ],
      });
      await expectLater(
        poll(device),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'm',
            contains('Page 2 processing failed on Pi'),
          ),
        ),
      );
    });

    test('gives up after maxAttempts', () async {
      final (device, sent) = _device({
        'GET /capture/2': [
          _json({'status': 'PROCESSING'}),
        ],
      });
      await expectLater(
        poll(device, maxAttempts: 3),
        throwsA(
          isA<Exception>().having((e) => '$e', 'm', contains('Timed out')),
        ),
      );
      expect(sent.length, 3);
    });
  });

  test('getCaptureDetails returns null instead of throwing', () async {
    final (device, _) = _device({
      'GET /capture/9': [
        _json({'detail': 'gone'}, 404),
      ],
    });
    expect(await device.getCaptureDetails(9), isNull);
  });

  test('getFullUrl builds on the reader address', () {
    final (device, _) = _device({});
    expect(
      device.getFullUrl('/capture/1/image'),
      'http://drpi2copy1.local:8000/capture/1/image',
    );
  });
}
