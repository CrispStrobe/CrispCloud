import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/commander_strings.dart';
import '../l10n/path_favorites_strings.dart';
import '../models/panel_side.dart';
import '../providers/bookmarks_provider.dart';
import '../providers/core_providers.dart';
import '../providers/auth_provider.dart';
import '../providers/multi_cloud_provider.dart';
import '../providers/file_collection_provider.dart';
import '../providers/panel_provider.dart';
import 'bookmark_actions.dart';
import 'rename_text_dialog.dart';

enum _FavoriteAction { add, manage }

Bookmark? _currentFavorite(PanelNotifier panel) {
  // Archive paths are virtual, and search results need the collection-saving
  // workflow. Neither may become a misleading ordinary directory favorite.
  if (panel.isInArchive || panel.showingSearchResults) return null;
  final storage = bookmarkStorage(panel);
  if (storage == null) return null;
  return Bookmark(
    name: panel.activeTab?.label ?? panel.currentPath,
    path: panel.currentPath,
    side: panel.side,
    storage: storage,
  );
}

String _sourceLabel(
  BuildContext context,
  PanelNotifier panel,
  Bookmark bookmark,
) {
  final strings = PathFavoritesStrings(context);
  if (bookmark.collectionId != null) return strings.text('collection');
  final storage = bookmark.storage;
  if (storage == null) return strings.text('unbound');
  return panel.storageDisplayName(storage);
}

bool _available(WidgetRef ref, PanelNotifier panel, Bookmark bookmark) {
  if (bookmark.collectionId case final id?) {
    return ref.read(fileCollectionStoreProvider).get(id) != null;
  }
  final storage = bookmark.storage;
  return storage != null &&
      panel.resolveStorageReference(storage, bookmark.path) != null;
}

bool _matches(
  BuildContext context,
  PanelNotifier panel,
  Bookmark bookmark,
  String query,
  String? group,
) {
  if (group != null && bookmark.group != group) return false;
  final text =
      '${bookmark.name}\n${bookmark.path}\n${bookmark.group}\n'
              '${_sourceLabel(context, panel, bookmark)}'
          .toLowerCase();
  return query.trim().toLowerCase().split(RegExp(r'\s+')).every(text.contains);
}

List<Object> _grouped(List<Bookmark> favorites) {
  final groups = <String, List<Bookmark>>{};
  for (final favorite in favorites) {
    (groups[favorite.group] ??= []).add(favorite);
  }
  return [
    for (final group in groups.entries) ...[group.key, ...group.value],
  ];
}

/// Open the searchable favorites picker for the requested pane. Both buttons
/// and configurable shortcuts use the same captured-session safety check.
Future<void> showPathFavoritesMenu(BuildContext context, PanelSide side) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final panel = container.read(panelProvider(side));
  final isCurrent = panel.captureOperationSession();
  final captured = _currentFavorite(panel);
  final sourceLabel = captured == null
      ? null
      : _sourceLabel(context, panel, captured);
  final selected = await showDialog<Object>(
    context: context,
    builder: (_) => _PathFavoritesPicker(side: side, canAdd: captured != null),
  );
  if (!context.mounted || !isCurrent()) return;
  container.read(activePanelProvider.notifier).state = side;
  if (selected == _FavoriteAction.manage) {
    await showPathFavoritesEditor(context, side);
  } else if (selected == _FavoriteAction.add && captured != null) {
    await showDialog<void>(
      context: context,
      builder: (_) => _FavoriteForm(
        initial: captured,
        editing: false,
        sourceLabel: sourceLabel!,
      ),
    );
  } else if (selected is Bookmark &&
      container.read(bookmarksProvider).bookmarks.contains(selected)) {
    try {
      await panel.openSavedLocation(selected.toTabJson());
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

/// Commander-style path picker, available at the top right of either pane.
class PathFavoritesButton extends StatelessWidget {
  const PathFavoritesButton({super.key, required this.side});
  final PanelSide side;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final touch =
        theme.platform == TargetPlatform.android ||
        theme.platform == TargetPlatform.iOS;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: touch ? 48 : 38,
        height: touch ? 48 : 34,
        child: IconButton(
          key: ValueKey('path-favorites-${side.name}'),
          tooltip: PathFavoritesStrings(context).text('title'),
          padding: EdgeInsets.zero,
          onPressed: () => showPathFavoritesMenu(context, side),
          icon: Text('*', style: theme.textTheme.titleLarge),
        ),
      ),
    );
  }
}

