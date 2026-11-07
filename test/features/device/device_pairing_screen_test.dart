import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/features/device/data/device_events.dart';
import 'package:alien_reader_app/features/device/data/models/saved_device.dart';
import 'package:alien_reader_app/features/device/data/services/device_storage_service.dart';
import 'package:alien_reader_app/features/device/data/services/network_binding.dart';
import 'package:alien_reader_app/features/device/data/services/setup_pairing_service.dart';
import 'package:alien_reader_app/features/device/presentation/pairing/device_pairing_screen.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _FakeBinding implements NetworkBinding {
  _FakeBinding({this.joinResult = HotspotJoin.unsupported});

  HotspotJoin joinResult;
  int binds = 0;
  int releases = 0;
  final List<String?> joinPasswords = [];

  @override
  Future<HotspotJoin> joinHotspot({
    required String ssid,
    String? passphrase,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    joinPasswords.add(passphrase);
    return joinResult;
  }

  @override
  Future<bool> bindToWifi() async => ++binds > 0;

  @override
  Future<void> release() async => releases++;
}

/// In-memory stand-in for the encrypted hotspot-password store.
class _Passwords extends HotspotPasswordStore {
  _Passwords([this.value]);
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> save(String password) async => value = password;
  @override
  Future<void> clear() async => value = null;
}

/// A scripted reader. [pollReplies] are served in order, then the last repeats.
class _Reader {
  _Reader({this.pollReplies = const [], this.wifiReply, this.expiresIn = 60});

  final List<http.Response> pollReplies;
  final http.Response Function(http.Request)? wifiReply;

  /// The pairing window the reader reports; null means it reports none.
  final int? expiresIn;
  final List<http.Request> requests = [];
  int polls = 0;

  SetupPairingService service() => SetupPairingService(
    baseUrl: 'http://reader.test:8000',
    client: MockClient((r) async {
      requests.add(r);
      final key = '${r.method} ${r.url.path}';
      if (key == 'POST /api/setup/session') {
        return _json({
          'pending_id': 'p1',
          if (expiresIn != null) 'expires_in': expiresIn,
        }, 202);
      }
      if (key == 'GET /api/setup/session/p1') {
        final i = polls < pollReplies.length ? polls : pollReplies.length - 1;
        polls++;
        return pollReplies[i];
      }
      if (key == 'GET /api/setup/networks') {
        return _json({
          'networks': [
            {'ssid': 'Home-WiFi', 'signal_strength': 80, 'security': 'WPA2'},
            {'ssid': 'Cafe', 'signal_strength': 50, 'security': 'OPEN'},
          ],
        });
      }
      if (key == 'POST /api/setup/wifi') {
        return wifiReply?.call(r) ?? _json({'success': true});
      }
      return http.Response('', 404);
    }),
  );
}

const _pending = 202;

/// Answers the home-network check from a script, counting calls.
class _Probe {
  _Probe(this.answers);

  /// Served in order, then the last one repeats.
  final List<bool> answers;
  int calls = 0;

  Future<bool> call() async {
    final i = calls < answers.length ? calls : answers.length - 1;
    calls++;
    return answers[i];
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required _Reader reader,
  _FakeBinding? binding,
  DeviceStorageService? storage,
  _Probe? probe,
  _Passwords? passwords,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: Text('home-root')),
    ),
  );
  final reachable = probe ?? _Probe([false]);
  navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => DevicePairingScreen(
        deviceId: 'NAADH-000123',
        service: reader.service(),
        binding: binding ?? _FakeBinding(),
        storage: storage,
        pollInterval: const Duration(milliseconds: 100),
        pollTimeout: const Duration(milliseconds: 450),
        probe: reachable.call,
        confirmInterval: const Duration(milliseconds: 100),
        confirmTimeout: const Duration(milliseconds: 400),
        hotspotPasswords: passwords ?? _Passwords(),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await _advance(tester, 6);
  }
}

/// Runs the flow up to submitting the password for Home-WiFi.
Future<void> _submitHomeWifi(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await _advance(tester, 8);
  await tester.tap(find.text('Home-WiFi'));
  await _advance(tester, 2);
  await tester.enterText(find.byType(TextField), 'correct-horse-battery');
  await tester.tap(find.text('Connect'));
  await _advance(tester, 2);
}

