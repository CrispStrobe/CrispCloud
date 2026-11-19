import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../providers/core_providers.dart';
import '../providers/panel_provider.dart';
import '../models/file_item.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/metadata_sidecar_service.dart';
import '../l10n/commander_strings.dart';

class StorageToolsSettings extends ConsumerWidget {
  const StorageToolsSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      ListTile(
        leading: const Icon(Icons.terminal),
        title: Text(context.commanderTr('Command-line tools')),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => const _CliDialog(),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.restore),
        title: Text(context.commanderTr('Restore metadata from sidecar')),
        onTap: () {
          try {
            final origin = ref
                .read(panelProvider(ref.read(activePanelProvider)))
                .captureCurrentOrigin();
            final backend = fileOperationBackend(
              source: origin.source,
              local: ref.read(localFileServiceProvider),
              isCurrent: () => origin.isCurrent,
            );
            showDialog<void>(
              context: context,
              builder: (_) => _MetadataDialog(
                backend: backend,
                directory: origin.source.currentPath,
              ),
            );
          } catch (error) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$error')));
          }
        },
      ),
    ],
  );
}

class _CliDialog extends StatelessWidget {
  const _CliDialog();
  @override
  Widget build(BuildContext context) {
    final installer = !kIsWeb && Platform.isMacOS
        ? p.join(
            p.dirname(Platform.resolvedExecutable),
            '..',
            'Resources',
            'CrispCloudCLI',
            'install.sh',
          )
        : null;
    final command = installer != null && File(installer).existsSync()
        ? "sh '${installer.replaceAll("'", "'\\''")}'"
        : 'sh install.sh';
    return AlertDialog(
      title: Text(context.commanderTr('Command-line tools')),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.commanderTr(
                'Download and extract the complete CLI bundle for your system, then run its installer in Terminal.',
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(command),
            const SizedBox(height: 12),
            Text(
              context.commanderTr(
                'crispcloud is the main command; crisp is a compatibility alias. Both use the same CLI configuration, separate from app accounts.',
              ),
            ),
            const SizedBox(height: 12),
            const SelectableText('~/.local/bin/crispcloud --help'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse('https://github.com/CrispStrobe/CrispCloud/releases'),
          ),
          child: Text(context.commanderTr('Downloads')),
        ),
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: command)),
          child: Text(context.commanderTr('Copy command')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.commanderTr('Close')),
        ),
      ],
    );
  }
}

class _MetadataDialog extends StatefulWidget {
  const _MetadataDialog({required this.backend, required this.directory});
  final FileOperationBackend backend;
  final String directory;
  @override
  State<_MetadataDialog> createState() => _MetadataDialogState();
}

class _MetadataDialogState extends State<_MetadataDialog> {
  List<FileItem> files = [];
  FileItem? selected;
  Map<String, dynamic>? record;
  String? status;
  bool busy = true,
      permissions = false,
      ownership = false,
      xattrs = false,
      acl = false,
      windows = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final list = await widget.backend.list(widget.directory);
      if (mounted) {
        setState(() {
          files = list
              .where(
                (f) =>
                    MetadataSidecarService.isSidecarName(f.name) && !f.isFolder,
              )
              .toList();
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          status = '$e';
          busy = false;
        });
      }
    }
  }

  Future<void> choose(FileItem file) async {
    setState(() {
      selected = file;
      record = null;
      busy = true;
      status = null;
    });
    try {
      final value = await MetadataSidecarService.read(widget.backend, file);
      if (mounted) {
        setState(() {
          record = value;
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          status = '$e';
          busy = false;
        });
      }
    }
  }

  Future<void> restore() async {
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await MetadataSidecarService.restore(
        widget.backend,
        selected!,
        permissions: permissions,
        ownership: ownership,
        extendedAttributes: xattrs,
        acl: acl,
        windowsAttributes: windows,
      );
      if (mounted) {
        setState(() {
          status = context.commanderTr('Metadata restored.');
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          status = '$e';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final caps = widget.backend.capabilities;
    Widget toggle(
      String label,
      bool value,
      bool supported,
      ValueChanged<bool> change,
    ) => CheckboxListTile(
      dense: true,
      title: Text(context.commanderTr(label)),
      value: value,
      onChanged: busy || !supported ? null : (v) => setState(() => change(v!)),
    );
    return AlertDialog(
      title: Text(context.commanderTr('Restore metadata from sidecar')),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(widget.directory),
            Text(
              context.commanderTr(
                'Choose one record. File contents must match before metadata is restored.',
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (!busy && files.isEmpty)
              Text(context.commanderTr('No metadata sidecars in this folder.')),
            for (final file in files)
              ListTile(
                dense: true,
                title: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: selected == file,
                leading: Icon(
                  selected == file
                      ? Icons.check_circle
                      : Icons.description_outlined,
                ),
                onTap: busy ? null : () => choose(file),
              ),
            if (record != null) ...[
              SelectableText(
                '${record!['name']}\n${(record!['metadata'] as Map).entries.where((e) => e.key != 'xattrs' && e.key != 'acl').map((e) => '${e.key}: ${e.value}').join('\n')}',
              ),
              Text(
                context.commanderTr(
                  'Timestamps are restored by default. Additional fields are optional.',
                ),
              ),
              toggle(
                'Permissions',
                permissions,
                caps.permissions,
                (v) => permissions = v,
              ),
              toggle(
                'Owner/group',
                ownership,
                caps.ownership,
                (v) => ownership = v,
              ),
              toggle(
                'Extended attributes',
                xattrs,
                caps.extendedAttributes,
                (v) => xattrs = v,
              ),
              toggle(
                'Access control list',
                acl,
                caps.accessControlLists,
                (v) => acl = v,
              ),
              toggle(
                'Windows attributes',
                windows,
                caps.windowsAttributes,
                (v) => windows = v,
              ),
            ],
            if (status != null) SelectableText(status!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy || record == null ? null : restore,
          child: Text(context.commanderTr('Restore')),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(context.commanderTr('Close')),
        ),
      ],
    );
  }
}
