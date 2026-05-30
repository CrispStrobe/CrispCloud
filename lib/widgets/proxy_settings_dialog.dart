// lib/widgets/proxy_settings_dialog.dart
//
// Dialog for configuring HTTP/SOCKS5 proxy settings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart' show certPinningProvider;
import '../providers/core_providers.dart';
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
              value: _type,
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
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
          ],
        ),
      ),
      actions: [
        if (_type != ProxyType.none)
          TextButton(
            onPressed: () async {
              await ref.read(proxyServiceProvider).clear();
              if (mounted) Navigator.pop(context, true);
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

    // Save cert pinning setting and re-apply global overrides
    final pinning = ref.read(certPinningProvider);
    await pinning.setEnabled(_certPinningEnabled);
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
