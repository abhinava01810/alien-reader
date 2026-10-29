import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/features/document/data/models/saved_document.dart';
import 'package:alien_reader_app/features/files/presentation/files_screen.dart';

SavedDocument _doc(String id, String title, String text) => SavedDocument(
  documentId: id,
  documentTitle: title,
  captureDate: DateTime(2026, 3, 4, 9, 5),
  originalText: text,
  summaryText: 'sum',
);

Future<void> _pump(WidgetTester tester, List<SavedDocument> docs) async {
  SharedPreferences.setMockInitialValues({
    'alien_reader_saved_documents': docs.map((d) => d.toJsonString()).toList(),
  });
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: FilesScreen())),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists title, date and word count', (tester) async {
    await _pump(tester, [_doc('a', 'Invoice', 'one two three four')]);

    expect(find.text('Invoice'), findsOneWidget);
    expect(find.textContaining('4 Mar 2026'), findsOneWidget);
    expect(find.text('4 words'), findsOneWidget);
  });

  testWidgets('falls back to first line of text when title is blank', (
    tester,
  ) async {
    await _pump(tester, [_doc('a', ' ', '\nFirst line here\nsecond')]);

    expect(find.text('First line here'), findsOneWidget);
  });

  testWidgets('shows empty state with no saved files', (tester) async {
    await _pump(tester, []);

    expect(find.text('No saved files'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation and removes the file', (
    tester,
  ) async {
    await _pump(tester, [_doc('a', 'Invoice', 'x y')]);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete document?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Invoice'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    // Deletion touches real file IO, which fake async does not drive.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invoice'), findsNothing);
    expect(find.text('No saved files'), findsOneWidget);
  });
}
