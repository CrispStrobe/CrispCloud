// widgets/file_list_view.dart

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/file_type_color_provider.dart';
import '../providers/providers.dart';
import '../providers/toolbar_provider.dart' show panelViewModeProvider;
import '../services/log_service.dart';
import '../services/panel_view_mode_service.dart' show PanelViewMode;
import '../utils/formatters.dart';
import 'file_context_menu.dart';

class FileListView extends ConsumerWidget {
  static final _log = Log('FileListView');

  final PanelSide side;
  final List<FileItem> files;
  final ScrollController scrollController;

  const FileListView({
    super.key,
    required this.side,
    required this.files,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(panelProvider(side));
    final viewMode = ref.watch(panelViewModeProvider(side));

    try {
      if (files.isEmpty) {
        return const Center(child: Text('Empty folder'));
      }

      final itemExtent = switch (viewMode) {
        PanelViewMode.brief => 32.0,
        PanelViewMode.full => 48.0,
        PanelViewMode.tree => 64.0,
      };

      final listView = ListView.builder(
        controller: scrollController,
        itemCount: files.length,
        itemExtent: itemExtent,
        itemBuilder: (context, index) {
          try {
            final file = files[index];
            final isSelected = panel.isSelected(file);

            return FileListTile(
              file: file,
              side: side,
              isSelected: isSelected,
              selectedFiles: panel.selection.toList(),
              showRelativePath: panel.isFlatView,
              viewMode: viewMode,
              onTap: (shiftKey, ctrlKey) {
                panel.toggleSelection(file, shiftKey: shiftKey, ctrlKey: ctrlKey);
              },
              onDoubleTap: () => panel.navigateInto(file),
              onSecondaryTap: (details) => showFileContextMenu(context, ref, side, file, details.globalPosition),
            );
          } catch (e) {
            _log.error('Error building file tile at index $index: $e');
            return ListTile(
              title: Text('Error loading item: $e'),
              leading: const Icon(Icons.error, color: Colors.red),
            );
          }
        },
      );

      // Full mode: add sortable column headers
      if (viewMode == PanelViewMode.full) {
        return Column(
          children: [
            _ColumnHeaders(panel: panel, side: side),
            Expanded(child: listView),
          ],
        );
      }

      return listView;
    } catch (e, stackTrace) {
      _log.error('Error building file list: $e', e, stackTrace);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error loading files: $e'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => panel.refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
  }
}

/// Sortable column headers for Full view mode.
class _ColumnHeaders extends StatelessWidget {
  final PanelNotifier panel;
  final PanelSide side;

  const _ColumnHeaders({required this.panel, required this.side});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortBy = panel.sortBy;
    final ascending = panel.sortOrder == SortOrder.ascending;

    Widget headerCell(String label, SortBy key, {int flex = 1}) {
      final isActive = sortBy == key;
      return Expanded(
        flex: flex,
        child: InkWell(
          onTap: () {
            if (isActive) {
              panel.toggleSortOrder();
            } else {
              panel.setSortBy(key);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 2),
                  Icon(
                    ascending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 48), // icon space
          headerCell('Name', SortBy.name, flex: 4),
          headerCell('Size', SortBy.size, flex: 2),
          headerCell('Date', SortBy.date, flex: 2),
          headerCell('Ext', SortBy.extension, flex: 1),
        ],
      ),
    );
  }
}

/// Data carried during a drag operation between panels.
class PanelDragData {
  final PanelSide sourceSide;
  final List<FileItem> files;
  const PanelDragData({required this.sourceSide, required this.files});
}

class FileListTile extends ConsumerWidget {
  final FileItem file;
  final PanelSide side;
  final bool isSelected;
  final List<FileItem> selectedFiles;
  final Function(bool shiftKey, bool ctrlKey) onTap;
  final VoidCallback onDoubleTap;
  final Function(TapDownDetails)? onSecondaryTap;
  /// When true, show relative path in subtitle (used in flat view).
  final bool showRelativePath;
  /// Controls rendering density: brief (name only), full (columns), tree (indented).
  final PanelViewMode viewMode;

  const FileListTile({
    super.key,
    required this.file,
    required this.side,
    required this.isSelected,
    this.selectedFiles = const [],
    required this.onTap,
    required this.onDoubleTap,
    this.onSecondaryTap,
    this.showRelativePath = false,
    this.viewMode = PanelViewMode.full,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorService = ref.watch(fileTypeColorProvider);
    final fileColor = colorService.colorForFile(file);

    // Symlink indicator
    final isLink = file.isSymlink == true;
    final iconWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          file.isFolder ? Icons.folder : getFileIcon(file.name),
          color: file.isFolder ? Colors.amber : fileColor,
          size: 32,
        ),
        if (isLink)
          const Positioned(
            bottom: -2,
            right: -2,
            child: Icon(Icons.link, size: 14, color: Colors.grey),
          ),
      ],
    );

    // Build tile content based on view mode
    final Widget tileContent;
    switch (viewMode) {
      case PanelViewMode.brief:
        // Compact: icon + name only, no subtitle
        tileContent = ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -4),
          selected: isSelected,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
          leading: SizedBox(width: 20, child: Icon(
            file.isFolder ? Icons.folder : getFileIcon(file.name),
            color: file.isFolder ? Colors.amber : fileColor,
            size: 18,
          )),
          title: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: fileColor),
          ),
          onTap: () {
            final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
            final ctrlPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
            onTap(shiftPressed, ctrlPressed);
          },
          onLongPress: onDoubleTap,
        );
      case PanelViewMode.full:
        // Full: column layout matching headers (Name | Size | Date | Ext)
        tileContent = InkWell(
          onTap: () {
            final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
            final ctrlPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
            onTap(shiftPressed, ctrlPressed);
          },
          onDoubleTap: onDoubleTap,
          child: Container(
            color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5) : null,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                SizedBox(width: 40, child: iconWidget),
                // Name
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: showRelativePath && file.path != null
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fileColor)),
                              Text(file.path!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          )
                        : Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fileColor)),
                  ),
                ),
                // Size
                Expanded(
                  flex: 2,
                  child: Text(
                    file.displaySize != null ? formatBytes(file.displaySize!) : '',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                // Date
                Expanded(
                  flex: 2,
                  child: Text(
                    file.updatedAt != null ? formatDate(file.updatedAt!) : '',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                // Extension
                Expanded(
                  flex: 1,
                  child: Text(
                    file.extension.toUpperCase(),
                    style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        );
      case PanelViewMode.tree:
        // Tree mode: same as old ListTile layout
        tileContent = ListTile(
          selected: isSelected,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
          leading: iconWidget,
          title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fileColor)),
          subtitle: Row(
            children: [
              if (showRelativePath && file.path != null) ...[
                Expanded(child: Text(file.path!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
              ] else ...[
                if (!file.isFolder && file.displaySize != null) ...[
                  Text(formatBytes(file.displaySize!)),
                  if (file.updatedAt != null) ...[const Text(' • '), Text(formatDate(file.updatedAt!))],
                ] else if (file.updatedAt != null)
                  Text(formatDate(file.updatedAt!)),
              ],
            ],
          ),
          trailing: file.isFolder ? IconButton(icon: const Icon(Icons.chevron_right), onPressed: onDoubleTap) : null,
          onTap: () {
            final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
            final ctrlPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
            onTap(shiftPressed, ctrlPressed);
          },
          onLongPress: onDoubleTap,
        );
    }

    final tile = GestureDetector(
      onSecondaryTapDown: onSecondaryTap,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
            onDoubleTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: tileContent,
      ),
    );

    // Wrap with LongPressDraggable for inter-panel drag
    // If this file is selected and there are multiple selections, drag all selected files
    final dragFiles = isSelected && selectedFiles.length > 1
        ? selectedFiles
        : [file];
    final dragCount = dragFiles.length;

    // On mobile, use shorter delay for touch drag; on desktop, use long press
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return LongPressDraggable<PanelDragData>(
      delay: isMobile ? const Duration(milliseconds: 200) : const Duration(milliseconds: 500),
      data: PanelDragData(sourceSide: side, files: dragFiles),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(file.isFolder ? Icons.folder : getFileIcon(file.name), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    dragCount > 1 ? '${file.name} +${dragCount - 1}' : file.name,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            // Count badge for multi-file drag
            if (dragCount > 1)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$dragCount',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }
}

IconData getFileIcon(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'pdf': return Icons.picture_as_pdf;
    case 'doc': case 'docx': return Icons.description;
    case 'xls': case 'xlsx': case 'csv': return Icons.table_chart;
    case 'ppt': case 'pptx': return Icons.slideshow;
    case 'txt': case 'md': return Icons.text_snippet;
    case 'jpg': case 'jpeg': case 'png': case 'gif': case 'bmp': case 'webp': return Icons.image;
    case 'mp4': case 'avi': case 'mov': case 'mkv': case 'webm': return Icons.video_file;
    case 'mp3': case 'wav': case 'flac': case 'ogg': case 'm4a': return Icons.audio_file;
    case 'zip': case 'rar': case '7z': case 'tar': case 'gz': return Icons.archive;
    case 'html': case 'css': case 'js': case 'json': case 'xml': case 'py': case 'java': case 'cpp': case 'c': case 'dart': return Icons.code;
    default: return Icons.insert_drive_file;
  }
}
