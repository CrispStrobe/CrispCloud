import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/panel_side.dart';
import '../providers/panel_provider.dart';
import '../services/file_list_export.dart';

Future<void> showFileListDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side, {
  bool importMode = false,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _FileListDialog(side: side, importMode: importMode),
  );
  if (context.mounted) ref.read(panelProvider(side)).focusList();
}

Future<void> copyFileListPaths(
  BuildContext context,
  WidgetRef ref,
  PanelSide side, {
  bool selectedOnly = false,
}) async {
  try {
    final text = ref
        .read(panelProvider(side))
        .exportFileListPaths(selectedOnly: selectedOnly);
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.commanderTr("Original paths copied."))),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _FileListDialog extends ConsumerStatefulWidget {
  const _FileListDialog({required this.side, required this.importMode});
  final PanelSide side;
  final bool importMode;

  @override
  ConsumerState<_FileListDialog> createState() => _FileListDialogState();
}

class _FileListDialogState extends ConsumerState<_FileListDialog> {
  final _input = TextEditingController();
  final _output = TextEditingController();
  late bool _importMode = widget.importMode;
  bool _selectedOnly = false;
  bool _busy = false;
  bool _cancelled = false;
  String? _error;
  String? _message;
  FileListImportResult? _result;

  @override
  void initState() {
    super.initState();
    final panel = ref.read(panelProvider(widget.side));
    _selectedOnly = panel.selection.isNotEmpty;
    _refreshExport();
  }

  @override
  void dispose() {
    _cancelled = true;
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _refreshExport() {
    try {
      _output.text = ref
          .read(panelProvider(widget.side))
          .exportFileListPaths(selectedOnly: _selectedOnly);
      _error = null;
    } catch (error) {
      _error = error.toString();
    }
  }

  Future<void> _pickList() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'lst'],
        withData: true,
      );
      if (!mounted || picked == null) return;
      final file = picked.files.single;
      if (file.size > 4 * 1024 * 1024 ||
          (file.bytes?.length ?? 0) > 4 * 1024 * 1024) {
        throw const FormatException('The file list exceeds 4 MiB.');
      }
      final bytes = file.bytes;
      if (bytes == null) throw StateError('The chosen file could not be read.');
      setState(() {
        _input.text = utf8.decode(bytes);
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _loadList() async {
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _message = null;
      _result = null;
    });
    try {
      final result = await ref
          .read(panelProvider(widget.side))
          .importFileListPaths(
            _input.text,
            isCancelled: () => _cancelled || !mounted,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _message = '${result.loaded} item(s) loaded into the panel.';
      });
      if (result.failures.isEmpty) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveList() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final message = await exportFileListText(_output.text);
      if (mounted) setState(() => _message = message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(panelProvider(widget.side));
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(context.commanderTr("File list")),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(context.commanderTr("Export paths")),
                      icon: const Icon(Icons.output),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(context.commanderTr("Import paths")),
                      icon: const Icon(Icons.input),
                    ),
                  ],
                  selected: {_importMode},
                  onSelectionChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _importMode = value.single;
                          _error = null;
                          _message = null;
                          if (!_importMode) _refreshExport();
                        }),
                ),
                const SizedBox(height: 12),
                Text(
                  _importMode
                      ? context.commanderTr(
                          "One path per line. Relative paths resolve against the current folder. Each entry is checked in this panel’s source before loading.",
                        )
                      : context.commanderTr(
                          "Original full paths, one per line. The list can be loaded again into the same storage source.",
                        ),
                ),
                if (!_importMode)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selectedOnly,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _selectedOnly = value!;
                            _refreshExport();
                          }),
                    title: Text(
                      context.commanderTr("Selected items only ({0})", [
                        panel.selection.length,
                      ]),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: ValueKey(
                    _importMode ? 'import-file-list' : 'export-file-list',
                  ),
                  controller: _importMode ? _input : _output,
                  readOnly: !_importMode || _busy,
                  minLines: 8,
                  maxLines: 12,
                  style: const TextStyle(fontFamily: 'AppMono', fontSize: 12),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: context.commanderTr("Paths"),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _importMode
                      ? [
                          TextButton.icon(
                            onPressed: _busy ? null : _pickList,
                            icon: const Icon(Icons.text_snippet_outlined),
                            label: Text(
                              context.commanderTr("Open .txt / .lst"),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final clipboard = await Clipboard.getData(
                                      Clipboard.kTextPlain,
                                    );
                                    if (mounted) {
                                      setState(
                                        () =>
                                            _input.text = clipboard?.text ?? '',
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.content_paste),
                            label: Text(context.commanderTr("Paste paths")),
                          ),
                        ]
                      : [
                          TextButton.icon(
                            onPressed: _busy || _output.text.isEmpty
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: _output.text),
                                    );
                                    if (mounted) {
                                      setState(
                                        () =>
                                            _message = 'Original paths copied.',
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.copy),
                            label: Text(context.commanderTr("Copy paths")),
                          ),
                          TextButton.icon(
                            onPressed: _busy || _output.text.isEmpty
                                ? null
                                : _saveList,
                            icon: const Icon(Icons.save_alt),
                            label: Text(context.commanderTr("Save list…")),
                          ),
                        ],
                ),
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 4),
                  Text(
                    _importMode
                        ? context.commanderTr("Checking original paths…")
                        : context.commanderTr("Saving file list…"),
                  ),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_message != null) Text(_message!),
                if (_result?.failures.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.commanderTr("{0} item(s) were not loaded:", [
                      _result!.failures.length,
                    ]),
                  ),
                  SizedBox(
                    height: 120,
                    child: ListView(
                      children: [
                        for (final entry in _result!.failures.entries)
                          ListTile(
                            dense: true,
                            title: Text(entry.key),
                            subtitle: Text(entry.value),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy
                ? (_importMode ? () => setState(() => _cancelled = true) : null)
                : () => Navigator.pop(context),
            child: Text(
              _busy
                  ? context.commanderTr("Cancel import")
                  : context.commanderTr("Close"),
            ),
          ),
          if (_importMode)
            FilledButton(
              onPressed: _busy ? null : _loadList,
              child: Text(context.commanderTr("Load into panel")),
            ),
        ],
      ),
    );
  }
}
