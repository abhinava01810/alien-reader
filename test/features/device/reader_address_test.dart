import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/features/device/data/models/saved_device.dart';
import 'package:alien_reader_app/features/device/data/services/device_storage_service.dart';
import 'package:alien_reader_app/features/device/data/services/reader_address.dart';

const _default = 'http://drpi2copy1.local:8000';

Future<DeviceStorageService> _storage({
  Map<String, String?> devices = const {},
  String? active,
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = DeviceStorageService();
  for (final e in devices.entries) {
    await storage.saveDevice(
      SavedDevice(
        deviceId: e.key,
        lastKnownAddress: e.value,
        createdAt: DateTime(2026),
      ),
    );
  }
  if (active != null) await storage.setActiveDeviceId(active);
  return storage;
}

/// Readers that answer `/status`, keyed by base URL.
ReaderStatusFetcher _network(Map<String, Map<String, dynamic>> answering) =>
    (url) async => answering[url];

void main() {
  group('hostname for a device ID', () {
    test('lower case, other characters become "-"', () {
      expect(ReaderAddress.hostFor('NAADH-3F9A1C2B4D5E'), 'naadh-3f9a1c2b4d5e');
      expect(ReaderAddress.hostFor('NAADH-000123'), 'naadh-000123');
      expect(ReaderAddress.hostFor(' NAADH_00 12 '), 'naadh-00-12');
      expect(ReaderAddress.hostFor('--NAADH--1--'), 'naadh-1');
    });

    test('URL uses .local and port 8000', () {
      expect(
        ReaderAddress.urlFor('NAADH-000123'),
        'http://naadh-000123.local:8000',
      );
    });
  });

  group('candidates', () {
    test('no paired reader: only the old default', () async {
      final a = ReaderAddress(storage: await _storage());
      expect(await a.candidatesFor(null), [_default]);
    });

    test('paired reader: typed address, its own name, then default', () async {
      final storage = await _storage(
        devices: {'NAADH-000123': 'http://192.168.1.16:8000'},
      );
      final a = ReaderAddress(storage: storage);
      expect(await a.candidatesFor('NAADH-000123'), [
        'http://192.168.1.16:8000',
        'http://naadh-000123.local:8000',
        _default,
      ]);
    });

    test('no typed address: its own name, then default', () async {
      final a = ReaderAddress(
        storage: await _storage(devices: {'NAADH-000123': null}),
      );
      expect(await a.candidatesFor('NAADH-000123'), [
        'http://naadh-000123.local:8000',
        _default,
      ]);
    });
  });

  group('resolve', () {
    test('uses the reader by its own name when it answers', () async {
      final a = ReaderAddress(
        storage: await _storage(devices: {'NAADH-1': null}, active: 'NAADH-1'),
        fetch: _network({
          'http://naadh-1.local:8000': {'device_id': 'NAADH-1'},
          _default: {'device_id': 'NAADH-1'},
        }),
      );
      expect(await a.resolve(), isTrue);
      expect(a.current, 'http://naadh-1.local:8000');
      expect(a.streamUrl, 'http://naadh-1.local:8000/camera/stream');
    });

    test('a typed address wins when it answers', () async {
      final a = ReaderAddress(
        storage: await _storage(
          devices: {'NAADH-1': 'http://192.168.1.16:8000'},
          active: 'NAADH-1',
        ),
        fetch: _network({
          'http://192.168.1.16:8000': {'device_id': 'NAADH-1'},
          'http://naadh-1.local:8000': {'device_id': 'NAADH-1'},
        }),
      );
      await a.resolve();
      expect(a.current, 'http://192.168.1.16:8000');
    });

    test('a stale typed address falls through to the reader name', () async {
      final a = ReaderAddress(
        storage: await _storage(
          devices: {'NAADH-1': 'http://192.168.1.99:8000'},
          active: 'NAADH-1',
        ),
        fetch: _network({
          'http://naadh-1.local:8000': {'device_id': 'NAADH-1'},
        }),
      );
      await a.resolve();
      expect(a.current, 'http://naadh-1.local:8000');
    });

    test('never talks to a different unit at the shared default', () async {
      // Two units on one network: the default name answers as the other one.
      final a = ReaderAddress(
        storage: await _storage(devices: {'NAADH-1': null}, active: 'NAADH-1'),
        fetch: _network({
          _default: {'device_id': 'NAADH-2'},
        }),
      );
      expect(await a.resolve(), isFalse);
      expect(a.current, 'http://naadh-1.local:8000');
    });

    test('an older reader without device_id still works', () async {
      final a = ReaderAddress(
        storage: await _storage(devices: {'NAADH-1': null}, active: 'NAADH-1'),
        fetch: _network({
          _default: {'status': 'AVAILABLE'},
        }),
      );
      expect(await a.resolve(), isTrue);
      expect(a.current, _default);
    });

    test('device IDs match regardless of case', () async {
      final a = ReaderAddress(
        storage: await _storage(
          devices: {'NAADH-ab': null},
          active: 'NAADH-ab',
        ),
        fetch: _network({
          'http://naadh-ab.local:8000': {'device_id': 'naadh-AB'},
        }),
      );
      expect(await a.resolve(), isTrue);
    });

    test('no paired reader: the old default, as before', () async {
      final a = ReaderAddress(
        storage: await _storage(),
        fetch: _network({
          _default: {'status': 'AVAILABLE'},
        }),
      );
      expect(await a.resolve(), isTrue);
      expect(a.current, _default);
    });

    test('pairing a second reader switches to it', () async {
      final storage = await _storage(
        devices: {'NAADH-1': null, 'NAADH-2': null},
        active: 'NAADH-1',
      );
      final a = ReaderAddress(
        storage: storage,
        fetch: _network({
          'http://naadh-1.local:8000': {'device_id': 'NAADH-1'},
          'http://naadh-2.local:8000': {'device_id': 'NAADH-2'},
        }),
      );
      await a.resolve();
      expect(a.current, 'http://naadh-1.local:8000');
      await storage.setActiveDeviceId('NAADH-2');
      await a.resolve();
      expect(a.current, 'http://naadh-2.local:8000');
    });

    test('a reader that throws counts as not answering', () async {
      final a = ReaderAddress(
        storage: await _storage(devices: {'NAADH-1': null}, active: 'NAADH-1'),
        fetch: (url) async => throw Exception('timeout'),
      );
      expect(await a.resolve(), isFalse);
    });
  });
}
