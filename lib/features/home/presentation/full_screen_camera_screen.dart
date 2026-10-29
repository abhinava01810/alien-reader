import 'package:flutter/material.dart';

import '../../../core/constants/pi_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../device/domain/reader_device.dart';
import '../widgets/home_camera_placeholder.dart';
import '../widgets/mjpeg_camera_view.dart';

class FullScreenCameraScreen extends StatelessWidget {
  const FullScreenCameraScreen({
    super.key,
    required this.status,
    this.onCapture,
    this.onProcess,
    this.pageCount = 0,
  });

  final ReaderConnectionStatus status;
  final VoidCallback? onCapture;
  final VoidCallback? onProcess;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final isDeviceReady =
        status == ReaderConnectionStatus.connected ||
        status == ReaderConnectionStatus.busy;

    final (labelText, dotColor) = switch (status) {
      ReaderConnectionStatus.connected => ('CONNECTED', AppColors.success),
      ReaderConnectionStatus.connecting => ('CONNECTING', AppColors.orange),
      ReaderConnectionStatus.disconnected => ('DISCONNECTED', AppColors.danger),
      ReaderConnectionStatus.busy => ('PROCESSING...', AppColors.purpleMid),
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Full-screen Live MJPEG camera feed ───────────────────
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: MjpegCameraView(
                    streamUrl: PiConfig.streamUrl,
                    active: isDeviceReady,
                  ),
                ),
              ),
            ),

            // ── Corner guides overlay ────────────────────────────────
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: CustomPaint(
                  painter: CornerGuidesPainter(
                    color: AppColors.orange.withValues(alpha: 0.9),
                    strokeWidth: 3.5,
                    length: 28.0,
                  ),
                ),
              ),
            ),

            // ── Top Bar: Close button & minimal status indicator ─────
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Material(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: dotColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle_rounded, color: dotColor, size: 8),
                        const SizedBox(width: 8),
                        Text(
                          labelText,
                          style: TextStyle(
                            color: dotColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom bar: page counter, shutter, Read ──────────────
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.article_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$pageCount ${pageCount == 1 ? 'page' : 'pages'}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (onCapture != null && isDeviceReady)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          onCapture!();
                          Navigator.of(context).pop();
                        },
                        customBorder: const CircleBorder(),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: const BoxDecoration(
                              color: AppColors.orange,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.photo_camera_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: onProcess != null && pageCount > 0
                          ? FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onProcess!();
                              },
                              icon: const Icon(
                                Icons.graphic_eq_rounded,
                                size: 18,
                              ),
                              label: const Text('Read'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.orange,
                                foregroundColor: Colors.white,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
