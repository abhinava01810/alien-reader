// Manual "Advanced: device address" path against a real reader on the home
// network. Stops at the "press the button" step; nothing is configured.
//
//   flutter test integration_test/manual_address_device_test.dart -d <device> \
//     --dart-define=READER_ADDRESS=192.168.1.16 --dart-define=DEAD_ADDRESS=192.168.1.250
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:alien_reader_app/features/device/presentation/pairing/device_pairing_screen.dart';

const _reader = String.fromEnvironment('READER_ADDRESS');
const _dead = String.fromEnvironment('DEAD_ADDRESS');

Future<void> _enterAddressAndContinue(WidgetTester tester, String addr) async {
  await tester.pumpWidget(
    const MaterialApp(home: DevicePairingScreen(deviceId: 'NAADH-TEST')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Advanced: device address'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), addr);
  await tester.tap(find.text('Continue'));
  // Real network: wait up to ~12 s for the screen to change.
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    final waiting = find
        .textContaining('Press the button')
        .evaluate()
        .isNotEmpty;
    final error = find.textContaining("Couldn't").evaluate().isNotEmpty;
    if (waiting || error) break;
  }
}

String _visibleError() => find
    .textContaining("Couldn't")
    .evaluate()
    .map((e) => (e.widget as Text).data ?? '')
    .join(' | ');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reader address without a port reaches the button step', (
    tester,
  ) async {
    await _enterAddressAndContinue(tester, _reader);
    // ignore: avoid_print
    print('MANUAL_OK_ERROR "${_visibleError()}"');
    expect(
      find.textContaining('Press the button'),
      findsOneWidget,
      reason: 'error shown: ${_visibleError()}',
    );
    // Leave: disposing the screen stops polling.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a dead address shows the real failure, not the hotspot', (
    tester,
  ) async {
    await _enterAddressAndContinue(tester, _dead);
    final error = _visibleError();
    // ignore: avoid_print
    print('MANUAL_DEAD_ERROR "$error"');
    expect(error, isNotEmpty);
    expect(error, isNot(contains('NAADH-Setup')));
    expect(error, isNot(contains('no internet')));
    await tester.pumpWidget(const SizedBox());
  });
}
