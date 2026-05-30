// lib/widgets/provider_settings_dialog.dart
//
// Dialog for provider-specific settings: custom headers, region overrides,
// endpoint URL, and other per-provider configuration.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/providers.dart';

void showProviderSettingsDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (_) => const _ProviderSettingsDialog(),
  );
}

class _ProviderSettingsDialog extends ConsumerStatefulWidget {
  const _ProviderSettingsDialog();

  @override
  ConsumerState<_ProviderSettingsDialog> createState() => _ProviderSettingsDialogState();
}

class _ProviderSettingsDialogState extends ConsumerState<_ProviderSettingsDialog> {
  final _customHeadersController = TextEditingController();
  final _timeoutController = TextEditingController();
  bool _followRedirects = true;
  bool _verifySSL = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final auth = ref.read(authProvider);
    final prefix = 'provider_${auth.providerName}';

    setState(() {
      _customHeadersController.text = prefs.getString('${prefix}_headers') ?? '';
      _timeoutController.text = (prefs.getInt('${prefix}_timeout') ?? 30).toString();
      _followRedirects = prefs.getBool('${prefix}_follow_redirects') ?? true;
      _verifySSL = prefs.getBool('${prefix}_verify_ssl') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final auth = ref.read(authProvider);
    final prefix = 'provider_${auth.providerName}';

    await prefs.setString('${prefix}_headers', _customHeadersController.text);
    await prefs.setInt('${prefix}_timeout', int.tryParse(_timeoutController.text) ?? 30);
    await prefs.setBool('${prefix}_follow_redirects', _followRedirects);
    await prefs.setBool('${prefix}_verify_ssl', _verifySSL);

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _customHeadersController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings, size: 20),
          const SizedBox(width: 8),
          Text('${auth.providerName} Settings'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _timeoutController,
              decoration: const InputDecoration(
                labelText: 'Request Timeout (seconds)',
                border: OutlineInputBorder(),
                helperText: 'Default: 30 seconds',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _customHeadersController,
              decoration: const InputDecoration(
                labelText: 'Custom Headers',
                border: OutlineInputBorder(),
                helperText: 'One per line: Header-Name: value',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Follow Redirects'),
              value: _followRedirects,
              onChanged: (v) => setState(() => _followRedirects = v),
              dense: true,
            ),
            SwitchListTile(
              title: const Text('Verify SSL Certificates'),
              subtitle: const Text('Disable only for self-signed certs'),
              value: _verifySSL,
              onChanged: (v) => setState(() => _verifySSL = v),
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _saveSettings, child: const Text('Save')),
      ],
    );
  }
}
