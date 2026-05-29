// widgets/file_panel.dart

import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/app_state.dart';
import '../models/file_item.dart';
import 'package:provider/provider.dart';
import '../models/panel_side.dart';

import 'file_toolbar.dart';
import 'file_list_view.dart';

class FilePanel extends StatefulWidget {
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
  State<FilePanel> createState() => _FilePanelState();
}

class _FilePanelState extends State<FilePanel> {
  bool _isDragging = false;
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

    final appState = context.watch<AppState>();

    // Show error if present
    if (appState.lastError != null && widget.side == PanelSide.local) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(appState.lastError!),
              action: SnackBarAction(
                label: 'Browse',
                onPressed: () => appState.pickLocalDirectory(),
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      });
    }

    // --- FIX: Use new getter 'localFileItems' ---
    final files = widget.side == PanelSide.local ? appState.localFileItems : appState.remoteFiles;
    // --- END FIX ---

    final currentPath = widget.side == PanelSide.local ? appState.localPath : appState.remotePath;
    final selection = widget.side == PanelSide.local ? appState.localSelection : appState.remoteSelection;

    // --- Scroll logic ---
    FileItem? itemToScroll = appState.itemToScrollTo;

    if (itemToScroll != null && files != null) {
      final index = files.indexWhere((f) =>
        (f.uuid != null && f.uuid == itemToScroll.uuid) ||
        (f.path != null && f.path == itemToScroll.path)
      );

      if (index != -1) {
        bool belongsToPanel = (widget.side == PanelSide.local && itemToScroll.path != null && itemToScroll.path!.startsWith(appState.localPath)) ||
                              (widget.side == PanelSide.remote && itemToScroll.uuid != null && (itemToScroll.path ?? '/').startsWith(appState.remotePath));

        if (belongsToPanel) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              final offset = index * 56.0;
              _scrollController.animateTo(
                offset,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
              appState.clearItemToScrollTo();
            }
          });
        }
      } else {
        appState.clearItemToScrollTo();
      }
    }
    // --- End scroll logic ---

    // Empty State prompt
    if (kIsWeb && widget.side == PanelSide.local && (files == null || files.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('No folder selected'),
            ElevatedButton(
              onPressed: () => appState.pickLocalDirectory(),
              child: const Text('Open Local Folder'),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      // --- FIX: Disable drop target on web ---
      child: kIsWeb ? _buildPanelContent(context, appState, files, currentPath, selection) : DropTarget(
      // --- END FIX ---
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (details) async {
          setState(() => _isDragging = false);
          if (widget.side == PanelSide.remote && appState.isConnected) {
            final items = details.files.map((xFile) => FileItem(
              name: xFile.name,
              path: xFile.path,
              isFolder: false,
            )).toList();
            await appState.uploadFiles(items);
          }
        },
        child: _buildPanelContent(context, appState, files, currentPath, selection),
      ),
    );
  }

  Widget _buildPanelContent(BuildContext context, AppState appState, List<FileItem>? files, String currentPath, Set<FileItem> selection) {
    return Container(
      decoration: BoxDecoration(
        color: widget.isActive ? null : Colors.black.withOpacity(0.02),
        border: _isDragging
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
      ),
      child: Column(
        children: [
          FileToolbar(
            side: widget.side,
            appState: appState,
            currentPath: currentPath,
          ),
          if (currentPath != '/' && currentPath != '')
            FileBreadcrumbs(
              side: widget.side,
              appState: appState,
              currentPath: currentPath,
            ),
          if (selection.isNotEmpty)
            FileSelectionBar(
              side: widget.side,
              appState: appState,
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
                                  Icon(
                                    Icons.upload_file,
                                    size: 64,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Drop files here to upload',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ],
                              )
                            : const Text('Empty folder'),
                      )
                    : FileListView(
                        side: widget.side,
                        files: files,
                        appState: appState,
                        scrollController: _scrollController,
                      ),
          ),
        ],
      ),
    );
  }
}
