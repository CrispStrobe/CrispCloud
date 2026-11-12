import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../l10n/browser_menu_strings.dart';
import '../l10n/commander_strings.dart';
import '../models/browser_menu_layout.dart';
import '../providers/browser_menu_provider.dart';
import 'configurable_browser_menu.dart';

Future<void> showBrowserMenuEditor(
  BuildContext context,
  WidgetRef ref,
  Map<String, BrowserMenuCommandBinding> commands, {
  bool resetDraft = false,
}) async {
  await ref.read(browserMenuStoreProvider).ready;
  if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) return;
  await showDialog<void>(
    context: context,
    builder: (_) =>
        BrowserMenuEditor(commands: commands, resetDraft: resetDraft),
  );
}

class BrowserMenuEditor extends ConsumerStatefulWidget {
  const BrowserMenuEditor({
    super.key,
    required this.commands,
    this.resetDraft = false,
  });
  final Map<String, BrowserMenuCommandBinding> commands;
  final bool resetDraft;
  @override
  ConsumerState<BrowserMenuEditor> createState() => _BrowserMenuEditorState();
}

class _BrowserMenuEditorState extends ConsumerState<BrowserMenuEditor> {
  late BrowserMenuLayout _draft;
  String _parent = '';
  String? _errorKey;
  bool _saving = false;
  BrowserMenuStrings get strings => BrowserMenuStrings(context);
  List<BrowserMenuNode> get entries =>
      _parent.isEmpty ? _draft.menus : _draft.find(_parent)!.children;
  @override
  void initState() {
    super.initState();
    _draft = widget.resetDraft
        ? BrowserMenuLayout.defaults()
        : ref.read(browserMenuStoreProvider).layout;
  }

  void _change(BrowserMenuLayout next) {
    try {
      next.encode();
      setState(() {
        _draft = next;
        _errorKey = null;
      });
    } catch (_) {
      setState(() => _errorKey = 'invalid');
    }
  }

  void _update(List<BrowserMenuNode> next) =>
      _change(_draft.updateChildren(_parent.isEmpty ? null : _parent, next));
  String _newId() => 'menu-${const Uuid().v4()}';

