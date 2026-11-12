// lib/widgets/settings_dialog.dart
//
// Unified settings dialog opened from the AppBar gear icon, the macOS app
// menu, the Tools menu and the in-app overflow menu.
// Sections:
//   • General      — F-key bar, toolbar customization
//   • Language     — system or explicit app locale
//   • Appearance   — theme, accent colour, file-list font
//   • Quick Search — configurable type-ahead behavior
//   • Cache        — usage and size limit
//   • Network      — proxy, TLS and provider request settings
//   • Accessibility, Privacy, File Colors and Advanced

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/settings_strings.dart';

import '../providers/accessibility_provider.dart';
import '../providers/analytics_provider.dart';
import '../providers/delta_sync_provider.dart';
import '../providers/file_type_color_provider.dart';
import '../providers/panel_source_provider.dart';
import '../providers/core_providers.dart';
import '../services/credential_storage_config.dart';
import '../services/app_lock_service.dart';
import '../services/secure_storage_macos_keychain.dart';
import 'credential_storage_setup.dart';
import '../providers/quick_search_provider.dart';
import 'cache_settings_dialog.dart';
import 'provider_settings_dialog.dart';
import 'proxy_settings_dialog.dart';
import 'theme_picker.dart';
import '../l10n/commander_strings.dart';
import 'custom_command_dialog.dart';
import '../l10n/extension_translations.dart';
import 'extensions_dialog.dart';
import 'keyboard_shortcut_dialog.dart';
import '../l10n/workspace_ux_strings.dart';
import '../l10n/external_terminal_strings.dart';
import 'external_terminal_dialog.dart';

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
            const CredentialStorageSettingsSection(),
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
        ListTile(
          key: const ValueKey('settings-keyboard-shortcuts'),
          leading: const Icon(Icons.keyboard_outlined),
          title: Text(WorkspaceUxStrings(context).text('customize')),
          onTap: () => showKeyboardShortcutSettings(context),
        ),
        ListTile(
          leading: const Icon(Icons.terminal),
          title: Text(CommanderStrings.translate(context, 'Custom commands')),
          onTap: () => showCustomCommandsDialog(
            context,
            ref,
            ref.read(activePanelProvider),
          ),
        ),
        ListTile(
          key: const ValueKey('settings-external-terminal'),
          leading: const Icon(Icons.open_in_new),
          title: Text(ExternalTerminalStrings(context).text('title')),
          onTap: () => showExternalTerminalDialog(context, ref),
        ),
        ListTile(
          key: const ValueKey('settings-extensions'),
          leading: const Icon(Icons.extension),
          title: Text(context.extensionTr('Extensions')),
          onTap: () =>
              showExtensionsDialog(context, ref, ref.read(activePanelProvider)),
        ),
        SwitchListTile(
          key: const Key('settings_fkey_bar_toggle'),
          value: fkeyVisible,
          onChanged: (_) => ref.read(fkeyBarVisibleProvider.notifier).toggle(),
          title: Text(s.text('F-key Bar')),
          subtitle: Text(
            s.text('Show F3–F9 shortcut buttons at the bottom of the screen'),
          ),
          secondary: Icon(fkeyVisible ? Icons.keyboard : Icons.keyboard_hide),
          dense: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
        ),
        ListTile(
          key: const Key('settings_toolbar_customize'),
          leading: const Icon(Icons.view_column_outlined),
          title: Text(s.text('Customize Toolbar')),
          subtitle: Text(s.text('Add, remove, or reorder toolbar buttons')),
          trailing: const Icon(Icons.chevron_right),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          onTap: () {
            // Dismiss settings first, then open toolbar customization.
            Navigator.pop(context);
            // The toolbar customization dialog is opened by the caller
            // through a separate route / dialog in provider_settings_dialog.
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  s.text('Open View → Toolbar to customize buttons'),
                ),
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
// Section: Appearance — file-list font
// ---------------------------------------------------------------------------

class _AppearanceSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = SettingsStrings(context);
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
      title: s.text('Appearance'),
      icon: Icons.text_fields,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
          child: Text(
            s.text('Theme and accent'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        ThemeSettingsPanel(themeService: themeService),
        const Divider(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: Text(
            s.text('File-list font'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        ListTile(
          key: const Key('settings_font_family'),
          leading: const Icon(Icons.font_download_outlined),
          title: Text(s.text('File list font')),
          subtitle: Text(
            s.text('Used for names, sizes and dates in the panels'),
          ),
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
                    child: Text(
                      s.text(entry.value),
                      overflow: TextOverflow.ellipsis,
                    ),
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
          title: Text(s.text('File list font size')),
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
            s.text('Example: Annual-Report-2026.pdf   ·   2.4 MB   ·   Today'),
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
// Section: Quick search and type-ahead behavior
// ---------------------------------------------------------------------------

class _QuickSearchSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = SettingsStrings(context);
    final settings = ref.watch(quickSearchSettingsProvider);
    final notifier = ref.read(quickSearchSettingsProvider.notifier);
    final modeLabel = switch (settings.mode) {
      QuickSearchMode.select => s.text('Select every matching file'),
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
              Text(
                s.text('Typing in the file list'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<QuickSearchMode>(
                key: const Key('settings_quick_search_mode'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: QuickSearchMode.select,
                    label: Text(s.text('Select')),
                  ),
                  ButtonSegment(
                    value: QuickSearchMode.jump,
                    label: Text(s.text('Jump')),
                  ),
                  ButtonSegment(
                    value: QuickSearchMode.filter,
                    label: Text(s.text('Filter')),
                  ),
                  ButtonSegment(
                    value: QuickSearchMode.off,
                    label: Text(s.text('Off')),
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
          subtitle: Text(
            s.text('Up/Down move to the previous/next match while searching'),
          ),
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
// Section: Language
// ---------------------------------------------------------------------------

class _LanguageSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = SettingsStrings(context);
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
    final locales =
        <String>{
          'system',
          ...AppLocalizations.supportedLocales.map((l) => l.languageCode),
        }.toList()..sort((a, b) {
          if (a == 'system') return -1;
          if (b == 'system') return 1;
          return a.compareTo(b);
        });
    final currentCode = current?.languageCode ?? 'system';

    return _Section(
      title: s.text('Language'),
      icon: Icons.language,
      children: [
        ListTile(
          key: const Key('settings_language'),
          leading: const Icon(Icons.translate),
          title: Text(s.text('App language')),
          subtitle: Text(
            current == null
                ? s.text('Follows the system language')
                : s.text('Applies immediately and is saved'),
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
                      code == 'system'
                          ? s.text('System default')
                          : labels[code] ?? code.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                ref
                    .read(localeProvider.notifier)
                    .setLocale(value == 'system' ? null : Locale(value));
              },
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Text(
            s.text(
              'The selected language is stored locally and restored on the next launch.',
            ),
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
    final s = SettingsStrings(context);
    final config = ref.watch(proxyServiceProvider).config;
    final proxySummary = config.isEnabled
        ? '${config.type.name.toUpperCase()} ${config.host}:${config.port}'
        : s.text('Direct connection');

    return _Section(
      title: s.text('Network'),
      icon: Icons.lan_outlined,
      children: [
        ListTile(
          key: const Key('settings_proxy'),
          leading: const Icon(Icons.vpn_lock_outlined),
          title: Text(s.text('Proxy and certificates')),
          subtitle: Text(proxySummary),
          trailing: const Icon(Icons.chevron_right),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
          onTap: _openProxy,
        ),
        ListTile(
          key: const Key('settings_provider'),
          leading: const Icon(Icons.cloud_outlined),
          title: Text(s.text('Cloud provider request settings')),
          subtitle: Text(
            s.text('Timeout, headers, redirects and TLS verification'),
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
// Section: Credential storage
// ---------------------------------------------------------------------------

/// Shows the backend in use separately from a saved choice for the next launch.
class CredentialStorageSettingsSection extends ConsumerStatefulWidget {
  const CredentialStorageSettingsSection({super.key});

  @override
  ConsumerState<CredentialStorageSettingsSection> createState() =>
      _CredentialStorageSettingsSectionState();
}

class _CredentialStorageSettingsSectionState
    extends ConsumerState<CredentialStorageSettingsSection> {
  late Future<CredentialStorageSelection> _selection =
      CredentialStorageConfig.readSelection();
  bool _busy = false;

  String _label(SettingsStrings s, CredentialStorageMode mode) =>
      switch (mode) {
        CredentialStorageMode.systemKeychain => s.text('System keychain'),
        CredentialStorageMode.encryptedFile => s.text(
          'Encrypted file (master password)',
        ),
        CredentialStorageMode.sessionOnly => s.text('This session only'),
      };

  String? get _activeKeychainPath {
    final storage = ref.read(secureStorageProvider);
    return storage is MacOsCustomKeychainStorage ? storage.path : null;
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(SettingsStrings(context).text(message))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final s = SettingsStrings(context);
    final active = ref.watch(credentialStorageModeProvider);
    final pending = ref.watch(credentialStoragePendingModeProvider);
    final changedKeychain = ref.watch(
      credentialStorageKeychainRestartRequiredProvider,
    );
    final activePath = active == CredentialStorageMode.systemKeychain
        ? _activeKeychainPath
        : null;
    return FutureBuilder<CredentialStorageSelection>(
      future: _selection,
      builder: (context, snapshot) => _Section(
        title: s.text('Credentials'),
        icon: Icons.key_outlined,
        children: [
          ListTile(
            key: const ValueKey('settings-credential-storage'),
            leading: const Icon(Icons.lock_outline),
            title: Text(s.text('Credential storage')),
            subtitle: Text(
              [
                s
                    .text('Current session: {mode}')
                    .replaceAll('{mode}', _label(s, active)),
                if (activePath != null) activePath,
                if (active == CredentialStorageMode.sessionOnly)
                  s.text('Credentials are forgotten when CrispCloud exits.'),
                if (pending != null || changedKeychain) ...[
                  s
                      .text('After restart: {mode}')
                      .replaceAll('{mode}', _label(s, pending ?? active)),
                  if ((pending ?? active) ==
                          CredentialStorageMode.systemKeychain &&
                      snapshot.data?.customKeychainPath != null)
                    snapshot.data!.customKeychainPath!,
                  s.text(
                    'The current session keeps using its original storage until restart.',
                  ),
                ],
                if (snapshot.hasError)
                  s.text(
                    'Could not read credential-storage settings. Try again.',
                  ),
              ].join('\n'),
            ),
            trailing: _busy
                ? const Icon(Icons.hourglass_empty)
                : const Icon(Icons.chevron_right),
            onTap: _busy ? null : _change,
          ),
        ],
      ),
    );
  }

  Future<void> _change() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final lock = AppLockService(ref.read(secureStorageProvider));
      if (await lock.isEnabled()) {
        _notice(
          'Disable App Lock before changing credential storage, then enable it again after restarting.',
        );
        return;
      }
      final previous = await CredentialStorageConfig.readSelection();
      if (!mounted) return;
      final active = ref.read(credentialStorageModeProvider);
      // Keep the operation guarded through both the dialog and the awaited
      // post-dialog verification/save. The static busy icon needs no animation.
      final result = await showCredentialStorageSetupDialog(
        context,
        initialMode: previous.mode ?? active,
        initialKeychainPath: previous.customKeychainPath,
      );
      if (result == null || !mounted) return;
      // Recheck after the dialog: another action may have enabled the lock.
      // A read failure is an error, never permission to use another store.
      if (await lock.isEnabled()) {
        _notice(
          'Disable App Lock before changing credential storage, then enable it again after restarting.',
        );
        return;
      }
      final path = result.mode == CredentialStorageMode.systemKeychain
          ? result.keychainPath
          : previous.customKeychainPath;
      await CredentialStorageConfig.writeSelection(
        mode: result.mode,
        customKeychainPath: path,
        // A missing already-selected vault is not permission to replace it.
        // Only this authenticated switch from another mode grants creation;
        // revisiting an unconsumed choice preserves its existing intent.
        createFileVault:
            result.mode == CredentialStorageMode.encryptedFile &&
            active != CredentialStorageMode.encryptedFile &&
            (previous.mode != CredentialStorageMode.encryptedFile ||
                previous.createFileVault),
      );
      if (!mounted) return;
      ref.read(credentialStoragePendingModeProvider.notifier).state =
          result.mode == active ? null : result.mode;
      ref
              .read(credentialStorageKeychainRestartRequiredProvider.notifier)
              .state =
          result.mode == CredentialStorageMode.systemKeychain &&
          path != _activeKeychainPath;
      setState(() => _selection = CredentialStorageConfig.readSelection());
      _notice(
        'Restart CrispCloud to apply. Existing credentials stay in their original store; sign in again if needed.',
      );
    } catch (_) {
      _notice(
        'Could not verify App Lock or save credential-storage settings. Your active storage is unchanged. Try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
        ),
        SwitchListTile(
          key: const Key('settings_reduced_motion_toggle'),
          value: reducedMotion,
          onChanged: (_) => ref.read(reducedMotionProvider.notifier).toggle(),
          title: Text(s.text('Reduced Motion')),
          subtitle: Text(s.text('Minimise animations and transition effects')),
          secondary: Icon(
            reducedMotion
                ? Icons.motion_photos_off
                : Icons.motion_photos_on_outlined,
          ),
          dense: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
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
              'Send anonymous feature-usage data to help improve CrispCloud. No file names, paths, or credentials are ever collected.',
            ),
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
        ),
        if (analyticsEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
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
                        'Data is stored locally and summarised before any transmission. You can disable this at any time.',
                      ),
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
    final blockSizeLabel =
        _kBlockSizeOptions
            .cast<(int, String)?>()
            .firstWhere((o) => o!.$1 == blockSize, orElse: () => null)
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
              'Transfer only changed blocks for files larger than 10 MB, reducing bandwidth usage.',
            ),
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
        ),
        if (deltaSyncEnabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: DropdownButtonFormField<int>(
              key: const Key('settings_delta_block_size'),
              isExpanded: true,
              initialValue:
                  _kBlockSizeOptions
                      .cast<(int, String)?>()
                      .firstWhere((o) => o!.$1 == blockSize, orElse: () => null)
                      ?.$1 ??
                  blockSize,
              decoration: InputDecoration(
                labelText: s.text('Block Size'),
                border: const OutlineInputBorder(),
                isDense: true,
                helperText: s.text(
                  'Smaller blocks improve bandwidth savings; larger blocks reduce hashing overhead.',
                ),
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
              'Apply per-extension colors to file names and icons in the file list',
            ),
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
        ),
        if (colorService.enabled) ...[
          ...colorService.rules.map(
            (rule) => ListTile(
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
            ),
          ),
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
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
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
