import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart'
    show OfficeFontPack, OfficeFontPackStatus;
import 'package:url_launcher/url_launcher.dart';

import '../l10n/settings_strings.dart';
import '../services/office_font_packs.dart';

/// Settings entry for the app-owned open font packs.
class OfficeFontDownloadsSettings extends StatelessWidget {
  const OfficeFontDownloadsSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsStrings(context);
    return ListTile(
      key: const ValueKey('settings-office-fonts'),
      leading: const Icon(Icons.font_download_outlined),
      title: Text(s.text('Office font downloads')),
      subtitle: Text(
        s.text(
          'Optional open fonts for Calibri, Arial, Times New Roman and other families when Microsoft Office fonts are not installed.',
        ),
      ),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const OfficeFontDownloadsDialog(),
      ),
    );
  }
}

class OfficeFontDownloadsDialog extends StatefulWidget {
  const OfficeFontDownloadsDialog({super.key});

  @override
  State<OfficeFontDownloadsDialog> createState() =>
      _OfficeFontDownloadsDialogState();
}

class _OfficeFontDownloadsDialogState extends State<OfficeFontDownloadsDialog> {
  List<OfficeFontPackStatus> _statuses = const <OfficeFontPackStatus>[];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final statuses = await OfficeFontPacks.statuses();
      if (mounted) setState(() => _statuses = statuses);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  String _size(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  Future<void> _install(OfficeFontPack pack) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await OfficeFontPacks.install(pack);
      await _refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(OfficeFontPack pack) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await OfficeFontPacks.remove(pack);
      await _refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(OfficeFontPackStatus status) async {
    final pack = status.pack;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(pack.title),
        scrollable: true,
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(pack.description),
              const SizedBox(height: 12),
              Text('Source: ${pack.source}'),
              Text('Licence: ${pack.licence}'),
              Text('Download size: ${_size(pack.bytes)}'),
              const SizedBox(height: 8),
              const Text(
                'Downloads start only when you choose Install. Every file is verified by SHA-256 before it is registered. Microsoft fonts are never downloaded.',
              ),
              const SizedBox(height: 12),
              Text('Files', style: Theme.of(context).textTheme.titleSmall),
              for (final file in pack.files)
                Text(
                  '${file.family}${file.italic ? ' Italic' : ''} · '
                  '${file.fileName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(pack.licenceUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Open licence'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await _install(pack);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
            child: Text(status.installed ? 'Repair' : 'Install'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Office font downloads'),
      scrollable: true,
      content: SizedBox(
        width: 680,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Optional open font packs are stored in the application-support folder. Exact fonts installed by Microsoft Office are preferred and are never redistributed.',
            ),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            for (final status in _statuses)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        status.pack.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        status.problem != null
                            ? 'Needs repair'
                            : status.installed
                            ? 'Installed'
                            : 'Not installed',
                      ),
                      Text(
                        '${status.pack.description} · '
                        '${_size(status.pack.bytes)} · '
                        '${status.pack.licence}',
                      ),
                      if (status.problem != null)
                        Text(
                          status.problem!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        children: <Widget>[
                          TextButton(
                            onPressed: _busy ? null : () => _review(status),
                            child: const Text('Review / install'),
                          ),
                          if (status.installed || status.problem != null)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _remove(status.pack),
                              child: const Text('Remove downloaded data'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
