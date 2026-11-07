// End-to-end runs of the real app against the real paired reader, on a real
// phone, with no manual taps. Each test prints one `E2E_REPORT <name> {...}`
// line with what actually happened.
//
// Needs: the phone signed in to the app (run with --no-uninstall so the
// stored session survives), the reader on the same network, and a page in
// front of the reader's camera. Phone-side processing needs a Gemini key,
// either already saved in the app's Settings or passed for the run with
// --dart-define=GEMINI_TEST_KEY=... (cleared again afterwards).
//
//   flutter test integration_test/real_reader_e2e_test.dart -d <device> \
//     --no-uninstall --dart-define-from-file=dart_defines.json
//
// The background/resume test waits for the app to be sent to the background
// and brought back from outside the test (see tool/e2e_background.sh).
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:alien_reader_app/app/app.dart';
import 'package:alien_reader_app/core/constants/pi_config.dart';
import 'package:alien_reader_app/features/auth/presentation/login_screen.dart';
import 'package:alien_reader_app/features/document/data/services/document_storage_service.dart';
import 'package:alien_reader_app/features/document/presentation/document_results_screen.dart';
import 'package:alien_reader_app/features/document/presentation/saved_document_detail_screen.dart';
import 'package:alien_reader_app/features/home/presentation/home_screen.dart';
import 'package:alien_reader_app/features/output/presentation/output_screen.dart';
import 'package:alien_reader_app/features/phone_processing/data/phone_processing_settings.dart';
import 'package:alien_reader_app/features/processing/presentation/processing_screen.dart';
import 'package:alien_reader_app/shared/widgets/app_bottom_nav.dart';

/// Where the test itself reads the reader's own results to compare against.
/// Defaults to the app's address.
const _readerUrl = String.fromEnvironment(
  'READER_URL',
  defaultValue: PiConfig.baseUrl,
);
const _geminiTestKey = String.fromEnvironment('GEMINI_TEST_KEY');

final _settings = PhoneProcessingSettings();
final _storage = DocumentStorageService();
bool? _originalPhoneMode;
bool _clearKeyAfter = false;
Set<String> _docsBefore = {};

bool _has(Finder f) => f.evaluate().isNotEmpty;

Finder _inHome(Finder f) =>
    find.descendant(of: find.byType(HomeScreen), matching: f);

Future<bool> _waitFor(
  WidgetTester t,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < timeout) {
    if (done()) return true;
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await t.pump();
  }
  return done();
}

Future<void> _idle(WidgetTester t, Duration d) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < d) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await t.pump();
  }
}

List<String> _textsUnder(Finder scope) => find
    .descendant(of: scope, matching: find.byWidgetPredicate((w) => true))
    .evaluate()
    .map((e) => e.widget)
    .map(
      (w) => w is Text
          ? w.data ?? w.textSpan?.toPlainText()
          : w is SelectableText
          ? w.data
          : null,
    )
    .whereType<String>()
    .where((s) => s.trim().isNotEmpty)
    .toList();

String _snackText() => _textsUnder(find.byType(SnackBar)).join(' | ');

void _report(String name, Map<String, Object?> data) {
  // ignore: avoid_print
  print('E2E_REPORT $name ${jsonEncode(data)}');
}

MainTab _currentTab(WidgetTester t) =>
    t.widget<AppBottomNav>(find.byType(AppBottomNav)).currentTab;

Future<void> _openTab(WidgetTester t, String label) async {
  await t.tap(
    find.descendant(
      of: find.byType(AppBottomNav),
      matching: find.text(label),
    ),
  );
  await _idle(t, const Duration(milliseconds: 800));
}

Future<void> _startApp(WidgetTester t, Map<String, Object?> r) async {
  await t.pumpWidget(const AlienReaderApp());
  await _waitFor(
    t,
    () => _has(find.byType(HomeScreen)) || _has(find.byType(LoginScreen)),
    timeout: const Duration(seconds: 40),
  );
  if (_has(find.byType(LoginScreen))) {
    r['blocked'] = 'App opened on the login screen: not signed in on this phone';
    _report('startup', r);
    fail(r['blocked']! as String);
  }
}

