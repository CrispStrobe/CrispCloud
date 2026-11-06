import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/file_attributes_service.dart';
import '../services/file_operation_backend.dart';
import '../services/storage_transfer_contract.dart';
import 'commander_review_dialog.dart';
import 'file_origin_actions.dart';

Future<void> showFileAttributesFromSelection(
  BuildContext context,
  WidgetRef ref,
) {
  final side = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(side));
  final files = panel.selection.isNotEmpty
      ? panel.selection.toList()
      : [if (panel.cursorItem != null) panel.cursorItem!];
  return showFileAttributesDialog(context, ref, side, files);
}

Future<void> showFileAttributesDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files, {
  PanelFileOrigin? sourceOrigin,
}) async {
  try {
    if (files.isEmpty) throw StateError('Select files or folders first.');
    final prepared = sourceOrigin == null
        ? await ref.read(panelProvider(side)).prepareOperationFiles(files)
        : files;
    if (!context.mounted) return;
    final local = ref.read(localFileServiceProvider);
    final targets = [
      for (final file in prepared)
        () {
          final origin = captureFileActionOrigin(
            ref,
            file,
            sourceOrigin: sourceOrigin,
          );
          return FileAttributesTarget(
            fileOperationBackend(
              source: origin.source,
              local: local,
              isCurrent: () => origin.isCurrent,
            ),
            file,
          );
        }(),
    ];
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FileAttributesDialog(targets: targets),
    );
    if (context.mounted) {
      await ref.read(panelProvider(side)).refresh();
      ref.read(panelProvider(side)).focusList();
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class FileAttributesDialog extends StatefulWidget {
  const FileAttributesDialog({super.key, required this.targets});
  final List<FileAttributesTarget> targets;
  @override
  State<FileAttributesDialog> createState() => _FileAttributesDialogState();
}

class _FileAttributesDialogState extends State<FileAttributesDialog> {
  final _mode = TextEditingController();
  final _owner = TextEditingController();
  final _group = TextEditingController();
  final _modified = TextEditingController();
  final _accessed = TextEditingController();
  final _created = TextEditingController();
  final _windowsFlags = <int, bool?>{1: null, 2: null, 4: null, 0x20: null};
  bool _recursive = false;
  bool _files = true;
  bool _folders = true;
  bool _utc = false;
  bool _stopOnError = true;
  bool _busy = false;
  bool _cancelled = false;
  String? _error;
  FileAttributesPlan? _plan;
  static const _service = FileAttributesService();

  @override
  void dispose() {
    _cancelled = true;
    for (final controller in [
      _mode,
      _owner,
      _group,
      _modified,
      _accessed,
      _created,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _edit(VoidCallback change) => setState(() {
    change();
    _plan = null;
    _error = null;
  });

  FileAttributesPatch _patch() {
    final mode = _mode.text.trim();
    if (mode.isNotEmpty && !RegExp(r'^[0-7]{3,4}$').hasMatch(mode)) {
      throw FormatException(
        context.commanderTr("Permissions must be 3 or 4 octal digits."),
      );
    }
    var windowsMask = 0;
    var windowsValue = 0;
    for (final flag in _windowsFlags.entries) {
      if (flag.value != null) windowsMask |= flag.key;
      if (flag.value == true) windowsValue |= flag.key;
    }
    return FileAttributesPatch(
      mode: mode.isEmpty ? null : int.parse(mode, radix: 8),
      owner: _owner.text.trim().isEmpty ? null : _owner.text.trim(),
      group: _group.text.trim().isEmpty ? null : _group.text.trim(),
      modified: parseFileAttributeTime(_modified.text, utc: _utc),
      accessed: parseFileAttributeTime(_accessed.text, utc: _utc),
      created: parseFileAttributeTime(_created.text, utc: _utc),
      windowsAttributes: windowsMask == 0 ? null : windowsValue,
      windowsAttributesMask: windowsMask,
    );
  }

  Future<void> _preview() async {
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _plan = null;
    });
    try {
      final result = await _service.preview(
        targets: widget.targets,
        patch: _patch(),
        recursive: _recursive,
        includeFiles: _files,
        includeFolders: _folders,
        isCancelled: () => _cancelled || !mounted,
      );
      if (mounted) setState(() => _plan = result);
    } on FileAttributesCancelled {
      if (mounted) {
        setState(() => _error = context.commanderTr("Preview cancelled."));
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final plan = _plan;
    if (plan == null || plan.started) return;
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
    });
    try {
      await _service.apply(
        plan,
        stopOnError: _stopOnError,
        isCancelled: () => _cancelled || !mounted,
        onChanged: () {
          if (mounted) setState(() {});
        },
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String key,
    String label, {
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      key: ValueKey(key),
      controller: controller,
      enabled: !_busy,
      onChanged: (_) => _edit(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );

  String _describe(TransferMetadata metadata) {
    final result = <String>[];
    if (metadata.mode != null) {
      result.add(
        context.commanderTr("Permissions: {0}", [
          (metadata.mode! & 0xfff).toRadixString(8).padLeft(4, '0'),
        ]),
      );
    }
    if (metadata.owner != null) {
      result.add(context.commanderTr("Owner: {0}", [metadata.owner]));
    }
    if (metadata.group != null) {
      result.add(context.commanderTr("Group: {0}", [metadata.group]));
    }
    String time(DateTime value) =>
        (_utc ? value.toUtc() : value.toLocal()).toIso8601String();
    if (metadata.modified != null) {
      result.add(
        context.commanderTr("Modified: {0}", [time(metadata.modified!)]),
      );
    }
    if (metadata.accessed != null) {
      result.add(
        context.commanderTr("Accessed: {0}", [time(metadata.accessed!)]),
      );
    }
    if (metadata.created != null) {
      result.add(
        context.commanderTr("Created: {0}", [time(metadata.created!)]),
      );
    }
    if (metadata.windowsAttributes != null) {
      final flags = <String>[];
      for (final flag in _windowsFlags.keys) {
        if ((metadata.windowsAttributesMask & flag) == 0) continue;
        final state = (metadata.windowsAttributes! & flag) != 0 ? '+' : '−';
        flags.add('$state${_flagLabel(flag)}');
      }
      result.add(
        context.commanderTr("Windows attributes: {0}", [flags.join(', ')]),
      );
    }
    return result.join(' · ');
  }

  String _flagLabel(int flag) => context.commanderTr(switch (flag) {
    1 => 'Read-only',
    2 => 'Hidden',
    4 => 'System',
    _ => 'Archive attribute',
  });

  String _status(FileAttributesOutcome status) =>
      context.commanderTr(switch (status) {
        FileAttributesOutcome.ready => 'Ready',
        FileAttributesOutcome.skipped => 'Skipped',
        FileAttributesOutcome.blocked => 'Blocked',
        FileAttributesOutcome.changed => 'Changed',
        FileAttributesOutcome.failed => 'Failed',
        FileAttributesOutcome.cancelled => 'Cancelled',
      });

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final capabilities = widget.targets.map(
      (target) => target.backend.capabilities,
    );
    final hasMode = capabilities.any((c) => c.permissions);
    final hasOwner = capabilities.any((c) => c.ownership);
    final hasModified = capabilities.any((c) => c.setModifiedTime);
    final hasAccessed = capabilities.any((c) => c.setAccessedTime);
    final hasCreated = capabilities.any((c) => c.setCreatedTime);
    final hasWindowsFlags = capabilities.any((c) => c.windowsAttributes);
    final hasChanges =
        hasMode ||
        hasOwner ||
        hasModified ||
        hasAccessed ||
        hasCreated ||
        hasWindowsFlags;
    return PopScope(
      canPop: !_busy,
      child: CommanderReviewDialog(
        title: context.commanderTr("Change attributes"),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.commanderTr(
                    "Leave a field blank to retain its current value. Preview checks each selected source before changes can be applied.",
                  ),
                ),
                const SizedBox(height: 16),
                if (!hasChanges)
                  Text(
                    context.commanderTr(
                      "This source does not support attribute changes.",
                    ),
                  ),
                if (hasMode)
                  _field(
                    _mode,
                    'attributes-mode',
                    context.commanderTr("Permissions (octal)"),
                    hint: '0755',
                  ),
                if (hasOwner)
                  _field(
                    _owner,
                    'attributes-owner',
                    context.commanderTr("Owner ID"),
                  ),
                if (hasOwner)
                  _field(
                    _group,
                    'attributes-group',
                    context.commanderTr("Group ID"),
                  ),
                if (hasModified)
                  _field(
                    _modified,
                    'attributes-modified',
                    context.commanderTr("Modified time"),
                    hint: 'YYYY-MM-DD HH:mm:ss',
                  ),
                if (hasAccessed)
                  _field(
                    _accessed,
                    'attributes-accessed',
                    context.commanderTr("Accessed time"),
                    hint: 'YYYY-MM-DD HH:mm:ss',
                  ),
                if (hasCreated)
                  _field(
                    _created,
                    'attributes-created',
                    context.commanderTr("Created time"),
                    hint: 'YYYY-MM-DD HH:mm:ss',
                  ),
                if (hasWindowsFlags) ...[
                  Text(
                    context.commanderTr("Windows attributes"),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    context.commanderTr(
                      "Dash: keep • Checked: set • Empty: clear",
                    ),
                  ),
                  for (final flag in _windowsFlags.keys)
                    CheckboxListTile(
                      key: ValueKey('attributes-windows-$flag'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(_flagLabel(flag)),
                      tristate: true,
                      value: _windowsFlags[flag],
                      onChanged: _busy
                          ? null
                          : (value) => _edit(() => _windowsFlags[flag] = value),
                    ),
                ],
                if (hasModified || hasAccessed || hasCreated)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.commanderTr("Use UTC timestamps")),
                    value: _utc,
                    onChanged: _busy
                        ? null
                        : (value) => _edit(() => _utc = value),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(context.commanderTr("Include subfolders")),
                  value: _recursive,
                  onChanged: _busy
                      ? null
                      : (value) => _edit(() => _recursive = value!),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(context.commanderTr("Files")),
                  value: _files,
                  onChanged: _busy
                      ? null
                      : (value) => _edit(() => _files = value!),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(context.commanderTr("Folders")),
                  value: _folders,
                  onChanged: _busy
                      ? null
                      : (value) => _edit(() => _folders = value!),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(context.commanderTr("Stop on error")),
                  value: _stopOnError,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _stopOnError = value!),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (plan != null) ...[
                  const Divider(),
                  Text(
                    context.commanderTr(
                      "{0} ready · {1} changed · {2} reviewed",
                      [plan.ready, plan.changed, plan.entries.length],
                    ),
                  ),
                  Text(
                    context.commanderTr("Requested: {0}", [
                      _describe(plan.patch.metadata),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          if (plan != null)
            SliverList.builder(
              itemCount: plan.entries.length,
              itemBuilder: (context, index) {
                final row = plan.entries[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    row.target.file.isFolder
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                  ),
                  title: Text(row.target.file.path ?? row.target.file.name),
                  subtitle: Text(
                    '${row.target.backend.label} · ${_status(row.outcome)}\n'
                    '${row.message ?? (row.before == null ? '' : _describe(row.before!))}',
                  ),
                );
              },
            ),
        ],
        actions: [
          if (_busy)
            TextButton(
              onPressed: () => setState(() => _cancelled = true),
              child: Text(context.commanderTr("Stop")),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.commanderTr("Close")),
            ),
          OutlinedButton(
            key: const ValueKey('attributes-preview'),
            onPressed: _busy || !hasChanges ? null : _preview,
            child: Text(context.commanderTr("Preview")),
          ),
          FilledButton(
            key: const ValueKey('attributes-apply'),
            onPressed: _busy || plan == null || plan.started || plan.ready == 0
                ? null
                : _apply,
            child: Text(
              context.commanderTr("Apply changes ({0})", [plan?.ready ?? 0]),
            ),
          ),
        ],
      ),
    );
  }
}
