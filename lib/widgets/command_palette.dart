// lib/widgets/command_palette.dart
//
// Quick-search command palette (Ctrl+Shift+P).
// Lists all available actions, type to filter, Enter to execute.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/pdf_operations_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../screens/screen_dialogs.dart'
    show
        showGoToDialog,
        showMultiRenameFromSelection,
        showCopyDialogFromSelection,
        showMoveDialogFromSelection,
        uploadSelected,
        downloadSelected;
import 'pattern_selection_dialog.dart';
import 'file_list_dialog.dart';
import 'file_collections_dialog.dart';
import 'rename_history_dialog.dart';
import 'trash_history_dialog.dart';
import 'transfer_history_dialog.dart';
import 'integrity_dialogs.dart';
import 'directory_comparison_dialog.dart';
import 'file_clipboard_actions.dart';
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

  const CommandPalette({super.key, required this.parentContext});

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<_Command> _filtered = [];
  int _selectedIndex = 0;

  late final List<_Command> _allCommands;

  @override
  void initState() {
    super.initState();
    _allCommands = _buildCommands();
    _filtered = _allCommands;
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<_Command> _buildCommands() {
    final side = ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(side));
    final auth = ref.read(authProvider);
    final pdfFiles = panel.selection.isNotEmpty
        ? panel.selection.toList()
        : <FileItem>[if (panel.cursorItem case final file?) file];

    return [
      // Navigation
      _Command(
        name: 'Navigate Up',
        shortcut: 'Backspace',
        icon: Icons.arrow_upward,
        action: () => panel.navigateUp(),
      ),
      _Command(
        name: 'Refresh Panel',
        shortcut: 'Ctrl+R',
        icon: Icons.refresh,
        action: () => panel.refresh(),
      ),
      _Command(
        name: 'Switch Panel',
        shortcut: 'Tab',
        icon: Icons.swap_horiz,
        action: () {
          ref.read(activePanelProvider.notifier).state = side == PanelSide.local
              ? PanelSide.remote
              : PanelSide.local;
        },
      ),
      _Command(
        name: 'Open Local Folder',
        icon: Icons.folder_open,
        action: () =>
            ref.read(panelProvider(PanelSide.local)).pickLocalDirectory(),
      ),

      // Go to path
      _Command(
        name: 'Go to Path',
        shortcut: 'Ctrl+G',
        icon: Icons.folder_open,
        action: () {
          showGoToDialog(widget.parentContext, ref);
        },
      ),

      // Selection
      _Command(
        name: 'Select by Wildcard or Regex',
        shortcut: 'Num +',
        icon: Icons.rule,
        action: () =>
            showPatternSelectionDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: 'Deselect by Wildcard or Regex',
        shortcut: 'Num -',
        icon: Icons.deselect,
        action: () => showPatternSelectionDialog(
          widget.parentContext,
          ref,
          side,
          initialAction: SelectionAction.deselect,
        ),
      ),
      _Command(
        name: 'Multi-Rename',
        shortcut: 'Ctrl+M',
        icon: Icons.drive_file_rename_outline,
        action: () => showMultiRenameFromSelection(widget.parentContext, ref),
      ),
      _Command(
        name: 'Copy with Options',
        shortcut: 'F5',
        icon: Icons.copy,
        action: () => showCopyDialogFromSelection(widget.parentContext, ref),
      ),
      _Command(
        name: 'Move with Options',
        shortcut: 'F6',
        icon: Icons.drive_file_move,
        action: () => showMoveDialogFromSelection(widget.parentContext, ref),
      ),
      _Command(
        name: 'Copy Files to Clipboard',
        shortcut: 'Ctrl+C',
        icon: Icons.content_copy,
        action: () => copyFilesToClipboard(widget.parentContext, ref, side),
      ),
      _Command(
        name: 'Cut Files to Clipboard',
        shortcut: 'Ctrl+X',
        icon: Icons.content_cut,
        action: () =>
            copyFilesToClipboard(widget.parentContext, ref, side, cut: true),
      ),
      _Command(
        name: 'Paste Files with Options',
        shortcut: 'Ctrl+V',
        icon: Icons.content_paste,
        action: () => pasteFilesFromClipboard(widget.parentContext, ref, side),
      ),
      _Command(
        name: 'Import File List',
        shortcut: 'Ctrl+Shift+L',
        icon: Icons.playlist_add,
        action: () => showFileListDialog(
          widget.parentContext,
          ref,
          side,
          importMode: true,
        ),
      ),
      _Command(
        name: 'Export File List',
        icon: Icons.playlist_play,
        action: () => showFileListDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: 'Trash History and Restore Original Items',
        icon: Icons.restore_from_trash,
        action: () => showTrashHistoryDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: 'Rename History, Batch Undo and Recovery',
        icon: Icons.history,
        action: () => showRenameHistoryDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: 'Transfer Queue, History and Recovery',
        icon: Icons.pending_actions,
        action: () => showTransferHistoryDialog(widget.parentContext, ref),
      ),
      _Command(
        name: 'Create or Verify Checksums',
        icon: Icons.verified_outlined,
        action: () =>
            showChecksumToolsDialog(widget.parentContext, ref, side, pdfFiles),
      ),
      if (pdfFiles.length == 1 && !pdfFiles.single.isFolder)
        _Command(
          name: 'Split File into Verified Parts',
          icon: Icons.splitscreen,
          action: () => showSplitFileDialog(
            widget.parentContext,
            ref,
            side,
            pdfFiles.single,
          ),
        ),
      if (pdfFiles.isNotEmpty && pdfFiles.every((file) => !file.isFolder))
        _Command(
          name: 'Combine Parts or Split Manifest',
          icon: Icons.join_inner,
          action: () =>
              showCombinePartsDialog(widget.parentContext, ref, side, pdfFiles),
        ),
      _Command(
        name: 'Save or Manage File Collections',
        icon: Icons.collections_bookmark_outlined,
        action: () =>
            showFileCollectionsDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: 'Compare Folders and Review Changes',
        icon: Icons.compare_arrows,
        action: () => showDirectoryComparisonDialog(widget.parentContext, ref),
      ),
      _Command(
        name: 'Remember Selection',
        icon: Icons.bookmark_add_outlined,
        action: () => panel.rememberSelection(),
      ),
      _Command(
        name: 'Restore Selection',
        icon: Icons.restore,
        action: () => panel.restoreSelection(),
      ),
      if (panel.showingSearchResults)
        _Command(
          name: 'Refresh Collection Items',
          icon: Icons.refresh,
          action: () => panel.refresh(),
        ),
      _Command(
        name: 'Select All',
        shortcut: 'Ctrl+A',
        icon: Icons.select_all,
        action: () => panel.selectAll(),
      ),
      _Command(
        name: 'Clear Selection',
        shortcut: 'Esc',
        icon: Icons.deselect,
        action: () => panel.clearSelection(),
      ),

      // Tabs
      _Command(
        name: 'New Tab',
        shortcut: 'Ctrl+T',
        icon: Icons.add,
        action: () => panel.addTab(),
      ),
      _Command(
        name: 'Close Tab',
        shortcut: 'Ctrl+W',
        icon: Icons.close,
        action: () {
          panel.closeTab(panel.activeTabId);
        },
      ),

      // Transfers
      if (auth.isConnected &&
          ref.read(panelProvider(PanelSide.local)).selection.isNotEmpty)
        _Command(
          name: 'Upload Selected',
          shortcut: 'Ctrl+U',
          icon: Icons.upload,
          action: () => uploadSelected(widget.parentContext, ref),
        ),
      if (auth.isConnected &&
          ref.read(panelProvider(PanelSide.remote)).selection.isNotEmpty)
        _Command(
          name: 'Download Selected',
          shortcut: 'Ctrl+D',
          icon: Icons.download,
          action: () => downloadSelected(widget.parentContext, ref),
        ),

      // View
      _Command(
        name: 'Toggle Preview',
        shortcut: 'Space',
        icon: Icons.visibility,
        action: () {
          ref.read(showPreviewProvider.notifier).state = !ref.read(
            showPreviewProvider,
          );
        },
      ),

      // Operations
      if (pdfFiles.length == 1 &&
          !pdfFiles.single.isFolder &&
          isPdfFileName(pdfFiles.single.name))
        _Command(
          name: widget.parentContext.pdfOpTr('Edit PDF'),
          icon: Icons.edit_document,
          action: () {
            if (widget.parentContext.mounted) {
              showPdfEditorDialog(
                widget.parentContext,
                ref,
                pdfFiles.single,
                side,
              );
            }
          },
        ),
      for (final action in pdfOperationsForSelection(pdfFiles))
        _Command(
          name: widget.parentContext.pdfOpTr(action.label),
          icon: action.icon,
          action: () {
            if (widget.parentContext.mounted) {
              showPdfOperationsDialog(
                widget.parentContext,
                ref,
                pdfFiles,
                side,
                action,
              );
            }
          },
        ),
      _Command(
        name: 'Clear Completed Operations',
        icon: Icons.cleaning_services,
        action: () => ref.read(transferProvider).clearCompletedOperations(),
      ),

      // Connection
      if (!auth.isConnected)
        _Command(
          name: 'Connect to Cloud',
          icon: Icons.cloud,
          action: () {},
        ), // handled by caller
      if (auth.isConnected)
        _Command(
          name: 'Disconnect',
          icon: Icons.cloud_off,
          action: () => ref.read(authProvider).logout(),
        ),

      // Sorting
      ...[SortBy.name, SortBy.size, SortBy.date, SortBy.extension].map(
        (sort) => _Command(
          name: 'Sort by ${sort.name}',
          icon: Icons.sort,
          action: () => panel.setSortBy(sort),
        ),
      ),
      _Command(
        name: 'Toggle Sort Order',
        icon: Icons.swap_vert,
        action: () => panel.toggleSortOrder(),
      ),

      // Panel actions
      _Command(
        name: 'Refresh Local Panel',
        icon: Icons.refresh,
        action: () => ref.read(panelProvider(PanelSide.local)).refresh(),
      ),
      _Command(
        name: 'Refresh Remote Panel',
        icon: Icons.refresh,
        action: () => ref.read(panelProvider(PanelSide.remote)).refresh(),
      ),
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
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    setState(() {
                      _selectedIndex = (_selectedIndex + 1).clamp(
                        0,
                        _filtered.length - 1,
                      );
                    });
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    setState(() {
                      _selectedIndex = (_selectedIndex - 1).clamp(
                        0,
                        _filtered.length - 1,
                      );
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
                    hintText: 'Type a command...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                      child: Text(
                        'No matching commands',
                        style: TextStyle(color: theme.disabledColor),
                      ),
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
                                ? theme.colorScheme.primaryContainer.withValues(
                                    alpha: 0.5,
                                  )
                                : null,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  cmd.icon,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    cmd.name,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                if (cmd.shortcut != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      cmd.shortcut!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
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
    builder: (_) => CommandPalette(parentContext: context),
  );
}
