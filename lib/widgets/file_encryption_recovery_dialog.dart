import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/key_management_strings.dart';
import '../services/encryption_service.dart';
import '../utils/secure_clipboard.dart';

/// Confirm recovery of the exact key that will be used for this connection.
/// This dialog does not activate encryption or persist the key or phrase.
Future<bool> showFileEncryptionRecoveryDialog(
  BuildContext context, {
  required Uint8List encryptionKey,
  required Uint8List salt,
}) async {
  final phrase = EncryptionService.generateMnemonic(encryptionKey, salt)[
    'mnemonic'
  ]!;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => FileEncryptionRecoveryDialog(mnemonic: phrase),
      ) ??
      false;
}

class FileEncryptionRecoveryDialog extends StatefulWidget {
  const FileEncryptionRecoveryDialog({super.key, required this.mnemonic});

  final String mnemonic;

  @override
  State<FileEncryptionRecoveryDialog> createState() =>
      _FileEncryptionRecoveryDialogState();
}

class _FileEncryptionRecoveryDialogState
    extends State<FileEncryptionRecoveryDialog> {
  final _confirmation = TextEditingController();
  bool _copying = false;
  bool _copied = false;
  bool _copyFailed = false;

  static String _normalize(String value) =>
      value.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

  bool get _confirmed {
    final entered = _normalize(_confirmation.text);
    return entered.split(' ').length == 24 &&
        entered == _normalize(widget.mnemonic);
  }

  Future<void> _copyPhrase() async {
    setState(() {
      _copying = true;
      _copied = false;
      _copyFailed = false;
    });
    try {
      await SecureClipboard.copy(widget.mnemonic);
      if (!mounted) return;
      setState(() => _copied = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _copyFailed = true);
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = KeyManagementStrings(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(strings.text('fileRecoveryTitle')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.text('fileRecoveryWarning')),
              const SizedBox(height: 16),
              Text(
                strings.text('phrase'),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.mnemonic,
                  key: const Key('file_encryption_recovery_phrase'),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace', height: 1.5),
                ),
              ),
              TextButton.icon(
                key: const Key('file_encryption_recovery_copy'),
                onPressed: _copying ? null : _copyPhrase,
                icon: const Icon(Icons.copy, size: 18),
                label: Text(
                  strings.text('copy', {'label': strings.text('mnemonic')}),
                ),
              ),
              if (_copied)
                Text(
                  strings.text('copied', {'label': strings.text('mnemonic')}),
                ),
              if (_copyFailed)
                Text(
                  strings.text('fileRecoveryCopyFailed'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('file_encryption_recovery_confirmation'),
                controller: _confirmation,
                minLines: 3,
                maxLines: 5,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                autofillHints: const [],
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: strings.text('fileRecoveryConfirm'),
                  helperText: strings.text('fileRecoveryConfirmHelp'),
                  helperMaxLines: 3,
                  errorText: _confirmation.text.isNotEmpty && !_confirmed
                      ? strings.text('fileRecoveryMismatch')
                      : null,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('file_encryption_recovery_cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          key: const Key('file_encryption_recovery_confirm'),
          onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
          child: Text(strings.text('fileRecoveryContinue')),
        ),
      ],
    );
  }
}