class _PathFavoritesPicker extends ConsumerStatefulWidget {
  const _PathFavoritesPicker({required this.side, required this.canAdd});
  final PanelSide side;
  final bool canAdd;
  @override
  ConsumerState<_PathFavoritesPicker> createState() =>
      _PathFavoritesPickerState();
}

class _PathFavoritesPickerState extends ConsumerState<_PathFavoritesPicker> {
  final _search = TextEditingController();
  String? _group;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = PathFavoritesStrings(context);
    final store = ref.watch(bookmarksProvider);
    final panel = ref.watch(panelProvider(widget.side));
    ref.watch(authProvider);
    ref.watch(multiCloudProvider);
    ref.watch(fileCollectionStoreProvider);
    final selectedGroup = _group == '' || store.groups.contains(_group)
        ? _group
        : null;
    final filtered = store.bookmarks
        .where(
          (item) => _matches(context, panel, item, _search.text, selectedGroup),
        )
        .toList();
    final rows = _grouped(filtered);
    return AlertDialog(
      title: Text(strings.text('title')),
      content: SizedBox(
        width: 560,
        height:
            (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom) *
            .55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('path-favorites-search'),
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                labelText: strings.text('search'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: strings.text('clearSearch'),
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                final available = filtered
                    .where((item) => _available(ref, panel, item))
                    .toList();
                if (available.length == 1) {
                  Navigator.pop(context, available.single);
                }
              },
            ),
            _GroupFilter(
              groups: store.groups,
              value: selectedGroup,
              onChanged: (value) => setState(() => _group = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: !store.isLoaded
                  ? const Center(child: CircularProgressIndicator())
                  : rows.isEmpty
                  ? Center(
                      child: Text(
                        strings.text(
                          store.bookmarks.isEmpty ? 'empty' : 'noMatches',
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row is String) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                            child: Text(
                              row.isEmpty ? strings.text('ungrouped') : row,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          );
                        }
                        final bookmark = row as Bookmark;
                        final available = _available(ref, panel, bookmark);
                        return ListTile(
                          key: ValueKey(
                            'path-favorite-menu-${bookmark.identity}',
                          ),
                          enabled: available,
                          leading: Icon(
                            available
                                ? Icons.folder_outlined
                                : Icons.cloud_off_outlined,
                          ),
                          title: Text(bookmark.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_sourceLabel(context, panel, bookmark)),
                              Text(
                                bookmark.path,
                                textDirection: TextDirection.ltr,
                              ),
                              if (!available && bookmark.isBound)
                                Text(
                                  strings.text(
                                    bookmark.collectionId != null
                                        ? 'missingCollection'
                                        : bookmark.isBound
                                        ? 'unavailable'
                                        : 'unbound',
                                  ),
                                ),
                            ],
                          ),
                          onTap: available
                              ? () => Navigator.pop(context, bookmark)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.canAdd
              ? () => Navigator.pop(context, _FavoriteAction.add)
              : null,
          child: Text(strings.text('add')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _FavoriteAction.manage),
          child: Text(strings.text('manage')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.commanderTr('Close')),
        ),
      ],
    );
  }
}

