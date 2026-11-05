// lib/widgets/settings_dialog.dart
//
// Unified settings dialog opened from the AppBar gear icon, the macOS app
// menu, the Tools menu and the in-app overflow menu.
// Sections:
//   • General      — F-key bar, toolbar customization
//   • Language     — system or explicit app locale
//   • Appearance   — theme, accent colour, file-list font
//   • Quick Search — Total Commander/Double Commander type-ahead behavior
//   • Cache        — usage and size limit
//   • Network      — proxy, TLS and provider request settings
//   • Accessibility, Privacy, File Colors and Advanced

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/accessibility_provider.dart';
import '../providers/analytics_provider.dart';
import '../providers/delta_sync_provider.dart';
import '../providers/file_type_color_provider.dart';
import '../providers/panel_source_provider.dart';
import '../providers/core_providers.dart';
import '../providers/quick_search_provider.dart';
import 'cache_settings_dialog.dart';
import 'provider_settings_dialog.dart';
import 'proxy_settings_dialog.dart';
import 'theme_picker.dart';
import '../l10n/commander_strings.dart';
import 'custom_command_dialog.dart';

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
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GeneralSection(),
            const Divider(height: 1),
            _LanguageSection(),
            const Divider(height: 1),
            _AppearanceSection(),
            const Divider(height: 1),
            _QuickSearchSection(),
            const Divider(height: 1),
            _CacheSection(),
            const Divider(height: 1),
            _NetworkSection(),
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
        ListTile(leading: const Icon(Icons.terminal),
          title: Text(CommanderStrings.translate(context, 'Custom commands')),
          onTap: () => showCustomCommandsDialog(context, ref,
            ref.read(activePanelProvider))),
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
// Section: Appearance — file-list font
// ---------------------------------------------------------------------------

