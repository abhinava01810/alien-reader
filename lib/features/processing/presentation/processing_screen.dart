import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';

enum _PiStatus { capturing, queued, processing, ready, failed }

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    super.key,
    this.onCompleted,
    this.onProcess,
    this.pageNumber = 1,
    this.imageUrl,
    this.statusStream,
  });

  final VoidCallback? onCompleted;
  final Future<void> Function()? onProcess;
  final int pageNumber;
  final String? imageUrl;
  final Stream<String>? statusStream;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  _PiStatus _piStatus = _PiStatus.capturing;
  bool _isProcessing = true;
  String? _error;
  StreamSubscription<String>? _statusSub;

  @override
  void initState() {
    super.initState();
    _statusSub = widget.statusStream?.listen(_onPiStatus);
    if (widget.onProcess != null) {
      _executeRealProcess();
    } else if (widget.onCompleted != null) {
      widget.onCompleted!();
    }
  }

  void _onPiStatus(String rawStatus) {
    if (!mounted) return;
    setState(() {
      switch (rawStatus.toUpperCase()) {
        case 'QUEUED':
          _piStatus = _PiStatus.queued;
          break;
        case 'PROCESSING':
          _piStatus = _PiStatus.processing;
          break;
        case 'READY':
          _piStatus = _PiStatus.ready;
          break;
        case 'FAILED':
          _piStatus = _PiStatus.failed;
          break;
        default:
          break;
      }
    });
  }

  Future<void> _executeRealProcess() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      await widget.onProcess!();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _piStatus = _PiStatus.failed;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isProcessing,
      child: Scaffold(
        appBar: AppBar(title: const Text('Processing')),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (_error == null)
              _buildProgressHero()
            else
              AppCard(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                          AppShapes.cardRadius,
                        ),
                      ),
                      child: Icon(
                        Icons.document_scanner_rounded,
                        color: context.accent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Captured Page ${widget.pageNumber}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _error != null
                                ? 'Processing failed'
                                : _statusSubtitle(),
                            style: TextStyle(
                              fontSize: 12,
                              color: _error != null
                                  ? AppColors.danger
                                  : context.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Captured Image',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppShapes.cardRadius),
                      child: Image.network(
                        widget.imageUrl!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return SizedBox(
                            height: 160,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: context.accent,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, _) => SizedBox(
                          height: 80,
                          child: Center(
                            child: Icon(
                              Icons.broken_image_rounded,
                              color: context.mutedText,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            if (_error != null) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.danger,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Capture Error',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(fontSize: 13, color: context.strongText),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Return to Home'),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [..._buildSteps()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              strokeWidth: 5,
              color: context.accent,
              backgroundColor: context.surfaceElevated,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Reading your document...',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Page ${widget.pageNumber} · ${_statusSubtitle()}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: context.mutedText),
          ),
        ],
      ),
    );
  }

  String _statusSubtitle() {
    switch (_piStatus) {
      case _PiStatus.capturing:
        return 'Triggering camera on Raspberry Pi...';
      case _PiStatus.queued:
        return 'Captured — waiting in Pi processing queue...';
      case _PiStatus.processing:
        return 'Pi is running OCR + AI summary + audio...';
      case _PiStatus.ready:
        return 'Processing complete — saving to phone...';
      case _PiStatus.failed:
        return 'Processing failed';
    }
  }

  List<Widget> _buildSteps() {
    final steps = <(String, int)>[
      ('Camera triggered', _PiStatus.queued.index),
      ('Image captured', _PiStatus.processing.index),
      ('OCR text extracted', _PiStatus.ready.index),
      ('AI summary generated', _PiStatus.ready.index),
      ('Audio files generated', _PiStatus.ready.index),
    ];
    return steps.map((step) {
      final done = _piStatus.index >= step.$2;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox(
          width: 18,
          height: 18,
          child: done
              ? const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 18,
                )
              : CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.accent,
                ),
        ),
        title: Text(
          step.$1,
          style: TextStyle(
            fontSize: 14,
            color: done ? context.strongText : context.mutedText,
          ),
        ),
      );
    }).toList();
  }
}
