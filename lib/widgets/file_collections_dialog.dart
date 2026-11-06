import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../l10n/commander_strings.dart';
import '../models/file_collection.dart';
import '../models/file_collection_page.dart';
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
      title: Text(
        context.commanderTr("Use {0} replacement item(s)?", [items.length]),
      ),
      content: SizedBox(
        width: 620,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.commanderTr(
                "Different items now occupy these saved paths. Accepting updates the collection references to the current items; file contents are unchanged.",
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, index) => ListTile(
                  title: Text(items[index].path ?? items[index].name),
                  subtitle: Text(
                    items[index].isFolder
                        ? context.commanderTr("Folder")
                        : context.commanderTr("{0} bytes", [
                            items[index].size ?? 0,
                          ]),
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
          child: Text(context.commanderTr("Cancel")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.commanderTr("Accept current items")),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await panel.refreshCollectionItems(
      acceptReplacements: true,
      acceptedReplacementKeys: items
          .map((item) => '${item.storageId}\u0000${item.path}')
          .toSet(),
    );
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
          title: Text(context.commanderTr("Collection name")),
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
              child: Text(context.commanderTr("Cancel")),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: Text(context.commanderTr("Save")),
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

  Future<void> _action(String action, FileCollectionSummary collection) async {
    final panel = ref.read(panelProvider(widget.side));
    final store = ref.read(fileCollectionStoreProvider);
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
          await store.rename(collection.id, name);
        }
      case 'export':
        final loaded = await store.load(collection.id);
        final message = await exportFileListText(
          const JsonEncoder.withIndent('  ').convert(loaded.toJson()),
          fileName: 'crispcloud-collection.json',
        );
        if (mounted) setState(() => _message = message);
      case 'copy':
        final loaded = await store.load(collection.id);
        await Clipboard.setData(
          ClipboardData(
            text: const JsonEncoder.withIndent('  ').convert(loaded.toJson()),
          ),
        );
        if (mounted) {
          setState(
            () => _message = 'Collection JSON copied. It contains file references and no login credentials.',
          );
        }
      case 'remove':
        await store.remove(collection.id);
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
    final collections = store.collections;
    final panel = ref.watch(panelProvider(widget.side));
    return AlertDialog(
      title: Text(context.commanderTr("File collections")),
      content: SizedBox(
        width: 760,
        height: 540,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.commanderTr(
                      "Keep search results, imported lists, and marked files with their original accounts. Open checks saved paths; Rerun search uses the saved query.",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('collection-name'),
                    controller: _name,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: context.commanderTr("Save current rows as"),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: Text(context.commanderTr("Marked rows only")),
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
                                        'Saved ${store.get(id)?.itemCount ?? 0} rows.',
                                  );
                                }
                              }),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(context.commanderTr("Save collection")),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _run(_import),
                        icon: const Icon(Icons.file_open_outlined),
                        label: Text(context.commanderTr("Import collection")),
                      ),
                    ],
                  ),
                  if (_busy || store.isLoading) const LinearProgressIndicator(),
                  if (store.loadProgress != null) Text(store.loadProgress!),
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
                        context.commanderTr(
                          "{0} saved records need attention",
                          [store.loadErrors.length],
                        ),
                      ),
                      children: [
                        SelectableText(store.loadErrors.join('\n')),
                        TextButton(
                          onPressed: _busy ? null : () => _run(store.reload),
                          child: Text(
                            context.commanderTr("Reload collections"),
                          ),
                        ),
                      ],
                    ),
                  const Divider(),
                ],
              ),
            ),
            if (collections.isEmpty && !store.isLoading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      context.commanderTr("No saved collections yet."),
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final collection = collections[index];
                  final unavailable = collection.unavailableCount;
                  return ListTile(
                    key: ValueKey('collection-${collection.id}'),
                    leading: Icon(
                      collection.hasSearch
                          ? Icons.saved_search
                          : Icons.list_alt,
                    ),
                    title: Text(collection.name),
                    subtitle: Text(
                      context.commanderTr("{0} rows · {1} source(s){2}", [
                        collection.itemCount,
                        collection.sourceCount,
                        unavailable == 0 ? '' : ' · $unavailable need checking',
                      ]),
                    ),
                    onTap: _busy
                        ? null
                        : () => _run(() => _action('open', collection)),
                    trailing: PopupMenuButton<String>(
                      tooltip: context.commanderTr("Collection actions"),
                      enabled: !_busy,
                      onSelected: (action) =>
                          _run(() => _action(action, collection)),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'open',
                          child: Text(
                            context.commanderTr("Open and refresh items"),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'tab',
                          child: Text(context.commanderTr("Open in new tab")),
                        ),
                        PopupMenuItem(
                          value: 'add',
                          enabled: panel.selection.isNotEmpty,
                          child: Text(
                            context.commanderTr("Add current marked rows"),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'rename',
                          child: Text(context.commanderTr("Rename collection")),
                        ),
                        PopupMenuItem(
                          value: 'export',
                          child: Text(
                            context.commanderTr("Export collection…"),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'copy',
                          child: Text(
                            context.commanderTr("Copy collection JSON"),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text(
                            context.commanderTr(
                              "Remove collection (keep files)",
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }, childCount: collections.length),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.commanderTr("Close")),
        ),
      ],
    );
  }
}