  Future<void> _addMenu() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _MenuNameDialog(initial: strings.text('newMenu')),
    );
    if (!mounted || name == null) return;
    _update([
      ...entries,
      BrowserMenuNode(
        id: _newId(),
        kind: BrowserMenuNodeKind.submenu,
        label: name,
      ),
    ]);
  }

  Future<void> _addCommand() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _MenuCommandPicker(commands: widget.commands),
    );
    if (!mounted || id == null) return;
    _update([
      ...entries,
      BrowserMenuNode(
        id: _newId(),
        kind: BrowserMenuNodeKind.command,
        commandId: id,
      ),
    ]);
  }

  void _reorder(int index, int offset) {
    final next = [...entries];
    final entry = next.removeAt(index);
    next.insert(index + offset, entry);
    _update(next);
  }

  Future<void> _entryAction(BrowserMenuNode entry, String action) async {
    if (action == 'remove') {
      _update(entries.where((node) => node.id != entry.id).toList());
    } else if (action == 'rename') {
      final label = await showDialog<String>(
        context: context,
        builder: (_) => _MenuNameDialog(initial: strings.title(entry)),
      );
      if (mounted && label != null) {
        _update([
          for (final node in entries)
            node.id == entry.id ? node.renamed(label) : node,
        ]);
      }
    } else if (action == 'move') {
      final excluded = <String>{entry.id};
      void descendants(BrowserMenuNode node) {
        for (final child in node.children) {
          excluded.add(child.id);
          descendants(child);
        }
      }

      descendants(entry);
      final parents = _draft.nodes.where(
        (node) =>
            node.kind == BrowserMenuNodeKind.submenu &&
            !excluded.contains(node.id) &&
            node.id != _parent,
      );
      final target = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(strings.text('move')),
          children: [
            if (_parent.isNotEmpty && entry.kind == BrowserMenuNodeKind.submenu)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, ''),
                child: Text(strings.text('root')),
              ),
            for (final parent in parents)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, parent.id),
                child: Text(strings.title(parent)),
              ),
          ],
        ),
      );
      if (!mounted || target == null) return;
      final without = _draft.updateChildren(
        _parent.isEmpty ? null : _parent,
        entries.where((node) => node.id != entry.id).toList(),
      );
      final targetEntries = target.isEmpty
          ? without.menus
          : without.find(target)!.children;
      _change(
        without.updateChildren(target.isEmpty ? null : target, [
          ...targetEntries,
          entry,
        ]),
      );
    }
  }

  Future<void> _import() async {
    final imported = await showDialog<BrowserMenuLayout>(
      context: context,
      builder: (_) => const _MenuImportDialog(),
    );
    if (!mounted || imported == null) return;
    setState(() {
      _draft = imported;
      _parent = '';
      _errorKey = null;
    });
  }

  Future<void> _export() async {
    final json = _draft.encode();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.commanderTr('Export')),
        content: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(context).height * .55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.text('exportHint')),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(child: SelectableText(json)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.commanderTr('Close')),
          ),
          FilledButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: json)),
            icon: const Icon(Icons.copy),
            label: Text(context.commanderTr('Copy')),
          ),
        ],
      ),
    );
  }

  Future<void> _preview() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.text('preview')),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .6,
        ),
        child: SingleChildScrollView(
          child: SizedBox(
            width: 760,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.text('permanent')),
                const SizedBox(height: 12),
                ConfigurableBrowserMenu(
                  layout: _draft,
                  commands: widget.commands,
                  fixedCommands: const [],
                  preview: true,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.commanderTr('Close')),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      await ref.read(browserMenuStoreProvider).save(_draft);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorKey = 'saveFailed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = entries;
    final store = ref.watch(browserMenuStoreProvider);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(strings.text('title')),
        content: SizedBox(
          width: 790,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.text('permanent')),
              if (store.recovered)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(strings.text('recovered')),
                ),
              if (_errorKey != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    strings.text(_errorKey!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('browser-menu-parent-$_parent'),
                initialValue: _parent,
                isExpanded: true,
                decoration: InputDecoration(labelText: strings.text('parent')),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(strings.text('root')),
                  ),
                  for (final node in _draft.nodes.where(
                    (node) => node.kind == BrowserMenuNodeKind.submenu,
                  ))
                    DropdownMenuItem(
                      value: node.id,
                      child: Text(
                        strings.title(node),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _parent = value);
                      },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    key: const ValueKey('browser-menu-add-submenu'),
                    onPressed: _saving ? null : _addMenu,
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 18,
                    ),
                    label: Text(strings.text('addMenu')),
                  ),
                  TextButton.icon(
                    key: const ValueKey('browser-menu-add-command'),
                    onPressed: _saving || _parent.isEmpty ? null : _addCommand,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(strings.text('addCommand')),
                  ),
                  TextButton.icon(
                    onPressed: _saving || _parent.isEmpty
                        ? null
                        : () => _update([
                            ...entries,
                            BrowserMenuNode(
                              id: _newId(),
                              kind: BrowserMenuNodeKind.separator,
                            ),
                          ]),
                    icon: const Icon(Icons.horizontal_rule, size: 18),
                    label: Text(strings.text('addSeparator')),
                  ),
                ],
              ),
              Column(
                children: List.generate(current.length, (index) {
                  final entry = current[index];
                  final label = switch (entry.kind) {
                    BrowserMenuNodeKind.separator => strings.text('separator'),
                    BrowserMenuNodeKind.submenu => strings.title(entry),
                    BrowserMenuNodeKind.command =>
                      widget.commands[entry.commandId]?.label ??
                          strings.unavailable(entry.commandId!),
                  };
                  return ListTile(
                    key: ValueKey('browser-menu-edit-${entry.id}'),
                    dense: true,
                    contentPadding: const EdgeInsetsDirectional.only(start: 4),
                    title: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: entry.commandId == null
                        ? null
                        : Text(
                            entry.commandId!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    leading: Icon(
                      entry.kind == BrowserMenuNodeKind.submenu
                          ? Icons.folder_outlined
                          : entry.kind == BrowserMenuNodeKind.command
                          ? Icons.play_arrow_outlined
                          : Icons.horizontal_rule,
                    ),
                    onTap: !_saving && entry.kind == BrowserMenuNodeKind.submenu
                        ? () => setState(() => _parent = entry.id)
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: strings.text('up'),
                          onPressed: _saving || index == 0
                              ? null
                              : () => _reorder(index, -1),
                          icon: const Icon(Icons.arrow_upward, size: 18),
                        ),
                        IconButton(
                          tooltip: strings.text('down'),
                          onPressed: _saving || index == current.length - 1
                              ? null
                              : () => _reorder(index, 1),
                          icon: const Icon(Icons.arrow_downward, size: 18),
                        ),
                        PopupMenuButton<String>(
                          enabled: !_saving,
                          onSelected: (action) => _entryAction(entry, action),
                          itemBuilder: (_) => [
                            if (entry.kind == BrowserMenuNodeKind.submenu)
                              PopupMenuItem(
                                value: 'rename',
                                child: Text(context.commanderTr('Rename')),
                              ),
                            PopupMenuItem(
                              value: 'move',
                              child: Text(strings.text('move')),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text(context.commanderTr('Remove')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _import,
            child: Text(context.commanderTr('Import')),
          ),
          TextButton(
            onPressed: _saving ? null : _export,
            child: Text(context.commanderTr('Export')),
          ),
          TextButton(
            onPressed: _saving
                ? null
                : () => setState(() {
                    _draft = BrowserMenuLayout.defaults();
                    _parent = '';
                    _errorKey = null;
                  }),
            child: Text(strings.text('reset')),
          ),
          TextButton(
            onPressed: _saving ? null : _preview,
            child: Text(strings.text('preview')),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(context.commanderTr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('browser-menu-save'),
            onPressed: _saving ? null : _save,
            child: Text(context.commanderTr('Save')),
          ),
        ],
      ),
    );
  }
}

class _MenuNameDialog extends StatefulWidget {
  const _MenuNameDialog({required this.initial});
  final String initial;
  @override
  State<_MenuNameDialog> createState() => _MenuNameDialogState();
}

class _MenuNameDialogState extends State<_MenuNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(BrowserMenuStrings(context).text('label')),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) {
        if (_controller.text.trim().isNotEmpty) {
          Navigator.pop(context, _controller.text.trim());
        }
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.commanderTr('Cancel')),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: Text(context.commanderTr('Save')),
      ),
    ],
  );
}

