import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/settings_strings.dart';
import '../services/credential_storage_config.dart';
import '../services/macos_keychain_service.dart';
import '../services/secure_storage_service.dart';

/// Result of the credential-storage chooser.
class CredentialStorageSetupResult {
  const CredentialStorageSetupResult({
    required this.mode,
    this.keychainPath,
    this.masterPassword,
  });

  final CredentialStorageMode mode;
  final String? keychainPath;
  final String? masterPassword;
}

enum _KeychainChoice { login, existing, newKeychain }

/// Full-screen first-run setup. It is shown before the main app mounts so the
/// user chooses a working backend instead of being auto-dropped into a keychain
/// failure.
class CredentialStorageSetupScreen extends StatelessWidget {
  const CredentialStorageSetupScreen({super.key, required this.onComplete});

  final ValueChanged<CredentialStorageSetupResult> onComplete;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CredentialStorageSetupPanel(
                    firstRun: true,
                    onComplete: onComplete,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<CredentialStorageSetupResult?> showCredentialStorageSetupDialog(
  BuildContext context, {
  bool firstRun = false,
  CredentialStorageMode initialMode = CredentialStorageMode.systemKeychain,
  String? initialKeychainPath,
}) {
  return showDialog<CredentialStorageSetupResult>(
    context: context,
    barrierDismissible: !firstRun,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: CredentialStorageSetupPanel(
            firstRun: firstRun,
            initialMode: initialMode,
            initialKeychainPath: initialKeychainPath,
            onComplete: (result) => Navigator.pop(dialogContext, result),
          ),
        ),
      ),
    ),
  );
}

class CredentialStorageSetupPanel extends StatefulWidget {
  const CredentialStorageSetupPanel({
    super.key,
    required this.onComplete,
    this.firstRun = false,
    this.initialMode = CredentialStorageMode.systemKeychain,
    this.initialKeychainPath,
  });

  final ValueChanged<CredentialStorageSetupResult> onComplete;
  final bool firstRun;
  final CredentialStorageMode initialMode;
  final String? initialKeychainPath;

  @override
  State<CredentialStorageSetupPanel> createState() =>
      _CredentialStorageSetupPanelState();
}

