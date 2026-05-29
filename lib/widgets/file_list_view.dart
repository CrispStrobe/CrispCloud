// widgets/file_list_view.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../services/app_state.dart';
import 'file_context_menu.dart';

class FileListView extends StatelessWidget {
  final PanelSide side;
  final List<FileItem> files;
  final AppState appState;
  final ScrollController scrollController;

  const FileListView({
    super.key,
    required this.side,
    required this.files,
    required this.appState,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    try {
      if (files.isEmpty) {
        return const Center(
          child: Text('Empty folder'),
        );
      }

      return ListView.builder(
        controller: scrollController,
        itemCount: files.length,
        itemBuilder: (context, index) {
          try {
            final file = files[index];
            final isSelected = appState.isSelected(side, file);

            return FileListTile(
              file: file,
              side: side,
              isSelected: isSelected,
              onTap: (shiftKey, ctrlKey) {
                appState.toggleSelection(side, file, shiftKey: shiftKey, ctrlKey: ctrlKey);
              },
              onDoubleTap: () => appState.navigateInto(side, file),
              onSecondaryTap: (details) => showFileContextMenu(context, appState, side, file, details.globalPosition),
            );
          } catch (e) {
            debugPrint('Error building file tile at index $index: $e');
            return ListTile(
              title: Text('Error loading item: $e'),
              leading: const Icon(Icons.error, color: Colors.red),
            );
          }
        },
      );
    } catch (e, stackTrace) {
      debugPrint('Error building file list: $e');
      debugPrint('Stack trace: $stackTrace');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error loading files: $e'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => appState.refreshPanel(side),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
  }
}

class FileListTile extends StatelessWidget {
  final FileItem file;
  final PanelSide side;
  final bool isSelected;
  final Function(bool shiftKey, bool ctrlKey) onTap;
  final VoidCallback onDoubleTap;
  final Function(TapDownDetails)? onSecondaryTap;

  const FileListTile({
    super.key,
    required this.file,
    required this.side,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: onSecondaryTap,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              onDoubleTap();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: ListTile(
          selected: isSelected,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
          leading: Icon(
            file.isFolder ? Icons.folder : getFileIcon(file.name),
            color: file.isFolder ? Colors.amber : null,
            size: 32,
          ),
          title: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              if (!file.isFolder && file.size != null) ...[
                Text(formatBytes(file.size!)),
                if (file.updatedAt != null) ...[
                  const Text(' • '),
                  Text(formatDate(file.updatedAt!)),
                ],
              ] else if (file.updatedAt != null)
                Text(formatDate(file.updatedAt!)),
            ],
          ),
          trailing: file.isFolder
              ? IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: onDoubleTap,
                )
              : null,
          onTap: () {
            final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
            final ctrlPressed = HardwareKeyboard.instance.isControlPressed ||
                              HardwareKeyboard.instance.isMetaPressed;
            onTap(shiftPressed, ctrlPressed);
          },
          onLongPress: onDoubleTap,
        ),
      ),
    );
  }
}

// Shared utility functions

IconData getFileIcon(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf;
    case 'doc':
    case 'docx':
      return Icons.description;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return Icons.table_chart;
    case 'ppt':
    case 'pptx':
      return Icons.slideshow;
    case 'txt':
    case 'md':
      return Icons.text_snippet;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'bmp':
    case 'webp':
      return Icons.image;
    case 'mp4':
    case 'avi':
    case 'mov':
    case 'mkv':
    case 'webm':
      return Icons.video_file;
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'ogg':
    case 'm4a':
      return Icons.audio_file;
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return Icons.archive;
    case 'html':
    case 'css':
    case 'js':
    case 'json':
    case 'xml':
    case 'py':
    case 'java':
    case 'cpp':
    case 'c':
    case 'dart':
      return Icons.code;
    default:
      return Icons.insert_drive_file;
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String formatDate(DateTime date) {
  final now = DateTime.now();
  final difference = now.difference(date);

  if (difference.inDays == 0) {
    return 'Today';
  } else if (difference.inDays == 1) {
    return 'Yesterday';
  } else if (difference.inDays < 7) {
    return '${difference.inDays} days ago';
  } else {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

String formatDateFull(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final fileDate = DateTime(date.year, date.month, date.day);

  String dateStr;
  if (fileDate == today) {
    dateStr = 'Today';
  } else if (fileDate == yesterday) {
    dateStr = 'Yesterday';
  } else {
    dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  return '$dateStr at $timeStr';
}
