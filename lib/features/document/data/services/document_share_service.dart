import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// Thin wrapper around [Share] that opens the Android share sheet
/// for text, files (TXT, PDF, WAV), and ZIP archives.
class DocumentShareService {
  // ─── Text ─────────────────────────────────────────────────────────

  /// Opens the native share sheet with plain text.
  Future<void> shareText(String text, {String? subject}) async {
    await Share.share(text, subject: subject ?? 'Naadh');
  }

  // ─── Files ────────────────────────────────────────────────────────

  /// Opens the native share sheet with a single file.
  ///
  /// [mimeType] examples: 'application/pdf', 'text/plain', 'audio/wav',
  /// 'application/zip'
  Future<void> shareFile(File file, {String? subject, String? mimeType}) async {
    if (!await file.exists()) {
      throw Exception('File not found: ${file.path}');
    }
    await Share.shareXFiles([
      XFile(file.path, mimeType: mimeType ?? _mimeFromExtension(file.path)),
    ], subject: subject ?? 'Naadh');
  }

  /// Opens the native share sheet with multiple files.
  Future<void> shareFiles(List<File> files, {String? subject}) async {
    final xFiles = <XFile>[];
    for (final f in files) {
      if (await f.exists()) {
        xFiles.add(XFile(f.path, mimeType: _mimeFromExtension(f.path)));
      }
    }
    if (xFiles.isEmpty) throw Exception('No files available to share.');
    await Share.shareXFiles(xFiles, subject: subject ?? 'Naadh');
  }

  // ─── Formatted text helpers ───────────────────────────────────────

  /// Builds the standard share message for OCR text.
  static String buildOriginalTextMessage(String originalText) =>
      'Naadh Document Scan\n\nExtracted Text:\n\n$originalText';

  /// Builds the standard share message for AI summary.
  static String buildSummaryMessage(String summaryText) =>
      'Naadh Document Scan\n\nAI Summary:\n\n$summaryText';

  // ─── MIME detection ───────────────────────────────────────────────

  String _mimeFromExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    return 'application/octet-stream';
  }
}