/// Taps Reconnect if needed and waits for the Home status bar to say
/// "Connected".
Future<void> _connect(WidgetTester t, Map<String, Object?> r) async {
  final connected = _inHome(find.text('Connected'));
  final reconnect = _inHome(find.text('Reconnect'));
  final setupCard = _inHome(find.text('Scan QR code'));
  // Home shows a spinner until it has looked up the saved reader.
  await _waitFor(
    t,
    () => _has(connected) || _has(reconnect) || _has(setupCard),
    timeout: const Duration(seconds: 20),
  );
  if (_has(setupCard)) {
    r['blocked'] =
        'Home shows "Set up your Naadh reader": no paired reader is saved '
        'on this phone';
    fail(r['blocked']! as String);
  }
  if (!_has(connected) && !_has(reconnect)) {
    r['blocked'] =
        'Home never showed the reader status bar: '
        '${_textsUnder(find.byType(HomeScreen)).take(12).toList()}';
    fail(r['blocked']! as String);
  }
  if (_has(connected)) {
    r['connect'] = 'already connected';
    return;
  }
  final watch = Stopwatch()..start();
  await t.tap(reconnect.first);
  await _waitFor(
    t,
    () => _has(connected) || _snackText().contains('Connection failed'),
    timeout: const Duration(seconds: 45),
  );
  if (!_has(connected)) {
    r['connect'] = 'FAILED after ${watch.elapsed.inSeconds}s: ${_snackText()}';
    fail('Could not connect: ${_snackText()}');
  }
  r['connect'] = 'connected in ${watch.elapsed.inMilliseconds} ms';
}

Future<void> _setPhoneMode(bool on, Map<String, Object?> r) async {
  if (on && await _settings.geminiKey() == null) {
    if (_geminiTestKey.isEmpty) {
      r['blocked'] =
          'Process on phone needs a Gemini key: none saved in Settings and '
          'no GEMINI_TEST_KEY given';
      fail(r['blocked']! as String);
    }
    await _settings.saveGeminiKey(_geminiTestKey);
    _clearKeyAfter = true;
  }
  await _settings.setEnabled(on);
  r['process_on_phone'] = on;
}

