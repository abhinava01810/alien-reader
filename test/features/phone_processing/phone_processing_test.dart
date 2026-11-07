import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/features/device/data/raspberry_pi_device.dart'
    show OcrFailureException;
import 'package:alien_reader_app/features/phone_processing/data/capture_image_fetcher.dart';
import 'package:alien_reader_app/features/phone_processing/data/gemini_summary_service.dart';
import 'package:alien_reader_app/features/phone_processing/data/on_device_ocr.dart';
import 'package:alien_reader_app/features/phone_processing/data/phone_document_processor.dart';
import 'package:alien_reader_app/features/phone_processing/data/phone_processing_settings.dart';
import 'package:alien_reader_app/features/phone_processing/data/phone_tts_audio.dart';
import 'package:alien_reader_app/features/phone_processing/data/text_cleaning.dart';

class _MemorySecrets implements SecretStore {
  final Map<String, String> values = {};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// Answers by file name: file name containing a key → that reading.
class _FakeOcr implements OcrEngine {
  _FakeOcr(this.readings);
  final Map<String, OcrReading> readings;
  final List<String> seen = [];
  @override
  Future<OcrReading> read(String imagePath) async {
    seen.add(imagePath);
    final name = imagePath.split(RegExp(r'[\\/]')).last;
    for (final e in readings.entries) {
      if (name.contains(e.key)) return e.value;
    }
    return const OcrReading('');
  }

