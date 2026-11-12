import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/commander_strings.dart';
import '../l10n/path_favorites_strings.dart';
import '../models/panel_side.dart';
import '../providers/bookmarks_provider.dart';
import '../providers/core_providers.dart';
import '../providers/panel_provider.dart';
import 'bookmark_actions.dart';

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

/// Commander-style path menu, available in both panes regardless of their source.
class PathFavoritesButton extends ConsumerStatefulWidget {
  const PathFavoritesButton({super.key, required this.side});

  final PanelSide side;

  @override
  ConsumerState<PathFavoritesButton> createState() =>
      _PathFavoritesButtonState();
}

class _PathFavoritesButtonState extends ConsumerState<PathFavoritesButton> {
  bool Function()? _menuIsCurrent;
  Bookmark? _capturedLocation;

  void _clearMenu() {
    _menuIsCurrent = null;
    _capturedLocation = null;
  }

  Future<void> _select(Object selected) async {
    final isCurrent = _menuIsCurrent?.call() == true;
    final location = _capturedLocation;
    _clearMenu();
    if (!mounted || !isCurrent) return;
    ref.read(activePanelProvider.notifier).state = widget.side;
    if (selected == _FavoriteAction.manage) {
      await showPathFavoritesEditor(context, widget.side);
    } else if (selected == _FavoriteAction.add && location != null) {
      await _showFavoriteForm(context, ref, widget.side, location);
    } else if (selected is Bookmark &&
        ref.read(bookmarksProvider).bookmarks.contains(selected)) {
      await openBookmark(context, ref, selected, side: widget.side);
    }
  }

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(panelProvider(widget.side));
    final bookmarks = ref.watch(bookmarksProvider);
    final strings = PathFavoritesStrings(context);
    final theme = Theme.of(context);
    final touchTarget = theme.platform == TargetPlatform.android ||
        theme.platform == TargetPlatform.iOS;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: PopupMenuButton<Object>(
        key: ValueKey('path-favorites-${widget.side.name}'),
        tooltip: strings.text('title'),
        padding: EdgeInsets.zero,
        onCanceled: _clearMenu,
        onSelected: _select,
        itemBuilder: (context) {
          final side = widget.side;
          final session = panel.captureOperationSession();
          _menuIsCurrent = () => mounted && widget.side == side && session();
          _capturedLocation = _currentFavorite(panel);
          return [
            if (!bookmarks.isLoaded)
              PopupMenuItem<Object>(
                enabled: false,
                child: Text(context.commanderTr('Loading…')),
              )
            else if (bookmarks.bookmarks.isEmpty)
              PopupMenuItem<Object>(
                enabled: false,
                child: Text(strings.text('empty')),
              ),
            for (final bookmark in bookmarks.bookmarks)
              PopupMenuItem<Object>(
                value: bookmark,
                enabled: bookmark.isBound,
                child: SizedBox(
                  width: 280,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        bookmark.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _sourceLabel(context, panel, bookmark),
                        style: theme.textTheme.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        bookmark.path,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem<Object>(
              value: _FavoriteAction.add,
              enabled: _capturedLocation != null,
              child: Text(strings.text('add')),
            ),
            PopupMenuItem<Object>(
              value: _FavoriteAction.manage,
              child: Text(strings.text('manage')),
            ),
          ];
        },
        child: SizedBox(
          width: touchTarget ? 48 : 38,
          height: touchTarget ? 48 : 34,
          child: Center(child: Text('*', style: theme.textTheme.titleLarge)),
        ),
      ),
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
  String? _error;
  bool _busy = false;

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
    final current = _currentFavorite(panel);
    final all = bookmarks.bookmarks;
    final needle = _filter.toLowerCase();
    final items = all
        .where(
          (bookmark) =>
              bookmark.name.toLowerCase().contains(needle) ||
              bookmark.path.toLowerCase().contains(needle) ||
              _sourceLabel(
                context,
                panel,
                bookmark,
              ).toLowerCase().contains(needle),
        )
        .toList();
    return AlertDialog(
      title: Text(strings.text('title')),
      content: SizedBox(
        width: 640,
        height: MediaQuery.sizeOf(context).height * .62,
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
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final bookmark = items[index];
                        final position = all.indexOf(bookmark);
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
                                SelectableText(
                                  bookmark.path,
                                  textDirection: TextDirection.ltr,
                                ),
                                Wrap(
                                  alignment: WrapAlignment.end,
                                  children: [
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
                                              () =>
                                                  bookmarks.move(bookmark, -1),
                                            ),
                                      icon: const Icon(Icons.arrow_upward),
                                    ),
                                    IconButton(
                                      tooltip: strings.text('down'),
                                      onPressed:
                                          _busy || position == all.length - 1
                                          ? null
                                          : () => _run(
                                              () => bookmarks.move(bookmark, 1),
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
  bool _busy = false;
  String? _error;
  Bookmark? _failedSave;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial.name);
    _path = TextEditingController(text: widget.initial.path);
  }

  @override
  void dispose() {
    _name.dispose();
    _path.dispose();
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
        await bookmarks.replace(retry ? failed! : initial, replacement);
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
