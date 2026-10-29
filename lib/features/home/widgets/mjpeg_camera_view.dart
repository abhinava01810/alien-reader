import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/theme/app_colors.dart';

/// Displays a live MJPEG stream from the Raspberry Pi camera.
///
/// Connects to the [streamUrl] endpoint which serves a
/// `multipart/x-mixed-replace` MJPEG stream. Each chunk from the HTTP
/// response is scanned for JPEG SOI (0xFF 0xD8) / EOI (0xFF 0xD9) markers
/// to extract complete frames.
///
/// Automatically reconnects on stream errors or disconnections.
class MjpegCameraView extends StatefulWidget {
  const MjpegCameraView({
    super.key,
    required this.streamUrl,
    this.active = true,
  });

  /// Full URL of the MJPEG endpoint, e.g.
  /// `http://192.168.0.134:8000/camera/stream`
  final String streamUrl;

  /// Whether the camera stream should actively fetch frames.
  final bool active;

  /// Compile-time toggle for preview rotation (90 deg CCW = 3 quarter turns)
  static const bool _kRotatePreview = true;

  @override
  State<MjpegCameraView> createState() => _MjpegCameraViewState();
}

class _MjpegCameraViewState extends State<MjpegCameraView> {
  Uint8List? _currentFrame;
  String? _error;
  bool _connecting = false;

  http.Client? _httpClient;
  StreamSubscription<List<int>>? _streamSub;

  // Raw byte accumulation buffer for the incoming HTTP stream.
  final List<int> _buffer = [];

  static const int _maxBufferBytes = 2 * 1024 * 1024; // 2 MB safety cap

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _connect();
    }
  }

  @override
  void didUpdateWidget(covariant MjpegCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active ||
        widget.streamUrl != oldWidget.streamUrl) {
      if (widget.active) {
        _connect();
      } else {
        _tearDown();
        if (mounted) {
          setState(() {
            _currentFrame = null;
            _connecting = false;
            _error = null;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _tearDown();
    super.dispose();
  }

  void _tearDown() {
    _streamSub?.cancel();
    _streamSub = null;
    _httpClient?.close();
    _httpClient = null;
  }

  /// Opens an HTTP streaming connection and begins processing MJPEG frames.
  Future<void> _connect() async {
    _tearDown();
    _buffer.clear();

    if (!mounted || !widget.active) return;
    setState(() {
      _connecting = true;
      _error = null;
    });

    _httpClient = http.Client();

    try {
      final request = http.Request('GET', Uri.parse(widget.streamUrl));
      final response = await _httpClient!
          .send(request)
          .timeout(const Duration(seconds: 10));

      if (!mounted || !widget.active) return;

      if (response.statusCode != 200) {
        setState(() {
          _connecting = false;
          _error = 'Camera unavailable\n(HTTP ${response.statusCode})';
        });
        return;
      }

      setState(() => _connecting = false);

      _streamSub = response.stream.listen(
        (chunk) {
          if (!widget.active) return;
          _buffer.addAll(chunk);
          _extractFrames();
        },
        onError: (Object e) {
          debugPrint('[MjpegCameraView] Stream error: $e');
          if (mounted && widget.active) {
            setState(() => _error = 'Stream error. Reconnecting...');
            Future<void>.delayed(const Duration(seconds: 2), _connect);
          }
        },
        onDone: () {
          debugPrint('[MjpegCameraView] Stream ended.');
          if (mounted && widget.active) {
            setState(() => _error = 'Stream disconnected. Reconnecting...');
            Future<void>.delayed(const Duration(seconds: 2), _connect);
          }
        },
        cancelOnError: true,
      );
    } on TimeoutException {
      if (mounted && widget.active) {
        setState(() {
          _connecting = false;
          _error = 'Connection timed out.\nIs the Raspberry Pi reachable?';
        });
      }
    } catch (e) {
      debugPrint('[MjpegCameraView] Connection error: $e');
      if (mounted && widget.active) {
        setState(() {
          _connecting = false;
          _error = 'Cannot reach camera.\nCheck Pi IP and network connection.';
        });
      }
    }
  }

  /// Scans [_buffer] for complete JPEG frames (SOI → EOI) and renders them.
  ///
  /// JPEG SOI marker: 0xFF 0xD8
  /// JPEG EOI marker: 0xFF 0xD9
  void _extractFrames() {
    while (_buffer.length >= 4) {
      // Locate JPEG Start Of Image (SOI)
      final soiIdx = _findMarker(0xFF, 0xD8);
      if (soiIdx == -1) {
        // No SOI found — clear garbage (keep last byte in case it's first
        // byte of a split marker)
        if (_buffer.length > _maxBufferBytes) _buffer.clear();
        return;
      }

      // Trim everything before SOI
      if (soiIdx > 0) _buffer.removeRange(0, soiIdx);

      // Locate JPEG End Of Image (EOI) after SOI
      final eoiIdx = _findMarker(0xFF, 0xD9, from: 2);
      if (eoiIdx == -1) {
        // Frame not yet complete — wait for more data
        if (_buffer.length > _maxBufferBytes) {
          // Safety: buffer too large without a valid frame — reset
          _buffer.clear();
        }
        return;
      }

      // Extract the complete JPEG frame (SOI through EOI inclusive)
      final frameEnd = eoiIdx + 2;
      final frame = Uint8List.fromList(_buffer.sublist(0, frameEnd));
      _buffer.removeRange(0, frameEnd);

      if (mounted && widget.active) {
        setState(() => _currentFrame = frame);
      }
      // Loop to check if another complete frame is already in the buffer
    }
  }

  /// Returns the index of the first occurrence of [b0, b1] in [_buffer]
  /// starting at [from], or -1 if not found.
  int _findMarker(int b0, int b1, {int from = 0}) {
    for (int i = from; i < _buffer.length - 1; i++) {
      if (_buffer[i] == b0 && _buffer[i + 1] == b1) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const SizedBox.shrink();
    }

    if (_connecting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: AppColors.orange,
                strokeWidth: 2,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Connecting to camera...',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    // Show error only if we have no frame yet (once streaming, keep last frame)
    if (_error != null && _currentFrame == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                color: Colors.white38,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _connect,
                icon: const Icon(
                  Icons.refresh,
                  size: 16,
                  color: AppColors.orange,
                ),
                label: const Text(
                  'Retry',
                  style: TextStyle(color: AppColors.orange, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.orange),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentFrame == null) {
      // Connected but waiting for first frame
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: AppColors.orange,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final frameWidget = Image.memory(
      _currentFrame!,
      fit: BoxFit.cover,
      gaplessPlayback: true, // prevents black flash between frames
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.white38,
          size: 32,
        ),
      ),
    );

    if (MjpegCameraView._kRotatePreview) {
      return RotatedBox(quarterTurns: 3, child: frameWidget);
    }

    return frameWidget;
  }
}
