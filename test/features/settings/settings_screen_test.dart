import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alien_reader_app/features/settings/presentation/settings_screen.dart';
import 'package:alien_reader_app/shared/widgets/section_header.dart';

void main() {
  testWidgets('every section uses SectionHeader with an icon', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    final headers = tester.widgetList<SectionHeader>(
      find.byType(SectionHeader),
    );
    expect(headers.map((h) => h.title), [
      'Device',
      'Appearance & Theme',
      'Scanning & Processing',
      'Audio & Synthesis',
      'About',
    ]);
    expect(headers.every((h) => h.icon != null), isTrue);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(10));
  });

  testWidgets('Connection Status tile opens the sheet callback', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(onOpenConnection: () => opened = true)),
    );

    await tester.tap(find.text('Connection Status'));
    expect(opened, isTrue);
  });

  testWidgets('Connection Status tile is hidden without a callback', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    expect(find.text('Connection Status'), findsNothing);
  });
}
