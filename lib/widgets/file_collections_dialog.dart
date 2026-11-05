import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/file_collection.dart';
import '../models/panel_side.dart';
import '../providers/file_collection_provider.dart';
import '../providers/panel_provider.dart';
import '../services/file_list_export.dart';

Future<void> showFileCollectionsDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => FileCollectionsDialog(side: side),
  );
  if (context.mounted) ref.read(panelProvider(side)).focusList();
}

Future<void> reviewCollectionReplacements(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
) async {
  final panel = ref.read(panelProvider(side));
  final items = panel.collectionReplacements;
  if (items.isEmpty) return;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Use ${items.length} replacement item(s)?'),
      content: SizedBox(
        width: 620,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Different items now occupy these saved paths. Accepting updates the collection references to the current items; file contents are unchanged.',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, index) => ListTile(
                  title: Text(items[index].path ?? items[index].name),
                  subtitle: Text(
                    items[index].isFolder
                        ? 'Folder'
                        : '${items[index].size ?? 0} bytes',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Accept current items'),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await panel.acceptCollectionReplacements(items);
  }
}

class FileCollectionsDialog extends ConsumerStatefulWidget {
  const FileCollectionsDialog({super.key, required this.side});
  final PanelSide side;
  @override
  ConsumerState<FileCollectionsDialog> createState() =>
      _FileCollectionsDialogState();
}

class _FileCollectionsDialogState extends ConsumerState<FileCollectionsDialog> {
  final _name = TextEditingController();
  bool _selectedOnly = false;
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    final panel = ref.read(panelProvider(widget.side));
    _name.text = panel.showingSearchResults
        ? panel.fileListTitle
        : 'File collection';
    _selectedOnly = panel.selection.isNotEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName(String current) async {
    final controller = TextEditingController(text: current);
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Collection name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 256,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'txt'],
      withReadStream: true,
      withData: false,
    );
    if (picked == null) return;
    final file = picked.files.single;
    const limit = 32 * 1024 * 1024;
    if (file.size > limit) {
      throw const FormatException('Collection exceeds 32 MiB.');
    }
    final bytes = BytesBuilder(copy: false);
    if (file.readStream != null) {
      await for (final chunk in file.readStream!) {
        if (bytes.length + chunk.length > limit) {
          throw const FormatException('Collection exceeds 32 MiB.');
        }
        bytes.add(chunk);
      }
    } else if (file.bytes != null) {
      if (file.bytes!.length > limit) {
        throw const FormatException('Collection exceeds 32 MiB.');
      }
      bytes.add(file.bytes!);
    } else {
      throw StateError('The chosen collection could not be read.');
    }
    final imported = FileCollection.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(utf8.decode(bytes.takeBytes())) as Map,
      ),
    );
    final collection = FileCollection(
      id: const Uuid().v4(),
      name: imported.name,
      entries: imported.entries,
      selectedKeys: imported.selectedKeys,
      search: imported.search,
    );
    await ref.read(fileCollectionStoreProvider).save(collection);
    if (mounted) {
      setState(
        () => _message =
            'Imported ${collection.entries.length} original references. Opening checks their sources.',
      );
    }
  }

  Future<void> _action(String action, FileCollection collection) async {
    final panel = ref.read(panelProvider(widget.side));
    switch (action) {
      case 'open':
      case 'tab':
        await panel.openCollection(collection.id, newTab: action == 'tab');
        if (mounted) Navigator.pop(context);
      case 'add':
        await panel.appendToCollection(collection.id);
        if (mounted) {
          setState(
            () => _message =
                'Marked rows added with their original storage references.',
          );
        }
      case 'rename':
        final name = await _askName(collection.name);
        if (name != null) {
          await panel.renameSavedCollection(collection.id, name);
        }
      case 'export':
        final message = await exportFileListText(
          const JsonEncoder.withIndent('  ').convert(collection.toJson()),
          fileName: 'crispcloud-collection.json',
        );
        if (mounted) setState(() => _message = message);
      case 'copy':
        await Clipboard.setData(
          ClipboardData(
            text: const JsonEncoder.withIndent('  ')
                .convert(collection.toJson()),
          ),
        );
        if (mounted) {
          setState(
            () => _message = 'Collection JSON copied. It contains file references and no login credentials.',
          );
        }
      case 'remove':
        await panel.removeSavedCollection(collection.id);
        if (mounted) {
          setState(
            () =>
                _message = 'Saved collection removed; the files are unchanged.',
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(fileCollectionStoreProvider);
    final panel = ref.watch(panelProvider(widget.side));
    return AlertDialog(
      title: const Text('File collections'),
      content: SizedBox(
        width: 760,
        height: 540,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Keep search results, imported lists, and marked files with their original accounts. Open checks saved paths; Rerun search uses the saved query.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('collection-name'),
                    controller: _name,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Save current rows as',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Marked rows only'),
                        selected: _selectedOnly,
                        onSelected: _busy
                            ? null
                            : (value) => setState(() => _selectedOnly = value),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('collection-save'),
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                final id = await panel.saveCurrentCollection(
                                  _name.text,
                                  selectedOnly: _selectedOnly,
                                  createNew: true,
                                );
                                if (mounted) {
                                  setState(
                                    () => _message =
                                        'Saved ${store.get(id)?.entries.length ?? 0} rows.',
                                  );
                                }
                              }),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save collection'),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _run(_import),
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('Import collection'),
                      ),
                    ],
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_message!),
                    ),
                  if (store.loadErrors.isNotEmpty)
                    ExpansionTile(
                      title: Text(
                        '${store.loadErrors.length} saved records need attention',
                      ),
                      children: [SelectableText(store.loadErrors.join('\n'))],
                    ),
                  const Divider(),
                ],
              ),
            ),
            if (store.collections.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No saved collections yet.')),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final collection = store.collections[index];
                  final sources = collection.entries
                      .map((entry) => entry.reference.storage.id)
                      .toSet();
                  final unavailable = collection.entries
                      .where(
                        (entry) =>
                            entry.state == CollectionItemState.missing ||
                            entry.state == CollectionItemState.offline ||
                            entry.replacement,
                      )
                      .length;
                  return ListTile(
                    key: ValueKey('collection-${collection.id}'),
                    leading: Icon(
                      collection.search == null
                          ? Icons.list_alt
                          : Icons.saved_search,
                    ),
                    title: Text(collection.name),
                    subtitle: Text(
                      '${collection.entries.length} rows · ${sources.length} source(s)${unavailable == 0 ? '' : ' · $unavailable need checking'}',
                    ),
                    onTap: _busy
                        ? null
                        : () => _run(() => _action('open', collection)),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Collection actions',
                      enabled: !_busy,
                      onSelected: (action) =>
                          _run(() => _action(action, collection)),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'open',
                          child: Text('Open and refresh items'),
                        ),
                        const PopupMenuItem(
                          value: 'tab',
                          child: Text('Open in new tab'),
                        ),
                        PopupMenuItem(
                          value: 'add',
                          enabled: panel.selection.isNotEmpty,
                          child: const Text('Add current marked rows'),
                        ),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename collection'),
                        ),
                        const PopupMenuItem(
                          value: 'export',
                          child: Text('Export collection…'),
                        ),
                        const PopupMenuItem(
                          value: 'copy',
                          child: Text('Copy collection JSON'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove collection (keep files)'),
                        ),
                      ],
                    ),
                  );
                }, childCount: store.collections.length),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
