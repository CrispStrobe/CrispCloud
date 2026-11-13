import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../services/archive_format_registry.dart';
import '../services/file_operation_backend.dart';
import '../services/folder_drop_service.dart';
import '../services/keyboard_shortcut_service.dart';
import '../services/local_file_service.dart';
import '../services/panel_source_service.dart';
import '../utils/formatters.dart';
import 'file_context_menu.dart';
import 'folder_drop_target.dart';
import 'folder_size_presentation.dart';
import 'panel_listing_placeholder.dart';
import 'file_list_view.dart'
    show FileListView, FileInlineRenameField, getFileIcon;

/// A directory hierarchy with background ancestor snapshots. Only the final
/// column is the live panel. Ancestors request navigation or a freshly verified
/// drop destination; their snapshot rows never authorize operation sources.
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
  String? _trailRoot;
  Object? _trailLocalIdentity;
  bool? _showHidden;
  _AncestorHydration? _hydration;
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
    _hydration = null;
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
    _hydration = null;
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
    if (origin == null) {
      _hydration = null;
      return;
    }
    final root = _ancestorRoot(origin);
    final localIdentity = _localIdentity(origin);
    if (_trailRoot != root ||
        !identical(_trailLocalIdentity, localIdentity) ||
        _showHidden != panel.showHiddenFiles) {
      _resetTrail();
    }
    _trailRoot = root;
    _trailLocalIdentity = localIdentity;
    _showHidden = panel.showHiddenFiles;
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
      _scheduleAncestors(panel, origin, root);
      return;
    }
    if (_columns.isNotEmpty) {
      final paths = _pathsFor(origin);
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
    _scheduleAncestors(panel, origin, root);
  }

  p.Context _pathsFor(PanelFileOrigin origin) =>
      origin.source.isLocal && !kIsWeb ? p.context : p.posix;

  Object? _localIdentity(PanelFileOrigin origin) {
    if (!origin.source.isLocal) return null;
    final local = ref.read(localFileServiceProvider);
    return local is LocalFileSourceIdentity
        ? (local as LocalFileSourceIdentity).sourceIdentityForPath(
            origin.source.currentPath,
          )
        : null;
  }

  /// Stop at the actual source/grant boundary, including named browser roots.
  /// An unrelated grant or malformed remote root must never widen the scope.
  String _ancestorRoot(PanelFileOrigin origin) {
    final paths = _pathsFor(origin);
    final current = paths.normalize(origin.source.currentPath);
    bool contains(String root) =>
        paths.isAbsolute(root) &&
        (root == current || paths.isWithin(root, current));
    if (!paths.isAbsolute(current) || current.contains('\u0000')) {
      return current;
    }
    if (origin.source.isLocal) {
      final local = ref.read(localFileServiceProvider);
      if (local is LocalFileSourceIdentity) {
        final identities = local as LocalFileSourceIdentity;
        final identity = identities.sourceIdentityForPath(current);
        if (identity == null) return current;
        var root = current;
        while (true) {
          final parent = paths.dirname(root);
          if (parent == root ||
              !identical(identities.sourceIdentityForPath(parent), identity)) {
            return root;
          }
          root = parent;
        }
      }
      final granted = local.grantedBasePath;
      if (granted != null) {
        final root = paths.normalize(granted);
        return contains(root) ? root : current;
      }
      return paths.rootPrefix(current);
    }
    final root = paths.normalize(origin.storageReference.root);
    return contains(root) ? root : current;
  }

  List<String> _ancestorPaths(PanelFileOrigin origin, String root) {
    final paths = _pathsFor(origin);
    var current = paths.normalize(origin.source.currentPath);
    final result = <String>[];
    if (current == root || !paths.isWithin(root, current)) return result;
    // Keep work bounded for unusually deep locations while retaining their
    // source root and nearest parents. Only two requests run concurrently.
    while (current != root && result.length < 127) {
      final parent = paths.dirname(current);
      if (parent == current ||
          (parent != root && !paths.isWithin(root, parent))) {
        break;
      }
      result.add(parent);
      current = parent;
    }
    if (result.isNotEmpty && result.last != root) result.add(root);
    return result.reversed.toList(growable: false);
  }

  bool _isCurrentHydration(_AncestorHydration request) {
    if (!mounted ||
        !identical(_hydration, request) ||
        !request.sessionIsCurrent() ||
        !request.origin.isCurrent) {
      return false;
    }
    final panel = ref.read(panelProvider(request.side));
    final current = _currentOrigin(panel);
    return current != null &&
        panel.activeTabId == request.tabId &&
        panel.showHiddenFiles == request.showHidden &&
        _sameEndpoint(request.origin, current) &&
        _pathsFor(current).normalize(current.source.currentPath) ==
            request.path &&
        _ancestorRoot(current) == request.root &&
        identical(_localIdentity(current), request.localIdentity);
  }

  void _scheduleAncestors(
    PanelNotifier panel,
    PanelFileOrigin origin,
    String root,
  ) {
    final paths = _ancestorPaths(origin, root);
    if (paths.isEmpty) return;
    var request = _hydration;
    if (request == null || !_isCurrentHydration(request)) {
      request = _AncestorHydration(
        side: widget.side,
        tabId: panel.activeTabId,
        origin: origin,
        root: root,
        path: _pathsFor(origin).normalize(origin.source.currentPath),
        showHidden: panel.showHiddenFiles,
        localIdentity: _localIdentity(origin),
        sessionIsCurrent: panel.captureOperationSession(),
      );
      _hydration = request;
    }
    if (request.running) return;
    final missing = paths
        .where(
          (path) =>
              !request!.attempted.contains(path) &&
              !_columns.any((column) => column.path == path),
        )
        .toList();
    if (missing.isEmpty) return;
    // Root context and the nearest parent arrive first; remaining ancestors
    // follow without blocking the already verified current directory.
    final queue = <String>[
      if (missing.contains(root)) root,
      ...missing.reversed.where((path) => path != root),
    ];
    request.running = true;
    final captured = request;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrentHydration(captured)) {
        unawaited(_hydrateAncestors(captured, paths, queue));
      }
    });
  }

  Future<void> _hydrateAncestors(
    _AncestorHydration request,
    List<String> hierarchy,
    List<String> queue,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (_isCurrentHydration(request) && next < queue.length) {
        final path = queue[next++];
        request.attempted.add(path);
        try {
          final local = ref.read(localFileServiceProvider);
          final List<FileItem> entries;
          if (request.origin.source.isLocal) {
            // Snapshot reads acquire existing access without mutating the
            // shared path/grant or opening a permission picker.
            final entities = await local.listDirectorySnapshot(path);
            if (entities == null || !_isCurrentHydration(request)) continue;
            final paths = _pathsFor(request.origin);
            entries = [
              for (final entity in entities)
                FileItem(
                  name: paths.basename(entity.path),
                  path: entity.path,
                  isFolder: entity is Directory,
                  isSymlink: entity is Link,
                ),
            ];
          } else {
            final backend = fileOperationBackend(
              source: request.origin.source.withPath(path),
              local: local,
              isCurrent: () => _isCurrentHydration(request),
            );
            entries = await backend.list(path);
          }
          if (!_isCurrentHydration(request)) return;
          final paths = _pathsFor(request.origin);
          final seen = <String>{};
          final files = <FileItem>[];
          for (final entry in entries) {
            final child = entry.path;
            if (child == null || child.contains('\u0000')) continue;
            final normalized = paths.normalize(child);
            if (!paths.isAbsolute(normalized) ||
                paths.dirname(normalized) != path ||
                paths.basename(normalized) != entry.name ||
                entry.name == '.' ||
                entry.name == '..' ||
                (!request.showHidden && entry.name.startsWith('.')) ||
                !seen.add(normalized)) {
              continue;
            }
            files.add(entry.copyWith(path: normalized));
          }
          if (_columns.any((column) => column.path == path)) continue;
          final position = hierarchy.indexOf(path);
          final insertion = _columns.indexWhere(
            (column) =>
                column.path == request.path ||
                hierarchy.indexOf(column.path) > position,
          );
          if (insertion < 0) continue;
          setState(() {
            _columns.insert(
              insertion,
              _DirectoryColumn(request.origin, files, path: path),
            );
          });
          _revealCurrentColumn();
        } on Object {
          // Ancestor context is optional. Failed/denied reads stay skipped for
          // this listing and never become another pane's loading/error state.
        }
      }
    }

    await Future.wait([worker(), worker()]);
    request.running = false;
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
    String? localRoot,
    Object? localIdentity,
  ) {
    if (!mounted ||
        ticket != _interaction ||
        !origin.isCurrent ||
        !_matchesLocalTrail(origin, localRoot, localIdentity)) {
      return false;
    }
    final selected = ref.read(panelSourceProvider(widget.side)).withPath('');
    return ref.read(panelProvider(widget.side)).activeTabId == tabId &&
        // Explicitly routed legacy listings can update a stale picker label.
        (selected == endpoint || selected == origin.source.withPath('')) &&
        ref.read(focusAreaProvider).panelSide == widget.side &&
        ModalRoute.of(context)?.isCurrent != false;
  }

  bool _matchesLocalTrail(
    PanelFileOrigin origin,
    String? root,
    Object? identity,
  ) =>
      !origin.source.isLocal ||
      (_ancestorRoot(origin) == root &&
          identical(_localIdentity(origin), identity));

  CapturedFolderDropTarget? _captureColumnDrop(
    _DirectoryColumn column,
    FileItem folder,
  ) {
    final origin = column.origin;
    final root = _trailRoot;
    final identity = _trailLocalIdentity;
    bool snapshotIsCurrent() =>
        mounted &&
        _columns.contains(column) &&
        identical(column.origin, origin) &&
        column.files.any((file) => identical(file, folder)) &&
        _matchesLocalTrail(origin, root, identity);
    return const FolderDropService().captureSnapshot(
      ref.read(panelProvider(widget.side)),
      folder,
      ref.read(localFileServiceProvider),
      snapshotOrigin: origin,
      directoryPath: column.path,
      snapshotIsCurrent: snapshotIsCurrent,
    );
  }

  /// Restore the original directory, then resolve its fresh row. Snapshot
  /// objects must never authorize selection, preview or a context-menu action.
  Future<FileItem?> _activate(_DirectoryColumn column, FileItem? item) async {
    final panel = ref.read(panelProvider(widget.side));
    final before = _currentOrigin(panel);
    if (panel.isLoading ||
        !column.origin.isCurrent ||
        !_columns.contains(column) ||
        !_matchesLocalTrail(column.origin, _trailRoot, _trailLocalIdentity) ||
        _tabId != panel.activeTabId ||
        (before != null && !_sameEndpoint(before, column.origin))) {
      return null;
    }
    final ticket = ++_interaction;
    final tabId = panel.activeTabId;
    final endpoint = ref.read(panelSourceProvider(widget.side)).withPath('');
    final captured = column.origin;
    final localRoot = _trailRoot;
    final localIdentity = _trailLocalIdentity;
    if (before == null || before.source.currentPath != column.path) {
      await panel.navigateToPath(column.path, origin: captured);
    }
    if (!_isCurrentInteraction(
      ticket,
      tabId,
      endpoint,
      captured,
      localRoot,
      localIdentity,
    )) {
      return null;
    }
    final current = _currentOrigin(panel);
    if (current == null ||
        !_sameEndpoint(captured, current) ||
        !_matchesLocalTrail(current, localRoot, localIdentity) ||
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
        if (file.isFolder || (open && isDefaultArchiveFilename(file.name))) {
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
      } else {
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
          !widget.scrollController.hasClients) {
        return;
      }
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
    ref.watch(authProvider);
    ref.watch(multiCloudProvider);
    final listingState = panelListingState(panel);
    if (panel.isInArchive || panel.showingSearchResults || panel.isFlatView) {
      if (_columns.isNotEmpty) _resetTrail();
      if (listingState != null) {
        return PanelListingPlaceholder(side: widget.side, state: listingState);
      }
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
        child: _columns.isEmpty || listingState?.blocksListing == true
            ? PanelListingPlaceholder(
                side: widget.side,
                state: listingState ?? PanelListingState.unavailable,
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
                        _buildColumn(
                          context,
                          panel,
                          index,
                          active,
                          listingState,
                        ),
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
    PanelListingState? listingState,
  ) {
    final column = _columns[index];
    final current = index == _columns.length - 1;
    final theme = Theme.of(context);
    final strings = FileListStrings(context);
    final files = current && _currentOrigin(panel) != null
        ? widget.files
        : (List<FileItem>.of(column.files)..sort((a, b) {
            if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
            var result = PanelNotifier.compareSortKey(a, b, panel.sortBy);
            if (panel.sortOrder == SortOrder.descending) result = -result;
            if (result == 0 && panel.secondarySortBy != null) {
              result = PanelNotifier.compareSortKey(
                a,
                b,
                panel.secondarySortBy!,
              );
              if (panel.secondarySortOrder == SortOrder.descending) {
                result = -result;
              }
            }
            return result == 0 ? a.name.compareTo(b.name) : result;
          }));
    final nextPath = current ? null : _columns[index + 1].path;
    final paths = _pathsFor(column.origin);
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
              child: current && listingState != null
                  ? PanelListingPlaceholder(
                      side: widget.side,
                      state: listingState,
                    )
                  : files.isEmpty
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
                        final folderSize = current
                            ? FolderSizePresentation.forFile(
                                context,
                                file,
                                panel.folderSizeFor(file),
                              )
                            : null;
                        final marked = current && panel.isSelected(file);
                        final cursor =
                            current && identical(panel.cursorItem, file);
                        final expanded =
                            file.isFolder &&
                            file.path != null &&
                            nextPath != null &&
                            (file.path == nextPath ||
                                paths.isWithin(file.path!, nextPath));
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
                          label:
                              strings.semantic(
                                folder: file.isFolder,
                                name: file.name,
                                selected: marked,
                                size: file.size == null
                                    ? null
                                    : formatBytes(file.size!),
                              ) +
                              (folderSize == null
                                  ? ''
                                  : ', ${folderSize.tooltip}'),
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
                                      if (folderSize != null)
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 84,
                                          ),
                                          child: Tooltip(
                                            message: folderSize.tooltip,
                                            child: Text(
                                              folderSize.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelSmall,
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
                        final destination = file.isFolder
                            ? FolderDropTarget(
                                side: widget.side,
                                folder: file,
                                captureDestination: current
                                    ? null
                                    : () => _captureColumnDrop(column, file),
                                child: rowWidget,
                              )
                            : rowWidget;
                        if (!current) return destination;
                        return PanelFileDragSource(
                          side: widget.side,
                          file: file,
                          child: destination,
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
  _DirectoryColumn(this.origin, List<FileItem> files, {String? path})
    : path = path ?? origin.source.currentPath,
      files = List<FileItem>.unmodifiable(files);

  PanelFileOrigin origin;
  List<FileItem> files;
  final String path;
  final scrollController = ScrollController();
}

class _AncestorHydration {
  _AncestorHydration({
    required this.side,
    required this.tabId,
    required this.origin,
    required this.root,
    required this.path,
    required this.showHidden,
    required this.localIdentity,
    required this.sessionIsCurrent,
  });

  final PanelSide side;
  final String tabId;
  final PanelFileOrigin origin;
  final String root;
  final String path;
  final bool showHidden;
  final Object? localIdentity;
  final bool Function() sessionIsCurrent;
  final attempted = <String>{};
  bool running = false;
}
