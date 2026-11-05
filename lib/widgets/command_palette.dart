// lib/widgets/command_palette.dart
//
// Quick-search command palette (Ctrl+Shift+P).
// Lists all available actions, type to filter, Enter to execute.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/pdf_operations_strings.dart';
import '../l10n/command_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../screens/screen_dialogs.dart' show showGoToDialog;
import 'pdf_editor_dialog.dart';
import 'pdf_operations_dialog.dart';

class _Command {
  final String name;
  final String? shortcut;
  final IconData icon;
  final VoidCallback action;

  const _Command({
    required this.name,
    this.shortcut,
    required this.icon,
    required this.action,
  });
}

class CommandPalette extends ConsumerStatefulWidget {
  final BuildContext parentContext;

  const CommandPalette({
    super.key,
    required this.parentContext,
  });

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<_Command> _filtered = [];
  int _selectedIndex = 0;

  List<_Command> _allCommands = [];

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _allCommands = _buildCommands();
    final query = _controller.text.toLowerCase();
    _filtered = query.isEmpty ? _allCommands : _allCommands
        .where((command) => command.name.toLowerCase().contains(query)).toList();
    _selectedIndex = 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<_Command> _buildCommands() {
    final strings = CommandStrings(context);
    final side = ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(side));
    final auth = ref.read(authProvider);
    final pdfFiles = panel.selection.isNotEmpty
        ? panel.selection.toList()
        : <FileItem>[if (panel.cursorItem case final file?) file];

