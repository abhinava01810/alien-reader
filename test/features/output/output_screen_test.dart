import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alien_reader_app/features/document/data/models/saved_document.dart';
import 'package:alien_reader_app/features/output/presentation/output_screen.dart';

final _doc = SavedDocument(
  documentId: 'd1',
  documentTitle: 'Doc',
  captureDate: DateTime(2026),
  originalText: 'Raw OCR words',
  summaryText: 'Short AI summary',
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('Original and Summary tabs show the matching text', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(OutputScreen(initialDocument: _doc)));
    await tester.pump();

    expect(find.text('Raw OCR words'), findsOneWidget);
    expect(find.text('Short AI summary'), findsNothing);

    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();

    expect(find.text('Short AI summary'), findsOneWidget);
    expect(find.text('Raw OCR words'), findsNothing);
  });

  testWidgets('player bar shows play button and 1x/1.5x/2x speeds', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(OutputScreen(initialDocument: _doc)));
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(find.text('1.5×'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
  });

  testWidgets('shows empty state when document has no text', (tester) async {
    final empty = SavedDocument(
      documentId: 'd2',
      documentTitle: 'Empty',
      captureDate: DateTime(2026),
      originalText: '  ',
      summaryText: '',
    );
    await tester.pumpWidget(_wrap(OutputScreen(initialDocument: empty)));
    await tester.pump();

    expect(find.text('No text extracted'), findsOneWidget);
  });

  testWidgets('shows shimmer instead of text while processing', (tester) async {
    await tester.pumpWidget(
      _wrap(OutputScreen(initialDocument: _doc, isProcessing: true)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.bySemanticsLabel('Loading text'), findsOneWidget);
    expect(find.text('Raw OCR words'), findsNothing);
    expect(find.text('No text extracted'), findsNothing);
  });

  testWidgets('a newly processed capture replaces the shown document', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(OutputScreen(initialDocument: _doc)));
    await tester.pump();
    expect(find.text('Raw OCR words'), findsOneWidget);

    final fresh = SavedDocument(
      documentId: 'd3',
      documentTitle: 'Fresh',
      captureDate: DateTime(2026, 2),
      originalText: 'Text read on the phone',
      summaryText: 'Phone summary',
    );
    await tester.pumpWidget(
      _wrap(OutputScreen(initialDocument: _doc, latestDocument: fresh)),
    );
    await tester.pump();

    expect(find.text('Text read on the phone'), findsOneWidget);
    expect(find.text('Raw OCR words'), findsNothing);
  });
}
