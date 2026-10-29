import 'cloud_api_service.dart';

/// A reader claimed by the signed-in account (`DeviceOut`).
class CloudDevice {
  const CloudDevice({
    required this.id,
    required this.serialNumber,
    required this.deviceName,
    this.lastSeenAt,
    this.deactivatedAt,
  });

  factory CloudDevice.fromJson(Map<String, dynamic> json) => CloudDevice(
    id: (json['id'] as num).toInt(),
    serialNumber: json['serial_number'] as String,
    deviceName: json['device_name'] as String,
    lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? ''),
    deactivatedAt: DateTime.tryParse(json['deactivated_at'] as String? ?? ''),
  );

  final int id;
  final String serialNumber;
  final String deviceName;
  final DateTime? lastSeenAt;
  final DateTime? deactivatedAt;

  bool get isActive => deactivatedAt == null;
}

/// Device pairing against the Naadh cloud API.
///
/// A scanned serial number only identifies a reader; ownership is proven by
/// the claim secret, which is sent once here and never stored or logged.
class DeviceCloudService {
  DeviceCloudService({CloudApiService? api})
    : _api = api ?? CloudApiService.instance;

  final CloudApiService _api;

  Future<CloudDevice> claimDevice(
    String serialNumber,
    String claimSecret,
    String deviceName,
  ) async {
    final body = await _api.post(
      '/devices/claim',
      json: {
        'serial_number': serialNumber.trim(),
        'claim_secret': claimSecret.trim(),
        'device_name': deviceName.trim(),
      },
      auth: true,
    );
    return CloudDevice.fromJson(body as Map<String, dynamic>);
  }

  Future<List<CloudDevice>> getDevices() async {
    final body = await _api.get('/devices') as List<dynamic>;
    return body
        .map((e) => CloudDevice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deactivateDevice(int id) => _api.delete('/devices/$id');
}
