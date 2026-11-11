import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/settings_strings.dart';
import '../l10n/startup_failure_strings.dart';
import '../l10n/app_localizations.dart';
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
  bool applyNow = false,
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
            applyNow: applyNow,
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
    this.applyNow = false,
    this.initialMode = CredentialStorageMode.systemKeychain,
    this.initialKeychainPath,
  });

  final ValueChanged<CredentialStorageSetupResult> onComplete;
  final bool firstRun;

  /// The choice is used immediately (startup recovery) rather than saved for
  /// the next launch. File vaults are still created only by the password gate.
  final bool applyNow;
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

  static const _validationMessages = {
    'Use at least 8 characters for the master password.',
    'Master passwords do not match.',
    'Select a keychain file.',
    'Enter a path and password for the new keychain.',
    'The system keychain is unavailable. Choose an encrypted file or session-only storage.',
    _keychainLocked,
    _keychainAccessNeeded,
  };

  static const _keychainLocked =
      'The selected keychain is locked. Unlock it in Keychain Access, then continue.';
  static const _keychainAccessNeeded =
      'CrispCloud needs permission to use this keychain file. Choose it in the file dialog to grant access.';

  /// Probes an existing keychain file. A path from the discovery list (or typed
  /// by hand) carries no sandbox permission, so an access failure opens the
  /// native picker for that file once and retries with the granted file.
  /// Returns the usable path; cancelling the picker is a validation error.
  Future<String> _probeExistingKeychain(String path) async {
    try {
      await MacosKeychainService.selectKeychain(path);
      return path;
    } on PlatformException catch (error) {
      if (error.code == 'custom_keychain_locked') {
        throw const FormatException(_keychainLocked);
      }
    }
    final granted = await MacosKeychainService.chooseKeychain(
      initialPath: path,
    );
    if (granted == null) throw const FormatException(_keychainAccessNeeded);
    if (mounted) setState(() => _existingPath.text = granted);
    try {
      await MacosKeychainService.selectKeychain(granted);
    } on PlatformException catch (error) {
      throw FormatException(
        error.code == 'custom_keychain_locked'
            ? _keychainLocked
            : _keychainAccessNeeded,
      );
    }
    return granted;
  }

  Future<void> _pickExistingKeychain() async {
    try {
      final path = await MacosKeychainService.chooseKeychain(
        initialPath: _existingPath.text.trim(),
      );
      if (path != null && mounted) {
        setState(() {
          _keychainChoice = _KeychainChoice.existing;
          _existingPath.text = path;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = _text('Could not open the keychain chooser.'));
      }
    }
  }

  void _complete(CredentialStorageSetupResult result) {
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onComplete(result);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      if (_macKeychain && _keychains.isEmpty) await _loadKeychains();
      if (!mounted) return;
      if (_mode == CredentialStorageMode.encryptedFile) {
        if (!widget.firstRun) {
          _complete(
            const CredentialStorageSetupResult(
              mode: CredentialStorageMode.encryptedFile,
            ),
          );
          return;
        }
        final password = _masterPassword.text;
        if (password.length < 8) {
          throw const FormatException(
            'Use at least 8 characters for the master password.',
          );
        }
        if (password != _masterConfirmation.text) {
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
            // The ordinary OS store uses its app-scoped data-protection
            // backend. A discovered login.keychain-db path is not equivalent.
            path = null;
          case _KeychainChoice.existing:
            path = _existingPath.text.trim();
            if (path.isEmpty) {
              throw const FormatException('Select a keychain file.');
            }
          case _KeychainChoice.newKeychain:
            path = _newPath.text.trim();
            final password = _newPassword.text;
            if (path.isEmpty || password.isEmpty) {
              throw const FormatException(
                'Enter a path and password for the new keychain.',
              );
            }
            path = await MacosKeychainService.createKeychain(path, password);
            if (!mounted) return;
            if (path == null) {
              if (mounted) setState(() => _busy = false);
              return;
            }
            if (mounted) {
              // A created file is a side effect explicitly requested by the
              // user. If later validation fails, retry that file, never create
              // another keychain or overwrite the first one.
              setState(() {
                _keychainChoice = _KeychainChoice.existing;
                _existingPath.text = path!;
              });
            }
        }
      }
      if (path == null) {
        if (!await PlatformSecureStorage().isAvailable()) {
          throw const FormatException(
            'The system keychain is unavailable. Choose an encrypted file or session-only storage.',
          );
        }
      } else {
        // Probe only the explicit selected/created keychain. Failure must not
        // silently turn this into a probe of the default OS keychain.
        path = await _probeExistingKeychain(path);
        if (!mounted) return;
      }

      _complete(
        CredentialStorageSetupResult(
          mode: CredentialStorageMode.systemKeychain,
          keychainPath: path,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          // Show only our fixed validation messages. Platform and parse
          // exceptions can include private paths or credential contents.
          _error =
              error is FormatException &&
                  _validationMessages.contains(error.message)
              ? _text(error.message)
              : StartupFailureStrings(context).credentialStorageUnavailable;
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
            widget.firstRun || widget.applyNow
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
              ? 'Use macOS secure storage or choose a separate keychain file.'
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
          'An encrypted file unlocked with your master password. No OS keychain is needed.',
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
            _text(
              widget.firstRun || widget.applyNow
                  ? 'Continue'
                  : 'Save and restart later',
            ),
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
      onChanged: _busy
          ? null
          : (selected) {
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
              title: Text(_text('System keychain')),
              onChanged: _busy
                  ? null
                  : (value) => setState(
                      () => _keychainChoice = value ?? _keychainChoice,
                    ),
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
                onTap: _busy
                    ? null
                    : () => setState(() {
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
              onTap: _busy ? null : _pickExistingKeychain,
            ),
            RadioListTile<_KeychainChoice>(
              value: _KeychainChoice.newKeychain,
              groupValue: _keychainChoice,
              title: Text(_text('Create a new keychain…')),
              onChanged: _busy
                  ? null
                  : (value) => setState(
                      () => _keychainChoice = value ?? _keychainChoice,
                    ),
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
                      onPressed: _busy ? null : _pickExistingKeychain,
                      child: Text(_text('Browse…')),
                    ),
                  ],
                ),
              ),
            if (_keychainChoice == _KeychainChoice.newKeychain) ...[
              TextField(
                controller: _newPath,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: _text('New keychain file'),
                  hintText: '~/Library/Keychains/CrispCloud.keychain-db',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newPassword,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
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
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
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
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
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
