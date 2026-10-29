import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alien_reader_app/core/constants/app_strings.dart';
import 'package:alien_reader_app/features/device/domain/reader_device.dart';
import 'package:alien_reader_app/features/settings/presentation/settings_screen.dart';
import 'package:alien_reader_app/shared/widgets/section_header.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
}

void main() {
  testWidgets('four sections with icon headers, no Profile duplicates', (
    tester,
  ) async {
    await _pump(tester, const SettingsScreen());

    final headers = tester.widgetList<SectionHeader>(
      find.byType(SectionHeader),
    );
    expect(headers.map((h) => h.title), [
      'Reader',
      'Scanning',
      'Audio',
      'About',
    ]);
    expect(headers.every((h) => h.icon != null), isTrue);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(8));

    expect(find.text('Add Device (QR Setup)'), findsNothing);
    expect(find.text('Device Information'), findsNothing);
    expect(find.text('Theme Mode'), findsNothing);
    expect(find.text('Naadh v${AppStrings.appVersion}'), findsOneWidget);
  });

  testWidgets('reader subtitles follow the connection status', (tester) async {
    await _pump(tester, const SettingsScreen());
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);

    await _pump(
      tester,
      const SettingsScreen(
        status: ReaderConnectionStatus.connected,
        wifiNetworkName: 'Home-Studio-WiFi',
      ),
    );
    expect(find.text('Home-Studio-WiFi'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('Connection Status opens the connection sheet callback', (
    tester,
  ) async {
    var opened = false;
    await _pump(tester, SettingsScreen(onOpenConnection: () => opened = true));

    await tester.tap(find.text('Connection Status'));
    expect(opened, isTrue);
  });
}