  @override
  Future<void> close() async {}
}

class _NameRotator implements ImageRotator {
  @override
  Future<String> rotate(String imagePath, int q) async =>
      imagePath.replaceFirst('.jpg', '_rot${q * 90}.jpg');
}

class _FakeSpeech implements SpeechFileSynthesizer {
  final List<String> spoken = [];
  @override
  Future<void> synthesize(String text, String outputPath) async {
    spoken.add(text);
    await File(outputPath).writeAsBytes(_wav([1, 2, 3, 4]));
  }
}

Uint8List _wav(List<int> pcm, {int rate = 22050}) {
  final b = BytesBuilder();
  final d = ByteData(36 + 8);
  void str(int at, String s) {
    for (var i = 0; i < 4; i++) {
      d.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  d.setUint32(4, 36 + pcm.length, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, rate, Endian.little);
  d.setUint32(28, rate * 2, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  str(36, 'data');
  d.setUint32(40, pcm.length, Endian.little);
  b.add(d.buffer.asUint8List());
  b.add(pcm);
  return b.takeBytes();
}

void main() {
  group('text cleaning (Pi parity)', () {
    test('normalises whitespace, control chars and blank lines', () {
      expect(
        cleanOcrText('\n\n  Hello \t  world\r\n\x07\n\n\n\nNext   line  \n\n'),
        'Hello world\n\nNext line',
      );
      expect(cleanOcrText(null), '');
    });

    test('usable text needs at least 3 letters or digits', () {
      expect(hasUsableText('a-b'), isFalse);
      expect(hasUsableText('ab1'), isTrue);
    });

    test('higher confidence and real words score higher', () {
      const words = 'The quick brown fox jumps over the lazy dog.';
      expect(
        ocrQualityScore(words, 90),
        greaterThan(ocrQualityScore(words, 40)),
      );
      expect(
        ocrQualityScore(words, 60),
        greaterThan(ocrQualityScore(r'|\ ;: ,. ~ |', 60)),
      );
    });
  });

  group('PageOcr orientation choice', () {
    test('keeps the upright reading when it is better', () async {
      final ocr = PageOcr(
        engine: _FakeOcr({
          'rot270': const OcrReading('lI1 ,', confidence: 30),
          'page': const OcrReading(
            'Dear customer,\nYour order has shipped.',
            confidence: 92,
          ),
        }),
        rotator: _NameRotator(),
      );
      final r = await ocr.read('/tmp/page.jpg');
      expect(r.orientation, OcrOrientation.original);
      expect(r.text, 'Dear customer,\nYour order has shipped.');
    });

    test('picks the counter-clockwise rotation like the Pi', () async {
      final engine = _FakeOcr({
        'rot270': const OcrReading(
          'Invoice 2041\nTotal due: 120.00',
          confidence: 88,
        ),
        'page': const OcrReading('~ ; l', confidence: 20),
      });
      final r = await PageOcr(
        engine: engine,
        rotator: _NameRotator(),
      ).read('/tmp/page.jpg');
      expect(r.orientation, OcrOrientation.rotatedCounterClockwise);
      expect(r.text, startsWith('Invoice 2041'));
      expect(engine.seen, hasLength(2), reason: 'no clockwise try needed');
    });

    test('tries clockwise only when both others found nothing', () async {
      final engine = _FakeOcr({
        'rot90': const OcrReading('Upside text found here', confidence: 80),
      });
      final r = await PageOcr(
        engine: engine,
        rotator: _NameRotator(),
      ).read('/tmp/page.jpg');
      expect(engine.seen, hasLength(3));
      expect(r.orientation, OcrOrientation.rotatedClockwise);
    });

    test('blank page gives empty text', () async {
      final r = await PageOcr(
        engine: _FakeOcr({}),
        rotator: _NameRotator(),
      ).read('/tmp/page.jpg');
      expect(r.text, isEmpty);
    });

    test('real rotation: 90° counter-clockwise turns landscape to portrait '
        'with the top-right corner moving to the top-left', () async {
      final dir = await Directory.systemTemp.createTemp('rot');
      addTearDown(() => dir.delete(recursive: true));
      final src = img.Image(width: 40, height: 20);
      img.fill(src, color: img.ColorRgb8(255, 255, 255));
      // Red block at the top-right.
      img.fillRect(
        src,
        x1: 30,
        y1: 0,
        x2: 39,
        y2: 5,
        color: img.ColorRgb8(255, 0, 0),
      );
      final path = '${dir.path}/page.jpg';
      File(path).writeAsBytesSync(img.encodeJpg(src, quality: 100));

      final out = await IsolateImageRotator().rotate(path, 3);
      final rotated = img.decodeJpg(File(out).readAsBytesSync())!;
      expect(rotated.width, 20);
      expect(rotated.height, 40);
      final corner = rotated.getPixel(2, 2);
      expect(corner.r, greaterThan(200));
      expect(corner.g, lessThan(80), reason: 'red block now top-left');
    });
  });

  group('Gemini summary', () {
    test('same model and prompt as the Pi, key only in a header', () async {
      late http.Request sent;
      final service = GeminiSummaryService(
        client: MockClient((req) async {
          sent = req;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '  A short   summary.\n\n\n'},
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      final summary = await service.summarize(
        'Document body',
        apiKey: 'test-key-123',
      );

      expect(summary, 'A short summary.');
      expect(sent.url.path, '/v1beta/models/gemini-2.5-flash:generateContent');
      expect(sent.url.query, isEmpty, reason: 'key never in the URL');
      expect(sent.headers['x-goog-api-key'], 'test-key-123');
      final prompt =
          (jsonDecode(sent.body)['contents'][0]['parts'][0]['text'] as String);
      expect(prompt, contains('You are helping a blind or visually impaired'));
      expect(prompt, contains('- Return only the summary.'));
      expect(prompt, endsWith('DOCUMENT:\n\nDocument body\n'));
    });

    test('a rejected key says so', () async {
      final service = GeminiSummaryService(
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"status":"INVALID_ARGUMENT","message":"API key not valid","details":[{"reason":"API_KEY_INVALID"}]}}',
            400,
          ),
        ),
      );
      await expectLater(
        service.summarize('x y z', apiKey: 'bad'),
        throwsA(
          isA<GeminiException>().having(
            (e) => e.keyRejected,
            'keyRejected',
            true,
          ),
        ),
      );
    });

    test('quota and network errors are explained', () async {
      final quota = GeminiSummaryService(
        client: MockClient((_) async => http.Response('{}', 429)),
      );
      await expectLater(
        quota.summarize('abc', apiKey: 'k'),
        throwsA(
          isA<GeminiException>().having(
            (e) => e.message,
            'message',
            contains('limit'),
          ),
        ),
      );
      final offline = GeminiSummaryService(
        client: MockClient((_) async => throw http.ClientException('down')),
      );
      await expectLater(
        offline.summarize('abc', apiKey: 'k'),
        throwsA(isA<GeminiException>()),
      );
    });
  });

  group('capture image fetcher', () {
    test('retries 404 until the photo exists', () async {
      var calls = 0;
      final dir = await Directory.systemTemp.createTemp('fetch');
      addTearDown(() => dir.delete(recursive: true));
      final fetcher = CaptureImageFetcher(
        retryDelay: Duration.zero,
        client: MockClient((_) async {
          calls++;
          return calls < 3
              ? http.Response('not yet', 404)
              : http.Response.bytes([0xFF, 0xD8, 0xFF], 200);
        }),
      );
      final f = await fetcher.fetch(
        'http://reader:8000/capture/1/image',
        File('${dir.path}/a.jpg'),
      );
      expect(calls, 3);
      expect(f.readAsBytesSync(), [0xFF, 0xD8, 0xFF]);
    });

    test('gives up with a clear error', () async {
      final fetcher = CaptureImageFetcher(
        retryDelay: Duration.zero,
        maxAttempts: 2,
        client: MockClient((_) async => http.Response('', 404)),
      );
      await expectLater(
        fetcher.fetch('http://r/capture/1/image', File('unused.jpg')),
        throwsA(isA<CaptureImageException>()),
      );
    });
  });

  group('speech files', () {
    test('long text is split under the engine limit on sentence breaks', () {
      final sentence = 'This is one full sentence of the document. ';
      final text = List.filled(200, sentence).join();
      final parts = splitForSpeech(text, 3000);
      expect(parts.length, greaterThan(1));
      expect(parts.every((p) => p.length <= 3000), isTrue);
      expect(parts.every((p) => p.endsWith('.')), isTrue);
      expect(parts.join(' ').replaceAll(RegExp(r'\s+'), ' '), text.trim());
    });

    test('a giant word is still split', () {
      final parts = splitForSpeech('x' * 7000, 3000);
      expect(parts.map((p) => p.length), [3000, 3000, 1000]);
    });

    test('WAV parts join into one valid file', () {
      final joined = concatWav([
        _wav([1, 2]),
        _wav([3, 4, 5, 6]),
      ]);
      final d = ByteData.sublistView(joined);
      expect(String.fromCharCodes(joined.sublist(0, 4)), 'RIFF');
      expect(d.getUint32(4, Endian.little), joined.length - 8);
      expect(d.getUint32(40, Endian.little), 6);
      expect(joined.sublist(44), [1, 2, 3, 4, 5, 6]);
    });

    test('prefers a very-high-quality offline US voice', () {
      final best = DeviceSpeechSynthesizer.pickBestVoice([
        {
          'name': 'net',
          'locale': 'en-US',
          'quality': 'very high',
          'network_required': '1',
          'features': '',
        },
        {
          'name': 'gb',
          'locale': 'en-GB',
          'quality': 'very high',
          'network_required': '0',
          'features': '',
        },
        {
          'name': 'us-normal',
          'locale': 'en-US',
          'quality': 'normal',
          'network_required': '0',
          'features': '',
        },
        {
          'name': 'us-best',
          'locale': 'en-US',
          'quality': 'very high',
          'network_required': '0',
          'features': '',
        },
        {
          'name': 'missing',
          'locale': 'en-US',
          'quality': 'very high',
          'network_required': '0',
          'features': 'notInstalled',
        },
        {
          'name': 'fr',
          'locale': 'fr-FR',
          'quality': 'very high',
          'network_required': '0',
          'features': '',
        },
      ]);
      expect(best?['name'], 'us-best');
      expect(DeviceSpeechSynthesizer.pickBestVoice(const []), isNull);
    });
  });

  group('settings', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('off by default; needs both the switch and a key', () async {
      final s = PhoneProcessingSettings(secrets: _MemorySecrets());
      expect(await s.isEnabled(), isFalse);
      expect(await s.readyKey(), isNull);
      await s.setEnabled(true);
      expect(await s.readyKey(), isNull, reason: 'no key yet');
      await s.saveGeminiKey('  AIzaTest9876  ');
      expect(await s.readyKey(), 'AIzaTest9876');
      await s.setEnabled(false);
      expect(await s.readyKey(), isNull);
    });

    test('key lives in the secret store, never in preferences', () async {
      final secrets = _MemorySecrets();
      final s = PhoneProcessingSettings(secrets: secrets);
      await s.saveGeminiKey('AIzaSecret');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().map(prefs.get).whereType<String>(),
        isNot(contains('AIzaSecret')),
      );
      expect(secrets.values.values, contains('AIzaSecret'));
      await s.clearGeminiKey();
      expect(await s.geminiKey(), isNull);
      expect(PhoneProcessingSettings.mask('AIzaSecret1234'), '••••1234');
    });
  });

