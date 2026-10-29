import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/models/document_output.dart';
import '../../../shared/widgets/app_card.dart';
import '../data/models/saved_document.dart';
import '../data/services/document_share_service.dart';
import '../data/services/document_storage_service.dart';

/// Shows the full results of a processed document:
/// - Real captured image from the Pi camera
/// - OCR extracted text — with Read Aloud, Save, Share
/// - AI summary — with Read Aloud, Save, Share
/// - Save Complete Document button (downloads everything locally)
class DocumentResultsScreen extends StatefulWidget {
  const DocumentResultsScreen({
    super.key,
    required this.output,
    this.savedDocument,
  });

  final DocumentOutput output;
  final SavedDocument? savedDocument;

  @override
  State<DocumentResultsScreen> createState() => _DocumentResultsScreenState();
}

class _DocumentResultsScreenState extends State<DocumentResultsScreen> {
  // ── Services ──────────────────────────────────────────────────────
  final _storage = DocumentStorageService();
  final _share = DocumentShareService();

  // ── TTS ───────────────────────────────────────────────────────────
  late final FlutterTts _tts;
  String? _activeSection; // 'original' | 'summary' | null

  // ── Loading states ────────────────────────────────────────────────
  bool _savingComplete = false;

  // ── Saved doc ref (after full save) ──────────────────────────────
  SavedDocument? _savedDocument;

