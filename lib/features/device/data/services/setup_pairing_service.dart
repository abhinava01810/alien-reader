import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/provisioning_models.dart';

/// Where to find the reader while it is running its setup hotspot.
abstract final class PairingConfig {
  /// Name of the Wi-Fi hotspot the reader broadcasts during setup.
  static const String hotspotName = 'NAADH-Setup';

  /// Address of the reader's setup API on its own hotspot. Override at build
  /// time with `--dart-define=NAADH_SETUP_BASE_URL=http://<address>:<port>`.
  static const String defaultBaseUrl = String.fromEnvironment(
    'NAADH_SETUP_BASE_URL',
    defaultValue: 'http://10.42.0.1:8000',
  );

  /// Port of the reader's API when an entered address has none.
  static const int defaultPort = 8000;

  /// Turns what a person typed ("192.168.1.16", "http://host:8000/") into a
  /// base URL, adding http:// and the reader's port when missing. Null when
  /// it is not a usable address.
  static String? normalizeAddress(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final port = uri.hasPort ? uri.port : defaultPort;
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    return '${uri.scheme}://$host:$port';
  }
}

/// The reader gave no answer at all (no route, timeout, dropped link), as
/// opposed to answering with an error. After the Wi-Fi details are sent this
/// is expected: the reader drops its hotspot to join the network.
class DeviceUnreachableException extends SetupNetworkException {
  const DeviceUnreachableException(super.message);
}

/// Reader's answer to `POST /api/setup/session`.
class PairingSession {
  const PairingSession({
    required this.pendingId,
    this.token,
    this.expiresInSeconds,
  });

  /// Identifier to poll until the button on the device is pressed.
  final String pendingId;

  /// Present only if the reader approved the session immediately.
  final String? token;

  final int? expiresInSeconds;
}

/// Outcome of one `GET /api/setup/session/{pending_id}` poll.
sealed class PollResult {
  const PollResult();
}

/// The button has not been pressed yet.
class PollPending extends PollResult {
  const PollPending();
}

/// The button was pressed; [token] authorises the rest of setup.
class PollApproved extends PollResult {
  const PollApproved(this.token);
  final String token;
}

/// The pairing window closed (HTTP 410) before the button was pressed.
class PollExpired extends PollResult {
  const PollExpired();
}

/// The reader refused the request.
class PollDenied extends PollResult {
  const PollDenied();
}

/// Reader's answer to `POST /api/setup/wifi`.
class WifiSubmitResult {
  const WifiSubmitResult({this.message});
  final String? message;
}

/// Talks to the reader's setup API while the phone is on its hotspot.
///
/// Flow: [startSession] -> [pollSession] until approved -> [getNetworks] ->
/// [submitWifi]. No secret is sent to start a session: the person proves they
/// are holding the device by pressing its physical button.
///
/// The Wi-Fi password is only ever sent in the [submitWifi] body, and is never
/// kept, logged, or included in an error message.
class SetupPairingService {
  SetupPairingService({
    http.Client? client,
    String? baseUrl,
    this.viaHotspot = true,
  }) : _client = client ?? http.Client(),
       baseUrl = _trimSlash(baseUrl ?? PairingConfig.defaultBaseUrl);

  final http.Client _client;
  final String baseUrl;

  /// True when the reader is reached on its own setup hotspot. False when
  /// the person typed an address for a reader already on a network: then
  /// connection errors report the real failure, not the hotspot.
  final bool viaHotspot;

