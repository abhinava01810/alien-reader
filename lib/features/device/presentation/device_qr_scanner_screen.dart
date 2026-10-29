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
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
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
                      color: Colors.amber,
                    );
                  case TorchState.off:
                  default:
                    return const Icon(
                      Icons.flash_off_rounded,
                      color: Colors.white,
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

  Widget _buildScannerOverlay(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanBoxSize = size.width * 0.72;

    return Center(
      child: Container(
        width: scanBoxSize,
        height: scanBoxSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.purpleMid, width: 3),
        ),
        child: Stack(
          children: [
            // Corner accents
            Positioned(top: 0, left: 0, child: _cornerAccent(topLeft: true)),
            Positioned(top: 0, right: 0, child: _cornerAccent(topRight: true)),
            Positioned(
              bottom: 0,
              left: 0,
              child: _cornerAccent(bottomLeft: true),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: _cornerAccent(bottomRight: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cornerAccent({
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.purple,
        borderRadius: BorderRadius.only(
          topLeft: topLeft ? const Radius.circular(12) : Radius.zero,
          topRight: topRight ? const Radius.circular(12) : Radius.zero,
          bottomLeft: bottomLeft ? const Radius.circular(12) : Radius.zero,
          bottomRight: bottomRight ? const Radius.circular(12) : Radius.zero,
        ),
      ),
    );
  }

  Widget _buildInstructionBanner() {
    return Positioned(
      top: 24,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(AppShapes.cardRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: const Column(
          children: [
            Text(
              'Align the Naadh device QR code inside the frame',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'The QR code is located on the back or bottom of your Naadh reader.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppShapes.cardRadius),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage ?? '',
                style: const TextStyle(
                  color: Colors.white,
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
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.no_photography_rounded,
                size: 56,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
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
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
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
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
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
