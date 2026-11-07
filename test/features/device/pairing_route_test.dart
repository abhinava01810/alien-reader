import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alien_reader_app/app/router.dart';
import 'package:alien_reader_app/features/device/data/models/device_qr_payload.dart';
import 'package:alien_reader_app/features/device/presentation/pairing/device_pairing_screen.dart';

void main() {
  test('a scanned QR hands its hotspot details to the pairing screen', () {
    final qr = DeviceQrPayload.parse(
      'NAADH://setup?device_id=NAADH-000123&ssid=NAADH-Setup'
      '&wifi_password=qr-hotspot-pass',
    );
    final route =
        AppRouter.onGenerateRoute(
              RouteSettings(name: AppRoutes.devicePairing, arguments: qr),
            )
            as MaterialPageRoute;
    final screen = route.builder(_FakeContext()) as DevicePairingScreen;

    expect(screen.deviceId, 'NAADH-000123');
    expect(screen.hotspotSsid, 'NAADH-Setup');
    expect(screen.hotspotPassword, 'qr-hotspot-pass');
  });

  test('a plain device ID still opens pairing without hotspot details', () {
    final route =
        AppRouter.onGenerateRoute(
              const RouteSettings(
                name: AppRoutes.devicePairing,
                arguments: 'NAADH-000123',
              ),
            )
            as MaterialPageRoute;
    final screen = route.builder(_FakeContext()) as DevicePairingScreen;
    expect(screen.hotspotPassword, isNull);
  });
}

class _FakeContext extends Fake implements BuildContext {}