  static const Duration _callTimeout = Duration(seconds: 8);
  static const Duration _scanTimeout = Duration(seconds: 25);

  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// `POST /api/setup/session` with no secret.
  Future<PairingSession> startSession() async {
    final res = await _send(
      () => _client.post(
        _uri('/api/setup/session'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: '{}',
      ),
      _callTimeout,
      'start setup',
    );
    _rejectCommonErrors(res, 'start setup');

    final body = _decode(res.body);
    final token = _firstString(body, _tokenKeys);
    final pendingId = _firstString(body, const [
      'pending_id',
      'pendingId',
      'session_id',
      'id',
    ]);
    if (pendingId == null && token == null) {
      throw const SetupNetworkException(
        'Unexpected reply from the device (no pending_id).',
      );
    }
    return PairingSession(
      pendingId: pendingId ?? '',
      token: token,
      expiresInSeconds: _firstInt(body, const ['expires_in', 'ttl']),
    );
  }

  /// `GET /api/setup/session/{pending_id}`.
  Future<PollResult> pollSession(String pendingId) async {
    final res = await _send(
      () => _client.get(
        _uri('/api/setup/session/${Uri.encodeComponent(pendingId)}'),
        headers: const {'Accept': 'application/json'},
      ),
      _callTimeout,
      'check confirmation',
    );

    if (res.statusCode == 410 || res.statusCode == 404) {
      return const PollExpired();
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      return const PollDenied();
    }
    _rejectCommonErrors(res, 'check confirmation');

    final body = _decode(res.body);
    final token = _firstString(body, _tokenKeys);
    if (token != null) return PollApproved(token);

    final status = (_firstString(body, const ['status', 'state']) ?? '')
        .toLowerCase();
    if (const {
      'denied',
      'rejected',
      'cancelled',
      'canceled',
    }.contains(status)) {
      return const PollDenied();
    }
    if (const {'expired', 'timeout', 'timed_out'}.contains(status)) {
      return const PollExpired();
    }
    return const PollPending();
  }

  /// `GET /api/setup/networks` with the approved session token.
  Future<List<WifiNetworkInfo>> getNetworks(String token) async {
    final res = await _send(
      () => _client.get(
        _uri('/api/setup/networks'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ),
      _scanTimeout,
      'scan for networks',
    );
    _rejectCommonErrors(res, 'scan for networks');

    final decoded = _tryDecode(res.body);
    final raw = decoded is List
        ? decoded
        : (decoded is Map ? decoded['networks'] : null);
    if (raw is! List) return const [];

    final seen = <String>{};
    final networks = <WifiNetworkInfo>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final network = WifiNetworkInfo.fromJson(item);
      if (network.ssid.isEmpty || !seen.add(network.ssid)) continue;
      networks.add(network);
    }
    networks.sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
    return networks;
  }

  /// `POST /api/setup/wifi`. [password] is empty for an open network.
  Future<WifiSubmitResult> submitWifi(
    String token, {
    required String ssid,
    required String password,
    bool hidden = false,
  }) async {
    final res = await _send(
      () => _client.post(
        _uri('/api/setup/wifi'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'ssid': ssid,
          'password': password,
          'hidden': hidden,
          'timeout_seconds': 30,
        }),
      ),
      _callTimeout,
      'send Wi-Fi details',
    );
    _rejectCommonErrors(res, 'send Wi-Fi details');

    final body = _decode(res.body);
    if (body['success'] == false) {
      throw SetupNetworkException(
        _firstString(body, const ['message', 'error', 'detail']) ??
            'The device did not accept the Wi-Fi details.',
      );
    }
    return WifiSubmitResult(message: _firstString(body, const ['message']));
  }

  void dispose() => _client.close();

  // ─── helpers ──────────────────────────────────────────────────────

  static const _tokenKeys = ['token', 'session_token', 'access_token'];

  Future<http.Response> _send(
    Future<http.Response> Function() request,
    Duration timeout,
    String what,
  ) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw DeviceUnreachableException(
        viaHotspot
            ? 'Timed out trying to $what. Check that your phone is still on '
                  '${PairingConfig.hotspotName}.'
            : _unreachableAt(what, 'no reply after ${timeout.inSeconds} s'),
      );
    } on SocketException catch (e) {
      throw DeviceUnreachableException(
        viaHotspot
            ? _unreachable(what)
            : _unreachableAt(what, e.osError?.message ?? e.message),
      );
    } on http.ClientException catch (e) {
      throw DeviceUnreachableException(
        viaHotspot ? _unreachable(what) : _unreachableAt(what, e.message),
      );
    }
  }

  String _unreachable(String what) =>
      "Couldn't reach the device to $what. Check that your phone is joined "
      'to ${PairingConfig.hotspotName}.';

  /// Manual address: say where we tried and what actually went wrong.
  String _unreachableAt(String what, String reason) {
    final uri = Uri.parse(baseUrl);
    final cleaned = reason.trim().isEmpty ? 'no connection' : reason.trim();
    return "Couldn't reach the device at ${uri.host}:${uri.port} to $what "
        '($cleaned).';
  }

  void _rejectCommonErrors(http.Response res, String what) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    if (res.statusCode == 401) {
      throw const SetupAuthException(
        'The setup session expired. Please start again.',
      );
    }
    if (res.statusCode == 429) throw const SetupRateLimitException();
    throw SetupNetworkException(
      'The device could not $what (HTTP ${res.statusCode}).',
    );
  }

  static Object? _tryDecode(String body) {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _decode(String body) {
    final decoded = _tryDecode(body);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  static String? _firstString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.isNotEmpty) return value;
      if (value is num) return value.toString();
    }
    return null;
  }

  static int? _firstInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) return value.toInt();
    }
    return null;
  }
}
