import '../services/document_workspace_session.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/document_workspace_strings.dart';
import '../l10n/provider_operation_strings.dart';
import '../providers/providers.dart';
import '../services/document_history.dart';
import '../services/file_operation_backend.dart';
import '../services/new_document.dart';
import '../services/panel_source_service.dart';
import '../models/storage_reference.dart';
import '../models/file_item.dart';
import 'file_editor_dialog.dart';
import 'document_conversion_dialog.dart';

Future<void> showNewDocumentDialog(BuildContext context, WidgetRef ref) async {
  if (!await closeDocumentWorkspace(context) || !context.mounted) return;
  final side = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(side));
  try {
    final origin = panel.captureCurrentOrigin();
    if (origin.source is! LocalPanelSource &&
        origin.source is! RemotePanelSource) {
      throw StateError('Choose a writable local or connected cloud folder.');
    }
    final directory = origin.source.currentPath;
    final backend = fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => origin.isCurrent,
    );
    var convert = false;
    final created = await showDialog<NewDocumentResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => NewDocumentDialog(
        onConvert: () {
          convert = true;
          Navigator.pop(dialogContext);
        },
        directory: directory,
        onCreate: (kind, name) => createNewDocument(
          backend: backend,
          directory: directory,
          name: name,
          kind: kind,
        ).then((file) => NewDocumentResult(file: file, kind: kind)),
      ),
    );
    if (convert && context.mounted) {
      await showDocumentConversionDialog(context, ref);
      return;
    }
    if (created == null) return;
    await ref
        .read(documentHistoryProvider)
        .record(
          FileReference(
            storage: origin.storageReference,
            path: created.file.path!,
          ),
          edited: true,
        );
    if (!context.mounted) return;
    if (!origin.isCurrent) {
      throw StateError(
        'The document was created. Reconnect its original storage to open it.',
      );
    }
    await panel.navigateToPath(directory, origin: origin);
    final listed = (panel.files ?? <FileItem>[])
        .where(
          (f) => f.path == created.file.path || f.name == created.file.name,
        )
        .firstOrNull;
    if (listed == null) {
      throw StateError(
        'The document was created. Refresh its original folder to open it.',
      );
    }
    panel.restoreCursorAndFocus(listed);
    if (context.mounted) {
      await showFileEditorDialog(
        context,
        ref,
        listed,
        side,
        forceText:
            created.kind == NewDocumentKind.text ||
            created.kind == NewDocumentKind.markdown ||
            created.kind == NewDocumentKind.csv,
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedProviderError(context, error))),
      );
    }
  }
}

class NewDocumentResult {
  const NewDocumentResult({required this.file, required this.kind});
  final FileItem file;
  final NewDocumentKind kind;
}

class NewDocumentDialog extends StatefulWidget {
  const NewDocumentDialog({
    super.key,
    required this.directory,
    required this.onCreate,
    this.onConvert,
  });
  final String directory;
  final VoidCallback? onConvert;
  final Future<NewDocumentResult> Function(NewDocumentKind, String) onCreate;
  @override
  State<NewDocumentDialog> createState() => _NewDocumentDialogState();
}

class _NewDocumentDialogState extends State<NewDocumentDialog> {
  final _name = TextEditingController(text: 'Untitled.txt');
  var _kind = NewDocumentKind.text;
  bool _working = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final name = validateNewDocumentName(_name.text, _kind);
      final result = await widget.onCreate(_kind, name);
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _working = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working,
    child: AlertDialog(
      key: const ValueKey('new-document-dialog'),
      title: Text(documentTr(context, 'New document')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(widget.directory),
              const SizedBox(height: 16),
              DropdownButtonFormField<NewDocumentKind>(
                key: const ValueKey('new-document-kind'),
                initialValue: _kind,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: documentTr(context, 'Editor / format'),
                ),
                items: [
                  for (final kind in NewDocumentKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Text(
                        '${documentTr(context, kind.label)} (.${kind.extension})',
                      ),
                    ),
                ],
                onChanged: _working
                    ? null
                    : (kind) {
                        if (kind == null) return;
                        setState(() {
                          final old = _name.text;
                          final dot = old.lastIndexOf('.');
                          _kind = kind;
                          _name.text =
                              '${dot > 0 ? old.substring(0, dot) : old}.${kind.extension}';
                        });
                      },
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('new-document-name'),
                controller: _name,
                enabled: !_working,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: documentTr(context, 'File name'),
                ),
                onSubmitted: (_) => _create(),
              ),
              if (_kind == NewDocumentKind.picture)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('1024 × 768 px · PNG'),
                ),
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
              if (_working)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onConvert != null)
          TextButton(
            key: const ValueKey('new-document-convert'),
            onPressed: _working ? null : widget.onConvert,
            child: Text(documentTr(context, 'Convert existing file…')),
          ),
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: Text(documentTr(context, 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('new-document-create'),
          onPressed: _working ? null : _create,
          child: Text(documentTr(context, 'Create and edit')),
        ),
      ],
    ),
  );
}
