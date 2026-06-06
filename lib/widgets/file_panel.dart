// widgets/file_panel.dart

import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import 'file_column_view.dart';
import 'file_grid_view.dart';
import 'file_toolbar.dart';
import 'file_list_view.dart' show FileListView, PanelDragData, getFileIcon;
import 'panel_tab_bar.dart';

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
    Widget content = DragTarget<PanelDragData>(
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
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
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
        color: widget.isActive ? null : Colors.black.withOpacity(0.02),
        border: _isDragging
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        children: [
          PanelTabBar(
            tabs: panel.tabs,
            activeTabId: panel.activeTabId,
            onTabSelected: (id) => panel.selectTab(id),
            onTabClosed: (id) => panel.closeTab(id),
            onNewTab: () => panel.addTab(),
            onTabPinToggle: (id) => panel.toggleTabPin(id),
          ),
          FileToolbar(
            side: widget.side,
            currentPath: currentPath,
          ),
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
                        icon: const Icon(Icons.edit, size: 16),
                        tooltip: 'Edit path',
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          _pathController.text = currentPath;
                          setState(() => _isEditingPath = true);
                        },
                      ),
                    ],
                  ),
          if (selection.length > 1)
            FileSelectionBar(
              side: widget.side,
              selection: selection,
            ),
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
                            : const Text('Empty folder'),
                      )
                    // Pull-to-refresh on mobile
                    : RefreshIndicator(
                        onRefresh: () => panel.refresh(),
                        child: _buildFileView(widget.side, files),
                      ),
          ),
        ],
      ),
    );
  }
}
