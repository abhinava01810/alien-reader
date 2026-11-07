import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/features/document/data/models/saved_document.dart';
import 'package:alien_reader_app/features/document/data/services/document_storage_service.dart';
import 'package:alien_reader_app/features/document/presentation/saved_document_detail_screen.dart';

SavedDocument _doc({String? original, String? summary}) => SavedDocument(
  documentId: 'd1',
  documentTitle: 'Doc',
  captureDate: DateTime(2026),
  originalText: 'text',
  summaryText: 'summary',
  originalAudioPath: original,
  summaryAudioPath: summary,
);

void main() {
  group('saved document titles', () {
    test('read as number, date and time', () {
      expect(
        DocumentStorageService.scanTitle(12, DateTime(2026, 11, 8, 0, 3)),
        'Scan 12, 8 Nov 2026 at 00:03',
      );
    });

    test('numbers keep counting across sessions and restarts', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await DocumentStorageService().nextScanNumber(), 1);
      expect(await DocumentStorageService().nextScanNumber(), 2);
      expect(await DocumentStorageService().nextScanNumber(), 3);
    });

    test('the first number follows documents already saved', () async {
      final existing = [
        _doc().toJsonString(),
        SavedDocument(
          documentId: 'd2',
          documentTitle: 'Scan Page 1',
          captureDate: DateTime(2026),
          originalText: 'x',
          summaryText: 'y',
        ).toJsonString(),
      ];
      SharedPreferences.setMockInitialValues({
        'alien_reader_saved_documents': existing,
      });
      expect(await DocumentStorageService().nextScanNumber(), 3);
    });
  });

  group('Read on a saved document', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('naadh_audio'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('uses the saved audio file when it is there', () {
      final f = File('${dir.path}/original_audio.wav')
        ..writeAsBytesSync(List.filled(2000, 1));
      expect(savedAudioPathFor(_doc(original: f.path), 'original'), f.path);
    });

    test('falls back to speech when the file is missing or empty', () {
      final header = File('${dir.path}/summary_audio.wav')
        ..writeAsBytesSync(List.filled(44, 0));
      expect(savedAudioPathFor(_doc(), 'original'), isNull);
      expect(
        savedAudioPathFor(_doc(original: '${dir.path}/gone.wav'), 'original'),
        isNull,
      );
      expect(savedAudioPathFor(_doc(summary: header.path), 'summary'), isNull);
    });
  });
}
