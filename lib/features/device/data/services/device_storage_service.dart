import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_device.dart';

/// Service responsible for persisting identified and configured Naadh devices.
///
/// NOTE: Wi-Fi passwords, setup PINs, and bearer tokens are NEVER persisted
/// in this or any local preferences storage.
class DeviceStorageService {
  static const _devicesKey = 'alien_reader_saved_devices';
  static const _activeDeviceIdKey = 'alien_reader_active_device_id';
  static const _readerConnectedBeforeKey = 'alien_reader_connected_before';

  /// Records that this phone has had a live session with a reader, so Home
  /// keeps showing the reader (with Reconnect) instead of first-time setup.
  /// Covers readers that were connected without going through QR pairing.
  Future<void> markReaderConnected() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_readerConnectedBeforeKey, true);
  }

  /// True if a reader was paired or has ever connected on this phone.
  Future<bool> hasKnownReader() async {
    if ((await getAllDevices()).isNotEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_readerConnectedBeforeKey) ?? false;
  }

  Future<List<SavedDevice>> getAllDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_devicesKey);
    if (rawJson == null || rawJson.isEmpty) return [];

    try {
      final list = jsonDecode(rawJson) as List<dynamic>;
      return list
          .map((item) => SavedDevice.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<SavedDevice?> getDevice(String deviceId) async {
    final devices = await getAllDevices();
    return devices.where((d) => d.deviceId == deviceId).firstOrNull;
  }

  Future<void> saveDevice(SavedDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await getAllDevices();

    final existingIndex = devices.indexWhere(
      (d) => d.deviceId == device.deviceId,
    );
    if (existingIndex >= 0) {
      devices[existingIndex] = device;
    } else {
      devices.add(device);
    }

    final rawJson = jsonEncode(devices.map((d) => d.toJson()).toList());
    await prefs.setString(_devicesKey, rawJson);
  }

  Future<void> updateDeviceSetupStatus(
    String deviceId,
    DeviceSetupStatus status, {
    String? lastKnownAddress,
  }) async {
    final existing = await getDevice(deviceId);
    if (existing != null) {
      final updated = existing.copyWith(
        setupStatus: status,
        lastKnownAddress: lastKnownAddress ?? existing.lastKnownAddress,
        lastSeenAt: DateTime.now(),
      );
      await saveDevice(updated);
    } else {
      final newDevice = SavedDevice(
        deviceId: deviceId,
        setupStatus: status,
        lastKnownAddress: lastKnownAddress,
        createdAt: DateTime.now(),
        lastSeenAt: DateTime.now(),
      );
      await saveDevice(newDevice);
    }
  }

  Future<String?> getActiveDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeDeviceIdKey);
  }

  Future<void> setActiveDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeDeviceIdKey, deviceId);
  }

  Future<void> removeDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await getAllDevices();
    devices.removeWhere((d) => d.deviceId == deviceId);
    final rawJson = jsonEncode(devices.map((d) => d.toJson()).toList());
    await prefs.setString(_devicesKey, rawJson);

    final activeId = await getActiveDeviceId();
    if (activeId == deviceId) {
      await prefs.remove(_activeDeviceIdKey);
    }
  }
}
