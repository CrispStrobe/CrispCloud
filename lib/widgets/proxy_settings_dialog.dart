// lib/widgets/proxy_settings_dialog.dart
//
// Dialog for configuring HTTP and SOCKS proxy settings.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show certPinningProvider;
import '../providers/core_providers.dart';
import '../services/cert_pinning_service.dart';
import '../services/proxy_service.dart';
import '../l10n/app_localizations.dart';
import '../l10n/proxy_settings_strings.dart';

class ProxySettingsDialog extends ConsumerStatefulWidget {
  const ProxySettingsDialog({super.key});

  @override
  ConsumerState<ProxySettingsDialog> createState() =>
      _ProxySettingsDialogState();
}

class _ProxySettingsDialogState extends ConsumerState<ProxySettingsDialog> {
  late ProxyType _type;
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _noProxyController = TextEditingController();
  late TlsVersion _minTlsVersion;
  List<CustomCaCertInfo> _customCaCerts = [];

  @override
  void initState() {
    super.initState();
    final config = ref.read(proxyServiceProvider).config;
    _type = config.type;
    _hostController.text = config.host;
    _portController.text = config.port > 0 ? config.port.toString() : '';
    _usernameController.text = config.username ?? '';
    _passwordController.text = config.password ?? '';
    _noProxyController.text = config.noProxy;
    _minTlsVersion = ref.read(certPinningProvider).getMinTlsVersion();
    _customCaCerts = ref.read(certPinningProvider).getCustomCaCertInfos();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ProxySettingsStrings(context);
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.proxySettings),
      scrollable: true,
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ref.read(proxyServiceProvider).config.isInvalid) ...[
              Text(
                strings.text(
                  'Saved proxy settings are invalid. Correct them or choose No Proxy to reconnect.',
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<ProxyType>(
              isExpanded: true,
              initialValue: _type,
              decoration: InputDecoration(
                labelText: strings.text('Proxy Type'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: ProxyType.none,
                  child: Text(strings.text('No Proxy (Direct)')),
                ),
                DropdownMenuItem(
                  value: ProxyType.http,
                  child: Text(strings.text('HTTP / HTTPS Proxy')),
                ),
                DropdownMenuItem(
                  value: ProxyType.socks5,
                  child: Text(strings.text('SOCKS5 Proxy')),
                ),
                DropdownMenuItem(
                  value: ProxyType.socks4,
                  child: Text(strings.text('SOCKS4 Proxy (local DNS)')),
                ),
                DropdownMenuItem(
                  value: ProxyType.socks4a,
                  child: Text(strings.text('SOCKS4a Proxy (remote DNS)')),
                ),
              ],
              onChanged: (value) => setState(() {
                _type = value ?? ProxyType.none;
                if (_type.isSocks4) _passwordController.clear();
              }),
            ),
            if (_type != ProxyType.none) ...[
              const SizedBox(height: 8),
              Text(
                strings.text(
                  'Applies to native HTTP/HTTPS connections. FTP, SFTP, SMB and browser connections use their own network settings.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_type == ProxyType.socks5) ...[
                const SizedBox(height: 8),
                Text(
                  strings.text(
                    'SOCKS5 resolves destination names at the proxy. For password authentication, enter both a username and password.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_type.isSocks4) ...[
                const SizedBox(height: 8),
                Text(
                  strings.text(
                    _type == ProxyType.socks4
                        ? 'SOCKS4 resolves destination names locally to IPv4. The optional user ID is not a password.'
                        : 'SOCKS4a resolves destination names at the proxy. IPv6 destinations and password authentication are not supported.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _hostController,
                      decoration: InputDecoration(
                        labelText: strings.text('Proxy Host'),
                        hintText: _type.isSocks
                            ? '127.0.0.1'
                            : 'proxy.company.com',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _portController,
                      decoration: InputDecoration(
                        labelText: strings.text('Port'),
                        hintText: _type.isSocks ? '1080' : '8080',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: strings.text(
                    _type.isSocks4
                        ? 'User ID (optional)'
                        : 'Username (optional)',
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              if (!_type.isSocks4) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: strings.text('Password (optional)'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _noProxyController,
                decoration: InputDecoration(
                  labelText: strings.text('No Proxy (bypass list)'),
                  hintText: 'localhost, 127.0.0.1, .local',
                  border: const OutlineInputBorder(),
                  helperText: strings.text(
                    'Comma-separated hostnames to bypass proxy',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _type == ProxyType.none
                          ? strings.text(
                              'Environment variables (HTTP_PROXY, HTTPS_PROXY) are auto-detected.',
                            )
                          : strings.text(
                              'Manual settings override environment variables.',
                            ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            CheckboxListTile(
              value: false,
              onChanged: null,
              title: Text(
                strings.text('Certificate Pinning'),
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                strings.text(
                  'Unavailable. TLS certificates are still verified.',
                ),
                style: const TextStyle(fontSize: 11),
              ),
              secondary: const Icon(Icons.shield_outlined),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),
            // --- Minimum TLS Version ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: DropdownButtonFormField<TlsVersion>(
                isExpanded: true,
                initialValue: _minTlsVersion,
                decoration: InputDecoration(
                  labelText: strings.text('Minimum TLS Version'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: TlsVersion.tls12,
                    child: Text(strings.text('TLS 1.2 (recommended)')),
                  ),
                  DropdownMenuItem(
                    value: TlsVersion.tls13,
                    child: Text(strings.text('TLS 1.3 (strict)')),
                  ),
                  DropdownMenuItem(
                    value: TlsVersion.any,
                    child: Text(strings.text('System default (TLS 1.2+)')),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _minTlsVersion = v ?? TlsVersion.tls12),
              ),
            ),
            Text(
              strings.text('TLS settings apply to new connections.'),
              style: const TextStyle(fontSize: 11),
            ),
            const Divider(),
            // --- Custom CA Certificates ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                strings.text('Custom CA Certificates'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (_customCaCerts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  strings.text('No custom CA certificates imported.'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            for (var i = 0; i < _customCaCerts.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.security, size: 18),
                title: Text(
                  _customCaCerts[i].subjectDn,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: strings.text('Remove certificate'),
                  onPressed: () async {
                    final proxy = ref.read(proxyServiceProvider);
                    await ref.read(certPinningProvider).removeCustomCaCert(i);
                    proxy.applyGlobally();
                    if (!mounted) return;
                    setState(() {
                      _customCaCerts = ref
                          .read(certPinningProvider)
                          .getCustomCaCertInfos();
                    });
                  },
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  strings.text('Import Certificate'),
                  style: const TextStyle(fontSize: 13),
                ),
                onPressed: _importCaCert,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_type != ProxyType.none)
          TextButton(
            onPressed: () async {
              await ref.read(proxyServiceProvider).clear();
              if (!context.mounted) return;
              Navigator.pop(context, true);
            },
            child: Text(strings.text('Clear')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(AppLocalizations.of(context)!.save),
        ),
      ],
    );
  }

  Future<void> _importCaCert() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pem', 'crt', 'cer'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final proxy = ref.read(proxyServiceProvider);
    try {
      await ref
          .read(certPinningProvider)
          .addCustomCaCert(Uint8List.fromList(bytes));
      proxy.applyGlobally();
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ProxySettingsStrings(context)
                .text('Import a valid PEM or DER certificate.'),
          ),
        ),
      );
      return;
    }
    if (mounted) {
      setState(() {
        _customCaCerts = ref.read(certPinningProvider).getCustomCaCertInfos();
      });
    }
  }

  Future<void> _save() async {
    final strings = ProxySettingsStrings(context);
    final port = int.tryParse(_portController.text) ?? 0;
    if (_type != ProxyType.none &&
        (!ProxyConfig.isValidHost(_hostController.text.trim()) ||
            port <= 0 ||
            port > 65535)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.text('Host and valid port are required')),
        ),
      );
      return;
    }

    final config = ProxyConfig(
      type: _type,
      host: _hostController.text.trim(),
      port: port,
      username: _usernameController.text.isNotEmpty
          ? _usernameController.text
          : null,
      password: !_type.isSocks4 && _passwordController.text.isNotEmpty
          ? _passwordController.text
          : null,
      noProxy: _noProxyController.text.trim(),
    );

    try {
      config.validate();
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.text(
              _type.isSocks4
                  ? 'SOCKS4 user IDs accept up to 255 printable ASCII characters; passwords are not supported.'
                  : 'SOCKS5 needs both a username and password (up to 255 UTF-8 bytes each).',
            ),
          ),
        ),
      );
      return;
    }
    await ref.read(proxyServiceProvider).save(config);

    // Clear the unsupported legacy pinning preference and apply TLS settings.
    final pinning = ref.read(certPinningProvider);
    await pinning.setEnabled(false);
    await pinning.setMinTlsVersion(_minTlsVersion);
    ref.read(proxyServiceProvider).applyGlobally();

    if (mounted) {
      Navigator.pop(context, true);
      final parts = <String>[];
      if (config.isEnabled) {
        parts.add(strings.proxy(config.type.name, config.host, config.port));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            parts.isEmpty ? strings.text('Proxy disabled') : parts.join(' | '),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _noProxyController.dispose();
    super.dispose();
  }
}
