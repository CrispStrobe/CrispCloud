// lib/providers/panel_provider.dart
//
// Per-panel state: file listing, selection, sort, tabs, navigation.
// Used as a family provider keyed by PanelSide.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/panel_tab.dart';
import '../services/archive_service.dart';
import '../services/audit_service.dart';
import '../services/local_file_service.dart';
import '../services/log_service.dart';
import '../services/panel_source_service.dart';
import 'action_history_provider.dart';
import 'auth_provider.dart';
import 'core_providers.dart';
import 'error_provider.dart';
import 'recent_locations_provider.dart';

enum SortBy { name, size, date, extension }
enum SortOrder { ascending, descending }

class PanelNotifier extends ChangeNotifier {
  static const _log = Log('PanelNotifier');

  final Ref _ref;
  final PanelSide side;

  final LocalFileService _localFileService;

  List<FileItem>? _files;
  final Set<FileItem> _selection = {};
  FileItem? _lastSelected;
  FileItem? _itemToScrollTo;

  // Cursor: keyboard-focus position (separate from selection marks)
  int _cursorIndex = -1;

  SortBy _sortBy = SortBy.name;
  SortOrder _sortOrder = SortOrder.ascending;

  // Client-side incremental filter (no re-fetch)
  String _filterQuery = '';
  // true when filter was set via type-ahead (vs the Ctrl+F dialog)
  bool _isTypeahead = false;

  // Per-panel navigation history (back/forward like a browser)
  final List<String> _navHistory = [];
  int _historyIndex = -1;

  // Tabs
  int _tabIdCounter = 0;
  final List<PanelTab> _tabs = [];
  String _activeTabId = '';

  final _refreshLock = _AsyncLock();
  Timer? _refreshDebounce;

  /// When true, [_files] holds search results instead of the real directory
  /// listing; normal refresh/navigation calls restore the real listing.
  bool _showingSearchResults = false;
  bool get showingSearchResults => _showingSearchResults;

  /// When non-null, the panel is browsing inside a compressed archive.
  ArchivePanelSource? _archiveSource;
  bool get isInArchive => _archiveSource != null;
  ArchivePanelSource? get archiveSource => _archiveSource;

  /// Secondary sort key for multi-key sorting (Phase 1.2).
  SortBy? _secondarySortBy;
  SortOrder _secondarySortOrder = SortOrder.ascending;
  SortBy? get secondarySortBy => _secondarySortBy;
  SortOrder get secondarySortOrder => _secondarySortOrder;

  /// Whether the panel is in flat (recursive) view mode.
  bool _isFlatView = false;
  bool get isFlatView => _isFlatView;

  // In-place rename state
  FileItem? _renamingItem;
  FileItem? get renamingItem => _renamingItem;

  // Whether to show hidden (dot-prefixed) files — toggle via Ctrl+.
  bool _showHiddenFiles = false;
  bool get showHiddenFiles => _showHiddenFiles;

  void toggleShowHiddenFiles() {
    _showHiddenFiles = !_showHiddenFiles;
    refresh();
  }

  // Free space for the current local path (populated after _loadLocalFiles)
  int? _freeBytes;
  int? get freeBytes => _freeBytes;

  PanelNotifier(this._ref, this.side)
      : _localFileService = _ref.read(localFileServiceProvider) {
    _restoreTabs();
    if (side == PanelSide.local) {
      _initializeLocalPath();
    } else {
      // Refresh remote panel when auth connection changes
      _ref.listen<AuthNotifier>(authProvider, (prev, next) {
        if (!(prev?.isConnected ?? false) && next.isConnected) {
          _remotePath = '/'; // start at cloud root when connecting
          refresh();
        } else if ((prev?.isConnected ?? false) && !next.isConnected) {
          // On disconnect, show local filesystem
          if (!kIsWeb) {
            _remotePath = Platform.environment['HOME'] ?? '/';
          }
          refresh();
        }
      });
    }
  }

  // --- Getters ---
  List<FileItem>? get files => _files;
  Set<FileItem> get selection => _selection;
  FileItem? get lastSelected => _lastSelected;
  FileItem? get itemToScrollTo => _itemToScrollTo;
  void clearItemToScrollTo() { _itemToScrollTo = null; }

  int get cursorIndex => _cursorIndex;
  FileItem? get cursorItem =>
      (_files != null && _cursorIndex >= 0 && _cursorIndex < _files!.length)
          ? _files![_cursorIndex]
          : null;

  SortBy get sortBy => _sortBy;
  SortOrder get sortOrder => _sortOrder;
  String get filterQuery => _filterQuery;
  bool get isTypeahead => _isTypeahead;

  /// Returns files filtered by the current filter query (client-side, no re-fetch).
  List<FileItem>? get filteredFiles {
    if (_files == null) return null;
    if (_filterQuery.isEmpty) return _files;
    final q = _filterQuery.toLowerCase();
    // ".." always stays visible even when a filter is active
    return [
      if (_files!.isNotEmpty && _files!.first.name == '..') _files!.first,
      ..._files!.where((f) => f.name != '..' && f.name.toLowerCase().contains(q)),
    ];
  }

  /// Set a client-side filter query. Filters without re-fetching from server.
  void setFilter(String query) {
    _filterQuery = query;
    notifyListeners();
  }

  /// Clear the client-side filter.
  void clearFilter() {
    _filterQuery = '';
    _isTypeahead = false;
    notifyListeners();
  }

  // --- Type-ahead incremental search (DC-style: type directly in file list) ---

  /// Append [char] to the type-ahead search query and filter the file list.
  void typeaheadAppend(String char) {
    _filterQuery += char;
    _isTypeahead = true;
    // Jump cursor to first match
    final displayed = filteredFiles;
    if (displayed != null && displayed.isNotEmpty) {
      final first = displayed.firstWhere(
        (f) => f.name != '..',
        orElse: () => displayed.first,
      );
      final rawIdx = _files?.indexOf(first) ?? -1;
      if (rawIdx != -1) {
        _cursorIndex = rawIdx;
        _itemToScrollTo = first;
      }
    }
    notifyListeners();
  }

  /// Remove last character from the type-ahead query.
  void typeaheadBackspace() {
    if (_filterQuery.isEmpty) return;
    _filterQuery = _filterQuery.substring(0, _filterQuery.length - 1);
    if (_filterQuery.isEmpty) _isTypeahead = false;
    notifyListeners();
  }

