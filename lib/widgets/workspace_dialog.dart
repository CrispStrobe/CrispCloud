import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../l10n/commander_strings.dart';
import '../l10n/workspace_strings.dart';
import '../models/panel_side.dart';
import '../models/workspace_configuration.dart';
import '../providers/panel_provider.dart';
import '../providers/bookmarks_provider.dart';
import '../providers/workspace_provider.dart';
import '../services/workspace_store.dart';
import 'file_view_editor_dialog.dart';
import 'rename_text_dialog.dart';
import 'bookmark_actions.dart';

Future<void> showWorkspaceDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side, {
  int initialSection = 0,
}) => showDialog<void>(
  context: context,
  builder: (_) => WorkspaceDialog(side: side, initialSection: initialSection),
);

class WorkspaceDialog extends ConsumerStatefulWidget {
  const WorkspaceDialog({
    super.key,
    required this.side,
    this.initialSection = 0,
  });
  final PanelSide side;
  final int initialSection;
  @override
  ConsumerState<WorkspaceDialog> createState() => _WorkspaceDialogState();
}

class _WorkspaceDialogState extends ConsumerState<WorkspaceDialog> {
  WorkspaceCatalog? _catalog;
  String? _error;
  bool _busy = false;
  WorkspaceStore get _store => ref.read(workspaceStoreProvider);
  WorkspaceController get _controller => ref.read(workspaceControllerProvider);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _store.load();
      if (mounted) setState(() => _catalog = value);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _name(String title, {String initial = ''}) =>
      showDialog<String>(
        context: context,
        builder: (_) => _WorkspaceNameDialog(title: title, initial: initial),
      );

  Future<void> _saveGroup({SavedWorkspace? existing}) async {
    final name =
        existing?.name ??
        await _name(context.commanderTr('Name this tab group'));
    if (name == null || !mounted) return;
    await _run(
      () async => _store.saveGroup(
        await _controller.captureGroup(name, id: existing?.id),
      ),
    );
  }

  Future<void> _savePair({PairedBookmark? existing}) async {
    final name =
        existing?.name ??
        await _name(context.commanderTr('Name this paired bookmark'));
    if (name == null || !mounted) return;
    await _run(
      () async => _store.savePair(
        await _controller.capturePair(name, id: existing?.id),
      ),
    );
  }

  Future<void> _saveProfile({SavedViewProfile? existing}) async {
    final panel = ref.read(panelProvider(widget.side));
    final value = await showDialog(
      context: context,
      builder: (_) => FileViewEditorDialog(
        initial: existing?.configuration ?? panel.captureViewConfiguration(),
        samples: panel.files ?? const [],
      ),
    );
    if (value == null || !mounted) return;
    final name =
        existing?.name ??
        await _name(context.commanderTr('Name this view profile'));
    if (name == null || !mounted) return;
    await _run(() async {
      final profile = SavedViewProfile(
        id: existing?.id ?? const Uuid().v4(),
        name: name,
        configuration: value,
      );
      await _store.saveProfile(profile);
      await panel.applyViewConfiguration(
        profile.configuration,
        profileId: profile.id,
      );
    });
  }

  Future<void> _rename(NamedWorkspaceItem item) async {
    final name = await _name(context.commanderTr('Rename'), initial: item.name);
    if (name == null || !mounted) return;
    await _run(() async {
      switch (item) {
        case SavedWorkspace():
          await _store.saveGroup(item.renamed(name));
        case PairedBookmark():
          await _store.savePair(item.renamed(name));
        case SavedViewProfile():
          await _store.saveProfile(item.renamed(name));
      }
    });
  }

  Future<void> _replaceGroup(SavedWorkspace group) async {
    final keepProtected = await showDialog<bool>(
      context: context,
      builder: (_) => const _ReplaceWorkspaceDialog(),
    );
    if (keepProtected == null || !mounted) return;
    await _run(
      () => _controller.openGroup(
        group,
        replace: true,
        keepProtected: keepProtected,
      ),
    );
  }

