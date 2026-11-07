import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/mock_audio_player.dart';
import '../../document/data/models/saved_document.dart';
import '../../document/data/services/document_storage_service.dart';
import '../widgets/output_device_sheet.dart';

/// "Output" tab: Original / Summary text with an audio player bar.
///
/// The most recently saved document is shown; it is reloaded each time
/// [isProcessing] drops back to false (processing auto-saves the result).
class OutputScreen extends StatefulWidget {
  const OutputScreen({
    super.key,
    this.isProcessing = false,
    this.storage,
    this.initialDocument,
    this.latestDocument,
  });

  final bool isProcessing;
  final DocumentStorageService? storage;

  /// Skips the storage lookup when provided (used by tests).
  final SavedDocument? initialDocument;

  /// The capture that was just processed and saved. Shown as soon as it
  /// arrives, ahead of any storage reload still in flight.
  final SavedDocument? latestDocument;

  @override
  State<OutputScreen> createState() => _OutputScreenState();
}

class _OutputScreenState extends State<OutputScreen>
    with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_onTabChanged);
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  SavedDocument? _document;
  bool _loadingDoc = true;

  /// Bumped whenever [OutputScreen.latestDocument] is applied, so a storage
  /// reload started earlier cannot replace it with an older document.
  int _docGeneration = 0;
  String outputDevice = 'Phone Speaker';

  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;

  bool get _isSummary => _tabs.index == 1;

  @override
  void initState() {
    super.initState();
    final first = widget.latestDocument ?? widget.initialDocument;
    if (first != null) {
      _document = first;
      _loadingDoc = false;
    } else {
      _loadDocument();
    }
    _syncShimmer();
  }

  @override
  void didUpdateWidget(covariant OutputScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final latest = widget.latestDocument;
    if (latest != null && !identical(latest, oldWidget.latestDocument)) {
      _showLatest(latest);
    } else if (oldWidget.isProcessing && !widget.isProcessing) {
      _loadDocument();
    }
    _syncShimmer();
  }

  Future<void> _showLatest(SavedDocument doc) async {
    _docGeneration++;
    await _stopAudio();
    if (!mounted) return;
    setState(() {
      _document = doc;
      _loadingDoc = false;
    });
    _syncShimmer();
  }

  void _syncShimmer() {
    if (_showLoading) {
      if (!_shimmer.isAnimating) _shimmer.repeat();
    } else {
      _shimmer.stop();
    }
  }

  bool get _showLoading => widget.isProcessing || _loadingDoc;

  Future<void> _loadDocument() async {
    final generation = _docGeneration;
    try {
      final docs = await (widget.storage ?? DocumentStorageService())
          .loadAllDocuments();
      docs.sort((a, b) => b.captureDate.compareTo(a.captureDate));
      if (!mounted || generation != _docGeneration) return;
      await _stopAudio();
      setState(() {
        _document = docs.isEmpty ? null : docs.first;
        _loadingDoc = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDoc = false);
    }
    _syncShimmer();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    _stopAudio();
    setState(() {});
  }

  String get _text {
    final doc = _document;
    if (doc == null) return '';
    return (_isSummary ? doc.summaryText : doc.originalText).trim();
  }

  Source? get _audioSource {
    final doc = _document;
    if (doc == null) return null;
    final local = _isSummary ? doc.summaryAudioPath : doc.originalAudioPath;
    if (local != null && File(local).existsSync()) {
      return DeviceFileSource(local);
    }
    final remote = _isSummary
        ? doc.remoteSummaryAudioUrl
        : doc.remoteOriginalAudioUrl;
    if (remote != null && remote.isNotEmpty) return UrlSource(remote);
    return null;
  }

  Future<void> _ensurePlayer() async {
    if (_player != null) return;
    final player = AudioPlayer();
    _player = player;
    _subs
      ..add(
        player.onPlayerStateChanged.listen((s) {
          if (mounted) setState(() => _playing = s == PlayerState.playing);
        }),
      )
      ..add(
        player.onPositionChanged.listen((p) {
          if (mounted) setState(() => _position = p);
        }),
      )
      ..add(
        player.onDurationChanged.listen((d) {
          if (mounted) setState(() => _duration = d);
        }),
      )
      ..add(
        player.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _position = Duration.zero);
        }),
      );
  }

  Future<void> _togglePlay() async {
    final source = _audioSource;
    if (source == null) return;
    try {
      await _ensurePlayer();
      if (_playing) {
        await _player!.pause();
      } else if (_position > Duration.zero && _position < _duration) {
        await _player!.resume();
      } else {
        await _player!.setPlaybackRate(_speed);
        await _player!.play(source);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio could not be played.')),
      );
    }
  }

  Future<void> _stopAudio() async {
    final player = _player;
    if (mounted) {
      setState(() {
        _playing = false;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
    }
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    try {
      await _player?.setPlaybackRate(speed);
    } catch (_) {}
  }

  Future<void> _seek(Duration to) async {
    setState(() => _position = to);
    try {
      await _player?.seek(to);
    } catch (_) {}
  }

  Future<void> _changeOutput() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => OutputDeviceSheet(
        selected: outputDevice,
        onSelected: (value) {
          setState(() => outputDevice = value);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    _tabs.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppColors.purpleMid : AppColors.purple;

    return Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor: accent,
          unselectedLabelColor: isDark
              ? AppColors.darkTextMuted
              : AppColors.lightTextMuted,
          indicatorColor: accent,
          dividerColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Original'),
            Tab(text: 'Summary'),
          ],
        ),
        Expanded(child: _buildTextArea(context, isDark)),
        MockAudioPlayer(
          title: _isSummary ? 'Summary audio' : 'Original audio',
          duration: _duration,
          position: _position,
          isPlaying: _playing,
          speed: _speed,
          outputTarget: outputDevice,
          enabled: _audioSource != null && !_showLoading,
          onPlayPause: _togglePlay,
          onSeek: _seek,
          onSpeedChanged: _setSpeed,
          onChangeOutput: _changeOutput,
        ),
      ],
    );
  }

  Widget _buildTextArea(BuildContext context, bool isDark) {
    if (_showLoading) {
      return _ShimmerLines(animation: _shimmer, isDark: isDark);
    }
    final text = _text;
    if (text.isEmpty) {
      return const EmptyState(
        title: 'No text extracted',
        subtitle: 'Capture a page on Home and tap Read to see it here.',
        icon: Icons.article_rounded,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
      ),
    );
  }
}

/// Placeholder text lines with a sweeping highlight, shown while processing.
class _ShimmerLines extends StatelessWidget {
  const _ShimmerLines({required this.animation, required this.isDark});

  final Animation<double> animation;
  final bool isDark;

  static const _widths = [1.0, 0.92, 1.0, 0.78, 0.96, 0.6];

  @override
  Widget build(BuildContext context) {
    final base = isDark
        ? AppColors.darkSurfaceElevated
        : AppColors.lightSurfaceElevated;
    final highlight = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Semantics(
      label: 'Loading text',
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) => LinearGradient(
              colors: [base, highlight, base],
              stops: [
                (t - 0.3).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(rect),
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                for (final w in _widths)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: w,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: base,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
