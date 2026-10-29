import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alien_reader_app/core/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeController Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('default theme mode is system', () async {
      final controller = ThemeController.instance;
      expect(controller.themeMode, equals(ThemeMode.system));
    });

    test('setThemeMode updates themeMode and persists setting', () async {
      final controller = ThemeController.instance;

      bool notified = false;
      controller.addListener(() {
        notified = true;
      });

      await controller.setThemeMode(ThemeMode.dark);
      expect(controller.themeMode, equals(ThemeMode.dark));
      expect(notified, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('alien_reader_theme_mode'), equals('dark'));

      await controller.setThemeMode(ThemeMode.light);
      expect(controller.themeMode, equals(ThemeMode.light));
      expect(prefs.getString('alien_reader_theme_mode'), equals('light'));
    });

    test('init restores saved theme mode from preferences', () async {
      SharedPreferences.setMockInitialValues({
        'alien_reader_theme_mode': 'dark',
      });

      final controller = ThemeController.instance;
      await controller.init();

      expect(controller.themeMode, equals(ThemeMode.dark));
    });
  });
}
