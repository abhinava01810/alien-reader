import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alien_reader_app/features/document/data/services/pdf_service.dart';

void main() {
  // Regression: "Save Complete Document" failed with "Null check operator
  // used on a null value" because the PDF read page numbers outside a page.
  test('PDFs generate, including multi-page text', () async {
    final dir = await Directory.systemTemp.createTemp('pdf');
    addTearDown(() => dir.delete(recursive: true));
    final service = PdfService();
    final short = await service.generateOriginalTextPdf(
      text: 'A short page of text.',
      documentTitle: 'Scan Page 1',
      captureDate: DateTime(2026, 11, 7),
      outputPath: '${dir.path}/original.pdf',
    );
    final long = await service.generateSummaryPdf(
      text: List.filled(400, 'A long line of summary text.').join('\n'),
      documentTitle: 'Scan Page 2',
      captureDate: DateTime(2026, 11, 7),
      outputPath: '${dir.path}/summary.pdf',
    );
    final oneHugeLine = await service.generateOriginalTextPdf(
      text: List.filled(2000, 'word').join(' '),
      documentTitle: 'Scan Page 3',
      captureDate: DateTime(2026, 11, 7),
      outputPath: '${dir.path}/huge.pdf',
    );
    for (final f in [short, long, oneHugeLine]) {
      final head = String.fromCharCodes(f.readAsBytesSync().take(5));
      expect(head, '%PDF-');
    }
  });
}
