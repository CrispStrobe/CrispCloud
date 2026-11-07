import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/credential_storage_config.dart';

/// Offered only after independent first-install checks establish that no
/// existing local profile or lock policy is being bypassed.
class CredentialStorageFirstSetupApp extends StatelessWidget {
  const CredentialStorageFirstSetupApp({
    super.key,
    required this.onSelected,
    required this.onRetry,
  });

  final ValueChanged<CredentialStorageMode> onSelected;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Choose credential storage',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No existing CrispCloud profile was found, and the system '
                    'keychain is unavailable. Choose how to keep credentials '
                    'on this device.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => onSelected(CredentialStorageMode.encryptedFile),
                    child: const Text('Use an encrypted file vault'),
                  ),
                  const Text(
                    'A master password protects saved credentials and is '
                    'required each time the app opens.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => onSelected(CredentialStorageMode.sessionOnly),
                    child: const Text('Keep credentials for this session only'),
                  ),
                  const Text(
                    'Reconnect after every restart. No saved credential '
                    'migration, persistent app lock, or unattended sync.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: onRetry,
                    child: Text('${AppLocalizations.of(context)!.retry} system keychain'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
