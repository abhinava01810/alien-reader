import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/features/device/data/models/saved_device.dart';
import 'package:alien_reader_app/features/device/data/services/device_storage_service.dart';
import 'package:alien_reader_app/features/device/domain/reader_device.dart';
import 'package:alien_reader_app/features/home/presentation/home_screen.dart';

Future<void> _seedDevice() async {
  SharedPreferences.setMockInitialValues({});
  await DeviceStorageService().saveDevice(
    SavedDevice(deviceId: 'naadh-test', createdAt: DateTime(2026)),
  );
}

void main() {
  setUp(() async => _seedDevice());
  group('HomeScreen Layout & Priority Order Tests', () {
    testWidgets('shows first-run setup card when no device is saved', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              status: ReaderConnectionStatus.disconnected,
              onConnect: () {},
              onCapture: () {},
              onFinish: () {},
              pageCount: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Set up your Naadh reader'), findsOneWidget);
      expect(find.text('Scan QR code'), findsOneWidget);
      expect(find.text('Reconnect'), findsNothing);
      expect(find.text('Capture page'), findsNothing);
    });

    testWidgets(
      'shows Disconnected status bar with Reconnect when disconnected',
      (WidgetTester tester) async {
        var connectPressed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeScreen(
                status: ReaderConnectionStatus.disconnected,
                onConnect: () => connectPressed = true,
                onCapture: () {},
                onFinish: () {},
                pageCount: 0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Disconnected'), findsOneWidget);
        expect(find.text('Reconnect'), findsOneWidget);

        await tester.tap(find.text('Reconnect'));
        expect(connectPressed, isTrue);

        // Verify removed items are NOT present
        expect(find.text('Raspberry Pi Feed'), findsNothing);
        expect(find.text('Recent Documents'), findsNothing);
        expect(find.text('Quick Shortcuts'), findsNothing);
      },
    );

    testWidgets(
      'renders Connected status and Disconnect option when connected',
      (WidgetTester tester) async {
        var disconnectPressed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeScreen(
                status: ReaderConnectionStatus.connected,
                onConnect: () {},
                onDisconnect: () => disconnectPressed = true,
                onCapture: () {},
                onFinish: () {},
                pageCount: 0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Connected'), findsOneWidget);
        expect(find.text('Disconnect'), findsOneWidget);

        await tester.tap(find.text('Disconnect'));
        await tester.pumpAndSettle();
        expect(disconnectPressed, isFalse);
        expect(find.text('Disconnect reader?'), findsOneWidget);

        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(disconnectPressed, isTrue);
      },
    );

    testWidgets('renders Capture page and Read buttons with correct states', (
      WidgetTester tester,
    ) async {
      var capturePressed = false;
      var processPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              status: ReaderConnectionStatus.connected,
              onConnect: () {},
              onCapture: () => capturePressed = true,
              onFinish: () => processPressed = true,
              pageCount: 2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Capture page'), findsOneWidget);
      expect(find.text('Read 2 pages'), findsOneWidget);

      await tester.tap(find.text('Capture page'));
      expect(capturePressed, isTrue);

      await tester.tap(find.text('Read 2 pages'));
      expect(processPressed, isTrue);
    });

    testWidgets(
      'renders Captured Pages strip with thumbnails and count badge',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HomeScreen(
                status: ReaderConnectionStatus.connected,
                onConnect: () {},
                onCapture: () {},
                onFinish: () {},
                pageCount: 3,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Captured Pages'), findsOneWidget);
        expect(find.text('3 Pages'), findsOneWidget);
        expect(find.text('Page 1'), findsOneWidget);
        expect(find.text('Page 2'), findsOneWidget);
        expect(find.text('Page 3'), findsOneWidget);
      },
    );

    testWidgets('renders subtle empty state when no pages captured', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              status: ReaderConnectionStatus.connected,
              onConnect: () {},
              onCapture: () {},
              onFinish: () {},
              pageCount: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No pages captured yet'), findsOneWidget);
      expect(find.text('0 Pages'), findsOneWidget);
    });
  });
}
