// lib/services/theme_service.dart
//
// Theme management with multiple built-in themes and accent color customization.
// Persists the selected theme to SharedPreferences.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available built-in themes.
enum AppThemeMode {
  system,
  light,
  dark,
  oledBlack,
  nord,
  dracula,
}

class AppTheme {
  final String name;
  final AppThemeMode mode;
  final Color seedColor;
  final Brightness brightness;
  final Color? scaffoldBackground;
  final Color? surfaceColor;

  const AppTheme({
    required this.name,
    required this.mode,
    required this.seedColor,
    required this.brightness,
    this.scaffoldBackground,
    this.surfaceColor,
  });

  ThemeData toThemeData() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: scaffoldBackground != null
          ? colorScheme.copyWith(
              surface: surfaceColor ?? scaffoldBackground,
            )
          : colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      useMaterial3: true,
    );
  }
}

/// All built-in themes.
const Map<AppThemeMode, AppTheme> builtInThemes = {
  AppThemeMode.light: AppTheme(
    name: 'Light',
    mode: AppThemeMode.light,
    seedColor: Colors.blue,
    brightness: Brightness.light,
  ),
  AppThemeMode.dark: AppTheme(
    name: 'Dark',
    mode: AppThemeMode.dark,
    seedColor: Colors.blue,
    brightness: Brightness.dark,
  ),
  AppThemeMode.oledBlack: AppTheme(
    name: 'OLED Black',
    mode: AppThemeMode.oledBlack,
    seedColor: Colors.blue,
    brightness: Brightness.dark,
    scaffoldBackground: Colors.black,
    surfaceColor: const Color(0xFF0A0A0A),
  ),
  AppThemeMode.nord: AppTheme(
    name: 'Nord',
    mode: AppThemeMode.nord,
    seedColor: const Color(0xFF5E81AC), // Nord blue
    brightness: Brightness.dark,
    scaffoldBackground: const Color(0xFF2E3440), // Nord polar night
    surfaceColor: const Color(0xFF3B4252),
  ),
  AppThemeMode.dracula: AppTheme(
    name: 'Dracula',
    mode: AppThemeMode.dracula,
    seedColor: const Color(0xFFBD93F9), // Dracula purple
    brightness: Brightness.dark,
    scaffoldBackground: const Color(0xFF282A36), // Dracula background
    surfaceColor: const Color(0xFF44475A),
  ),
};

/// Manages theme state and persistence.
class ThemeService extends ChangeNotifier {
  static const _themeKey = 'app_theme';
  static const _accentKey = 'app_accent_color';

  AppThemeMode _currentMode = AppThemeMode.system;
  Color? _customAccent;

  AppThemeMode get currentMode => _currentMode;
  Color? get customAccent => _customAccent;

  ThemeService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeKey);
    if (saved != null) {
      _currentMode = AppThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => AppThemeMode.system,
      );
    }
    final accentValue = prefs.getInt(_accentKey);
    if (accentValue != null) {
      _customAccent = Color(accentValue);
    }
    notifyListeners();
  }

  Future<void> setTheme(AppThemeMode mode) async {
    _currentMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  Future<void> setAccentColor(Color? color) async {
    _customAccent = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color != null) {
      await prefs.setInt(_accentKey, color.value);
    } else {
      await prefs.remove(_accentKey);
    }
  }

  /// Get the ThemeData for the current selection.
  ThemeData get lightTheme => _buildTheme(Brightness.light);
  ThemeData get darkTheme => _buildTheme(Brightness.dark);

  ThemeMode get themeMode {
    switch (_currentMode) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      default:
        return ThemeMode.dark;
    }
  }

  ThemeData _buildTheme(Brightness brightness) {
    if (_currentMode == AppThemeMode.system ||
        _currentMode == AppThemeMode.light ||
        _currentMode == AppThemeMode.dark) {
      final seed = _customAccent ?? Colors.blue;
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: brightness,
        ),
        useMaterial3: true,
      );
    }

    // Named themes
    final theme = builtInThemes[_currentMode];
    if (theme == null) return ThemeData(useMaterial3: true);

    final seed = _customAccent ?? theme.seedColor;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: theme.brightness,
    );

    return ThemeData(
      colorScheme: theme.surfaceColor != null
          ? colorScheme.copyWith(surface: theme.surfaceColor)
          : colorScheme,
      scaffoldBackgroundColor: theme.scaffoldBackground,
      useMaterial3: true,
    );
  }
}
