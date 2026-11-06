// lib/widgets/provider_settings_dialog.dart
//
// Dialog for provider-specific settings: custom headers, region overrides,
// endpoint URL, and other per-provider configuration.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/providers.dart';
import '../l10n/app_localizations.dart';
import '../l10n/provider_settings_strings.dart';

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
    final strings = ProviderSettingsStrings(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings, size: 20),
          const SizedBox(width: 8),
          Text(strings.text('settings', {'provider': auth.providerName})),
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
              decoration: InputDecoration(
                labelText: strings.text('timeout'),
                border: const OutlineInputBorder(),
                helperText: strings.text('default'),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _customHeadersController,
              decoration: InputDecoration(
                labelText: strings.text('headers'),
                border: const OutlineInputBorder(),
                helperText: strings.text('headerHelp'),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(strings.text('redirects')),
              value: _followRedirects,
              onChanged: (v) => setState(() => _followRedirects = v),
              dense: true,
            ),
            SwitchListTile(
              title: Text(strings.text('verify')),
              subtitle: Text(strings.text('verifyHelp')),
              value: _verifySSL,
              onChanged: (v) => setState(() => _verifySSL = v),
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(onPressed: _saveSettings, child: Text(AppLocalizations.of(context)!.save)),
      ],
    );
  }
}
