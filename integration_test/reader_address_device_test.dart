// Real phone, real reader: the reader address comes from the saved reader
// record. Needs the reader on the same Wi-Fi; READER_IP is its LAN address.
//
//   flutter test integration_test/reader_address_device_test.dart -d <id> \
//     --dart-define=READER_IP=192.168.1.16
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/features/device/data/models/saved_device.dart';
import 'package:alien_reader_app/features/device/data/raspberry_pi_device.dart';
import 'package:alien_reader_app/features/device/data/services/device_storage_service.dart';
import 'package:alien_reader_app/features/device/data/services/pi_api_service.dart';
import 'package:alien_reader_app/features/device/data/services/reader_address.dart';

const _readerIp = String.fromEnvironment('READER_IP');
const _id = 'NAADH-E2E-0001';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved address is used for the whole session', (t) async {
    expect(_readerIp, isNotEmpty, reason: 'pass READER_IP');
    final report = <String, Object?>{};
    await t.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = DeviceStorageService();
      final address = ReaderAddress(storage: storage);
      final sent = <String>[];
      final device = RaspberryPiDevice(
        apiService: PiApiService(
          baseUrl: () {
            sent.add(address.current);
            return address.current;
          },
        ),
      );

      // 1. Paired with a typed address.
      final typed = 'http://$_readerIp:8000';
      await storage.saveDevice(
        SavedDevice(
          deviceId: _id,
          lastKnownAddress: typed,
          createdAt: DateTime.now(),
        ),
      );
      await storage.setActiveDeviceId(_id);
      report['typed_candidates'] = await address.candidatesFor(_id);
      report['typed_found'] = await address.resolve();
      report['typed_current'] = address.current;

      await device.startSession('Address test');
      final trigger = await device.triggerCaptureAsync();
      final page = trigger['page_number'] as int;
      String outcome;
      try {
        final r = await device.pollPageUntilReady(page, maxAttempts: 60);
        outcome = 'READY (${(r['text'] as String? ?? '').length} chars)';
      } catch (e) {
        outcome = 'reader reported: $e';
      }
      report['capture'] = {'page': page, 'outcome': outcome};
      report['image_url'] = device.getFullUrl(trigger['image_url'] as String?);
      await device.endSession();
      report['hosts_used_in_session'] = sent
          .map((u) => Uri.parse(u).authority)
          .toSet()
          .toList();

      // 2. Same reader, no typed address: its own name is tried first, then
      // the old shared default.
      await storage.saveDevice(
        SavedDevice(deviceId: _id, createdAt: DateTime.now()),
      );
      report['name_candidates'] = await address.candidatesFor(_id);
      report['name_found'] = await address.resolve();
      report['name_current'] = address.current;
      device.dispose();
    });
    // ignore: avoid_print
    print('E2E_REPORT reader_address ${jsonEncode(report)}');
    expect(report['typed_current'], 'http://$_readerIp:8000');
    expect(report['hosts_used_in_session'], ['$_readerIp:8000']);
    // Its own name comes first; the shared default only as a fallback.
    // (Whether drpi2copy1.local answers depends on mDNS on the day: on
    // 2026-11-08 it resolved to IPv6 only, which the reader does not serve.)
    expect(report['name_candidates'], [
      'http://naadh-e2e-0001.local:8000',
      'http://drpi2copy1.local:8000',
    ]);
  });
}