  group('PhoneDocumentProcessor', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('proc'));
    tearDown(() => dir.delete(recursive: true));

    PhoneDocumentProcessor build(
      _FakeOcr ocr,
      _FakeSpeech speech, {
      String summary = 'Short summary.',
    }) => PhoneDocumentProcessor(
      workDir: () async => dir,
      fetcher: CaptureImageFetcher(
        retryDelay: Duration.zero,
        client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
      ),
      ocr: PageOcr(engine: ocr, rotator: _NameRotator()),
      gemini: GeminiSummaryService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': summary},
                    ],
                  },
                },
              ],
            }),
            200,
          ),
        ),
      ),
      speech: speech,
    );

    test('fetch → OCR → summary → two audio files, all local', () async {
      final speech = _FakeSpeech();
      final statuses = <String>[];
      final result =
          await build(
            _FakeOcr({
              'captured_image': const OcrReading(
                'Meeting moved to Friday at 10am.',
                confidence: 90,
              ),
            }),
            speech,
          ).process(
            imageUrl: 'http://reader:8000/capture/3/image',
            pageNumber: 3,
            geminiKey: 'k',
            onStatus: statuses.add,
          );

      expect(result.text, 'Meeting moved to Friday at 10am.');
      expect(result.summary, 'Short summary.');
      expect(File(result.imagePath).readAsBytesSync(), [1, 2, 3]);
      expect(File(result.originalAudioPath).existsSync(), isTrue);
      expect(File(result.summaryAudioPath).existsSync(), isTrue);
      expect(speech.spoken, [
        'Meeting moved to Friday at 10am.',
        'Short summary.',
      ]);
      expect(statuses, ['QUEUED', 'PROCESSING', 'READY']);
      expect(result.timings.keys, ['fetch', 'ocr', 'summary', 'audio']);
    });

    test('no text → the same OCR failure the Pi path reports', () async {
      await expectLater(
        build(_FakeOcr({}), _FakeSpeech()).process(
          imageUrl: 'http://r/capture/1/image',
          pageNumber: 1,
          geminiKey: 'k',
        ),
        throwsA(isA<OcrFailureException>()),
      );
    });
  });
}
