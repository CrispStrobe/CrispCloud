// lib/widgets/proxy_settings_dialog.dart
//
// Dialog for configuring HTTP/SOCKS5 proxy settings.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show certPinningProvider;
import '../providers/core_providers.dart';
import '../services/cert_pinning_service.dart';
import '../services/proxy_service.dart';

class ProxySettingsDialog extends ConsumerStatefulWidget {
  const ProxySettingsDialog({super.key});

  @override
  ConsumerState<ProxySettingsDialog> createState() => _ProxySettingsDialogState();
}

class _ProxySettingsDialogState extends ConsumerState<ProxySettingsDialog> {
  late ProxyType _type;
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _noProxyController = TextEditingController();
  bool _certPinningEnabled = false;
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
    _certPinningEnabled = ref.read(certPinningProvider).isEnabled;
    _minTlsVersion = ref.read(certPinningProvider).getMinTlsVersion();
    _customCaCerts = ref.read(certPinningProvider).getCustomCaCertInfos();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Proxy Settings'),
      scrollable: true,
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<ProxyType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Proxy Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: ProxyType.none, child: Text('No Proxy (Direct)')),
                DropdownMenuItem(value: ProxyType.http, child: Text('HTTP / HTTPS Proxy')),
                DropdownMenuItem(value: ProxyType.socks5, child: Text('SOCKS5 Proxy')),
              ],
              onChanged: (v) => setState(() => _type = v ?? ProxyType.none),
            ),
            if (_type != ProxyType.none) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _hostController,
                      decoration: InputDecoration(
                        labelText: 'Proxy Host',
                        hintText: _type == ProxyType.socks5 ? '127.0.0.1' : 'proxy.company.com',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _portController,
                      decoration: InputDecoration(
                        labelText: 'Port',
                        hintText: _type == ProxyType.socks5 ? '1080' : '8080',
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
                decoration: const InputDecoration(
                  labelText: 'Username (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _noProxyController,
                decoration: const InputDecoration(
                  labelText: 'No Proxy (bypass list)',
                  hintText: 'localhost, 127.0.0.1, .local',
                  border: OutlineInputBorder(),
                  helperText: 'Comma-separated hostnames to bypass proxy',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _type == ProxyType.none
                          ? 'Environment variables (HTTP_PROXY, HTTPS_PROXY) are auto-detected.'
                          : 'Manual settings override environment variables.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            CheckboxListTile(
              value: _certPinningEnabled,
              onChanged: (v) => setState(() => _certPinningEnabled = v ?? false),
              title: const Text('Certificate Pinning', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Verify TLS certificates for Google, Microsoft, Dropbox, Amazon',
                style: TextStyle(fontSize: 11),
              ),
              secondary: Icon(
                _certPinningEnabled ? Icons.verified_user : Icons.shield_outlined,
                color: _certPinningEnabled ? Theme.of(context).colorScheme.primary : null,
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),
            // --- Minimum TLS Version ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: DropdownButtonFormField<TlsVersion>(
                initialValue: _minTlsVersion,
                decoration: const InputDecoration(
                  labelText: 'Minimum TLS Version',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: TlsVersion.tls12, child: Text('TLS 1.2 (recommended)')),
                  DropdownMenuItem(value: TlsVersion.tls13, child: Text('TLS 1.3 (strict)')),
                  DropdownMenuItem(value: TlsVersion.any, child: Text('Any (legacy override)')),
                ],
                onChanged: (v) => setState(() => _minTlsVersion = v ?? TlsVersion.tls12),
              ),
            ),
            if (_minTlsVersion == TlsVersion.any)
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Allowing any TLS version may expose connections to downgrade attacks.',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            // --- Custom CA Certificates ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Custom CA Certificates',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (_customCaCerts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'No custom CA certificates imported.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
                  tooltip: 'Remove certificate',
                  onPressed: () async {
                    await ref.read(certPinningProvider).removeCustomCaCert(i);
                    setState(() {
                      _customCaCerts =
                          ref.read(certPinningProvider).getCustomCaCertInfos();
                    });
                  },
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Import Certificate', style: TextStyle(fontSize: 13)),
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
            child: const Text('Reset'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
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
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null || bytes.isEmpty) return;

    await ref.read(certPinningProvider).addCustomCaCert(Uint8List.fromList(bytes));
    if (mounted) {
      setState(() {
        _customCaCerts = ref.read(certPinningProvider).getCustomCaCertInfos();
      });
    }
  }

  Future<void> _save() async {
    final port = int.tryParse(_portController.text) ?? 0;
    if (_type != ProxyType.none && (_hostController.text.isEmpty || port <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Host and valid port are required')),
      );
      return;
    }

    final config = ProxyConfig(
      type: _type,
      host: _hostController.text.trim(),
      port: port,
      username: _usernameController.text.isNotEmpty ? _usernameController.text : null,
      password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
      noProxy: _noProxyController.text.trim(),
    );

    await ref.read(proxyServiceProvider).save(config);

    // Save cert pinning and TLS settings, then re-apply global overrides
    final pinning = ref.read(certPinningProvider);
    await pinning.setEnabled(_certPinningEnabled);
    await pinning.setMinTlsVersion(_minTlsVersion);
    ref.read(proxyServiceProvider).applyGlobally();

    if (mounted) {
      Navigator.pop(context, true);
      final parts = <String>[];
      if (config.isEnabled) parts.add('Proxy: ${config.type.name} ${config.host}:${config.port}');
      if (_certPinningEnabled) parts.add('Cert pinning: on');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(parts.isEmpty ? 'Proxy disabled' : parts.join(' | '))),
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
