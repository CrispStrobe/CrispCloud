import '../services/document_workspace_session.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
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
  try {
    if (!await closeDocumentWorkspace(context) || !context.mounted) return;
    final side = ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(side));
    if (!panel.hasVerifiedDirectoryListing) {
      throw StateError(
        'Open a normal destination folder before creating a document.',
      );
    }
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

  void _selectKind(NewDocumentKind kind) {
    setState(() {
      final old = _name.text;
      final dot = old.lastIndexOf('.');
      _kind = kind;
      _name.text = '${dot > 0 ? old.substring(0, dot) : old}.${kind.extension}';
    });
  }

  IconData _kindIcon(NewDocumentKind kind) => switch (kind) {
    NewDocumentKind.text => Icons.code,
    NewDocumentKind.markdown => Icons.notes,
    NewDocumentKind.csv => Icons.table_chart_outlined,
    NewDocumentKind.word => Icons.description_outlined,
    NewDocumentKind.spreadsheet => Icons.grid_on,
    NewDocumentKind.presentation => Icons.slideshow,
    NewDocumentKind.pdf => Icons.picture_as_pdf_outlined,
    NewDocumentKind.picture => Icons.image_outlined,
    NewDocumentKind.ebook => Icons.menu_book_outlined,
  };

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
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 350 ? 2 : 3;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 8) / columns;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in NewDocumentKind.values)
                        SizedBox(
                          width: width,
                          child: Semantics(
                            selected: _kind == kind,
                            child: OutlinedButton(
                              key: ValueKey('new-document-kind-${kind.name}'),
                              autofocus: kind == NewDocumentKind.text,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                                backgroundColor: _kind == kind
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer
                                    : null,
                                side: BorderSide(
                                  color: _kind == kind
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _working
                                  ? null
                                  : () => _selectKind(kind),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_kindIcon(kind), size: 28),
                                  const SizedBox(height: 6),
                                  Text(switch (kind) {
                                    NewDocumentKind.word =>
                                      AppLocalizations.of(
                                            context,
                                          )?.officeDocuments ??
                                          'Documents (.docx)',
                                    NewDocumentKind.spreadsheet =>
                                      AppLocalizations.of(
                                            context,
                                          )?.officeSpreadsheets ??
                                          'Spreadsheets (.xlsx)',
                                    NewDocumentKind.presentation =>
                                      AppLocalizations.of(
                                            context,
                                          )?.officePresentations ??
                                          'Presentations (.pptx)',
                                    _ => documentTr(context, kind.label),
                                  }, textAlign: TextAlign.center),
                                  Text(
                                    '.${kind.extension}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('new-document-name'),
                controller: _name,
                enabled: !_working,
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
