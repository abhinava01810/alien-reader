/// Ports of the Pi reader's text helpers (server.py `clean_ocr_text` and
/// `calculate_ocr_quality`), so on-phone results are cleaned and judged the
/// same way the Pi does.
library;

/// Normalises line endings, drops control characters, collapses runs of
/// spaces and blank lines, trims every line and the whole text.
String cleanOcrText(String? text) {
  if (text == null || text.isEmpty) return '';
  var t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  t = String.fromCharCodes(
    t.runes.where((c) => c == 0x0A || c == 0x09 || !_isControl(c)),
  );
  t = t.replaceAll(RegExp(r'[ \t]+'), ' ');
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  final lines = t.split('\n').map((l) => l.trim()).toList();
  while (lines.isNotEmpty && lines.first.isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n').trim();
}

bool _isControl(int c) => c < 0x20 || (c >= 0x7F && c < 0xA0);

final RegExp _alnum = RegExp(r'[\p{L}\p{N}]', unicode: true);
final RegExp _letter = RegExp(r'\p{L}', unicode: true);

int alphanumericCount(String text) => _alnum.allMatches(text).length;

/// Pi's quality score, used only to choose between the upright and the
/// rotated reading. [confidence] is 0–100 (the Pi uses Tesseract's mean
/// word confidence; ML Kit's line confidences are scaled to match).
double ocrQualityScore(String text, double confidence) {
  final cleaned = cleanOcrText(text);
  if (cleaned.isEmpty) return 0;
  final chars = cleaned.length;
  final useful = alphanumericCount(cleaned) / chars;
  final letters = _letter.allMatches(cleaned).length / chars;
  final length = (chars / 150.0).clamp(0.0, 1.0);
  return confidence * 0.65 + useful * 20.0 + letters * 10.0 + length * 10.0;
}

/// The Pi treats fewer than 3 letters/digits as "no usable text".
bool hasUsableText(String text) => alphanumericCount(text) >= 3;