class _GroupFilter extends StatelessWidget {
  const _GroupFilter({
    required this.groups,
    required this.value,
    required this.onChanged,
  });
  final List<String> groups;
  final String? value;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) {
    final strings = PathFavoritesStrings(context);
    final values = <String>['', ...groups];
    return DropdownButtonFormField<String>(
      key: ValueKey(
        'path-favorites-group-filter-${value ?? 'all'}-${groups.join('|')}',
      ),
      initialValue: value != null && values.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: strings.text('group')),
      hint: Text(strings.text('allGroups')),
      items: [
        DropdownMenuItem(value: null, child: Text(strings.text('allGroups'))),
        for (final group in values)
          DropdownMenuItem(
            value: group,
            child: Text(group.isEmpty ? strings.text('ungrouped') : group),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

Future<void> showPathFavoritesEditor(BuildContext context, PanelSide side) =>
    showDialog<void>(
      context: context,
      builder: (_) => PathFavoritesDialog(side: side),
    );

/// Edits the existing bookmark store; changes are shared by both pane menus.
class PathFavoritesDialog extends ConsumerStatefulWidget {
  const PathFavoritesDialog({super.key, required this.side});

  final PanelSide side;

  @override
  ConsumerState<PathFavoritesDialog> createState() =>
      _PathFavoritesDialogState();
}

class _PathFavoritesDialogState extends ConsumerState<PathFavoritesDialog> {
  String _filter = '';
  String? _group;
  String? _error;
  bool _busy = false;

  Future<void> _exchange({required bool importing}) => _run(() async {
    final store = ref.read(bookmarksProvider);
    await store.ready;
    final initial = importing ? '' : await store.exportText();
    if (!mounted) return;
    final strings = PathFavoritesStrings(context);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => RenameTextDialog(
        title: strings.text(importing ? 'import' : 'export'),
        instructions: strings.text(importing ? 'importNotice' : 'exportNotice'),
        initialText: initial,
        submitLabel: importing
            ? strings.text('previewImport')
            : context.commanderTr('Done'),
        filename: 'crispcloud-path-favorites.json',
        fileExtensions: const ['json'],
        validate: importing
            ? (text) {
                try {
                  BookmarksNotifier.decodeImport(text);
                  return null;
                } catch (_) {
                  return strings.text('invalidImport');
                }
              }
            : null,
      ),
    );
    if (importing && text != null && mounted) {
      await showPathFavoritesImportPreview(context, widget.side, text);
    }
  });

  Future<void> _renameGroup() async {
    final original = _group;
    if (original == null || original.isEmpty || _busy) return;
    final next = await showDialog<String>(
      context: context,
      builder: (_) => _FavoriteGroupNameDialog(initial: original),
    );
    if (next == null || !mounted) return;
    await _run(() => ref.read(bookmarksProvider).renameGroup(original, next));
    if (mounted) setState(() => _group = next);
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = PathFavoritesStrings(context);
    final bookmarks = ref.watch(bookmarksProvider);
    final panel = ref.watch(panelProvider(widget.side));
    ref.watch(authProvider);
    ref.watch(multiCloudProvider);
    ref.watch(fileCollectionStoreProvider);
    final current = _currentFavorite(panel);
    final all = bookmarks.bookmarks;
    final selectedGroup = _group == '' || bookmarks.groups.contains(_group)
        ? _group
        : null;
    final items = all
        .where(
          (bookmark) =>
              _matches(context, panel, bookmark, _filter, selectedGroup),
        )
        .toList();
    return AlertDialog(
      title: Text(strings.text('title')),
      content: SizedBox(
        width: 640,
        height:
            (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom) *
            .62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              children: [
                Tooltip(
                  message: current == null
                      ? strings.text('folderRequired')
                      : '',
                  child: TextButton.icon(
                    onPressed: _busy || current == null
                        ? null
                        : () => _showFavoriteForm(
                            context,
                            ref,
                            widget.side,
                            current,
                          ),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(strings.text('add')),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('path-favorites-import'),
                  onPressed: _busy ? null : () => _exchange(importing: true),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(strings.text('import')),
                ),
                TextButton.icon(
                  key: const ValueKey('path-favorites-export'),
                  onPressed: _busy || all.isEmpty
                      ? null
                      : () => _exchange(importing: false),
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text(strings.text('export')),
                ),
              ],
            ),
            TextField(
              key: const ValueKey('path-favorites-filter'),
              decoration: InputDecoration(
                labelText: strings.text('filter'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _filter = value),
            ),
            Row(
              children: [
                Expanded(
                  child: _GroupFilter(
                    groups: bookmarks.groups,
                    value: selectedGroup,
                    onChanged: (value) => setState(() => _group = value),
                  ),
                ),
                IconButton(
                  tooltip: strings.text('renameGroup'),
                  onPressed:
                      _busy || selectedGroup == null || selectedGroup.isEmpty
                      ? null
                      : _renameGroup,
                  icon: const Icon(Icons.drive_file_rename_outline),
                ),
              ],
            ),
            if (_error != null || bookmarks.lastError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error ?? bookmarks.lastError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: !bookmarks.isLoaded
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                  ? Center(
                      child: Text(
                        strings.text(all.isEmpty ? 'empty' : 'noMatches'),
                      ),
                    )
                  : ListView.builder(
                      key: const ValueKey('path-favorites-list'),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final bookmark = items[index];
                        final siblings = all
                            .where((item) => item.group == bookmark.group)
                            .toList();
                        final position = siblings.indexOf(bookmark);
                        final available = _available(ref, panel, bookmark);
                        return Card(
                          key: ValueKey('path-favorite-${bookmark.identity}'),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  bookmark.name,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                Text(_sourceLabel(context, panel, bookmark)),
                                Text(
                                  bookmark.group.isEmpty
                                      ? strings.text('ungrouped')
                                      : bookmark.group,
                                ),
                                if (!available)
                                  Text(
                                    strings.text(
                                      bookmark.collectionId != null
                                          ? 'missingCollection'
                                          : bookmark.isBound
                                          ? 'unavailable'
                                          : 'unbound',
                                    ),
                                  ),
                                SelectableText(
                                  bookmark.path,
                                  textDirection: TextDirection.ltr,
                                ),
                                Wrap(
                                  alignment: WrapAlignment.end,
                                  children: [
                                    IconButton(
                                      tooltip: strings.text('open'),
                                      onPressed: _busy || !available
                                          ? null
                                          : () => openBookmark(
                                              context,
                                              ref,
                                              bookmark,
                                              side: widget.side,
                                            ),
                                      icon: const Icon(Icons.folder_open),
                                    ),
                                    if (!bookmark.isBound)
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _run(
                                                () => bindLegacyBookmark(
                                                  context,
                                                  ref,
                                                  bookmark,
                                                  widget.side,
                                                ),
                                              ),
                                        child: Text(strings.text('bind')),
                                      ),
                                    IconButton(
                                      tooltip: strings.text('up'),
                                      onPressed: _busy || position == 0
                                          ? null
                                          : () => _run(
                                              () => bookmarks.move(
                                                bookmark,
                                                -1,
                                                withinGroup: true,
                                              ),
                                            ),
                                      icon: const Icon(Icons.arrow_upward),
                                    ),
                                    IconButton(
                                      tooltip: strings.text('down'),
                                      onPressed:
                                          _busy ||
                                              position == siblings.length - 1
                                          ? null
                                          : () => _run(
                                              () => bookmarks.move(
                                                bookmark,
                                                1,
                                                withinGroup: true,
                                              ),
                                            ),
                                      icon: const Icon(Icons.arrow_downward),
                                    ),
                                    IconButton(
                                      tooltip: strings.text('edit'),
                                      onPressed: _busy
                                          ? null
                                          : () => _showFavoriteForm(
                                              context,
                                              ref,
                                              widget.side,
                                              bookmark,
                                              editing: true,
                                            ),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: context.commanderTr('Remove'),
                                      onPressed: _busy
                                          ? null
                                          : () => _run(
                                              () => bookmarks.remove(
                                                bookmark.path,
                                                bookmark.side,
                                                storage: bookmark.storage,
                                                collectionId:
                                                    bookmark.collectionId,
                                              ),
                                            ),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.commanderTr('Close')),
        ),
      ],
    );
  }
}

class _FavoriteGroupNameDialog extends StatefulWidget {
  const _FavoriteGroupNameDialog({required this.initial});
  final String initial;
  @override
  State<_FavoriteGroupNameDialog> createState() =>
      _FavoriteGroupNameDialogState();
}

class _FavoriteGroupNameDialogState extends State<_FavoriteGroupNameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    try {
      Bookmark.validateGroup(_name.text.trim());
      Navigator.pop(context, _name.text.trim());
    } catch (_) {
      setState(
        () => _error = PathFavoritesStrings(context).text('invalidGroup'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = PathFavoritesStrings(context);
    return AlertDialog(
      scrollable: true,
      title: Text(strings.text('renameGroup')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.text('groupNotice')),
            TextField(
              key: const ValueKey('path-favorites-rename-group'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: strings.text('group'),
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.commanderTr('Cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(context.commanderTr('Save')),
        ),
      ],
    );
  }
}

/// A separate, explicit merge step shared with the Commander workspace import.
Future<void> showPathFavoritesImportPreview(
  BuildContext context,
  PanelSide side,
  String text,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _FavoriteImportPreview(side: side, text: text),
);

class _FavoriteImportPreview extends ConsumerStatefulWidget {
  const _FavoriteImportPreview({required this.side, required this.text});
  final PanelSide side;
  final String text;
  @override
  ConsumerState<_FavoriteImportPreview> createState() =>
      _FavoriteImportPreviewState();
}

class _FavoriteImportPreviewState
    extends ConsumerState<_FavoriteImportPreview> {
  bool _busy = false;
  String? _error;

  Future<void> _merge() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final store = ref.read(bookmarksProvider);
      await store.mergeImport(store.previewImport(widget.text));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = PathFavoritesStrings(context).text('saveFailed'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = PathFavoritesStrings(context);
    final store = ref.watch(bookmarksProvider);
    final panel = ref.watch(panelProvider(widget.side));
    ref.watch(authProvider);
    ref.watch(multiCloudProvider);
    ref.watch(fileCollectionStoreProvider);
    BookmarkImportPreview? preview;
    try {
      preview = store.previewImport(widget.text);
    } catch (_) {
      // A corrupt local store or invalid import never reaches the merge button.
    }
    final additions = preview?.additions ?? const <Bookmark>[];
    final unavailable = additions
        .where((item) => !_available(ref, panel, item))
        .length;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(strings.text('importPreview')),
        content: SizedBox(
          width: 620,
          height:
              (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom) *
              .55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.text('mergeNotice')),
              const SizedBox(height: 12),
              if (preview != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(
                      label: Text(
                        strings.text(
                          'additionsCount',
                          arguments: {'count': additions.length},
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        strings.text(
                          'duplicatesCount',
                          arguments: {'count': preview.duplicates},
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(
                        strings.text(
                          'unavailableCount',
                          arguments: {'count': unavailable},
                        ),
                      ),
                    ),
                  ],
                ),
              if (_error != null || preview == null)
                Text(
                  _error ?? strings.text('invalidImport'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: additions.isEmpty
                    ? Center(child: Text(strings.text('noNew')))
                    : ListView.builder(
                        itemCount: additions.length,
                        itemBuilder: (context, index) {
                          final bookmark = additions[index];
                          final available = _available(ref, panel, bookmark);
                          return ListTile(
                            title: Text(bookmark.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bookmark.group.isEmpty
                                      ? strings.text('ungrouped')
                                      : bookmark.group,
                                ),
                                Text(_sourceLabel(context, panel, bookmark)),
                                Text(
                                  bookmark.path,
                                  textDirection: TextDirection.ltr,
                                ),
                                if (!available)
                                  Text(
                                    strings.text(
                                      bookmark.collectionId != null
                                          ? 'missingCollection'
                                          : bookmark.isBound
                                          ? 'unavailable'
                                          : 'unbound',
                                    ),
                                  ),
                              ],
                            ),
                            trailing: available
                                ? null
                                : const Icon(Icons.cloud_off_outlined),
                          );
                        },
                      ),
              ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(context.commanderTr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('path-favorites-merge'),
            onPressed:
                _busy ||
                    preview == null ||
                    (additions.isEmpty && store.lastError == null)
                ? null
                : _merge,
            child: Text(strings.text('merge')),
          ),
        ],
      ),
    );
  }
}

Future<void> _showFavoriteForm(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  Bookmark initial, {
  bool editing = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _FavoriteForm(
    initial: initial,
    editing: editing,
    sourceLabel: _sourceLabel(context, ref.read(panelProvider(side)), initial),
  ),
);

class _FavoriteForm extends ConsumerStatefulWidget {
  const _FavoriteForm({
    required this.initial,
    required this.editing,
    required this.sourceLabel,
  });
  final Bookmark initial;
  final bool editing;
  final String sourceLabel;

  @override
  ConsumerState<_FavoriteForm> createState() => _FavoriteFormState();
}

class _FavoriteFormState extends ConsumerState<_FavoriteForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _path;
  late final TextEditingController _group;
  bool _busy = false;
  String? _error;
  Bookmark? _failedSave;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial.name);
    _path = TextEditingController(text: widget.initial.path);
    _group = TextEditingController(text: widget.initial.group);
  }

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
    _group.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final initial = widget.initial;
    final replacement = Bookmark(
      name: _name.text.trim(),
      path: _path.text,
      side: initial.side,
      storage: initial.storage,
      collectionId: initial.collectionId,
      group: _group.text.trim(),
    );
    final bookmarks = ref.read(bookmarksProvider);
    var previous = bookmarks.bookmarks;
    try {
      replacement.validate();
      await bookmarks.ready;
      if (!mounted) return;
      previous = bookmarks.bookmarks;
      final failed = _failedSave;
      // The existing store updates optimistically. If persistence failed, keep
      // this editor open and retry that item instead of creating a duplicate.
      final retry =
          failed != null &&
          bookmarks.bookmarks.any((item) => item.identity == failed.identity);
      if (widget.editing || retry) {
        await bookmarks.replace(retry ? failed : initial, replacement);
      } else {
        if (bookmarks.bookmarks.any(
          (item) =>
              item.path == replacement.path &&
              item.storage == replacement.storage &&
              item.collectionId == replacement.collectionId,
        )) {
          setState(
            () => _error = PathFavoritesStrings(context).text('duplicate'),
          );
          return;
        }
        await bookmarks.add(
          replacement.name,
          replacement.path,
          replacement.side,
          storage: replacement.storage,
          collectionId: replacement.collectionId,
          group: replacement.group,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      // Only retry a row this attempt actually changed. A rejected duplicate
      // must never turn into permission to replace the other saved favorite.
      for (final item in bookmarks.bookmarks) {
        if (item.identity == replacement.identity && !previous.contains(item)) {
          _failedSave = item;
          break;
        }
      }
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = PathFavoritesStrings(context);
    final initial = widget.initial;
    final paths =
        (initial.storage?.isLocal == true &&
                initial.storage?.provider == 'windows') ||
            (initial.storage == null && p.windows.isAbsolute(initial.path))
        ? p.windows
        : p.posix;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(strings.text(widget.editing ? 'edit' : 'new')),
        content: SizedBox(
          width: 500,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('path-favorite-name'),
                  controller: _name,
                  autofocus: true,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: context.commanderTr('Name'),
                  ),
                  validator: (value) =>
                      value == null ||
                          value.trim().isEmpty ||
                          value.trim().length > 160 ||
                          value.contains('\u0000')
                      ? strings.text('invalidName')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('path-favorite-path'),
                  controller: _path,
                  textDirection: TextDirection.ltr,
                  enabled: !_busy,
                  readOnly: initial.collectionId != null,
                  decoration: InputDecoration(labelText: strings.text('path')),
                  validator: (value) =>
                      value == null ||
                          value.length > 8192 ||
                          value.contains('\u0000') ||
                          !paths.isAbsolute(value)
                      ? strings.text('invalidPath')
                      : null,
                  onFieldSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('path-favorite-group'),
                  controller: _group,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: strings.text('group'),
                    helperText: strings.text('groupHint'),
                    suffixIcon: PopupMenuButton<String>(
                      tooltip: strings.text('group'),
                      enabled: !_busy,
                      onSelected: (value) => _group.text = value,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: '',
                          child: Text(strings.text('ungrouped')),
                        ),
                        for (final group in ref.read(bookmarksProvider).groups)
                          PopupMenuItem(value: group, child: Text(group)),
                      ],
                      icon: const Icon(Icons.arrow_drop_down),
                    ),
                  ),
                  validator: (value) {
                    try {
                      Bookmark.validateGroup((value ?? '').trim());
                      return null;
                    } catch (_) {
                      return strings.text('invalidGroup');
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  strings.text('source'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                SelectableText(widget.sourceLabel),
                if (widget.editing) ...[
                  const SizedBox(height: 8),
                  Text(strings.text('sourceFixed')),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(context.commanderTr('Cancel')),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(context.commanderTr('Save')),
          ),
        ],
      ),
    );
  }
}