  /// Clear type-ahead on navigation/escape.
  void clearTypeahead() {
    if (!_isTypeahead) return;
    _filterQuery = '';
    _isTypeahead = false;
    notifyListeners();
  }

  // --- Navigation history (Alt+Left / Alt+Right) ---

  bool get canNavigateBack => _historyIndex > 0;
  bool get canNavigateForward => _historyIndex < _navHistory.length - 1;

  void _pushHistory(String path) {
    // Drop forward stack when navigating to a new location
    if (_historyIndex < _navHistory.length - 1) {
      _navHistory.removeRange(_historyIndex + 1, _navHistory.length);
    }
    if (_navHistory.isNotEmpty && _navHistory.last == path) return;
    _navHistory.add(path);
    _historyIndex = _navHistory.length - 1;
  }

  Future<void> navigateBack() async {
    if (!canNavigateBack) return;
    _historyIndex--;
    await _navigateRaw(_navHistory[_historyIndex]);
  }

  Future<void> navigateForward() async {
    if (!canNavigateForward) return;
    _historyIndex++;
    await _navigateRaw(_navHistory[_historyIndex]);
  }

  /// Navigate to [path] without recording to history (used by back/forward).
  Future<void> _navigateRaw(String path) async {
    _selection.clear();
    _lastSelected = null;
    if (_isTypeahead) { _filterQuery = ''; _isTypeahead = false; }
    if (side == PanelSide.local) {
      _localFileService.currentPath = path;
      await _loadLocalFiles();
    } else {
      _remotePath = path;
      if (_ref.read(authProvider).isConnected) {
        await _loadRemoteFiles();
      } else {
        await _loadLocalFiles();
      }
    }
    _syncTabPath();
    notifyListeners();
  }

  // --- Search-results virtual folder ---

  /// Replace the file listing with [results] from a search/find operation.
  /// The actual remote path is preserved so [clearSearchResults] can restore it.
  void showSearchResults(List<FileItem> results) {
    _log.info('Showing ${results.length} search results as virtual folder');
    _showingSearchResults = true;
    _files = List.of(results);
    _sortFiles();
    notifyListeners();
  }

  /// Restore the real directory listing by re-loading the current remote path.
  void clearSearchResults() {
    if (!_showingSearchResults) return;
    _log.info('Clearing search results, restoring directory listing');
    _showingSearchResults = false;
    refresh();
  }

  // --- Archive navigation ---

  /// Enter a compressed archive for browsing.
  Future<void> enterArchive(FileItem file) async {
    if (file.path == null && file.name.isEmpty) return;
    final archivePath = file.path ?? p.posix.join(_remotePath, file.name);
    final parentSource = side == PanelSide.local
        ? LocalPanelSource(currentPath)
        : LocalPanelSource(currentPath); // Simplified — local archives only for now
    _archiveSource = const PanelSourceService().enterArchive(archivePath, parentSource);
    await _loadArchiveFiles();
    notifyListeners();
  }

  /// Navigate deeper into a folder within the archive.
  Future<void> _navigateArchive(String innerPath) async {
    if (_archiveSource == null) return;
    _archiveSource = _archiveSource!.withPath(innerPath);
    await _loadArchiveFiles();
    notifyListeners();
  }

  /// Navigate up one level within the archive, or exit if at root.
  Future<void> navigateUpArchive() async {
    if (_archiveSource == null) return;
    final inner = _archiveSource!.innerPath;
    if (inner.isEmpty) {
      exitArchive();
      return;
    }
    // Go up one directory level within the archive
    var parent = inner.endsWith('/') ? inner.substring(0, inner.length - 1) : inner;
    final lastSlash = parent.lastIndexOf('/');
    parent = lastSlash > 0 ? parent.substring(0, lastSlash + 1) : '';
    _archiveSource = _archiveSource!.withPath(parent);
    await _loadArchiveFiles();
    notifyListeners();
  }

  /// Exit the archive and restore the parent directory listing.
  void exitArchive() {
    _archiveSource = null;
    refresh();
  }

  Future<void> _loadArchiveFiles() async {
    if (_archiveSource == null) return;
    try {
      _files = await const PanelSourceService().listFiles(_archiveSource!);
      _sortFiles();
    } catch (e) {
      _files = [];
      _ref.read(errorProvider).addError('Failed to read archive: $e');
    }
  }

  // --- Multi-key sort ---

  void setSecondarySortBy(SortBy? sortBy) {
    _secondarySortBy = sortBy;
    _sortFiles();
    notifyListeners();
  }

  void toggleSecondarySortOrder() {
    _secondarySortOrder = _secondarySortOrder == SortOrder.ascending
        ? SortOrder.descending
        : SortOrder.ascending;
    _sortFiles();
    notifyListeners();
  }

  // --- Flat view ---

  Future<void> toggleFlatView() async {
    if (_isFlatView) {
      _isFlatView = false;
      await refresh();
    } else {
      _isFlatView = true;
      await _loadFlatFiles();
    }
    notifyListeners();
  }

  Future<void> _loadFlatFiles() async {
    if (kIsWeb || side != PanelSide.local) {
      _ref.read(errorProvider).addError('Flat view is only available for local directories');
      _isFlatView = false;
      return;
    }
    try {
      final items = <FileItem>[];
      const maxItems = 10000;
      await _walkDirectory(currentPath, items, maxItems);
      final prev = cursorItem;
      _files = items;
      _sortFiles();
      _resetCursor(preserveItem: prev);
      notifyListeners();
    } catch (e) {
      _ref.read(errorProvider).addError('Flat view failed: $e');
      _isFlatView = false;
    }
  }

  Future<void> _walkDirectory(String dirPath, List<FileItem> items, int maxItems) async {
    if (items.length >= maxItems) return;
    final entities = await Directory(dirPath).list().toList();
    for (final entity in entities) {
      if (items.length >= maxItems) return;
      final name = p.basename(entity.path);
      if (!_showHiddenFiles && name.startsWith('.')) continue;
      final stat = await entity.stat();
      if (stat.type == FileSystemEntityType.directory) {
        await _walkDirectory(entity.path, items, maxItems);
      } else if (stat.type == FileSystemEntityType.file) {
        items.add(FileItem(
          name: name,
          path: entity.path,
          isFolder: false,
          size: stat.size,
          updatedAt: stat.modified,
        ));
      }
    }
  }