  @override
  void initState() {
    super.initState();
    _savedDocument = widget.savedDocument;
    _initTts();
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _activeSection = null);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _activeSection = null);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _activeSection = null);
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  // ─── TTS ──────────────────────────────────────────────────────────

  Future<void> _toggleSpeak(String text, String section) async {
    if (_activeSection == section) {
      await _tts.stop();
      setState(() => _activeSection = null);
      return;
    }
    await _tts.stop();
    setState(() => _activeSection = section);
    await _tts.speak(text);
  }

  // ─── Copy ─────────────────────────────────────────────────────────

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _snack('Copied to clipboard');
  }

  // ─── Save helpers ─────────────────────────────────────────────────

  Future<void> _showSaveOptions(
    BuildContext ctx,
    String text,
    String section, // 'original' | 'summary'
  ) async {
    await showModalBottomSheet<void>(
      context: ctx,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_snippet_rounded),
              title: Text('Save as Text (.txt) — ${_sectionLabel(section)}'),
              onTap: () {
                Navigator.pop(ctx);
                _saveAsTxt(text, section);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: Text('Save as PDF (.pdf) — ${_sectionLabel(section)}'),
              onTap: () {
                Navigator.pop(ctx);
                _saveAsPdf(text, section);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAsTxt(String text, String section) async {
    _snackLoading('Saving…');
    try {
      File file;
      if (section == 'original') {
        file = await _storage.saveOriginalTextAsTxt(
          text,
          label: 'original_text',
        );
      } else {
        file = await _storage.saveSummaryAsTxt(text, label: 'ai_summary');
      }
      if (!mounted) return;
      _snack('Saved: ${_filename(file.path)}', success: true);
    } catch (e) {
      if (mounted) _snack('Save failed: $e', success: false);
    }
  }

  Future<void> _saveAsPdf(String text, String section) async {
    _snackLoading('Generating PDF…');
    try {
      File file;
      final now = DateTime.now();
      if (section == 'original') {
        file = await _storage.saveOriginalTextAsPdf(
          text,
          documentTitle: 'Scan ${_shortDate(now)}',
          captureDate: now,
          label: 'original_text',
        );
      } else {
        file = await _storage.saveSummaryAsPdf(
          text,
          documentTitle: 'Scan ${_shortDate(now)}',
          captureDate: now,
          label: 'ai_summary',
        );
      }
      if (!mounted) return;
      _snack('PDF saved: ${_filename(file.path)}', success: true);
    } catch (e) {
      if (mounted) _snack('PDF generation failed: $e', success: false);
    }
  }

  // ─── Share helpers ────────────────────────────────────────────────

  Future<void> _showShareOptions(
    BuildContext ctx,
    String text,
    String section, // 'original' | 'summary'
  ) async {
    final audioUrl = section == 'original'
        ? widget.output.originalAudioUrl
        : widget.output.summaryAudioUrl;

    await showModalBottomSheet<void>(
      context: ctx,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Share — ${_sectionLabel(section)}',
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields_rounded),
              title: const Text('Share Text'),
              onTap: () {
                Navigator.pop(ctx);
                _shareText(text, section);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded),
              title: const Text('Share as PDF'),
              onTap: () {
                Navigator.pop(ctx);
                _shareAsPdf(text, section);
              },
            ),
            if (audioUrl != null)
              ListTile(
                leading: const Icon(Icons.audio_file_rounded),
                title: const Text('Share Audio'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareAudio(audioUrl, section);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _shareText(String text, String section) async {
    try {
      final msg = section == 'original'
          ? DocumentShareService.buildOriginalTextMessage(text)
          : DocumentShareService.buildSummaryMessage(text);
      await _share.shareText(msg);
    } catch (e) {
      if (mounted) _snack('Share failed: $e', success: false);
    }
  }

  Future<void> _shareAsPdf(String text, String section) async {
    _snackLoading('Generating PDF for sharing…');
    try {
      final now = DateTime.now();
      File file;
      if (section == 'original') {
        file = await _storage.saveOriginalTextAsPdf(
          text,
          documentTitle: 'Scan ${_shortDate(now)}',
          captureDate: now,
        );
      } else {
        file = await _storage.saveSummaryAsPdf(
          text,
          documentTitle: 'Scan ${_shortDate(now)}',
          captureDate: now,
        );
      }
      await _share.shareFile(file, subject: 'Naadh');
    } catch (e) {
      if (mounted) _snack('Share failed: $e', success: false);
    }
  }

  Future<void> _shareAudio(String audioUrl, String section) async {
    _snackLoading('Preparing audio for share…');
    try {
      // 1. If saved document exists and local audio file exists, share directly
      if (_savedDocument != null) {
        final localPath = section == 'original'
            ? _savedDocument!.originalAudioPath
            : _savedDocument!.summaryAudioPath;
        if (localPath != null && File(localPath).existsSync()) {
          await _share.shareFile(File(localPath), subject: 'Naadh Audio');
          return;
        }
      }

      // 2. Download to temporary file without creating a SavedDocument
      final uri = Uri.parse(audioUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final tmpDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tmpDir.path}/${section}_audio_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await tempFile.writeAsBytes(response.bodyBytes);

      await _share.shareFile(tempFile, subject: 'Naadh Audio');
    } catch (e) {
      if (mounted) _snack('Audio share failed: $e', success: false);
    }
  }

  // ─── Save complete document ───────────────────────────────────────

  Future<void> _saveCompleteDocument() async {
    setState(() => _savingComplete = true);
    _snackLoading('Saving complete document…');

    try {
      final doc = await _storage.saveCompleteDocument(
        originalText: widget.output.originalText,
        summaryText: widget.output.summaryText,
        imageUrl: widget.output.imageUrl,
        originalAudioUrl: widget.output.originalAudioUrl,
        summaryAudioUrl: widget.output.summaryAudioUrl,
      );

      if (!mounted) return;
      setState(() {
        _savedDocument = doc;
        _savingComplete = false;
      });
      _snack(
        'Document saved to Files tab!',
        success: true,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _savingComplete = false);
        _snack('Save failed: $e', success: false);
      }
    }
  }

  // ─── Share complete document (ZIP) ────────────────────────────────

  Future<void> _shareCompleteDocument() async {
    if (_savedDocument == null) {
      _snack('Save the document first, then share it.');
      return;
    }
    _snackLoading('Creating ZIP archive…');
    try {
      final zip = await _storage.createZip(_savedDocument!);
      await _share.shareFile(zip, subject: 'Naadh — Complete Scan');
    } catch (e) {
      if (mounted) _snack('Share failed: $e', success: false);
    }
  }

  // ─── SnackBar helpers ─────────────────────────────────────────────

  void _snack(
    String msg, {
    bool? success,
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: success == true
              ? AppColors.success
              : success == false
              ? AppColors.danger
              : null,
          duration: duration,
        ),
      );
  }

  void _snackLoading(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Text(msg),
            ],
          ),
          duration: const Duration(seconds: 60),
        ),
      );
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Results'),
        actions: [
          IconButton(
            onPressed: () => _copyText(
              'EXTRACTED TEXT:\n${widget.output.originalText}\n\n'
              'AI SUMMARY:\n${widget.output.summaryText}',
            ),
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy all text',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.output.imageUrl != null ||
              _savedDocument?.imagePath != null) ...[
            _CapturedImageCard(
              imageUrl: widget.output.imageUrl ?? '',
              localImagePath: _savedDocument?.imagePath,
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Extracted text section ────────────────────────────────
          _SectionCard(
            title: 'Extracted Text',
            icon: Icons.text_snippet_rounded,
            iconColor: context.accent,
            text: widget.output.originalText,
            isReading: _activeSection == 'original',
            onReadAloud: () =>
                _toggleSpeak(widget.output.originalText, 'original'),
            onCopy: () => _copyText(widget.output.originalText),
            onSave: () => _showSaveOptions(
              context,
              widget.output.originalText,
              'original',
            ),
            onShare: () => _showShareOptions(
              context,
              widget.output.originalText,
              'original',
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── AI summary section ────────────────────────────────────
          _SectionCard(
            title: 'AI Summary',
            icon: Icons.auto_awesome_rounded,
            iconColor: AppColors.orange,
            text: widget.output.summaryText,
            isReading: _activeSection == 'summary',
            onReadAloud: () =>
                _toggleSpeak(widget.output.summaryText, 'summary'),
            onCopy: () => _copyText(widget.output.summaryText),
            onSave: () =>
                _showSaveOptions(context, widget.output.summaryText, 'summary'),
            onShare: () => _showShareOptions(
              context,
              widget.output.summaryText,
              'summary',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Save Complete Document ────────────────────────────────
          _savedDocument == null
              ? FilledButton.icon(
                  onPressed: _savingComplete ? null : _saveCompleteDocument,
                  icon: _savingComplete
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _savingComplete ? 'Saving…' : 'Save Complete Document',
                  ),
                )
              : Column(
                  children: [
                    // Already saved — show share complete option
                    OutlinedButton.icon(
                      onPressed: _shareCompleteDocument,
                      icon: const Icon(Icons.folder_zip_rounded),
                      label: const Text('Share Complete Document (ZIP)'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Saved to Files tab',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          const SizedBox(height: AppSpacing.md),

          // ── Return home ───────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_rounded),
            label: const Text('Return Home'),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  // ─── Utils ────────────────────────────────────────────────────────

  String _sectionLabel(String section) =>
      section == 'original' ? 'Extracted Text' : 'AI Summary';

  String _filename(String path) => path.split('/').last.split(r'\').last;

  String _shortDate(DateTime dt) {
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
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Captured image card
// ─────────────────────────────────────────────────────────────────────────────

class _CapturedImageCard extends StatelessWidget {
  const _CapturedImageCard({required this.imageUrl, this.localImagePath});

  final String imageUrl;
  final String? localImagePath;

  @override
  Widget build(BuildContext context) {
    final hasLocalImage =
        localImagePath != null && File(localImagePath!).existsSync();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Captured Document',
            icon: Icons.document_scanner_rounded,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppShapes.cardRadius),
            child: hasLocalImage
                ? Image.file(
                    File(localImagePath!),
                    fit: BoxFit.contain,
                    width: double.infinity,
                  )
                : Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return SizedBox(
                        height: 220,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!
                                : null,
                            color: context.accent,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 180,
                        decoration: BoxDecoration(
                          color: context.surfaceElevated,
                          borderRadius: BorderRadius.circular(
                            AppShapes.cardRadius,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.image_not_supported_rounded,
                                color: context.mutedText,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Image unavailable',
                                style: TextStyle(
                                  color: context.mutedText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section card — text + action buttons
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.isReading,
    required this.onReadAloud,
    required this.onCopy,
    required this.onSave,
    required this.onShare,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final String text;
  final bool isReading;
  final VoidCallback onReadAloud;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────────────
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              // Copy
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: 'Copy',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkTextMuted
                    : context.mutedText,
              ),
              const SizedBox(width: 4),
              // TTS toggle
              _TtsButton(isReading: isReading, onPressed: onReadAloud),
            ],
          ),

          const Divider(height: 16),

          // ── Action buttons row ─────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.save_rounded,
                  label: 'Save ▼',
                  onPressed: onSave,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.share_rounded,
                  label: 'Share ▼',
                  onPressed: onShare,
                  outlined: true,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 8),
          const SizedBox(height: 6),

          // ── Text body ─────────────────────────────────────────────
          SelectableText(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.7),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated TTS button
// ─────────────────────────────────────────────────────────────────────────────

class _TtsButton extends StatelessWidget {
  const _TtsButton({required this.isReading, required this.onPressed});
  final bool isReading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isReading
            ? AppColors.orange.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppShapes.cardRadius),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            isReading ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
            key: ValueKey(isReading),
            color: isReading
                ? AppColors.orange
                : (Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkTextMuted
                      : context.mutedText),
            size: 22,
          ),
        ),
        tooltip: isReading ? 'Stop reading' : 'Read aloud',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small action button (Save / Share)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.outlined = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}
