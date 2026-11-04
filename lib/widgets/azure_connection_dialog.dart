// lib/widgets/azure_connection_dialog.dart
//
// Connection dialog for Azure Blob Storage.
// Supports three authentication modes:
//   1. Account Key  — Account Name + Account Key + Container
//   2. SAS Token    — Full SAS URL  or  Account Name + SAS Token + Container
//   3. Connection String — paste the full Azure connection string

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import '../services/azure_config_service.dart';
import '../l10n/app_localizations.dart';
import '../l10n/cloud_setup_strings.dart';

// ---------------------------------------------------------------------------
// Auth mode enum
// ---------------------------------------------------------------------------

enum _AzureAuthMode { accountKey, sasToken, connectionString }

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class AzureConnectionDialog extends ConsumerStatefulWidget {
  const AzureConnectionDialog({super.key});

  @override
  ConsumerState<AzureConnectionDialog> createState() =>
      _AzureConnectionDialogState();
}

class _AzureConnectionDialogState
    extends ConsumerState<AzureConnectionDialog> {
  _AzureAuthMode _authMode = _AzureAuthMode.accountKey;

  // Account Key mode
  final _accountNameController = TextEditingController();
  final _accountKeyController = TextEditingController();
  final _containerController = TextEditingController();

  // SAS Token mode
  final _sasUrlController = TextEditingController();
  final _sasAccountNameController = TextEditingController();
  final _sasTokenController = TextEditingController();
  final _sasContainerController = TextEditingController();
  bool _sasUseFull = true; // true → paste full SAS URL; false → separate fields

  // Connection String mode
  final _connStringController = TextEditingController();

  bool _isLoading = false;
  bool _isTesting = false;
  String? _error;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final svc = AzureConfigService(
      secureStorage: ref.read(secureStorageProvider),
    );
    final creds = await svc.readCredentials();
    if (creds == null || !mounted) return;

    setState(() {
      final mode = creds['authMode'];
      if (mode == 'accountKey') {
        _authMode = _AzureAuthMode.accountKey;
        _accountNameController.text = creds['accountName'] ?? '';
        _accountKeyController.text = creds['accountKey'] ?? '';
        _containerController.text = creds['container'] ?? '';
      } else if (mode == 'sasToken') {
        _authMode = _AzureAuthMode.sasToken;
        _sasUrlController.text = creds['sasUrl'] ?? '';
        _sasAccountNameController.text = creds['accountName'] ?? '';
        _sasTokenController.text = creds['sasToken'] ?? '';
        _sasContainerController.text = creds['container'] ?? '';
        _sasUseFull = creds['sasUseFull'] != 'false';
      } else if (mode == 'connectionString') {
        _authMode = _AzureAuthMode.connectionString;
        _connStringController.text = creds['connectionString'] ?? '';
      }
    });
  }

  String _text(String key, [Map<String, Object> values = const {}]) =>
      CloudSetupStrings(context).text(key, values);

  // ── Validation ────────────────────────────────────────────────────────────

  String? _validate() {
    switch (_authMode) {
      case _AzureAuthMode.accountKey:
        if (_accountNameController.text.trim().isEmpty) {
          return _text('accountNameRequired');
        }
        if (_accountKeyController.text.trim().isEmpty) {
          return _text('accountKeyRequired');
        }
        if (_containerController.text.trim().isEmpty) {
          return _text('containerRequired');
        }
        return null;

      case _AzureAuthMode.sasToken:
        if (_sasUseFull) {
          if (_sasUrlController.text.trim().isEmpty) {
            return _text('sasUrlRequired');
          }
          final token = AzureConfigService.parseSasToken(
            _sasUrlController.text.trim(),
          );
          if (token == null) {
            return _text('sasInvalid');
          }
        } else {
          if (_sasAccountNameController.text.trim().isEmpty) {
            return _text('accountNameRequired');
          }
          if (_sasTokenController.text.trim().isEmpty) {
            return _text('sasTokenRequired');
          }
          if (_sasContainerController.text.trim().isEmpty) {
            return _text('containerRequired');
          }
        }
        return null;

      case _AzureAuthMode.connectionString:
        if (_connStringController.text.trim().isEmpty) {
          return _text('connectionRequired');
        }
        final info = AzureConfigService.parseConnectionString(
          _connStringController.text.trim(),
        );
        if (info == null) {
          return _text('connectionInvalid');
        }
        return null;
    }
  }

  // ── Build credential map ──────────────────────────────────────────────────

  Map<String, String> _buildCredentials() {
    switch (_authMode) {
      case _AzureAuthMode.accountKey:
        return {
          'authMode': 'accountKey',
          'accountName': _accountNameController.text.trim(),
          'accountKey': _accountKeyController.text.trim(),
          'container': _containerController.text.trim(),
        };
      case _AzureAuthMode.sasToken:
        if (_sasUseFull) {
          return {
            'authMode': 'sasToken',
            'sasUrl': _sasUrlController.text.trim(),
            'sasUseFull': 'true',
          };
        } else {
          return {
            'authMode': 'sasToken',
            'accountName': _sasAccountNameController.text.trim(),
            'sasToken': _sasTokenController.text.trim(),
            'container': _sasContainerController.text.trim(),
            'sasUseFull': 'false',
          };
        }
      case _AzureAuthMode.connectionString:
        return {
          'authMode': 'connectionString',
          'connectionString': _connStringController.text.trim(),
        };
    }
  }

  // ── Check Format ───────────────────────────────────────────────────────

  Future<void> _testConnection() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() {
        _error = validationError;
        _testResult = null;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _error = null;
      _testResult = null;
    });

    try {
      // This checks local formatting only; it does not contact Azure.

      // Parse / derive endpoint for display.
      String endpoint;
      if (_authMode == _AzureAuthMode.accountKey) {
        endpoint = AzureConfigService.getEndpoint(
          _accountNameController.text.trim(),
        );
      } else if (_authMode == _AzureAuthMode.sasToken && _sasUseFull) {
        final uri = Uri.tryParse(_sasUrlController.text.trim());
        endpoint = uri != null
            ? '${uri.scheme}://${uri.host}'
            : _sasUrlController.text.trim();
      } else if (_authMode == _AzureAuthMode.sasToken) {
        endpoint = AzureConfigService.getEndpoint(
          _sasAccountNameController.text.trim(),
        );
      } else {
        final info = AzureConfigService.parseConnectionString(
          _connStringController.text.trim(),
        )!;
        endpoint = info.blobEndpoint;
      }

      setState(() {
        _testResult = _text('connected', {'endpoint': endpoint});
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _error = _text('formatFailed', {'error': e.toString().replaceAll('Exception:', '').trim()});
        _isTesting = false;
      });
    }
  }

  // ── Save & Connect ────────────────────────────────────────────────────────

  Future<void> _connect() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final svc = AzureConfigService(
        secureStorage: ref.read(secureStorageProvider),
      );
      await svc.saveCredentials(_buildCredentials());

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception:', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_text('azure')),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Auth mode selector ──────────────────────────────────────────
            Text(
              _text('mode'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            RadioGroup<_AzureAuthMode>(
              groupValue: _authMode,
              onChanged: (v) {
                if (_isLoading || v == null) return;
                setState(() {
                  _authMode = v;
                  _error = null;
                  _testResult = null;
                });
              },
              child: Column(
                children: [
                  _ModeRadio<_AzureAuthMode>(
                    value: _AzureAuthMode.accountKey,
                    label: _text('accountKey'),
                  ),
                  _ModeRadio<_AzureAuthMode>(
                    value: _AzureAuthMode.sasToken,
                    label: _text('sasToken'),
                  ),
                  _ModeRadio<_AzureAuthMode>(
                    value: _AzureAuthMode.connectionString,
                    label: _text('connectionString'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // ── Mode-specific fields ────────────────────────────────────────
            if (_authMode == _AzureAuthMode.accountKey) ..._accountKeyFields(),
            if (_authMode == _AzureAuthMode.sasToken) ..._sasTokenFields(),
            if (_authMode == _AzureAuthMode.connectionString)
              ..._connectionStringFields(),

            // ── Error / test result ─────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 12),
              _StatusBanner(
                message: _error!,
                isError: true,
              ),
            ],
            if (_testResult != null && _error == null) ...[
              const SizedBox(height: 12),
              _StatusBanner(
                message: _testResult!,
                isError: false,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_isLoading || _isTesting)
              ? null
              : () => Navigator.pop(context, false),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        TextButton(
          onPressed: (_isLoading || _isTesting) ? null : _testConnection,
          child: _isTesting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_text('checkFormat')),
        ),
        ElevatedButton(
          onPressed: (_isLoading || _isTesting) ? null : _connect,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(AppLocalizations.of(context)!.connect),
        ),
      ],
    );
  }

  // ── Field builders ────────────────────────────────────────────────────────

  List<Widget> _accountKeyFields() => [
        TextField(
          key: const Key('azure_account_name'),
          controller: _accountNameController,
          enabled: !_isLoading,
          decoration: InputDecoration(
            labelText: _text('accountName'),
            hintText: 'mystorageaccount',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.storage_outlined),
            helperText: _text('accountHelp'),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('azure_account_key'),
          controller: _accountKeyController,
          enabled: !_isLoading,
          obscureText: true,
          decoration: InputDecoration(
            labelText: _text('accountKey'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.vpn_key_outlined),
            helperText: _text('azureKeyHelp'),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('azure_container'),
          controller: _containerController,
          enabled: !_isLoading,
          decoration: InputDecoration(
            labelText: _text('container'),
            hintText: 'my-container',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.folder_outlined),
          ),
        ),
      ];

  List<Widget> _sasTokenFields() => [
        // Toggle: full URL or separate fields
        RadioGroup<bool>(
          groupValue: _sasUseFull,
          onChanged: (v) {
            if (_isLoading || v == null) return;
            setState(() => _sasUseFull = v);
          },
          child: Row(
            children: [
              Expanded(
                child: RadioListTile<bool>(
                  value: true,
                  title: Text(_text('fullUrl'), style: const TextStyle(fontSize: 13)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Expanded(
                child: RadioListTile<bool>(
                  value: false,
                  title: Text(_text('tokenAccount'), style: const TextStyle(fontSize: 13)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_sasUseFull) ...[
          TextField(
            key: const Key('azure_sas_url'),
            controller: _sasUrlController,
            enabled: !_isLoading,
            decoration: InputDecoration(
              labelText: 'SAS URL',
              hintText:
                  'https://account.blob.core.windows.net/container?sv=…&sig=…',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link),
              helperText:
                  _text('sasUrlHelp'),
            ),
          ),
        ] else ...[
          TextField(
            key: const Key('azure_sas_account_name'),
            controller: _sasAccountNameController,
            enabled: !_isLoading,
            decoration: InputDecoration(
              labelText: _text('accountName'),
              hintText: 'mystorageaccount',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.storage_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('azure_sas_token'),
            controller: _sasTokenController,
            enabled: !_isLoading,
            obscureText: true,
            decoration: InputDecoration(
              labelText: _text('sasToken'),
              hintText: 'sv=2023-11-03&ss=b&…&sig=…',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              helperText:
                  _text('tokenHelp'),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('azure_sas_container'),
            controller: _sasContainerController,
            enabled: !_isLoading,
            decoration: InputDecoration(
              labelText: _text('container'),
              hintText: 'my-container',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.folder_outlined),
            ),
          ),
        ],
      ];

  List<Widget> _connectionStringFields() => [
        TextField(
          key: const Key('azure_connection_string'),
          controller: _connStringController,
          enabled: !_isLoading,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: _text('connectionString'),
            hintText:
                'DefaultEndpointsProtocol=https;AccountName=…;AccountKey=…;EndpointSuffix=core.windows.net',
            border: const OutlineInputBorder(),
            helperText:
                _text('azureKeyHelp'),
          ),
        ),
      ];

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _accountNameController.dispose();
    _accountKeyController.dispose();
    _containerController.dispose();
    _sasUrlController.dispose();
    _sasAccountNameController.dispose();
    _sasTokenController.dispose();
    _sasContainerController.dispose();
    _connStringController.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _ModeRadio<T> extends StatelessWidget {
  final T value;
  final String label;

  const _ModeRadio({
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<T>(
      value: value,
      title: Text(label),
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String message;
  final bool isError;

  const _StatusBanner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.red : Colors.green;
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: color.shade700),
            ),
          ),
        ],
      ),
    );
  }
}
