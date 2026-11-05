// lib/widgets/hetzner_connection_dialog.dart
//
// Connection dialog for Hetzner Storage Box.
//
// Fields:
//   • Username  — uNNNNNN format (e.g. u123456)
//   • Password
//   • Protocol  — SFTP (default) / WebDAV radio selector
//   • Sub-account — optional (e.g. "sub1" → effective login "u123456-sub1")
//
// Buttons: Cancel | Test Connection | Connect

import 'package:flutter/material.dart';

import '../l10n/provider_operation_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import '../services/hetzner_adapter.dart';
import '../services/hetzner_config_service.dart';
import '../l10n/app_localizations.dart';
import '../l10n/hetzner_setup_strings.dart';
import '../l10n/cloud_setup_strings.dart';
import '../l10n/connection_dialog_extra_strings.dart';

class HetznerConnectionDialog extends ConsumerStatefulWidget {
  const HetznerConnectionDialog({super.key});

  @override
  ConsumerState<HetznerConnectionDialog> createState() =>
      _HetznerConnectionDialogState();
}

class _HetznerConnectionDialogState
    extends ConsumerState<HetznerConnectionDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _subAccountController = TextEditingController();

  HetznerProtocol _protocol = HetznerProtocol.sftp;

  bool _isLoading = false;
  bool _isTesting = false;
  bool _obscurePassword = true;

  String? _error;
  String? _testResult;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _subAccountController.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final svc = HetznerConfigService(
      secureStorage: ref.read(secureStorageProvider),
    );
    final creds = await svc.readCredentials();
    if (creds == null || !mounted) return;

    setState(() {
      _usernameController.text = creds['username'] ?? '';
      _subAccountController.text = creds['subAccount'] ?? '';
      _protocol = HetznerConfigService.parseProtocol(creds['protocol']);
      // Password is intentionally not pre-filled.
    });
  }

  String _text(String key, [Map<String, Object> values = const {}]) =>
      HetznerSetupStrings(context).text(key, values);

  // ── Validation ────────────────────────────────────────────────────────────

  String? _validate() {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return _text('usernameRequired');

    // Soft format hint — Hetzner usernames start with 'u' followed by digits.
    if (!RegExp(r'^u\d+$').hasMatch(username)) {
      return _text('usernameFormat');
    }

    if (_passwordController.text.isEmpty) return _text('passwordRequired');

    return null;
  }

  // ── Derived display values ────────────────────────────────────────────────

  String get _previewHostname {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return 'uNNNNNN.your-storagebox.de';
    return hetznerHostname(username);
  }

  String get _previewPort => _protocol == HetznerProtocol.sftp
      ? '$kHetznerSftpPort'
      : '$kHetznerWebDavPort';

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
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      final subAccount = _subAccountController.text.trim();

      final hosts =
          HetznerConfigService(secureStorage: ref.read(secureStorageProvider))
              .knownHosts;
      final adapter = HetznerStorageBoxAdapter.withMemoryStorage(
          knownHosts: hosts,
          confirmHostKey: (endpoint, fingerprint) async {
            if (!mounted) return false;
            return await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => AlertDialog(
                            title: Text(ConnectionDialogExtraStrings(context).text('verifySsh')),
                            content: SelectableText(
                                ConnectionDialogExtraStrings(context).text('sshFingerprint', {'endpoint': endpoint, 'fingerprint': fingerprint})),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(AppLocalizations.of(context)!.cancel)),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(ConnectionDialogExtraStrings(context).text('trust')))
                            ])) ??
                false;
          });
      await adapter.login(
        username,
        password,
        protocol: _protocol,
        subAccount: subAccount.isNotEmpty ? subAccount : null,
      );

      final latency = await adapter.healthCheck();
      await adapter.logout();

      if (!mounted) return;
      setState(() {
        _testResult = latency >= 0
            ? _text('success', {'latency': latency})
            : _text('healthTimeout');
        _isTesting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            CloudSetupStrings(context).text('testFailed', {'error': localizedProviderError(context, e).replaceAll('Exception:', '').trim()});
        _isTesting = false;
      });
    }
  }

  // ── Connect ───────────────────────────────────────────────────────────────

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
      final svc = HetznerConfigService(
        secureStorage: ref.read(secureStorageProvider),
      );
      final subAccount = _subAccountController.text.trim();
      await svc.saveCredentials(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        protocol: _protocol,
        subAccount: subAccount.isNotEmpty ? subAccount : null,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = localizedProviderError(context, e).replaceAll('Exception:', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading || _isTesting;

    return AlertDialog(
      title: Text(_text('connectTitle')),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info banner ─────────────────────────────────────────────────
            _InfoBanner(
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 12),
                  children: [
                    const TextSpan(
                      text: 'Hetzner Storage Box — ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: _text('info'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Username ────────────────────────────────────────────────────
            TextField(
              key: const Key('hetzner_username'),
              controller: _usernameController,
              enabled: !busy,
              onChanged: (_) => setState(() {}), // refresh preview
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.username,
                hintText: 'u123456',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person_outline),
                helperText: _text('usernameHelp'),
              ),
            ),
            const SizedBox(height: 16),

            // ── Password ────────────────────────────────────────────────────
            TextField(
              key: const Key('hetzner_password'),
              controller: _passwordController,
              enabled: !busy,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.password,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Protocol selector ───────────────────────────────────────────
            Text(
              _text('protocol'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            RadioGroup<HetznerProtocol>(
              groupValue: _protocol,
              onChanged: (v) {
                if (busy || v == null) return;
                setState(() => _protocol = v);
              },
              child: Row(
                children: [
                  Expanded(
                    child: RadioListTile<HetznerProtocol>(
                      key: const Key('hetzner_proto_sftp'),
                      title: Text(_text('sftp')),
                      value: HetznerProtocol.sftp,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<HetznerProtocol>(
                      key: const Key('hetzner_proto_webdav'),
                      title: const Text('WebDAV  (HTTPS)'),
                      value: HetznerProtocol.webdav,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Connection preview ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.dns_outlined, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$_previewHostname : $_previewPort',
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Sub-account (optional) ──────────────────────────────────────
            TextField(
              key: const Key('hetzner_subaccount'),
              controller: _subAccountController,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: _text('subAccount'),
                hintText: 'sub1',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.manage_accounts_outlined),
                helperText: _text('subHelp'),
              ),
            ),

            // ── Error / test result ─────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 14),
              _StatusBanner(message: _error!, isError: true),
            ],
            if (_testResult != null && _error == null) ...[
              const SizedBox(height: 14),
              _StatusBanner(message: _testResult!, isError: false),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        TextButton(
          onPressed: busy ? null : _testConnection,
          child: _isTesting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(CloudSetupStrings(context).text('test')),
        ),
        ElevatedButton(
          onPressed: busy ? null : _connect,
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
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _InfoBanner extends StatelessWidget {
  final Widget child;
  const _InfoBanner({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
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