/// Lets queued futures and timers run without waiting on animations.
Future<void> _advance(WidgetTester tester, [int ticks = 6]) async {
  for (var i = 0; i < ticks; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('step 1 tells the person to join NAADH-Setup by hand', (
    tester,
  ) async {
    await _pump(tester, reader: _Reader());

    expect(find.text('NAADH-000123'), findsOneWidget);
    expect(find.textContaining('NAADH-Setup'), findsWidgets);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('full flow: button press, network, password, confirmed', (
    tester,
  ) async {
    final reader = _Reader(
      pollReplies: [
        _json({'status': 'pending'}, _pending),
        _json({'status': 'pending'}, _pending),
        _json({'token': 'tok-1'}),
      ],
    );
    final binding = _FakeBinding();
    final storage = DeviceStorageService();
    final probe = _Probe([false, false, true]);
    final events = <DeviceChange>[];
    final sub = DeviceEvents.changes.listen(events.add);
    addTearDown(sub.cancel);
    await _pump(
      tester,
      reader: reader,
      binding: binding,
      storage: storage,
      probe: probe,
    );

    await tester.tap(find.text('Continue'));
    await _advance(tester, 2);

    // Waiting for the physical button.
    expect(
      find.text('Press the button on your device to confirm setup'),
      findsOneWidget,
    );
    expect(binding.binds, 1);

    // The session request carried no secret.
    final start = reader.requests.firstWhere(
      (r) => r.url.path == '/api/setup/session' && r.method == 'POST',
    );
    expect(jsonDecode(start.body), isEmpty);

    await _advance(tester, 8);

    // Approved: the network list appears, fetched with the token.
    expect(find.text('Choose your Wi-Fi'), findsOneWidget);
    expect(find.text('Home-WiFi'), findsOneWidget);
    final scan = reader.requests.firstWhere(
      (r) => r.url.path == '/api/setup/networks',
    );
    expect(scan.headers['Authorization'], 'Bearer tok-1');

    await tester.tap(find.text('Home-WiFi'));
    await _advance(tester, 2);

    // Password step: obscured, with a visibility toggle.
    EditableText field() =>
        tester.widget<EditableText>(find.byType(EditableText).first);
    expect(field().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(field().obscureText, isFalse);

    await tester.enterText(find.byType(TextField), 'correct-horse-battery');
    await tester.tap(find.text('Connect'));
    await _advance(tester, 2);

    final submit = reader.requests.firstWhere(
      (r) => r.url.path == '/api/setup/wifi',
    );
    expect(submit.headers['Authorization'], 'Bearer tok-1');
    final body = jsonDecode(submit.body) as Map<String, dynamic>;
    expect(body['ssid'], 'Home-WiFi');
    expect(body['password'], 'correct-horse-battery');

    // Not a dead end: the app now looks for the reader on the home network.
    expect(
      find.text('Waiting for your reader to join "Home-WiFi"'),
      findsOneWidget,
    );
    expect(binding.releases, greaterThan(0));
    expect(
      (await storage.getDevice('NAADH-000123'))?.setupStatus,
      DeviceSetupStatus.provisioningPending,
    );

    // The third check finds it: configured, active, and back to Home.
    await _advance(tester, 8);
    await tester.pumpAndSettle();
    expect(probe.calls, 3);
    final saved = await storage.getDevice('NAADH-000123');
    expect(saved?.setupStatus, DeviceSetupStatus.configured);
    expect(await storage.getActiveDeviceId(), 'NAADH-000123');
    expect(find.text('home-root'), findsOneWidget);
    expect(find.byType(DevicePairingScreen), findsNothing);
    // Home/Profile reload on the first event; the shell connects on the last.
    expect(events.first.readyToConnect, isFalse);
    expect(events.last.readyToConnect, isTrue);
    expect(events.last.deviceId, 'NAADH-000123');
  });

  testWidgets('no reader after the timeout: plain message and retry', (
    tester,
  ) async {
    final reader = _Reader(
      pollReplies: [
        _json({'token': 'tok-1'}),
      ],
    );
    final storage = DeviceStorageService();
    final probe = _Probe([false]);
    await _pump(tester, reader: reader, storage: storage, probe: probe);

    await _submitHomeWifi(tester);
    await _advance(tester, 10);

    expect(
      find.text("Couldn't confirm your reader rejoined your Wi-Fi"),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Set up Wi-Fi again'), findsOneWidget);
    // Still recorded as being set up, never promoted.
    expect(
      (await storage.getDevice('NAADH-000123'))?.setupStatus,
      DeviceSetupStatus.provisioningPending,
    );

    // Try again runs the check again.
    final callsBefore = probe.calls;
    await tester.tap(find.text('Try again'));
    await _advance(tester, 3);
    expect(probe.calls, greaterThan(callsBefore));
    expect(
      find.text('Waiting for your reader to join "Home-WiFi"'),
      findsOneWidget,
    );
  });

  testWidgets('retry can succeed after a failed confirmation', (tester) async {
    final reader = _Reader(
      pollReplies: [
        _json({'token': 'tok-1'}),
      ],
    );
    final storage = DeviceStorageService();
    // Four misses fill the 400ms window; the retry then finds it.
    final probe = _Probe([false, false, false, false, true]);
    await _pump(tester, reader: reader, storage: storage, probe: probe);

    await _submitHomeWifi(tester);
    await _advance(tester, 10);
    expect(
      find.text("Couldn't confirm your reader rejoined your Wi-Fi"),
      findsOneWidget,
    );

    await tester.tap(find.text('Try again'));
    await _advance(tester, 4);
    await tester.pumpAndSettle();

    expect(find.text('home-root'), findsOneWidget);
    expect(
      (await storage.getDevice('NAADH-000123'))?.setupStatus,
      DeviceSetupStatus.configured,
    );
  });

  testWidgets('"Set up Wi-Fi again" goes back to joining the hotspot', (
    tester,
  ) async {
    final reader = _Reader(
      pollReplies: [
        _json({'token': 'tok-1'}),
      ],
    );
    await _pump(tester, reader: reader);

    await _submitHomeWifi(tester);
    await _advance(tester, 10);
    await tester.tap(find.text('Set up Wi-Fi again'));
    await _advance(tester, 2);

    expect(find.text('Continue'), findsOneWidget);
    expect(find.textContaining('NAADH-Setup'), findsWidgets);
  });

  testWidgets('losing the reader right after sending still confirms', (
    tester,
  ) async {
    final reader = _Reader(
      pollReplies: [
        _json({'token': 'tok-1'}),
      ],
      wifiReply: (_) => throw http.ClientException('connection reset'),
    );
    final storage = DeviceStorageService();
    await _pump(
      tester,
      reader: reader,
      storage: storage,
      probe: _Probe([false, true]),
    );

    await _submitHomeWifi(tester);
    expect(find.textContaining('has left its setup hotspot'), findsOneWidget);

    await _advance(tester, 6);
    await tester.pumpAndSettle();
    expect(find.text('home-root'), findsOneWidget);
    expect(
      (await storage.getDevice('NAADH-000123'))?.setupStatus,
      DeviceSetupStatus.configured,
    );
  });

  testWidgets('410 shows a timeout with a way to start again', (tester) async {
    final reader = _Reader(pollReplies: [http.Response('', 410)]);
    await _pump(tester, reader: reader);

    await tester.tap(find.text('Continue'));
    await _advance(tester, 6);

    expect(find.text('Setup timed out'), findsOneWidget);
    expect(find.text('Start again'), findsOneWidget);

    final sessionsBefore = reader.requests
        .where((r) => r.url.path == '/api/setup/session' && r.method == 'POST')
        .length;
    await tester.tap(find.text('Start again'));
    await _advance(tester, 2);
    final sessionsAfter = reader.requests
        .where((r) => r.url.path == '/api/setup/session' && r.method == 'POST')
        .length;
    expect(sessionsAfter, sessionsBefore + 1);
  });

  testWidgets('giving up while waiting also ends in a timeout', (tester) async {
    // No window reported, so the screen's own limit (450ms here) applies.
    final reader = _Reader(
      pollReplies: [
        _json({'status': 'pending'}, _pending),
      ],
      expiresIn: null,
    );
    await _pump(tester, reader: reader);

    await tester.tap(find.text('Continue'));
    await _advance(tester, 30);

    expect(find.text('Setup timed out'), findsOneWidget);
  });

  testWidgets('wrong password length is caught before anything is sent', (
    tester,
  ) async {
    final reader = _Reader(
      pollReplies: [
        _json({'token': 'tok-1'}),
      ],
    );
    await _pump(tester, reader: reader);

    await tester.tap(find.text('Continue'));
    await _advance(tester, 8);
    await tester.tap(find.text('Home-WiFi'));
    await _advance(tester, 2);

    await tester.enterText(find.byType(TextField), 'short');
    await tester.tap(find.text('Connect'));
    await tester.pump();

    expect(find.textContaining('8-63 characters'), findsOneWidget);
    expect(
      reader.requests.where((r) => r.url.path == '/api/setup/wifi'),
      isEmpty,
    );
  });

  testWidgets('an open network needs no password', (tester) async {
    final reader = _Reader(
      pollReplies: [
        _json({'token': 'tok-1'}),
      ],
    );
    await _pump(tester, reader: reader);

    await tester.tap(find.text('Continue'));
    await _advance(tester, 8);
    await tester.tap(find.text('Cafe'));
    await _advance(tester, 2);

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Connect'));
    await _advance(tester, 4);

    final body =
        jsonDecode(
              reader.requests
                  .firstWhere((r) => r.url.path == '/api/setup/wifi')
                  .body,
            )
            as Map<String, dynamic>;
    expect(body['password'], '');
    expect(find.text('Waiting for your reader to join "Cafe"'), findsOneWidget);
  });

  testWidgets('the device rejecting the details keeps the form open', (
    tester,
  ) async {
    final reader = _Reader(
      pollReplies: [
        _json({'token': 'tok-1'}),
      ],
      wifiReply: (_) => _json({'success': false, 'message': 'Bad passphrase'}),
    );
    await _pump(tester, reader: reader);

    await tester.tap(find.text('Continue'));
    await _advance(tester, 8);
    await tester.tap(find.text('Home-WiFi'));
    await _advance(tester, 2);
    await tester.enterText(find.byType(TextField), 'not-the-password');
    await tester.tap(find.text('Connect'));
    await _advance(tester, 4);

    expect(find.text('Bad passphrase'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    // The password field was cleared after the attempt.
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      isEmpty,
    );
  });

  testWidgets('an unreachable device on step 1 shows how to fix it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = SetupPairingService(
      baseUrl: 'http://reader.test',
      client: MockClient((_) async => throw http.ClientException('no route')),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DevicePairingScreen(
          deviceId: 'NAADH-000123',
          service: service,
          binding: _FakeBinding(),
          hotspotPasswords: _Passwords(),
        ),
      ),
    );

    await tester.tap(find.text('Continue'));
    await _advance(tester, 3);

    expect(find.textContaining("Couldn't reach the device"), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  group('joining the hotspot from the app', () {
    testWidgets('a saved password joins on open and starts setup', (
      tester,
    ) async {
      final binding = _FakeBinding(joinResult: HotspotJoin.connected);
      final reader = _Reader(
        pollReplies: [
          _json({'status': 'pending'}, _pending),
        ],
      );
      await _pump(
        tester,
        reader: reader,
        binding: binding,
        passwords: _Passwords('hotspot-pass'),
        settle: false,
      );

      expect(binding.joinPasswords, ['hotspot-pass']);
      // Already bound to the hotspot network: no generic Wi-Fi bind.
      expect(binding.binds, 0);
      expect(
        find.text('Press the button on your device to confirm setup'),
        findsOneWidget,
      );
    });

    testWidgets('no saved password: nothing happens until asked', (
      tester,
    ) async {
      final binding = _FakeBinding(joinResult: HotspotJoin.connected);
      await _pump(tester, reader: _Reader(), binding: binding);
      expect(binding.joinPasswords, isEmpty);
      expect(find.text('Connect automatically'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('typed password is used, then remembered on success', (
      tester,
    ) async {
      final binding = _FakeBinding(joinResult: HotspotJoin.connected);
      final passwords = _Passwords();
      await _pump(
        tester,
        reader: _Reader(
          pollReplies: [
            _json({'status': 'pending'}, _pending),
          ],
        ),
        binding: binding,
        passwords: passwords,
      );
      await tester.tap(find.text('Connect automatically'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'typed-pass',
      );
      await tester.tap(find.text('Connect'));
      await _advance(tester, 4);

      expect(binding.joinPasswords, ['typed-pass']);
      expect(passwords.value, 'typed-pass');
      expect(
        find.text('Press the button on your device to confirm setup'),
        findsOneWidget,
      );
    });

    testWidgets('declined or not found: falls back to joining by hand', (
      tester,
    ) async {
      final binding = _FakeBinding(joinResult: HotspotJoin.unavailable);
      final passwords = _Passwords('old-pass');
      await _pump(
        tester,
        reader: _Reader(),
        binding: binding,
        passwords: passwords,
      );
      await _advance(tester, 3);

      expect(
        find.textContaining("Couldn't join NAADH-Setup automatically"),
        findsOneWidget,
      );
      expect(find.textContaining('saved password'), findsOneWidget);
      expect(find.text('Or join it by hand'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Connect automatically'), findsOneWidget);
    });

    testWidgets('permission refused: explains and offers the manual path', (
      tester,
    ) async {
      await _pump(
        tester,
        reader: _Reader(),
        binding: _FakeBinding(joinResult: HotspotJoin.permissionDenied),
        passwords: _Passwords('p'),
      );
      await _advance(tester, 3);
      expect(find.textContaining('needs the Wi-Fi permission'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });
  });
}
