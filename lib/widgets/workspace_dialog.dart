import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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
    final name = existing?.name ?? await _name('Name this tab group');
    if (name == null || !mounted) return;
    await _run(
      () async => _store.saveGroup(
        await _controller.captureGroup(name, id: existing?.id),
      ),
    );
  }

  Future<void> _savePair({PairedBookmark? existing}) async {
    final name = existing?.name ?? await _name('Name this paired bookmark');
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
    final name = existing?.name ?? await _name('Name this view profile');
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
    final name = await _name('Rename', initial: item.name);
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
              ? 'Import workspace settings'
              : 'Export workspace settings',
          instructions: importing
              ? 'Merge named tab groups, paired bookmarks and views by their saved IDs. Original accounts remain required. Referenced file collections must be imported separately.'
              : 'This JSON contains locations and view settings. It includes no credentials or file contents. Referenced file collections are exported separately.',
          initialText: text,
          submitLabel: importing ? 'Import settings' : 'Done',
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
          title: importing ? 'Import bookmarks' : 'Export bookmarks',
          instructions: 'Bookmarks keep their original storage account or collection. Older unbound bookmarks require explicit source binding before they can open.',
          initialText: text,
          submitLabel: importing ? 'Import bookmarks' : 'Done',
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
    final name = await _name('Rename bookmark', initial: bookmark.name);
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
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    initialIndex: widget.initialSection.clamp(0, 2),
    child: AlertDialog(
      title: const Text('Commander workspaces'),
      content: SizedBox(
        width: 760,
        height: (MediaQuery.sizeOf(context).height * 0.68).clamp(240, 600),
        child: Column(
          children: [
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Tab groups'),
                Tab(text: 'Paired bookmarks'),
                Tab(text: 'View profiles'),
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
                              child: const Text('Retry'),
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
          child: const Text('Import'),
        ),
        TextButton(
          onPressed: _busy || _catalog == null
              ? null
              : () => _exchange(importing: false),
          child: const Text('Export'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _groups() => ListView(
    padding: const EdgeInsets.only(top: 12),
    children: [
      const Text(
        'Save both panes, their tab order, accounts, locks, views and layout. Unavailable accounts stay unavailable when a group opens.',
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy ? null : _saveGroup,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save current tab group'),
        ),
      ),
      if (_catalog!.groups.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No saved tab groups yet.'),
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
        const Text(
          'Open two saved locations together. Both original accounts are checked before either pane changes. Locked tabs are preserved.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy ? null : _savePair,
            icon: const Icon(Icons.bookmarks_outlined),
            label: const Text('Save current pair'),
          ),
        ),
        if (_catalog!.pairs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No paired bookmarks yet.'),
          ),
        for (var i = 0; i < _catalog!.pairs.length; i++)
          _pairCard(_catalog!.pairs[i], i),
        const Divider(),
        const Text(
          'Single locations',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => togglePanelBookmark(context, ref, widget.side),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Toggle current bookmark'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _exchangeBookmarks(importing: true),
              child: const Text('Import bookmarks'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _exchangeBookmarks(importing: false),
              child: const Text('Export bookmarks'),
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
                        ? 'Saved collection'
                        : bookmark.storage == null
                        ? 'Original source not yet bound'
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
                          child: const Text('Open in this pane'),
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
                          child: const Text('Bind original source…'),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _renameBookmark(bookmark),
                        child: const Text('Rename'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => removeBookmark(context, ref, bookmark),
                        child: const Text('Remove'),
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
      const Text(
        'Save display mode, ordered columns, widths, metadata fields, sorting and a manual filter. Each tab keeps its own view.',
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy ? null : _saveProfile,
          icon: const Icon(Icons.view_column_outlined),
          label: const Text('Create view profile'),
        ),
      ),
      if (_catalog!.profiles.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No saved view profiles yet.'),
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
                tooltip: 'Manage ${item.name}',
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
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'update', child: Text(updateLabel)),
                  if (index > 0)
                    const PopupMenuItem(value: 'up', child: Text('Move up')),
                  if (index + 1 < count)
                    const PopupMenuItem(
                      value: 'down',
                      child: Text('Move down'),
                    ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Delete saved item'),
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
    details:
        'Left: ${group.left.tabs.length} tabs · ${_location(group.left.tabs[group.left.activeIndex])}\nRight: ${group.right.tabs.length} tabs · ${_location(group.right.tabs[group.right.activeIndex])}',
    update: () => _saveGroup(existing: group),
    remove: () => _store.removeGroup(group.id),
    actions: [
      TextButton(
        onPressed: _busy
            ? null
            : () => _run(() => _controller.openGroup(group)),
        child: const Text('Append tabs'),
      ),
      TextButton(
        onPressed: _busy ? null : () => _replaceGroup(group),
        child: const Text('Replace tabs…'),
      ),
    ],
  );

  Widget _pairCard(PairedBookmark pair, int index) => _card(
    item: pair,
    section: 'pairs',
    index: index,
    count: _catalog!.pairs.length,
    details: 'Left: ${_location(pair.left)}\nRight: ${_location(pair.right)}',
    update: () => _savePair(existing: pair),
    remove: () => _store.removePair(pair.id),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => _run(() => _controller.openPair(pair)),
        child: const Text('Open pair'),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => _run(() => _controller.openPair(pair, newTabs: true)),
        child: const Text('Open in new tabs'),
      ),
    ],
  );

  Widget _profileCard(SavedViewProfile profile, int index) => _card(
    item: profile,
    section: 'profiles',
    index: index,
    count: _catalog!.profiles.length,
    details:
        '${profile.configuration.display.name} · ${profile.configuration.columns.map((column) => column.label).join(', ')}',
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
        child: const Text('Apply to this pane'),
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
        child: const Text('Apply to both panes'),
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
      setState(() => _error = 'Enter a name with 1–160 characters.');
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
      decoration: InputDecoration(labelText: 'Name', errorText: _error),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
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
    title: const Text('Replace current tabs'),
    content: CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: _keepProtected,
      onChanged: (value) => setState(() => _keepProtected = value ?? true),
      title: const Text('Keep pinned and locked tabs'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _keepProtected),
        child: const Text('Replace tabs'),
      ),
    ],
  );
}
