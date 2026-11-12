// widgets/file_panel.dart

import '../l10n/commander_strings.dart';
import '../l10n/folder_drop_strings.dart';

import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/panel_drag_data.dart';
import '../providers/providers.dart';
import '../l10n/panel_error_strings.dart';
import '../providers/toolbar_provider.dart' show panelViewModeProvider;
import '../services/panel_view_mode_service.dart' show PanelViewMode;
import 'file_column_view.dart';
import 'file_column_header.dart';
import 'file_view_editor_dialog.dart';
import 'workspace_dialog.dart';
import 'file_command_toolbar.dart';
import 'file_grid_view.dart';
import 'file_list_view.dart' show FileListView;
import 'file_selection_bar.dart';
import 'file_list_dialog.dart';
import 'file_collections_dialog.dart';
import 'file_operation_dialog.dart';
import 'external_drop_review.dart';
import '../services/file_operation_service.dart';
import '../services/folder_drop_service.dart';
import 'folder_drop_target.dart';
import 'pattern_selection_dialog.dart';
import 'file_tree_view_stub.dart' if (dart.library.io) 'file_tree_view.dart';
import 'panel_tab_bar.dart';
import 'path_favorites.dart';
import 'panel_header.dart';
import 'panel_listing_placeholder.dart';
import '../l10n/file_panel_strings.dart';

class FilePanel extends ConsumerStatefulWidget {
  final PanelSide side;
  final bool isActive;
  final VoidCallback onTap;

  const FilePanel({
    super.key,
    required this.side,
    required this.isActive,
    required this.onTap,
  });

  @override
  ConsumerState<FilePanel> createState() => _FilePanelState();
}

class _FilePanelState extends ConsumerState<FilePanel> {
  bool _isDragging = false;
  bool _externalDropInProgress = false;
  AppError? _lastShownError;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(panelProvider(widget.side));
    final errors = ref.watch(errorProvider);
    final lastAppError = errors.lastAppError;
    final lastError = lastAppError?.message;

