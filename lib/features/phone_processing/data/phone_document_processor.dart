import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../device/data/raspberry_pi_device.dart' show OcrFailureException;
import 'capture_image_fetcher.dart';
import 'gemini_summary_service.dart';
import 'on_device_ocr.dart';
import 'phone_tts_audio.dart';

/// What the on-phone pipeline produced. All paths are local files.
class PhoneProcessingResult {
  const PhoneProcessingResult({
    required this.text,
    required this.summary,
    required this.imagePath,
    required this.originalAudioPath,
    required this.summaryAudioPath,
    required this.orientation,
    required this.timings,
  });

  final String text;
  final String summary;
  final String imagePath;
  final String originalAudioPath;
  final String summaryAudioPath;
  final OcrOrientation orientation;

  /// How long each stage took, for testing and comparison.
  final Map<String, Duration> timings;
}

/// Status strings understood by ProcessingScreen.
abstract final class PhoneStage {
  static const fetched = 'QUEUED';
  static const working = 'PROCESSING';
  static const ready = 'READY';
}

/// The app-mode capture pipeline run on the phone instead of the Pi:
/// fetch the photo → ML Kit OCR → Gemini summary → phone TTS audio.
///
/// Images, text, summaries and audio stay on the phone; the only thing that
/// leaves is the extracted text, sent to Gemini (as the Pi already does).
class PhoneDocumentProcessor {
  PhoneDocumentProcessor({
    CaptureImageFetcher? fetcher,
    this._ocr,
    GeminiSummaryService? gemini,
    this._speech,
    Future<Directory> Function()? workDir,
  }) : _fetcher = fetcher ?? CaptureImageFetcher(),
       _gemini = gemini ?? GeminiSummaryService(),
       _workDir = workDir ?? _defaultWorkDir;

  final CaptureImageFetcher _fetcher;
  PageOcr? _ocr;
  final GeminiSummaryService _gemini;
  SpeechFileSynthesizer? _speech;
  final Future<Directory> Function() _workDir;

  static Future<Directory> _defaultWorkDir() async {
    final tmp = await getTemporaryDirectory();
    return Directory('${tmp.path}/phone_captures');
  }

  Future<PhoneProcessingResult> process({
    required String imageUrl,
    required int pageNumber,
    required String geminiKey,
    void Function(String status)? onStatus,
  }) async {
    final timings = <String, Duration>{};
    final watch = Stopwatch()..start();
    Duration lap() {
      final d = watch.elapsed;
      watch.reset();
      return d;
    }

    final root = await _workDir();
    final dir = Directory(
      '${root.path}/page_${pageNumber}_${DateTime.now().millisecondsSinceEpoch}',
    );
    await dir.create(recursive: true);

    final image = await _fetcher.fetch(
      imageUrl,
      File('${dir.path}/captured_image.jpg'),
    );
    timings['fetch'] = lap();
    onStatus?.call(PhoneStage.fetched);

    final ocr = _ocr ??= PageOcr();
    final page = await ocr.read(image.path);
    timings['ocr'] = lap();
    if (page.text.isEmpty) throw const OcrFailureException();
    onStatus?.call(PhoneStage.working);

    final summary = await _gemini.summarize(page.text, apiKey: geminiKey);
    timings['summary'] = lap();

    final speech = _speech ??= DeviceSpeechSynthesizer();
    final originalAudio = '${dir.path}/original_audio.wav';
    final summaryAudio = '${dir.path}/summary_audio.wav';
    await speech.synthesize(page.text, originalAudio);
    await speech.synthesize(summary, summaryAudio);
    timings['audio'] = lap();
    onStatus?.call(PhoneStage.ready);

    return PhoneProcessingResult(
      text: page.text,
      summary: summary,
      imagePath: image.path,
      originalAudioPath: originalAudio,
      summaryAudioPath: summaryAudio,
      orientation: page.orientation,
      timings: timings,
    );
  }

  Future<void> close() async => _ocr?.close();
}
