// lib/widgets/key_management_dialog.dart
//
// Key management dialog: export/import encryption keys, BIP39 mnemonic
// backup and recovery. Accessible from the connection dialog or app bar
// when encryption is active.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/encryption_service.dart';
import '../utils/secure_clipboard.dart';

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
  String? _saltHex;
  String? _backupBundle;

  // Import tab
  final _importMnemonicController = TextEditingController();
  final _importHexController = TextEditingController();
  final _importBundleController = TextEditingController();
  String? _importError;
  String? _importSuccess;

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
    _saltHex = mnemonicData['salt'];
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
      setState(() => _importSuccess = 'Key recovered from mnemonic. '
          'Note: a new salt was generated. Previously encrypted files will '
          'still decrypt correctly (salt is only for key derivation).');
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
      setState(() => _importSuccess = 'Key imported successfully.');
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
          _importSuccess = 'Key and salt restored from backup bundle.');
    } on FormatException catch (e) {
      setState(() => _importError = e.message);
    } catch (e) {
      setState(() => _importError = e.toString());
    }
  }

  void _copyToClipboard(String data, String label) {
    SecureClipboard.copy(data);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard (auto-clears in 30s)')),
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
      title: const Row(
        children: [
          Icon(Icons.key, size: 20),
          SizedBox(width: 8),
          Text('Key Management'),
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
                        'Encryption is not active. Enable it in the connection dialog, '
                        'or import an existing key below.',
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
              tabs: const [
                Tab(text: 'Export / Backup'),
                Tab(text: 'Import / Recover'),
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
            child: const Text('Close')),
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
            Text('No encryption key to export',
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
            title: 'Recovery Phrase (BIP39)',
            subtitle:
                'Write down these 24 words in order. They can recover your key.',
            content: _mnemonic ?? '',
            copyLabel: 'Mnemonic',
            sensitive: true,
          ),
          const SizedBox(height: 16),
          // Raw key hex
          _exportSection(
            theme,
            icon: Icons.vpn_key,
            title: 'Raw Key (Hex)',
            subtitle: '32-byte encryption key as hexadecimal.',
            content: _keyHex ?? '',
            copyLabel: 'Key',
            sensitive: true,
          ),
          const SizedBox(height: 16),
          // Backup bundle
          _exportSection(
            theme,
            icon: Icons.backup,
            title: 'Full Backup Bundle',
            subtitle:
                'JSON with mnemonic, salt, and verification. Best for full recovery.',
            content: _backupBundle ?? '',
            copyLabel: 'Backup bundle',
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
            label: Text('Copy $copyLabel', style: const TextStyle(fontSize: 12)),
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
          Text('Restore from Backup Bundle (recommended)',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: theme.colorScheme.primary)),
          const SizedBox(height: 4),
          TextField(
            controller: _importBundleController,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Paste backup bundle JSON...',
              isDense: true,
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            icon: const Icon(Icons.restore, size: 16),
            label: const Text('Restore from Bundle'),
            onPressed: _importBundleController.text.isEmpty
                ? null
                : _importFromBundle,
          ),
          const Divider(height: 24),

          // Import from mnemonic
          const Text('Recover from Mnemonic (24 words)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: _importMnemonicController,
            maxLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'word1 word2 word3 ... word24',
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            icon: const Icon(Icons.vpn_key, size: 16),
            label: const Text('Recover from Mnemonic'),
            onPressed: _importMnemonicController.text.isEmpty
                ? null
                : _importFromMnemonic,
          ),
          const Divider(height: 24),

          // Import from hex
          const Text('Import Raw Key (Hex)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: _importHexController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '64 hex characters (32 bytes)',
              isDense: true,
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            icon: const Icon(Icons.input, size: 16),
            label: const Text('Import Hex Key'),
            onPressed: _importHexController.text.isEmpty
                ? null
                : _importFromHex,
          ),
        ],
      ),
    );
  }
}
