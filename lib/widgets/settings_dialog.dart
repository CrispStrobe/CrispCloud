import 'notification_settings.dart';
import 'pdf_open_settings.dart';
import 'storage_tools_settings.dart';
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
import '../providers/file_type_color_provider.dart';
import '../providers/panel_source_provider.dart';
import '../providers/core_providers.dart';
import '../services/credential_storage_config.dart';
import '../services/app_lock_service.dart';
import '../services/secure_storage_macos_keychain.dart';
import 'credential_storage_setup.dart';
import 'keychain_lock_settings.dart';
import 'biometric_vault_settings_tile.dart';
import '../services/biometric_vault_unlock.dart';
import '../services/secure_storage_web.dart';
import '../providers/quick_search_provider.dart';
import '../providers/folder_sort_provider.dart';
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
import 'transfer_bandwidth_dialog.dart';
import 'office_font_downloads.dart';
import 'office_spacy_settings.dart';
import 'settings_backup_panel.dart';

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

enum _SettingsPage {
  general,
  appearance,
  documents,
  connections,
  storage,
  privacy,
  backups,
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  _SettingsPage _page = _SettingsPage.general;

  @override
  Widget build(BuildContext context) {
    final s = SettingsStrings(context);
    final labels = {
      _SettingsPage.general: s.text('General'),
      _SettingsPage.appearance: s.text('Appearance'),
      _SettingsPage.documents: s.text('Documents and language'),
      _SettingsPage.connections: s.text('Connections'),
      _SettingsPage.storage: s.text('Storage'),
      _SettingsPage.privacy: s.text('Privacy and accessibility'),
      _SettingsPage.backups: s.text('Settings backups'),
    };
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final content = SingleChildScrollView(
      key: ValueKey(_page),
      primary: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: switch (_page) {
          _SettingsPage.general => [
            _GeneralSection(),
            _QuickSearchSection(),
            const NotificationSettingsPanel(),
          ],
          _SettingsPage.appearance => [
            _AppearanceSection(),
            _FileColorsSection(),
          ],
          _SettingsPage.documents => [
            _LanguageSection(),
            const PdfOpenSettings(),
            const OfficeSpacySettings(),
            const OfficeFontDownloadsSettings(),
          ],
          _SettingsPage.connections => [
            _NetworkSection(),
            const CredentialStorageSettingsSection(),
          ],
          _SettingsPage.storage => [
            _CacheSection(),
            _AdvancedSection(),
            const StorageToolsSettings(),
          ],
          _SettingsPage.privacy => [_PrivacySection(), _AccessibilitySection()],
          _SettingsPage.backups => const [SettingsBackupPanel()],
        },
      ),
    );
    return AlertDialog(
      title: Text(s.text('Settings')),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 800,
        height: MediaQuery.sizeOf(context).height * .68,
        child: wide
            ? Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: ListView(
                      primary: false,
                      children: [
                        for (final entry in labels.entries)
                          ListTile(
                            dense: true,
                            key: ValueKey('settings-page-${entry.key.name}'),
                            selected: _page == entry.key,
                            title: Text(entry.value),
                            onTap: () => setState(() => _page = entry.key),
                          ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: DropdownButton<_SettingsPage>(
                      key: const ValueKey('settings-page-selector'),
                      value: _page,
                      isExpanded: true,
                      items: [
                        for (final entry in labels.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (page) {
                        if (page != null) setState(() => _page = page);
                      },
                    ),
                  ),
                  Expanded(child: content),
                ],
              ),
      ),
      actions: [
        ElevatedButton(
          autofocus: true,
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
        SwitchListTile(
          value: ref.watch(sortFoldersLikeFilesProvider),
          onChanged: ref.read(sortFoldersLikeFilesProvider.notifier).set,
          secondary: const Icon(Icons.sort),
          title: Text(s.text('Sort folders like files')),
          subtitle: Text(
            s.text('When off, folders stay in alphabetical order.'),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
            width: MediaQuery.sizeOf(context).width < 480 ? 112 : 190,
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
            width: MediaQuery.sizeOf(context).width < 480 ? 112 : 190,
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
          key: const Key('settings_space_advances'),
          value: settings.spaceAdvancesCursor,
          onChanged: notifier.setSpaceAdvancesCursor,
          title: Text(s.text('Space advances to the next item')),
          subtitle: Text(
            s.text('Off: Space only selects or deselects the current item'),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          dense: true,
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
            width: MediaQuery.sizeOf(context).width < 480 ? 112 : 190,
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
        const TransferBandwidthSettingsTile(),
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
          if (activePath != null)
            KeychainLockSettings(
              storage: ref.watch(
                secureStorageProvider,
              ) as MacOsCustomKeychainStorage,
            ),
          if (active == CredentialStorageMode.encryptedFile &&
              ref.watch(secureStorageProvider) is WebEncryptedStorage &&
              ref.watch(biometricVaultUnlockProvider).isSupported)
            BiometricVaultSettingsTile(
              storage: ref.watch(secureStorageProvider) as WebEncryptedStorage,
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
      if (result.mode != CredentialStorageMode.encryptedFile) {
        // The vault's Touch ID key must not outlive a switch to another store.
        await ref.read(biometricVaultUnlockProvider).removeIfEnabled();
      }
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

class _AdvancedSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = SettingsStrings(context);
    return _Section(
      title: s.text('Advanced'),
      icon: Icons.settings_applications_outlined,
      children: [
        SwitchListTile(
          key: const Key('settings_delta_sync_toggle'),
          value: false,
          onChanged: null,
          title: Text(s.text('Delta Sync')),
          subtitle: Text(
            s.text(
              'Automatic delta selection is unavailable. Supported S3 copies can use “Reuse verified S3 blocks” in the copy dialog.',
            ),
          ),
          secondary: const Icon(Icons.compare_arrows_outlined),
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
