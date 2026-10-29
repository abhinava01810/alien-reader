import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/features/device/data/services/device_storage_service.dart';
import 'package:alien_reader_app/features/device/data/services/pi_api_service.dart';
import 'package:alien_reader_app/features/device/presentation/wifi_onboarding_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestApp({
    required PiApiService apiService,
    required DeviceStorageService storageService,
  }) {
    return MaterialApp(
      home: WifiOnboardingScreen(
        deviceId: 'NAADH-000123',
        apiService: apiService,
        storageService: storageService,
      ),
    );
  }

  testWidgets('renders PIN authentication screen initially', (
    WidgetTester tester,
  ) async {
    final mockClient = MockClient((request) async {
      return http.Response('{}', 200);
    });

    final apiService = PiApiService(client: mockClient);
    final storageService = DeviceStorageService();

    await tester.pumpWidget(
      buildTestApp(apiService: apiService, storageService: storageService),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wi-Fi Setup'), findsOneWidget);
    expect(find.text('Device ID: NAADH-000123'), findsOneWidget);
    expect(find.text('AUTHENTICATE DEVICE'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('shows validation error when authenticating with empty PIN', (
    WidgetTester tester,
  ) async {
    final mockClient = MockClient((request) async {
      return http.Response('{}', 200);
    });

    final apiService = PiApiService(client: mockClient);
    final storageService = DeviceStorageService();

    await tester.pumpWidget(
      buildTestApp(apiService: apiService, storageService: storageService),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('AUTHENTICATE DEVICE'));
    await tester.tap(find.text('AUTHENTICATE DEVICE'));
    await tester.pumpAndSettle();

    expect(
      find.text('Please enter the device setup PIN or secret.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'authenticates and renders network list with mock mode notice banner',
    (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/setup/session') {
          return http.Response(
            jsonEncode({'token': 'test-session-token', 'expires_in': 900}),
            200,
          );
        }
        if (request.url.path == '/api/setup/status') {
          return http.Response(
            jsonEncode({
              'device_id': 'NAADH-000123',
              'is_provisioned': false,
              'setup_state': 'READY_FOR_SETUP',
              'network_state': {'connected': false},
              'auth_required': true,
              'live_mutations_enabled': false,
              'backend': 'MOCK',
              'mock_mode': true,
              'transport_security': {'scheme': 'http', 'encrypted': false},
            }),
            200,
          );
        }
        if (request.url.path == '/api/setup/networks') {
          return http.Response(
            jsonEncode({
              'networks': [
                {
                  'ssid': 'Home-Studio-WiFi',
                  'signal_strength': 90,
                  'security': 'WPA2',
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiService = PiApiService(client: mockClient);
      final storageService = DeviceStorageService();

      await tester.pumpWidget(
        buildTestApp(apiService: apiService, storageService: storageService),
      );
      await tester.pumpAndSettle();

      // Enter PIN
      await tester.enterText(find.byType(TextField), 'valid-secret');
      await tester.ensureVisible(find.text('AUTHENTICATE DEVICE'));
      await tester.tap(find.text('AUTHENTICATE DEVICE'));
      await tester.pumpAndSettle();

      // Verify mock mode banner is prominently displayed
      expect(find.text('Simulated / Demo Mode Active'), findsOneWidget);

      // Verify scanned network is rendered
      expect(find.text('Home-Studio-WiFi'), findsOneWidget);
      expect(find.text('WPA2 • 90% signal'), findsOneWidget);
    },
  );

  testWidgets('handles HTTP 401 authentication error gracefully', (
    WidgetTester tester,
  ) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/setup/session') {
        return http.Response(
          jsonEncode({'detail': 'Invalid setup secret'}),
          401,
        );
      }
      return http.Response('Not Found', 404);
    });

    final apiService = PiApiService(client: mockClient);
    final storageService = DeviceStorageService();

    await tester.pumpWidget(
      buildTestApp(apiService: apiService, storageService: storageService),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'wrong-secret');
    await tester.ensureVisible(find.text('AUTHENTICATE DEVICE'));
    await tester.tap(find.text('AUTHENTICATE DEVICE'));
    await tester.pumpAndSettle();

    expect(
      find.text('Authentication failed. Invalid device setup PIN or secret.'),
      findsOneWidget,
    );
  });

  testWidgets('handles HTTP 429 rate limit error gracefully', (
    WidgetTester tester,
  ) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/setup/session') {
        return http.Response(jsonEncode({'detail': 'Rate limited'}), 429);
      }
      return http.Response('Not Found', 404);
    });

    final apiService = PiApiService(client: mockClient);
    final storageService = DeviceStorageService();

    await tester.pumpWidget(
      buildTestApp(apiService: apiService, storageService: storageService),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'any-secret');
    await tester.ensureVisible(find.text('AUTHENTICATE DEVICE'));
    await tester.tap(find.text('AUTHENTICATE DEVICE'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Too many failed attempts. The device is temporarily locked out. Please wait and try again.',
      ),
      findsOneWidget,
    );
  });
}