  Future<void> _exchange({required bool importing}) async {
    try {
      final text = importing ? '' : await _store.exportText();
      if (!mounted) return;
      final result = await showDialog<String>(
        context: context,
        builder: (_) => RenameTextDialog(
          title: importing
              ? context.commanderTr("Import workspace settings")
              : context.commanderTr("Export workspace settings"),
          instructions: importing
              ? context.commanderTr(
                  "Merge named tab groups, paired bookmarks and views by their saved IDs. Original accounts remain required. Referenced file collections must be imported separately.",
                )
              : context.commanderTr(
                  "This JSON contains locations and view settings. It includes no credentials or file contents. Referenced file collections are exported separately.",
                ),
          initialText: text,
          submitLabel: importing
              ? context.commanderTr("Import settings")
              : context.commanderTr("Done"),
          fileExtensions: const ['json'],
          filename: 'crispcloud-workspaces.json',
          validate: (text) {
            try {
              WorkspaceStore.decode(text);
              return null;
            } catch (error) {
              return error.toString();
            }
          },
        ),
      );
      if (importing && result != null && mounted) {
        await _run(() => _store.importText(result));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  String _location(WorkspaceTabSnapshot tab) {
    if (tab.collectionId != null) return '${tab.label} · saved collection';
    final storage = tab.storage!;
    final panel = ref.read(panelProvider(widget.side));
    return '${panel.storageDisplayName(storage)} · ${tab.path}';
  }

  Future<void> _exchangeBookmarks({required bool importing}) async {
    final bookmarks = ref.read(bookmarksProvider);
    try {
      final text = importing ? '' : await bookmarks.exportText();
      if (!mounted) return;
      final result = await showDialog<String>(
        context: context,
        builder: (_) => RenameTextDialog(
          title: importing
              ? context.commanderTr("Import bookmarks")
              : context.commanderTr("Export bookmarks"),
          instructions: context.commanderTr(
            "Bookmarks keep their original storage account or collection. Older unbound bookmarks require explicit source binding before they can open.",
          ),
          initialText: text,
          submitLabel: importing
              ? context.commanderTr("Import bookmarks")
              : context.commanderTr("Done"),
          filename: 'crispcloud-bookmarks.json',
          fileExtensions: const ['json'],
          validate: (text) {
            try {
              BookmarksNotifier.decodeImport(text);
              return null;
            } catch (error) {
              return error.toString();
            }
          },
        ),
      );
      if (importing && result != null && mounted) {
        await _run(() => bookmarks.importText(result));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _renameBookmark(Bookmark bookmark) async {
    final name = await _name(
      context.commanderTr('Rename bookmark'),
      initial: bookmark.name,
    );
    if (name == null || !mounted) return;
    await _run(
      () => ref
          .read(bookmarksProvider)
          .replace(
            bookmark,
            Bookmark(
              name: name,
              path: bookmark.path,
              side: bookmark.side,
              storage: bookmark.storage,
              collectionId: bookmark.collectionId,
              group: bookmark.group,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    initialIndex: widget.initialSection.clamp(0, 2),
    child: AlertDialog(
      title: Text(
        context.commanderTr("Commander workspaces"),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 760,
        height: (MediaQuery.sizeOf(context).height * 0.48).clamp(160, 520),
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: context.commanderTr('Tab groups')),
                Tab(text: context.commanderTr('Paired bookmarks')),
                Tab(text: context.commanderTr('View profiles')),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SelectableText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _catalog == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : TextButton(
                              onPressed: _load,
                              child: Text(context.commanderTr("Retry")),
                            ),
                    )
                  : TabBarView(children: [_groups(), _pairs(), _profiles()]),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _exchange(importing: true),
          child: Text(context.commanderTr("Import")),
        ),
        TextButton(
          onPressed: _busy || _catalog == null
              ? null
              : () => _exchange(importing: false),
          child: Text(context.commanderTr("Export")),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.commanderTr("Close")),
        ),
      ],
    ),
  );

  Widget _groups() => ListView(
    padding: const EdgeInsets.only(top: 12),
    children: [
      Text(
        context.commanderTr(
          "Save both panes, their tab order, accounts, locks, views and layout. Unavailable accounts stay unavailable when a group opens.",
        ),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          onPressed: _busy ? null : _saveGroup,
          icon: const Icon(Icons.save_outlined),
          label: Text(context.commanderTr("Save current tab group")),
        ),
      ),
      if (_catalog!.groups.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.commanderTr("No saved tab groups yet.")),
        ),
      for (var i = 0; i < _catalog!.groups.length; i++)
        _groupCard(_catalog!.groups[i], i),
    ],
  );

  Widget _pairs() {
    final bookmarks = ref.watch(bookmarksProvider);
    return ListView(
      padding: const EdgeInsets.only(top: 12),
      children: [
        Text(
          context.commanderTr(
            "Open two saved locations together. Both original accounts are checked before either pane changes. Locked tabs are preserved.",
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: _busy ? null : _savePair,
            icon: const Icon(Icons.bookmarks_outlined),
            label: Text(context.commanderTr("Save current pair")),
          ),
        ),
        if (_catalog!.pairs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.commanderTr("No paired bookmarks yet.")),
          ),
        for (var i = 0; i < _catalog!.pairs.length; i++)
          _pairCard(_catalog!.pairs[i], i),
        const Divider(),
        Text(
          context.commanderTr("Single locations"),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => togglePanelBookmark(context, ref, widget.side),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(context.commanderTr("Toggle current bookmark")),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _exchangeBookmarks(importing: true),
              child: Text(context.commanderTr("Import bookmarks")),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _exchangeBookmarks(importing: false),
              child: Text(context.commanderTr("Export bookmarks")),
            ),
          ],
        ),
        if (bookmarks.lastError != null)
          Text(
            bookmarks.lastError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (final bookmark in bookmarks.bookmarks)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    bookmark.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${bookmark.collectionId != null
                        ? context.commanderTr('Saved collection')
                        : bookmark.storage == null
                        ? context.commanderTr('Original source not yet bound')
                        : ref.read(panelProvider(widget.side)).storageDisplayName(bookmark.storage!)} · ${bookmark.path}',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (bookmark.isBound)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => openBookmark(
                                  context,
                                  ref,
                                  bookmark,
                                  side: widget.side,
                                ),
                          child: Text(context.commanderTr("Open in this pane")),
                        )
                      else
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => bindLegacyBookmark(
                                  context,
                                  ref,
                                  bookmark,
                                  widget.side,
                                ),
                          child: Text(
                            context.commanderTr("Bind original source…"),
                          ),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _renameBookmark(bookmark),
                        child: Text(context.commanderTr("Rename")),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => removeBookmark(context, ref, bookmark),
                        child: Text(context.commanderTr("Remove")),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _profiles() => ListView(
    padding: const EdgeInsets.only(top: 12),
    children: [
      Text(
        context.commanderTr(
          "Save display mode, ordered columns, widths, metadata fields, sorting and a manual filter. Each tab keeps its own view.",
        ),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          onPressed: _busy ? null : _saveProfile,
          icon: const Icon(Icons.view_column_outlined),
          label: Text(context.commanderTr("Create view profile")),
        ),
      ),
      if (_catalog!.profiles.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.commanderTr("No saved view profiles yet.")),
        ),
      for (var i = 0; i < _catalog!.profiles.length; i++)
        _profileCard(_catalog!.profiles[i], i),
    ],
  );

