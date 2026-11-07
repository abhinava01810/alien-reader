// Real Android hotspot join from the pairing screen. With the reader NOT in
// setup mode this exercises the permission prompt, Android's own "Connect"
// dialog and the fallback to joining by hand. With the reader in setup mode
// and HOTSPOT_TEST_PASSWORD given, it should reach "Press the button".
//
// The password is only passed in for the run (never stored in source).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:alien_reader_app/features/device/data/services/network_binding.dart';
import 'package:alien_reader_app/features/device/presentation/pairing/device_pairing_screen.dart';

const _password = String.fromEnvironment(
  'HOTSPOT_TEST_PASSWORD',
  defaultValue: 'not-the-real-password',
);
const _expectJoin = bool.fromEnvironment('EXPECT_JOIN');

class _OneRunPasswords extends HotspotPasswordStore {
  @override
  Future<String?> read() async => _password;
  @override
  Future<void> save(String password) async {}
  @override
  Future<void> clear() async {}
}

String _texts() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data)
    .whereType<String>()
    .join(' / ');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('join NAADH-Setup from the app', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DevicePairingScreen(
          deviceId: 'NAADH-TEST',
          hotspotPasswords: _OneRunPasswords(),
          joinTimeout: const Duration(seconds: 40),
        ),
      ),
    );
    // Permission prompt + Android's dialog + up to 40 s search.
    final watch = Stopwatch()..start();
    var outcome = 'timeout';
    while (watch.elapsed < const Duration(seconds: 90)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();
      if (find.textContaining('Press the button').evaluate().isNotEmpty) {
        outcome = 'joined';
        break;
      }
      if (find.textContaining("Couldn't").evaluate().isNotEmpty ||
          find
              .textContaining('needs the Wi-Fi permission')
              .evaluate()
              .isNotEmpty) {
        outcome = 'fallback';
        break;
      }
    }
    // ignore: avoid_print
    print(
      'HOTSPOT_RESULT outcome=$outcome after=${watch.elapsed.inSeconds}s '
      'screen="${_texts()}"',
    );
    expect(outcome, _expectJoin ? 'joined' : 'fallback');
    expect(find.text('Continue'), _expectJoin ? findsNothing : findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await const PlatformNetworkBinding().release();
  });
}
