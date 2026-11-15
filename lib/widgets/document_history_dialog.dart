import '../services/document_workspace_session.dart';

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/document_workspace_strings.dart';
import '../models/file_item.dart';
import '../providers/providers.dart';
import '../services/document_history.dart';
import '../services/file_list_export.dart';
import '../services/file_operation_backend.dart';
import 'file_editor_dialog.dart';
import 'internal_viewer_dialog.dart';

class HistoryOpenRequest {
  const HistoryOpenRequest(this.entry, {required this.edit});
  final DocumentHistoryEntry entry;
  final bool edit;
}

Future<void> showDocumentHistoryDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final side = ref.read(activePanelProvider);
  final request = await showDialog<HistoryOpenRequest>(
    context: context,
    builder: (_) => const DocumentHistoryDialog(),
  );
  if (request == null || !context.mounted) return;
  if (!await closeDocumentWorkspace(context) || !context.mounted) return;
  try {
    final panel = ref.read(panelProvider(side));
    final file = request.entry.file;
    final origin = panel.resolveStorageReference(file.storage, file.path);
    if (origin == null) {
      throw StateError(
        'Reconnect the original storage account before reopening this file.',
      );
    }
    final backend = fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => origin.isCurrent,
    );
    final fresh = await backend.stat(file.path);
    if (!origin.isCurrent || fresh == null || fresh.isFolder) {
      throw StateError('This file is unavailable at its original location.');
    }
    final directory = backend.paths.dirname(file.path);
    await panel.navigateToPath(directory, origin: origin);
    if (!origin.isCurrent || !context.mounted) return;
    final listed = (panel.files ?? <FileItem>[])
        .where((f) => f.path == file.path || f.name == fresh.name)
        .firstOrNull;
    if (listed == null) {
      throw StateError(
        'Refresh the original folder before reopening this file.',
      );
    }
    panel.restoreCursorAndFocus(listed);
    if (request.edit) {
      await showFileEditorDialog(context, ref, listed, side);
    } else {
      final action = await showInternalViewer(
        context,
        file: listed,
        side: side,
      );
      if (action == InternalViewerAction.edit && context.mounted) {
        await showFileEditorDialog(context, ref, listed, side);
      }
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class DocumentHistoryDialog extends ConsumerStatefulWidget {
  const DocumentHistoryDialog({super.key});
  @override
  ConsumerState<DocumentHistoryDialog> createState() =>
      _DocumentHistoryDialogState();
}

class _DocumentHistoryDialogState extends ConsumerState<DocumentHistoryDialog> {
  String _filter = 'Edited', _query = '';
  bool _busy = false;
  bool _awaitingDecision = false;
  String? _message;
  Future<void> _work(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _awaitingDecision = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final result = await exportFileListText(
      ref.read(documentHistoryProvider).exportJson(),
      fileName: 'crispcloud-recent-files.json',
    );
    if (mounted && result != null) {
      setState(() => _message = documentTr(context, 'List saved.'));
    }
  }

  Future<void> _load() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
      withReadStream: true,
    );
    if (result == null || !mounted) return;
    final file = result.files.single;
    if (file.size > DocumentHistory.maxImportBytes || file.readStream == null) {
      throw const FormatException('Choose a history JSON file up to 8 MiB.');
    }
    final bytes = <int>[];
    await for (final chunk in file.readStream!) {
      if (bytes.length + chunk.length > DocumentHistory.maxImportBytes) {
        throw const FormatException('History exceeds 8 MiB.');
      }
      bytes.addAll(chunk);
    }
    final raw = utf8.decode(bytes);
    final entries = DocumentHistory.decode(raw);
    if (!mounted) return;
    var replace = false;
    setState(() => _awaitingDecision = true);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(documentTr(context, 'Load list…')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${entries.length} ${documentTr(context, 'Recent files')}'),
              CheckboxListTile(
                value: replace,
                onChanged: (v) => setDialogState(() => replace = v!),
                title: Text(documentTr(context, 'Replace current list')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(documentTr(context, 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(documentTr(context, 'Load')),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() => _awaitingDecision = false);
    if (accepted == true && mounted) {
      await ref.read(documentHistoryProvider).importJson(raw, replace: replace);
      if (mounted) setState(() => _filter = 'All');
    }
  }

  Future<void> _purge() async {
    setState(() => _awaitingDecision = true);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(documentTr(context, 'Purge this history?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(documentTr(context, 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(documentTr(context, 'Purge list…')),
          ),
        ],
      ),
    );
    if (mounted) setState(() => _awaitingDecision = false);
    if (yes == true && mounted) await ref.read(documentHistoryProvider).purge();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(documentHistoryProvider);
    final items = history.entries
        .where(
          (e) =>
              (_filter != 'Edited' || e.editedAt != null) &&
              (_filter != 'Opened' || e.openedAt != null) &&
              ('${e.file.path} ${e.file.storage.provider}')
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    items.sort(
      (a, b) =>
          (_filter == 'Edited'
                  ? b.editedAt!
                  : _filter == 'Opened'
                  ? b.openedAt!
                  : b.latest)
              .compareTo(
                _filter == 'Edited'
                    ? a.editedAt!
                    : _filter == 'Opened'
                    ? a.openedAt!
                    : a.latest,
              ),
    );
    final dialog = AlertDialog(
      key: const ValueKey('document-history-dialog'),
      title: Text(documentTr(context, 'Recent files')),
      content: SizedBox(
        width: 780,
        height: 620,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    key: const ValueKey('history-record-edits'),
                    title: Text(documentTr(context, 'Record edited files')),
                    value: history.recordEdits,
                    onChanged: _busy
                        ? null
                        : (v) => _work(
                            () => history.configure(
                              edits: v,
                              opens: history.recordOpens,
                            ),
                          ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    key: const ValueKey('history-record-opens'),
                    title: Text(
                      documentTr(context, 'Record opened files (optional)'),
                    ),
                    value: history.recordOpens,
                    onChanged: _busy
                        ? null
                        : (v) => _work(
                            () => history.configure(
                              edits: history.recordEdits,
                              opens: v,
                            ),
                          ),
                  ),
                  Text(
                    documentTr(
                      context,
                      'History saved automatically; up to 1000 files.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final filter in ['Edited', 'Opened', 'All'])
                        ChoiceChip(
                          label: Text(documentTr(context, filter)),
                          selected: _filter == filter,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _filter = filter),
                        ),
                    ],
                  ),
                  TextField(
                    key: const ValueKey('history-search'),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: documentTr(context, 'Search'),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  if (_busy && !_awaitingDecision)
                    const LinearProgressIndicator(),
                  if (history.persistenceError ?? _message
                      case final String message)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SelectableText(message),
                    ),
                ],
              ),
            ),
            items.isEmpty
                ? SliverToBoxAdapter(
                    child: Center(
                      child: Text(documentTr(context, 'No recent files')),
                    ),
                  )
                : SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final entry = items[index];
                      final file = entry.file;
                      final name = file.path
                          .replaceAll('\\', '/')
                          .split('/')
                          .last;
                      return ListTile(
                        title: Text(name),
                        subtitle: Text(
                          '${file.path}\n${file.storage.provider} · ${file.storage.isLocal ? '' : file.storage.accountKey}\n${documentTr(context, 'Edited')}: ${entry.editedAt?.toLocal() ?? '–'} · ${documentTr(context, 'Opened')}: ${entry.openedAt?.toLocal() ?? '–'}',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          enabled: !_busy,
                          onSelected: (action) {
                            if (action == 'remove') {
                              _work(() => history.remove(entry));
                            } else {
                              Navigator.pop(
                                context,
                                HistoryOpenRequest(
                                  entry,
                                  edit: action == 'edit',
                                ),
                              );
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(documentTr(context, 'Edit')),
                            ),
                            PopupMenuItem(
                              value: 'view',
                              child: Text(documentTr(context, 'View')),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text(documentTr(context, 'Remove')),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('history-export'),
          onPressed: _busy ? null : () => _work(_save),
          child: Text(documentTr(context, 'Save list…')),
        ),
        TextButton(
          key: const ValueKey('history-import'),
          onPressed: _busy ? null : () => _work(_load),
          child: Text(documentTr(context, 'Load list…')),
        ),
        TextButton(
          key: const ValueKey('history-purge'),
          onPressed: _busy ? null : () => _work(_purge),
          child: Text(documentTr(context, 'Purge list…')),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(documentTr(context, 'Close')),
        ),
      ],
    );
    final small =
        MediaQuery.sizeOf(context).width < 600 ||
        MediaQuery.sizeOf(context).height < 650;
    return PopScope(
      canPop: !_busy,
      child: small
          ? Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  automaticallyImplyLeading: false,
                  leading: IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: documentTr(context, 'Close'),
                  ),
                  title: dialog.title,
                  actions: [
                    PopupMenuButton<String>(
                      key: const ValueKey('history-mobile-actions'),
                      enabled: !_busy,
                      onSelected: (action) {
                        _work(switch (action) {
                          'save' => _save,
                          'load' => _load,
                          _ => _purge,
                        });
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'save',
                          child: Text(documentTr(context, 'Save list…')),
                        ),
                        PopupMenuItem(
                          value: 'load',
                          child: Text(documentTr(context, 'Load list…')),
                        ),
                        PopupMenuItem(
                          value: 'purge',
                          child: Text(documentTr(context, 'Purge list…')),
                        ),
                      ],
                    ),
                  ],
                ),
                body: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: dialog.content!,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : dialog,
    );
  }
}