  Widget _card({
    required NamedWorkspaceItem item,
    required String section,
    required int index,
    required int count,
    required String details,
    required List<Widget> actions,
    required Future<void> Function() update,
    required Future<void> Function() remove,
    String updateLabel = 'Replace with current',
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_busy,
                tooltip: context.commanderTr("Manage {0}", [item.name]),
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      _rename(item);
                    case 'update':
                      update();
                    case 'remove':
                      _run(remove);
                    case 'up':
                      _run(() => _store.reorder(section, index, index - 1));
                    case 'down':
                      _run(() => _store.reorder(section, index, index + 2));
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(context.commanderTr("Rename")),
                  ),
                  PopupMenuItem(
                    value: 'update',
                    child: Text(context.commanderTr(updateLabel)),
                  ),
                  if (index > 0)
                    PopupMenuItem(
                      value: 'up',
                      child: Text(context.commanderTr("Move up")),
                    ),
                  if (index + 1 < count)
                    PopupMenuItem(
                      value: 'down',
                      child: Text(context.commanderTr("Move down")),
                    ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(context.commanderTr("Delete saved item")),
                  ),
                ],
              ),
            ],
          ),
          Text(details),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: actions),
        ],
      ),
    ),
  );

  Widget _groupCard(SavedWorkspace group, int index) => _card(
    item: group,
    section: 'groups',
    index: index,
    count: _catalog!.groups.length,
    details: context.commanderTr(
      'Left: {0} tabs · {1}\nRight: {2} tabs · {3}',
      [
        group.left.tabs.length,
        _location(group.left.tabs[group.left.activeIndex]),
        group.right.tabs.length,
        _location(group.right.tabs[group.right.activeIndex]),
      ],
    ),
    update: () => _saveGroup(existing: group),
    remove: () => _store.removeGroup(group.id),
    actions: [
      TextButton(
        onPressed: _busy
            ? null
            : () => _run(() => _controller.openGroup(group)),
        child: Text(context.commanderTr("Append tabs")),
      ),
      TextButton(
        onPressed: _busy ? null : () => _replaceGroup(group),
        child: Text(context.commanderTr("Replace tabs…")),
      ),
    ],
  );

  Widget _pairCard(PairedBookmark pair, int index) => _card(
    item: pair,
    section: 'pairs',
    index: index,
    count: _catalog!.pairs.length,
    details: context.commanderTr('Left: {0}\nRight: {1}', [
      _location(pair.left),
      _location(pair.right),
    ]),
    update: () => _savePair(existing: pair),
    remove: () => _store.removePair(pair.id),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => _run(() => _controller.openPair(pair)),
        child: Text(context.commanderTr("Open pair")),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => _run(() => _controller.openPair(pair, newTabs: true)),
        child: Text(context.commanderTr("Open in new tabs")),
      ),
    ],
  );

  Widget _profileCard(SavedViewProfile profile, int index) => _card(
    item: profile,
    section: 'profiles',
    index: index,
    count: _catalog!.profiles.length,
    details:
        '${profile.configuration.display.localizedLabel(context)} · ${profile.configuration.columns.map((column) => column.localizedLabel(context)).join(', ')}',
    update: () => _saveProfile(existing: profile),
    updateLabel: 'Edit view',
    remove: () => _store.removeProfile(profile.id),
    actions: [
      TextButton(
        onPressed: _busy
            ? null
            : () => _run(
                () => ref
                    .read(panelProvider(widget.side))
                    .applyViewConfiguration(
                      profile.configuration,
                      profileId: profile.id,
                    ),
              ),
        child: Text(context.commanderTr("Apply to this pane")),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => _run(() async {
                for (final side in PanelSide.values) {
                  await ref
                      .read(panelProvider(side))
                      .applyViewConfiguration(
                        profile.configuration,
                        profileId: profile.id,
                      );
                }
              }),
        child: Text(context.commanderTr("Apply to both panes")),
      ),
    ],
  );
}

