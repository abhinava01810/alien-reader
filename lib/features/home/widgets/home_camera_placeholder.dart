import 'package:flutter/material.dart';

import '../../../core/constants/pi_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../device/domain/reader_device.dart';
import 'mjpeg_camera_view.dart';

/// Camera preview area on the home screen.
///
/// Always displays the live MJPEG stream from the Raspberry Pi camera.
/// If the Pi is unreachable, [MjpegCameraView] shows an error + retry button.
/// A status indicator pill is overlaid at the top showing connection state.
/// Document-framing corner guides are painted over the live feed.
/// A full-screen button allows expanding the live preview.
class HomeCameraPlaceholder extends StatelessWidget {
  const HomeCameraPlaceholder({
    super.key,
    required this.status,
    this.onToggleFullScreen,
    this.onConnect,
  });

  final ReaderConnectionStatus status;
  final VoidCallback? onToggleFullScreen;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final (labelText, dotColor) = switch (status) {
      ReaderConnectionStatus.connected => ('CONNECTED', AppColors.success),
      ReaderConnectionStatus.connecting => ('CONNECTING', AppColors.orange),
      ReaderConnectionStatus.disconnected => ('DISCONNECTED', AppColors.danger),
      ReaderConnectionStatus.busy => ('PROCESSING...', AppColors.purpleMid),
    };

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121218), // dark fallback behind the stream
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == ReaderConnectionStatus.connected
              ? AppColors.purpleMid.withValues(alpha: 0.6)
              : AppColors.orange.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // ── Live MJPEG camera feed ────────────────────────────────
            Positioned.fill(
              child: MjpegCameraView(
                streamUrl: PiConfig.streamUrl,
                active:
                    status == ReaderConnectionStatus.connected ||
                    status == ReaderConnectionStatus.busy,
              ),
            ),

            // ── Clean disconnected placeholder state ───────────────────
            if (status == ReaderConnectionStatus.disconnected)
              Positioned.fill(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.videocam_off_rounded,
                        color: Colors.white.withValues(alpha: 0.35),
                        size: 38,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Camera Feed Inactive',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Connect to Naadh reader to start live stream',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Document-positioning corner guides ────────────────────
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: CustomPaint(
                  painter: CornerGuidesPainter(
                    color: AppColors.orange.withValues(alpha: 0.85),
                    strokeWidth: 2.5,
                    length: 20.0,
                  ),
                ),
              ),
            ),

            // ── Connection status pill ────────────────────────────────
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle_rounded, color: dotColor, size: 7),
                      const SizedBox(width: 6),
                      Text(
                        labelText,
                        style: TextStyle(
                          color: dotColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Full-screen expand icon button ─────────────────────────
            if (onToggleFullScreen != null) ...[
              Positioned(
                bottom: 8,
                right: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onToggleFullScreen,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.fullscreen_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Paints L-shaped corner guides to help position a document under the camera.
class CornerGuidesPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double length;

  CornerGuidesPainter({
    required this.color,
    this.strokeWidth = 3.0,
    this.length = 20.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // Top-Left
    canvas.drawLine(const Offset(0, 0), Offset(length, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, length), paint);

    // Top-Right
    canvas.drawLine(Offset(w, 0), Offset(w - length, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, length), paint);

    // Bottom-Left
    canvas.drawLine(Offset(0, h), Offset(length, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - length), paint);

    // Bottom-Right
    canvas.drawLine(Offset(w, h), Offset(w - length, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - length), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
