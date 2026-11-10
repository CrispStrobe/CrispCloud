// widgets/file_list_view.dart

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/provider_operation_strings.dart';
import '../l10n/file_list_strings.dart';
import '../models/file_item.dart';
import '../models/file_view_configuration.dart';
import '../models/panel_side.dart';
import '../providers/focus_area_provider.dart';
import '../providers/terminal_provider.dart' show showTerminalProvider;
import '../providers/providers.dart';
import '../providers/toolbar_provider.dart'
    show columnWidthsProvider, panelViewModeProvider, fileColumnsProvider;
import '../services/log_service.dart';
import '../services/panel_view_mode_service.dart' show PanelViewMode;
import '../services/keyboard_shortcut_service.dart';
import '../utils/formatters.dart';
import 'file_context_menu.dart';
import 'pattern_selection_dialog.dart';

String _collectionPathLabel(FileItem file) {
  final source = file.metadata?['collectionSource'];
  return '${source == null ? '' : '$source · '}${file.path ?? file.name}';
}

String _collectionStatusLabel(FileItem file) {
  final state = file.metadata?['collectionState'];
  return switch (state) {
    'missing' => 'Missing at original path',
    'offline' => 'Original account unavailable',
    'changed' =>
      file.metadata?['collectionReplacement'] == true
          ? 'Replacement requires review'
          : 'Item changed since it was saved',
    _ => '',
  };
}

Widget _collectionStatus(BuildContext context, FileItem file) {
  final label = _collectionStatusLabel(file);
  final detail = file.metadata?['collectionDetail'];
  return Tooltip(
    message: '$label${detail == null ? '' : ': $detail'}',
    child: Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(
        file.metadata?['collectionState'] == 'offline'
            ? Icons.cloud_off_outlined
            : file.metadata?['collectionState'] == 'missing'
            ? Icons.broken_image_outlined
            : Icons.info_outline,
        semanticLabel: label,
        color: Theme.of(context).colorScheme.error,
        size: 16,
      ),
    ),
  );
}

/// Tracks modifier keys from the most recent pointer-down event.
/// Captured at pointer-down time (before GestureDetector.onTap fires),
/// which is more reliable on web than checking HardwareKeyboard in onTap.
class _PointerModifiers {
  static const _log = Log('PointerMod');
  static bool shiftPressed = false;
  static bool ctrlOrMetaPressed = false;

