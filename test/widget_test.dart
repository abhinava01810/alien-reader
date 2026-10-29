import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/app/app.dart';

import 'helpers/fake_cloud.dart';

Future<void> _launch(WidgetTester tester, FakeCloud cloud) async {
  await tester.pumpWidget(AlienReaderApp(cloudAuth: cloud.auth));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));

  // Let the splash fade out and its timers finish.
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('without stored tokens the app opens on login', (tester) async {
    final cloud = FakeCloud((_) => null);

    await _launch(tester, cloud);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(cloud.requests, isEmpty);
  });

  testWidgets('with stored tokens the app opens home without waiting', (
    tester,
  ) async {
    // The backend never answers in time; startup must not block on it.
    final cloud = FakeCloud((_) => null, signedIn: true);

    await _launch(tester, cloud);

    expect(find.text('Welcome back'), findsNothing);
    expect(find.text('Home'), findsWidgets);
  });
}
