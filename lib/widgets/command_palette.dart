// lib/widgets/command_palette.dart
//
// Quick-search command palette (Ctrl+Shift+P).
// Lists all available actions, type to filter, Enter to execute.

import 'dart:async';

import '../l10n/commander_strings.dart';

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
        showConnectionDialogScreen,
        confirmLogoutRiverpod,
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
import 'directory_selection_actions.dart';
import 'storage_analyzer_dialog.dart';
import 'storage_scan_batch_dialog.dart';
import '../l10n/storage_analyzer_strings.dart';
import 'file_clipboard_actions.dart';
import 'pdf_editor_dialog.dart';
import 'pdf_operations_dialog.dart';
import 'workspace_dialog.dart';
import 'path_favorites.dart';
import 'file_view_editor_dialog.dart';
import 'custom_command_dialog.dart';
import 'extensions_dialog.dart';
import '../l10n/extension_translations.dart';
import '../l10n/navigation_strings.dart';
import '../l10n/workspace_ux_strings.dart';
import '../l10n/synchronized_browsing_strings.dart';
import '../providers/synchronized_browsing_provider.dart';
import 'synchronized_browsing_controls.dart';
import '../services/keyboard_shortcut_service.dart';
import '../services/command_search.dart';
import 'keyboard_shortcut_dialog.dart';
import '../screens/keyboard_shortcuts.dart' show executeBrowserShortcut;
import '../providers/quick_open_provider.dart';
import '../providers/panel_source_provider.dart';
import '../providers/file_collection_provider.dart';
import '../services/quick_open_service.dart';
import '../l10n/quick_open_strings.dart';
import 'batch_rename_dialog.dart';
import 'drive_bar.dart';

class _Command {
  final String name;
  final String? shortcut;
  final IconData icon;
  final VoidCallback action;
  final ShortcutAction? binding;
  final String keywords;
  final bool enabled;
  final String? id;
  final String? detail;
  final String? disabledReason;
  String get identity => id ?? name;

