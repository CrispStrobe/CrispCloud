import '../services/document_workspace_session.dart';

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/document_workspace_strings.dart';
import '../models/file_item.dart';
import '../models/storage_reference.dart';
import '../providers/providers.dart';
import '../services/document_conversion.dart';
import '../services/document_history.dart';
import '../services/file_bytes_loader.dart';
import '../services/file_operation_backend.dart';
import '../services/new_document.dart';
import 'file_editor_dialog.dart';

Future<void> showDocumentConversionDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  if (!await closeDocumentWorkspace(context) || !context.mounted) return;
  try {
    final side = ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(side));
    final destination = panel.captureCurrentOrigin();
    final directory = destination.source.currentPath;
    final backend = fileOperationBackend(
      source: destination.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => destination.isCurrent,
    );
    final selected = panel.selection.length == 1
        ? panel.selection.single
        : panel.cursorItem;
    final source = selected == null || selected.isFolder
        ? null
        : panel.originForOperation(selected);
    final created = await showDialog<FileItem>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DocumentConversionDialog(
        directory: directory,
        sourceName: source == null ? null : selected!.name,
        readSource: source == null
            ? null
            : () => loadFileBytes(
                ref,
                selected!,
                side,
                origin: source,
                capBytes: documentConversionInputLimit,
              ),
        onSave: (result, name) => createNewDocument(
          backend: backend,
          directory: directory,
          name: name,
          kind: result.kind,
          content: result.bytes,
        ),
      ),
    );
    if (created == null) return;
    await ref
        .read(documentHistoryProvider)
        .record(
          FileReference(
            storage: destination.storageReference,
            path: created.path!,
          ),
          edited: true,
        );
    if (!context.mounted || !destination.isCurrent) return;
    await panel.navigateToPath(directory, origin: destination);
    final listed = (panel.files ?? <FileItem>[])
        .where((f) => f.path == created.path || f.name == created.name)
        .firstOrNull;
    if (listed == null) {
      throw StateError(
        'The converted copy was saved. Refresh its original folder to open it.',
      );
    }
    panel.restoreCursorAndFocus(listed);
    if (context.mounted) await showFileEditorDialog(context, ref, listed, side);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class DocumentConversionDialog extends StatefulWidget {
  const DocumentConversionDialog({
    super.key,
    required this.directory,
    required this.onSave,
    this.sourceName,
    this.readSource,
  });
  final String directory;
  final String? sourceName;
  final Future<Uint8List> Function()? readSource;
  final Future<FileItem> Function(DocumentConversionResult, String) onSave;
  @override
  State<DocumentConversionDialog> createState() =>
      _DocumentConversionDialogState();
}

class _DocumentConversionDialogState extends State<DocumentConversionDialog> {
  final _name = TextEditingController(), _password = TextEditingController();
  Uint8List? _bytes;
  String? _sourceName, _target, _error;
  bool _busy = false, _reviewed = false;
  DocumentConversionResult? _result;
  List<String> get _formats =>
      _bytes == null ? [] : documentConversionFormats(_sourceName!, _bytes!);
  @override
  void initState() {
    super.initState();
    if (widget.readSource != null) _readSelected();
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _work(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _install(String name, Uint8List bytes) {
    if (bytes.length > documentConversionInputLimit) {
      throw const FormatException('Choose a file up to 64 MiB.');
    }
    setState(() {
      _sourceName = name;
      _bytes = bytes;
      _target = _formats.firstOrNull;
      _result = null;
      _reviewed = false;
      _suggestName();
    });
  }

  void _suggestName() {
    final name = _sourceName ?? 'Document';
    final dot = name.lastIndexOf('.');
    _name.text =
        '${dot > 0 ? name.substring(0, dot) : name} (converted).${_target ?? 'txt'}';
  }

  Future<void> _readSelected() => _work(() async {
    final bytes = await widget.readSource!();
    if (mounted) _install(widget.sourceName!, bytes);
  });
  Future<void> _pick() => _work(() async {
    final result = await FilePicker.platform.pickFiles(
      withData: false,
      withReadStream: true,
    );
    if (result == null || !mounted) return;
    final file = result.files.single;
    if (file.size > documentConversionInputLimit || file.readStream == null) {
      throw const FormatException('Choose a file up to 64 MiB.');
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in file.readStream!) {
      if (out.length + chunk.length > documentConversionInputLimit) {
        throw const FormatException('Conversion input exceeds 64 MiB.');
      }
      out.add(chunk);
    }
    if (mounted) _install(file.name, out.takeBytes());
  });
  Future<void> _convert() => _work(() async {
    final result = await convertDocument(
      _bytes!,
      sourceName: _sourceName!,
      extension: _target!,
      password: _password.text.isEmpty ? null : _password.text,
    );
    if (mounted) {
      setState(() {
        _result = result;
        _reviewed = result.notices.isEmpty;
      });
    }
  });
  Future<void> _save() => _work(() async {
    final result = _result!;
    final name = _name.text;
    if (!name.toLowerCase().endsWith('.${result.extension}')) {
      throw FormatException('Use a .${result.extension} filename.');
    }
    final file = await widget.onSave(result, name);
    if (mounted) Navigator.pop(context, file);
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      key: const ValueKey('document-conversion-dialog'),
      title: Text(documentTr(context, 'Convert existing file…')),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(documentTr(context, 'Destination')),
              SelectableText(widget.directory),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _sourceName ?? documentTr(context, 'Choose a source file'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('conversion-choose-source'),
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(documentTr(context, 'Choose file…')),
                  ),
                ],
              ),
              if (_bytes != null && _formats.isEmpty)
                Text(
                  documentTr(
                    context,
                    'No conversion is available for this source.',
                  ),
                ),
              if (_formats.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  key: ValueKey(_sourceName),
                  initialValue: _target,
                  decoration: InputDecoration(
                    labelText: documentTr(context, 'Output format'),
                  ),
                  items: [
                    for (final ext in _formats)
                      DropdownMenuItem(
                        value: ext,
                        child: Text(ext.toUpperCase()),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _target = value;
                          _result = null;
                          _reviewed = false;
                          _suggestName();
                        }),
                ),
                TextField(
                  key: const ValueKey('conversion-password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: documentTr(context, 'Password (if encrypted)'),
                  ),
                  onChanged: (_) => setState(() => _result = null),
                ),
                TextField(
                  key: const ValueKey('conversion-output-name'),
                  controller: _name,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: documentTr(context, 'File name'),
                  ),
                ),
              ],
              if (_result case final result?) ...[
                const SizedBox(height: 12),
                Text(
                  '${result.extension.toUpperCase()} · ${result.bytes.length} bytes${result.pages > 0 ? ' · ${result.pages} pages · ${result.tables} tables' : ''}',
                ),
                for (final notice in result.notices)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(notice),
                  ),
                if (result.notices.isNotEmpty)
                  CheckboxListTile(
                    key: const ValueKey('conversion-review'),
                    contentPadding: EdgeInsets.zero,
                    value: _reviewed,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _reviewed = v!),
                    title: Text(
                      documentTr(
                        context,
                        'I have reviewed the conversion limitations',
                      ),
                    ),
                  ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(documentTr(context, 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('conversion-prepare'),
          onPressed: _busy || _target == null ? null : _convert,
          child: Text(documentTr(context, 'Convert')),
        ),
        FilledButton(
          key: const ValueKey('conversion-save'),
          onPressed: _busy || _result == null || !_reviewed ? null : _save,
          child: Text(documentTr(context, 'Save copy and edit')),
        ),
      ],
    ),
  );
}
