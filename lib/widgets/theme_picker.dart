// lib/widgets/theme_picker.dart
//
// Theme selection dialog with preview swatches and accent color picker.

import 'package:flutter/material.dart';
import '../services/theme_service.dart';

class ThemePickerDialog extends StatelessWidget {
  final ThemeService themeService;

  const ThemePickerDialog({super.key, required this.themeService});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose Theme'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Theme options
            ...AppThemeMode.values.map((mode) {
              final isSelected = themeService.currentMode == mode;
              final label = mode == AppThemeMode.system
                  ? 'System'
                  : builtInThemes[mode]?.name ?? mode.name;
              final swatch = _swatchColor(mode);

              return ListTile(
                dense: true,
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
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => themeService.setTheme(mode),
              );
            }),

            const Divider(height: 24),

            // Accent color picker
            Text('Accent Color',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _colorDot(context, null, 'Default'),
                _colorDot(context, Colors.blue, 'Blue'),
                _colorDot(context, Colors.indigo, 'Indigo'),
                _colorDot(context, Colors.purple, 'Purple'),
                _colorDot(context, Colors.pink, 'Pink'),
                _colorDot(context, Colors.red, 'Red'),
                _colorDot(context, Colors.orange, 'Orange'),
                _colorDot(context, Colors.amber, 'Amber'),
                _colorDot(context, Colors.green, 'Green'),
                _colorDot(context, Colors.teal, 'Teal'),
                _colorDot(context, Colors.cyan, 'Cyan'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
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
    final isSelected = themeService.customAccent == color ||
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
