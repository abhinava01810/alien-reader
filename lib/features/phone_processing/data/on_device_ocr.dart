import 'dart:io';
import 'dart:isolate';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import 'reading_order.dart';
import 'text_cleaning.dart';

/// One OCR pass over one image file.
class OcrReading {
  const OcrReading(this.text, {this.confidence});

  final String text;

  /// Mean line confidence, 0–100, when the engine reports it.
  final double? confidence;
}

/// Reads text from an image file. ML Kit in the app, a fake in tests.
abstract interface class OcrEngine {
  Future<OcrReading> read(String imagePath);
  Future<void> close();
}

/// Google ML Kit text recognition, Latin script, running entirely on the
/// phone with the model bundled in the app (no download, no network).
class MlKitOcrEngine implements OcrEngine {
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  @override
  Future<OcrReading> read(String imagePath) async {
    final result = await _recognizer.processImage(
      InputImage.fromFilePath(imagePath),
    );
    final confidences = [
      for (final block in result.blocks)
        for (final line in block.lines)
          if (line.confidence != null) line.confidence!,
    ];
    final mean = confidences.isEmpty
        ? null
        : confidences.reduce((a, b) => a + b) / confidences.length * 100;
    return OcrReading(
      readingOrderText([
        for (final block in result.blocks)
          for (final line in block.lines) LineBox(line.text, line.cornerPoints),
      ]),
      confidence: mean,
    );
  }

  @override
  Future<void> close() => _recognizer.close();
}

/// Writes a rotated copy of an image. Real decoding runs off the UI thread.
abstract interface class ImageRotator {
  /// [quarterTurnsClockwise]: 1 = 90° clockwise, 3 = 90° counter-clockwise.
  Future<String> rotate(String imagePath, int quarterTurnsClockwise);
}

class IsolateImageRotator implements ImageRotator {
  @override
  Future<String> rotate(String imagePath, int quarterTurnsClockwise) {
    final out =
        '${imagePath.substring(0, imagePath.lastIndexOf('.'))}'
        '_rot${quarterTurnsClockwise * 90}.jpg';
    return Isolate.run(() {
      final decoded = img.decodeImage(File(imagePath).readAsBytesSync());
      if (decoded == null) {
        throw const FormatException('Could not decode captured image.');
      }
      final rotated = img.copyRotate(
        decoded,
        angle: quarterTurnsClockwise * 90,
      );
      File(out).writeAsBytesSync(img.encodeJpg(rotated, quality: 92));
      return out;
    });
  }
}

/// Which way the selected reading was taken.
enum OcrOrientation { original, rotatedCounterClockwise, rotatedClockwise }

class PageOcrResult {
  const PageOcrResult(this.text, this.orientation, this.score);

  /// Cleaned text; empty when nothing usable was found.
  final String text;
  final OcrOrientation orientation;
  final double score;
}

/// Mirrors the Pi's `extract_text_from_image`: read the photo as captured
/// and rotated 90° counter-clockwise (the camera frame can be sideways),
/// keep the better-scoring reading, clean it, and reject tiny results.
/// Additionally tries 90° clockwise when neither found usable text, which
/// the Pi never does.
class PageOcr {
  PageOcr({OcrEngine? engine, ImageRotator? rotator})
    : _engine = engine ?? MlKitOcrEngine(),
      _rotator = rotator ?? IsolateImageRotator();

  final OcrEngine _engine;
  final ImageRotator _rotator;

  /// Confidence used when the engine reports none, so the comparison falls
  /// back to how much real text each orientation produced.
  static const double _neutralConfidence = 60;

  Future<PageOcrResult> read(String imagePath) async {
    final candidates = <PageOcrResult>[
      await _score(imagePath, OcrOrientation.original),
      await _score(
        await _rotator.rotate(imagePath, 3),
        OcrOrientation.rotatedCounterClockwise,
      ),
    ];
    if (!candidates.any((c) => hasUsableText(c.text))) {
      candidates.add(
        await _score(
          await _rotator.rotate(imagePath, 1),
          OcrOrientation.rotatedClockwise,
        ),
      );
    }
    // Ties keep the earlier (upright) reading, as the Pi does.
    var best = candidates.first;
    for (final c in candidates.skip(1)) {
      if (c.score > best.score) best = c;
    }
    if (!hasUsableText(best.text)) {
      return PageOcrResult('', best.orientation, best.score);
    }
    return best;
  }

  Future<PageOcrResult> _score(String path, OcrOrientation o) async {
    final reading = await _engine.read(path);
    final text = cleanOcrText(reading.text);
    final score = ocrQualityScore(
      text,
      reading.confidence ?? _neutralConfidence,
    );
    return PageOcrResult(text, o, score);
  }

  Future<void> close() => _engine.close();
}
