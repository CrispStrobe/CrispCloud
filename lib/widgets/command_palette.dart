// lib/widgets/command_palette.dart
//
// Quick-search command palette (Ctrl+Shift+P).
// Lists all available actions, type to filter, Enter to execute.

import '../l10n/commander_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/pdf_operations_strings.dart';
import '../l10n/command_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../screens/screen_dialogs.dart'
    show
        showGoToDialog,
        showConnectionDialogScreen,
        showMultiRenameFromSelection,
        showCopyDialogFromSelection,
        showMoveDialogFromSelection,
        uploadSelected,
        downloadSelected;
import 'pattern_selection_dialog.dart';
import 'file_attributes_dialog.dart';
import 'file_list_dialog.dart';
import 'file_collections_dialog.dart';
import 'rename_history_dialog.dart';
import 'trash_history_dialog.dart';
import 'transfer_history_dialog.dart';
import 'integrity_dialogs.dart';
import 'integrity_recovery_dialog.dart';
import 'directory_comparison_dialog.dart';
import 'file_clipboard_actions.dart';
import 'pdf_editor_dialog.dart';
import 'pdf_operations_dialog.dart';
import 'workspace_dialog.dart';
import 'file_view_editor_dialog.dart';
import 'custom_command_dialog.dart';
import 'extensions_dialog.dart';
import '../l10n/extension_translations.dart';

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
  final WidgetRef actionRef;

  const CommandPalette({
    super.key,
    required this.parentContext,
    required this.actionRef,
  });

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _selectedRow = GlobalKey();
  List<_Command> _filtered = [];
  int _selectedIndex = 0;

  List<_Command> _allCommands = const [];

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
    _filtered = _allCommands
        .where((command) => command.name.toLowerCase().contains(query))
        .toList();
    _selectedIndex = 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<_Command> _buildCommands() {
    final ref = widget.actionRef;
    final side = ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(side));
    final auth = ref.read(authProvider);
    final pdfFiles = panel.selection.isNotEmpty
        ? panel.selection.toList()
        : <FileItem>[if (panel.cursorItem case final file?) file];

    return [
      // Navigation
      _Command(
        name: context.commanderTr("Navigate Up"),
        shortcut: 'Backspace',
        icon: Icons.arrow_upward,
        action: () => panel.navigateUp(),
      ),
      _Command(
        name: context.commanderTr("Refresh Panel"),
        shortcut: 'Ctrl+R',
        icon: Icons.refresh,
        action: () => panel.refresh(),
      ),
      _Command(
        name: context.commanderTr("Switch Panel"),
        shortcut: 'Tab',
        icon: Icons.swap_horiz,
        action: () {
          ref.read(activePanelProvider.notifier).state = side == PanelSide.local
              ? PanelSide.remote
              : PanelSide.local;
        },
      ),
      _Command(
        name: context.commanderTr("Open Local Folder"),
        icon: Icons.folder_open,
        action: () =>
            ref.read(panelProvider(PanelSide.local)).pickLocalDirectory(),
      ),

      // Go to path
      _Command(
        name: context.commanderTr("Go to Path"),
        shortcut: 'Ctrl+G',
        icon: Icons.folder_open,
        action: () {
          showGoToDialog(widget.parentContext, ref);
        },
      ),

      _Command(
        name: context.commanderTr("Commander workspaces"),
        icon: Icons.bookmarks_outlined,
        action: () => showWorkspaceDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: context.commanderTr("Columns and view"),
        icon: Icons.view_column_outlined,
        action: () => showPanelViewDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: context.commanderTr("Custom commands"),
        icon: Icons.terminal,
        action: () => showCustomCommandsDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: context.extensionTr('Extensions'),
        icon: Icons.extension,
        action: () => showExtensionsDialog(widget.parentContext, ref, side),
      ),

      // Selection
      _Command(
        name: context.commanderTr("Select by Wildcard or Regex"),
        shortcut: 'Num +',
        icon: Icons.rule,
        action: () =>
            showPatternSelectionDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: context.commanderTr("Deselect by Wildcard or Regex"),
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
        name: context.commanderTr("Same extension"),
        shortcut: 'Shift+Num +',
        icon: Icons.library_add_check,
        action: () => panel.selectSameExtension(),
      ),
      _Command(
        name: context.commanderTr("Same name (without extension)"),
        icon: Icons.checklist,
        action: () => panel.selectSameName(),
      ),
      _Command(
        name: context.commanderTr("Same containing folder"),
        icon: Icons.folder_copy_outlined,
        action: () => panel.selectSameParent(),
      ),
      _Command(
        name: context.commanderTr("Load selection from paths…"),
        icon: Icons.playlist_add_check,
        action: () => showFileListDialog(
          widget.parentContext,
          ref,
          side,
          selectionMode: true,
        ),
      ),
      _Command(
        name: context.commanderTr("Change attributes…"),
        icon: Icons.tune,
        action: () =>
            showFileAttributesFromSelection(widget.parentContext, ref),
      ),
      _Command(
        name: context.commanderTr("Multi-Rename"),
        shortcut: 'Ctrl+M',
        icon: Icons.drive_file_rename_outline,
        action: () => showMultiRenameFromSelection(widget.parentContext, ref),
      ),
      _Command(
        name: context.commanderTr("Copy with Options"),
        shortcut: 'F5',
        icon: Icons.copy,
        action: () => showCopyDialogFromSelection(widget.parentContext, ref),
      ),
      _Command(
        name: context.commanderTr("Move with Options"),
        shortcut: 'F6',
        icon: Icons.drive_file_move,
        action: () => showMoveDialogFromSelection(widget.parentContext, ref),
      ),
      _Command(
        name: context.commanderTr("Copy Files to Clipboard"),
        shortcut: 'Ctrl+C',
        icon: Icons.content_copy,
        action: () => copyFilesToClipboard(widget.parentContext, ref, side),
      ),
      _Command(
        name: context.commanderTr("Cut Files to Clipboard"),
        shortcut: 'Ctrl+X',
        icon: Icons.content_cut,
        action: () =>
            copyFilesToClipboard(widget.parentContext, ref, side, cut: true),
      ),
      _Command(
        name: context.commanderTr("Paste Files with Options"),
        shortcut: 'Ctrl+V',
        icon: Icons.content_paste,
        action: () => pasteFilesFromClipboard(widget.parentContext, ref, side),
      ),
      _Command(
        name: context.commanderTr("Import File List"),
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
        name: context.commanderTr("Export File List"),
        icon: Icons.playlist_play,
        action: () => showFileListDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: context.commanderTr("Trash History and Restore Original Items"),
        icon: Icons.restore_from_trash,
        action: () => showTrashHistoryDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: context.commanderTr("Rename History, Batch Undo and Recovery"),
        icon: Icons.history,
        action: () => showRenameHistoryDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: context.commanderTr("Transfer Queue, History and Recovery"),
        icon: Icons.pending_actions,
        action: () => showTransferHistoryDialog(widget.parentContext, ref),
      ),
      _Command(
        name: context.commanderTr("Create or Verify Checksums"),
        icon: Icons.verified_outlined,
        action: () =>
            showChecksumToolsDialog(widget.parentContext, ref, side, pdfFiles),
      ),
      _Command(
        name: context.commanderTr("Split/combine recovery"),
        icon: Icons.restore,
        action: () => showIntegrityRecoveryDialog(widget.parentContext, ref),
      ),
      if (pdfFiles.length == 1 && !pdfFiles.single.isFolder)
        _Command(
          name: context.commanderTr("Split File into Verified Parts"),
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
          name: context.commanderTr("Combine Parts or Split Manifest"),
          icon: Icons.join_inner,
          action: () =>
              showCombinePartsDialog(widget.parentContext, ref, side, pdfFiles),
        ),
      _Command(
        name: context.commanderTr("Save or Manage File Collections"),
        icon: Icons.collections_bookmark_outlined,
        action: () =>
            showFileCollectionsDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: context.commanderTr("Compare Folders and Review Changes"),
        icon: Icons.compare_arrows,
        action: () => showDirectoryComparisonDialog(widget.parentContext, ref),
      ),
      _Command(
        name: context.commanderTr("Remember Selection"),
        icon: Icons.bookmark_add_outlined,
        action: () => panel.rememberSelection(),
      ),
      _Command(
        name: context.commanderTr("Restore Selection"),
        icon: Icons.restore,
        action: () => panel.restoreSelection(),
      ),
      if (panel.showingSearchResults)
        _Command(
          name: context.commanderTr("Refresh Collection Items"),
          icon: Icons.refresh,
          action: () => panel.refresh(),
        ),
      _Command(
        name: context.commanderTr("Select All"),
        shortcut: 'Ctrl+A',
        icon: Icons.select_all,
        action: () => panel.selectAll(),
      ),
      _Command(
        name: context.commanderTr("Clear Selection"),
        shortcut: 'Esc',
        icon: Icons.deselect,
        action: () => panel.clearSelection(),
      ),

      // Tabs
      _Command(
        name: context.commanderTr("New Tab"),
        shortcut: 'Ctrl+T',
        icon: Icons.add,
        action: () => panel.addTab(),
      ),
      _Command(
        name: context.commanderTr("Close Tab"),
        shortcut: 'Ctrl+W',
        icon: Icons.close,
        action: () {
          panel.closeTab(panel.activeTabId);
        },
      ),

      // Transfers
      if (ref.read(panelProvider(PanelSide.local)).selection.isNotEmpty)
        _Command(
          name: context.commanderTr("Upload Selected"),
          shortcut: 'Ctrl+U',
          icon: Icons.upload,
          action: () => uploadSelected(widget.parentContext, ref),
        ),
      if (ref.read(panelProvider(PanelSide.remote)).selection.isNotEmpty)
        _Command(
          name: context.commanderTr("Download Selected"),
          shortcut: 'Ctrl+D',
          icon: Icons.download,
          action: () => downloadSelected(widget.parentContext, ref),
        ),

      // View
      _Command(
        name: context.commanderTr("Toggle Preview"),
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
        name: context.commanderTr("Clear Completed Operations"),
        icon: Icons.cleaning_services,
        action: () => ref.read(transferProvider).clearCompletedOperations(),
      ),

      // Connection
      if (!auth.isConnected)
        _Command(
          name: context.commanderTr("Connect to Cloud"),
          icon: Icons.cloud,
          action: () => showConnectionDialogScreen(widget.parentContext),
        ),
      if (auth.isConnected)
        _Command(
          name: context.commanderTr("Disconnect"),
          icon: Icons.cloud_off,
          action: () => ref.read(authProvider).logout(),
        ),

      // Sorting
      ...[SortBy.name, SortBy.size, SortBy.date, SortBy.extension].map(
        (sort) => _Command(
          name: context.commanderTr("Sort by {0}", [
            context.commanderEnum(sort),
          ]),
          icon: Icons.sort,
          action: () => panel.setSortBy(sort),
        ),
      ),
      _Command(
        name: context.commanderTr("Toggle Sort Order"),
        icon: Icons.swap_vert,
        action: () => panel.toggleSortOrder(),
      ),

      // Panel actions
      _Command(
        name: context.commanderTr("Refresh Left Panel"),
        icon: Icons.refresh,
        action: () => ref.read(panelProvider(PanelSide.local)).refresh(),
      ),
      _Command(
        name: context.commanderTr("Refresh Right Panel"),
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

  void _moveSelection(int delta) {
    if (_filtered.isEmpty) return;
    setState(
      () => _selectedIndex = (_selectedIndex + delta).clamp(
        0,
        _filtered.length - 1,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = _selectedRow.currentContext;
      if (mounted && rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          duration: Duration.zero,
          alignmentPolicy: delta > 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }

  void _executeSelected() {
    if (_filtered.isNotEmpty && _selectedIndex < _filtered.length) {
      Navigator.of(context).pop();
      _filtered[_selectedIndex].action();
    }
  }

  Widget _commandRow(int index, ThemeData theme) {
    final command = _filtered[index];
    final selected = index == _selectedIndex;
    final compact =
        MediaQuery.sizeOf(context).width < 500 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    Widget shortcut() => DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          command.shortcut!,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    return Semantics(
      key: selected ? _selectedRow : ValueKey('command-$index'),
      button: true,
      selected: selected,
      child: InkWell(
        onTap: () {
          setState(() => _selectedIndex = index);
          _executeSelected();
        },
        child: Container(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                command.icon,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(command.name, style: const TextStyle(fontSize: 13)),
                    if (compact && command.shortcut != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: shortcut(),
                      ),
                  ],
                ),
              ),
              if (!compact && command.shortcut != null) shortcut(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.only(
        top: MediaQuery.sizeOf(context).height < 600 ? 24 : 80,
        left: MediaQuery.sizeOf(context).width < 600 ? 12 : 80,
        right: MediaQuery.sizeOf(context).width < 600 ? 12 : 80,
      ),
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
                    _moveSelection(1);
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _moveSelection(-1);
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
                    hintText: context.commanderTr("Type a command..."),
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
                        context.commanderTr("No matching commands"),
                        style: TextStyle(color: theme.disabledColor),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          for (var index = 0; index < _filtered.length; index++)
                            _commandRow(index, theme),
                        ],
                      ),
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
    builder: (_) => CommandPalette(parentContext: context, actionRef: ref),
  );
}