  static void update(PointerDownEvent event) {
    shiftPressed = HardwareKeyboard.instance.isShiftPressed;
    ctrlOrMetaPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (shiftPressed || ctrlOrMetaPressed) {
      _log.debug('shift=$shiftPressed ctrl/meta=$ctrlOrMetaPressed');
    }
  }
}

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
    final strings = FileListStrings(context);
    final panel = ref.watch(panelProvider(side));
    final viewMode = ref.watch(panelViewModeProvider(side));
    final double fontSize = ref.watch(fontSizeProvider);
    final String fontFamily = ref.watch(fontFamilyProvider);
    final TextStyle listTextStyle = TextStyle(
      fontFamily: fontFamily == 'system' ? null : fontFamily,
      fontSize: fontSize,
    );

    void handleTap(FileItem file, bool shiftKey, bool ctrlKey) {
      if (shiftKey || ctrlKey) {
        panel.toggleSelection(file, shiftKey: shiftKey, ctrlKey: ctrlKey);
      } else {
        panel.setCursorOnly(file);
      }
    }

    final isCompact = viewMode == PanelViewMode.full;
    final itemHeight = isCompact
        ? math.max(26.0, fontSize + 14.0)
        : math.max(64.0, fontSize + 46.0);
    // Cursor position within the displayed (possibly filtered) list.
    final cursorIndex = panel.displayedCursorIndex;

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
        return Center(child: Text(strings.text('Empty folder')));
      }

      final selectedFiles = panel.selection.toList();
      final listView = DefaultTextStyle.merge(
        style: listTextStyle,
        child: ListView.builder(
          controller: scrollController,
          itemCount: files.length,
          itemExtent: itemHeight,
          itemBuilder: (context, index) {
            try {
              final file = files[index];
              final isSelected = panel.isSelected(file);
              final isCursor = index == cursorIndex;

              if (panel.renamingItem == file) {
                return FileInlineRenameField(
                  file: file,
                  side: side,
                  isCursor: isCursor,
                  isSelected: isSelected,
                  height: itemHeight,
                  keepExtension: panel.renameKeepExtension,
                );
              }

              if (isCompact) {
                final origin = panel.originForOperation(file);
                return CompactFileTile(
                  file: file,
                  side: side,
                  isSelected: isSelected,
                  isCursor: isCursor,
                  selectedFiles: selectedFiles,
                  textStyle: listTextStyle,
                  sourceLabel: origin == null
                      ? null
                      : panel.storageDisplayName(origin.storageReference),
                  showRelativePath:
                      panel.isFlatView || panel.showingSearchResults,
                  onTap: (shiftKey, ctrlKey) =>
                      handleTap(file, shiftKey, ctrlKey),
                  onDoubleTap: () => panel.navigateInto(file),
                  onSecondaryTap: (details) => showFileContextMenu(
                    context,
                    ref,
                    side,
                    file,
                    details.globalPosition,
                  ),
                );
              }

              return FileListTile(
                file: file,
                side: side,
                isSelected: isSelected,
                isCursor: isCursor,
                selectedFiles: selectedFiles,
                textStyle: listTextStyle,
                showRelativePath:
                    panel.isFlatView || panel.showingSearchResults,
                onTap: (shiftKey, ctrlKey) =>
                    handleTap(file, shiftKey, ctrlKey),
                onDoubleTap: () => panel.navigateInto(file),
                onSecondaryTap: (details) => showFileContextMenu(
                  context,
                  ref,
                  side,
                  file,
                  details.globalPosition,
                ),
              );
            } catch (e) {
              _log.error('Error building file tile at index $index: $e');
              return ListTile(
                title: Text('Error loading item: $e'),
                leading: const Icon(Icons.error, color: Colors.red),
              );
            }
          },
        ),
      );

      // Wrap with a Focus that intercepts arrow/space/enter BEFORE the
      // ListView's own Shortcuts handler consumes them for scrolling.
      // autofocus = true when this is the active panel so compact tiles
      // (which have no inner Focus widget) still drive key events here.
      final focusArea = ref.read(focusAreaProvider);
      final terminalVisible = ref.watch(showTerminalProvider);
      final isActivePanel = focusArea.panelSide == side && !terminalVisible;
      if (isActivePanel) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (ref.read(showTerminalProvider)) return;
          if (ModalRoute.of(context)?.isCurrent != true) return;
          if (!panel.listFocusNode.hasFocus) {
            panel.listFocusNode.requestFocus();
          }
        });
      }
      return Listener(
        onPointerDown: (event) {
          _PointerModifiers.update(event);
          panel.listFocusNode.requestFocus();
        },
        child: Focus(
          focusNode: panel.listFocusNode,
          autofocus: isActivePanel,
          canRequestFocus: true,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (ref.read(focusAreaProvider).panelSide != side) {
              return KeyEventResult.ignored;
            }

            final isShift = HardwareKeyboard.instance.isShiftPressed;
            final p = ref.read(panelProvider(side));
            if (p.renamingItem != null) return KeyEventResult.ignored;
            final keyboard = HardwareKeyboard.instance;
            final shortcuts = ref.read(keyboardShortcutServiceProvider);
            final command = shortcuts.resolveBrowser(event,
                isCtrl: keyboard.isControlPressed,
                isMeta: keyboard.isMetaPressed,
                isShift: isShift, isAlt: keyboard.isAltPressed);
            final editingQuery = p.isTypeahead &&
                event.logicalKey == LogicalKeyboardKey.backspace &&
                !shortcuts.isCustomized(ShortcutAction.up);
            if ((!editingQuery && command != null) ||
                keyboard.isControlPressed || keyboard.isMetaPressed ||
                keyboard.isAltPressed || shortcuts.suppressesDefault(event,
                    isCtrl: keyboard.isControlPressed,
                    isMeta: keyboard.isMetaPressed,
                    isShift: isShift, isAlt: keyboard.isAltPressed)) {
              return KeyEventResult.ignored;
            }

            // Selection shortcuts must run before printable-character quick search.
            if (event.logicalKey == LogicalKeyboardKey.numpadAdd ||
                event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
              if (p.renamingItem != null) return KeyEventResult.ignored;
              if (event is KeyDownEvent && isShift) {
                p.selectSameExtension(
                  action: event.logicalKey == LogicalKeyboardKey.numpadAdd
                      ? SelectionAction.select
                      : SelectionAction.deselect,
                );
              } else if (event is KeyDownEvent) {
                showPatternSelectionDialog(
                  context,
                  ref,
                  side,
                  initialAction:
                      event.logicalKey == LogicalKeyboardKey.numpadAdd
                      ? SelectionAction.select
                      : SelectionAction.deselect,
                );
              }
              return KeyEventResult.handled;
            }

            if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.arrowUp) {
              final direction = event.logicalKey == LogicalKeyboardKey.arrowDown
                  ? 1
                  : -1;
              if (isShift) {
                p.shiftMoveCursor(direction);
                return KeyEventResult.handled;
              }
              if (p.isTypeahead) {
                final settings = ref.read(quickSearchSettingsProvider);
                if (settings.arrowNavigation && p.cycleTypeahead(direction)) {
                  return KeyEventResult.handled;
                }
                // Arrows end the search when cycling is disabled.
                if (!settings.arrowNavigation) p.clearTypeahead();
              }
              p.moveCursor(direction);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.insert) {
              // While typing a quick search, Space belongs to the query.
              if (event.logicalKey == LogicalKeyboardKey.space &&
                  p.isTypeahead) {
                p.typeaheadAppend(' ');
                return KeyEventResult.handled;
              }
              p.spaceSelectAndAdvance();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              final item = p.cursorItem;
              if (p.isTypeahead) p.clearTypeahead();
              if (item != null) p.navigateInto(item);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.home) {
              p.moveCursorTo(0);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.end) {
              p.moveCursorTo((p.displayedFiles?.length ?? 1) - 1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.pageDown ||
                event.logicalKey == LogicalKeyboardKey.pageUp) {
              final pageSize = scrollController.hasClients
                  ? (scrollController.position.viewportDimension / itemHeight)
                        .floor()
                        .clamp(1, 999)
                  : 15;
              final delta = event.logicalKey == LogicalKeyboardKey.pageDown
                  ? pageSize
                  : -pageSize;
              p.moveCursor(delta);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.numpadMultiply) {
              p.invertSelection();
              return KeyEventResult.handled;
            }
            // Numpad 5 - Select all (DC convention)
            if (event.logicalKey == LogicalKeyboardKey.numpad5) {
              p.selectAll();
              return KeyEventResult.handled;
            }
            final isCtrl =
                HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed;
            final isAlt = HardwareKeyboard.instance.isAltPressed;
            if (!isCtrl && !isAlt && event is KeyDownEvent) {
              // Escape: clear type-ahead if active
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                if (p.isTypeahead) {
                  p.clearTypeahead();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              }
              // Backspace: remove last type-ahead char
              if (event.logicalKey == LogicalKeyboardKey.backspace &&
                  p.isTypeahead) {
                p.typeaheadBackspace();
                return KeyEventResult.handled;
              }
              // Printable char: quick search / quick filter.
              final String? rawChar = event.character;
              final String label = event.logicalKey.keyLabel;
              final String? char = (rawChar != null && rawChar.isNotEmpty)
                  ? rawChar
                  : (label.length == 1 ? label : null);
              if (char != null && char.isNotEmpty) {
                final settings = ref.read(quickSearchSettingsProvider);
                if (settings.mode != QuickSearchMode.off) {
                  p.typeaheadAppend(char);
                  return KeyEventResult.handled;
                }
              }
            }
            return KeyEventResult.ignored;
          },
          child: listView,
        ),
      );
    } catch (e, stackTrace) {
      _log.error('Error building file list: $e', e, stackTrace);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              strings.format('Error loading files: {error}', {
                'error': localizedProviderError(context, e),
              }),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => panel.refresh(),
              child: Text(strings.text('Retry')),
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
  final TextStyle? textStyle;
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
    this.textStyle,
  });

  String _buildSemanticLabel(FileItem f, bool selected, bool cursor) {
    final type = f.isFolder ? 'Folder' : 'File';
    final size = f.isFolder ? '' : ', ${formatBytes(f.size ?? 0)}';
    final sel = selected ? ', selected' : '';
    final collection = f.metadata?['collectionSource'];
    final status = _collectionStatusLabel(f);
    return '$type ${f.name}$size$sel${collection == null ? '' : ', $collection, ${f.path}'}${status.isEmpty ? '' : ', $status'}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRenaming = ref.watch(
      panelProvider(side).select((p) => p.renamingItem == file),
    );
    final colorService = ref.watch(fileTypeColorProvider);
    final fileColor = colorService.colorForFile(file);

    // Inline rename mode: replace the whole tile with an editable field
    if (isRenaming) {
      return FileInlineRenameField(
        file: file,
        side: side,
        isCursor: isCursor,
        isSelected: isSelected,
        keepExtension: ref.read(panelProvider(side)).renameKeepExtension,
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

    final strings = FileListStrings(context);
    final tile = GestureDetector(
      onSecondaryTapDown: onSecondaryTap,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter &&
              !HardwareKeyboard.instance.isControlPressed &&
              !HardwareKeyboard.instance.isMetaPressed &&
              !HardwareKeyboard.instance.isAltPressed &&
              !HardwareKeyboard.instance.isShiftPressed &&
              ref.read(keyboardShortcutServiceProvider).resolveBrowser(event,
                  isCtrl: false, isShift: false, isAlt: false, isMeta: false) == null) {
            onDoubleTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          label: strings.semantic(
            folder: file.isFolder,
            name: file.name,
            size: file.size == null ? null : formatBytes(file.size!),
            selected: isSelected,
          ),
          selected: isSelected,
          focused: isCursor,
          button: true,
          child: Container(
            decoration: isCursor
                ? BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.16),
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
              selectedTileColor: Theme.of(context).colorScheme.primaryContainer
                  .withValues(alpha: 0.65),
              leading: file.name == '..'
                  ? const Icon(
                      Icons.arrow_upward,
                      size: 28,
                      color: Colors.amber,
                    )
                  : iconWidget,
              title: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (textStyle ?? const TextStyle()).copyWith(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : fileColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              subtitle: file.name == '..'
                  ? null
                  : Row(
                      children: [
                        if (_collectionStatusLabel(file).isNotEmpty)
                          _collectionStatus(context, file),
                        if (showRelativePath && file.path != null) ...[
                          Expanded(
                            child: Text(
                              _collectionPathLabel(file),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: (textStyle ?? const TextStyle()).copyWith(
                                fontSize: math.max(
                                  9.0,
                                  (textStyle?.fontSize ?? 13) - 2,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          if (file.isFolder && file.calculatedSize != null) ...[
                            Text(formatBytes(file.calculatedSize!)),
                            if (file.updatedAt != null) ...[
                              const Text(' • '),
                              Text(formatDate(file.updatedAt!)),
                            ],
                          ] else if (!file.isFolder &&
                              file.displaySize != null) ...[
                            Text(formatBytes(file.displaySize!)),
                            if (file.updatedAt != null) ...[
                              const Text(' • '),
                              Text(formatDate(file.updatedAt!)),
                            ],
                          ] else if (file.updatedAt != null)
                            Text(formatDate(file.updatedAt!)),
                        ],
                      ],
                    ),
              trailing: file.isFolder
                  ? IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Open',
                      onPressed: onDoubleTap,
                    )
                  : null,
              onTap: () {
                // Use _PointerModifiers captured at pointer-down time (more reliable on web).
                onTap(
                  _PointerModifiers.shiftPressed,
                  _PointerModifiers.ctrlOrMetaPressed,
                );
              },
              onLongPress: onDoubleTap,
            ),
          ), // Container (cursor border)
        ), // Semantics
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
      delay: isMobile
          ? const Duration(milliseconds: 200)
          : const Duration(milliseconds: 500),
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
                  Icon(
                    file.isFolder ? Icons.folder : getFileIcon(file.name),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dragCount > 1
                        ? '${file.name} +${dragCount - 1}'
                        : file.name,
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
  final TextStyle? textStyle;
  final String? sourceLabel;

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
    this.textStyle,
    this.sourceLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = FileListStrings(context);
    final colorService = ref.watch(fileTypeColorProvider);
    final fileColor = colorService.colorForFile(file);
    final theme = Theme.of(context);
    final view = FileViewConfiguration(
      columns: ref.watch(fileColumnsProvider(side)),
      widths: ref.watch(columnWidthsProvider(side)),
    );

    // Selected = fill; cursor = blue current-row bar + left marker.
    final double baseSize = textStyle?.fontSize ?? 12;
    final bgColor = isSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : isCursor
        ? theme.colorScheme.primary.withValues(alpha: 0.16)
        : Colors.transparent;

    final nameStyle = (textStyle ?? const TextStyle()).copyWith(
      fontSize: baseSize,
      color: isSelected ? theme.colorScheme.onPrimaryContainer : fileColor,
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      height: 1.0,
    );
    final dimStyle = (textStyle ?? const TextStyle()).copyWith(
      fontSize: math.max(9.0, baseSize - 1),
      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
      height: 1.0,
    );

    final sizeStr = file.name == '..'
        ? ''
        : file.isFolder
        // Show calculated folder size if available (from Space key), else <DIR>
        ? (file.calculatedSize != null
              ? formatBytes(file.calculatedSize!)
              : '<DIR>')
        : (file.displaySize != null ? formatBytes(file.displaySize!) : '');

    final semantic = strings.semantic(
      folder: file.isFolder,
      name: file.name,
      size: sizeStr.isEmpty ? null : sizeStr,
      selected: isSelected,
    );
    final collection = file.metadata?['collectionSource'];
    final status = _collectionStatusLabel(file);
    final semanticLabel =
        '$semantic${collection == null ? '' : ', $collection, ${file.path}'}${status.isEmpty ? '' : ', $status'}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = view.columnsFitting(constraints.maxWidth);
        return Semantics(
          label: semanticLabel,
          selected: isSelected,
          focused: isCursor,
          button: true,
          child: GestureDetector(
            onTap: () {
              final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
              final ctrlPressed =
                  HardwareKeyboard.instance.isControlPressed ||
                  HardwareKeyboard.instance.isMetaPressed;
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
                      showRelativePath && file.path != null
                          ? _collectionPathLabel(file)
                          : file.name,
                      style: nameStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_collectionStatusLabel(file).isNotEmpty)
                    _collectionStatus(context, file),
                  for (final column in columns) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      width: view.widthFor(column),
                      child: Text(
                        column.displayValue(file, sourceLabel: sourceLabel),
                        style: dimStyle,
                        textAlign: column.kind == FileColumnKind.size
                            ? TextAlign.right
                            : TextAlign.left,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Inline rename text field shown in-place of the filename when F2 is pressed.
class FileInlineRenameField extends ConsumerStatefulWidget {
  final FileItem file;
  final PanelSide side;
  final bool isCursor;
  final bool isSelected;

  /// Exact row height when the field replaces a list row.
  final double? height;

  /// Select only the base name so the extension is preserved.
  final bool keepExtension;

  const FileInlineRenameField({
    required this.file,
    required this.side,
    required this.isCursor,
    required this.isSelected,
    this.height,
    this.keepExtension = false,
  });

  @override
  ConsumerState<FileInlineRenameField> createState() => FileInlineRenameFieldState();
}

class FileInlineRenameFieldState extends ConsumerState<FileInlineRenameField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  late final FocusNode _keyboardListenerFocus;

  @override
  void initState() {
    super.initState();
    final name = widget.file.name;
    _ctrl = TextEditingController(text: name);
    _focus = FocusNode();
    _keyboardListenerFocus = FocusNode();
    // Select filename without extension (like DC)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      final dotIdx = name.lastIndexOf('.');
      if (widget.keepExtension && !widget.file.isFolder && dotIdx > 0) {
        _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: dotIdx);
      } else {
        _ctrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: name.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _keyboardListenerFocus.dispose();
    super.dispose();
  }

  void _commit() =>
      ref.read(panelProvider(widget.side)).commitRename(_ctrl.text);
  void _cancel() => ref.read(panelProvider(widget.side)).cancelRename();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = widget.isSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.2);

    return Container(
      height:
          widget.height ??
          (ref.read(panelViewModeProvider(widget.side)) == PanelViewMode.full
              ? 26.0
              : 64.0),
      color: bgColor,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: KeyboardListener(
        focusNode: _keyboardListenerFocus,
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 4,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 2,
              ),
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
