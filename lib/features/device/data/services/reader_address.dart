import '../../../../core/constants/pi_config.dart';
import 'device_storage_service.dart';
import 'pi_api_service.dart';

/// Reads a reader's `GET /status` at [baseUrl]; null if it does not answer.
typedef ReaderStatusFetcher =
    Future<Map<String, dynamic>?> Function(String baseUrl);

/// Which address the app uses for the reader.
///
/// Every reader unit has its own `.local` name derived from its device ID
/// (see [hostFor]). For the active (paired) reader the app tries, in order:
///   1. an address typed during pairing ("Advanced: device address"),
///   2. the reader's own name, `http://<hostFor(deviceId)>.local:8000`,
///   3. the old shared default, [PiConfig.baseUrl].
/// The first that answers `/status` is used, unless its `device_id` names a
/// different reader. Readers that do not report a `device_id` yet are
/// accepted, so units without the new hostname keep working.
class ReaderAddress {
  ReaderAddress({DeviceStorageService? storage, ReaderStatusFetcher? fetch})
    : _storage = storage ?? DeviceStorageService(),
      _fetch = fetch ?? _fetchStatus;

  /// The address the whole app uses (API calls, images, audio, video).
  static final ReaderAddress instance = ReaderAddress();

  final DeviceStorageService _storage;
  final ReaderStatusFetcher _fetch;

  String _current = PiConfig.baseUrl;

  /// Base URL in use now, e.g. `http://naadh-3f9a1c2b4d5e.local:8000`.
  String get current => _current;

  String get streamUrl => '$_current/camera/stream';

  static const port = 8000;

  /// The reader's hostname for a device ID: the ID in lower case, with any
  /// character other than a-z, 0-9 and "-" replaced by "-".
  /// `NAADH-3F9A1C2B4D5E` → `naadh-3f9a1c2b4d5e`.
  static String hostFor(String deviceId) {
    var host = deviceId.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9-]+'),
      '-',
    );
    host = host.replaceAll(RegExp(r'-{2,}'), '-');
    host = host.replaceAll(RegExp(r'^-+|-+$'), '');
    return host.length > 63 ? host.substring(0, 63) : host;
  }

  /// `http://<hostFor(deviceId)>.local:8000`
  static String urlFor(String deviceId) =>
      'http://${hostFor(deviceId)}.local:$port';

  /// Addresses to try for [deviceId], best first, without duplicates.
  Future<List<String>> candidatesFor(String? deviceId) async {
    final list = <String>[];
    void add(String? url) {
      if (url != null && url.isNotEmpty && !list.contains(url)) list.add(url);
    }

    if (deviceId != null && deviceId.isNotEmpty) {
      add((await _storage.getDevice(deviceId))?.lastKnownAddress);
      if (hostFor(deviceId).isNotEmpty) add(urlFor(deviceId));
    }
    add(PiConfig.baseUrl);
    return list;
  }

  /// Finds where [deviceId] (default: the active reader) answers and makes
  /// that [current]. Returns whether any candidate answered as that reader.
  /// When none does, [current] becomes the best candidate so errors refer to
  /// it.
  Future<bool> resolve({String? deviceId}) async {
    final id = deviceId ?? await _storage.getActiveDeviceId();
    final candidates = await candidatesFor(id);
    // Ask them all at once; take the best one that is the right reader.
    final replies = await Future.wait(candidates.map(_safeFetch));
    for (var i = 0; i < candidates.length; i++) {
      final status = replies[i];
      if (status != null && _isReader(status, id)) {
        _current = candidates[i];
        return true;
      }
    }
    _current = candidates.first;
    return false;
  }

  /// Used by pairing to confirm the reader joined the home network.
  Future<bool> findReader(String deviceId) => resolve(deviceId: deviceId);

  static bool _isReader(Map<String, dynamic> status, String? expectedId) {
    final reported = status['device_id'];
    if (expectedId == null || expectedId.isEmpty) return true;
    if (reported is! String || reported.isEmpty) return true; // older reader
    return reported.trim().toUpperCase() == expectedId.trim().toUpperCase();
  }

  Future<Map<String, dynamic>?> _safeFetch(String baseUrl) async {
    try {
      return await _fetch(baseUrl);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _fetchStatus(String baseUrl) async {
    final api = PiApiService(baseUrl: () => baseUrl);
    try {
      return await api.getStatus();
    } finally {
      api.dispose();
    }
  }
}
