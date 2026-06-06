// widgets/file_list_view.dart

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../providers/toolbar_provider.dart' show panelViewModeProvider;
import '../services/log_service.dart';
import '../services/panel_view_mode_service.dart' show PanelViewMode;
import '../utils/formatters.dart';
import 'file_context_menu.dart';

class FileListView extends ConsumerWidget {
  static const _log = Log('FileListView');

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
    final cursorIndex = panel.cursorIndex;

    // Auto-scroll to cursor when it changes
    final itemToScroll = panel.itemToScrollTo;
    if (itemToScroll != null && scrollController.hasClients) {
      final idx = files.indexOf(itemToScroll);
      if (idx != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!scrollController.hasClients) return;
          final itemTop = idx * itemHeight;
          final itemBot = itemTop + itemHeight;
          final viewMin = scrollController.offset;
          final viewportH = scrollController.position.viewportDimension;
          final viewMax = viewMin + viewportH;
          final maxScroll = scrollController.position.maxScrollExtent;

          // DC-style: scroll the minimum distance to keep cursor visible.
          // Cursor above viewport → scroll up so cursor is at top edge.
          // Cursor below viewport → scroll down so cursor is at bottom edge.
          double? target;
          if (itemTop < viewMin) {
            target = itemTop; // scroll up: cursor at top
          } else if (itemBot > viewMax) {
            target = itemBot - viewportH; // scroll down: cursor at bottom
          }

          if (target != null) {
            scrollController.animateTo(
              target.clamp(0.0, maxScroll),
              duration: const Duration(milliseconds: 80),
              curve: Curves.easeOut,
            );
          }
          panel.clearItemToScrollTo();
        });
      }
    }

    try {
      if (files.isEmpty) {
        return const Center(child: Text('Empty folder'));
      }

      final listView = ListView.builder(
        controller: scrollController,
        itemCount: files.length,
        itemExtent: itemHeight,
        itemBuilder: (context, index) {
          try {
            final file = files[index];
            final isSelected = panel.isSelected(file);
            final isCursor = index == cursorIndex;

            if (isCompact) {
              return CompactFileTile(
                file: file,
                side: side,
                isSelected: isSelected,
                isCursor: isCursor,
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
              isCursor: isCursor,
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

      // Wrap with a Focus that intercepts arrow/space/enter BEFORE the
      // ListView's own Shortcuts handler consumes them for scrolling.
      // autofocus = true when this is the active panel so compact tiles
      // (which have no inner Focus widget) still drive key events here.
      final isActivePanel = ref.read(activePanelProvider) == side;
      return Focus(
        autofocus: isActivePanel,
        canRequestFocus: true,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final activePanel = ref.read(activePanelProvider);
          if (side != activePanel) return KeyEventResult.ignored;

          final isShift = HardwareKeyboard.instance.isShiftPressed;
          final p = ref.read(panelProvider(side));

          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            isShift ? p.shiftMoveCursor(1) : p.moveCursor(1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            isShift ? p.shiftMoveCursor(-1) : p.moveCursor(-1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.insert) {
            p.spaceSelectAndAdvance();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            final item = p.cursorItem;
            if (item != null) p.navigateInto(item);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.home) {
            p.moveCursorTo(0);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.end) {
            p.moveCursorTo((p.filteredFiles?.length ?? 1) - 1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.pageDown ||
              event.logicalKey == LogicalKeyboardKey.pageUp) {
            final pageSize = scrollController.hasClients
                ? (scrollController.position.viewportDimension / itemHeight).floor().clamp(1, 999)
                : 15;
            final delta = event.logicalKey == LogicalKeyboardKey.pageDown ? pageSize : -pageSize;
            p.moveCursor(delta);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.numpadMultiply) {
            p.invertSelection();
            return KeyEventResult.handled;
          }
          final isCtrl = HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          final isAlt = HardwareKeyboard.instance.isAltPressed;
          if (!isCtrl && !isAlt && event is KeyDownEvent) {
            // Escape: clear type-ahead if active
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              if (p.isTypeahead) { p.clearTypeahead(); return KeyEventResult.handled; }
              return KeyEventResult.ignored;
            }
            // Backspace: remove last type-ahead char
            if (event.logicalKey == LogicalKeyboardKey.backspace && p.isTypeahead) {
              p.typeaheadBackspace();
              return KeyEventResult.handled;
            }
            // Printable char: enter type-ahead mode (accumulates + filters)
            final char = event.character;
            if (char != null && char.isNotEmpty && char.codeUnitAt(0) >= 32) {
              p.typeaheadAppend(char);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: listView,
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
  final bool isCursor;
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
    this.isCursor = false,
    this.selectedFiles = const [],
    required this.onTap,
    required this.onDoubleTap,
    this.onSecondaryTap,
    this.showRelativePath = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(panelProvider(side));
    final isRenaming = panel.renamingItem == file;
    final colorService = ref.watch(fileTypeColorProvider);
    final fileColor = colorService.colorForFile(file);

    // Inline rename mode: replace the whole tile with an editable field
    if (isRenaming) {
      return _InlineRenameField(
        file: file,
        side: side,
        isCursor: isCursor,
        isSelected: isSelected,
      );
    }

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
        child: Container(
          decoration: isCursor
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  ),
                )
              : null,
          child: ListTile(
          selected: isSelected,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.65),
          leading: file.name == '..'
              ? const Icon(Icons.arrow_upward, size: 28, color: Colors.amber)
              : iconWidget,
          title: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected ? Theme.of(context).colorScheme.onPrimaryContainer : fileColor,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: file.name == '..' ? null : Row(
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
        ),  // Container (cursor border)
      ),
    );

    // ".." cannot be dragged
    if (file.name == '..') return tile;

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
  final bool isCursor;
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
    this.isCursor = false,
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

    // Selected = fill; cursor = left border (can combine both)
    final bgColor = isSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : Colors.transparent;

    final nameStyle = TextStyle(
      fontSize: 12,
      color: isSelected ? theme.colorScheme.onPrimaryContainer : fileColor,
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      height: 1.0,
    );
    final dimStyle = TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.55), height: 1.0);

    final sizeStr = file.name == '..'
        ? ''
        : file.isFolder
            ? '<DIR>'
            : (file.displaySize != null ? formatBytes(file.displaySize!) : '');
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
        decoration: BoxDecoration(
          color: bgColor,
          border: isCursor
              ? Border(
                  left: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 3,
                  ),
                )
              : null,
        ),
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
                style: nameStyle,
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

/// Inline rename text field shown in-place of the filename when F2 is pressed.
class _InlineRenameField extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelSide side;
  final bool isCursor;
  final bool isSelected;

  const _InlineRenameField({
    required this.file,
    required this.side,
    required this.isCursor,
    required this.isSelected,
  });

  @override
  ConsumerState<_InlineRenameField> createState() => _InlineRenameFieldState();
}

class _InlineRenameFieldState extends ConsumerState<_InlineRenameField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    final name = widget.file.name;
    _ctrl = TextEditingController(text: name);
    _focus = FocusNode();
    // Select filename without extension (like DC)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      final dotIdx = name.lastIndexOf('.');
      if (!widget.file.isFolder && dotIdx > 0) {
        _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: dotIdx);
      } else {
        _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: name.length);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() => ref.read(panelProvider(widget.side)).commitRename(_ctrl.text);
  void _cancel() => ref.read(panelProvider(widget.side)).cancelRename();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = widget.isSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.2);

    return Container(
      height: ref.read(panelViewModeProvider(widget.side)) == PanelViewMode.full ? 26.0 : 64.0,
      color: bgColor,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) _cancel();
          }
        },
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          autofocus: true,
          onSubmitted: (_) => _commit(),
          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
            ),
          ),
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
