// Real app, real reader, real phone: fires the same event the pairing screen
// sends when it confirms the reader is on the home network, then checks what
// Home shows. Run with --no-uninstall so the stored sign-in is kept.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:alien_reader_app/app/app.dart';
import 'package:alien_reader_app/features/auth/presentation/login_screen.dart';
import 'package:alien_reader_app/features/device/data/device_events.dart';
import 'package:alien_reader_app/features/home/presentation/home_screen.dart';

List<String> _homeTexts() => find
    .descendant(of: find.byType(HomeScreen), matching: find.byType(Text))
    .evaluate()
    .map((e) => (e.widget as Text).data)
    .whereType<String>()
    .toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Home shows the reader right after pairing connects', (t) async {
    final r = <String, Object?>{};
    Future<void> waitFor(bool Function() done, Duration timeout) async {
      final watch = Stopwatch()..start();
      while (!done() && watch.elapsed < timeout) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await t.pump();
      }
    }

    await t.pumpWidget(const AlienReaderApp());
    await waitFor(
      () => find.byType(HomeScreen).evaluate().isNotEmpty ||
          find.byType(LoginScreen).evaluate().isNotEmpty,
      const Duration(seconds: 30),
    );
    expect(find.byType(LoginScreen), findsNothing, reason: 'not signed in');
    await waitFor(
      () => _homeTexts().isNotEmpty,
      const Duration(seconds: 10),
    );
    r['before'] = _homeTexts().take(4).toList();

    // What DevicePairingScreen._onConfirmed sends.
    final watch = Stopwatch()..start();
    DeviceEvents.notify(
      const DeviceChange('NAADH-TEST', readyToConnect: true),
    );
    String? firstChange;
    await waitFor(() {
      final texts = _homeTexts();
      if (firstChange == null && !texts.contains('Set up your Naadh reader')) {
        firstChange = '${watch.elapsedMilliseconds} ms: ${texts.take(3)}';
      }
      return texts.contains('Connected');
    }, const Duration(seconds: 45));
    r['left_setup_card'] = firstChange;
    r['connected_after_ms'] = watch.elapsedMilliseconds;
    r['after'] = _homeTexts().take(6).toList();
    // ignore: avoid_print
    print('E2E_REPORT home_after_pairing ${jsonEncode(r)}');
    // ignore: avoid_print
    print('E2E_SCREENSHOT_NOW');
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 4)));
    expect(_homeTexts(), contains('Connected'));
    expect(_homeTexts(), isNot(contains('Set up your Naadh reader')));
  });
}
