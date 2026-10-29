import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alien_reader_app/features/processing/presentation/processing_screen.dart';

void main() {
  testWidgets('shows centered progress and reading label while processing', (
    tester,
  ) async {
    final never = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(home: ProcessingScreen(onProcess: () => never.future)),
    );
    await tester.pump();

    expect(find.text('Reading your document...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('Camera triggered'), findsOneWidget);
  });

  testWidgets('shows the error card instead of the progress hero on failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProcessingScreen(onProcess: () async => throw Exception('boom')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reading your document...'), findsNothing);
    expect(find.text('Capture Error'), findsOneWidget);
    expect(find.text('Return to Home'), findsOneWidget);
  });
}
