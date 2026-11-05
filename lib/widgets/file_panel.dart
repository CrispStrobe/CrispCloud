// widgets/file_panel.dart

import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../services/log_service.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../providers/panel_source_provider.dart' show panelSourceProvider;
import '../providers/toolbar_provider.dart'
    show columnWidthsProvider, panelViewModeProvider;
import '../services/panel_source_service.dart' show RemotePanelSource;
import '../services/panel_view_mode_service.dart' show PanelViewMode;
import 'file_column_view.dart';
import 'file_grid_view.dart';
import 'file_list_view.dart' show FileListView, PanelDragData;
import 'file_selection_bar.dart';
import 'file_list_dialog.dart';
import 'file_collections_dialog.dart';
import 'file_operation_dialog.dart';
import '../services/file_operation_service.dart';
import 'pattern_selection_dialog.dart';
import 'file_tree_view_stub.dart' if (dart.library.io) 'file_tree_view.dart';
import 'panel_tab_bar.dart';
import 'panel_header.dart';
import '../l10n/app_localizations.dart';
import '../screens/screen_dialogs.dart' show showConnectionDialogScreen;

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
  static const _log = Log('FilePanel');

  bool _isDragging = false;
  String? _lastShownError;
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
    final lastError = errors.lastError;

    // Show each error once. Without clearing it, every rebuild re-queued a
    // snackbar and the message appeared to never go away.
    if (lastError != null &&
        lastError.isNotEmpty &&
        widget.side == PanelSide.local &&
        lastError != _lastShownError) {
      _lastShownError = lastError;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        final panel = ref.read(panelProvider(widget.side));
        final missingPath =
            lastError.contains('PathNotFound') ||
            lastError.contains('No such file') ||
            lastError.contains('not found');
        final actionLabel = panel.isInArchive
            ? 'Exit archive'
            : missingPath
            ? 'Home'
            : 'Grant access';
        messenger.showSnackBar(
          SnackBar(
            content: Text(lastError),
            showCloseIcon: true,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: actionLabel,
              onPressed: () {
                if (panel.isInArchive) {
                  panel.exitArchive();
                } else if (missingPath) {
                  panel.navigateHome();
                } else {
                  panel.grantAccessToCurrentPath();
                }
              },
            ),
            duration: const Duration(seconds: 8),
          ),
        );
        // Consume it so it is not shown again on the next build.
        ref.read(errorProvider).clearLastError();
      });
    } else if (lastError == null) {
      _lastShownError = null;
    }

    final files = panel.filteredFiles;
    final currentPath = panel.currentPath;
    final selection = panel.selection;

    final layout = widget.side == PanelSide.local
        ? ref.watch(localViewModeProvider)
        : ref.watch(remoteViewModeProvider);
    final visualLayout =
        !panel.showingSearchResults &&
        (layout == ViewMode.grid ||
            layout == ViewMode.tiles ||
            layout == ViewMode.gallery);
    // Visual layouts keep their search/view controls usable in empty folders.
    if (kIsWeb &&
        !visualLayout &&
        (files == null || files.isEmpty) &&
        !panel.isLoading &&
        !panel.showingSearchResults) {
      final auth = ref.watch(authProvider);
      final l = AppLocalizations.of(context)!;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(l.noFolderSelected),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              onPressed: () => panel.pickLocalDirectory(),
              label: Text(l.openLocalFolder),
            ),
            const SizedBox(height: 8),
            if (!auth.isConnected)
              OutlinedButton.icon(
                icon: const Icon(Icons.cloud),
                onPressed: () => showConnectionDialogScreen(context),
                label: Text(l.connectToCloud),
              )
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.cloud_done),
                onPressed: () {
                  // Switch this panel to the connected remote source.
                  ref
                      .read(panelSourceProvider(widget.side).notifier)
                      .setSource(
                        RemotePanelSource(
                          providerName: auth.providerName,
                          client: auth.client,
                          path: '/',
                        ),
                      );
                },
                label: Text(l.browseProvider(auth.providerName)),
              ),
          ],
        ),
      );
    }

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
        if (details.data.sourceSide == widget.side ||
            panel.showingSearchResults) {
          return false;
        }
        try {
          ref.read(panelProvider(details.data.sourceSide))
              .captureOperationOrigin(details.data.files);
          panel.captureCurrentOrigin();
          return true;
        } catch (_) {
          return false;
        }
      },
      onAcceptWithDetails: (details) async {
        final data = details.data;
        final sourcePanel = ref.read(panelProvider(data.sourceSide));
        if (data.sourceSide == widget.side || panel.showingSearchResults) {
          return;
        }
        try {
          // PanelSide is a visual position. Both normal folders and virtual
          // lists must retain their actual storage/account through the dialog.
          final source = sourcePanel.captureOperationOrigin(data.files);
          final destination = panel.captureCurrentOrigin();
          await showFileOperationDialog(
            context,
            ref,
            data.sourceSide,
            data.files,
            kind: FileOperationKind.copy,
            sourceOrigin: source,
            destinationOrigin: destination,
            destinationPath: destination.source.currentPath,
          );
        } catch (error) {
          if (context.mounted) {
            ref.read(errorProvider).addError(error.toString());
          }
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isDropTarget = candidateData.isNotEmpty;
        if (!isDropTarget) return panelContent;

        const opIcon = Icons.copy_outlined;
        const opLabel = 'Copy';
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
                        '$opLabel ${fileCount > 1 ? "$fileCount files" : "file"}',
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
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (details) async {
          if (panel.showingSearchResults) {
            setState(() => _isDragging = false);
            ref
                .read(errorProvider)
                .addError(
                  'Return to a real folder before dropping files into this panel.',
                );
            return;
          }
          setState(() => _isDragging = false);
          if (kIsWeb) {
            // Web: save dropped files to the current local folder.
            final localSvc = ref.read(localFileServiceProvider);
            for (final xFile in details.files) {
              try {
                final bytes = await xFile.readAsBytes();
                final targetPath = '${panel.currentPath}/${xFile.name}';
                await localSvc.saveFile(targetPath, bytes);
              } catch (e) {
                _log.warn('operation failed', e);
              }
            }
            panel.refresh();
          } else {
            final auth = ref.read(authProvider);
            if (widget.side == PanelSide.remote && auth.isConnected) {
              try {
                final items = details.files
                    .map(
                      (xFile) => FileItem(
                        name: xFile.name,
                        path: xFile.path,
                        isFolder: false,
                      ),
                    )
                    .toList();
                await ref.read(transferProvider).uploadFiles(items);
              } catch (e) {
                _log.warn('operation failed', e);
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
                }
              }
            }
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

    if (viewMode == ViewMode.grid ||
        viewMode == ViewMode.tiles ||
        viewMode == ViewMode.gallery) {
      return FileGridView(
        side: side,
        files: files,
        scrollController: _scrollController,
        galleryOnly: viewMode == ViewMode.gallery,
        tileLayout: viewMode == ViewMode.tiles,
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
      child: Row(
        children: [
          Icon(
            panel.canOperateOnFileList ? Icons.list_alt : Icons.warning_amber,
            size: 16,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: panel.canOperateOnFileList
                  ? 'Original paths are retained. Copy, move, rename, or remove rows from this list.'
                  : 'The source account changed. Run the search or import again before file operations.',
              child: Text(
                '${panel.fileListTitle} · ${panel.files?.length ?? 0} item(s)${panel.collectionBusy ? ' · ${panel.collectionProgress}' : ''}',
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
            tooltip: 'Open containing folder',
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
            tooltip: 'Remove from list (keep files)',
            onPressed: targets.isEmpty
                ? null
                : () => panel.removeFromFileList(targets),
            icon: const Icon(Icons.playlist_remove),
          ),
          PopupMenuButton<String>(
            tooltip: 'File list actions',
            iconSize: 18,
            onSelected: (value) async {
              try {
                switch (value) {
                  case 'collections':
                    await showFileCollectionsDialog(context, ref, widget.side);
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
              const PopupMenuItem(
                value: 'collections',
                child: Text('Save / manage collections…'),
              ),
              PopupMenuItem(
                value: 'refresh-items',
                enabled: !panel.collectionBusy,
                child: const Text('Refresh original items'),
              ),
              PopupMenuItem(
                value: 'rerun',
                enabled:
                    !panel.collectionBusy && panel.canRerunCollectionSearch,
                child: const Text('Rerun saved search'),
              ),
              PopupMenuItem(
                value: 'replacements',
                enabled:
                    !panel.collectionBusy &&
                    panel.collectionReplacements.isNotEmpty,
                child: const Text('Review replacement items…'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'pattern',
                child: Text('Select by pattern…'),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: Text('Copy original paths'),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Text('Export file list…'),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Text('Import file list…'),
              ),
            ],
          ),
          if (panel.collectionBusy)
            IconButton(
              tooltip: 'Cancel collection refresh',
              onPressed: panel.cancelCollectionRefresh,
              icon: const Icon(Icons.stop),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: 'Return to folder',
            onPressed: () => panel.clearSearchResults(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelContent(
    BuildContext context,
    PanelNotifier panel,
    List<FileItem>? files,
    String currentPath,
    Set<FileItem> selection,
  ) {
    final layout = widget.side == PanelSide.local
        ? ref.watch(localViewModeProvider)
        : ref.watch(remoteViewModeProvider);
    final visualLayout =
        !panel.showingSearchResults &&
        (layout == ViewMode.grid ||
            layout == ViewMode.tiles ||
            layout == ViewMode.gallery);
    return Container(
      decoration: BoxDecoration(
        color: widget.isActive ? null : Colors.black.withValues(alpha: 0.02),
        border: _isDragging
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        children: [
          PanelTabBar(
            tabs: panel.tabs,
            activeTabId: panel.activeTabId,
            activeSelectionCount: selection.length,
            onTabSelected: (id) => panel.selectTab(id),
            onTabClosed: (id) => panel.closeTab(id),
            onNewTab: () => panel.addTab(),
            onTabPinToggle: (id) => panel.toggleTabPin(id),
            onTabRenamed: (id, name) => panel.renameTab(id, name),
          ),
          PanelHeader(
            side: widget.side,
            isActive: widget.isActive,
            showSource: MediaQuery.sizeOf(context).width > 800,
          ),
          if (panel.showingSearchResults) _buildFileListHeader(context, panel),
          // Selection bar: off by default (DC mode — info is in status bar).
          // Enable in settings for touch/tablet mode.
          if (ref.watch(showSelectionBarProvider) && selection.isNotEmpty)
            FileSelectionBar(side: widget.side, selection: selection),
          if (ref.watch(panelViewModeProvider(widget.side)) ==
                  PanelViewMode.full &&
              (panel.showingSearchResults || layout == ViewMode.list))
            _CompactColumnHeader(side: widget.side, panel: panel),
          // Loading indicator shown while directory listing is in progress
          if (panel.isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: files == null
                ? const Center(child: CircularProgressIndicator())
                : files.isEmpty && !visualLayout
                ? Center(
                    child: _isDragging && widget.side == PanelSide.remote
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.upload_file,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                AppLocalizations.of(context)!.dropFilesToUpload,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          )
                        : panel.showingSearchResults
                        ? const Text('This file list is empty.')
                        : widget.side == PanelSide.remote &&
                              !ref.read(authProvider).isConnected
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cloud_off,
                                size: 56,
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                AppLocalizations.of(context)!.notConnected,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.5),
                                    ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.login, size: 18),
                                label: Text(
                                  AppLocalizations.of(context)!
                                      .connectToCloudShort,
                                ),
                                onPressed: () =>
                                    showConnectionDialogScreen(context),
                              ),
                            ],
                          )
                        : Text(AppLocalizations.of(context)!.emptyFolder),
                  )
                // Pull-to-refresh on mobile, with type-ahead overlay
                : Stack(
                    children: [
                      RefreshIndicator(
                        onRefresh: () => panel.refresh(),
                        child: _buildFileView(widget.side, files),
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

/// Sortable column headers for compact ("Full") view, matching CompactFileTile layout.
/// Supports drag-to-resize Size and Date columns (DC-11).
class _CompactColumnHeader extends ConsumerWidget {
  final PanelSide side;
  final PanelNotifier panel;
  const _CompactColumnHeader({required this.side, required this.panel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );
    final colWidths = ref.watch(columnWidthsProvider(side));
    final colNotifier = ref.read(columnWidthsProvider(side).notifier);
    final sizeW = (colWidths['size'] ?? 62.0).abs();
    final dateW = (colWidths['date'] ?? 78.0).abs();
    final extW = (colWidths['ext'] ?? 40.0).abs();
    final showSize = colNotifier.isVisible('size');
    final showDate = colNotifier.isVisible('date');
    final showExt = colNotifier.isVisible('ext');

    Widget colLabel(String label, SortBy by, {double? width}) {
      final isPrimary = panel.sortBy == by;
      final isSecondary = panel.secondarySortBy == by;
      final primaryArrow = isPrimary
          ? (panel.sortOrder == SortOrder.ascending ? ' ↑' : ' ↓')
          : '';
      final secondaryArrow = isSecondary && !isPrimary
          ? (panel.secondarySortOrder == SortOrder.ascending ? '↑' : '↓')
          : '';
      final cell = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label + primaryArrow,
            style: style.copyWith(
              color: isPrimary ? theme.colorScheme.primary : style.color,
            ),
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
          if (secondaryArrow.isNotEmpty)
            Text(
              secondaryArrow,
              style: style.copyWith(
                fontSize: 9,
                color: theme.colorScheme.tertiary,
              ),
            ),
        ],
      );
      return GestureDetector(
        onTap: () => isPrimary ? panel.toggleSortOrder() : panel.setSortBy(by),
        onSecondaryTap: () => isSecondary && !isPrimary
            ? panel.setSecondarySortBy(null)
            : panel.setSecondarySortBy(by),
        onLongPress: () => isSecondary && !isPrimary
            ? panel.setSecondarySortBy(null)
            : panel.setSecondarySortBy(by),
        child: Tooltip(
          message: isSecondary
              ? 'Secondary sort (right-click/long-press to clear)'
              : 'Right-click/long-press to set as secondary sort',
          child: width != null ? SizedBox(width: width, child: cell) : cell,
        ),
      );
    }

    // Drag handle between columns
    Widget dragHandle(String colKey) {
      return GestureDetector(
        onHorizontalDragUpdate: (details) {
          final current = colWidths[colKey] ?? 62.0;
          final newW = (current + details.delta.dx).clamp(36.0, 200.0);
          ref.read(columnWidthsProvider(side).notifier).setWidth(colKey, newW);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: Container(
            width: 6,
            color: Colors.transparent,
            child: Center(
              child: Container(width: 1, height: 12, color: theme.dividerColor),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 20,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const SizedBox(
            width: 18 + 2 + 14 + 4,
          ), // icon space matches CompactFileTile
          Expanded(
            child: GestureDetector(
              onSecondaryTap: () =>
                  _showColumnMenu(context, ref, side, colNotifier),
              child: colLabel(
                panel.showingSearchResults ? 'Original path' : 'Name',
                SortBy.name,
              ),
            ),
          ),
          if (showSize) ...[
            dragHandle('size'),
            colLabel('Size', SortBy.size, width: sizeW),
          ],
          if (showDate) ...[
            dragHandle('date'),
            colLabel('Date', SortBy.date, width: dateW),
          ],
          if (showExt) ...[
            dragHandle('ext'),
            colLabel('Ext', SortBy.extension, width: extW),
          ],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Show column visibility menu on right-click of column header.
void _showColumnMenu(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  dynamic colNotifier,
) {
  final position = RelativeRect.fromLTRB(
    MediaQuery.sizeOf(context).width / 2,
    80,
    MediaQuery.sizeOf(context).width / 2 + 1,
    81,
  );
  showMenu<String>(
    context: context,
    position: position,
    items: [
      for (final col in ['size', 'date', 'ext'])
        CheckedPopupMenuItem<String>(
          value: col,
          checked: colNotifier.isVisible(col),
          child: Text(col[0].toUpperCase() + col.substring(1)),
        ),
    ],
  ).then((selected) {
    if (selected != null) {
      ref.read(columnWidthsProvider(side).notifier).toggleVisibility(selected);
    }
  });
}
