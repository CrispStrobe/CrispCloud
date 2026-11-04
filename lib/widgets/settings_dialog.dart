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

import '../l10n/settings_strings.dart';
import '../providers/accessibility_provider.dart';
import '../providers/analytics_provider.dart';
import '../providers/delta_sync_provider.dart';
import '../providers/file_type_color_provider.dart';
import '../providers/panel_source_provider.dart';
import '../providers/quick_search_provider.dart';

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
    final s = SettingsStrings(context);
    return AlertDialog(
      title: Text(s.text('Settings')),
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
            _QuickSearchSection(),
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
          child: Text(s.text('Done')),
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
    final s = SettingsStrings(context);
    final fkeyVisible = ref.watch(fkeyBarVisibleProvider);

    return _Section(
      title: s.text('General'),
      icon: Icons.tune,
      children: [
        SwitchListTile(
          key: const Key('settings_fkey_bar_toggle'),
          value: fkeyVisible,
          onChanged: (_) => ref.read(fkeyBarVisibleProvider.notifier).toggle(),
          title: Text(s.text('F-key Bar')),
          subtitle: Text(
            s.text('Show F3–F8 shortcut buttons at the bottom of the screen'),
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
          title: Text(s.text('Customize Toolbar')),
          subtitle: Text(s.text('Add, remove, or reorder toolbar buttons')),
          trailing: const Icon(Icons.chevron_right),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          onTap: () {
            // Dismiss settings first, then open toolbar customization.
            Navigator.pop(context);
            // The toolbar customization dialog is opened by the caller
            // through a separate route / dialog in provider_settings_dialog.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(s.text('Open View → Toolbar to customize buttons')),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: Quick search (Total Commander / Double Commander behavior)
// ---------------------------------------------------------------------------

class _QuickSearchSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = SettingsStrings(context);
    final settings = ref.watch(quickSearchSettingsProvider);
    final notifier = ref.read(quickSearchSettingsProvider.notifier);
    final modeLabel = switch (settings.mode) {
      QuickSearchMode.jump => s.text('Jump to the next matching file'),
      QuickSearchMode.filter => s.text('Filter the file list'),
      QuickSearchMode.off => s.text('Disabled'),
    };

    return _Section(
      title: s.text('Quick Search'),
      icon: Icons.search,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.text('Typing in the file list'),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              SegmentedButton<QuickSearchMode>(
                key: const Key('settings_quick_search_mode'),
                segments: [
                  ButtonSegment(
                    value: QuickSearchMode.jump,
                    label: Text(s.text('Jump')),
                    icon: const Icon(Icons.keyboard_tab, size: 18),
                  ),
                  ButtonSegment(
                    value: QuickSearchMode.filter,
                    label: Text(s.text('Filter')),
                    icon: const Icon(Icons.filter_list, size: 18),
                  ),
                  ButtonSegment(
                    value: QuickSearchMode.off,
                    label: Text(s.text('Off')),
                    icon: const Icon(Icons.block, size: 18),
                  ),
                ],
                selected: {settings.mode},
                onSelectionChanged: (selection) =>
                    notifier.setMode(selection.first),
              ),
              const SizedBox(height: 6),
              Text(
                modeLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          key: const Key('settings_quick_search_prefix'),
          value: settings.matchFromStart,
          onChanged: notifier.setMatchFromStart,
          title: Text(s.text('Match from the beginning')),
          subtitle: Text(s.text('Off: match anywhere in the file name')),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
        ),
        SwitchListTile(
          key: const Key('settings_quick_search_case'),
          value: settings.caseSensitive,
          onChanged: notifier.setCaseSensitive,
          title: Text(s.text('Case sensitive')),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
        ),
        SwitchListTile(
          key: const Key('settings_quick_search_arrows'),
          value: settings.arrowNavigation,
          onChanged: notifier.setArrowNavigation,
          title: Text(s.text('Arrow keys cycle through matches')),
          subtitle: Text(s
              .text('Up/Down move to the previous/next match while searching')),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: Text(s.text('Reset search after')),
          subtitle: Text(
            settings.resetSeconds == 0
                ? s.text('Never')
                : s.inactivity(settings.resetSeconds),
          ),
          trailing: DropdownButton<int>(
            key: const Key('settings_quick_search_reset'),
            value: settings.resetSeconds,
            onChanged: (value) {
              if (value != null) notifier.setResetSeconds(value);
            },
            items: [
              DropdownMenuItem(value: 0, child: Text(s.text('Never'))),
              DropdownMenuItem(value: 1, child: Text(s.seconds(1))),
              DropdownMenuItem(value: 2, child: Text(s.seconds(2))),
              DropdownMenuItem(value: 3, child: Text(s.seconds(3))),
              DropdownMenuItem(value: 5, child: Text(s.seconds(5))),
              DropdownMenuItem(value: 10, child: Text(s.seconds(10))),
            ],
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
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
    final s = SettingsStrings(context);
    final highContrast = ref.watch(highContrastProvider);
    final reducedMotion = ref.watch(reducedMotionProvider);

    return _Section(
      title: s.text('Accessibility'),
      icon: Icons.accessibility_new,
      children: [
        SwitchListTile(
          key: const Key('settings_high_contrast_toggle'),
          value: highContrast,
          onChanged: (_) => ref.read(highContrastProvider.notifier).toggle(),
          title: Text(s.text('High Contrast')),
          subtitle: Text(
            s.text('Increase colour contrast for text and UI elements'),
          ),
          secondary: Icon(
            highContrast ? Icons.contrast : Icons.contrast_outlined,
          ),
          dense: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        ),
        SwitchListTile(
          key: const Key('settings_reduced_motion_toggle'),
          value: reducedMotion,
          onChanged: (_) => ref.read(reducedMotionProvider.notifier).toggle(),
          title: Text(s.text('Reduced Motion')),
          subtitle: Text(
            s.text('Minimise animations and transition effects'),
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
    final s = SettingsStrings(context);
    final analyticsEnabled = ref.watch(analyticsEnabledProvider);

    return _Section(
      title: s.text('Privacy'),
      icon: Icons.shield_outlined,
      children: [
        SwitchListTile(
          key: const Key('settings_analytics_toggle'),
          value: analyticsEnabled,
          onChanged: (value) =>
              ref.read(analyticsEnabledProvider.notifier).setEnabled(value),
          title: Text(s.text('Share Usage Analytics')),
          subtitle: Text(
            s.text(
                'Send anonymous feature-usage data to help improve CrispCloud. No file names, paths, or credentials are ever collected.'),
          ),
          secondary: Icon(
            analyticsEnabled
                ? Icons.insert_chart_outlined
                : Icons.insert_chart_outlined_rounded,
            color:
                analyticsEnabled ? Theme.of(context).colorScheme.primary : null,
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
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.text(
                          'Data is stored locally and summarised before any transmission. You can disable this at any time.'),
                      style: const TextStyle(fontSize: 12),
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
    final s = SettingsStrings(context);
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

    final localizedBlockSizeLabel = s.text(blockSizeLabel);

    return _Section(
      title: s.text('Advanced'),
      icon: Icons.settings_applications_outlined,
      children: [
        SwitchListTile(
          key: const Key('settings_delta_sync_toggle'),
          value: deltaSyncEnabled,
          onChanged: (value) =>
              ref.read(deltaSyncEnabledProvider.notifier).setEnabled(value),
          title: Text(s.text('Delta Sync')),
          subtitle: Text(
            s.text(
                'Transfer only changed blocks for files larger than 10 MB, reducing bandwidth usage.'),
          ),
          secondary: Icon(
            deltaSyncEnabled
                ? Icons.compare_arrows
                : Icons.compare_arrows_outlined,
            color:
                deltaSyncEnabled ? Theme.of(context).colorScheme.primary : null,
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
              isExpanded: true,
              initialValue: _kBlockSizeOptions
                      .cast<(int, String)?>()
                      .firstWhere(
                        (o) => o!.$1 == blockSize,
                        orElse: () => null,
                      )
                      ?.$1 ??
                  blockSize,
              decoration: InputDecoration(
                labelText: s.text('Block Size'),
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: s.text(
                    'Smaller blocks improve bandwidth savings; larger blocks reduce hashing overhead.'),
              ),
              items: _kBlockSizeOptions
                  .map(
                    (o) => DropdownMenuItem<int>(
                      value: o.$1,
                      child: Text(s.text(o.$2)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref.read(deltaBlockSizeProvider.notifier).setBlockSize(value);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              s.current(localizedBlockSizeLabel),
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
    final s = SettingsStrings(context);
    final colorService = ref.watch(fileTypeColorProvider);

    return _Section(
      title: s.text('File Colors'),
      icon: Icons.palette_outlined,
      children: [
        SwitchListTile(
          key: const Key('settings_file_colors_toggle'),
          value: colorService.enabled,
          onChanged: (value) => colorService.setEnabled(value),
          title: Text(s.text('Colorize Files by Type')),
          subtitle: Text(
            s.text(
                'Apply per-extension colors to file names and icons in the file list'),
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
              label: Text(s.text('Reset to Defaults')),
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
                  size: 18, color: Theme.of(context).colorScheme.primary),
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
