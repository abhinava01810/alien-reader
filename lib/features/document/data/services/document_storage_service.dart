import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_document.dart';
import 'pdf_service.dart';

/// Manages all local file I/O for saved scans.
///
/// Each saved document lives in its own folder:
///   `appDocDir/alien_reader_docs/doc_id/`
///     captured_image.jpg, original_text.txt, original_text.pdf,
///     ai_summary.txt, ai_summary.pdf,
///     original_audio.wav, summary_audio.wav
///
/// Metadata is persisted as a JSON list in SharedPreferences under
/// [_prefsKey] so it survives app restarts.
class DocumentStorageService {
  DocumentStorageService({PdfService? pdfService})
    : _pdf = pdfService ?? PdfService();

  final PdfService _pdf;

  static const String _prefsKey = 'alien_reader_saved_documents';

  /// Number of the last scan saved on this phone. Never reset, so every
  /// title is different even though the reader restarts page numbers each
  /// session.
  static const String _scanCounterKey = 'alien_reader_scan_counter';

  /// Next number for [scanTitle]. Starts after the documents already saved.
  @visibleForTesting
  Future<int> nextScanNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final last =
        prefs.getInt(_scanCounterKey) ?? (await loadAllDocuments()).length;
    final next = last + 1;
    await prefs.setInt(_scanCounterKey, next);
    return next;
  }

  /// "Scan 12, 8 Nov 2026 at 00:03": short, unique, and reads clearly in a
  /// screen reader.
  static String scanTitle(int number, DateTime at) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Scan $number, ${at.day} ${months[at.month - 1]} ${at.year} '
        'at ${two(at.hour)}:${two(at.minute)}';
  }

  // ─── Root directory ───────────────────────────────────────────────

  Future<Directory> _docsRoot() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/alien_reader_docs');
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _docDir(String id) async {
    final root = await _docsRoot();
    final dir = Directory('${root.path}/doc_$id');
    await dir.create(recursive: true);
    return dir;
  }

  // ─── Save complete document ───────────────────────────────────────

  /// Downloads all files from the Pi and saves them locally.
  ///
  /// Returns the [SavedDocument] metadata on success.
  /// Throws on unrecoverable errors; partial failures (e.g. audio
  /// download failure) are silently tolerated.
  Future<SavedDocument> saveCompleteDocument({
    required String originalText,
    required String summaryText,
    int? pageNumber,
    String? imageUrl,
    String? originalAudioUrl,
    String? summaryAudioUrl,
    String? documentTitle,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final dir = await _docDir(id);
    final now = DateTime.now();
    final title = documentTitle ?? scanTitle(await nextScanNumber(), now);

    // ── Download captured image ───────────────────────────────────
    String? imagePath;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      imagePath = '${dir.path}/captured_image.jpg';
      try {
        await _downloadFile(imageUrl, imagePath);
      } catch (e) {
        imagePath = null; // tolerate failure, will fallback to remote URL
      }
    }

    // ── Save TXT files ────────────────────────────────────────────
    final originalTxtPath = '${dir.path}/original_text.txt';
    await _writeText(originalText, originalTxtPath);

    final summaryTxtPath = '${dir.path}/ai_summary.txt';
    await _writeText(summaryText, summaryTxtPath);

    // ── Generate PDF files ─────────────────────────────────────────
    final originalPdfPath = '${dir.path}/original_text.pdf';
    await _pdf.generateOriginalTextPdf(
      text: originalText,
      documentTitle: title,
      captureDate: now,
      outputPath: originalPdfPath,
    );

    final summaryPdfPath = '${dir.path}/ai_summary.pdf';
    await _pdf.generateSummaryPdf(
      text: summaryText,
      documentTitle: title,
      captureDate: now,
      outputPath: summaryPdfPath,
    );

    // ── Download audio files (best-effort) ────────────────────────
    String? originalAudioPath;
    if (originalAudioUrl != null && originalAudioUrl.isNotEmpty) {
      originalAudioPath = '${dir.path}/original_audio.wav';
      try {
        await _downloadFile(originalAudioUrl, originalAudioPath);
      } catch (e) {
        originalAudioPath = null;
      }
    }

    String? summaryAudioPath;
    if (summaryAudioUrl != null && summaryAudioUrl.isNotEmpty) {
      summaryAudioPath = '${dir.path}/summary_audio.wav';
      try {
        await _downloadFile(summaryAudioUrl, summaryAudioPath);
      } catch (e) {
        summaryAudioPath = null;
      }
    }

    // ── Build and persist metadata ─────────────────────────────────
    final doc = SavedDocument(
      documentId: id,
      documentTitle: title,
      captureDate: now,
      pageNumber: pageNumber,
      imagePath: imagePath,
      originalTextPath: originalTxtPath,
      originalPdfPath: originalPdfPath,
      summaryTextPath: summaryTxtPath,
      summaryPdfPath: summaryPdfPath,
      originalAudioPath: originalAudioPath,
      summaryAudioPath: summaryAudioPath,
      originalText: originalText,
      summaryText: summaryText,
      remoteImageUrl: imageUrl,
      remoteOriginalAudioUrl: originalAudioUrl,
      remoteSummaryAudioUrl: summaryAudioUrl,
    );

    await _persistDocument(doc);
    return doc;
  }

  /// Finds a locally saved document by pageNumber if it exists.
  Future<SavedDocument?> findByPageNumber(int pageNumber) async {
    final docs = await loadAllDocuments();
    for (final doc in docs) {
      if (doc.pageNumber == pageNumber) return doc;
    }
    return null;
  }

  // ─── On-demand single-section saves ──────────────────────────────

  /// Saves only the original text as a TXT file and returns the [File].
  Future<File> saveOriginalTextAsTxt(
    String text, {
    String? docId,
    String? label,
  }) async {
    final id = docId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final dir = await _docDir(id);
    final path = '${dir.path}/${label ?? "original_text"}.txt';
    await _writeText(text, path);
    return File(path);
  }

  /// Saves only the original text as a PDF and returns the [File].
  Future<File> saveOriginalTextAsPdf(
    String text, {
    required String documentTitle,
    required DateTime captureDate,
    String? docId,
    String? label,
  }) async {
    final id = docId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final dir = await _docDir(id);
    final path = '${dir.path}/${label ?? "original_text"}.pdf';
    return _pdf.generateOriginalTextPdf(
      text: text,
      documentTitle: documentTitle,
      captureDate: captureDate,
      outputPath: path,
    );
  }

  /// Saves only the AI summary as a TXT file and returns the [File].
  Future<File> saveSummaryAsTxt(
    String text, {
    String? docId,
    String? label,
  }) async {
    final id = docId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final dir = await _docDir(id);
    final path = '${dir.path}/${label ?? "ai_summary"}.txt';
    await _writeText(text, path);
    return File(path);
  }

  /// Saves only the AI summary as a PDF and returns the [File].
  Future<File> saveSummaryAsPdf(
    String text, {
    required String documentTitle,
    required DateTime captureDate,
    String? docId,
    String? label,
  }) async {
    final id = docId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final dir = await _docDir(id);
    final path = '${dir.path}/${label ?? "ai_summary"}.pdf';
    return _pdf.generateSummaryPdf(
      text: text,
      documentTitle: documentTitle,
      captureDate: captureDate,
      outputPath: path,
    );
  }

  // ─── ZIP archive ──────────────────────────────────────────────────

  /// Creates a ZIP archive of all files belonging to [document] and
  /// saves it to a temp path. Returns the ZIP [File].
  Future<File> createZip(SavedDocument document) async {
    final archive = Archive();

    final paths = <String, String?>{
      'captured_image.jpg': document.imagePath,
      'original_text.txt': document.originalTextPath,
      'original_text.pdf': document.originalPdfPath,
      'ai_summary.txt': document.summaryTextPath,
      'ai_summary.pdf': document.summaryPdfPath,
      'original_audio.wav': document.originalAudioPath,
      'summary_audio.wav': document.summaryAudioPath,
    };

    for (final entry in paths.entries) {
      final path = entry.value;
      if (path == null) continue;
      final f = File(path);
      if (!await f.exists()) continue;
      final bytes = await f.readAsBytes();
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) throw Exception('Failed to encode ZIP archive');

    final tmpDir = await getTemporaryDirectory();
    final zipPath = '${tmpDir.path}/alien_reader_${document.documentId}.zip';
    final zipFile = File(zipPath);
    await zipFile.writeAsBytes(Uint8List.fromList(zipData));
    return zipFile;
  }

  // ─── Metadata CRUD ────────────────────────────────────────────────

  /// Loads all saved documents from SharedPreferences, newest first.
  Future<List<SavedDocument>> loadAllDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    final docs = <SavedDocument>[];
    for (final s in raw) {
      try {
        docs.add(SavedDocument.fromJsonString(s));
      } catch (_) {
        // skip corrupted entries
      }
    }
    // Sort newest first
    docs.sort((a, b) => b.captureDate.compareTo(a.captureDate));
    return docs;
  }

  /// Deletes a document's folder and removes it from SharedPreferences.
  Future<void> deleteDocument(String documentId) async {
    // Remove from prefs
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    raw.removeWhere((s) {
      try {
        final doc = SavedDocument.fromJsonString(s);
        return doc.documentId == documentId;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_prefsKey, raw);

    // Delete folder
    try {
      final root = await _docsRoot();
      final dir = Directory('${root.path}/doc_$documentId');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // best-effort
    }
  }

  // ─── Private helpers ──────────────────────────────────────────────

  Future<void> _persistDocument(SavedDocument doc) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    raw.add(doc.toJsonString());
    await prefs.setStringList(_prefsKey, raw);
  }

  Future<void> _downloadFile(String url, String destPath) async {
    // Phone-processed captures are already on the phone: copy, don't fetch.
    if (url.startsWith('file://')) {
      final src = File.fromUri(Uri.parse(url));
      await File(destPath).parent.create(recursive: true);
      await src.copy(destPath);
      return;
    }
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode} for $url');
    }
    final file = File(destPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(response.bodyBytes);
  }

  Future<void> _writeText(String text, String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(text, encoding: utf8);
  }
}
