import 'dart:convert';

class QrPayloadException implements Exception {
  final String message;
  const QrPayloadException(this.message);

  @override
  String toString() => message;
}

/// Represents the validated contents of a Naadh device onboarding QR code.
///
/// Format: `NAADH://setup?device_id=NAADH-000123`, optionally with the
/// reader's setup hotspot: `&ssid=NAADH-Setup&wifi_password=...`.
///
/// Security & Architectural considerations:
/// - A scanned device ID is an identifier, NOT proof of ownership or an auth token.
/// - The hotspot password is only used to join the reader's setup hotspot.
///   It is kept out of [raw], [additionalParams] and [toString], and must
///   never be logged or shown.
/// - Arbitrary URLs and unsupported schemes are rejected.
/// - Designed with forward-compatibility for optional versioning and setup hints.
class DeviceQrPayload {
  static const String expectedScheme = 'naadh';
  static const String expectedAction = 'setup';

  // Device IDs must be 3-64 chars: alphanumeric with hyphens or underscores
  static final RegExp _deviceIdRegex = RegExp(r'^[a-zA-Z0-9_\-]{3,64}$');

  final String raw;
  final String deviceId;
  final String? version;
  final String? model;
  final Map<String, String> additionalParams;

  /// Name of the reader's setup hotspot, when the QR gives one.
  final String? hotspotSsid;

  /// WPA2 password of the reader's setup hotspot, when the QR gives one.
  final String? hotspotPassword;

  const DeviceQrPayload({
    required this.raw,
    required this.deviceId,
    this.version,
    this.model,
    this.additionalParams = const {},
    this.hotspotSsid,
    this.hotspotPassword,
  });

  static const _ssidKeys = {'ssid', 'wifi_ssid', 'hotspot_ssid'};
  static const _passwordKeys = {'wifi_password', 'hotspot_password'};

  static String? _first(Map<String, String> params, Set<String> keys) {
    for (final k in keys) {
      final v = params[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// WPA2-Personal: 8–63 printable ASCII characters, or 64 hex digits.
  static bool _validWpa2Password(String p) {
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(p)) return true;
    return p.length >= 8 &&
        p.length <= 63 &&
        p.codeUnits.every((c) => c >= 0x20 && c <= 0x7E);
  }

  /// Parses a raw QR code string into a validated [DeviceQrPayload].
  ///
  /// Throws [QrPayloadException] with a descriptive message if the payload is invalid.
  factory DeviceQrPayload.parse(String? rawInput) {
    if (rawInput == null || rawInput.trim().isEmpty) {
      throw const QrPayloadException('QR code is empty.');
    }

    final trimmed = rawInput.trim();

    if (trimmed.length > 1024) {
      throw const QrPayloadException(
        'QR payload exceeds maximum supported length.',
      );
    }

    // Explicitly reject standard web URLs (e.g. http/https) to avoid phishing/redirection
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      throw const QrPayloadException(
        'Invalid QR code: Web URLs are not valid Naadh device setup codes.',
      );
    }

    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      throw const QrPayloadException('Malformed QR format: Not a valid URI.');
    }

    // 1. Verify URI Scheme
    if (uri.scheme.toLowerCase() != expectedScheme) {
      throw QrPayloadException(
        'Unsupported QR code scheme "${uri.scheme}". Expected "$expectedScheme://".',
      );
    }

    // 2. Verify Action / Host / Path
    // NAADH://setup?... -> host is 'setup', path is ''
    // NAADH:/setup?... -> path is '/setup'
    final action = uri.host.isNotEmpty
        ? uri.host.toLowerCase()
        : uri.path.replaceAll('/', '').toLowerCase();

    if (action != expectedAction) {
      throw QrPayloadException(
        'Invalid setup action "$action". Expected "$expectedAction".',
      );
    }

    // 3. Extract and Validate device_id
    final queryParams = uri.queryParameters;
    final deviceId = queryParams['device_id'] ?? queryParams['deviceId'];

    if (deviceId == null || deviceId.trim().isEmpty) {
      throw const QrPayloadException(
        'Missing required parameter "device_id" in QR code.',
      );
    }

    final trimmedDeviceId = deviceId.trim();
    if (!_deviceIdRegex.hasMatch(trimmedDeviceId)) {
      throw const QrPayloadException(
        'Invalid device_id format. Device IDs must be 3-64 alphanumeric characters, hyphens, or underscores.',
      );
    }

    // 4. Optional setup hotspot. Errors never repeat the password.
    final ssid = _first(queryParams, _ssidKeys)?.trim();
    if (ssid != null && (ssid.isEmpty || utf8.encode(ssid).length > 32)) {
      throw const QrPayloadException(
        'Invalid hotspot name in QR code (must be 1-32 bytes).',
      );
    }
    final password = _first(queryParams, _passwordKeys);
    if (password != null && !_validWpa2Password(password)) {
      throw const QrPayloadException(
        'Invalid hotspot password in QR code (WPA2 needs 8-63 characters).',
      );
    }

    // 5. Extract optional versioning and metadata
    final version = queryParams['version'] ?? queryParams['v'];
    final model = queryParams['model'];

    final additional = <String, String>{};
    queryParams.forEach((key, value) {
      if (!const {
            'device_id',
            'deviceId',
            'version',
            'v',
            'model',
          }.contains(key) &&
          !_ssidKeys.contains(key) &&
          !_passwordKeys.contains(key)) {
        additional[key] = value;
      }
    });

    // Never keep the password in the raw text.
    final safeRaw = password == null
        ? trimmed
        : uri
              .replace(
                queryParameters: Map.of(queryParams)
                  ..removeWhere((k, _) => _passwordKeys.contains(k)),
              )
              .toString();

    return DeviceQrPayload(
      raw: safeRaw,
      deviceId: trimmedDeviceId,
      version: version,
      model: model,
      additionalParams: Map.unmodifiable(additional),
      hotspotSsid: ssid,
      hotspotPassword: password,
    );
  }

  /// Attempts to parse [rawInput]. Returns `null` if invalid instead of throwing.
  static DeviceQrPayload? tryParse(String? rawInput) {
    try {
      return DeviceQrPayload.parse(rawInput);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'DeviceQrPayload(deviceId: $deviceId, version: $version, '
      'hotspot: ${hotspotSsid ?? '-'}, '
      'password: ${hotspotPassword == null ? 'none' : 'present'})';
}