  String get currentPath {
    if (isInArchive) {
      return '${_archiveSource!.archiveName}:/${_archiveSource!.innerPath}';
    }
    if (side == PanelSide.local) return _localFileService.currentPath;
    return _remotePath;
  }
  String _remotePath = '/';

  List<PanelTab> get tabs => _tabs;
  String get activeTabId => _activeTabId;
  PanelTab? get activeTab =>
      _tabs.isEmpty ? null : _tabs.firstWhere(
        (t) => t.id == _activeTabId,
        orElse: () => _tabs.first,
      );

  // --- Sort ---
  void setSortBy(SortBy sortBy) {
    _sortBy = sortBy;
    _sortFiles();
    notifyListeners();
  }

  void toggleSortOrder() {
    _sortOrder = _sortOrder == SortOrder.ascending
        ? SortOrder.descending
        : SortOrder.ascending;
    _sortFiles();
    notifyListeners();
  }

  /// Compare two file items by a single sort key. Exposed for testing.
  static int compareSortKey(FileItem a, FileItem b, SortBy key) {
    switch (key) {
      case SortBy.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case SortBy.size:
        return (a.size ?? 0).compareTo(b.size ?? 0);
      case SortBy.date:
        return (a.updatedAt ?? DateTime(1970)).compareTo(b.updatedAt ?? DateTime(1970));
      case SortBy.extension:
        if (a.isFolder || b.isFolder) return 0;
        final extA = a.name.contains('.') ? a.name.split('.').last.toLowerCase() : '';
        final extB = b.name.contains('.') ? b.name.split('.').last.toLowerCase() : '';
        return extA.compareTo(extB);
    }
  }

  void _sortFiles() {
    if (_files == null || _files!.isEmpty) return;
    _files!.sort((a, b) {
      // ".." always stays at the top
      if (a.name == '..') return -1;
      if (b.name == '..') return 1;

      if (a.isFolder && !b.isFolder) return -1;
      if (!a.isFolder && b.isFolder) return 1;

      int comparison = compareSortKey(a, b, _sortBy);
      comparison = _sortOrder == SortOrder.ascending ? comparison : -comparison;

      // Secondary sort key when primary ties
      if (comparison == 0 && _secondarySortBy != null) {
        final int secondary = compareSortKey(a, b, _secondarySortBy!);
        comparison = _secondarySortOrder == SortOrder.ascending ? secondary : -secondary;
      }

      return comparison;
    });
  }

  // --- Selection ---
  bool isSelected(FileItem item) => _selection.contains(item);

  void toggleSelection(FileItem item, {bool shiftKey = false, bool ctrlKey = false}) {
    // Sync cursor to clicked item
    if (_files != null) {
      final idx = _files!.indexOf(item);
      if (idx != -1) _cursorIndex = idx;
    }
    // ".." cannot be selection-marked — clicking it just moves cursor
    if (item.name == '..') {
      _lastSelected = null;
      notifyListeners();
      return;
    }
    if (shiftKey && _lastSelected != null && _files != null) {
      final startIdx = _files!.indexOf(_lastSelected!);
      final endIdx = _files!.indexOf(item);
      if (startIdx != -1 && endIdx != -1) {
        final start = startIdx < endIdx ? startIdx : endIdx;
        final end = startIdx < endIdx ? endIdx : startIdx;
        for (var i = start; i <= end; i++) {
          if (_files![i].name != '..') _selection.add(_files![i]);
        }
      }
    } else if (ctrlKey) {
      if (_selection.contains(item)) {
        _selection.remove(item);
      } else {
        _selection.add(item);
      }
    } else {
      _selection.clear();
      _selection.add(item);
    }
    _lastSelected = item;
    notifyListeners();
  }

  void selectAll() {
    if (_files != null) {
      _selection.addAll(_files!.where((f) => f.name != '..'));
      notifyListeners();
    }
  }

  void invertSelection() {
    if (_files == null) return;
    final newSel = _files!.where((f) => f.name != '..' && !_selection.contains(f)).toSet();
    _selection
      ..clear()
      ..addAll(newSel);
    _lastSelected = null;
    notifyListeners();
  }

  void clearSelection() {
    _selection.clear();
    _lastSelected = null;
    notifyListeners();
  }

  // --- Cursor (keyboard focus, separate from selection marks) ---

  /// Set cursor to a specific item by reference.
  void setCursorToItem(FileItem item) {
    if (_files == null) return;
    final idx = _files!.indexOf(item);
    if (idx != -1) {
      _cursorIndex = idx;
      _itemToScrollTo = item;
      notifyListeners();
    }
  }

  /// Move cursor by [delta] rows. Clamps at list bounds.
  void moveCursor(int delta) {
    if (_files == null || _files!.isEmpty) return;
    final newIdx = (_cursorIndex + delta).clamp(0, _files!.length - 1);
    if (newIdx == _cursorIndex) return;
    _cursorIndex = newIdx;
    _itemToScrollTo = _files![_cursorIndex];
    notifyListeners();
  }

  /// DC-style Space / Insert: toggle selection mark on cursor item, advance down.
  /// When pressed on a folder with no calculated size yet, also triggers async
  /// folder size computation (shown inline in the size column, like DC).
  void spaceSelectAndAdvance() {
    if (_files == null || _files!.isEmpty) return;
    final idx = _cursorIndex.clamp(0, _files!.length - 1);
    _cursorIndex = idx;
    final item = _files![idx];
    // ".." cannot be marked
    if (item.name != '..') {
      if (_selection.contains(item)) {
        _selection.remove(item);
      } else {
        _selection.add(item);
      }
      _lastSelected = item;
      // DC: Space on a folder triggers inline size calculation
      if (item.isFolder && item.calculatedSize == null && item.path != null && !kIsWeb) {
        _calculateFolderSizeInBackground(item);
      }
    }
    final next = (idx + 1).clamp(0, _files!.length - 1);
    _cursorIndex = next;
    _itemToScrollTo = _files![next];
    notifyListeners();
  }

  /// Calculate folder size in a background isolate and update the file list entry.
  void _calculateFolderSizeInBackground(FileItem folder) {
    _computeFolderSize(folder.path!).then((size) {
      updateItemCalculatedSize(folder, size);
    }).catchError((_) {});
  }

