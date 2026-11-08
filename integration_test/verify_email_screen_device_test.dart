// Shows the email-code screen on a real phone so its accessibility tree can
// be read from the host (uiautomator) at each E2E_A11Y marker. The server is
// scripted: the live backend does not take {email, otp} yet, and no account
// is created.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:alien_reader_app/core/services/auth_service_cloud.dart';
import 'package:alien_reader_app/core/services/cloud_api_service.dart';
import 'package:alien_reader_app/core/theme/app_theme.dart';
import 'package:alien_reader_app/features/auth/presentation/verify_email_banner.dart';
import 'package:alien_reader_app/features/auth/presentation/verify_email_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('code screen on the phone: initial, wrong code, resend', (
    t,
  ) async {
    final sent = <String>[];
    final auth = CloudAuthService(
      api: CloudApiService(
        tokens: MemoryTokenStore(),
        baseUrl: 'https://api.test',
        client: MockClient((r) async {
          sent.add('${r.url.path} ${r.body}');
          if (r.url.path == '/auth/verify-email/confirm') {
            return http.Response(
              jsonEncode({'detail': 'That code is wrong or has expired'}),
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 200);
        }),
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: VerifyEmailScreen(
          email: 'alice@example.com',
          auth: auth,
          onVerified: (_) async {},
        ),
      ),
    );
    Future<void> hold(String marker) async {
      await t.pumpAndSettle();
      // The host polls this file (run-as) and dumps the screen.
      await t.runAsync(() async {
        final dir = await getTemporaryDirectory();
        await File('${dir.path}/a11y_marker').writeAsString(marker);
      });
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 5)));
      await t.pump();
    }

    await hold('initial');
    await t.enterText(find.byType(TextField), '999999');
    await t.tap(find.text('Verify'));
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await hold('wrong_code');
    // The keyboard can cover it; TalkBack users reach it by swiping.
    await t.ensureVisible(find.text('Resend code'));
    await t.pumpAndSettle();
    await t.tap(find.text('Resend code'));
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await hold('resent');
    // ignore: avoid_print
    print('E2E_A11Y_SENT ${jsonEncode(sent)}');

    // The way back for an unverified account, as shown above the app.
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          appBar: AppBar(title: const Text('Naadh')),
          body: Column(
            children: [
              VerifyEmailBanner(
                email: 'alice@example.com',
                onVerifyNow: () {},
              ),
              const Expanded(child: Center(child: Text('Home'))),
            ],
          ),
        ),
      ),
    );
    await hold('banner');
  });
}
