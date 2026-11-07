import 'dart:async';

/// A saved reader was added or changed.
class DeviceChange {
  const DeviceChange(this.deviceId, {this.readyToConnect = false});

  final String deviceId;

  /// True once the reader is confirmed on the home network, so the app
  /// should connect to it now.
  final bool readyToConnect;
}

/// App-wide signal that the saved-reader list changed.
///
/// Screens that show saved readers (Home, Profile) stay alive in the tab
/// stack and only read storage once; they listen here to reload.
abstract final class DeviceEvents {
  static final StreamController<DeviceChange> _changes =
      StreamController<DeviceChange>.broadcast();

  static Stream<DeviceChange> get changes => _changes.stream;

  static void notify(DeviceChange change) => _changes.add(change);
}