class _WorkspaceNameDialog extends StatefulWidget {
  const _WorkspaceNameDialog({required this.title, required this.initial});
  final String title;
  final String initial;
  @override
  State<_WorkspaceNameDialog> createState() => _WorkspaceNameDialogState();
}

class _WorkspaceNameDialogState extends State<_WorkspaceNameDialog> {
  late final _text = TextEditingController(text: widget.initial);
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    if (value.isEmpty || value.length > 160 || value.contains('\u0000')) {
      setState(
        () =>
            _error = context.commanderTr('Enter a name with 1–160 characters.'),
      );
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('workspace-name'),
      controller: _text,
      autofocus: true,
      decoration: InputDecoration(
        labelText: context.commanderTr("Name"),
        errorText: _error,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.commanderTr("Cancel")),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(context.commanderTr("Save")),
      ),
    ],
  );
}

class _ReplaceWorkspaceDialog extends StatefulWidget {
  const _ReplaceWorkspaceDialog();
  @override
  State<_ReplaceWorkspaceDialog> createState() =>
      _ReplaceWorkspaceDialogState();
}

class _ReplaceWorkspaceDialogState extends State<_ReplaceWorkspaceDialog> {
  bool _keepProtected = true;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(context.commanderTr("Replace current tabs")),
    content: CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: _keepProtected,
      onChanged: (value) => setState(() => _keepProtected = value ?? true),
      title: Text(context.commanderTr("Keep pinned and locked tabs")),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.commanderTr("Cancel")),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _keepProtected),
        child: Text(context.commanderTr("Replace tabs")),
      ),
    ],
  );
}
