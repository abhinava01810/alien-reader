import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../data/models/saved_document.dart';
import '../data/services/document_share_service.dart';
import '../data/services/document_storage_service.dart';

/// The saved audio file for [section] ('original' or 'summary'), or null
/// when it is missing or empty and the text has to be spoken instead.
String? savedAudioPathFor(SavedDocument doc, String section) {
  final path = section == 'original'
      ? doc.originalAudioPath
      : doc.summaryAudioPath;
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  // A WAV header alone (44 bytes) has no sound in it.
  if (!file.existsSync() || file.lengthSync() <= 44) return null;
  return path;
}

/// Detail view for a locally saved [SavedDocument].
///
/// Works entirely offline — reads files from local storage.
/// Provides view, TTS, save (re-save), share, and delete actions.
class SavedDocumentDetailScreen extends StatefulWidget {
  const SavedDocumentDetailScreen({super.key, required this.document});

  final SavedDocument document;

  @override
  State<SavedDocumentDetailScreen> createState() =>
      _SavedDocumentDetailScreenState();
}

class _SavedDocumentDetailScreenState extends State<SavedDocumentDetailScreen> {
  final _storage = DocumentStorageService();
  final _share = DocumentShareService();
  late final FlutterTts _tts;
  AudioPlayer? _player;
  StreamSubscription<void>? _playerDone;
  String? _activeSection;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
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
    _playerDone?.cancel();
    _player?.dispose();
    super.dispose();
  }

  // ─── TTS ──────────────────────────────────────────────────────────

  /// Plays the section's saved audio. Speaks the text with the phone's
  /// voice only when that file is missing or will not play.
  Future<void> _toggleSpeak(String text, String section) async {
    final wasActive = _activeSection == section;
    await _stopReading();
    if (wasActive) {
      if (mounted) setState(() => _activeSection = null);
      return;
    }
    if (!mounted) return;
    setState(() => _activeSection = section);

    final path = savedAudioPathFor(widget.document, section);
    if (path != null) {
      try {
        final player = _player ??= _createPlayer();
        await player.play(DeviceFileSource(path));
        return;
      } catch (_) {
        // Fall back to speaking the text below.
      }
    }
    await _tts.speak(text);
  }

  AudioPlayer _createPlayer() {
    final player = AudioPlayer();
    _playerDone = player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _activeSection = null);
    });
    return player;
  }

  Future<void> _stopReading() async {
    await _tts.stop();
    try {
      await _player?.stop();
    } catch (_) {}
  }

  // ─── Share ────────────────────────────────────────────────────────

  Future<void> _shareText(String text, String section) async {
    try {
      final msg = section == 'original'
          ? DocumentShareService.buildOriginalTextMessage(text)
          : DocumentShareService.buildSummaryMessage(text);
      await _share.shareText(msg);
    } catch (e) {
      _snack('Share failed: $e', success: false);
    }
  }

  Future<void> _shareFile(String? path, String description) async {
    if (path == null || !File(path).existsSync()) {
      _snack('$description not found on this device.', success: false);
      return;
    }
    try {
      await _share.shareFile(File(path));
    } catch (e) {
      _snack('Share failed: $e', success: false);
    }
  }

  Future<void> _shareCompleteZip() async {
    _snackLoading('Creating ZIP archive…');
    try {
      final zip = await _storage.createZip(widget.document);
      await _share.shareFile(
        zip,
        subject: 'Naadh — ${widget.document.documentTitle}',
      );
    } catch (e) {
      if (mounted) _snack('Share failed: $e', success: false);
    }
  }

  // ─── Delete ───────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Document?'),
        content: Text(
          'This will permanently delete "${widget.document.documentTitle}" '
          'and all its files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _storage.deleteDocument(widget.document.documentId);
      if (!mounted) return;
      _snack('Document deleted', success: true);
      Navigator.of(context).pop(true); // signal refresh to caller
    } catch (e) {
      if (mounted) _snack('Delete failed: $e', success: false);
    }
  }

  // ─── Snack helpers ────────────────────────────────────────────────

  void _snack(String msg, {bool? success}) {
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
    final doc = widget.document;
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.documentTitle, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppColors.danger,
            tooltip: 'Delete document',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Document info chip ─────────────────────────────────────
          _MetaChip(date: doc.captureDate),
          const SizedBox(height: AppSpacing.md),

          // ── Captured image (local file) ────────────────────────────
          if (doc.imagePath != null) ...[
            _LocalImageCard(imagePath: doc.imagePath!),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Extracted text ─────────────────────────────────────────
          _SavedSectionCard(
            title: 'Extracted Text',
            icon: Icons.text_snippet_rounded,
            iconColor: context.accent,
            text: doc.originalText,
            isReading: _activeSection == 'original',
            onReadAloud: () => _toggleSpeak(doc.originalText, 'original'),
            actions: [
              _SectionAction(
                icon: Icons.volume_up_rounded,
                label: _activeSection == 'original' ? 'Stop' : 'Read',
                onTap: () => _toggleSpeak(doc.originalText, 'original'),
                active: _activeSection == 'original',
              ),
              _SectionAction(
                icon: Icons.text_snippet_rounded,
                label: 'Save TXT',
                onTap: () async {
                  _snackLoading('Saving…');
                  try {
                    final f = await _storage.saveOriginalTextAsTxt(
                      doc.originalText,
                      docId: doc.documentId,
                    );
                    if (mounted) {
                      _snack('Saved: ${f.path.split('/').last}', success: true);
                    }
                  } catch (e) {
                    if (mounted) _snack('Failed: $e', success: false);
                  }
                },
              ),
              _SectionAction(
                icon: Icons.picture_as_pdf_rounded,
                label: 'Save PDF',
                onTap: () async {
                  _snackLoading('Generating PDF…');
                  try {
                    final f = await _storage.saveOriginalTextAsPdf(
                      doc.originalText,
                      documentTitle: doc.documentTitle,
                      captureDate: doc.captureDate,
                      docId: doc.documentId,
                    );
                    if (mounted) {
                      _snack(
                        'PDF saved: ${f.path.split('/').last}',
                        success: true,
                      );
                    }
                  } catch (e) {
                    if (mounted) _snack('Failed: $e', success: false);
                  }
                },
              ),
              _SectionAction(
                icon: Icons.share_rounded,
                label: 'Share Text',
                onTap: () => _shareText(doc.originalText, 'original'),
              ),
              _SectionAction(
                icon: Icons.picture_as_pdf_rounded,
                label: 'Share PDF',
                onTap: () => _shareFile(doc.originalPdfPath, 'PDF'),
              ),
              if (doc.originalAudioPath != null)
                _SectionAction(
                  icon: Icons.audio_file_rounded,
                  label: 'Share Audio',
                  onTap: () =>
                      _shareFile(doc.originalAudioPath, 'Original Audio'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── AI summary ─────────────────────────────────────────────
          _SavedSectionCard(
            title: 'AI Summary',
            icon: Icons.auto_awesome_rounded,
            iconColor: AppColors.orange,
            text: doc.summaryText,
            isReading: _activeSection == 'summary',
            onReadAloud: () => _toggleSpeak(doc.summaryText, 'summary'),
            actions: [
              _SectionAction(
                icon: Icons.volume_up_rounded,
                label: _activeSection == 'summary' ? 'Stop' : 'Read',
                onTap: () => _toggleSpeak(doc.summaryText, 'summary'),
                active: _activeSection == 'summary',
              ),
              _SectionAction(
                icon: Icons.text_snippet_rounded,
                label: 'Save TXT',
                onTap: () async {
                  _snackLoading('Saving…');
                  try {
                    final f = await _storage.saveSummaryAsTxt(
                      doc.summaryText,
                      docId: doc.documentId,
                    );
                    if (mounted) {
                      _snack('Saved: ${f.path.split('/').last}', success: true);
                    }
                  } catch (e) {
                    if (mounted) _snack('Failed: $e', success: false);
                  }
                },
              ),
              _SectionAction(
                icon: Icons.picture_as_pdf_rounded,
                label: 'Save PDF',
                onTap: () async {
                  _snackLoading('Generating PDF…');
                  try {
                    final f = await _storage.saveSummaryAsPdf(
                      doc.summaryText,
                      documentTitle: doc.documentTitle,
                      captureDate: doc.captureDate,
                      docId: doc.documentId,
                    );
                    if (mounted) {
                      _snack(
                        'PDF saved: ${f.path.split('/').last}',
                        success: true,
                      );
                    }
                  } catch (e) {
                    if (mounted) _snack('Failed: $e', success: false);
                  }
                },
              ),
              _SectionAction(
                icon: Icons.share_rounded,
                label: 'Share Text',
                onTap: () => _shareText(doc.summaryText, 'summary'),
              ),
              _SectionAction(
                icon: Icons.picture_as_pdf_rounded,
                label: 'Share PDF',
                onTap: () => _shareFile(doc.summaryPdfPath, 'Summary PDF'),
              ),
              if (doc.summaryAudioPath != null)
                _SectionAction(
                  icon: Icons.audio_file_rounded,
                  label: 'Share Audio',
                  onTap: () =>
                      _shareFile(doc.summaryAudioPath, 'Summary Audio'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Share complete document ────────────────────────────────
          FilledButton.icon(
            onPressed: _shareCompleteZip,
            icon: const Icon(Icons.folder_zip_rounded),
            label: const Text('Share Complete Document (ZIP)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete Document'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Meta info chip
// ─────────────────────────────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final months = [
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
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    final label = '${date.day} ${months[date.month - 1]} ${date.year} · $h:$m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 14,
            color: context.mutedText,
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: context.mutedText)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local image card (reads from device file system)
// ─────────────────────────────────────────────────────────────────────────────

class _LocalImageCard extends StatelessWidget {
  const _LocalImageCard({required this.imagePath});
  final String imagePath;

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);
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
            child: file.existsSync()
                ? Image.file(file, fit: BoxFit.contain, width: double.infinity)
                : Builder(
                    builder: (context) {
                      return Container(
                        height: 160,
                        color: context.surfaceElevated,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.image_not_supported_rounded,
                                size: 32,
                                color: context.mutedText,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Image file not found',
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
// Section card for saved document (with action chips)
// ─────────────────────────────────────────────────────────────────────────────

class _SavedSectionCard extends StatelessWidget {
  const _SavedSectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.isReading,
    required this.onReadAloud,
    required this.actions,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final String text;
  final bool isReading;
  final VoidCallback onReadAloud;
  final List<_SectionAction> actions;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const Divider(height: 16),
          // Action chips in a horizontal scroll
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: actions.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final action = actions[index];
                return ActionChip(
                  avatar: Icon(
                    action.icon,
                    size: 15,
                    color: action.active ? AppColors.orange : context.accent,
                  ),
                  label: Text(
                    action.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: action.active ? AppColors.orange : null,
                      fontWeight: action.active
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                  onPressed: action.onTap,
                  backgroundColor: action.active
                      ? AppColors.orange.withValues(alpha: 0.1)
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 8),
          const SizedBox(height: 6),
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
// Action descriptor
// ─────────────────────────────────────────────────────────────────────────────

class _SectionAction {
  const _SectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
}
