import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shapes.dart';

/// Playback-speed options offered by [MockAudioPlayer].
const List<double> kAudioSpeeds = [1.0, 1.5, 2.0];

/// Audio player bar: play/pause, progress slider and speed selector.
///
/// Stateless and fully controlled; the owner drives playback and feeds
/// [position], [duration] and [speed] back in.
class MockAudioPlayer extends StatelessWidget {
  const MockAudioPlayer({
    super.key,
    required this.title,
    required this.duration,
    required this.outputTarget,
    this.position = Duration.zero,
    this.isPlaying = false,
    this.speed = 1.0,
    this.enabled = true,
    this.onPlayPause,
    this.onSeek,
    this.onSpeedChanged,
    this.onChangeOutput,
  });

  final String title;
  final Duration duration;
  final String outputTarget;
  final Duration position;
  final bool isPlaying;
  final double speed;
  final bool enabled;
  final VoidCallback? onPlayPause;
  final ValueChanged<Duration>? onSeek;
  final ValueChanged<double>? onSpeedChanged;
  final VoidCallback? onChangeOutput;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppColors.purpleMid : AppColors.purple;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    final totalMs = duration.inMilliseconds;
    final posMs = position.inMilliseconds.clamp(0, totalMs > 0 ? totalMs : 0);
    final canSeek = enabled && totalMs > 0 && onSeek != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: onChangeOutput,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.volume_up_rounded, size: 16, color: muted),
                      const SizedBox(width: 4),
                      Text(
                        outputTarget,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton.filled(
                onPressed: enabled ? onPlayPause : null,
                tooltip: isPlaying ? 'Pause' : 'Play',
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: isDark
                      ? AppColors.darkSurfaceElevated
                      : AppColors.lightSurfaceElevated,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: accent,
                    thumbColor: accent,
                    inactiveTrackColor: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                  child: Slider(
                    value: posMs.toDouble(),
                    max: totalMs > 0 ? totalMs.toDouble() : 1,
                    onChanged: canSeek
                        ? (v) => onSeek!(Duration(milliseconds: v.round()))
                        : null,
                  ),
                ),
              ),
              Text(
                '${_formatDuration(position)} / ${_formatDuration(duration)}',
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final s in kAudioSpeeds)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text('${s == s.roundToDouble() ? s.toInt() : s}×'),
                    selected: speed == s,
                    onSelected: enabled && onSpeedChanged != null
                        ? (_) => onSpeedChanged!(s)
                        : null,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    selectedColor: accent.withValues(alpha: 0.16),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: speed == s ? accent : muted,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppShapes.buttonRadius,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
