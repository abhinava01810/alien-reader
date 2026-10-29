import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shapes.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/models/device_qr_payload.dart';
import 'device_identified_screen.dart';

/// Screen that opens the phone camera to scan a Naadh device QR code.
///
/// Ensures:
/// - Camera permissions are handled and recovery path provided on denial.
/// - Scans only QR codes (formats: [BarcodeFormat.qrCode]).
/// - Prevents duplicate scans after detecting a valid payload.
/// - Validates payload before proceeding; surfaces clear error without logging payload.
/// - Preserves independent operation from the Raspberry Pi document camera stream.
class DeviceQrScannerScreen extends StatefulWidget {
  const DeviceQrScannerScreen({super.key});

  @override
  State<DeviceQrScannerScreen> createState() => _DeviceQrScannerScreenState();
}

class _DeviceQrScannerScreenState extends State<DeviceQrScannerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _scanLine;
  bool _hasProcessed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
      autoStart: true,
    );
    _scanLine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller.stop();
    } else if (state == AppLifecycleState.resumed) {
      _controller.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanLine.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasProcessed || !mounted) return;

    final barcode = capture.barcodes.firstOrNull;
    final rawValue = barcode?.rawValue;

    if (rawValue == null || rawValue.trim().isEmpty) {
      return;
    }

    try {
      final payload = DeviceQrPayload.parse(rawValue);

      setState(() {
        _hasProcessed = true;
        _errorMessage = null;
      });

      _controller.stop();

      // Navigate to setup-in-progress screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DeviceIdentifiedScreen(payload: payload),
        ),
      );
    } on QrPayloadException catch (e) {
      // Do not log the raw value. Present helpful feedback to the user.
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.danger,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Invalid QR code. Please scan a Naadh device QR code.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: AppColors.darkText,
        elevation: 0,
        title: const Text(
          'Scan Device QR Code',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                switch (state.torchState) {
                  case TorchState.on:
                    return const Icon(
                      Icons.flash_on_rounded,
                      color: AppColors.orange,
                    );
                  case TorchState.off:
                  default:
                    return const Icon(
                      Icons.flash_off_rounded,
                      color: AppColors.darkText,
                    );
                }
              },
            ),
            tooltip: 'Toggle Flashlight',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return _buildErrorState(error);
            },
          ),
          _buildScannerOverlay(context),
          _buildInstructionBanner(),
          if (_errorMessage != null) _buildErrorBanner(),
        ],
      ),
    );
  }

  /// Dimmed surround with a rounded cut-out, corner brackets and a scan line.
  Widget _buildScannerOverlay(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final boxSize = size.width * 0.72;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: CustomPaint(
            painter: _ViewfinderPainter(
              boxSize: boxSize,
              scrim: AppColors.darkBackground.withValues(alpha: 0.62),
              bracket: AppColors.purpleMid,
            ),
          ),
        ),
        Center(
          child: IgnorePointer(
            child: SizedBox(
              width: boxSize,
              height: boxSize,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  _ViewfinderPainter.cornerRadius,
                ),
                child: AnimatedBuilder(
                  animation: _scanLine,
                  builder: (context, _) {
                    const lineHeight = 3.0;
                    final top = _scanLine.value * (boxSize - lineHeight);
                    return Stack(
                      children: [
                        Positioned(
                          top: top,
                          left: 12,
                          right: 12,
                          child: Container(
                            height: lineHeight,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.orange.withValues(alpha: 0),
                                  AppColors.orange.withValues(alpha: 0.9),
                                  AppColors.orange.withValues(alpha: 0),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.orange.withValues(
                                    alpha: 0.35,
                                  ),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionBanner() {
    return Positioned(
      top: AppSpacing.xxl,
      left: AppSpacing.xl,
      right: AppSpacing.xl,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.darkSurface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(AppShapes.cardRadius),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: const Column(
          children: [
            Text(
              'Align the Naadh device QR code inside the frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.darkText,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: AppSpacing.xs),
            Text(
              'The QR code is located on the back or bottom of your Naadh reader.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Positioned(
      bottom: 40,
      left: AppSpacing.xl,
      right: AppSpacing.xl,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.onBrand,
              size: 24,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                _errorMessage ?? '',
                style: const TextStyle(
                  color: AppColors.onBrand,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(MobileScannerException error) {
    String title = 'Camera Error';
    String message = 'Unable to access the camera.';

    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      title = 'Camera Permission Required';
      message =
          'Camera access is needed to scan your Naadh device QR code. Please grant permission in your phone settings to proceed.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.darkSurfaceElevated,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.no_photography_rounded,
                size: 56,
                color: AppColors.darkTextMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.darkText,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.darkText,
                    side: const BorderSide(color: AppColors.darkBorder),
                    minimumSize: const Size(0, AppSpacing.buttonHeight),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () async {
                    setState(() {
                      _errorMessage = null;
                    });
                    await _controller.start();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    foregroundColor: AppColors.onBrand,
                    minimumSize: const Size(0, AppSpacing.buttonHeight),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a dimmed scrim with a rounded square cut-out and corner brackets.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({
    required this.boxSize,
    required this.scrim,
    required this.bracket,
  });

  static const double cornerRadius = 24;
  static const double _bracketLength = 36;
  static const double _bracketStroke = 5;

  final double boxSize;
  final Color scrim;
  final Color bracket;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: boxSize,
        height: boxSize,
      ),
      const Radius.circular(cornerRadius),
    );

    final scrimPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(hole),
    );
    canvas.drawPath(scrimPath, Paint()..color = scrim);

    final stroke = Paint()
      ..color = bracket
      ..style = PaintingStyle.stroke
      ..strokeWidth = _bracketStroke
      ..strokeCap = StrokeCap.round;

    final r = cornerRadius;
    final l = _bracketLength;
    final left = hole.left;
    final top = hole.top;
    final right = hole.right;
    final bottom = hole.bottom;

    // Each bracket: straight run in, rounded corner, straight run out.
    canvas.drawPath(
      Path()
        ..moveTo(left, top + r + l)
        ..lineTo(left, top + r)
        ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
        ..lineTo(left + r + l, top),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(right - r - l, top)
        ..lineTo(right - r, top)
        ..arcToPoint(Offset(right, top + r), radius: Radius.circular(r))
        ..lineTo(right, top + r + l),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(right, bottom - r - l)
        ..lineTo(right, bottom - r)
        ..arcToPoint(Offset(right - r, bottom), radius: Radius.circular(r))
        ..lineTo(right - r - l, bottom),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(left + r + l, bottom)
        ..lineTo(left + r, bottom)
        ..arcToPoint(Offset(left, bottom - r), radius: Radius.circular(r))
        ..lineTo(left, bottom - r - l),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.boxSize != boxSize || old.scrim != scrim || old.bracket != bracket;
}
