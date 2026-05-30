// lib/widgets/file_column_view.dart
//
// Finder-style column view for file browsing.
// Each folder expands a new column to the right showing its contents.
// Clicking a file selects it; clicking a folder opens it in a new column.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';
import 'file_context_menu.dart';
import 'file_list_view.dart' show getFileIcon;

class FileColumnView extends ConsumerStatefulWidget {
  final PanelSide side;
  final List<FileItem> files;
  final ScrollController scrollController;

  const FileColumnView({
    super.key,
    required this.side,
    required this.files,
    required this.scrollController,
  });

  @override
  ConsumerState<FileColumnView> createState() => _FileColumnViewState();
}

class _FileColumnViewState extends ConsumerState<FileColumnView> {
  /// Stack of (path, files) for each column after the root.
  final List<_ColumnData> _columns = [];
  final ScrollController _horizontalScroll = ScrollController();

  @override
  void didUpdateWidget(covariant FileColumnView old) {
    super.didUpdateWidget(old);
    // If the root files changed (navigated to different dir), clear columns
    if (old.files != widget.files) {
      _columns.clear();
    }
  }

  @override
  void dispose() {
    _horizontalScroll.dispose();
    super.dispose();
  }

  void _onFolderTap(FileItem folder, int columnIndex) {
    // Remove columns after this one
    if (columnIndex < _columns.length) {
      _columns.removeRange(columnIndex, _columns.length);
    }

    // Load the folder contents
    final panel = ref.read(panelProvider(widget.side));
    panel.navigateInto(folder);

    // We'll add a placeholder column; the actual files will come from the panel
    _columns.add(_ColumnData(
      parentFolder: folder,
      files: null, // Will be populated on next build via panel state
    ));

    setState(() {});

    // Scroll right to show the new column
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_horizontalScroll.hasClients) {
        _horizontalScroll.animateTo(
          _horizontalScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onFileTap(FileItem file, int columnIndex) {
    // Remove columns after this one (a file doesn't expand further)
    if (columnIndex < _columns.length) {
      _columns.removeRange(columnIndex, _columns.length);
    }

    // Select the file
    final panel = ref.read(panelProvider(widget.side));
    final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final ctrlPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    panel.toggleSelection(file, shiftKey: shiftPressed, ctrlKey: ctrlPressed);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(panelProvider(widget.side));
    final currentFiles = panel.files ?? widget.files;

    // The root column always shows the current directory files.
    // Additional columns show contents of navigated subfolders.
    // For simplicity, we use a flat approach: the current panel state
    // IS the deepest column, and we rebuild from scratch.

    return SingleChildScrollView(
      controller: _horizontalScroll,
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildColumn(context, currentFiles, panel, 0),
          ],
        ),
      ),
    );
  }

  Widget _buildColumn(
    BuildContext context,
    List<FileItem> files,
    PanelNotifier panel,
    int columnIndex,
  ) {
    final theme = Theme.of(context);
    const columnWidth = 220.0;

    return Container(
      width: columnWidth,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: theme.dividerColor.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: ListView.builder(
        itemCount: files.length,
        itemExtent: 32,
        itemBuilder: (context, index) {
          final file = files[index];
          final isSelected = panel.isSelected(file);

          return GestureDetector(
            onSecondaryTapDown: (details) => showFileContextMenu(
                context, ref, widget.side, file, details.globalPosition),
            child: InkWell(
              onTap: () {
                if (file.isFolder) {
                  _onFolderTap(file, columnIndex);
                } else {
                  _onFileTap(file, columnIndex);
                }
              },
              onDoubleTap: () => panel.navigateInto(file),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: isSelected
                    ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                    : null,
                child: Row(
                  children: [
                    Icon(
                      file.isFolder
                          ? Icons.folder
                          : getFileIcon(file.name),
                      size: 16,
                      color: file.isFolder
                          ? Colors.amber
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        file.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (!file.isFolder && file.size != null)
                      Text(
                        formatBytes(file.size!),
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (file.isFolder)
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ColumnData {
  final FileItem parentFolder;
  final List<FileItem>? files;

  _ColumnData({required this.parentFolder, this.files});
}
