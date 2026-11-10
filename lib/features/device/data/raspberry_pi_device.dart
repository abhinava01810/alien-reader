import 'dart:async';

import '../domain/reader_device.dart';
import 'reader_session_errors.dart';
import 'services/pi_api_service.dart';

class OcrFailureException implements Exception {
  final String message;
  const OcrFailureException([
    this.message =
        'No text detected in image. Please adjust lighting/position and try again.',
  ]);

  @override
  String toString() => message;
}

class RaspberryPiDevice implements ReaderDevice {
  RaspberryPiDevice({PiApiService? apiService})
    : _apiService = apiService ?? PiApiService();

  final PiApiService _apiService;

  final StreamController<ReaderConnectionStatus> _controller =
      StreamController<ReaderConnectionStatus>.broadcast();

  Map<String, dynamic>? _lastCapture;
  Map<String, dynamic>? _lastTriggeredPage; // immediate trigger result
  String? _sessionId;
  String? _accessToken;

  @override
  Stream<ReaderConnectionStatus> get status => _controller.stream;

  Map<String, dynamic>? get lastCapture => _lastCapture;
  Map<String, dynamic>? get lastTriggeredPage => _lastTriggeredPage;
  String? get sessionId => _sessionId;
  String? get accessToken => _accessToken;

  @override
  Future<void> connect() async {
    _controller.add(ReaderConnectionStatus.connecting);

    try {
      final data = await _apiService.getStatus();

      if (data['status'] == 'AVAILABLE') {
        _controller.add(ReaderConnectionStatus.disconnected);
      } else {
        _controller.add(ReaderConnectionStatus.disconnected);
      }
    } catch (_) {
      _controller.add(ReaderConnectionStatus.disconnected);
    }
  }

