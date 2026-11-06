import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/panel_side.dart';
import '../providers/panel_provider.dart';
import '../services/file_list_export.dart';
import '../services/file_selection_pattern.dart';

Future<void> showFileListDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side, {
  bool importMode = false,
  bool selectionMode = false,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _FileListDialog(
      side: side,
      importMode: importMode || selectionMode,
      selectionMode: selectionMode,
    ),
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
    final text = await ref
        .read(panelProvider(side))
        .exportAllFileListPaths(selectedOnly: selectedOnly);
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
  const _FileListDialog({
    required this.side,
    required this.importMode,
    required this.selectionMode,
  });
  final PanelSide side;
  final bool importMode;
  final bool selectionMode;

  @override
  ConsumerState<_FileListDialog> createState() => _FileListDialogState();
}

class _FileListDialogState extends ConsumerState<_FileListDialog> {
  final _input = TextEditingController();
  final _output = TextEditingController();
  late bool _importMode = widget.importMode;
  late bool _selectionMode = widget.selectionMode;
  late final List<PathSelectionSource> _sources;
  PathSelectionSource? _source;
  SelectionAction _selectionAction = SelectionAction.select;
  bool _selectedOnly = false;
  bool _busy = false;
  bool _cancelled = false;
  String? _error;
  String? _message;
  FileListImportResult? _result;
  int _exportRequest = 0;

  @override
  void initState() {
    super.initState();
    final panel = ref.read(panelProvider(widget.side));
    _selectedOnly = panel.selection.isNotEmpty;
    _sources = panel.pathSelectionSources;
    if (_sources.length == 1) _source = _sources.single;
    _refreshExport();
  }

  @override
  void dispose() {
    _cancelled = true;
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  Future<void> _refreshExport() async {
    final request = ++_exportRequest;
    setState(() => _busy = true);
    try {
      final text = await ref
          .read(panelProvider(widget.side))
          .exportAllFileListPaths(selectedOnly: _selectedOnly);
      if (!mounted || request != _exportRequest) return;
      setState(() {
        _output.text = text;
        _error = null;
      });
    } catch (error) {
      if (mounted && request == _exportRequest) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && request == _exportRequest) setState(() => _busy = false);
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
      final panel = ref.read(panelProvider(widget.side));
      if (_selectionMode && _source == null) {
        throw StateError(
          'Choose the original storage account for this path list.',
        );
      }
      final result = _selectionMode
          ? await panel.selectPathsFromListAsync(
              _input.text,
              source: _source,
              action: _selectionAction,
              isCancelled: () => _cancelled || !mounted,
            )
          : await panel.importFileListPaths(
              _input.text,
              isCancelled: () => _cancelled || !mounted,
            );
      if (!mounted) return;
      setState(() {
        _result = result;
        _message = _selectionMode
            ? context.commanderTr("Updated marks for {0} matching item(s).", [
                result.loaded,
              ])
            : '${result.loaded} item(s) loaded into the panel.';
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
        title: Text(
          context.commanderTr(_selectionMode ? "Load selection" : "File list"),
        ),
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
                if (_importMode) ...[
                  CheckboxListTile(
                    key: const ValueKey('file-list-selection-mode'),
                    contentPadding: EdgeInsets.zero,
                    value: _selectionMode,
                    title: Text(
                      context.commanderTr("Apply paths as selection marks"),
                    ),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _selectionMode = value!),
                  ),
                  if (_selectionMode) ...[
                    Text(
                      context.commanderTr(
                        "Only visible, verified rows in the chosen source are marked. The panel contents stay in place.",
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<PathSelectionSource>(
                      key: const ValueKey('file-list-selection-source'),
                      initialValue: _source,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.commanderTr("Storage source"),
                      ),
                      items: [
                        for (final source in _sources)
                          DropdownMenuItem(
                            value: source,
                            child: Text(
                              source.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (source) => setState(() => _source = source),
                    ),
                    if (_source != null)
                      Text(
                        context.commanderTr("Relative paths start at {0}", [
                          _source!.basePath,
                        ]),
                      ),
                    if (_source?.isCurrent == false)
                      Text(
                        context.commanderTr(
                          "The panel changed. Close and reopen this dialog.",
                        ),
                      ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<SelectionAction>(
                      key: const ValueKey('file-list-selection-action'),
                      initialValue: _selectionAction,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.commanderTr("Action"),
                      ),
                      items: [
                        for (final action in SelectionAction.values)
                          DropdownMenuItem(
                            value: action,
                            child: Text(
                              context.commanderTr(switch (action) {
                                SelectionAction.select =>
                                  'Add matches to selection',
                                SelectionAction.deselect =>
                                  'Remove matches from selection',
                                SelectionAction.invert =>
                                  'Invert matching marks',
                                SelectionAction.replace =>
                                  'Replace marks in this source',
                              }),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) =>
                                setState(() => _selectionAction = value!),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
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
              key: const ValueKey('file-list-apply'),
              onPressed: _busy || (_selectionMode && _source?.isCurrent != true)
                  ? null
                  : _loadList,
              child: Text(
                context.commanderTr(
                  _selectionMode ? "Apply selection marks" : "Load into panel",
                ),
              ),
            ),
        ],
      ),
    );
  }
}