class _AppearanceSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double fontSize = ref.watch(fontSizeProvider);
    final String family = ref.watch(fontFamilyProvider);
    final themeService = ref.watch(themeProvider);
    const Map<String, String> families = <String, String>{
      'system': 'System default',
      'AppMono': 'Monospaced (Roboto Mono)',
      'StoreRoboto': 'Roboto',
      'Arial': 'Arial',
      'Helvetica': 'Helvetica',
      'Verdana': 'Verdana',
      'Georgia': 'Georgia',
      'Times New Roman': 'Times New Roman',
    };

    return _Section(
      title: 'Appearance',
      icon: Icons.text_fields,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
          child: Text(
            'Theme and accent',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        ThemeSettingsPanel(themeService: themeService),
        const Divider(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: Text(
            'File-list font',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        ListTile(
          key: const Key('settings_font_family'),
          leading: const Icon(Icons.font_download_outlined),
          title: const Text('File list font'),
          subtitle: const Text('Used for names, sizes and dates in the panels'),
          trailing: SizedBox(
            width: 190,
            child: DropdownButton<String>(
              value: families.containsKey(family) ? family : 'system',
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: <DropdownMenuItem<String>>[
                for (final MapEntry<String, String> entry in families.entries)
                  DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  ref.read(fontFamilyProvider.notifier).setFamily(value);
                }
              },
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
        ),
        ListTile(
          key: const Key('settings_font_size'),
          leading: const Icon(Icons.format_size),
          title: const Text('File list font size'),
          subtitle: Text('${fontSize.toStringAsFixed(0)} pt'),
          trailing: SizedBox(
            width: 190,
            child: Slider(
              value: fontSize,
              min: 10,
              max: 20,
              divisions: 10,
              label: '${fontSize.toStringAsFixed(0)} pt',
              onChanged: (double value) =>
                  ref.read(fontSizeProvider.notifier).setSize(value),
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Text(
            'Example: Annual-Report-2026.pdf   ·   2.4 MB   ·   Today',
            style: TextStyle(
              fontFamily: family == 'system' ? null : family,
              fontSize: fontSize,
            ),
          ),
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
    final settings = ref.watch(quickSearchSettingsProvider);
    final notifier = ref.read(quickSearchSettingsProvider.notifier);
    final modeLabel = switch (settings.mode) {
      QuickSearchMode.select => 'Select every matching file',
      QuickSearchMode.jump => 'Jump to the next matching file',
      QuickSearchMode.filter => 'Filter the file list',
      QuickSearchMode.off => 'Disabled',
    };

    return _Section(
      title: 'Quick Search',
      icon: Icons.search,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Typing in the file list',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              SegmentedButton<QuickSearchMode>(
                key: const Key('settings_quick_search_mode'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: QuickSearchMode.select,
                    label: Text('Select'),
                  ),
                  ButtonSegment(
                    value: QuickSearchMode.jump,
                    label: Text('Jump'),
                  ),
                  ButtonSegment(
                    value: QuickSearchMode.filter,
                    label: Text('Filter'),
                  ),
                  ButtonSegment(
                    value: QuickSearchMode.off,
                    label: Text('Off'),
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
          title: const Text('Match from the beginning'),
          subtitle: const Text('Off: match anywhere in the file name'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
        ),
        SwitchListTile(
          key: const Key('settings_quick_search_case'),
          value: settings.caseSensitive,
          onChanged: notifier.setCaseSensitive,
          title: const Text('Case sensitive'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
        ),
        SwitchListTile(
          key: const Key('settings_quick_search_arrows'),
          value: settings.arrowNavigation,
          onChanged: notifier.setArrowNavigation,
          title: const Text('Arrow keys cycle through matches'),
          subtitle: const Text(
              'Up/Down move to the previous/next match while searching'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Reset search after'),
          subtitle: Text(
            settings.resetSeconds == 0
                ? 'Never'
                : '${settings.resetSeconds} second(s) of inactivity',
          ),
          trailing: DropdownButton<int>(
            key: const Key('settings_quick_search_reset'),
            value: settings.resetSeconds,
            onChanged: (value) {
              if (value != null) notifier.setResetSeconds(value);
            },
            items: const [
              DropdownMenuItem(value: 0, child: Text('Never')),
              DropdownMenuItem(value: 1, child: Text('1 s')),
              DropdownMenuItem(value: 2, child: Text('2 s')),
              DropdownMenuItem(value: 3, child: Text('3 s')),
              DropdownMenuItem(value: 5, child: Text('5 s')),
              DropdownMenuItem(value: 10, child: Text('10 s')),
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
// Section: Language
// ---------------------------------------------------------------------------

class _LanguageSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Locale? current = ref.watch(localeProvider);
    const labels = <String, String>{
      'system': 'System default',
      'en': 'English',
      'de': 'Deutsch',
      'fr': 'Français',
      'es': 'Español',
      'pt': 'Português',
      'zh': '中文',
      'ja': '日本語',
      'ko': '한국어',
      'ar': 'العربية',
    };
    final locales = <String>{
      'system',
      ...AppLocalizations.supportedLocales.map((l) => l.languageCode),
    }.toList()
      ..sort((a, b) {
        if (a == 'system') return -1;
        if (b == 'system') return 1;
        return a.compareTo(b);
      });
    final currentCode = current?.languageCode ?? 'system';

    return _Section(
      title: 'Language',
      icon: Icons.language,
      children: [
        ListTile(
          key: const Key('settings_language'),
          leading: const Icon(Icons.translate),
          title: const Text('App language'),
          subtitle: Text(
            current == null
                ? 'Follows the system language'
                : 'Applies immediately and is saved',
          ),
          trailing: SizedBox(
            width: 190,
            child: DropdownButton<String>(
              value: locales.contains(currentCode) ? currentCode : 'system',
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final code in locales)
                  DropdownMenuItem<String>(
                    value: code,
                    child: Text(
                      labels[code] ?? code.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                ref.read(localeProvider.notifier).setLocale(
                      value == 'system' ? null : Locale(value),
                    );
              },
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Text(
            'The selected language is stored locally and restored on the '
            'next launch.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: Cache
// ---------------------------------------------------------------------------

class _CacheSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const _Section(
      title: 'Cache',
      icon: Icons.storage,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: CacheSettingsPanel(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: Network
// ---------------------------------------------------------------------------

class _NetworkSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_NetworkSection> createState() => _NetworkSectionState();
}

class _NetworkSectionState extends ConsumerState<_NetworkSection> {
  Future<void> _openProxy() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const ProxySettingsDialog(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openProvider() async {
    showProviderSettingsDialog(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(proxyServiceProvider).config;
    final proxySummary = config.isEnabled
        ? '${config.type.name.toUpperCase()} ${config.host}:${config.port}'
        : 'Direct connection';

    return _Section(
      title: 'Network',
      icon: Icons.lan_outlined,
      children: [
        ListTile(
          key: const Key('settings_proxy'),
          leading: const Icon(Icons.vpn_lock_outlined),
          title: const Text('Proxy and certificates'),
          subtitle: Text(proxySummary),
          trailing: const Icon(Icons.chevron_right),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
          onTap: _openProxy,
        ),
        ListTile(
          key: const Key('settings_provider'),
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('Cloud provider request settings'),
          subtitle: const Text(
            'Timeout, headers, redirects and TLS verification',
          ),
          trailing: const Icon(Icons.chevron_right),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
          onTap: _openProvider,
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
                    .withValues(alpha: 0.5),
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
              initialValue: _kBlockSizeOptions
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
