// lib/widgets/settings_dialog.dart
//
// Unified settings dialog opened from the AppBar gear icon or main menu.
// Sections:
//   • General      — F-key bar toggle, toolbar customization link
//   • Accessibility — High contrast toggle, Reduced motion toggle
//   • Privacy      — Analytics opt-in toggle with explanation
//   • Advanced     — Delta sync toggle, delta sync block size selector

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/accessibility_provider.dart';
import '../providers/analytics_provider.dart';
import '../providers/delta_sync_provider.dart';
import '../providers/file_type_color_provider.dart';
import '../providers/panel_source_provider.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Show the settings dialog from any [BuildContext].
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => const SettingsDialog(),
  );
}

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text('Settings'),
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GeneralSection(),
            const Divider(height: 1),
            _AccessibilitySection(),
            const Divider(height: 1),
            _PrivacySection(),
            const Divider(height: 1),
            _FileColorsSection(),
            const Divider(height: 1),
            _AdvancedSection(),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: General
// ---------------------------------------------------------------------------

class _GeneralSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fkeyVisible = ref.watch(fkeyBarVisibleProvider);

    return _Section(
      title: 'General',
      icon: Icons.tune,
      children: [
        SwitchListTile(
          key: const Key('settings_fkey_bar_toggle'),
          value: fkeyVisible,
          onChanged: (_) =>
              ref.read(fkeyBarVisibleProvider.notifier).toggle(),
          title: const Text('F-key Bar'),
          subtitle: const Text(
            'Show F3–F8 shortcut buttons at the bottom of the screen',
          ),
          secondary: Icon(
            fkeyVisible ? Icons.keyboard : Icons.keyboard_hide,
          ),
          dense: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        ),
        ListTile(
          key: const Key('settings_toolbar_customize'),
          leading: const Icon(Icons.view_column_outlined),
          title: const Text('Customize Toolbar'),
          subtitle: const Text('Add, remove, or reorder toolbar buttons'),
          trailing: const Icon(Icons.chevron_right),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          onTap: () {
            // Dismiss settings first, then open toolbar customization.
            Navigator.pop(context);
            // The toolbar customization dialog is opened by the caller
            // through a separate route / dialog in provider_settings_dialog.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Open View → Toolbar to customize buttons'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: Accessibility
// ---------------------------------------------------------------------------

class _AccessibilitySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highContrast = ref.watch(highContrastProvider);
    final reducedMotion = ref.watch(reducedMotionProvider);

    return _Section(
      title: 'Accessibility',
      icon: Icons.accessibility_new,
      children: [
        SwitchListTile(
          key: const Key('settings_high_contrast_toggle'),
          value: highContrast,
          onChanged: (_) =>
              ref.read(highContrastProvider.notifier).toggle(),
          title: const Text('High Contrast'),
          subtitle: const Text(
            'Increase colour contrast for text and UI elements',
          ),
          secondary: Icon(
            highContrast
                ? Icons.contrast
                : Icons.contrast_outlined,
          ),
          dense: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        ),
        SwitchListTile(
          key: const Key('settings_reduced_motion_toggle'),
          value: reducedMotion,
          onChanged: (_) =>
              ref.read(reducedMotionProvider.notifier).toggle(),
          title: const Text('Reduced Motion'),
          subtitle: const Text(
            'Minimise animations and transition effects',
          ),
          secondary: Icon(
            reducedMotion
                ? Icons.motion_photos_off
                : Icons.motion_photos_on_outlined,
          ),
          dense: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: Privacy
// ---------------------------------------------------------------------------

class _PrivacySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsEnabled = ref.watch(analyticsEnabledProvider);

    return _Section(
      title: 'Privacy',
      icon: Icons.shield_outlined,
      children: [
        SwitchListTile(
          key: const Key('settings_analytics_toggle'),
          value: analyticsEnabled,
          onChanged: (value) =>
              ref.read(analyticsEnabledProvider.notifier).setEnabled(value),
          title: const Text('Share Usage Analytics'),
          subtitle: const Text(
            'Send anonymous feature-usage data to help improve CrispCloud. '
            'No file names, paths, or credentials are ever collected.',
          ),
          secondary: Icon(
            analyticsEnabled
                ? Icons.insert_chart_outlined
                : Icons.insert_chart_outlined_rounded,
            color: analyticsEnabled
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          dense: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        ),
        if (analyticsEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Data is stored locally and summarised before any '
                      'transmission. You can disable this at any time.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: Advanced
// ---------------------------------------------------------------------------

/// Block-size options shown in the selector (bytes → display label).
const _kBlockSizeOptions = [
  (64 * 1024, '64 KB'),
  (256 * 1024, '256 KB'),
  (512 * 1024, '512 KB'),
  (1 * 1024 * 1024, '1 MB'),
  (2 * 1024 * 1024, '2 MB'),
  (4 * 1024 * 1024, '4 MB (default)'),
  (8 * 1024 * 1024, '8 MB'),
  (16 * 1024 * 1024, '16 MB'),
  (32 * 1024 * 1024, '32 MB'),
  (64 * 1024 * 1024, '64 MB'),
];

class _AdvancedSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deltaSyncEnabled = ref.watch(deltaSyncEnabledProvider);
    final blockSize = ref.watch(deltaBlockSizeProvider);

    // Find the nearest option or use a fallback label.
    final blockSizeLabel = _kBlockSizeOptions
        .cast<(int, String)?>()
        .firstWhere(
          (o) => o!.$1 == blockSize,
          orElse: () => null,
        )
        ?.$2 ??
        '${(blockSize / (1024 * 1024)).toStringAsFixed(1)} MB';

    return _Section(
      title: 'Advanced',
      icon: Icons.settings_applications_outlined,
      children: [
        SwitchListTile(
          key: const Key('settings_delta_sync_toggle'),
          value: deltaSyncEnabled,
          onChanged: (value) =>
              ref.read(deltaSyncEnabledProvider.notifier).setEnabled(value),
          title: const Text('Delta Sync'),
          subtitle: const Text(
            'Transfer only changed blocks for files larger than 10 MB, '
            'reducing bandwidth usage.',
          ),
          secondary: Icon(
            deltaSyncEnabled
                ? Icons.compare_arrows
                : Icons.compare_arrows_outlined,
            color: deltaSyncEnabled
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          dense: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        ),
        if (deltaSyncEnabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: DropdownButtonFormField<int>(
              key: const Key('settings_delta_block_size'),
              value: _kBlockSizeOptions
                      .cast<(int, String)?>()
                      .firstWhere(
                        (o) => o!.$1 == blockSize,
                        orElse: () => null,
                      )
                      ?.$1 ??
                  blockSize,
              decoration: const InputDecoration(
                labelText: 'Block Size',
                border: OutlineInputBorder(),
                isDense: true,
                helperText:
                    'Smaller blocks improve bandwidth savings; larger blocks '
                    'reduce hashing overhead.',
              ),
              items: _kBlockSizeOptions
                  .map(
                    (o) => DropdownMenuItem<int>(
                      value: o.$1,
                      child: Text(o.$2),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref
                      .read(deltaBlockSizeProvider.notifier)
                      .setBlockSize(value);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Current: $blockSizeLabel',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: File Colors
// ---------------------------------------------------------------------------

class _FileColorsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorService = ref.watch(fileTypeColorProvider);

    return _Section(
      title: 'File Colors',
      icon: Icons.palette_outlined,
      children: [
        SwitchListTile(
          key: const Key('settings_file_colors_toggle'),
          value: colorService.enabled,
          onChanged: (value) => colorService.setEnabled(value),
          title: const Text('Colorize Files by Type'),
          subtitle: const Text(
            'Apply per-extension colors to file names and icons in the file list',
          ),
          secondary: Icon(
            colorService.enabled
                ? Icons.format_color_fill
                : Icons.format_color_reset,
            color: colorService.enabled
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          dense: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        ),
        if (colorService.enabled) ...[
          ...colorService.rules.map((rule) => ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: rule.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            title: Text(
              rule.extensions,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          )),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: TextButton.icon(
              icon: const Icon(Icons.restore, size: 16),
              label: const Text('Reset to Defaults'),
              onPressed: () => colorService.resetToDefaults(),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section layout helper
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        ...children,
        const SizedBox(height: 8),
      ],
    );
  }
}
