import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/theme_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeService', () {
    test('defaults to system theme', () {
      final service = ThemeService();
      expect(service.currentMode, AppThemeMode.system);
      expect(service.themeMode, ThemeMode.system);
    });

    test('setTheme changes mode', () async {
      final service = ThemeService();
      await service.setTheme(AppThemeMode.dark);
      expect(service.currentMode, AppThemeMode.dark);
      expect(service.themeMode, ThemeMode.dark);
    });

    test('light mode returns ThemeMode.light', () async {
      final service = ThemeService();
      await service.setTheme(AppThemeMode.light);
      expect(service.themeMode, ThemeMode.light);
    });

    test('nord/dracula/oled return ThemeMode.dark', () async {
      final service = ThemeService();

      for (final mode in [AppThemeMode.nord, AppThemeMode.dracula, AppThemeMode.oledBlack]) {
        await service.setTheme(mode);
        expect(service.themeMode, ThemeMode.dark, reason: '$mode should be dark');
      }
    });

    test('lightTheme and darkTheme produce valid ThemeData', () {
      final service = ThemeService();
      expect(service.lightTheme, isA<ThemeData>());
      expect(service.darkTheme, isA<ThemeData>());
      expect(service.lightTheme.useMaterial3, isTrue);
      expect(service.darkTheme.useMaterial3, isTrue);
    });

    test('setAccentColor changes accent', () async {
      final service = ThemeService();
      expect(service.customAccent, isNull);

      await service.setAccentColor(Colors.red);
      expect(service.customAccent, Colors.red);

      await service.setAccentColor(null);
      expect(service.customAccent, isNull);
    });

    test('oled black theme has black scaffold', () async {
      final service = ThemeService();
      await service.setTheme(AppThemeMode.oledBlack);
      final theme = service.darkTheme;
      expect(theme.scaffoldBackgroundColor, Colors.black);
    });

    test('builtInThemes contains all non-system modes', () {
      for (final mode in AppThemeMode.values) {
        if (mode == AppThemeMode.system) continue;
        expect(builtInThemes.containsKey(mode), isTrue,
            reason: 'Missing built-in theme for $mode');
      }
    });
  });
}
