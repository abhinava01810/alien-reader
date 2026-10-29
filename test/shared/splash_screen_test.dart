import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alien_reader_app/shared/widgets/splash_screen.dart';

void main() {
  testWidgets('splash shows the Naadh wordmark, then reveals the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: SplashGate(child: Text('app body'))),
    );

    expect(find.text('Naadh'), findsOneWidget);
    expect(find.byType(SplashScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.text('app body'), findsOneWidget);
  });
}
