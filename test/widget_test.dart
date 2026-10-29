import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/app/app.dart';

void main() {
  testWidgets('initial app launch renders welcome screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AlienReaderApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Let the splash fade out and its timers finish.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Welcome to Naadh'), findsOneWidget);
  });
}