  Future<int> _computeFolderSize(String path) async {
    int total = 0;
    try {
      final entities = await Directory(path).list(recursive: true).toList();
      for (final e in entities) {
        if (e is File) {
          final stat = await e.stat();
          total += stat.size;
        }
      }
    } catch (_) {}
    return total;
  }

  /// Shift+Arrow: move cursor AND extend/shrink selection range.
  void shiftMoveCursor(int delta) {
    if (_files == null || _files!.isEmpty) return;
    final cur = _cursorIndex.clamp(0, _files!.length - 1);
    final next = (cur + delta).clamp(0, _files!.length - 1);
    if (next == cur) return;
    // Add items swept over to selection
    final start = cur < next ? cur : next;
    final end = cur < next ? next : cur;
    for (var i = start; i <= end; i++) {
      _selection.add(_files![i]);
    }
    _lastSelected = _files![next];
    _cursorIndex = next;
    _itemToScrollTo = _files![next];
    notifyListeners();
  }

  /// Jump cursor to an absolute index (clamped). Used for Home/End/PgUp/PgDn.
  void moveCursorTo(int index) {
    if (_files == null || _files!.isEmpty) return;
    final newIdx = index.clamp(0, _files!.length - 1);
    if (newIdx == _cursorIndex) return;
    _cursorIndex = newIdx;
    _itemToScrollTo = _files![_cursorIndex];
    notifyListeners();
  }

  /// Reset or preserve cursor after a file listing changes.
  /// On first load (_cursorIndex == -1) or if files are empty, goes to 0.
  /// Otherwise keeps the cursor on the same item by name/path/uuid,
  /// falling back to clamping the current index within the new list length.
  /// Select all files matching [glob] pattern (e.g. "*.dart"). Numpad +.
  void selectByPattern(String glob) {
    if (_files == null) return;
    final lower = glob.toLowerCase();
    // Simple glob: "*.ext" or "prefix*" — convert to prefix/suffix match
    final isExtGlob = lower.startsWith('*.') && !lower.substring(2).contains('*');
    for (final f in _files!) {
      if (f.name == '..') continue;
      final name = f.name.toLowerCase();
      final matches = isExtGlob
          ? name.endsWith(lower.substring(1)) // "*.dart" → ".dart" suffix
          : _globMatch(lower, name);
      if (matches) _selection.add(f);
    }
    notifyListeners();
  }

  /// Deselect all files matching [glob] pattern. Numpad -.
  void deselectByPattern(String glob) {
    if (_files == null) return;
    final lower = glob.toLowerCase();
    final isExtGlob = lower.startsWith('*.') && !lower.substring(2).contains('*');
    _selection.removeWhere((f) {
      final name = f.name.toLowerCase();
      return isExtGlob
          ? name.endsWith(lower.substring(1))
          : _globMatch(lower, name);
    });
    notifyListeners();
  }

