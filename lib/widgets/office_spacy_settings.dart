import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/settings_strings.dart';
import '../services/office_spacy_preferences.dart';

class OfficeSpacySettings extends StatefulWidget {
  const OfficeSpacySettings({super.key});
  @override
  State<OfficeSpacySettings> createState() => _OfficeSpacySettingsState();
}

class _OfficeSpacySettingsState extends State<OfficeSpacySettings> {
  ({bool enabled, String bundle, String library})? _config;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final value = await OfficeSpacyPreferences.read();
    if (mounted) setState(() => _config = value);
  }

  Future<void> _save({bool? enabled, String? bundle, String? library}) async {
    final config = _config;
    if (config == null) return;
    setState(() => _saving = true);
    try {
      await OfficeSpacyPreferences.write(
        enabled: enabled ?? false,
        bundle: bundle ?? config.bundle,
        library: library ?? config.library,
      );
      await _read();
    } on Object catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsStrings(context);
    final config = _config;
    final supported = !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const ValueKey('settings-spacy-manual'),
          title: Text(s.text('Optional German grammar')),
          subtitle: Text(
            s.text(
              'Manual checks only. Requires a verified Linux x86-64/AVX2 installation. Off by default.',
            ),
          ),
          value: config?.enabled ?? false,
          onChanged: _saving || config == null
              ? null
              : (enabled) {
                  if (!enabled ||
                      (supported &&
                          config.bundle.isNotEmpty &&
                          config.library.isNotEmpty)) {
                    _save(enabled: enabled);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          s.text(
                            'Choose the verified native library and model bundle on a supported Linux installation first.',
                          ),
                        ),
                      ),
                    );
                  }
                },
        ),
        if (supported) ...[
          ListTile(
            title: Text(s.text('Model bundle folder')),
            subtitle: config?.bundle.isNotEmpty == true
                ? Text(config!.bundle)
                : null,
            trailing: const Icon(Icons.folder_open),
            onTap: _saving
                ? null
                : () async {
                    final folder = await FilePicker.platform.getDirectoryPath();
                    if (folder != null && mounted) await _save(bundle: folder);
                  },
          ),
          ListTile(
            title: Text(s.text('Verified native library')),
            subtitle: config?.library.isNotEmpty == true
                ? Text(config!.library)
                : null,
            trailing: const Icon(Icons.file_open),
            onTap: _saving
                ? null
                : () async {
                    final choice = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['so'],
                    );
                    final file = choice?.files.single.path;
                    if (file != null && mounted) await _save(library: file);
                  },
          ),
        ],
      ],
    );
  }
}