class _MenuCommandPicker extends StatefulWidget {
  const _MenuCommandPicker({required this.commands});
  final Map<String, BrowserMenuCommandBinding> commands;
  @override
  State<_MenuCommandPicker> createState() => _MenuCommandPickerState();
}

class _MenuCommandPickerState extends State<_MenuCommandPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final strings = BrowserMenuStrings(context);
    final commands =
        widget.commands.values
            .where(
              (command) =>
                  command.label.toLowerCase().contains(_query) ||
                  command.id.toLowerCase().contains(_query),
            )
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
    return AlertDialog(
      title: Text(strings.text('choose')),
      content: SizedBox(
        width: 540,
        height: MediaQuery.sizeOf(context).height * .5,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('browser-menu-command-search'),
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.commanderTr('Search'),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            Expanded(
              child: commands.isEmpty
                  ? Center(child: Text(strings.text('empty')))
                  : ListView.builder(
                      itemCount: commands.length,
                      itemBuilder: (context, index) {
                        final command = commands[index];
                        return ListTile(
                          key: ValueKey('browser-menu-pick-${command.id}'),
                          title: Text(command.label),
                          subtitle: Text(command.id),
                          onTap: () => Navigator.pop(context, command.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.commanderTr('Cancel')),
        ),
      ],
    );
  }
}

class _MenuImportDialog extends StatefulWidget {
  const _MenuImportDialog();
  @override
  State<_MenuImportDialog> createState() => _MenuImportDialogState();
}

class _MenuImportDialogState extends State<_MenuImportDialog> {
  final _controller = TextEditingController();
  bool _invalid = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = BrowserMenuStrings(context);
    return AlertDialog(
      title: Text(context.commanderTr('Import')),
      content: SizedBox(
        width: 640,
        height: MediaQuery.sizeOf(context).height * .5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.text('importHint')),
            const SizedBox(height: 8),
            if (_invalid)
              Text(
                strings.text('invalid'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Expanded(
              child: TextField(
                key: const ValueKey('browser-menu-import-json'),
                controller: _controller,
                maxLines: null,
                expands: true,
                maxLength: BrowserMenuLayout.maxBytes,
                decoration: const InputDecoration(labelText: 'JSON'),
                textAlignVertical: TextAlignVertical.top,
              ),
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
          key: const ValueKey('browser-menu-import-apply'),
          onPressed: () {
            try {
              Navigator.pop(
                context,
                BrowserMenuLayout.decode(_controller.text),
              );
            } catch (_) {
              setState(() => _invalid = true);
            }
          },
          child: Text(context.commanderTr('Import')),
        ),
      ],
    );
  }
}