class _CredentialStorageSetupPanelState
    extends State<CredentialStorageSetupPanel> {
  late CredentialStorageMode _mode = widget.initialMode;
  late _KeychainChoice _keychainChoice = widget.initialKeychainPath == null
      ? _KeychainChoice.login
      : _KeychainChoice.existing;
  late final TextEditingController _existingPath = TextEditingController(
    text: widget.initialKeychainPath ?? '',
  );
  final _newPath = TextEditingController(
    text: '~/Library/Keychains/CrispCloud.keychain-db',
  );
  final _newPassword = TextEditingController();
  final _masterPassword = TextEditingController();
  final _masterConfirmation = TextEditingController();
  bool _obscureNew = true;
  bool _obscureMaster = true;
  bool _obscureConfirmation = true;
  bool _busy = false;
  String? _error;
  List<MacosKeychainInfo> _keychains = const [];

  bool get _macKeychain => MacosKeychainService.isSupported;

  @override
  void initState() {
    super.initState();
    if (_macKeychain) _loadKeychains();
  }

  Future<void> _loadKeychains() async {
    try {
      final items = await MacosKeychainService.listKeychains().timeout(
        const Duration(milliseconds: 800),
        onTimeout: () => const <MacosKeychainInfo>[],
      );
      if (mounted) setState(() => _keychains = items);
    } catch (_) {
      // The manual path field remains available.
    }
  }

  @override
  void dispose() {
    _existingPath.dispose();
    _newPath.dispose();
    _newPassword.dispose();
    _masterPassword.dispose();
    _masterConfirmation.dispose();
    super.dispose();
  }

  String _text(String value) => SettingsStrings(context).text(value);

  Future<void> _pickExistingKeychain() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    final path = picked?.files.single.path;
    if (path != null && mounted) {
      setState(() {
        _keychainChoice = _KeychainChoice.existing;
        _existingPath.text = path;
      });
    }
  }

  void _complete(CredentialStorageSetupResult result) {
    if (mounted) setState(() => _busy = false);
    widget.onComplete(result);
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      if (_macKeychain && _keychains.isEmpty) await _loadKeychains();
      if (_mode == CredentialStorageMode.encryptedFile) {
        if (!widget.firstRun) {
          _complete(
            const CredentialStorageSetupResult(
              mode: CredentialStorageMode.encryptedFile,
            ),
          );
          return;
        }
        final password = _masterPassword.text.trim();
        if (password.isEmpty) {
          throw const FormatException('Enter a master password.');
        }
        if (password != _masterConfirmation.text.trim()) {
          throw const FormatException('Master passwords do not match.');
        }
        _complete(
          CredentialStorageSetupResult(
            mode: CredentialStorageMode.encryptedFile,
            masterPassword: password,
          ),
        );
        return;
      }

      if (_mode == CredentialStorageMode.sessionOnly) {
        _complete(
          const CredentialStorageSetupResult(
            mode: CredentialStorageMode.sessionOnly,
          ),
        );
        return;
      }

      String? path;
      if (_macKeychain) {
        switch (_keychainChoice) {
          case _KeychainChoice.login:
            path = null;
            for (final keychain in _keychains) {
              if (keychain.label.toLowerCase() == 'login') {
                path = keychain.path;
                break;
              }
            }
            if (path != null) {
              await MacosKeychainService.selectKeychain(path);
            }
          case _KeychainChoice.existing:
            path = _existingPath.text.trim();
            if (path.isEmpty) {
              throw const FormatException('Select a keychain file.');
            }
            await MacosKeychainService.selectKeychain(path);
          case _KeychainChoice.newKeychain:
            path = _newPath.text.trim();
            final password = _newPassword.text;
            if (path.isEmpty || password.isEmpty) {
              throw const FormatException(
                'Enter a path and password for the new keychain.',
              );
            }
            await MacosKeychainService.createKeychain(path, password);
        }
        final probe = PlatformSecureStorage(
          useDataProtectionKeyChain: path == null,
        );
        if (!await probe.isAvailable()) {
          throw const FormatException(
            'This keychain could not be used. Choose another keychain or the encrypted file vault.',
          );
        }
      }

      _complete(
        CredentialStorageSetupResult(
          mode: CredentialStorageMode.systemKeychain,
          keychainPath: path,
        ),
      );
    } on FlutterError catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message ?? error.toString();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.key, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _text(
                  widget.firstRun
                      ? 'Choose credential storage'
                      : 'Credential storage',
                ),
                style: theme.textTheme.headlineSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _text(
            widget.firstRun
                ? 'Choose where CrispCloud keeps provider credentials. You can change this later in Settings.'
                : 'Where should CrispCloud keep provider credentials after the next restart?',
          ),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _modeTile(
          CredentialStorageMode.systemKeychain,
          Icons.lock_outline,
          'System keychain',
          _macKeychain
              ? 'macOS Keychain. Choose the login keychain or another keychain file.'
              : 'The operating-system keychain or credential manager.',
        ),
        if (_mode == CredentialStorageMode.systemKeychain && _macKeychain) ...[
          const SizedBox(height: 8),
          _keychainChoices(),
        ],
        _modeTile(
          CredentialStorageMode.encryptedFile,
          Icons.enhanced_encryption_outlined,
          'Encrypted file (master password)',
          'AES-256-GCM vault in the app support folder. No OS keychain is needed.',
        ),
        if (_mode == CredentialStorageMode.encryptedFile && widget.firstRun)
          _masterPasswordFields(),
        _modeTile(
          CredentialStorageMode.sessionOnly,
          Icons.timer_outlined,
          'This session only',
          'Credentials are forgotten when CrispCloud exits.',
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const ValueKey('credential-setup-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('credential-setup-continue'),
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(
            _text(widget.firstRun ? 'Continue' : 'Save and restart later'),
          ),
        ),
      ],
    );
  }

  Widget _modeTile(
    CredentialStorageMode value,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return RadioListTile<CredentialStorageMode>(
      value: value,
      groupValue: _mode,
      title: Text(_text(title)),
      subtitle: Text(_text(subtitle)),
      secondary: Icon(icon),
      onChanged: (selected) {
        if (selected != null) setState(() => _mode = selected);
      },
    );
  }

  Widget _keychainChoices() {
    return Card(
      margin: const EdgeInsets.only(left: 24),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioListTile<_KeychainChoice>(
              value: _KeychainChoice.login,
              groupValue: _keychainChoice,
              title: Text(_text('Login / system default keychain')),
              onChanged: (value) =>
                  setState(() => _keychainChoice = value ?? _keychainChoice),
            ),
            for (final keychain in _keychains)
              ListTile(
                leading: Icon(
                  Icons.key,
                  color:
                      _keychainChoice == _KeychainChoice.existing &&
                          _existingPath.text == keychain.path
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(keychain.label),
                subtitle: Text(keychain.path),
                trailing:
                    _keychainChoice == _KeychainChoice.existing &&
                        _existingPath.text == keychain.path
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => setState(() {
                  _keychainChoice = _KeychainChoice.existing;
                  _existingPath.text = keychain.path;
                }),
              ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(_text('Other keychain file…')),
              subtitle: Text(
                _existingPath.text.isEmpty
                    ? _text('Choose a .keychain-db file')
                    : _existingPath.text,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickExistingKeychain,
            ),
            RadioListTile<_KeychainChoice>(
              value: _KeychainChoice.newKeychain,
              groupValue: _keychainChoice,
              title: Text(_text('Create a new keychain…')),
              onChanged: (value) =>
                  setState(() => _keychainChoice = value ?? _keychainChoice),
            ),
            if (_keychainChoice == _KeychainChoice.existing &&
                _existingPath.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _existingPath.text,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: _pickExistingKeychain,
                      child: Text(_text('Browse…')),
                    ),
                  ],
                ),
              ),
            if (_keychainChoice == _KeychainChoice.newKeychain) ...[
              TextField(
                controller: _newPath,
                decoration: InputDecoration(
                  labelText: _text('New keychain file'),
                  hintText: '~/Library/Keychains/CrispCloud.keychain-db',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newPassword,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: _text('Keychain password'),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _text(
                      _obscureNew ? 'Show password' : 'Hide password',
                    ),
                    icon: Icon(
                      _obscureNew ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _masterPasswordFields() {
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 8),
      child: Column(
        children: [
          TextField(
            controller: _masterPassword,
            obscureText: _obscureMaster,
            decoration: InputDecoration(
              labelText: _text('Master password'),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _text(
                  _obscureMaster ? 'Show password' : 'Hide password',
                ),
                icon: Icon(
                  _obscureMaster ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () =>
                    setState(() => _obscureMaster = !_obscureMaster),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _masterConfirmation,
            obscureText: _obscureConfirmation,
            decoration: InputDecoration(
              labelText: _text('Confirm master password'),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _text(
                  _obscureConfirmation ? 'Show password' : 'Hide password',
                ),
                icon: Icon(
                  _obscureConfirmation
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
                onPressed: () => setState(
                  () => _obscureConfirmation = !_obscureConfirmation,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