    // Show each error once. Without clearing it, every rebuild re-queued a
    // snackbar and the message appeared to never go away.
    if (lastError != null &&
        lastError.isNotEmpty &&
        widget.side == ref.watch(activePanelProvider) &&
        lastAppError?.code != PanelErrorCode.permissionDenied &&
        !identical(lastAppError, _lastShownError)) {
      _lastShownError = lastAppError;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted ||
            !identical(ref.read(errorProvider).lastAppError, lastAppError)) {
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(localizedPanelError(context, lastAppError!)),
            showCloseIcon: true,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
          ),
        );
        // Only consume the error this callback actually displayed. A newer
        // failure may have arrived between scheduling and showing the notice.
        if (identical(ref.read(errorProvider).lastAppError, lastAppError)) {
          ref.read(errorProvider).clearLastError();
        }
      });
    } else if (lastError == null) {
      _lastShownError = null;
    }

    final files = panel.filteredFiles;
    final currentPath = panel.currentPath;
    final selection = panel.selection;

    // Wrap in DragTarget for inter-panel file dragging
    final panelContent = _buildPanelContent(
      context,
      panel,
      files,
      currentPath,
      selection,
    );

    // Flutter DragTarget for cross-panel drops
    final Widget content = DragTarget<PanelDragData>(
      onWillAcceptWithDetails: (details) {
        if (details.data.hasFolderTarget ||
            details.data.sourceSide == widget.side ||
            panel.showingSearchResults) {
          return false;
        }
        try {
          final source = ref.read(panelProvider(details.data.sourceSide));
          details.data.captureFrom(source);
          if (!details.data.isCurrent) return false;
          panel.captureCurrentOrigin();
          return true;
        } catch (_) {
          return false;
        }
      },
      onAcceptWithDetails: (details) async {
        final data = details.data;
        final sourcePanel = ref.read(panelProvider(data.sourceSide));
        if (data.hasFolderTarget ||
            data.sourceSide == widget.side ||
            panel.showingSearchResults) {
          return;
        }
        try {
          // PanelSide is a visual position. Both normal folders and virtual
          // lists must retain their actual storage/account through the dialog.
          final destination = panel.captureCurrentOrigin();
          final destinationTab = panel.activeTabId;
          data.captureFrom(sourcePanel);
          final groups = await data.prepareForDrop();
          final files = [for (final group in groups.values) ...group];
          if (!context.mounted) return;
          if (panel.activeTabId != destinationTab ||
              !identical(panel.captureCurrentOrigin(), destination)) {
            throw const PanelDragException(PanelDragFailure.destinationChanged);
          }
          await showFileOperationDialog(
            context,
            ref,
            data.sourceSide,
            files,
            kind: FileOperationKind.copy,
            sourceGroups: groups,
            destinationOrigin: destination,
            destinationPath: destination.source.currentPath,
          );
        } catch (error) {
          if (context.mounted) {
            ref
                .read(errorProvider)
                .addError(FolderDropStrings(context).failure(error));
          }
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isDropTarget = candidateData.isNotEmpty;
        if (!isDropTarget) return panelContent;

        const opIcon = Icons.copy_outlined;
        final opLabel = context.commanderTr('Copy');
        final fileCount = candidateData.first?.files.length ?? 0;

        return Stack(
          children: [
            panelContent,
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.08),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        opIcon,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$opLabel ${FilePanelStrings(context).value('files', fileCount)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    return GestureDetector(
      onTap: widget.onTap,
      child: DropTarget(
        enable:
            !_externalDropInProgress &&
            (ModalRoute.of(context)?.isCurrent ?? true),
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (details) async {
          if (!mounted ||
              _externalDropInProgress ||
              ModalRoute.of(context)?.isCurrent == false) {
            return;
          }
          setState(() {
            _isDragging = false;
            _externalDropInProgress = true;
          });
          try {
            await showExternalDropReview(
              context,
              ref,
              widget.side,
              details.files,
            );
          } finally {
            if (mounted) setState(() => _externalDropInProgress = false);
          }
        },
        child: content,
      ),
    );
  }

  Widget _buildFileView(PanelSide side, List<FileItem> files) {
    // Result lists always show original paths, including duplicate basenames.
    if (ref.watch(panelProvider(side)).showingSearchResults) {
      return FileListView(
        side: side,
        files: files,
        scrollController: _scrollController,
      );
    }
    // Tree mode overrides the list/grid/column choice (desktop only)
    final densityMode = ref.watch(panelViewModeProvider(side));
    if (densityMode == PanelViewMode.tree && !kIsWeb) {
      return FileTreeView(side: side);
    }

    final viewMode = side == PanelSide.local
        ? ref.watch(localViewModeProvider)
        : ref.watch(remoteViewModeProvider);

    if (viewMode == ViewMode.grid) {
      return FileGridView(
        side: side,
        files: files,
        scrollController: _scrollController,
      );
    }
    if (viewMode == ViewMode.tiles) {
      return FileGridView(
        side: side,
        files: files,
        scrollController: _scrollController,
        tileLayout: true,
      );
    }
    if (viewMode == ViewMode.gallery) {
      return FileGridView(
        side: side,
        files: files,
        scrollController: _scrollController,
        galleryOnly: true,
      );
    }
    if (viewMode == ViewMode.column) {
      return FileColumnView(
        side: side,
        files: files,
        scrollController: _scrollController,
      );
    }
    return FileListView(
      side: side,
      files: files,
      scrollController: _scrollController,
    );
  }

  Widget _buildFileListHeader(BuildContext context, PanelNotifier panel) {
    final colors = Theme.of(context).colorScheme;
    final targets = panel.selection.isNotEmpty
        ? panel.selection.toList()
        : [if (panel.cursorItem != null) panel.cursorItem!];
    return Container(
      color: colors.secondaryContainer,
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                panel.canOperateOnFileList
                    ? Icons.list_alt
                    : Icons.warning_amber,
                size: 16,
                color: colors.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Tooltip(
                  message: panel.canOperateOnFileList
                      ? context.commanderTr(
                          "Original paths are retained. Copy, move, rename, or remove rows from this list.",
                        )
                      : context.commanderTr(
                          "The source account changed. Run the search or import again before file operations.",
                        ),
                  child: Text(
                    context.commanderTr("{0} · {1} item(s){2}", [
                      panel.fileListTitle,
                      panel.collectionTotalCount,
                      panel.collectionBusy
                          ? ' · ${panel.collectionProgress}'
                          : '',
                    ]),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSecondaryContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: context.commanderTr("Open containing folder"),
                onPressed: targets.length != 1 || !panel.canOperateOnFileList
                    ? null
                    : () async {
                        try {
                          await panel.openContainingFolder(targets.single);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.toString())),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.folder_open),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: context.commanderTr("Remove from list (keep files)"),
                onPressed: targets.isEmpty
                    ? null
                    : () => panel.removeFromFileList(targets),
                icon: const Icon(Icons.playlist_remove),
              ),
              PopupMenuButton<String>(
                tooltip: context.commanderTr("File list actions"),
                iconSize: 18,
                onSelected: (value) async {
                  try {
                    switch (value) {
                      case 'collections':
                        await showFileCollectionsDialog(
                          context,
                          ref,
                          widget.side,
                        );
                      case 'refresh-items':
                        await panel.refreshCollectionItems();
                      case 'rerun':
                        await panel.refreshCollectionItems(rerunSearch: true);
                      case 'replacements':
                        await reviewCollectionReplacements(
                          context,
                          ref,
                          widget.side,
                        );
                      case 'pattern':
                        showPatternSelectionDialog(context, ref, widget.side);
                      case 'copy':
                        copyFileListPaths(
                          context,
                          ref,
                          widget.side,
                          selectedOnly: panel.selection.isNotEmpty,
                        );
                      case 'export':
                        showFileListDialog(context, ref, widget.side);
                      case 'import':
                        showFileListDialog(
                          context,
                          ref,
                          widget.side,
                          importMode: true,
                        );
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('$error')));
                    }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'collections',
                    child: Text(
                      context.commanderTr("Save / manage collections…"),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'refresh-items',
                    enabled: !panel.collectionBusy,
                    child: Text(context.commanderTr("Refresh original items")),
                  ),
                  PopupMenuItem(
                    value: 'rerun',
                    enabled:
                        !panel.collectionBusy && panel.canRerunCollectionSearch,
                    child: Text(context.commanderTr("Rerun saved search")),
                  ),
                  PopupMenuItem(
                    value: 'replacements',
                    enabled:
                        !panel.collectionBusy &&
                        panel.collectionReplacements.isNotEmpty,
                    child: Text(
                      context.commanderTr("Review replacement items…"),
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'pattern',
                    child: Text(context.commanderTr("Select by pattern…")),
                  ),
                  PopupMenuItem(
                    value: 'copy',
                    child: Text(context.commanderTr("Copy original paths")),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    child: Text(context.commanderTr("Export file list…")),
                  ),
                  PopupMenuItem(
                    value: 'import',
                    child: Text(context.commanderTr("Import file list…")),
                  ),
                ],
              ),
              if (panel.collectionBusy)
                IconButton(
                  tooltip: context.commanderTr("Cancel collection refresh"),
                  onPressed: panel.cancelCollectionRefresh,
                  icon: const Icon(Icons.stop),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: context.commanderTr("Return to folder"),
                onPressed: () => panel.clearSearchResults(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (panel.isPagedCollection &&
              (panel.collectionPageCount > 1 ||
                  panel.collectionTotalCount > 500))
            Row(
              children: [
                IconButton(
                  key: const ValueKey('collection-first-page'),
                  visualDensity: VisualDensity.compact,
                  tooltip: context.commanderTr("First collection page"),
                  icon: const Icon(Icons.first_page),
                  onPressed:
                      panel.collectionBusy || panel.collectionPageIndex == 0
                      ? null
                      : () => _collectionAction(
                          () => panel.loadCollectionPage(0),
                        ),
                ),
                IconButton(
                  key: const ValueKey('collection-previous-page'),
                  visualDensity: VisualDensity.compact,
                  tooltip: context.commanderTr("Previous collection page"),
                  icon: const Icon(Icons.chevron_left),
                  onPressed:
                      panel.collectionBusy || panel.collectionPageIndex == 0
                      ? null
                      : () => _collectionAction(
                          () => panel.loadCollectionPage(
                            panel.collectionPageIndex - 1,
                          ),
                        ),
                ),
                Expanded(
                  child: Tooltip(
                    message: context.commanderTr(
                      "Sorting, filtering, and marks include every collection page.",
                    ),
                    child: Text(
                      context.commanderTr("{0}–{1} of {2} · {3} marked", [
                        panel.collectionMatchingCount == 0
                            ? 0
                            : panel.collectionPageStart + 1,
                        panel.collectionPageStart + (panel.files?.length ?? 0),
                        panel.collectionMatchingCount,
                        panel.selection.length,
                      ]),
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('collection-next-page'),
                  visualDensity: VisualDensity.compact,
                  tooltip: context.commanderTr("Next collection page"),
                  icon: const Icon(Icons.chevron_right),
                  onPressed:
                      panel.collectionBusy ||
                          panel.collectionPageIndex + 1 >=
                              panel.collectionPageCount
                      ? null
                      : () => _collectionAction(
                          () => panel.loadCollectionPage(
                            panel.collectionPageIndex + 1,
                          ),
                        ),
                ),
                IconButton(
                  key: const ValueKey('collection-last-page'),
                  visualDensity: VisualDensity.compact,
                  tooltip: context.commanderTr("Last collection page"),
                  icon: const Icon(Icons.last_page),
                  onPressed:
                      panel.collectionBusy ||
                          panel.collectionPageIndex + 1 >=
                              panel.collectionPageCount
                      ? null
                      : () => _collectionAction(
                          () => panel.loadCollectionPage(
                            panel.collectionPageCount - 1,
                          ),
                        ),
                ),
              ],
            ),
          if (panel.collectionLoadError != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    panel.collectionLoadError!,
                    maxLines: 3,
                    style: TextStyle(color: colors.error),
                  ),
                ),
                IconButton(
                  tooltip: context.commanderTr(
                    "Reload saved collection; unsaved marks are discarded",
                  ),
                  onPressed: panel.collectionBusy
                      ? null
                      : () => _collectionAction(panel.reloadSavedCollection),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _collectionAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Widget _buildPanelContent(
    BuildContext context,
    PanelNotifier panel,
    List<FileItem>? files,
    String currentPath,
    Set<FileItem> selection,
  ) {
    // Observe account changes even if they invalidate an existing listing
    // without publishing new rows. Status uses that listing's actual source.
    ref.watch(authProvider);
    ref.watch(multiCloudProvider);
    final sourceIsRemote = panel.directoryStorage?.isLocal == false;
    final listingState = panelListingState(panel);
    final layout = widget.side == PanelSide.local
        ? ref.watch(localViewModeProvider)
        : ref.watch(remoteViewModeProvider);
    final visualLayout =
        layout == ViewMode.grid ||
        layout == ViewMode.tiles ||
        layout == ViewMode.gallery ||
        layout == ViewMode.column;
    final retainColumns =
        layout == ViewMode.column &&
        !panel.showingSearchResults &&
        ref.watch(panelViewModeProvider(widget.side)) != PanelViewMode.tree;
    return Container(
      decoration: BoxDecoration(
        color: widget.isActive ? null : Colors.black.withValues(alpha: 0.02),
        border: _isDragging
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: PanelTabBar(
                  tabs: panel.tabs,
                  activeTabId: panel.activeTabId,
                  activeSelectionCount: selection.length,
                  onTabSelected: (id) => panel.selectTab(id),
                  onTabClosed: (id) => panel.closeTab(id),
                  onNewTab: () => panel.addTab(),
                  onTabPinToggle: (id) => panel.toggleTabPin(id),
                  onTabRenamed: (id, name) => panel.renameTab(id, name),
                  onReopenClosedTab: panel.reopenClosedTab,
                  canReopenClosedTab: panel.canReopenClosedTab,
                  onTabLockChanged: (id, mode) => panel.setTabLock(id, mode),
                  onTabDuplicated: (id) => panel.duplicateTab(id),
                  onTabReordered: panel.reorderTabs,
                  onTabForceClosed: (id) => panel.closeTab(id, force: true),
                  onCloseDuplicates: () => panel.closeDuplicateTabs(),
                  onWorkspace: () =>
                      showWorkspaceDialog(context, ref, widget.side),
                  tabDropTargetBuilder: (tab, child) => FolderDropTarget(
                    key: ValueKey(
                      'tab-folder-drop-${widget.side.name}-${tab.id}',
                    ),
                    side: widget.side,
                    folder: FileItem(
                      name: tab.label,
                      path: tab.path,
                      isFolder: true,
                    ),
                    captureDestination: () =>
                        const FolderDropService().captureTab(
                          panel,
                          tab,
                          ref.read(localFileServiceProvider),
                        ),
                    child: child,
                  ),
                ),
              ),
              PathFavoritesButton(side: widget.side),
            ],
          ),
          PanelHeader(
            side: widget.side,
            isActive: widget.isActive,
            showSource: MediaQuery.sizeOf(context).width > 800,
          ),
          FileCommandToolbar(side: widget.side),
          if (panel.showingSearchResults) _buildFileListHeader(context, panel),
          if (panel.collectionBusy && !panel.showingSearchResults)
            Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    panel.collectionProgress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: panel.cancelCollectionRefresh,
                  child: Text(context.commanderTr("Cancel")),
                ),
              ],
            ),
          // Selection bar: off by default (DC mode — info is in status bar).
          // Enable in settings for touch/tablet mode.
          if (ref.watch(showSelectionBarProvider) && selection.isNotEmpty)
            FileSelectionBar(side: widget.side, selection: selection),
          if (ref.watch(panelViewModeProvider(widget.side)) ==
                  PanelViewMode.full &&
              layout == ViewMode.list)
            _CompactColumnHeader(side: widget.side, panel: panel),
          // Loading indicator shown while directory listing is in progress
          if (panel.isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child:
                !retainColumns &&
                    listingState != null &&
                    (listingState.blocksListing ||
                        (!visualLayout &&
                            listingState != PanelListingState.loading) ||
                        (listingState == PanelListingState.loading &&
                            (files == null ||
                                !files.any((file) => file.name != '..'))))
                ? PanelListingPlaceholder(
                    side: widget.side,
                    state: listingState,
                    dropHint: _isDragging && sourceIsRemote,
                  )
                // Pull-to-refresh on mobile, with type-ahead overlay
                : Stack(
                    children: [
                      RefreshIndicator(
                        onRefresh: () => panel.refresh(),
                        child: _buildFileView(widget.side, files ?? const []),
                      ),
                      if (panel.isTypeahead)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: Theme.of(context).colorScheme.inverseSurface
                                .withValues(alpha: 0.9),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  panel.isQuickFilterActive
                                      ? Icons.filter_list
                                      : Icons.search,
                                  size: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    (panel.isQuickFilterActive
                                            ? 'Filter: '
                                            : 'Find: ') +
                                        panel.filterQuery,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onInverseSurface,
                                    ),
                                  ),
                                ),
                                if (panel.typeaheadMatchCount > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                      '${panel.typeaheadMatchPosition}/'
                                      '${panel.typeaheadMatchCount}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onInverseSurface,
                                      ),
                                    ),
                                  ),
                                GestureDetector(
                                  onTap: () => panel.clearTypeahead(),
                                  child: Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onInverseSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CompactColumnHeader extends ConsumerWidget {
  const _CompactColumnHeader({required this.side, required this.panel});
  final PanelSide side;
  final PanelNotifier panel;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FileColumnHeader(
    side: side,
    panel: panel,
    onConfigure: () => showPanelViewDialog(context, ref, side),
  );
}
