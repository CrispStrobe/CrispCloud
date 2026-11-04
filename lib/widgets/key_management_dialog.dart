// lib/widgets/key_management_dialog.dart
//
// Key management dialog: export/import encryption keys, BIP39 mnemonic
// backup and recovery. Accessible from the connection dialog or app bar
// when encryption is active.


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/encryption_service.dart';
import '../utils/secure_clipboard.dart';
import '../l10n/app_localizations.dart';
import '../l10n/key_management_strings.dart';

void showKeyManagementDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (_) => const _KeyManagementDialog(),
  );
}

class _KeyManagementDialog extends ConsumerStatefulWidget {
  const _KeyManagementDialog();

  @override
  ConsumerState<_KeyManagementDialog> createState() =>
      _KeyManagementDialogState();
}

class _KeyManagementDialogState extends ConsumerState<_KeyManagementDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Export tab
  String? _mnemonic;
  String? _keyHex;
  String? _backupBundle;

  // Import tab
  final _importMnemonicController = TextEditingController();
  final _importHexController = TextEditingController();
  final _importBundleController = TextEditingController();
  String? _importError;
  String? _importSuccess;

  String _t(String key, [Map<String, Object> values = const {}]) =>
      KeyManagementStrings(context).text(key, values);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _generateExportData();
  }

  void _generateExportData() {
    final auth = ref.read(authProvider);
    final key = auth.encryptionKey;
    final salt = auth.encryptionSalt;
    if (key == null || salt == null) return;

    final mnemonicData = EncryptionService.generateMnemonic(key, salt);
    _mnemonic = mnemonicData['mnemonic'];
    _keyHex = EncryptionService.exportKeyAsHex(key);
    _backupBundle = EncryptionService.exportBackupBundle(key, salt);
  }

  void _importFromMnemonic() {
    setState(() {
      _importError = null;
      _importSuccess = null;
    });
    try {
      final key = EncryptionService.recoverKeyFromMnemonic(
          _importMnemonicController.text);
      // When recovering from mnemonic alone, we need a new salt
      // (the original salt is not encoded in the mnemonic).
      // The user should use the backup bundle for full recovery.
      final salt = EncryptionService.generateSalt();
      ref.read(authProvider).enableEncryptionWithKey(key, salt);
      setState(() => _importSuccess = _t('mnemonicSuccess'));
    } on FormatException catch (e) {
      setState(() => _importError = e.message);
    } catch (e) {
      setState(() => _importError = e.toString());
    }
  }

  void _importFromHex() {
    setState(() {
      _importError = null;
      _importSuccess = null;
    });
    try {
      final key =
          EncryptionService.importKeyFromHex(_importHexController.text);
      final salt = EncryptionService.generateSalt();
      ref.read(authProvider).enableEncryptionWithKey(key, salt);
      setState(() => _importSuccess = _t('hexSuccess'));
    } on FormatException catch (e) {
      setState(() => _importError = e.message);
    } catch (e) {
      setState(() => _importError = e.toString());
    }
  }

  void _importFromBundle() {
    setState(() {
      _importError = null;
      _importSuccess = null;
    });
    try {
      final result =
          EncryptionService.importBackupBundle(_importBundleController.text);
      ref.read(authProvider).enableEncryptionWithKey(
            result['key']!,
            result['salt']!,
          );
      setState(() =>
          _importSuccess = _t('bundleSuccess'));
    } on FormatException catch (e) {
      setState(() => _importError = e.message);
    } catch (e) {
      setState(() => _importError = e.toString());
    }
  }

  void _copyToClipboard(String data, String label) {
    SecureClipboard.copy(data);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('copied', {'label': label}))),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _importMnemonicController.dispose();
    _importHexController.dispose();
    _importBundleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final hasKey = auth.encryptionKey != null;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.key, size: 20),
          const SizedBox(width: 8),
          Text(_t('keyManagement')),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          children: [
            if (!hasKey)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning,
                        size: 16,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _t('inactive'),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: _t('exportTab')),
                Tab(text: _t('importTab')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildExportTab(theme, hasKey),
                  _buildImportTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.close)),
      ],
    );
  }

  Widget _buildExportTab(ThemeData theme, bool hasKey) {
    if (!hasKey) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_open, size: 48, color: theme.disabledColor),
            const SizedBox(height: 8),
            Text(_t('noKey'),
                style: TextStyle(color: theme.disabledColor)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // BIP39 Mnemonic
          _exportSection(
            theme,
            icon: Icons.article,
            title: _t('phrase'),
            subtitle:
                'Write down these 24 words in order. They can recover your key.',
            content: _mnemonic ?? '',
            copyLabel: _t('mnemonic'),
            sensitive: true,
          ),
          const SizedBox(height: 16),
          // Raw key hex
          _exportSection(
            theme,
            icon: Icons.vpn_key,
            title: _t('raw'),
            subtitle: _t('rawHelp'),
            content: _keyHex ?? '',
            copyLabel: _t('key'),
            sensitive: true,
          ),
          const SizedBox(height: 16),
          // Backup bundle
          _exportSection(
            theme,
            icon: Icons.backup,
            title: _t('bundle'),
            subtitle:
                'JSON with mnemonic, salt, and verification. Best for full recovery.',
            content: _backupBundle ?? '',
            copyLabel: _t('bundleLabel'),
            sensitive: true,
          ),
        ],
      ),
    );
  }

  Widget _exportSection(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String content,
    required String copyLabel,
    bool sensitive = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 2),
        Text(subtitle,
            style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.dividerColor),
          ),
          child: SelectableText(
            content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.copy, size: 14),
            label: Text(_t('copy', {'label': copyLabel}), style: const TextStyle(fontSize: 12)),
            onPressed: () => _copyToClipboard(content, copyLabel),
          ),
        ),
      ],
    );
  }

  Widget _buildImportTab(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_importError != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_importError!,
                          style: TextStyle(
                              fontSize: 12, color: theme.colorScheme.error))),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_importSuccess != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_importSuccess!,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.green))),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Import from backup bundle (recommended)
          Text(_t('restoreTitle'),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: theme.colorScheme.primary)),
          const SizedBox(height: 4),
          TextField(
            controller: _importBundleController,
            onChanged: (_) => setState(() {}),
            maxLines: 3,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: _t('bundleHint'),
              isDense: true,
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            icon: const Icon(Icons.restore, size: 16),
            label: Text(_t('restore')),
            onPressed: _importBundleController.text.isEmpty
                ? null
                : _importFromBundle,
          ),
          const Divider(height: 24),

          // Import from mnemonic
          Text(_t('recoverTitle'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: _importMnemonicController,
            onChanged: (_) => setState(() {}),
            maxLines: 2,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'word1 word2 word3 ... word24',
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            icon: const Icon(Icons.vpn_key, size: 16),
            label: Text(_t('recover')),
            onPressed: _importMnemonicController.text.isEmpty
                ? null
                : _importFromMnemonic,
          ),
          const Divider(height: 24),

          // Import from hex
          Text(_t('importRaw'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: _importHexController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: _t('hexHint'),
              isDense: true,
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            icon: const Icon(Icons.input, size: 16),
            label: Text(_t('importHex')),
            onPressed: _importHexController.text.isEmpty
                ? null
                : _importFromHex,
          ),
        ],
      ),
    );
  }
}