  /// [takeOver]: end a session held by someone else.
  /// Only after the person chose to.
  Future<void> startSession(String userName, {bool takeOver = false}) async {
    _controller.add(ReaderConnectionStatus.connecting);

    try {
      final result = await _apiService.startSession(userName);

      if (result['success'] == true) {
        _sessionId = result['session_id'] as String?;
        _accessToken = result['access_token'] as String?;
        _controller.add(ReaderConnectionStatus.connected);
      } else {
        _sessionId = null;
        _accessToken = null;
        _controller.add(ReaderConnectionStatus.disconnected);

        throw Exception(result['message'] ?? 'Failed to start session');
      }
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('409') ||
          errStr.contains('being used by another user')) {
        // Only end the open session if it is this
        // user's own, or they chose to take over.
        if (!takeOver) {
          final holder = await _sessionHolder();
          if (holder != userName.trim().toLowerCase()) {
            _sessionId = null;
            _accessToken = null;
            _controller.add(ReaderConnectionStatus.disconnected);
            throw ReaderInUseException(_holderName);
          }
        }
        try {
          await _apiService.endSession();
          await Future<void>.delayed(const Duration(milliseconds: 600));
          final retryResult = await _apiService.startSession(userName);
          if (retryResult['success'] == true) {
            _sessionId = retryResult['session_id'] as String?;
            _accessToken = retryResult['access_token'] as String?;
            _controller.add(ReaderConnectionStatus.connected);
            return;
          }
        } catch (_) {}
      }

      _sessionId = null;
      _accessToken = null;
      _controller.add(ReaderConnectionStatus.disconnected);
      rethrow;
    }
  }

  String? _holderName;

  /// Lower-cased display name of the reader's open
  /// app session, or null if unknown.
  Future<String?> _sessionHolder() async {
    try {
      final s = await _apiService.getStatus();
      final name = s['status'] == 'APP_ACTIVE'
          ? (s['display_name'] as String?)?.trim()
          : null;
      _holderName = name;
      return name?.toLowerCase();
    } catch (_) {
      _holderName = null;
      return null;
    }
  }

  @override
  Future<void> disconnect() async {
    await endSession();
  }

  @override
  Future<void> capture() async {
    final result = await _apiService.captureImage();

    if (result['success'] != true) {
      if (result['reason'] == 'text_not_detected') {
        throw OcrFailureException(
          result['message'] as String? ??
              'No text detected in image. Please try again.',
        );
      }
      throw Exception(
        result['message'] as String? ?? 'Failed to capture image',
      );
    }

    _lastCapture = result;
  }

  /// Triggers an async capture on the Pi and returns immediately.
  /// The Pi captures the image and then processes OCR + summary + audio
  /// in the background. Call [pollPageUntilReady] to wait for completion.
  ///
  /// Returns a map with:
  ///   - page_number (int)
  ///   - status: "PROCESSING"
  ///   - image_url: relative path for immediate image display
  Future<Map<String, dynamic>> triggerCaptureAsync() async {
    final result = await _apiService.triggerCapture();

    if (result['success'] != true) {
      throw Exception(
        result['message'] as String? ?? 'Failed to trigger capture',
      );
    }

    _lastTriggeredPage = result;
    return result;
  }

  /// Polls GET /capture/{pageNumber} until the Pi reports READY or FAILED.
  /// Polls every [pollInterval] (default 2 s). Throws after [maxAttempts]
  /// polls with no READY/FAILED status (default ~5 min at 2 s intervals).
  ///
  /// On READY: stores result in [lastCapture] and returns it.
  /// On FAILED: throws [OcrFailureException].
  /// On timeout: throws Exception.
  Future<Map<String, dynamic>> pollPageUntilReady(
    int pageNumber, {
    Duration pollInterval = const Duration(seconds: 2),
    int maxAttempts = 150,
    void Function(String status)? onStatusUpdate,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future<void>.delayed(pollInterval);

      Map<String, dynamic> data;
      try {
        data = await _apiService.getCaptureStatus(pageNumber);
      } catch (e) {
        // Transient network hiccup — keep polling
        continue;
      }

      final status = (data['status'] as String? ?? '').toUpperCase();
      onStatusUpdate?.call(status);

      if (status == 'READY') {
        _lastCapture = data;
        return data;
      }

      if (status == 'FAILED') {
        final reason = data['reason'] as String?;
        final message = (data['error'] ?? data['message']) as String?;
        if (reason == 'text_not_detected') {
          throw OcrFailureException(
            message ??
                'No text detected in image. Please adjust lighting/position and try again.',
          );
        }
        throw Exception(message ?? 'Page $pageNumber processing failed on Pi');
      }

      // QUEUED or PROCESSING — keep polling
    }

    throw Exception(
      'Timed out waiting for page $pageNumber to finish processing on Pi.',
    );
  }

  @override
  Future<void> finishScan() async {}

  @override
  Future<List<String>> getFiles() async {
    try {
      final data = await _apiService.getCaptures();

      final captures = data['captures'] as List<dynamic>? ?? [];

      return captures
          .map(
            (capture) =>
                _apiService.getFullUrl(capture['image_url'] as String?),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns the full list of captures from the current session.
  /// Each entry has: page_number (int) and image_url (String, full URL).
  Future<List<Map<String, dynamic>>> getCaptureList() async {
    try {
      final data = await _apiService.getCaptures();
      final raw = data['captures'] as List<dynamic>? ?? [];
      return raw.map((c) {
        final m = c as Map<String, dynamic>;
        return {
          'page_number': m['page_number'],
          'image_url': _apiService.getFullUrl(m['image_url'] as String?),
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getCaptureDetails(int pageNumber) async {
    try {
      return await _apiService.getCaptureDetails(pageNumber);
    } catch (_) {
      return null;
    }
  }

  String getFullUrl(String? path) {
    return _apiService.getFullUrl(path);
  }

  Future<void> endSession() async {
    try {
      await _apiService.endSession();
    } catch (_) {}
    _sessionId = null;
    _accessToken = null;
    _lastCapture = null;
    _controller.add(ReaderConnectionStatus.disconnected);
  }

  void dispose() {
    _apiService.dispose();
    _controller.close();
  }
}
