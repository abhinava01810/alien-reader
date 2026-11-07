import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Outcome of asking Android to join the reader's hotspot from the app.
enum HotspotJoin {
  /// Joined, and the app's traffic is bound to that exact network.
  connected,

  /// The person declined Android's prompt, the hotspot was not found, the
  /// password was wrong, or it timed out. Android does not say which.
  unavailable,

  /// The Wi-Fi permission was refused.
  permissionDenied,

  /// Android 9 or older, or not Android.
  unsupported,

  failed,
}

/// Keeps the app's traffic on the Wi-Fi network while the phone is joined to
/// the reader's setup hotspot.
///
/// The hotspot has no internet, so Android may quietly send app traffic over
/// mobile data instead, and requests to the reader then fail. Binding the
/// process to the Wi-Fi network prevents that. It affects every request the
/// app makes, so [release] must be called when setup ends.
abstract class NetworkBinding {
  /// Returns true if app traffic is now pinned to Wi-Fi.
  Future<bool> bindToWifi();

  /// Joins [ssid] from inside the app (Android shows its own "Connect?"
  /// prompt) and binds the app's traffic to it. Asks for the Wi-Fi runtime
  /// permission first. The connection lasts until [release].
  Future<HotspotJoin> joinHotspot({
    required String ssid,
    String? passphrase,
    Duration timeout,
  });

  /// Unbinds and, if the app joined a hotspot, leaves it.
  Future<void> release();
}

/// Android implementation, backed by `MainActivity`.
class PlatformNetworkBinding implements NetworkBinding {
  const PlatformNetworkBinding();

  static const _channel = MethodChannel('naadh/network');

  @override
  Future<bool> bindToWifi() async {
    try {
      return await _channel.invokeMethod<bool>('bindToWifi') ?? false;
    } catch (_) {
      // Not Android, or running in a test: carry on without binding.
      return false;
    }
  }

  @override
  Future<HotspotJoin> joinHotspot({
    required String ssid,
    String? passphrase,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      final permission = await _channel.invokeMethod<String>(
        'requestWifiPermission',
      );
      if (permission == 'unsupported') return HotspotJoin.unsupported;
      if (permission != 'granted') return HotspotJoin.permissionDenied;

      final result = await _channel.invokeMethod<String>('connectToHotspot', {
        'ssid': ssid,
        'passphrase': passphrase,
        'timeoutMs': timeout.inMilliseconds,
      });
      return switch (result) {
        'connected' => HotspotJoin.connected,
        'unavailable' => HotspotJoin.unavailable,
        'unsupported' => HotspotJoin.unsupported,
        _ => HotspotJoin.failed,
      };
    } on MissingPluginException {
      return HotspotJoin.unsupported;
    } catch (_) {
      return HotspotJoin.failed;
    }
  }

  @override
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {}
  }
}

/// A reader's setup-hotspot password (from its QR code), kept only in
/// encrypted storage on this phone after a successful join, one entry per
/// reader. Never logged or shown.
class HotspotPasswordStore {
  HotspotPasswordStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String deviceId) => 'setup_hotspot_password.$deviceId';

  Future<String?> read(String deviceId) async {
    try {
      final value = await _storage.read(key: _key(deviceId));
      return (value == null || value.isEmpty) ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String deviceId, String password) async {
    try {
      await _storage.write(key: _key(deviceId), value: password);
    } catch (_) {}
  }

  Future<void> clear(String deviceId) async {
    try {
      await _storage.delete(key: _key(deviceId));
    } catch (_) {}
  }
}
