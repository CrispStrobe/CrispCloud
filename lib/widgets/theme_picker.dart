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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...AppThemeMode.values.map((mode) {
          final isSelected = themeService.currentMode == mode;
          final label = ThemeUpdateStrings(context).text(switch (mode) {
            AppThemeMode.system => 'system',
            AppThemeMode.light => 'light',
            AppThemeMode.dark => 'dark',
            AppThemeMode.oledBlack => 'oled',
            AppThemeMode.nord => 'nord',
            AppThemeMode.dracula => 'dracula',
            AppThemeMode.materialYou => 'materialYou',
          });
          final swatch = _swatchColor(mode);

          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: swatch,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.withValues(alpha: 0.3),
                  width: isSelected ? 2 : 1,
                ),
              ),
            ),
            title: Text(label),
            trailing: isSelected
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            onTap: () => themeService.setTheme(mode),
          );
        }),

        const Divider(height: 24),

        // Accent color picker
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              ThemeUpdateStrings(context).text('accent'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _colorDot(
                context,
                null,
                ThemeUpdateStrings(context).text('default'),
              ),
              _colorDot(
                context,
                Colors.blue,
                ThemeUpdateStrings(context).text('blue'),
              ),
              _colorDot(
                context,
                Colors.indigo,
                ThemeUpdateStrings(context).text('indigo'),
              ),
              _colorDot(
                context,
                Colors.purple,
                ThemeUpdateStrings(context).text('purple'),
              ),
              _colorDot(
                context,
                Colors.pink,
                ThemeUpdateStrings(context).text('pink'),
              ),
              _colorDot(
                context,
                Colors.red,
                ThemeUpdateStrings(context).text('red'),
              ),
              _colorDot(
                context,
                Colors.orange,
                ThemeUpdateStrings(context).text('orange'),
              ),
              _colorDot(
                context,
                Colors.amber,
                ThemeUpdateStrings(context).text('amber'),
              ),
              _colorDot(
                context,
                Colors.green,
                ThemeUpdateStrings(context).text('green'),
              ),
              _colorDot(
                context,
                Colors.teal,
                ThemeUpdateStrings(context).text('teal'),
              ),
              _colorDot(
                context,
                Colors.cyan,
                ThemeUpdateStrings(context).text('cyan'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

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

  Widget _colorDot(BuildContext context, Color? color, String label) {
    final isSelected =
        themeService.customAccent == color ||
        (color == null && themeService.customAccent == null);

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => themeService.setAccentColor(color),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color ?? Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 3,
            ),
          ),
          child: color == null
              ? const Icon(Icons.auto_awesome, size: 14, color: Colors.white)
              : isSelected
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