  const _Command({
    required this.name,
    this.shortcut,
    required this.icon,
    required this.action,
    this.binding,
    this.keywords = '',
    this.enabled = true,
    this.id,
    this.detail,
    this.disabledReason,
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
    _filtered = _rankCommands(_controller.text);
    _selectedIndex = _filtered.indexWhere((command) => command.enabled);
    if (_selectedIndex < 0) _selectedIndex = 0;
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
    final hasTargets = pdfFiles.any((file) => file.name != '..');

    return [
      // Navigation
      _Command(
        name: SynchronizedBrowsingStrings(context).text(
          ref.read(synchronizedBrowsingProvider).enabled ? 'stop' : 'start',
        ),
        icon: Icons.link,
        keywords: 'linked panes folders navigation synchronized browsing',
        action: () => toggleSynchronizedBrowsing(ref),
      ),
      _Command(
        name: WorkspaceUxStrings(context).text('back'),
        binding: ShortcutAction.back,
        icon: Icons.arrow_back,
        enabled: panel.canNavigateBack,
        action: () => panel.navigateBack(),
      ),
      _Command(
        name: WorkspaceUxStrings(context).text('forward'),
        binding: ShortcutAction.forward,
        icon: Icons.arrow_forward,
        enabled: panel.canNavigateForward,
        action: () => panel.navigateForward(),
      ),
      _Command(
        name: NavigationStrings(context).text('reopen'),
        binding: ShortcutAction.reopenClosedTab,
        icon: Icons.restore,
        enabled: panel.canReopenClosedTab,
        action: () => panel.reopenClosedTab(),
      ),
      _Command(
        name: WorkspaceUxStrings(context).text('customize'),
        icon: Icons.keyboard_outlined,
        keywords: 'keyboard keys bindings shortcuts',
        action: () => showKeyboardShortcutSettings(widget.parentContext),
      ),
      for (final action in [
        ShortcutAction.search,
        ShortcutAction.filter,
        ShortcutAction.rename,
        ShortcutAction.preview,
        ShortcutAction.edit,
        ShortcutAction.newFolder,
        ShortcutAction.delete,
        ShortcutAction.toggleHidden,
        ShortcutAction.toggleTreeView,
        ShortcutAction.cycleLayout,
      ])
        _Command(
          name: WorkspaceUxStrings(context).action(action),
          binding: action,
          enabled:
              ![
                ShortcutAction.rename,
                ShortcutAction.preview,
                ShortcutAction.edit,
                ShortcutAction.delete,
              ].contains(action) ||
              hasTargets,
          icon: switch (action) {
            ShortcutAction.search => Icons.search,
            ShortcutAction.filter => Icons.filter_list,
            ShortcutAction.rename => Icons.drive_file_rename_outline,
            ShortcutAction.preview => Icons.preview_outlined,
            ShortcutAction.edit => Icons.edit_outlined,
            ShortcutAction.newFolder => Icons.create_new_folder_outlined,
            ShortcutAction.delete => Icons.delete_outline,
            ShortcutAction.toggleHidden => Icons.visibility_outlined,
            ShortcutAction.toggleTreeView => Icons.account_tree_outlined,
            _ => Icons.view_list_outlined,
          },
          action: () =>
              executeBrowserShortcut(widget.parentContext, ref, action),
        ),
      _Command(
        name: context.commanderTr("Navigate Up"),
        binding: ShortcutAction.up,
        icon: Icons.arrow_upward,
        action: () => panel.navigateUp(),
      ),
      _Command(
        name: context.commanderTr("Refresh Panel"),
        binding: ShortcutAction.refresh,
        icon: Icons.refresh,
        action: () => panel.refresh(),
      ),
      _Command(
        name: context.commanderTr("Switch Panel"),
        binding: ShortcutAction.switchPanel,
        icon: Icons.swap_horiz,
        action: () => executeBrowserShortcut(
          widget.parentContext,
          ref,
          ShortcutAction.switchPanel,
        ),
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
        binding: ShortcutAction.goToFolder,
        icon: Icons.folder_open,
        action: () {
          showGoToDialog(widget.parentContext, ref);
        },
      ),

      ..._quickOpenCommands(side),

      _Command(
        name: context.commanderTr("Commander workspaces"),
        icon: Icons.bookmarks_outlined,
        action: () => showWorkspaceDialog(widget.parentContext, ref, side),
      ),
      _Command(
        name: WorkspaceUxStrings(context).action(ShortcutAction.pathFavorites),
        binding: ShortcutAction.pathFavorites,
        icon: Icons.star_outline,
        keywords: 'favorites favourite bookmark path directory group',
        action: () => showPathFavoritesMenu(widget.parentContext, side),
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
        binding: ShortcutAction.findPattern,
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
        binding: ShortcutAction.multiRename,
        icon: Icons.drive_file_rename_outline,
        action: () => showMultiRenameFromSelection(widget.parentContext, ref),
      ),
      _Command(
        name: context.commanderTr("Copy with Options"),
        binding: ShortcutAction.copyWithOptions,
        icon: Icons.copy,
        action: () => showCopyDialogFromSelection(widget.parentContext, ref),
      ),
      _Command(
        name: context.commanderTr("Move with Options"),
        binding: ShortcutAction.moveWithOptions,
        icon: Icons.drive_file_move,
        action: () => showMoveDialogFromSelection(widget.parentContext, ref),
      ),
      _Command(
        name: context.commanderTr("Copy Files to Clipboard"),
        binding: ShortcutAction.copy,
        icon: Icons.content_copy,
        action: () => copyFilesToClipboard(widget.parentContext, ref, side),
      ),
      _Command(
        name: context.commanderTr("Cut Files to Clipboard"),
        binding: ShortcutAction.cut,
        icon: Icons.content_cut,
        action: () =>
            copyFilesToClipboard(widget.parentContext, ref, side, cut: true),
      ),
      _Command(
        name: context.commanderTr("Paste Files with Options"),
        binding: ShortcutAction.paste,
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
        name: 'Copy name(s)',
        icon: Icons.copy,
        action: () => copySelectionNamesOrPaths(ref, namesOnly: true),
      ),
      _Command(
        name: 'Copy full path(s)',
        icon: Icons.copy,
        action: () => copySelectionNamesOrPaths(ref, namesOnly: false),
      ),
      if (canCompareDirectories(ref))
        _Command(
          name: 'Compare Directories',
          icon: Icons.compare_arrows,
          action: () => compareDirectories(ref),
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
        binding: ShortcutAction.restoreSelection,
        icon: Icons.restore,
        enabled: panel.restorableSelectionCount > 0,
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
        binding: ShortcutAction.selectAll,
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
        binding: ShortcutAction.newTab,
        icon: Icons.add,
        action: () => panel.addTab(),
      ),
      _Command(
        name: context.commanderTr("Close Tab"),
        binding: ShortcutAction.closeTab,
        icon: Icons.close,
        enabled: panel.tabs.length > 1 && panel.activeTab?.isProtected != true,
        action: () {
          panel.closeTab(panel.activeTabId);
        },
      ),

      // Transfers
      if (ref.read(panelProvider(PanelSide.local)).selection.isNotEmpty)
        _Command(
          name: context.commanderTr("Upload Selected"),
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
        binding: ShortcutAction.togglePreview,
        icon: Icons.visibility,
        action: () {
          ref.read(showPreviewProvider.notifier).state = !ref.read(
            showPreviewProvider,
          );
        },
      ),

      // Operations
      _Command(
        name: StorageAnalyzerStrings(context).text('title'),
        icon: Icons.space_dashboard_outlined,
        action: () => showStorageAnalyzerDialog(widget.parentContext, ref),
      ),
      _Command(
        name: StorageAnalyzerStrings(context).text('batchTitle'),
        icon: Icons.inventory_2_outlined,
        action: () => showStorageScanBatchDialog(widget.parentContext, ref),
      ),
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
          binding: ShortcutAction.connect,
          icon: Icons.cloud,
          action: () => showConnectionDialogScreen(widget.parentContext),
        ),
      if (auth.isConnected)
        _Command(
          name: context.commanderTr("Disconnect"),
          icon: Icons.cloud_off,
          action: () => confirmLogoutRiverpod(widget.parentContext, ref),
        ),

      // Sorting
      ...[SortBy.name, SortBy.size, SortBy.date, SortBy.extension].map(
        (sort) => _Command(
          name: context.commanderTr("Sort by {0}", [
            context.commanderEnum(sort),
          ]),
          binding: switch (sort) {
            SortBy.name => ShortcutAction.sortByName,
            SortBy.size => ShortcutAction.sortBySize,
            SortBy.date => ShortcutAction.sortByDate,
            SortBy.extension => ShortcutAction.sortByExtension,
          },
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
      _filtered = _rankCommands(query);
      _selectedIndex = _filtered.indexWhere((command) => command.enabled);
      if (_selectedIndex < 0) _selectedIndex = 0;
    });
  }

  String? _shortcut(_Command command) => command.binding == null
      ? command.shortcut
      : ref
            .read(keyboardShortcutServiceProvider)
            .browserDisplay(command.binding!);

  List<_Command> _quickOpenCommands(PanelSide side) {
    final strings = QuickOpenStrings(context);
    final saved = ref.read(quickOpenSavedItemsProvider);
    final entries = ref
        .read(quickOpenControllerProvider)
        .entries(
          side,
          saved.valueOrNull,
          devices: [
            for (final device
                in ref.read(drivesProvider).valueOrNull ?? const <DriveEntry>[])
              QuickOpenDevice(path: device.path, name: device.label),
          ],
          reviewRename: (request) async {
            if (!widget.parentContext.mounted) return;
            await showDialog<void>(
              context: widget.parentContext,
              barrierDismissible: false,
              builder: (_) => BatchRenameDialog(
                parentRef: widget.actionRef,
                side: request.side,
                files: request.files,
                initialOptions: request.options,
                initialPresetName: request.name,
                capturedOrigin: request.origin,
                capturedDirectory: request.directory,
              ),
            );
          },
        );
    return [
      for (final entry in entries)
        _Command(
          id: entry.id,
          name: entry.name,
          detail:
              '${strings.kind(entry.kind)} · ${entry.kind == QuickOpenKind.renamePreset ? strings.reviewCount(entry.detail) : entry.detail}',
          disabledReason: entry.unavailable == null
              ? null
              : strings.reason(entry.unavailable!),
          icon: switch (entry.kind) {
            QuickOpenKind.favorite => Icons.star_outline,
            QuickOpenKind.source => Icons.cloud_outlined,
            QuickOpenKind.device => Icons.storage_outlined,
            QuickOpenKind.workspace => Icons.view_quilt_outlined,
            QuickOpenKind.renamePreset => Icons.drive_file_rename_outline,
          },
          keywords:
              '${entry.kind.name} ${strings.kind(entry.kind)} ${entry.detail}',
          enabled: entry.enabled,
          action: () => unawaited(_openQuickEntry(entry)),
        ),
      if (saved.isLoading && !saved.hasValue)
        _Command(
          id: 'quick-open-loading',
          name: strings.text('loading'),
          icon: Icons.hourglass_empty,
          enabled: false,
          action: () {},
        ),
      if (saved.hasError ||
          saved.valueOrNull?.workspaceError == true ||
          saved.valueOrNull?.renamePresetError == true ||
          ref.read(bookmarksProvider).lastError != null)
        _Command(
          id: 'quick-open-load-error',
          name: strings.reason(QuickOpenUnavailable.savedItemsUnavailable),
          icon: Icons.error_outline,
          enabled: false,
          action: () {},
        ),
    ];
  }

  Future<void> _openQuickEntry(QuickOpenEntry entry) async {
    final parent = widget.parentContext;
    try {
      final controller = widget.actionRef.read(quickOpenControllerProvider);
      await controller.executor.open(entry, isCurrent: () => parent.mounted);
    } catch (error) {
      if (!parent.mounted) return;
      final message = error is QuickOpenException
          ? QuickOpenStrings(parent).reason(error.reason)
          : '$error';
      ScaffoldMessenger.maybeOf(parent)
          ?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  List<_Command> _rankCommands(String query) {
    final ranked = <({int index, int score, _Command command})>[];
    for (var i = 0; i < _allCommands.length; i++) {
      final command = _allCommands[i];
      final score = commandSearchScore(
        query,
        command.name,
        keywords:
            '${command.keywords} ${command.binding == null ? '' : CommanderStrings.labelForEnum(command.binding!)} ${_shortcut(command) ?? ''}',
      );
      if (score != null) ranked.add((index: i, score: score, command: command));
    }
    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore == 0 ? a.index.compareTo(b.index) : byScore;
    });
    return ranked.map((entry) => entry.command).toList();
  }

  void _moveSelection(int delta) {
    if (_filtered.isEmpty) return;
    var next = _selectedIndex + delta;
    while (next >= 0 && next < _filtered.length && !_filtered[next].enabled) {
      next += delta;
    }
    if (next < 0 || next >= _filtered.length) return;
    setState(() => _selectedIndex = next);
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
    if (_filtered.isNotEmpty &&
        _selectedIndex < _filtered.length &&
        _filtered[_selectedIndex].enabled) {
      final command = _filtered[_selectedIndex];
      Navigator.of(context).pop();
      command.action();
    }
  }

  Widget _commandRow(int index, ThemeData theme) {
    final command = _filtered[index];
    final shortcutLabel = _shortcut(command);
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
          shortcutLabel!,
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
      enabled: command.enabled,
      child: InkWell(
        onTap: !command.enabled
            ? null
            : () {
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
                    Text(
                      command.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: command.enabled ? null : theme.disabledColor,
                      ),
                    ),
                    if (command.detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          command.detail!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (command.disabledReason != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          command.disabledReason!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.disabledColor,
                          ),
                        ),
                      ),
                    if (compact && shortcutLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: shortcut(),
                      ),
                  ],
                ),
              ),
              if (!compact && shortcutLabel != null) shortcut(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final side = ref.watch(activePanelProvider);
    ref.watch(panelProvider(side));
    ref.watch(authProvider);
    ref.watch(shortcutBindingsProvider);
    ref.watch(bookmarksProvider);
    ref.watch(availableSourcesProvider);
    ref.watch(drivesProvider);
    ref.watch(fileCollectionStoreProvider);
    ref.watch(quickOpenSavedItemsProvider);
    final previouslySelected = _selectedIndex < _filtered.length
        ? _filtered[_selectedIndex]
        : null;
    _allCommands = _buildCommands();
    if (previouslySelected?.id != null &&
        !_allCommands.any(
          (command) => command.identity == previouslySelected!.identity,
        )) {
      // A disconnected/removed target must not silently hand keyboard selection
      // to another account with the same display name.
      _allCommands.add(
        _Command(
          id: previouslySelected!.id,
          name: previouslySelected.name,
          detail: previouslySelected.detail,
          keywords: previouslySelected.keywords,
          icon: previouslySelected.icon,
          enabled: false,
          disabledReason: QuickOpenStrings(context)
              .reason(QuickOpenUnavailable.changed),
          action: () {},
        ),
      );
    }
    _filtered = _rankCommands(_controller.text);
    _selectedIndex = _filtered.indexWhere(
      (command) => command.identity == previouslySelected?.identity,
    );
    if (_selectedIndex < 0) {
      _selectedIndex = _filtered.indexWhere((command) => command.enabled);
      if (_selectedIndex < 0) _selectedIndex = 0;
    }

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
                  if (_filtered.isEmpty &&
                      (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                          event.logicalKey == LogicalKeyboardKey.arrowUp)) {
                    return KeyEventResult.handled;
                  }
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
                    hintText: QuickOpenStrings(context).text('hint'),
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
