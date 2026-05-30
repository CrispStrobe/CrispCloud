// lib/widgets/proxy_settings_dialog.dart
//
// Dialog for configuring HTTP/SOCKS5 proxy settings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(config.isEnabled
              ? 'Proxy configured: ${config.type.name} ${config.host}:${config.port}'
              : 'Proxy disabled'),
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
