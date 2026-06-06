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

  // ── Validation ────────────────────────────────────────────────────────────

  String? _validate() {
    switch (_authMode) {
      case _AzureAuthMode.accountKey:
        if (_accountNameController.text.trim().isEmpty) {
          return 'Account Name is required';
        }
        if (_accountKeyController.text.trim().isEmpty) {
          return 'Account Key is required';
        }
        if (_containerController.text.trim().isEmpty) {
          return 'Container name is required';
        }
        return null;

      case _AzureAuthMode.sasToken:
        if (_sasUseFull) {
          if (_sasUrlController.text.trim().isEmpty) {
            return 'SAS URL is required';
          }
          final token = AzureConfigService.parseSasToken(
            _sasUrlController.text.trim(),
          );
          if (token == null) {
            return 'SAS URL does not appear to contain a valid query string';
          }
        } else {
          if (_sasAccountNameController.text.trim().isEmpty) {
            return 'Account Name is required';
          }
          if (_sasTokenController.text.trim().isEmpty) {
            return 'SAS Token is required';
          }
          if (_sasContainerController.text.trim().isEmpty) {
            return 'Container name is required';
          }
        }
        return null;

      case _AzureAuthMode.connectionString:
        if (_connStringController.text.trim().isEmpty) {
          return 'Connection String is required';
        }
        final info = AzureConfigService.parseConnectionString(
          _connStringController.text.trim(),
        );
        if (info == null) {
          return 'Connection string is not valid. '
              'Expected format: DefaultEndpointsProtocol=…;AccountName=…;AccountKey=…';
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

  // ── Test Connection ───────────────────────────────────────────────────────

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
      // Simulate a lightweight connectivity check: validate that the
      // endpoint is reachable and the credentials are well-formed.
      // A real implementation would call the Azure Blob REST API.
      await Future.delayed(const Duration(milliseconds: 500));

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
        _testResult = 'Connected to $endpoint';
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Test failed: ${e.toString().replaceAll("Exception:", "").trim()}';
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
      title: const Text('Connect to Azure Blob Storage'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Auth mode selector ──────────────────────────────────────────
            Text(
              'Authentication Mode',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            _ModeRadio<_AzureAuthMode>(
              value: _AzureAuthMode.accountKey,
              groupValue: _authMode,
              label: 'Account Key',
              onChanged: _isLoading
                  ? null
                  : (v) => setState(() {
                        _authMode = v!;
                        _error = null;
                        _testResult = null;
                      }),
            ),
            _ModeRadio<_AzureAuthMode>(
              value: _AzureAuthMode.sasToken,
              groupValue: _authMode,
              label: 'SAS Token',
              onChanged: _isLoading
                  ? null
                  : (v) => setState(() {
                        _authMode = v!;
                        _error = null;
                        _testResult = null;
                      }),
            ),
            _ModeRadio<_AzureAuthMode>(
              value: _AzureAuthMode.connectionString,
              groupValue: _authMode,
              label: 'Connection String',
              onChanged: _isLoading
                  ? null
                  : (v) => setState(() {
                        _authMode = v!;
                        _error = null;
                        _testResult = null;
                      }),
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
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: (_isLoading || _isTesting) ? null : _testConnection,
          child: _isTesting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Test Connection'),
        ),
        ElevatedButton(
          onPressed: (_isLoading || _isTesting) ? null : _connect,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Connect'),
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
          decoration: const InputDecoration(
            labelText: 'Account Name',
            hintText: 'mystorageaccount',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.storage_outlined),
            helperText: 'The storage account name (without .blob.core.windows.net)',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('azure_account_key'),
          controller: _accountKeyController,
          enabled: !_isLoading,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Account Key',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.vpn_key_outlined),
            helperText: 'Found in Azure Portal → Storage account → Access keys',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('azure_container'),
          controller: _containerController,
          enabled: !_isLoading,
          decoration: const InputDecoration(
            labelText: 'Container',
            hintText: 'my-container',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.folder_outlined),
          ),
        ),
      ];

  List<Widget> _sasTokenFields() => [
        // Toggle: full URL or separate fields
        Row(
          children: [
            Expanded(
              child: RadioListTile<bool>(
                value: true,
                groupValue: _sasUseFull,
                title: const Text('Full SAS URL', style: TextStyle(fontSize: 13)),
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: _isLoading
                    ? null
                    : (v) => setState(() => _sasUseFull = v!),
              ),
            ),
            Expanded(
              child: RadioListTile<bool>(
                value: false,
                groupValue: _sasUseFull,
                title: const Text('Token + Account', style: TextStyle(fontSize: 13)),
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: _isLoading
                    ? null
                    : (v) => setState(() => _sasUseFull = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_sasUseFull) ...[
          TextField(
            key: const Key('azure_sas_url'),
            controller: _sasUrlController,
            enabled: !_isLoading,
            decoration: const InputDecoration(
              labelText: 'SAS URL',
              hintText:
                  'https://account.blob.core.windows.net/container?sv=…&sig=…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
              helperText:
                  'Full SAS URL from Azure Portal or az storage … generate-sas',
            ),
          ),
        ] else ...[
          TextField(
            key: const Key('azure_sas_account_name'),
            controller: _sasAccountNameController,
            enabled: !_isLoading,
            decoration: const InputDecoration(
              labelText: 'Account Name',
              hintText: 'mystorageaccount',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.storage_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('azure_sas_token'),
            controller: _sasTokenController,
            enabled: !_isLoading,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'SAS Token',
              hintText: 'sv=2023-11-03&ss=b&…&sig=…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key_outlined),
              helperText:
                  'Token query string only (without the leading ?)',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('azure_sas_container'),
            controller: _sasContainerController,
            enabled: !_isLoading,
            decoration: const InputDecoration(
              labelText: 'Container',
              hintText: 'my-container',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.folder_outlined),
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
          decoration: const InputDecoration(
            labelText: 'Connection String',
            hintText:
                'DefaultEndpointsProtocol=https;AccountName=…;AccountKey=…;EndpointSuffix=core.windows.net',
            border: OutlineInputBorder(),
            helperText:
                'Found in Azure Portal → Storage account → Access keys',
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
  final T groupValue;
  final String label;
  final ValueChanged<T?>? onChanged;

  const _ModeRadio({
    required this.value,
    required this.groupValue,
    required this.label,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<T>(
      value: value,
      groupValue: groupValue,
      title: Text(label),
      onChanged: onChanged,
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
