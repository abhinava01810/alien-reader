import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../core/constants/pi_config.dart';
import '../models/provisioning_models.dart';

class PiApiService {
  final http.Client _client;

  /// Where the reader is, asked on every request so a re-paired reader is
  /// picked up without recreating this service. Null or empty means the
  /// default [PiConfig.baseUrl].
  final String Function()? _baseUrlFor;

  PiApiService({http.Client? client, String Function()? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrlFor = baseUrl;

  String get _baseUrl {
    final url = _baseUrlFor?.call();
    return (url == null || url.isEmpty) ? PiConfig.baseUrl : url;
  }

  Future<Map<String, dynamic>> getStatus() async {
    final uri = Uri.parse('$_baseUrl/status');

    final response = await _client.get(uri).timeout(PiConfig.connectionTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to get device status: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> startSession(String displayName) async {
    final uri = Uri.parse('$_baseUrl/session/start');

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'display_name': displayName}),
        )
        .timeout(PiConfig.connectionTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to start session: '
        '${response.statusCode} ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> captureImage() async {
    final uri = Uri.parse('$_baseUrl/capture');

    final response = await _client
        .post(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to capture image: '
        '${response.statusCode} ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// POST /capture — triggers camera capture and returns immediately.
  /// Response includes: page_number, status ("PROCESSING"), image_url.
  /// The Pi continues OCR + summary + audio generation asynchronously.
  Future<Map<String, dynamic>> triggerCapture() async {
    final uri = Uri.parse('$_baseUrl/capture');

    final response = await _client
        .post(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        'Capture trigger failed: ${response.statusCode} ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// GET /capture/{pageNumber} — polls the processing state for a single page.
  /// Status values: QUEUED | PROCESSING | READY | FAILED
  Future<Map<String, dynamic>> getCaptureStatus(int pageNumber) async {
    final uri = Uri.parse('$_baseUrl/capture/$pageNumber');

    final response = await _client.get(uri).timeout(PiConfig.connectionTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to get capture status: ${response.statusCode} ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCaptureDetails(int pageNumber) async {
    final uri = Uri.parse('$_baseUrl/capture/$pageNumber');

    final response = await _client.get(uri).timeout(PiConfig.connectionTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to get capture details: '
        '${response.statusCode} ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCaptures() async {
    final uri = Uri.parse('$_baseUrl/captures');

    final response = await _client.get(uri).timeout(PiConfig.connectionTimeout);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to get captures: '
        '${response.statusCode} ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Full URL for the live MJPEG camera stream.
  String get streamUrl => '$_baseUrl/camera/stream';

  /// Checks if the Raspberry Pi is reachable with a 3-second timeout.
  /// Returns true if the /status endpoint responds with HTTP 200.
  Future<bool> checkHealth() async {
    try {
      final uri = Uri.parse('$_baseUrl/status');
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String getFullUrl(String? path) {
    if (path == null || path.isEmpty) {
      return '';
    }

    if (path.startsWith('http')) {
      return path;
    }

    return '$_baseUrl$path';
  }

  Future<void> endSession() async {
    final uri = Uri.parse('$_baseUrl/session/end');

    await _client.post(uri).timeout(PiConfig.connectionTimeout);
  }

  /// Downloads raw byte content from full URL or relative path on Pi server.
  Future<List<int>> downloadBytes(String path) async {
    final fullUrl = getFullUrl(path);
    final uri = Uri.parse(fullUrl);
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download file from $fullUrl: ${response.statusCode}',
      );
    }
    return response.bodyBytes;
  }

  void dispose() {
    _client.close();
  }

  // ============================================================
  // PROVISIONING & SETUP ENDPOINTS
  // ============================================================

  /// GET /api/setup/status
  Future<SetupStatusModel> getSetupStatus({String? baseUrl}) async {
    final root = baseUrl ?? PiConfig.baseUrl;
    final uri = Uri.parse('$root/api/setup/status');

    try {
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(PiConfig.connectionTimeout);

      if (response.statusCode != 200) {
        throw SetupNetworkException(
          'Failed to retrieve setup status (HTTP ${response.statusCode}).',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return SetupStatusModel.fromJson(json);
    } on TimeoutException {
      throw const SetupNetworkException(
        'Connection timed out while checking device setup status.',
      );
    } on SocketException catch (e) {
      throw SetupNetworkException(
        'Unable to reach device at $root: ${e.message}',
      );
    } catch (e) {
      if (e is SetupNetworkException) rethrow;
      throw SetupNetworkException('Setup status error: $e');
    }
  }

  /// POST /api/setup/session
  Future<SetupSessionModel> createSetupSession(
    String setupSecret, {
    String? baseUrl,
  }) async {
    final root = baseUrl ?? PiConfig.baseUrl;
    final uri = Uri.parse('$root/api/setup/session');

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'setup_secret': setupSecret,
              'secret': setupSecret,
              'pin': setupSecret,
            }),
          )
          .timeout(PiConfig.connectionTimeout);

      if (response.statusCode == 401) {
        throw const SetupAuthException(
          'Authentication failed. Invalid device setup PIN or secret.',
        );
      }

      if (response.statusCode == 429) {
        throw const SetupRateLimitException(
          'Too many failed attempts. The device is temporarily locked out. Please wait and try again.',
        );
      }

      if (response.statusCode != 200) {
        throw SetupNetworkException(
          'Authentication failed (HTTP ${response.statusCode}).',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return SetupSessionModel.fromJson(json);
    } on TimeoutException {
      throw const SetupNetworkException(
        'Connection timed out while authenticating with the device.',
      );
    } on SocketException catch (e) {
      throw SetupNetworkException(
        'Unable to reach device at $root: ${e.message}',
      );
    } catch (e) {
      if (e is SetupAuthException ||
          e is SetupRateLimitException ||
          e is SetupNetworkException) {
        rethrow;
      }
      throw SetupNetworkException('Authentication error: $e');
    }
  }

  /// GET /api/setup/networks
  Future<List<WifiNetworkInfo>> getAvailableNetworks(
    String sessionToken, {
    String? baseUrl,
  }) async {
    final root = baseUrl ?? PiConfig.baseUrl;
    final uri = Uri.parse('$root/api/setup/networks');

    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $sessionToken',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        throw const SetupAuthException(
          'Session expired or invalid. Please re-enter your setup PIN.',
        );
      }

      if (response.statusCode == 429) {
        throw const SetupRateLimitException();
      }

      if (response.statusCode != 200) {
        throw SetupNetworkException(
          'Failed to scan Wi-Fi networks (HTTP ${response.statusCode}).',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final rawList = json['networks'] as List<dynamic>? ?? [];
      return rawList
          .map((item) => WifiNetworkInfo.fromJson(item as Map<String, dynamic>))
          .toList();
    } on TimeoutException {
      throw const SetupNetworkException(
        'Network scan timed out. The device may still be scanning.',
      );
    } on SocketException catch (e) {
      throw SetupNetworkException('Unable to reach device: ${e.message}');
    } catch (e) {
      if (e is SetupAuthException ||
          e is SetupRateLimitException ||
          e is SetupNetworkException) {
        rethrow;
      }
      throw SetupNetworkException('Wi-Fi scan failed: $e');
    }
  }

  /// POST /api/setup/wifi
  Future<WifiProvisionResponseModel> provisionWifi(
    String sessionToken, {
    required String ssid,
    required String password,
    bool hidden = false,
    int timeoutSeconds = 30,
    String? baseUrl,
  }) async {
    final root = baseUrl ?? PiConfig.baseUrl;
    final uri = Uri.parse('$root/api/setup/wifi');

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $sessionToken',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'ssid': ssid,
              'password': password,
              'hidden': hidden,
              'timeout_seconds': timeoutSeconds,
            }),
          )
          .timeout(PiConfig.connectionTimeout);

      if (response.statusCode == 401) {
        throw const SetupAuthException(
          'Session expired. Please re-authenticate to provision Wi-Fi.',
        );
      }

      if (response.statusCode == 429) {
        throw const SetupRateLimitException();
      }

      if (response.statusCode != 200) {
        throw SetupNetworkException(
          'Failed to submit Wi-Fi configuration (HTTP ${response.statusCode}).',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return WifiProvisionResponseModel.fromJson(json);
    } on TimeoutException {
      throw const SetupNetworkException(
        'Timed out submitting Wi-Fi configuration to device.',
      );
    } on SocketException catch (e) {
      throw SetupNetworkException('Unable to reach device: ${e.message}');
    } catch (e) {
      if (e is SetupAuthException ||
          e is SetupRateLimitException ||
          e is SetupNetworkException) {
        rethrow;
      }
      throw SetupNetworkException('Wi-Fi submission failed: $e');
    }
  }

  /// GET /api/setup/connection-status
  Future<ConnectionStatusModel> getConnectionStatus(
    String sessionToken, {
    String? baseUrl,
  }) async {
    final root = baseUrl ?? PiConfig.baseUrl;
    final uri = Uri.parse('$root/api/setup/connection-status');

    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $sessionToken',
              'Accept': 'application/json',
            },
          )
          .timeout(PiConfig.connectionTimeout);

      if (response.statusCode == 401) {
        throw const SetupAuthException('Session expired or cancelled.');
      }

      if (response.statusCode == 429) {
        throw const SetupRateLimitException();
      }

      if (response.statusCode != 200) {
        throw SetupNetworkException(
          'Failed to check connection status (HTTP ${response.statusCode}).',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return ConnectionStatusModel.fromJson(json);
    } on TimeoutException {
      throw const SetupNetworkException(
        'Timed out querying connection status.',
      );
    } on SocketException catch (e) {
      throw SetupNetworkException('Lost connection to device: ${e.message}');
    } catch (e) {
      if (e is SetupAuthException ||
          e is SetupRateLimitException ||
          e is SetupNetworkException) {
        rethrow;
      }
      throw SetupNetworkException('Connection check error: $e');
    }
  }

  /// POST /api/setup/cancel
  Future<void> cancelSetupSession(
    String sessionToken, {
    String? baseUrl,
  }) async {
    final root = baseUrl ?? PiConfig.baseUrl;
    final uri = Uri.parse('$root/api/setup/cancel');

    try {
      await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $sessionToken',
              'Accept': 'application/json',
            },
          )
          .timeout(PiConfig.connectionTimeout);
    } catch (_) {
      // Best-effort cancellation: local session is invalidated regardless.
    }
  }
}