Future<Map<String, Object?>> _readerCapture(int page) async {
  try {
    final res = await http
        .get(Uri.parse('$_readerUrl/capture/$page'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return {'http': res.statusCode};
    return jsonDecode(res.body) as Map<String, Object?>;
  } catch (e) {
    return {'error': '$e'};
  }
}

String _short(String? s, [int n = 160]) {
  final t = (s ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= n ? t : '${t.substring(0, n)}…';
}

/// Plays [path] for a moment and reports whether the position moved.
Future<Map<String, Object?>> _playFile(WidgetTester t, String? path) async {
  if (path == null) return {'file': 'none'};
  final f = File(path);
  if (!f.existsSync()) return {'file': 'missing', 'path': path};
  final player = AudioPlayer();
  try {
    final result = await t.runAsync(() async {
      await player.play(DeviceFileSource(path));
      await Future<void>.delayed(const Duration(seconds: 2));
      final pos = await player.getCurrentPosition();
      final dur = await player.getDuration();
      await player.stop();
      return {
        'bytes': f.lengthSync(),
        'played_ms': pos?.inMilliseconds,
        'duration_ms': dur?.inMilliseconds,
      };
    });
    return result ?? {'error': 'no result'};
  } catch (e) {
    return {'error': '$e'};
  } finally {
    await t.runAsync(player.dispose);
  }
}

/// Presses Capture page on Home and follows the app until it settles:
/// the Output tab, the old results page, an error on the Processing screen,
/// or a capture failure snackbar.
Future<Map<String, Object?>> _captureOnce(
  WidgetTester t, {
  required bool expectPhone,
}) async {
  final r = <String, Object?>{};
  final capture = _inHome(find.text('Capture page'));
  await t.ensureVisible(capture);
  final watch = Stopwatch()..start();
  await t.tap(capture);

  bool? onPhone;
  final subtitles = <String>{};
  String? processingError;
  String? landing;
  await _waitFor(t, () {
    if (_has(find.byType(ProcessingScreen))) {
      final p = t.widget<ProcessingScreen>(find.byType(ProcessingScreen));
      onPhone ??= p.onPhone;
      for (final s in _textsUnder(find.byType(ProcessingScreen))) {
        if (s.startsWith('Page ')) subtitles.add(s);
      }
      final texts = _textsUnder(find.byType(ProcessingScreen)).join(' | ');
      if (texts.contains('Exception') ||
          texts.contains('No text detected') ||
          texts.contains('Try again') ||
          texts.toLowerCase().contains('failed:')) {
        processingError = texts;
        return true;
      }
      return false;
    }
    if (_has(find.byType(DocumentResultsScreen))) {
      landing = 'Document Results page';
      return true;
    }
    if (_snackText().contains('Capture failed')) {
      landing = 'snackbar: ${_snackText()}';
      return true;
    }
    if (onPhone != null && _currentTab(t) == MainTab.output) {
      landing = 'Output tab';
      return true;
    }
    return false;
  }, timeout: const Duration(seconds: 180));
  r['elapsed_s'] = watch.elapsed.inSeconds;
  r['processed_on'] = onPhone == null ? 'unknown' : (onPhone! ? 'phone' : 'reader');
  r['mode_matches'] = onPhone == expectPhone;
  r['progress_seen'] = subtitles.toList();
  if (processingError != null) {
    r['landed'] = 'stayed on Processing with an error';
    r['error'] = _short(processingError, 400);
    return r;
  }
  r['landed'] = landing ?? 'timed out (tab ${_currentTab(t).name})';
  if (landing != 'Output tab') return r;

  await _idle(t, const Duration(seconds: 1));
  final docs = await t.runAsync(_storage.loadAllDocuments) ?? [];
  docs.sort((a, b) => b.captureDate.compareTo(a.captureDate));
  final saved = docs.isEmpty ? null : docs.first;
  r['saved_title'] = saved?.documentTitle;
  r['saved_id'] = saved?.documentId;
  final page = int.tryParse(
    RegExp(r'(\d+)$').firstMatch(saved?.documentTitle ?? '')?.group(1) ?? '',
  );
  r['page'] = page;

  final shown = _textsUnder(find.byType(OutputScreen)).join('\n');
  final text = (saved?.originalText ?? '').trim();
  final summary = (saved?.summaryText ?? '').trim();
  r['text_chars'] = text.length;
  r['text_start'] = _short(text);
  r['output_shows_saved_text'] = text.isNotEmpty && shown.contains(text);

  if (onPhone == false && page != null) {
    final pi = await t.runAsync(() => _readerCapture(page)) ?? {};
    final piText = ((pi['text'] as String?) ?? '').trim();
    final piSummary = ((pi['summary'] as String?) ?? '').trim();
    r['matches_reader_text'] = piText.isNotEmpty && piText == text;
    r['matches_reader_summary'] = piSummary.isNotEmpty && piSummary == summary;
    if (pi.containsKey('error') || pi.containsKey('http')) {
      r['reader_lookup'] = pi;
    }
  }

  // Original audio, played from the Output tab's own player.
  final play = find.descendant(
    of: find.byType(OutputScreen),
    matching: find.byIcon(Icons.play_arrow_rounded),
  );
  if (_has(play)) {
    await t.tap(play);
    final playing = await _waitFor(
      t,
      () => _has(
        find.descendant(
          of: find.byType(OutputScreen),
          matching: find.byIcon(Icons.pause_rounded),
        ),
      ),
      timeout: const Duration(seconds: 8),
    );
    r['output_original_audio_plays'] = playing;
    if (playing) {
      await t.tap(
        find.descendant(
          of: find.byType(OutputScreen),
          matching: find.byIcon(Icons.pause_rounded),
        ),
      );
    }
  } else {
    r['output_original_audio_plays'] = 'no enabled play button';
  }

  await t.tap(
    find.descendant(of: find.byType(OutputScreen), matching: find.text('Summary')),
  );
  await _idle(t, const Duration(seconds: 1));
  final shownSummary = _textsUnder(find.byType(OutputScreen)).join('\n');
  r['summary_start'] = _short(summary);
  r['output_shows_saved_summary'] =
      summary.isNotEmpty && shownSummary.contains(summary);
  r['summary_audio_file'] = await _playFile(t, saved?.summaryAudioPath);
  await t.tap(
    find.descendant(of: find.byType(OutputScreen), matching: find.text('Original')),
  );
  await _idle(t, const Duration(milliseconds: 500));
  return r;
}

bool _captureOk(Map<String, Object?> c, {required bool phone}) =>
    c['landed'] == 'Output tab' &&
    c['mode_matches'] == true &&
    c['output_shows_saved_text'] == true &&
    c['output_shows_saved_summary'] == true &&
    c['output_original_audio_plays'] == true &&
    (phone || c['matches_reader_text'] == true);

Future<void> _captureTest(
  WidgetTester t, {
  required String name,
  required bool phone,
  required int pages,
}) async {
  final r = <String, Object?>{};
  try {
    await _setPhoneMode(phone, r);
    await _startApp(t, r);
    await _connect(t, r);
    final runs = <Map<String, Object?>>[];
    for (var i = 0; i < pages; i++) {
      if (_currentTab(t) != MainTab.home) await _openTab(t, 'Home');
      await _waitFor(t, () => _has(_inHome(find.text('Connected'))));
      final c = await _captureOnce(t, expectPhone: phone);
      runs.add(c);
      if (c['landed'] != 'Output tab') break;
    }
    r['captures'] = runs;
    if (pages > 1) {
      final nums = runs.map((c) => c['page']).toList();
      r['page_numbers'] = nums;
      if (_currentTab(t) != MainTab.home) await _openTab(t, 'Home');
      r['home_read_button'] = _textsUnder(
        find.byType(HomeScreen),
      ).where((s) => s.startsWith('Read ')).toList();
    }
    _report(name, r);
    expect(
      runs.length == pages && runs.every((c) => _captureOk(c, phone: phone)),
      isTrue,
      reason: jsonEncode(r),
    );
    if (pages > 1) {
      final nums = runs.map((c) => c['page'] as int?).toList();
      for (var i = 1; i < nums.length; i++) {
        expect(nums[i], (nums[i - 1] ?? -1) + 1, reason: 'page numbers $nums');
      }
    }
  } catch (e) {
    r['exception'] ??= _short('$e', 600);
    _report(name, r);
    rethrow;
  } finally {
    await t.pumpWidget(const SizedBox());
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const long = Timeout(Duration(minutes: 12));

  setUpAll(() async {
    _originalPhoneMode = await _settings.isEnabled();
    _docsBefore = (await _storage.loadAllDocuments())
        .map((d) => d.documentId)
        .toSet();
  });

  tearDownAll(() async {
    await _settings.setEnabled(_originalPhoneMode ?? false);
    if (_clearKeyAfter) await _settings.clearGeminiKey();
    // Leave the person's Files tab as it was.
    final created = (await _storage.loadAllDocuments()).where(
      (d) => !_docsBefore.contains(d.documentId),
    );
    var removed = 0;
    for (final d in created) {
      await _storage.deleteDocument(d.documentId);
      removed++;
    }
    _report('cleanup', {
      'process_on_phone_restored_to': _originalPhoneMode,
      'test_documents_removed': removed,
    });
  });

  testWidgets('preflight: reader address resolves and answers', (t) async {
    final host = Uri.parse(PiConfig.baseUrl).host;
    final r = <String, Object?>{'app_reader_url': PiConfig.baseUrl};
    await t.runAsync(() async {
      try {
        final addrs = await InternetAddress.lookup(
          host,
        ).timeout(const Duration(seconds: 8));
        r['resolves_to'] = addrs.map((a) => a.address).toList();
      } catch (e) {
        r['resolves_to'] = 'FAILED: ${_short('$e')}';
      }
      try {
        final res = await http
            .get(Uri.parse('${PiConfig.baseUrl}/status'))
            .timeout(const Duration(seconds: 8));
        r['status'] = '${res.statusCode} ${_short(res.body)}';
      } catch (e) {
        r['status'] = 'FAILED: ${_short('$e')}';
      }
    });
    _report('preflight', r);
    expect(r['status'], startsWith('200'));
  });

  testWidgets(
    'capture, processed on the reader, lands on Output',
    (t) => _captureTest(t, name: 'reader_single', phone: false, pages: 1),
    timeout: long,
  );

  testWidgets(
    'capture, processed on the phone, lands on Output',
    (t) => _captureTest(t, name: 'phone_single', phone: true, pages: 1),
    timeout: long,
  );

  testWidgets(
    'three-page session, processed on the reader',
    (t) => _captureTest(t, name: 'reader_multi', phone: false, pages: 3),
    timeout: long,
  );

  testWidgets(
    'three-page session, processed on the phone',
    (t) => _captureTest(t, name: 'phone_multi', phone: true, pages: 3),
    timeout: long,
  );

  testWidgets('saved capture appears in Files, reopens, audio plays', (
    t,
  ) async {
    final r = <String, Object?>{};
    try {
      await _setPhoneMode(false, r);
      await _startApp(t, r);
      await _connect(t, r);
      final c = await _captureOnce(t, expectPhone: false);
      r['capture'] = c;
      if (c['landed'] != 'Output tab') fail('Capture did not finish');
      final title = c['saved_title'] as String;
      final id = c['saved_id'] as String;
      final saved = (await t.runAsync(_storage.loadAllDocuments) ?? [])
          .firstWhere((d) => d.documentId == id);

      await _openTab(t, 'Files');
      final card = find.text(title);
      final listed = await _waitFor(
        t,
        () => _has(card),
        timeout: const Duration(seconds: 10),
      );
      r['listed_in_files'] = listed;
      r['files_titles'] = _textsUnder(
        find.byType(Scrollable),
      ).where((s) => s.startsWith('Scan ')).take(6).toList();
      if (!listed) fail('Not listed in Files');
      await t.tap(card.first);
      final opened = await _waitFor(
        t,
        () => _has(find.byType(SavedDocumentDetailScreen)),
        timeout: const Duration(seconds: 10),
      );
      r['reopened'] = opened;
      if (!opened) fail('Did not open');
      await _idle(t, const Duration(seconds: 1));
      final detail = _textsUnder(
        find.byType(SavedDocumentDetailScreen),
      ).join('\n');
      r['detail_shows_text'] = detail.contains(saved.originalText.trim());
      r['detail_shows_summary'] = detail.contains(saved.summaryText.trim());
      r['detail_has_image'] = _has(
        find.descendant(
          of: find.byType(SavedDocumentDetailScreen),
          matching: find.byType(Image),
        ),
      );
      r['saved_files'] = {
        'image': saved.imagePath != null && File(saved.imagePath!).existsSync(),
        'original_audio':
            saved.originalAudioPath != null &&
            File(saved.originalAudioPath!).existsSync(),
        'summary_audio':
            saved.summaryAudioPath != null &&
            File(saved.summaryAudioPath!).existsSync(),
        'pdf':
            saved.originalPdfPath != null &&
            File(saved.originalPdfPath!).existsSync(),
      };

      // What the detail screen's "Read" button does.
      final read = find.descendant(
        of: find.byType(SavedDocumentDetailScreen),
        matching: find.text('Read'),
      );
      if (_has(read)) {
        await t.tap(read.first);
        r['detail_read_button_becomes_stop'] = await _waitFor(
          t,
          () => _has(
            find.descendant(
              of: find.byType(SavedDocumentDetailScreen),
              matching: find.text('Stop'),
            ),
          ),
          timeout: const Duration(seconds: 6),
        );
        if (_has(find.text('Stop'))) await t.tap(find.text('Stop').first);
      }
      // The saved audio files themselves, played directly.
      r['saved_original_audio_plays'] = await _playFile(
        t,
        saved.originalAudioPath,
      );
      r['saved_summary_audio_plays'] = await _playFile(
        t,
        saved.summaryAudioPath,
      );
      _report('files', r);
      final orig = r['saved_original_audio_plays']! as Map;
      expect(
        r['detail_shows_text'] == true &&
            r['detail_shows_summary'] == true &&
            ((orig['played_ms'] as int?) ?? 0) > 0,
        isTrue,
        reason: jsonEncode(r),
      );
    } catch (e) {
      r['exception'] ??= _short('$e', 600);
      _report('files', r);
      rethrow;
    } finally {
      await t.pumpWidget(const SizedBox());
    }
  }, timeout: long);

  testWidgets('background and resume: what Home shows', (t) async {
    final r = <String, Object?>{};
    List<String> homeState() => _textsUnder(find.byType(HomeScreen))
        .where(
          (s) =>
              s.contains('Connect') ||
              s.contains('Disconnect') ||
              s.contains('Busy') ||
              s.contains('Read ') ||
              s.contains('Capture') ||
              s.contains('camera') ||
              s.contains('Camera') ||
              s.contains('stream') ||
              s.contains('reader'),
        )
        .toList();
    Future<String> readerStatus() async =>
        await t.runAsync(() async {
          try {
            final res = await http
                .get(Uri.parse('$_readerUrl/status'))
                .timeout(const Duration(seconds: 6));
            return _short(res.body, 200);
          } catch (e) {
            return 'FAILED: ${_short('$e')}';
          }
        }) ??
        '';
    try {
      await _startApp(t, r);
      await _connect(t, r);
      await _idle(t, const Duration(seconds: 3));
      r['before'] = {'home': homeState(), 'reader': await readerStatus()};

      // Ask the host to press Home, wait, then reopen the app.
      // ignore: avoid_print
      print('E2E_BACKGROUND_NOW');
      final binding = WidgetsBinding.instance;
      final watch = Stopwatch()..start();
      var wentBackground = false;
      while (watch.elapsed < const Duration(minutes: 4)) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        final s = binding.lifecycleState;
        if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
          wentBackground = true;
        }
        if (wentBackground && s == AppLifecycleState.resumed) break;
      }
      r['went_background'] = wentBackground;
      r['resumed_after_s'] = watch.elapsed.inSeconds;
      if (!wentBackground) fail('App was never sent to the background');

      final after = <String, Object?>{};
      final sinceResume = Stopwatch()..start();
      await t.pump();
      for (final at in [0, 5, 15, 30]) {
        final wait = Duration(seconds: at) - sinceResume.elapsed;
        if (wait > Duration.zero) await _idle(t, wait);
        after['${at}s'] = {
          'tab': _currentTab(t).name,
          'home': homeState(),
          'snackbar': _snackText(),
          'reader': await readerStatus(),
        };
      }
      r['after_resume'] = after;
      // Does Capture still work without pressing Reconnect?
      final capture = _inHome(find.text('Capture page'));
      final enabled =
          _has(capture) &&
          t
                  .widget<OutlinedButton>(
                    find.ancestor(
                      of: capture,
                      matching: find.byType(OutlinedButton),
                    ),
                  )
                  .onPressed !=
              null;
      r['capture_button_enabled_after_resume'] = enabled;
      _report('background_resume', r);
    } catch (e) {
      r['exception'] ??= _short('$e', 600);
      _report('background_resume', r);
      rethrow;
    } finally {
      await t.pumpWidget(const SizedBox());
    }
  }, timeout: long);

  testWidgets('next capture waits until the reader has finished the last page', (
    t,
  ) async {
    // Phone mode finishes before the reader does (the reader still processes
    // every capture), so this is where overlapping captures could happen.
    final r = <String, Object?>{};
    String now() => DateTime.now().toIso8601String().substring(11, 23);
    try {
      await _setPhoneMode(true, r);
      await _startApp(t, r);
      await _connect(t, r);
      final first = await _captureOnce(t, expectPhone: true);
      r['page1'] = {'landed': first['landed'], 'error': first['error']};
      r['page1_phone_done_at'] = now();

      // Back to Home whichever way page 1 ended.
      if (_has(find.text('Return to Home'))) {
        await t.tap(find.text('Return to Home'));
      }
      await _waitFor(t, () => !_has(find.byType(ProcessingScreen)));
      await _idle(t, const Duration(milliseconds: 600));
      if (_currentTab(t) != MainTab.home) await _openTab(t, 'Home');
      await _waitFor(t, () => _has(_inHome(find.text('Connected'))));

      final capture = _inHome(find.text('Capture page'));
      await t.ensureVisible(capture);
      r['page2_tapped_at'] = now();
      await t.tap(capture);
      String? waitingShownAt;
      String? page2ProcessingAt;
      await _waitFor(t, () {
        if (waitingShownAt == null &&
            _snackText().contains('Waiting for the reader to finish page')) {
          waitingShownAt = now();
        }
        final processing = find.byType(ProcessingScreen);
        if (_has(processing) &&
            t.widget<ProcessingScreen>(processing).pageNumber >= 2) {
          page2ProcessingAt = now();
          return true;
        }
        return _snackText().contains('still working on page');
      }, timeout: const Duration(minutes: 7));
      r['waiting_message_shown_at'] = waitingShownAt;
      r['page2_processing_shown_at'] = page2ProcessingAt;
      r['gave_up'] = _snackText().contains('still working on page');
      if (page2ProcessingAt != null) {
        r['page2_number'] = t
            .widget<ProcessingScreen>(find.byType(ProcessingScreen))
            .pageNumber;
        // Let page 2 settle so the test leaves nothing half done.
        await _waitFor(
          t,
          () =>
              !_has(find.byType(ProcessingScreen)) ||
              _has(find.text('Return to Home')),
          timeout: const Duration(minutes: 3),
        );
      }
      _report('sequential', r);
      expect(page2ProcessingAt, isNotNull, reason: jsonEncode(r));
    } catch (e) {
      r['exception'] ??= _short('$e', 600);
      _report('sequential', r);
      rethrow;
    } finally {
      await t.pumpWidget(const SizedBox());
    }
  }, timeout: long);
}
