// Runs the real on-phone pipeline pieces on a real device against a real
// reader capture: ML Kit OCR and the phone's TTS engine. Gemini runs only
// when a key is passed with --dart-define=GEMINI_TEST_KEY=... (never stored).
//
//   flutter test integration_test/phone_processing_device_test.dart \
//     -d <device> --dart-define=CAPTURE_IMAGE_URL=http://<reader>:8000/capture/1/image
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:alien_reader_app/features/document/data/services/document_storage_service.dart';
import 'package:alien_reader_app/features/document/data/models/saved_document.dart';
import 'package:alien_reader_app/features/output/presentation/output_screen.dart';
import 'package:alien_reader_app/features/phone_processing/data/capture_image_fetcher.dart';
import 'package:alien_reader_app/features/phone_processing/data/gemini_summary_service.dart';
import 'package:alien_reader_app/features/phone_processing/data/on_device_ocr.dart';
import 'package:alien_reader_app/features/phone_processing/data/phone_document_processor.dart';
import 'package:alien_reader_app/features/phone_processing/data/phone_tts_audio.dart';
import 'package:alien_reader_app/shared/models/document_output.dart';

const _imageUrl = String.fromEnvironment('CAPTURE_IMAGE_URL');
const _summaryForAudio = String.fromEnvironment('SUMMARY_FOR_AUDIO');
const _geminiKey = String.fromEnvironment('GEMINI_TEST_KEY');

double _wavSeconds(File f) {
  final b = f.readAsBytesSync();
  final bytesPerSec = b.buffer.asByteData().getUint32(28, Endian.little);
  return (b.length - 44) / bytesPerSec;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real capture: ML Kit OCR + phone TTS', (tester) async {
    expect(_imageUrl, isNotEmpty, reason: 'pass CAPTURE_IMAGE_URL');
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/device_test',
    );
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final report = <String, Object?>{};
    final watch = Stopwatch()..start();

    final image = await CaptureImageFetcher().fetch(
      _imageUrl,
      File('${dir.path}/captured_image.jpg'),
    );
    report['fetch_ms'] = watch.elapsedMilliseconds;
    report['image_bytes'] = image.lengthSync();

    watch.reset();
    final ocr = PageOcr();
    final page = await ocr.read(image.path);
    await ocr.close();
    report['ocr_ms'] = watch.elapsedMilliseconds;
    report['orientation'] = page.orientation.name;
    report['ocr_score'] = page.score;
    report['ocr_text'] = page.text;

    var summary = _summaryForAudio;
    if (_geminiKey.isNotEmpty) {
      watch.reset();
      summary = await GeminiSummaryService().summarize(
        page.text,
        apiKey: _geminiKey,
      );
      report['gemini_ms'] = watch.elapsedMilliseconds;
      report['gemini_summary'] = summary;
    }

    watch.reset();
    final speech = DeviceSpeechSynthesizer();
    final original = '${dir.path}/original_audio.wav';
    await speech.synthesize(page.text, original);
    report['tts_original_ms'] = watch.elapsedMilliseconds;
    report['voice'] = speech.chosenVoice;
    report['original_audio'] = original;
    report['original_audio_s'] = _wavSeconds(File(original));
    if (summary.isNotEmpty) {
      watch.reset();
      final s = '${dir.path}/summary_audio.wav';
      await speech.synthesize(summary, s);
      report['tts_summary_ms'] = watch.elapsedMilliseconds;
      report['summary_audio'] = s;
      report['summary_audio_s'] = _wavSeconds(File(s));
    }

    // One line the runner can grep.
    // ignore: avoid_print
    print('PHONE_PIPELINE_REPORT ${jsonEncode(report)}');
    expect(page.text, isNotEmpty);
    expect(File(original).lengthSync(), greaterThan(44));
  });

  testWidgets('full flow: processor → save to Files → Output tab', (
    tester,
  ) async {
    // Real fetch, ML Kit, TTS and storage. Gemini is real when
    // GEMINI_TEST_KEY is given, otherwise a stub that returns a fixed
    // summary (marked in the report).
    final gemini = _geminiKey.isNotEmpty
        ? GeminiSummaryService()
        : GeminiSummaryService(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'text': 'STUB SUMMARY (no Gemini key given).'},
                        ],
                      },
                    },
                  ],
                }),
                200,
              ),
            ),
          );
    final statuses = <String>[];
    final processor = PhoneDocumentProcessor(gemini: gemini);
    final result = await tester.runAsync(
      () => processor.process(
        imageUrl: _imageUrl,
        pageNumber: 1,
        geminiKey: _geminiKey.isEmpty ? 'stub' : _geminiKey,
        onStatus: statuses.add,
      ),
    );
    expect(result, isNotNull);
    expect(statuses, ['QUEUED', 'PROCESSING', 'READY']);

    final output = DocumentOutput(
      originalText: result!.text,
      summaryText: result.summary,
      imageUrl: Uri.file(result.imagePath).toString(),
      originalAudioUrl: Uri.file(result.originalAudioPath).toString(),
      summaryAudioUrl: Uri.file(result.summaryAudioPath).toString(),
    );
    final storage = DocumentStorageService();
    final saved = await tester.runAsync(
      () => storage.saveCompleteDocument(
        originalText: output.originalText,
        summaryText: output.summaryText,
        pageNumber: 1,
        imageUrl: output.imageUrl,
        originalAudioUrl: output.originalAudioUrl,
        summaryAudioUrl: output.summaryAudioUrl,
      ),
    );
    expect(saved, isNotNull);
    for (final path in [
      saved!.imagePath,
      saved.originalAudioPath,
      saved.summaryAudioPath,
      saved.originalPdfPath,
    ]) {
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue, reason: path);
    }
    expect(
      File(saved.imagePath!).lengthSync(),
      File(result.imagePath).lengthSync(),
    );

    // The Output tab, as the app shows it when processing ends: busy while
    // processing, then handed the saved document.
    Widget outputTab({required bool busy, SavedDocument? latest}) =>
        MaterialApp(
          home: Scaffold(
            body: OutputScreen(isProcessing: busy, latestDocument: latest),
          ),
        );
    await tester.pumpWidget(outputTab(busy: true));
    await tester.pump();
    await tester.pumpWidget(outputTab(busy: false, latest: saved));
    await tester.pump(const Duration(milliseconds: 500));
    final firstLine = result.text.split('\n').first.trim();
    expect(find.textContaining(firstLine), findsWidgets);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.textContaining(result.summary.trim()), findsWidgets);

    // ignore: avoid_print
    print(
      'FULL_FLOW_REPORT ${jsonEncode({'timings_ms': result.timings.map((k, v) => MapEntry(k, v.inMilliseconds)), 'gemini': _geminiKey.isEmpty ? 'stub' : 'live', 'summary': result.summary, 'saved_id': saved.documentId})}',
    );

    // Leave no test document behind in the user's Files tab.
    await tester.runAsync(() => storage.deleteDocument(saved.documentId));
    await processor.close();
  });
}
