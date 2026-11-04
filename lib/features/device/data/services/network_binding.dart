import 'package:flutter/services.dart';

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
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {}
  }
}
