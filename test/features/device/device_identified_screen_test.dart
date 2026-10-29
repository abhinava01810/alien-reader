import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alien_reader_app/features/device/data/models/device_qr_payload.dart';
import 'package:alien_reader_app/features/device/presentation/device_identified_screen.dart';

void main() {
  testWidgets(
    'DeviceIdentifiedScreen renders device ID and unconfigured status',
    (WidgetTester tester) async {
      const payload = DeviceQrPayload(
        raw: 'NAADH://setup?device_id=NAADH-TEST-001&version=1.0',
        deviceId: 'NAADH-TEST-001',
        version: '1.0',
      );

      await tester.pumpWidget(
        const MaterialApp(home: DeviceIdentifiedScreen(payload: payload)),
      );

      // Verify header and device ID
      expect(find.text('Device Setup'), findsOneWidget);
      expect(find.text('Device Detected'), findsOneWidget);
      expect(find.text('NAADH-TEST-001'), findsOneWidget);
      expect(find.text('SERIAL NUMBER'), findsOneWidget);
      expect(find.text('v1.0'), findsOneWidget);

      // Verify explicit honest status label
      expect(
        find.text('Device identified — setup not completed'),
        findsOneWidget,
      );

      // Verify actions
      expect(find.text('CONFIGURE WI-FI'), findsOneWidget);
      expect(find.text('Cancel / Return to App'), findsOneWidget);
    },
  );
}