    return [
      // Navigation
      _Command(name: strings.text('up'), shortcut: 'Backspace', icon: Icons.arrow_upward, action: () => panel.navigateUp()),
      _Command(name: strings.text('refresh'), shortcut: 'F5', icon: Icons.refresh, action: () => panel.refresh()),
      _Command(name: strings.text('switch'), shortcut: 'Tab', icon: Icons.swap_horiz, action: () {
        ref.read(activePanelProvider.notifier).state =
            side == PanelSide.local ? PanelSide.remote : PanelSide.local;
      }),
      _Command(name: strings.text('localFolder'), icon: Icons.folder_open, action: () => ref.read(panelProvider(PanelSide.local)).pickLocalDirectory()),

      // Go to path
      _Command(name: strings.text('goPath'), shortcut: 'Ctrl+G', icon: Icons.folder_open, action: () {
        showGoToDialog(widget.parentContext, ref);
      }),

      // Selection
      _Command(name: strings.text('selectAll'), shortcut: 'Ctrl+A', icon: Icons.select_all, action: () => panel.selectAll()),
      _Command(name: strings.text('clearSelection'), shortcut: 'Esc', icon: Icons.deselect, action: () => panel.clearSelection()),

      // Tabs
      _Command(name: strings.text('newTab'), shortcut: 'Ctrl+T', icon: Icons.add, action: () => panel.addTab()),
      _Command(name: strings.text('closeTab'), shortcut: 'Ctrl+W', icon: Icons.close, action: () {
        panel.closeTab(panel.activeTabId);
      }),

      // Transfers
      if (auth.isConnected && ref.read(panelProvider(PanelSide.local)).selection.isNotEmpty)
        _Command(name: strings.text('upload'), shortcut: 'Ctrl+U', icon: Icons.upload, action: () =>
            ref.read(transferProvider).uploadFiles(ref.read(panelProvider(PanelSide.local)).selection.toList())),
      if (auth.isConnected && ref.read(panelProvider(PanelSide.remote)).selection.isNotEmpty)
        _Command(name: strings.text('download'), shortcut: 'Ctrl+D', icon: Icons.download, action: () =>
            ref.read(transferProvider).downloadFiles(ref.read(panelProvider(PanelSide.remote)).selection.toList())),

      // View
      _Command(name: strings.text('preview'), shortcut: 'Space', icon: Icons.visibility, action: () {
        ref.read(showPreviewProvider.notifier).state = !ref.read(showPreviewProvider);
      }),

      // Operations
      if (pdfFiles.length == 1 && !pdfFiles.single.isFolder && isPdfFileName(pdfFiles.single.name))
        _Command(name: widget.parentContext.pdfOpTr('Edit PDF'), icon: Icons.edit_document, action: () {
          if (widget.parentContext.mounted) showPdfEditorDialog(widget.parentContext, ref, pdfFiles.single, side);
        }),
      for (final action in pdfOperationsForSelection(pdfFiles))
        _Command(name: widget.parentContext.pdfOpTr(action.label), icon: action.icon, action: () {
          if (widget.parentContext.mounted) showPdfOperationsDialog(widget.parentContext, ref, pdfFiles, side, action);
        }),
      _Command(name: strings.text('clearOps'), icon: Icons.cleaning_services, action: () =>
          ref.read(transferProvider).clearCompletedOperations()),

      // Connection
      if (!auth.isConnected)
        _Command(name: strings.text('connect'), icon: Icons.cloud, action: () {}), // handled by caller
      if (auth.isConnected)
        _Command(name: strings.text('disconnect'), icon: Icons.cloud_off, action: () => ref.read(authProvider).logout()),

      // Sorting
      ...[SortBy.name, SortBy.size, SortBy.date, SortBy.extension].map((sort) =>
        _Command(
          name: strings.text(switch (sort) {
            SortBy.name => 'sortName',
            SortBy.size => 'sortSize',
            SortBy.date => 'sortDate',
            SortBy.extension => 'sortExtension',
          }),
          icon: Icons.sort,
          action: () => panel.setSortBy(sort),
        ),
      ),
      _Command(name: strings.text('sortOrder'), icon: Icons.swap_vert, action: () => panel.toggleSortOrder()),

      // Panel actions
      _Command(name: strings.text('refreshLocal'), icon: Icons.refresh, action: () => ref.read(panelProvider(PanelSide.local)).refresh()),
      _Command(name: strings.text('refreshRemote'), icon: Icons.refresh, action: () => ref.read(panelProvider(PanelSide.remote)).refresh()),
    ];
  }

  void _onQueryChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = _allCommands;
      } else {
        final lower = query.toLowerCase();
        _filtered = _allCommands
            .where((c) => c.name.toLowerCase().contains(lower))
            .toList();
      }
      _selectedIndex = 0;
    });
  }

  void _executeSelected() {
    if (_filtered.isNotEmpty && _selectedIndex < _filtered.length) {
      Navigator.of(context).pop();
      _filtered[_selectedIndex].action();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 80, left: 80, right: 80),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search field
            Padding(
              padding: const EdgeInsets.all(8),
              child: Focus(
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  if (_filtered.isEmpty && (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                      event.logicalKey == LogicalKeyboardKey.arrowUp)) return KeyEventResult.handled;
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    setState(() {
                      _selectedIndex = (_selectedIndex + 1).clamp(0, _filtered.length - 1);
                    });
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    setState(() {
                      _selectedIndex = (_selectedIndex - 1).clamp(0, _filtered.length - 1);
                    });
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.enter) {
                    _executeSelected();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.of(context).pop();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: CommandStrings(context).text('query'),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: _onQueryChanged,
                ),
              ),
            ),
            // Results
            Flexible(
              child: _filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(CommandStrings(context).text('noCommands'),
                          style: TextStyle(color: theme.disabledColor)),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        final cmd = _filtered[index];
                        final isSelected = index == _selectedIndex;

                        return InkWell(
                          onTap: () {
                            setState(() => _selectedIndex = index);
                            _executeSelected();
                          },
                          child: Container(
                            color: isSelected
                                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                                : null,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                Icon(cmd.icon, size: 18,
                                    color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(cmd.name,
                                      style: const TextStyle(fontSize: 13)),
                                ),
                                if (cmd.shortcut != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      cmd.shortcut!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
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
    );
  }
}

/// Show the command palette.
void showCommandPalette(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (_) => CommandPalette(
      parentContext: context,
    ),
  );
}