  bool _globMatch(String pattern, String text) {
    // Minimal glob: * matches anything
    if (!pattern.contains('*')) return pattern == text;
    final parts = pattern.split('*');
    int pos = 0;
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;
      final idx = text.indexOf(part, pos);
      if (idx == -1) return false;
      if (i == 0 && idx != 0) return false; // must start with prefix
      pos = idx + part.length;
    }
    if (!pattern.endsWith('*') && pos != text.length) return false;
    return true;
  }

  /// Jump cursor to the first file whose name starts with [char] (case-insensitive).
  /// Searches within the currently displayed (filtered) list and cycles.
  void quickJumpToChar(String char) {
    final displayed = filteredFiles;
    if (displayed == null || displayed.isEmpty) return;
    final q = char.toLowerCase();
    final start = _cursorIndex.clamp(0, displayed.length - 1);
    for (int i = 1; i <= displayed.length; i++) {
      final idx = (start + i) % displayed.length;
      final f = displayed[idx];
      if (f.name != '..' && f.name.toLowerCase().startsWith(q)) {
        // Map displayed index back to _files index for _cursorIndex
        if (_files != null) {
          final rawIdx = _files!.indexOf(f);
          if (rawIdx != -1) _cursorIndex = rawIdx;
        } else {
          _cursorIndex = idx;
        }
        _itemToScrollTo = f;
        notifyListeners();
        return;
      }
    }
  }

  void _resetCursor({FileItem? preserveItem}) {
    if (_files == null || _files!.isEmpty) {
      _cursorIndex = -1;
      return;
    }
    final anchor = preserveItem ?? cursorItem;
    if (anchor != null) {
      final idx = _files!.indexWhere((f) =>
          (f.uuid != null && f.uuid == anchor.uuid) ||
          (f.path != null && f.path == anchor.path) ||
          f.name == anchor.name);
      if (idx != -1) {
        _cursorIndex = idx;
        return;
      }
    }
    if (_cursorIndex < 0) {
      _cursorIndex = 0;
    } else {
      _cursorIndex = _cursorIndex.clamp(0, _files!.length - 1);
    }
  }

  // --- Navigation ---

  /// Refresh the current directory listing. Debounced to avoid rapid re-fetches
  /// (e.g. from multiple filesystem events or repeated F5 presses).
  Future<void> refresh() async {
    await _refreshLock.synchronized(() async {
      if (isInArchive) {
        await _loadArchiveFiles();
      } else if (_isFlatView) {
        await _loadFlatFiles();
      } else if (side == PanelSide.local) {
        await _localFileService.refresh();
        await _loadLocalFiles();
      } else if (_ref.read(authProvider).isConnected) {
        await _loadRemoteFiles();
      } else {
        await _loadLocalFiles();
      }
    });
  }

  /// Debounced refresh — coalesces rapid refresh calls within [delay].
  void refreshDebounced({Duration delay = const Duration(milliseconds: 500)}) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(delay, () => refresh());
  }

  /// Alias used by widgets and keyboard shortcuts.
  void refreshFiles() => refresh();

  Future<void> navigateUp() async {
    // If inside an archive, navigate up within archive or exit
    if (isInArchive) {
      await navigateUpArchive();
      return;
    }
    // If in flat view, exit flat view
    if (_isFlatView) {
      _isFlatView = false;
      await refresh();
      return;
    }
    if (side == PanelSide.local) {
      final parent = p.dirname(currentPath);
      if (parent != currentPath && parent != '.') {
        await navigateToPath(parent);
      }
    } else {
      if (_remotePath != '/') {
        final parent = p.dirname(_remotePath);
        await navigateToPath(parent.isEmpty ? '/' : parent);
      }
    }
  }

  Future<void> navigateToPath(String path, {FileItem? selectItem}) async {
    _selection.clear();
    _lastSelected = null;
    if (_isTypeahead) { _filterQuery = ''; _isTypeahead = false; }
    if (side == PanelSide.local) {
      if (!kIsWeb && !await _localFileService.hasAccessToPath(path)) {
        final newGrant = await _localFileService.requestDirectoryAccess(initialDirectory: path);
        if (newGrant != null) {
          path = newGrant;
        } else {
          _ref.read(errorProvider).addError(
            'Cannot access paths outside the granted directory.',
          );
          return;
        }
      } else if (kIsWeb && !await _localFileService.hasAccessToPath(path)) {
        return;
      }
      _localFileService.currentPath = path;
      await _loadLocalFiles();
    } else {
      _remotePath = path;
      if (_ref.read(authProvider).isConnected) {
        await _loadRemoteFiles();
      } else {
        await _loadLocalFiles();
      }
    }

    if (selectItem != null && _files != null) {
      try {
        final found = _files!.firstWhere(
          (f) => side == PanelSide.local
              ? f.path == selectItem.path
              : f.uuid == selectItem.uuid,
        );
        _selection.clear();
        _selection.add(found);
        _lastSelected = found;
        _itemToScrollTo = found;
      } catch (_) {}
    }

    _syncTabPath();
    _pushHistory(currentPath);
    _ref.read(recentLocationsProvider).add(currentPath, side);
    notifyListeners();
  }

  Future<void> navigateInto(FileItem item) async {
    // If we're inside an archive, navigate within it
    if (isInArchive) {
      if (item.isFolder && item.path != null) {
        await _navigateArchive(item.path!);
      }
      return;
    }
    // If a non-folder file is an archive, enter it
    if (!item.isFolder && ArchiveService.isArchive(item.name)) {
      await enterArchive(item);
      return;
    }
    if (!item.isFolder) return;
    if (side == PanelSide.local) {
      if (item.path != null) await navigateToPath(item.path!);
    } else {
      await navigateToPath(p.posix.join(_remotePath, item.name));
    }
  }

  Future<void> pickLocalDirectory() async {
    try {
      final dir = await _localFileService.requestDirectoryAccess(
        initialDirectory: _localFileService.currentPath,
      );
      if (dir != null) {
        _localFileService.currentPath = dir;
        await _loadLocalFiles();
        notifyListeners();
      }
    } catch (e) {
      _ref.read(errorProvider).addError('Error picking directory: $e');
    }
  }

  /// Update a file item's calculated size (for inline directory size display).
  void updateItemCalculatedSize(FileItem item, int size) {
    if (_files == null) return;
    final idx = _files!.indexOf(item);
    if (idx == -1) return;
    _files![idx] = item.copyWith(calculatedSize: size);
    notifyListeners();
  }

  // --- File operations (local panel helpers) ---
  Future<void> deleteFiles(List<FileItem> files) async {
    final errors = _ref.read(errorProvider);
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final providerName = side == PanelSide.local ? 'local' : _ref.read(authProvider).client.providerName;
    if (kIsWeb && side == PanelSide.local) return;
    try {
      final client = _ref.read(authProvider).client;
      for (final file in files) {
        final src = file.path ?? p.posix.join(_remotePath, file.name);
        if (side == PanelSide.local) {
          if (file.isFolder) {
            await Directory(file.path!).delete(recursive: true);
          } else {
            await File(file.path!).delete();
          }
        } else {
          final deletePath = file.path ?? p.posix.join(_remotePath, file.name);
          await client.deletePath(deletePath);
        }
        await audit.logSuccess(
          operation: AuditOperation.delete,
          sourcePath: src,
          provider: providerName,
          sizeBytes: file.size,
        );
        actionHistory.record(
          type: ActionType.delete,
          originalPath: src,
          provider: providerName,
          metadata: {'name': file.name, 'isFolder': file.isFolder},
        );
      }
      // Remember cursor position so we can land on the next item after delete
      final savedIdx = _cursorIndex;
      await refresh();
      clearSelection();
      // Move cursor to the same index (now points to the next item) or clamp to last
      if (_files != null && _files!.isNotEmpty) {
        _cursorIndex = savedIdx.clamp(0, _files!.length - 1);
        _itemToScrollTo = _files![_cursorIndex];
        notifyListeners();
      }
    } catch (e) {
      errors.addError('Delete failed: $e');
      for (final file in files) {
        final src = file.path ?? p.posix.join(_remotePath, file.name);
        await audit.logError(
          operation: AuditOperation.delete,
          sourcePath: src,
          provider: providerName,
          error: e.toString(),
        );
      }
    }
  }

  // --- In-place rename ---

  void startRename(FileItem item) {
    if (item.name == '..') return;
    _renamingItem = item;
    notifyListeners();
  }

  void cancelRename() {
    if (_renamingItem == null) return;
    _renamingItem = null;
    notifyListeners();
  }

  Future<void> commitRename(String newName) async {
    final item = _renamingItem;
    if (item == null) return;
    _renamingItem = null;
    notifyListeners();
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == item.name) return;
    await renameFile(item, trimmed);
  }

  Future<void> renameFile(FileItem file, String newName) async {
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final providerName = side == PanelSide.local ? 'local' : _ref.read(authProvider).client.providerName;
    final src = file.path ?? p.posix.join(_remotePath, file.name);
    if (kIsWeb && side == PanelSide.local) return;
    try {
      String computedNewPath;
      if (side == PanelSide.local) {
        computedNewPath = p.join(p.dirname(file.path!), newName);
        if (file.isFolder) {
          await Directory(file.path!).rename(computedNewPath);
        } else {
          await File(file.path!).rename(computedNewPath);
        }
      } else {
        final client = _ref.read(authProvider).client;
        final sourcePath = file.path ?? p.posix.join(_remotePath, file.name);
        computedNewPath = p.posix.join(p.posix.dirname(sourcePath), newName);
        await client.renamePath(sourcePath, newName);
      }
      await audit.logSuccess(
        operation: AuditOperation.rename,
        sourcePath: src,
        targetPath: newName,
        provider: providerName,
      );
      actionHistory.record(
        type: ActionType.rename,
        originalPath: src,
        newPath: computedNewPath,
        provider: providerName,
        metadata: {'oldName': file.name, 'newName': newName},
      );
      await refresh();
    } catch (e) {
      _ref.read(errorProvider).addError('Rename failed: $e');
      await audit.logError(
        operation: AuditOperation.rename,
        sourcePath: src,
        targetPath: newName,
        provider: providerName,
        error: e.toString(),
      );
    }
  }

  Future<void> createFolder(String name) async {
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final providerName = side == PanelSide.local ? 'local' : _ref.read(authProvider).client.providerName;
    final folderPath = side == PanelSide.local
        ? p.join(currentPath, name)
        : p.posix.join(_remotePath, name);
    if (kIsWeb && side == PanelSide.local) return;
    try {
      if (side == PanelSide.local) {
        await Directory(p.join(currentPath, name)).create();
      } else {
        final client = _ref.read(authProvider).client;
        await client.createFolderPath(p.posix.join(_remotePath, name));
      }
      await audit.logSuccess(
        operation: AuditOperation.createFolder,
        sourcePath: folderPath,
        provider: providerName,
      );
      actionHistory.record(
        type: ActionType.createFolder,
        originalPath: folderPath,
        provider: providerName,
        metadata: {'name': name},
      );
      await refresh();
    } catch (e) {
      _ref.read(errorProvider).addError('Create folder failed: $e');
      await audit.logError(
        operation: AuditOperation.createFolder,
        sourcePath: folderPath,
        provider: providerName,
        error: e.toString(),
      );
    }
  }

  Future<void> moveFiles(List<FileItem> files, String targetPath) async {
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final providerName = side == PanelSide.local ? 'local' : _ref.read(authProvider).client.providerName;
    if (kIsWeb && side == PanelSide.local) return;
    try {
      for (final file in files) {
        final src = file.path ?? p.posix.join(_remotePath, file.name);
        final String movedToPath;
        if (side == PanelSide.local) {
          movedToPath = p.join(targetPath, file.name);
          if (file.isFolder) {
            await Directory(file.path!).rename(movedToPath);
          } else {
            await File(file.path!).rename(movedToPath);
          }
        } else {
          final client = _ref.read(authProvider).client;
          final sourcePath = file.path ?? p.posix.join(_remotePath, file.name);
          movedToPath = p.posix.join(targetPath, file.name);
          await client.movePath(sourcePath, targetPath);
        }
        await audit.logSuccess(
          operation: AuditOperation.move,
          sourcePath: src,
          targetPath: targetPath,
          provider: providerName,
          sizeBytes: file.size,
        );
        actionHistory.record(
          type: ActionType.move,
          originalPath: src,
          newPath: movedToPath,
          provider: providerName,
          metadata: {'name': file.name, 'targetDir': targetPath},
        );
      }
      await refresh();
      clearSelection();
    } catch (e) {
      _ref.read(errorProvider).addError('Move failed: $e');
      for (final file in files) {
        final src = file.path ?? p.posix.join(_remotePath, file.name);
        await audit.logError(
          operation: AuditOperation.move,
          sourcePath: src,
          targetPath: targetPath,
          provider: providerName,
          error: e.toString(),
        );
      }
      await refresh();
    }
  }

  Future<void> copyFiles(List<FileItem> files, String targetPath) async {
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final providerName = side == PanelSide.local ? 'local' : _ref.read(authProvider).client.providerName;
    if (kIsWeb && side == PanelSide.local) return;
    try {
      for (final file in files) {
        final src = file.path ?? p.posix.join(_remotePath, file.name);
        // copyPath is the new file that was created — used for undo (delete the copy)
        final String copyPath;
        if (side == PanelSide.local) {
          copyPath = p.join(targetPath, file.name);
          if (file.isFolder) {
            await _copyDirectory(file.path!, copyPath);
          } else {
            await File(file.path!).copy(copyPath);
          }
        } else {
          if (kIsWeb) throw UnsupportedError('Remote copy not supported on web');
          final client = _ref.read(authProvider).client;
          final sourcePath = file.path ?? p.posix.join(_remotePath, file.name);
          copyPath = p.posix.join(targetPath, file.name);
          if (client.supportsServerSideCopy) {
            _log.info('Using server-side copy for ${file.name}');
            await client.copyPath(sourcePath, targetPath);
          } else {
            final tempPath = p.join(Directory.systemTemp.path, file.name);
            await client.downloadFileByPath(sourcePath, tempPath);
            final data = await File(tempPath).readAsBytes();
            await client.uploadFile(data, file.name, targetPath);
            await File(tempPath).delete();
          }
        }
        await audit.logSuccess(
          operation: AuditOperation.copy,
          sourcePath: src,
          targetPath: targetPath,
          provider: providerName,
          sizeBytes: file.size,
        );
        // For copy: originalPath = the new copy, newPath = source (for display)
        actionHistory.record(
          type: ActionType.copy,
          originalPath: copyPath,
          newPath: src,
          provider: providerName,
          metadata: {'name': file.name, 'sourceDir': p.dirname(src), 'targetDir': targetPath},
        );
      }
      await refresh();
    } catch (e) {
      _ref.read(errorProvider).addError('Copy failed: $e');
      for (final file in files) {
        final src = file.path ?? p.posix.join(_remotePath, file.name);
        await audit.logError(
          operation: AuditOperation.copy,
          sourcePath: src,
          targetPath: targetPath,
          provider: providerName,
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _copyDirectory(String source, String target) async {
    if (kIsWeb) return;
    await Directory(target).create(recursive: true);
    final entities = await Directory(source).list().toList();
    for (final entity in entities) {
      if (entity is File) {
        await entity.copy(p.join(target, p.basename(entity.path)));
      } else if (entity is Directory) {
        await _copyDirectory(entity.path, p.join(target, p.basename(entity.path)));
      }
    }
  }

  // --- Tabs ---
  String _nextTabId() => 'tab_${_tabIdCounter++}';

  String get _tabStorageKey => 'panel_tabs_${side.name}';

  void _initFirstTab() {
    final id = _nextTabId();
    final path = side == PanelSide.local ? _localFileService.currentPath : _remotePath;
    _tabs.add(PanelTab(id: id, path: path));
    _activeTabId = id;
  }

  /// Restore tabs from SharedPreferences. Falls back to single default tab.
  Future<void> _restoreTabs() async {
    // Skip persistence in test environments to avoid pending timer assertions
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _initFirstTab();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tabStorageKey);
      if (raw != null) {
        final List<dynamic> list = json.decode(raw);
        if (list.isNotEmpty) {
          _tabs.clear();
          for (final item in list) {
            final id = _nextTabId();
            _tabs.add(PanelTab(
              id: id,
              path: item['path'] ?? '/',
              isPinned: item['pinned'] == true,
            ));
          }
          final savedActiveIdx = prefs.getInt('${_tabStorageKey}_active') ?? 0;
          _activeTabId = _tabs[savedActiveIdx.clamp(0, _tabs.length - 1)].id;

          // Sync local file service to restored path
          if (side == PanelSide.local) {
            final tab = activeTab;
            if (tab != null) _localFileService.currentPath = tab.path;
          } else {
            final tab = activeTab;
            if (tab != null) _remotePath = tab.path;
          }
          notifyListeners();
          if (side == PanelSide.remote) refresh();
          return;
        }
      }
    } catch (e) {
      _log.warn('Tab restore failed', e);
    }
    _initFirstTab();
    if (side == PanelSide.remote) {
      if (!kIsWeb && !_ref.read(authProvider).isConnected) {
        _remotePath = Platform.environment['HOME'] ?? '/';
        final tab = activeTab;
        if (tab != null) tab.path = _remotePath;
      }
      refresh();
    }
  }

  /// Persist current tabs to SharedPreferences.
  Future<void> _saveTabs() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _tabs.map((t) => {'path': t.path, 'pinned': t.isPinned}).toList();
      await prefs.setString(_tabStorageKey, json.encode(list));
      await prefs.setInt('${_tabStorageKey}_active', _tabs.indexWhere((t) => t.id == _activeTabId).clamp(0, _tabs.length - 1));
    } catch (e) {
      _log.warn('Tab save failed', e);
    }
  }

  void addTab({String? path}) {
    final id = _nextTabId();
    _tabs.add(PanelTab(id: id, path: path ?? currentPath));
    _activeTabId = id;
    notifyListeners();
    _saveTabs();
  }

  void closeTab(String tabId) {
    if (_tabs.length <= 1) return;
    final tab = _tabs.firstWhere((t) => t.id == tabId, orElse: () => _tabs.first);
    if (tab.isPinned) return;
    final idx = _tabs.indexOf(tab);
    _tabs.remove(tab);
    if (_activeTabId == tabId) {
      final newIdx = idx.clamp(0, _tabs.length - 1);
      _activeTabId = _tabs[newIdx].id;
    }
    notifyListeners();
    _saveTabs();
  }

  void selectTab(String tabId) {
    _activeTabId = tabId;
    final tab = activeTab;
    if (tab != null) {
      if (side == PanelSide.local) {
        _localFileService.currentPath = tab.path;
      } else {
        _remotePath = tab.path;
      }
    }
    notifyListeners();
    _saveTabs();
    refresh();
  }

  /// Cycle to the next tab. Wraps around.
  void nextTab() {
    if (_tabs.length <= 1) return;
    final idx = _tabs.indexWhere((t) => t.id == _activeTabId);
    final nextIdx = (idx + 1) % _tabs.length;
    selectTab(_tabs[nextIdx].id);
  }

  /// Cycle to the previous tab. Wraps around.
  void previousTab() {
    if (_tabs.length <= 1) return;
    final idx = _tabs.indexWhere((t) => t.id == _activeTabId);
    final prevIdx = (idx - 1 + _tabs.length) % _tabs.length;
    selectTab(_tabs[prevIdx].id);
  }

  void toggleTabPin(String tabId) {
    final tab = _tabs.firstWhere((t) => t.id == tabId, orElse: () => _tabs.first);
    tab.isPinned = !tab.isPinned;
    notifyListeners();
    _saveTabs();
  }

  void renameTab(String tabId, String newLabel) {
    final tab = _tabs.firstWhere((t) => t.id == tabId, orElse: () => _tabs.first);
    tab.label = newLabel;
    notifyListeners();
    _saveTabs();
  }

  void _syncTabPath() {
    final tab = activeTab;
    if (tab != null) {
      tab.path = currentPath;
      tab.updateLabel();
    }
    _saveTabs();
  }

  // --- Internal loading ---
  Future<void> _initializeLocalPath() async {
    try {
      await _localFileService.getInitialPath();
      if (!kIsWeb && Platform.isMacOS && _localFileService.grantedBasePath == null) {
        _ref.read(errorProvider).addError(
          'Please select a base directory to grant access (e.g., your home folder)',
        );
        final grantedPath = await _localFileService.requestDirectoryAccess(
          initialDirectory: await _localFileService.getSafeFallbackDirectory(),
        );
        if (grantedPath != null) {
          _ref.read(errorProvider).clearErrors();
        } else {
          _localFileService.currentPath = await _localFileService.getSafeFallbackDirectory();
          _ref.read(errorProvider).clearErrors();
          _ref.read(errorProvider).addError('Access cancelled. Using fallback directory.');
        }
      }
      await _loadLocalFiles();
      _pushHistory(currentPath);
      notifyListeners();
    } catch (e) {
      _localFileService.currentPath = await _localFileService.getSafeFallbackDirectory();
      _ref.read(errorProvider).addError(e.toString());
      notifyListeners();
    }
  }

  Future<void> _loadLocalFiles() async {
    try {
      final entities = await _localFileService.listDirectory(currentPath);
      if (entities == null) {
        _files = [];
        if (!kIsWeb) {
          _ref.read(errorProvider).addError('Local file access is not supported on this platform.');
        }
        _log.warn('listDirectory returned null for "$currentPath"');
        notifyListeners();
        return;
      }
      _log.debug('listDirectory("$currentPath") returned ${entities.length} entities');

      final items = <FileItem>[];
      for (final entity in entities) {
        try {
          final name = p.basename(entity.path);
          if (!_showHiddenFiles && name.startsWith('.')) continue;

          if (kIsWeb) {
            final isFolder = entity is Directory;
            int size = 0;
            DateTime updated = DateTime.now();
            if (!isFolder) {
              final meta = _localFileService.getWebMetadata(entity.path);
              size = meta['size'] ?? 0;
              updated = meta['modified'] ?? DateTime.now();
            }
            items.add(FileItem(name: name, path: entity.path, isFolder: isFolder, size: size, updatedAt: updated));
            continue;
          }

          final stat = await entity.stat();
          final linkType = await FileSystemEntity.type(entity.path, followLinks: false);
          final isLink = linkType == FileSystemEntityType.link;
          String? linkTarget;
          if (isLink) {
            try { linkTarget = await Link(entity.path).target(); } catch (_) {}
          }
          if (stat.type == FileSystemEntityType.directory) {
            items.add(FileItem(name: name, path: entity.path, isFolder: true, updatedAt: stat.modified, isSymlink: isLink ? true : null, symlinkTarget: linkTarget));
          } else if (stat.type == FileSystemEntityType.file) {
            items.add(FileItem(name: name, path: entity.path, isFolder: false, size: stat.size, updatedAt: stat.modified, isSymlink: isLink ? true : null, symlinkTarget: linkTarget));
          }
        } catch (_) {
          continue;
        }
      }

      // Prepend ".." parent-dir entry unless we're at root
      final parentPath = p.dirname(currentPath);
      if (parentPath != currentPath && currentPath != '/') {
        items.insert(0, FileItem(
          name: '..',
          path: parentPath,
          isFolder: true,
        ));
      }
      final prev = cursorItem;
      _files = items;
      _sortFiles();
      _resetCursor(preserveItem: prev);
      _ref.read(errorProvider).clearErrors();
      // Fire-and-forget free space fetch (result stored in _freeBytes, shown in status bar)
      if (!kIsWeb && side == PanelSide.local) _updateFreeSpace(currentPath);
      notifyListeners();
    } catch (e) {
      if (!kIsWeb && (e is PathAccessException || e.toString().contains('Operation not permitted'))) {
        _files = [];
        _ref.read(errorProvider).addError('Permission denied. Use the Browse button to grant access.');
        notifyListeners();
        return;
      }
      _files = [];
      _ref.read(errorProvider).addError(e.toString());
      notifyListeners();
    }
  }

  void _updateFreeSpace(String path) {
    // Skip in test environments to avoid pending OS-process timers that
    // cause "test failed after it had already completed" assertions.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    Process.run('df', ['-k', path]).then((result) {
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length >= 2) {
        final parts = lines.last.trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final kb = int.tryParse(parts[3]);
          if (kb != null) { _freeBytes = kb * 1024; notifyListeners(); }
        }
      }
    }).catchError((_) {});
  }


  Future<void> _loadRemoteFiles() async {
    // When the panel is showing search results, skip the normal directory
    // listing unless clearSearchResults() has already reset the flag.
    if (_showingSearchResults) {
      _log.debug('Skipping _loadRemoteFiles — panel is showing search results');
      return;
    }

    final auth = _ref.read(authProvider);
    try {
      if (!auth.client.isAuthenticated && !auth.isConnected) {
        _files = [];
        notifyListeners();
        return;
      }

      final result = await auth.client.listPath(_remotePath);

      final folders = (result['folders'] as List<dynamic>?)?.map((item) {
        final map = item as Map<String, dynamic>;
        DateTime? folderDate;
        final rawDate = map['modificationTime'] ?? map['lastModified'] ?? map['timestamp'];
        if (rawDate != null) {
          try {
            if (rawDate is int) {
              folderDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
            } else {
              folderDate = DateTime.parse(rawDate.toString());
            }
          } catch (_) {}
        }
        final meta = Map<String, dynamic>.from(map)
          ..removeWhere((k, _) => const {'name', 'uuid', 'modificationTime', 'lastModified', 'timestamp'}.contains(k));
        return FileItem(name: map['name'] ?? 'Unknown', isFolder: true, uuid: map['uuid'], updatedAt: folderDate, metadata: meta.isNotEmpty ? meta : null);
      }).toList() ?? [];

      final files = (result['files'] as List<dynamic>?)?.map((item) {
        final map = item as Map<String, dynamic>;
        final fileName = map['name'] ?? 'Unknown';
        final rawType = map['fileType'] ?? map['type'] ?? '';
        final fileType = rawType.toString().toLowerCase();
        String fullName = fileName;
        if (fileType.isNotEmpty && fileType != 'file' && !fileName.toLowerCase().endsWith('.$fileType')) {
          fullName = '$fileName.$rawType';
        }
        DateTime? fileDate;
        final rawDate = map['modificationTime'] ?? map['lastModified'];
        if (rawDate != null) {
          try {
            if (rawDate is int) {
              fileDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
            } else {
              fileDate = DateTime.parse(rawDate.toString());
            }
          } catch (_) {}
        }
        final meta = Map<String, dynamic>.from(map)
          ..removeWhere((k, _) => const {'name', 'uuid', 'size', 'modificationTime', 'lastModified', 'fileType', 'type', 'timestamp'}.contains(k));
        return FileItem(name: fullName, isFolder: false, size: map['size'] as int?, uuid: map['uuid'], updatedAt: fileDate, metadata: meta.isNotEmpty ? meta : null);
      }).toList() ?? [];

      // Prepend ".." for cloud paths that aren't root
      final allItems = [...folders, ...files];
      if (_remotePath != '/' && _remotePath.isNotEmpty) {
        final parentRemote = p.posix.dirname(_remotePath);
        allItems.insert(0, FileItem(
          name: '..',
          path: parentRemote.isEmpty ? '/' : parentRemote,
          isFolder: true,
        ));
      }
      final prev = cursorItem;
      _files = allItems;
      _sortFiles();
      _resetCursor(preserveItem: prev);
      _ref.read(errorProvider).clearErrors();
      notifyListeners();
    } catch (e) {
      _log.error('Refresh error', e);
      _files = [];
      _ref.read(errorProvider).addError(e.toString());
      notifyListeners();
    }
  }
}

class _AsyncLock {
  Completer<void>? _completer;
  Future<T> synchronized<T>(Future<T> Function() action) async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
    try {
      return await action();
    } finally {
      final c = _completer!;
      _completer = null;
      c.complete();
    }
  }
}

final panelProvider = ChangeNotifierProvider.family<PanelNotifier, PanelSide>((ref, side) {
  return PanelNotifier(ref, side);
});
