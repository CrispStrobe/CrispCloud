// lib/widgets/theme_picker.dart
//
// Theme selection panel with preview swatches and accent color picker.
// The panel is embedded in the unified Settings dialog; ThemePickerDialog is
// kept for callers that still need a standalone picker.

import 'package:flutter/material.dart';

import '../l10n/theme_update_strings.dart';
import '../services/theme_service.dart';

class ThemePickerDialog extends StatelessWidget {
  final ThemeService themeService;

  const ThemePickerDialog({super.key, required this.themeService});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(ThemeUpdateStrings(context).text('choose')),
      scrollable: true,
      content: SizedBox(
        width: 340,
        child: ThemeSettingsPanel(themeService: themeService),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ThemeUpdateStrings(context).text('done')),
        ),
      ],
    );
  }
}

/// Theme and accent controls for embedding in Settings.
class ThemeSettingsPanel extends StatelessWidget {
  final ThemeService themeService;

  const ThemeSettingsPanel({super.key, required this.themeService});

  @override
  Widget build(BuildContext context) {
    final strings = ThemeUpdateStrings(context);
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            title: Text(strings.text('choose')),
            trailing: SizedBox(
              width: MediaQuery.sizeOf(context).width < 480 ? 112 : 190,
              child: DropdownButton<AppThemeMode>(
                key: const ValueKey('settings-theme'),
                value: themeService.currentMode,
                isExpanded: true,
                items: [
                  for (final mode in AppThemeMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: _label(
                        _swatchColor(mode),
                        strings.text(switch (mode) {
                          AppThemeMode.system => 'system',
                          AppThemeMode.light => 'light',
                          AppThemeMode.dark => 'dark',
                          AppThemeMode.oledBlack => 'oled',
                          AppThemeMode.nord => 'nord',
                          AppThemeMode.dracula => 'dracula',
                          AppThemeMode.materialYou => 'materialYou',
                        }),
                      ),
                    ),
                ],
                onChanged: (mode) {
                  if (mode != null) themeService.setTheme(mode);
                },
              ),
            ),
          ),
          ListTile(
            dense: true,
            title: Text(strings.text('accent')),
            trailing: SizedBox(
              width: MediaQuery.sizeOf(context).width < 480 ? 112 : 190,
              child: DropdownButton<int>(
                key: const ValueKey('settings-accent'),
                value: themeService.customAccent?.toARGB32() ?? -1,
                isExpanded: true,
                items: [
                  for (final (color, name) in _accents)
                    DropdownMenuItem(
                      value: color?.toARGB32() ?? -1,
                      child: _label(
                        color ?? Theme.of(context).colorScheme.primary,
                        strings.text(name),
                      ),
                    ),
                  if (themeService.customAccent case final color?
                      when !_accents.any(
                        (entry) => entry.$1?.toARGB32() == color.toARGB32(),
                      ))
                    DropdownMenuItem(
                      value: color.toARGB32(),
                      child: _label(
                        color,
                        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    themeService.setAccentColor(
                      value == -1 ? null : Color(value),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _accents = <(Color?, String)>[
    (null, 'default'),
    (Colors.blue, 'blue'),
    (Colors.indigo, 'indigo'),
    (Colors.purple, 'purple'),
    (Colors.pink, 'pink'),
    (Colors.red, 'red'),
    (Colors.orange, 'orange'),
    (Colors.green, 'green'),
    (Colors.teal, 'teal'),
    (Colors.cyan, 'cyan'),
  ];

  Widget _label(Color color, String text) => Row(
    children: [
      Container(width: 16, height: 16, color: color),
      const SizedBox(width: 8),
      Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
    ],
  );

  Color _swatchColor(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return Colors.grey;
      case AppThemeMode.light:
        return Colors.white;
      case AppThemeMode.dark:
        return const Color(0xFF303030);
      case AppThemeMode.oledBlack:
        return Colors.black;
      case AppThemeMode.nord:
        return const Color(0xFF2E3440);
      case AppThemeMode.dracula:
        return const Color(0xFF282A36);
      case AppThemeMode.materialYou:
        return Colors.blueGrey;
    }
  }
}
