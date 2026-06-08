// widgets/file_panel.dart

import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../providers/toolbar_provider.dart' show columnWidthsProvider, panelViewModeProvider;
import '../services/panel_view_mode_service.dart' show PanelViewMode;
import 'file_column_view.dart';
import 'file_grid_view.dart';
import 'file_toolbar.dart';
import 'file_list_view.dart' show FileListView, PanelDragData;
import 'file_tree_view_stub.dart'
    if (dart.library.io) 'file_tree_view.dart';
import 'drive_bar.dart';
import 'panel_tab_bar.dart';
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
  bool _isDragging = false;
  bool _isEditingPath = false;
  late final ScrollController _scrollController;
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _pathController = TextEditingController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(panelProvider(widget.side));
    final errors = ref.watch(errorProvider);

    // Show error if present
    if (errors.lastError != null && widget.side == PanelSide.local) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errors.lastError!),
              action: SnackBarAction(
                label: 'Browse',
                onPressed: () => panel.pickLocalDirectory(),
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      });
    }

    final files = panel.filteredFiles;
    final currentPath = panel.currentPath;
    final selection = panel.selection;

    // Web empty state
    if (kIsWeb && widget.side == PanelSide.local && (files == null || files.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('No folder selected'),
            ElevatedButton(
              onPressed: () => panel.pickLocalDirectory(),
              child: const Text('Open Local Folder'),
            ),
          ],
        ),
      );
    }

    // Wrap in DragTarget for inter-panel file dragging
    final panelContent = _buildPanelContent(context, panel, files, currentPath, selection);

    // Flutter DragTarget for cross-panel drops
    final Widget content = DragTarget<PanelDragData>(
      onWillAcceptWithDetails: (details) {
        // Accept drops from the OTHER panel only
        return details.data.sourceSide != widget.side;
      },
      onAcceptWithDetails: (details) async {
        final data = details.data;
        final transfers = ref.read(transferProvider);
        if (data.sourceSide == PanelSide.local && widget.side == PanelSide.remote) {
          await transfers.uploadFiles(data.files);
        } else if (data.sourceSide == PanelSide.remote && widget.side == PanelSide.local) {
          await transfers.downloadFiles(data.files);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isDropTarget = candidateData.isNotEmpty;
        if (!isDropTarget) return panelContent;

        // Determine operation hint
        final sourceIsLocal = candidateData.first?.sourceSide == PanelSide.local;
        final opIcon = sourceIsLocal ? Icons.upload : Icons.download;
        final opLabel = sourceIsLocal ? 'Upload' : 'Download';
        final fileCount = candidateData.first?.files.length ?? 0;

        return Stack(
          children: [
            panelContent,
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(opIcon, size: 48, color: Theme.of(context).colorScheme.primary),
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
      child: kIsWeb
          ? content
          : DropTarget(
              onDragEntered: (_) => setState(() => _isDragging = true),
              onDragExited: (_) => setState(() => _isDragging = false),
              onDragDone: (details) async {
                setState(() => _isDragging = false);
                final auth = ref.read(authProvider);
                if (widget.side == PanelSide.remote && auth.isConnected) {
                  final items = details.files.map((xFile) => FileItem(
                    name: xFile.name,
                    path: xFile.path,
                    isFolder: false,
                  )).toList();
                  await ref.read(transferProvider).uploadFiles(items);
                }
              },
              child: content,
            ),
    );
  }

  Widget _buildFileView(PanelSide side, List<FileItem> files) {
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

  Widget _buildPanelContent(
    BuildContext context,
    PanelNotifier panel,
    List<FileItem>? files,
    String currentPath,
    Set<FileItem> selection,
  ) {
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
          FileToolbar(
            side: widget.side,
            currentPath: currentPath,
          ),
          DriveBar(side: widget.side),
          if (currentPath != '/' && currentPath != '')
            _isEditingPath
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pathController,
                            autofocus: true,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(),
                              hintText: 'Enter path...',
                              prefixIcon: Icon(Icons.folder_open, size: 18),
                            ),
                            onSubmitted: (value) {
                              if (value.isNotEmpty) {
                                panel.navigateToPath(value);
                              }
                              setState(() => _isEditingPath = false);
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Cancel',
                          onPressed: () => setState(() => _isEditingPath = false),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: FileBreadcrumbs(
                          side: widget.side,
                          currentPath: currentPath,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        tooltip: 'Edit path',
                        onPressed: () {
                          _pathController.text = currentPath;
                          setState(() => _isEditingPath = true);
                        },
                      ),
                    ],
                  ),
          // Search results header: shows when panel is displaying search results
          if (panel.showingSearchResults)
            Container(
              color: Theme.of(context).colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.search, size: 14,
                      color: Theme.of(context).colorScheme.onSecondaryContainer),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Search results — ${files?.length ?? 0} file(s)',
                      style: TextStyle(fontSize: 12,
                          color: Theme.of(context).colorScheme.onSecondaryContainer),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => panel.clearSearchResults(),
                    child: Icon(Icons.close, size: 14,
                        color: Theme.of(context).colorScheme.onSecondaryContainer),
                  ),
                ],
              ),
            ),
          // Selection bar: off by default (DC mode — info is in status bar).
          // Enable in settings for touch/tablet mode.
          if (ref.watch(showSelectionBarProvider) && selection.isNotEmpty)
            FileSelectionBar(
              side: widget.side,
              selection: selection,
            ),
          if (ref.watch(panelViewModeProvider(widget.side)) == PanelViewMode.full)
            _CompactColumnHeader(side: widget.side, panel: panel),
          Expanded(
            child: files == null
                ? const Center(child: CircularProgressIndicator())
                : files.isEmpty
                    ? Center(
                        child: _isDragging && widget.side == PanelSide.remote
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.upload_file, size: 64, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(height: 16),
                                  Text('Drop files here to upload', style: Theme.of(context).textTheme.titleMedium),
                                ],
                              )
                            : widget.side == PanelSide.remote && !ref.read(authProvider).isConnected
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.cloud_off, size: 56,
                                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                                      const SizedBox(height: 12),
                                      Text('Not connected',
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.login, size: 18),
                                        label: const Text('Connect to cloud'),
                                        onPressed: () => showConnectionDialogScreen(context),
                                      ),
                                    ],
                                  )
                                : const Text('Empty folder'),
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
                              left: 0, right: 0, bottom: 0,
                              child: Container(
                                color: Theme.of(context).colorScheme.inverseSurface.withValues(alpha: 0.9),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.search, size: 16,
                                        color: Theme.of(context).colorScheme.onInverseSurface),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        panel.filterQuery,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Theme.of(context).colorScheme.onInverseSurface,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => panel.clearTypeahead(),
                                      child: Icon(Icons.close, size: 16,
                                          color: Theme.of(context).colorScheme.onInverseSurface),
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
    final style = TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7));
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
          ? (panel.sortOrder == SortOrder.ascending ? ' ↑' : ' ↓') : '';
      final secondaryArrow = isSecondary && !isPrimary
          ? (panel.secondarySortOrder == SortOrder.ascending ? '↑' : '↓') : '';
      final cell = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label + primaryArrow, style: style.copyWith(
            color: isPrimary ? theme.colorScheme.primary : style.color,
          ), maxLines: 1, overflow: TextOverflow.clip),
          if (secondaryArrow.isNotEmpty)
            Text(secondaryArrow, style: style.copyWith(
              fontSize: 9, color: theme.colorScheme.tertiary,
            )),
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
              child: Container(
                width: 1,
                height: 12,
                color: theme.dividerColor,
              ),
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
          const SizedBox(width: 18 + 2 + 14 + 4), // icon space matches CompactFileTile
          Expanded(child: GestureDetector(
            onSecondaryTap: () => _showColumnMenu(context, ref, side, colNotifier),
            child: colLabel('Name', SortBy.name),
          )),
          if (showSize) ...[dragHandle('size'), colLabel('Size', SortBy.size, width: sizeW)],
          if (showDate) ...[dragHandle('date'), colLabel('Date', SortBy.date, width: dateW)],
          if (showExt) ...[dragHandle('ext'), colLabel('Ext', SortBy.extension, width: extW)],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Show column visibility menu on right-click of column header.
void _showColumnMenu(
    BuildContext context, WidgetRef ref, PanelSide side, dynamic colNotifier) {
  final position = RelativeRect.fromLTRB(
    MediaQuery.sizeOf(context).width / 2, 80, MediaQuery.sizeOf(context).width / 2 + 1, 81);
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
