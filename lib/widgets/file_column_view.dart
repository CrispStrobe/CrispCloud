import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/file_list_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/focus_area_provider.dart';
import '../providers/panel_source_provider.dart';
import '../providers/providers.dart';
import '../screens/screen_dialogs.dart' show viewSelectedFile;
import '../services/archive_service.dart';
import '../services/keyboard_shortcut_service.dart';
import '../services/panel_source_service.dart';
import '../utils/formatters.dart';
import 'file_context_menu.dart';
import 'folder_drop_target.dart';
import 'file_list_view.dart'
    show FileListView, FileInlineRenameField, getFileIcon;

/// A trail of visited directories. Only the final column is the live panel;
/// earlier columns are snapshots, never an independent authorization to act.
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
  final _columns = <_DirectoryColumn>[];
  final _horizontalScroll = ScrollController();
  String? _tabId;
  PanelSource? _selectedEndpoint;
  int _interaction = 0;
  bool _shiftPressed = false;
  bool _togglePressed = false;
  bool _revealScheduled = false;

  @override
  void didUpdateWidget(covariant FileColumnView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.side != widget.side) _resetTrail();
  }

  @override
  void dispose() {
    _interaction++;
    for (final column in _columns) {
      column.scrollController.dispose();
    }
    _horizontalScroll.dispose();
    super.dispose();
  }

  void _removeColumnsFrom(int index) {
    final removed = _columns.sublist(index);
    _columns.removeRange(index, _columns.length);
    // Let the old Scrollables detach before their controllers are disposed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final column in removed) {
        column.scrollController.dispose();
      }
    });
  }

  void _resetTrail() {
    _interaction++;
    _removeColumnsFrom(0);
  }

  bool _sameEndpoint(PanelFileOrigin first, PanelFileOrigin second) =>
      first.isCurrent &&
      second.isCurrent &&
      first.storageReference == second.storageReference &&
      first.source.withPath('') == second.source.withPath('');

  PanelFileOrigin? _currentOrigin(PanelNotifier panel) {
    try {
      return panel.captureCurrentOrigin();
    } on StateError {
      return null;
    }
  }

  /// A loading panel can contain previous-location or cached rows. Snapshot
  /// only a verified listing, never attach those rows to the requested path.
  void _observePanel(PanelNotifier panel, PanelSource selected) {
    final endpoint = selected.withPath('');
    final pickerChanged = _selectedEndpoint != endpoint;
    final sameLiveEndpoint =
        _columns.isNotEmpty &&
        _columns.last.origin.source.withPath('') == endpoint;
    if (_tabId != panel.activeTabId ||
        (pickerChanged && !sameLiveEndpoint) ||
        _columns.any((column) => !column.origin.isCurrent)) {
      _resetTrail();
    }
    _tabId = panel.activeTabId;
    _selectedEndpoint = endpoint;
    final origin = _currentOrigin(panel);
    if (origin == null) return;
    if (_columns.isNotEmpty && !_sameEndpoint(_columns.last.origin, origin)) {
      _resetTrail();
    }
    final path = origin.source.currentPath;
    final existing = _columns.indexWhere((column) => column.path == path);
    if (existing >= 0) {
      if (existing + 1 < _columns.length) _removeColumnsFrom(existing + 1);
      _columns[existing]
        ..origin = origin
        ..files = List<FileItem>.unmodifiable(panel.files ?? const []);
      return;
    }
    if (_columns.isNotEmpty) {
      final paths = origin.source.isLocal ? p.context : p.posix;
      final parent = paths.dirname(path);
      final parentIndex = _columns.indexWhere(
        (column) => paths.normalize(column.path) == paths.normalize(parent),
      );
      if (parentIndex < 0) {
        _removeColumnsFrom(0);
      } else if (parentIndex + 1 < _columns.length) {
        _removeColumnsFrom(parentIndex + 1);
      }
    }
    _columns.add(_DirectoryColumn(origin, panel.files ?? const []));
    _revealCurrentColumn();
  }

  void _revealCurrentColumn() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted || !_horizontalScroll.hasClients) return;
      final target = _horizontalScroll.position.maxScrollExtent;
      if (MediaQuery.of(context).disableAnimations) {
        _horizontalScroll.jumpTo(target);
      } else {
        _horizontalScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _takeFocus() {
    ref.read(activePanelProvider.notifier).state = widget.side;
    ref.read(focusAreaProvider.notifier).state = widget.side == PanelSide.local
        ? FocusArea.local
        : FocusArea.remote;
    ref.read(panelProvider(widget.side)).listFocusNode.requestFocus();
  }

  bool _isCurrentInteraction(
    int ticket,
    String tabId,
    PanelSource endpoint,
    PanelFileOrigin origin,
  ) {
    if (!mounted || ticket != _interaction || !origin.isCurrent) return false;
    final selected = ref.read(panelSourceProvider(widget.side)).withPath('');
    return ref.read(panelProvider(widget.side)).activeTabId == tabId &&
        // Explicitly routed legacy listings can update a stale picker label.
        (selected == endpoint || selected == origin.source.withPath('')) &&
        ref.read(focusAreaProvider).panelSide == widget.side &&
        ModalRoute.of(context)?.isCurrent != false;
  }

  /// Restore the original directory, then resolve its fresh row. Snapshot
  /// objects must never authorize selection, preview or a context-menu action.
  Future<FileItem?> _activate(_DirectoryColumn column, FileItem? item) async {
    final panel = ref.read(panelProvider(widget.side));
    final before = _currentOrigin(panel);
    if (panel.isLoading ||
        !column.origin.isCurrent ||
        !_columns.contains(column) ||
        _tabId != panel.activeTabId ||
        (before != null && !_sameEndpoint(before, column.origin))) {
      return null;
    }
    final ticket = ++_interaction;
    final tabId = panel.activeTabId;
    final endpoint = ref.read(panelSourceProvider(widget.side)).withPath('');
    final captured = column.origin;
    if (before == null || before.source.currentPath != column.path) {
      await panel.navigateToPath(column.path, origin: captured);
    }
    if (!_isCurrentInteraction(ticket, tabId, endpoint, captured)) return null;
    final current = _currentOrigin(panel);
    if (current == null ||
        !_sameEndpoint(captured, current) ||
        current.source.currentPath != column.path ||
        item == null) {
      return null;
    }
    FileItem? found;
    for (final candidate in panel.files ?? const <FileItem>[]) {
      if (candidate.isFolder != item.isFolder) continue;
      final matches = item.uuid != null
          ? candidate.uuid == item.uuid
          : item.path != null
          ? candidate.path == item.path
          : identical(candidate, item);
      if (!matches) continue;
      if (found != null) return null; // Ambiguous identifiers are not targets.
      found = candidate;
    }
    return found;
  }

  Future<void> _perform(
    _DirectoryColumn column,
    FileItem? item, {
    bool open = false,
    bool shift = false,
    bool toggle = false,
    Offset? contextPosition,
  }) async {
    try {
      final file = await _activate(column, item);
      if (!mounted || file == null) return;
      final panel = ref.read(panelProvider(widget.side));
      if (file.name != '..' && panel.originForOperation(file) == null) return;
      if (!(panel.displayedFiles?.any((row) => identical(row, file)) ??
          false)) {
        panel.setFilter('');
      }
      if (contextPosition != null) {
        showFileContextMenu(context, ref, widget.side, file, contextPosition);
      } else if (shift || toggle) {
        panel.toggleSelection(file, shiftKey: shift, ctrlKey: toggle);
      } else {
        panel.setCursorOnly(file);
        if (file.isFolder || (open && ArchiveService.isArchive(file.name))) {
          await panel.navigateInto(file);
        } else if (open) {
          viewSelectedFile(context, ref);
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            FileListStrings(context)
                .format('Error loading item: {error}', {'error': error}),
          ),
        ),
      );
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        ref.read(focusAreaProvider).panelSide != widget.side ||
        _columns.isEmpty) {
      return KeyEventResult.ignored;
    }
    final panel = ref.read(panelProvider(widget.side));
    if (panel.isLoading || panel.renamingItem != null) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final shortcuts = ref.read(keyboardShortcutServiceProvider);
    final command = shortcuts.resolveBrowser(
      event,
      isCtrl: keyboard.isControlPressed,
      isMeta: keyboard.isMetaPressed,
      isShift: keyboard.isShiftPressed,
      isAlt: keyboard.isAltPressed,
    );
    final editingQuery =
        panel.isTypeahead &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        !shortcuts.isCustomized(ShortcutAction.up);
    if ((!editingQuery && command != null) ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        shortcuts.suppressesDefault(
          event,
          isCtrl: keyboard.isControlPressed,
          isMeta: keyboard.isMetaPressed,
          isShift: keyboard.isShiftPressed,
          isAlt: keyboard.isAltPressed,
        )) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.numpadAdd ||
        key == LogicalKeyboardKey.numpadSubtract ||
        key == LogicalKeyboardKey.numpadMultiply ||
        key == LogicalKeyboardKey.numpad5) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_columns.length > 1) {
        unawaited(_perform(_columns[_columns.length - 2], null));
      } else {
        unawaited(panel.navigateUp());
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.enter) {
      final file = panel.cursorItem;
      if (file != null && (file.isFolder || key == LogicalKeyboardKey.enter)) {
        unawaited(_perform(_columns.last, file, open: true));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final delta = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      if (keyboard.isShiftPressed) {
        panel.shiftMoveCursor(delta);
      } else if (!panel.isTypeahead ||
          !ref.read(quickSearchSettingsProvider).arrowNavigation ||
          !panel.cycleTypeahead(delta)) {
        panel.moveCursor(delta);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
      panel.moveCursorTo(
        key == LogicalKeyboardKey.home ? 0 : widget.files.length - 1,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.pageDown) {
      final page = widget.scrollController.hasClients
          ? (widget.scrollController.position.viewportDimension / _rowHeight)
                .floor()
                .clamp(1, 999)
          : 12;
      panel.moveCursor(key == LogicalKeyboardKey.pageDown ? page : -page);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.insert) {
      if (panel.isTypeahead && key == LogicalKeyboardKey.space) {
        panel.typeaheadAppend(' ');
      } else {
        panel.spaceSelectAndAdvance();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.escape && panel.isTypeahead) {
        panel.clearTypeahead();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.backspace && panel.isTypeahead) {
        panel.typeaheadBackspace();
        return KeyEventResult.handled;
      }
      final character =
          event.character ?? (key.keyLabel.length == 1 ? key.keyLabel : null);
      if (character != null &&
          character.isNotEmpty &&
          ref.read(quickSearchSettingsProvider).mode != QuickSearchMode.off) {
        panel.typeaheadAppend(character);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  double get _rowHeight {
    final fontSize = ref.read(fontSizeProvider);
    final platform = Theme.of(context).platform;
    return math.max(
      platform == TargetPlatform.android || platform == TargetPlatform.iOS
          ? 48.0
          : 32.0,
      MediaQuery.textScalerOf(context).scale(fontSize) + 14,
    );
  }

  void _revealCursor(PanelNotifier panel) {
    final item = panel.itemToScrollTo;
    final index = item == null
        ? -1
        : widget.files.indexWhere((file) => identical(file, item));
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(panel.itemToScrollTo, item) ||
          !widget.scrollController.hasClients)
        return;
      final position = widget.scrollController.position;
      final top = index * _rowHeight;
      final bottom = top + _rowHeight;
      final offset = top < position.pixels
          ? top
          : bottom > position.pixels + position.viewportDimension
          ? bottom - position.viewportDimension
          : position.pixels;
      widget.scrollController.jumpTo(
        offset.clamp(0.0, position.maxScrollExtent),
      );
      panel.clearItemToScrollTo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final panel = ref.watch(panelProvider(widget.side));
    final selected = ref.watch(panelSourceProvider(widget.side));
    ref.watch(fontSizeProvider);
    ref.watch(fontFamilyProvider);
    if (panel.isInArchive || panel.showingSearchResults || panel.isFlatView) {
      if (_columns.isNotEmpty) _resetTrail();
      return FileListView(
        side: widget.side,
        files: widget.files,
        scrollController: widget.scrollController,
      );
    }
    _observePanel(panel, selected);
    _revealCursor(panel);
    final active = ref.watch(focusAreaProvider).panelSide == widget.side;
    final terminal = ref.watch(showTerminalProvider);
    return Listener(
      onPointerDown: (_) {
        _shiftPressed = HardwareKeyboard.instance.isShiftPressed;
        _togglePressed =
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        _takeFocus();
      },
      child: Focus(
        focusNode: panel.listFocusNode,
        autofocus: active && !terminal,
        skipTraversal: true,
        onKeyEvent: _onKeyEvent,
        child: _columns.isEmpty
            ? Center(
                child: panel.isLoading
                    ? const CircularProgressIndicator()
                    : Text(FileListStrings(context).text('Empty folder')),
              )
            : Scrollbar(
                controller: _horizontalScroll,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  key: const ValueKey('file-column-trail'),
                  controller: _horizontalScroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < _columns.length; index++)
                        _buildColumn(context, panel, index, active),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildColumn(
    BuildContext context,
    PanelNotifier panel,
    int index,
    bool active,
  ) {
    final column = _columns[index];
    final current = index == _columns.length - 1;
    final theme = Theme.of(context);
    final strings = FileListStrings(context);
    final files = current && _currentOrigin(panel) != null
        ? widget.files
        : column.files;
    final nextPath = current ? null : _columns[index + 1].path;
    final ready = !panel.isLoading && column.origin.isCurrent;
    final fontFamily = ref.read(fontFamilyProvider);
    return SizedBox(
      key: ValueKey('file-column:${column.path}'),
      width: 252,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: current && active
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
              width: 2,
            ),
            right: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Tooltip(
              message: column.path,
              child: TextButton.icon(
                onPressed: ready
                    ? () {
                        _takeFocus();
                        unawaited(_perform(column, null));
                      }
                    : null,
                icon: Icon(
                  current ? Icons.folder_open : Icons.folder_outlined,
                  size: 16,
                ),
                label: Text(
                  column.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                ),
              ),
            ),
            Expanded(
              child: files.isEmpty
                  ? Center(child: Text(strings.text('Empty folder')))
                  : ListView.builder(
                      key: PageStorageKey('column-list:${column.path}'),
                      controller: current
                          ? widget.scrollController
                          : column.scrollController,
                      itemExtent: _rowHeight,
                      itemCount: files.length,
                      itemBuilder: (context, row) {
                        final file = files[row];
                        final marked = current && panel.isSelected(file);
                        final cursor =
                            current && identical(panel.cursorItem, file);
                        final expanded = file.isFolder && file.path == nextPath;
                        if (current && identical(panel.renamingItem, file)) {
                          return FileInlineRenameField(
                            file: file,
                            side: widget.side,
                            isCursor: cursor,
                            isSelected: marked,
                            height: _rowHeight,
                            keepExtension: panel.renameKeepExtension,
                          );
                        }
                        void tap() {
                          _takeFocus();
                          unawaited(
                            _perform(
                              column,
                              file,
                              shift: _shiftPressed,
                              toggle: _togglePressed,
                            ),
                          );
                        }

                        void menu(Offset position) {
                          _takeFocus();
                          unawaited(
                            _perform(column, file, contextPosition: position),
                          );
                        }

                        final rowWidget = Semantics(
                          key: ValueKey(
                            'column-item:${column.path}:${file.path ?? file.uuid ?? file.name}',
                          ),
                          container: true,
                          button: true,
                          selected: marked,
                          focused: cursor && active,
                          enabled: ready,
                          label: strings.semantic(
                            folder: file.isFolder,
                            name: file.name,
                            selected: marked,
                            size: file.size == null
                                ? null
                                : formatBytes(file.size!),
                          ),
                          onTap: ready ? tap : null,
                          child: ExcludeSemantics(
                            child: GestureDetector(
                              onSecondaryTapDown: ready
                                  ? (details) => menu(details.globalPosition)
                                  : null,
                              onLongPressStart: ready
                                  ? (details) => menu(details.globalPosition)
                                  : null,
                              child: InkWell(
                                canRequestFocus: false,
                                onTap: ready ? tap : null,
                                onDoubleTap: ready
                                    ? () {
                                        _takeFocus();
                                        unawaited(
                                          _perform(column, file, open: true),
                                        );
                                      }
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  color: marked
                                      ? theme.colorScheme.primaryContainer
                                      : cursor || expanded
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: 0.14,
                                        )
                                      : null,
                                  child: Row(
                                    children: [
                                      Icon(
                                        file.isFolder
                                            ? Icons.folder
                                            : getFileIcon(file.name),
                                        size: 18,
                                        color: file.isFolder
                                            ? theme.colorScheme.primary
                                            : theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          file.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: ref.read(
                                              fontSizeProvider,
                                            ),
                                            fontFamily: fontFamily == 'system'
                                                ? null
                                                : fontFamily,
                                            fontWeight: marked || expanded
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      if (file.isFolder)
                                        const Icon(
                                          Icons.chevron_right,
                                          size: 16,
                                        )
                                      else if (file.size != null)
                                        Text(
                                          formatBytes(file.size!),
                                          style: theme.textTheme.labelSmall,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                        if (!current) return rowWidget;
                        return PanelFileDragSource(
                          side: widget.side,
                          file: file,
                          child: file.isFolder
                              ? FolderDropTarget(
                                  side: widget.side,
                                  folder: file,
                                  child: rowWidget,
                                )
                              : rowWidget,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectoryColumn {
  _DirectoryColumn(this.origin, List<FileItem> files)
    : files = List<FileItem>.unmodifiable(files);

  PanelFileOrigin origin;
  List<FileItem> files;
  final scrollController = ScrollController();
  String get path => origin.source.currentPath;
}
