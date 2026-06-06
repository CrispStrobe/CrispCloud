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
    final isCompact = viewMode == PanelViewMode.full;
    final itemHeight = isCompact ? 26.0 : 64.0;

    try {
      if (files.isEmpty) {
        return const Center(child: Text('Empty folder'));
      }

      return ListView.builder(
        controller: scrollController,
        itemCount: files.length,
        itemExtent: itemHeight,
        itemBuilder: (context, index) {
          try {
            final file = files[index];
            final isSelected = panel.isSelected(file);

            if (isCompact) {
              return CompactFileTile(
                file: file,
                side: side,
                isSelected: isSelected,
                selectedFiles: panel.selection.toList(),
                showRelativePath: panel.isFlatView,
                onTap: (shiftKey, ctrlKey) =>
                    panel.toggleSelection(file, shiftKey: shiftKey, ctrlKey: ctrlKey),
                onDoubleTap: () => panel.navigateInto(file),
                onSecondaryTap: (details) =>
                    showFileContextMenu(context, ref, side, file, details.globalPosition),
              );
            }

            return FileListTile(
              file: file,
              side: side,
              isSelected: isSelected,
              selectedFiles: panel.selection.toList(),
              showRelativePath: panel.isFlatView,
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
        child: ListTile(
          selected: isSelected,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
          leading: iconWidget,
          title: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fileColor),
          ),
          subtitle: Row(
            children: [
              if (showRelativePath && file.path != null) ...[
                Expanded(
                  child: Text(file.path!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                ),
              ] else ...[
                if (!file.isFolder && file.displaySize != null) ...[
                  Text(formatBytes(file.displaySize!)),
                  if (file.updatedAt != null) ...[const Text(' • '), Text(formatDate(file.updatedAt!))],
                ] else if (file.updatedAt != null)
                  Text(formatDate(file.updatedAt!)),
              ],
            ],
          ),
          trailing: file.isFolder
              ? IconButton(icon: const Icon(Icons.chevron_right), onPressed: onDoubleTap)
              : null,
          onTap: () {
            final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
            final ctrlPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
            onTap(shiftPressed, ctrlPressed);
          },
          onLongPress: onDoubleTap,
        ),
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

/// Compact single-line tile for "Full" view mode — like Double Commander.
/// Shows: icon | name | (spacer) | size | date — all on one 26px row.
class CompactFileTile extends ConsumerWidget {
  final FileItem file;
  final PanelSide side;
  final bool isSelected;
  final List<FileItem> selectedFiles;
  final Function(bool shiftKey, bool ctrlKey) onTap;
  final VoidCallback onDoubleTap;
  final Function(TapDownDetails)? onSecondaryTap;
  final bool showRelativePath;

  const CompactFileTile({
    super.key,
    required this.file,
    required this.side,
    required this.isSelected,
    this.selectedFiles = const [],
    required this.onTap,
    required this.onDoubleTap,
    this.onSecondaryTap,
    this.showRelativePath = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorService = ref.watch(fileTypeColorProvider);
    final fileColor = colorService.colorForFile(file);
    final theme = Theme.of(context);

    final bgColor = isSelected
        ? theme.colorScheme.primaryContainer.withOpacity(0.6)
        : Colors.transparent;

    final style = TextStyle(fontSize: 12, color: fileColor, height: 1.0);
    final dimStyle = TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.55), height: 1.0);

    final sizeStr = (!file.isFolder && file.displaySize != null)
        ? formatBytes(file.displaySize!)
        : '';
    final dateStr = file.updatedAt != null ? formatDate(file.updatedAt!) : '';

    return GestureDetector(
      onTap: () {
        final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
        final ctrlPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
        onTap(shiftPressed, ctrlPressed);
      },
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown: onSecondaryTap,
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(
              file.isFolder ? Icons.folder : getFileIcon(file.name),
              color: file.isFolder ? Colors.amber : fileColor,
              size: 14,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                showRelativePath && file.path != null ? file.path! : file.name,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (sizeStr.isNotEmpty) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 62,
                child: Text(sizeStr, style: dimStyle, textAlign: TextAlign.right, maxLines: 1),
              ),
            ],
            if (dateStr.isNotEmpty) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 78,
                child: Text(dateStr, style: dimStyle, textAlign: TextAlign.right, maxLines: 1),
              ),
            ],
            const SizedBox(width: 4),
          ],
        ),
      ),
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
