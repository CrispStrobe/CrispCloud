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
import '../models/sort.dart';
import '../services/archive_service.dart';
import '../services/archive_viewer_service.dart';
import '../services/audit_service.dart';
import '../services/cloud_storage_interface.dart'
    show CloudStorageClient, CloudStorageClientCapabilities;
import '../services/directory_cache_service.dart';
import '../services/local_file_service.dart';
import '../services/log_service.dart';
import '../services/panel_source_service.dart';
import '../utils/async_lock.dart';
import 'action_history_provider.dart';
import 'auth_provider.dart';
import 'core_providers.dart';
import 'error_provider.dart';
import 'panel_source_provider.dart';
import 'quick_search_provider.dart';
import 'recent_locations_provider.dart';

// SortBy and SortOrder are defined in models/sort.dart
export '../models/sort.dart';

/// The storage source that actually produced a listed file, captured before
/// the listing request. It is independent of the pane's label or dropdown.
class PanelFileOrigin {
  const PanelFileOrigin._(this.source, this._isCurrent);

  final PanelSource source;
  final bool Function() _isCurrent;

  /// Remains false after the captured account disconnects or changes.
  bool get isCurrent => _isCurrent();
}

class PanelNotifier extends ChangeNotifier {
  static const _log = Log('PanelNotifier');

  final Ref _ref;
  final PanelSide side;

  final LocalFileService _localFileService;

  List<FileItem>? _files;
  final _fileOrigins = Expando<PanelFileOrigin>('listed file origin');
  int _listingGeneration = 0;
  int _verifiedListingGeneration = -1;
  int _accountGeneration = 0;
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
  // Behavior selected for the current type-ahead session.
  QuickSearchMode _typeaheadMode = QuickSearchMode.jump;
  Timer? _typeaheadResetTimer;

  // Per-panel navigation history (back/forward like a browser)
  final List<String> _navHistory = [];
  int _historyIndex = -1;

  // Tabs
  int _tabIdCounter = 0;
  final List<PanelTab> _tabs = [];
  String _activeTabId = '';

  final _refreshLock = AsyncLock();
  Timer? _refreshDebounce;
  bool _isDisposed = false;

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

  // Loading state — true while a directory listing is being fetched.
  bool _isLoading = false;
  bool get isLoading => _isLoading;

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
  String? _lastFreeSpacePath;
  DateTime? _lastFreeSpaceTime;

  // Per-panel local path — avoids sharing the singleton _localFileService.currentPath
  // between two panels on web.
  String _localPath = '/';

  PanelNotifier(this._ref, this.side)
      : _localFileService = _ref.read(localFileServiceProvider) {
    // ChangeNotifier listeners cannot compare prev/next objects: both can be
    // the same mutated notifier. Retain a value snapshot for account changes.
    final initialAuth = _ref.read(authProvider);
    var account = (
      initialAuth.client,
      initialAuth.userEmail,
      initialAuth.isConnected,
      initialAuth.client.userId,
      initialAuth.client.bucketId,
    );
    _ref.listen<AuthNotifier>(authProvider, (_, next) {
      final current = (
        next.client,
        next.userEmail,
        next.isConnected,
        next.client.userId,
        next.client.bucketId,
      );
      if (current != account) {
        _accountGeneration++;
        account = current;
      }
    });
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
          _remotePath = kIsWeb ? '/' : (Platform.environment['HOME'] ?? '/');
          refresh();
        }
      });
    }
    // Listen for panel source changes (e.g. user switches provider in dropdown).
    _ref.listen<PanelSource>(panelSourceProvider(side), (prev, next) {
      if (prev == next) return;
      _listingGeneration++;
      _log.info(
          'Source switched: ${prev?.displayName} → ${next.displayName} (path=${next.currentPath})');
      if (next.isLocal) {
        _localPath = next.currentPath;
        _loadLocalFiles();
      } else if (next.isRemote) {
        _remotePath = next.currentPath;
        _loadRemoteFiles();
      }
      notifyListeners();
    });
  }

  // --- Getters ---
  List<FileItem>? get files => _files;

  /// Returns an origin only for this exact object in the current verified
  /// listing. A same-path object from search, an archive, an old listing, or
  /// another account must never authorize an editor write.
  PanelFileOrigin? originForFile(FileItem file) {
    if (_isDisposed) return null;
    final selectedSource = _ref.read(panelSourceProvider(side));
    if (_isLoading || _showingSearchResults ||
        _verifiedListingGeneration != _listingGeneration ||
        selectedSource.isArchive || selectedSource.isContainer ||
        isInArchive || _isFlatView ||
        !(_files?.any((item) => identical(item, file)) ?? false)) {
      return null;
    }
    final origin = _fileOrigins[file];
    return origin != null && origin.isCurrent ? origin : null;
  }

  void _recordOrigins(Iterable<FileItem> files, PanelFileOrigin origin) {
    final listed = files.toList(growable: false);
    // The preview uses selection.first; keeping the old object here would
    // leave it permanently outside the exact-identity origin gate after a
    // refresh or the native metadata pass. Resolve references while their
    // old origin is still available, before stamping the new publication.
    FileItem? replacement(FileItem? previous) {
      if (previous == null) return null;
      final before = _fileOrigins[previous];
      if (before == null || !before.isCurrent || !origin.isCurrent ||
          !_sameFileSource(before.source, origin.source)) {
        return null;
      }
      FileItem? match;
      for (final candidate in listed) {
        if (candidate.isFolder != previous.isFolder) continue;
        final matches = previous.uuid != null
            ? candidate.uuid == previous.uuid
            : previous.path != null
                ? candidate.path == previous.path
                : candidate.name == previous.name;
        if (!matches) continue;
        // Duplicate identifiers are ambiguous; require a new user selection.
        if (match != null) return null;
        match = candidate;
      }
      return match;
    }

    final selected = _selection.map(replacement).whereType<FileItem>().toList();
    final lastSelected = replacement(_lastSelected);
    final scrollTarget = replacement(_itemToScrollTo);
    _verifiedListingGeneration = _listingGeneration;
    for (final file in listed) {
      _fileOrigins[file] = origin;
    }
    _selection..clear()..addAll(selected);
    _lastSelected = lastSelected;
    _itemToScrollTo = scrollTarget;
  }

  static bool _sameFileSource(PanelSource before, PanelSource after) {
    if (before is LocalPanelSource && after is LocalPanelSource) {
      return before.path == after.path;
    }
    if (before is RemotePanelSource && after is RemotePanelSource) {
      return identical(before.client, after.client) &&
          before.providerName == after.providerName && before.path == after.path;
    }
    return false;
  }

  PanelFileOrigin _remoteOrigin(
      CloudStorageClient client, String providerName, String path) {
    final generation = _accountGeneration;
    final email = _ref.read(authProvider).userEmail;
    final userId = client.userId;
    final bucketId = client.bucketId;
    return PanelFileOrigin._(
      RemotePanelSource(providerName: providerName, client: client, path: path),
      () {
        if (_isDisposed || generation != _accountGeneration) return false;
        final auth = _ref.read(authProvider);
        return auth.isConnected && identical(auth.client, client) &&
            auth.userEmail == email && client.isAuthenticated &&
            client.userId == userId && client.bucketId == bucketId;
      },
    );
  }
  Set<FileItem> get selection => _selection;
  FileItem? get lastSelected => _lastSelected;
  FileItem? get itemToScrollTo => _itemToScrollTo;
  void clearItemToScrollTo() {
    _itemToScrollTo = null;
  }

  int get cursorIndex => _cursorIndex;

  /// Identity-based indexOf: FileItem equality is path/uuid based, which can
  /// collapse distinct in-memory entries (e.g. items without a path).
  static int _indexOfIdentical(List<FileItem> items, FileItem item) {
    for (var i = 0; i < items.length; i++) {
      if (identical(items[i], item)) return i;
    }
    return -1;
  }

  static bool _containsIdentical(List<FileItem> items, FileItem item) =>
      _indexOfIdentical(items, item) >= 0;
  FileItem? get cursorItem =>
      (_files != null && _cursorIndex >= 0 && _cursorIndex < _files!.length)
          ? _files![_cursorIndex]
          : null;

  SortBy get sortBy => _sortBy;
  SortOrder get sortOrder => _sortOrder;
  String get filterQuery => _filterQuery;
  bool get isTypeahead => _isTypeahead;
  QuickSearchMode get typeaheadMode => _typeaheadMode;

  /// True when the current type-ahead narrows the visible listing.
  bool get isQuickFilterActive =>
      _isTypeahead && _typeaheadMode == QuickSearchMode.filter;

  /// The entries currently shown by the panel (filter applied when active).
  List<FileItem>? get displayedFiles => filteredFiles;

  /// Cursor index within [displayedFiles] (-1 when absent).
  int get displayedCursorIndex {
    final displayed = filteredFiles;
    if (displayed == null) return -1;
    final item = cursorItem;
    if (item == null) return -1;
    return _indexOfIdentical(displayed, item);
  }

  /// Number of quick-search matches (excludes the ".." entry).
  int get typeaheadMatchCount => _typeaheadMatches().length;

  /// 1-based position of the cursor within the quick-search matches, or 0.
  int get typeaheadMatchPosition {
    final matches = _typeaheadMatches();
    final item = cursorItem;
    if (item == null) return 0;
    final index = _indexOfIdentical(matches, item);
    return index < 0 ? 0 : index + 1;
  }

  /// Whether the filter query should narrow the listing right now.
  bool get _isFiltering =>
      _filterQuery.isNotEmpty &&
      (!_isTypeahead || _typeaheadMode == QuickSearchMode.filter);

  /// Returns files filtered by the current filter query (client-side, no re-fetch).
  List<FileItem>? get filteredFiles {
    if (_files == null) return null;
    if (!_isFiltering) return _files;
    final settings = _ref.read(quickSearchSettingsProvider);
    final q = settings.caseSensitive
        ? _filterQuery
        : _filterQuery.toLowerCase();
    return [
      if (_files!.isNotEmpty && _files!.first.name == '..') _files!.first,
      ..._files!.where((f) => _matchesQuickSearch(f, q, settings)),
    ];
  }

  bool _matchesQuickSearch(
    FileItem file,
    String query,
    QuickSearchSettings settings,
  ) {
    if (file.name == '..') return false;
    final name = settings.caseSensitive ? file.name : file.name.toLowerCase();
    return settings.matchFromStart
        ? name.startsWith(query)
        : name.contains(query);
  }

  /// Entries matching the current query, in listing order, excluding "..".
  List<FileItem> _typeaheadMatches() {
    final files = _files;
    if (files == null || _filterQuery.isEmpty) return const <FileItem>[];
    final settings = _ref.read(quickSearchSettingsProvider);
    final q = settings.caseSensitive
        ? _filterQuery
        : _filterQuery.toLowerCase();
    return files.where((f) => _matchesQuickSearch(f, q, settings)).toList();
  }

  /// Set a client-side filter query. Filters without re-fetching from server.
  void setFilter(String query) {
    _filterQuery = query;
    _isTypeahead = false;
    if (_isFiltering) {
      final current = cursorItem;
      final displayed = filteredFiles;
      if (displayed != null &&
          displayed.isNotEmpty &&
          (current == null || !_containsIdentical(displayed, current))) {
        final first = displayed.firstWhere(
          (f) => f.name != '..',
          orElse: () => displayed.first,
        );
        _setCursorToItem(first);
      }
    }
    notifyListeners();
  }

  /// Clear the client-side filter.
  void clearFilter() {
    _typeaheadResetTimer?.cancel();
    _filterQuery = '';
    _isTypeahead = false;
    notifyListeners();
  }

  // --- Type-ahead incremental search (DC-style: type directly in file list) ---

  /// Append [char] to the type-ahead query, then either filter the listing
  /// (quick filter mode) or jump the cursor to the next matching entry
  /// (quick search mode).
  void typeaheadAppend(String char) {
    final settings = _ref.read(quickSearchSettingsProvider);
    if (settings.mode == QuickSearchMode.off) return;

    final wasActive = _isTypeahead;
    _isTypeahead = true;
    _typeaheadMode = settings.mode;
    _filterQuery += char;

    if (settings.mode == QuickSearchMode.filter) {
      _selectFirstVisibleMatch();
    } else if (settings.mode == QuickSearchMode.select) {
      _selectTypeaheadMatches();
    } else {
      _jumpToMatch(refine: wasActive);
    }
    _scheduleTypeaheadReset(settings);
    notifyListeners();
  }

  /// Remove last character from the type-ahead query.
  void typeaheadBackspace() {
    if (_filterQuery.isEmpty) return;
    _filterQuery = _filterQuery.substring(0, _filterQuery.length - 1);
    if (_filterQuery.isEmpty) {
      clearTypeahead();
      return;
    }
    if (_typeaheadMode == QuickSearchMode.filter) {
      _selectFirstVisibleMatch();
    } else if (_typeaheadMode == QuickSearchMode.select) {
      _selectTypeaheadMatches();
    } else {
      _jumpToMatch(refine: true);
    }
    _scheduleTypeaheadReset(_ref.read(quickSearchSettingsProvider));
    notifyListeners();
  }

  /// Move to the previous/next quick-search match (Up/Down while searching).
  ///
  /// Returns true when the key was consumed.
  bool cycleTypeahead(int direction) {
    if (!_isTypeahead) return false;
    final matches = _typeaheadMatches();
    if (matches.isEmpty) return false;
    final current = cursorItem;
    var index = current == null ? -1 : _indexOfIdentical(matches, current);
    if (index < 0) {
      index = direction > 0 ? 0 : matches.length - 1;
    } else {
      index = (index + direction) % matches.length;
      if (index < 0) index += matches.length;
    }
    _setCursorToItem(matches[index]);
    _scheduleTypeaheadReset(_ref.read(quickSearchSettingsProvider));
    notifyListeners();
    return true;
  }

  /// Clear type-ahead on navigation/escape/timeout.
  void clearTypeahead() {
    _typeaheadResetTimer?.cancel();
    if (!_isTypeahead) return;
    _filterQuery = '';
    _isTypeahead = false;
    notifyListeners();
  }

  void _scheduleTypeaheadReset(QuickSearchSettings settings) {
    _typeaheadResetTimer?.cancel();
    if (settings.resetSeconds <= 0) return;
    _typeaheadResetTimer = Timer(Duration(seconds: settings.resetSeconds), () {
      if (_isTypeahead) clearTypeahead();
    });
  }

  /// Quick filter: keep the cursor on its entry when it still matches,
  /// otherwise move to the first visible match.
  void _selectFirstVisibleMatch() {
    final displayed = filteredFiles;
    if (displayed == null || displayed.isEmpty) return;
    final current = cursorItem;
    if (current != null && _containsIdentical(displayed, current)) {
      _setCursorToItem(current);
      return;
    }
    final first = displayed.firstWhere(
      (f) => f.name != '..',
      orElse: () => displayed.first,
    );
    _setCursorToItem(first);
  }

  /// Quick-select: make every match the selection and put the cursor on the
  /// first one. This is the Total Commander "select" flavor of type-ahead.
  void _selectTypeaheadMatches() {
    final matches = _typeaheadMatches();
    if (matches.isEmpty) return;
    _selection
      ..clear()
      ..addAll(matches);
    _setCursorToItem(matches.first);
  }

  /// Quick search: select the next match after the cursor. When refining an
  /// existing search, keep the current entry if it still matches.
  void _jumpToMatch({required bool refine}) {
    final matches = _typeaheadMatches();
    if (matches.isEmpty) return;
    final current = cursorItem;
    if (refine && current != null && _containsIdentical(matches, current)) {
      return;
    }
    final files = _files;
    if (files == null || files.isEmpty) return;
    final currentIndex = current == null ? -1 : files.indexOf(current);
    for (var step = 1; step <= files.length; step++) {
      final rawIndex = (currentIndex + step) % files.length;
      final candidate = files[rawIndex];
      if (_containsIdentical(matches, candidate)) {
        _setCursorToItem(candidate);
        return;
      }
    }
  }

  void _setCursorToItem(FileItem item) {
    final files = _files;
    if (files == null) return;
    final index = _indexOfIdentical(files, item);
    if (index < 0) return;
    _cursorIndex = index;
    _itemToScrollTo = item;
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
    if (_isTypeahead) {
      _filterQuery = '';
      _isTypeahead = false;
    }
    if (side == PanelSide.local) {
      _localPath = path;
      await _loadLocalFiles();
    } else {
      _remotePath = path;
      if (_ref.read(authProvider).isConnected) {
        await _loadRemoteFiles();
      } else {
        _localPath = path;
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
    _listingGeneration++;
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
  /// Cached archive bytes for web browsing (native reads from disk each time).
  Uint8List? _archiveBytes;

  Future<void> enterArchive(FileItem file) async {
    if (file.path == null && file.name.isEmpty) return;
    final archivePath = file.path ?? p.posix.join(_remotePath, file.name);
    final parentSource = side == PanelSide.local
        ? LocalPanelSource(currentPath)
        : LocalPanelSource(currentPath);
    _log.info('enterArchive: $archivePath');
    _archiveSource =
        const PanelSourceService().enterArchive(archivePath, parentSource);

    // Load the archive through the platform service so macOS security-scoped
    // bookmarks are honoured; the listing is decoded from these bytes.
    _archiveBytes = null;
    try {
      if (side == PanelSide.local) {
        await _localFileService.ensureAccess(archivePath);
        _archiveBytes = await _localFileService.readFile(
          archivePath,
          fileItem: file,
        );
      } else {
        final client = _ref.read(authProvider).client;
        _archiveBytes = await client.downloadFileBytes(archivePath);
      }
    } catch (e) {
      _log.warn('archive open failed', e);
      _archiveSource = null;
      _ref.read(errorProvider).addError('Cannot open archive: $e');
      notifyListeners();
      return;
    }

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
    var parent =
        inner.endsWith('/') ? inner.substring(0, inner.length - 1) : inner;
    final lastSlash = parent.lastIndexOf('/');
    parent = lastSlash > 0 ? parent.substring(0, lastSlash + 1) : '';
    _archiveSource = _archiveSource!.withPath(parent);
    await _loadArchiveFiles();
    notifyListeners();
  }

  /// Exit the archive and restore the parent directory listing.
  void exitArchive() {
    final source = _archiveSource;
    _archiveSource = null;
    _archiveBytes = null;
    if (source != null) {
      if (side == PanelSide.local) {
        _localPath = p.dirname(source.archivePath);
      } else {
        _remotePath = p.posix.dirname(source.archivePath);
      }
    }
    _syncTabPath();
    refresh();
  }

  /// Leave an archive and go to the home directory. Used by the error banner
  /// when a stale archive path cannot be listed.
  Future<void> navigateHome() async {
    if (isInArchive) {
      exitArchive();
      return;
    }
    final path = kIsWeb
        ? '/'
        : (Platform.environment['HOME'] ?? '/');
    await navigateToPath(path);
  }

  Future<void> _loadArchiveFiles() async {
    _listingGeneration++;
    final source = _archiveSource;
    if (source == null) return;
    final bytes = _archiveBytes;
    if (bytes == null) {
      // Fallback for sources without cached bytes (legacy path).
      _files = await const PanelSourceService().listFiles(source);
      _sortFiles();
      return;
    }

    ViewerArchive? archive;
    try {
      archive = await openViewerArchive(bytes, name: source.archivePath);
      final prefix = source.innerPath.isEmpty
          ? ''
          : (source.innerPath.endsWith('/')
              ? source.innerPath
              : '${source.innerPath}/');
      final items = <FileItem>[];
      final folders = <String>{};
      for (final member in archive.members) {
        var name = member.name;
        if (name.startsWith('./')) name = name.substring(2);
        if (prefix.isNotEmpty && !name.startsWith(prefix)) continue;
        if (name == prefix || name == source.innerPath) continue;
        final relative = prefix.isEmpty ? name : name.substring(prefix.length);
        if (relative.isEmpty) continue;
        final slash = relative.indexOf('/');
        if (slash == -1) {
          if (member.isFile) {
            items.add(FileItem(
              name: relative,
              path: '$prefix$relative',
              isFolder: false,
              size: member.size,
            ));
          }
        } else {
          final folder = relative.substring(0, slash);
          if (folders.add(folder)) {
            items.add(FileItem(
              name: folder,
              path: '$prefix$folder/',
              isFolder: true,
            ));
          }
        }
      }
      _files = items;
      _sortFiles();
    } on ArchivePasswordRequiredException {
      _files = [];
      _ref.read(errorProvider).addError('This archive is password-protected.');
    } on ArchiveViewException catch (e) {
      _files = [];
      _ref.read(errorProvider).addError('Failed to read archive: ${e.message}');
    } catch (e) {
      _log.warn('archive listing failed', e);
      _files = [];
      _ref.read(errorProvider).addError('Failed to read archive: $e');
    } finally {
      await archive?.close();
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
    _listingGeneration++;
    if (kIsWeb || side != PanelSide.local) {
      _ref
          .read(errorProvider)
          .addError('Flat view is only available for local directories');
      _isFlatView = false;
      return;
    }
    try {
      final items = await _localFileService.walkFiles(
        currentPath,
        includeHidden: _showHiddenFiles,
        maxItems: 10000,
      );
      final prev = cursorItem;
      _files = items;
      _sortFiles();
      _resetCursor(preserveItem: prev);
      notifyListeners();
    } catch (e) {
      _log.warn('operation failed', e);
      _ref.read(errorProvider).addError('Flat view failed: $e');
      _isFlatView = false;
    }
  }



  String get currentPath {
    if (isInArchive) {
      return '${_archiveSource!.archiveName}:/${_archiveSource!.innerPath}';
    }
    // Check the panel source — if it's local, use the per-panel _localPath
    // (not the shared singleton _localFileService.currentPath).
    final source = _ref.read(panelSourceProvider(side));
    if (source.isLocal) return _localPath;
    if (side == PanelSide.local) return _localPath;
    return _remotePath;
  }

  String _remotePath = '/';

  List<PanelTab> get tabs => _tabs;
  String get activeTabId => _activeTabId;
  PanelTab? get activeTab => _tabs.isEmpty
      ? null
      : _tabs.firstWhere(
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
        return (a.updatedAt ?? DateTime(1970))
            .compareTo(b.updatedAt ?? DateTime(1970));
      case SortBy.extension:
        if (a.isFolder || b.isFolder) return 0;
        final extA =
            a.name.contains('.') ? a.name.split('.').last.toLowerCase() : '';
        final extB =
            b.name.contains('.') ? b.name.split('.').last.toLowerCase() : '';
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
        comparison =
            _secondarySortOrder == SortOrder.ascending ? secondary : -secondary;
      }

      return comparison;
    });
  }

  // --- Selection ---
  bool isSelected(FileItem item) => _selection.contains(item);

  void toggleSelection(FileItem item,
      {bool shiftKey = false, bool ctrlKey = false}) {
    _log.debug(
        'toggleSelection: ${item.name} shift=$shiftKey ctrl=$ctrlKey lastSelected=${_lastSelected?.name} side=$side');
    // Ensure this panel is the active panel (drives F-key context).
    if (_ref.read(activePanelProvider) != side) {
      _ref.read(activePanelProvider.notifier).state = side;
    }
    // Sync cursor to clicked item
    if (_files != null) {
      final idx = _indexOfIdentical(_files!, item);
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
    _log.debug('selectAll (${_files?.length ?? 0} files)');
    if (_files != null) {
      _selection.addAll(_files!.where((f) => f.name != '..'));
      notifyListeners();
    }
  }

  void invertSelection() {
    _log.debug('invertSelection (was ${_selection.length} selected)');
    if (_files == null) return;
    final newSel =
        _files!.where((f) => f.name != '..' && !_selection.contains(f)).toSet();
    _selection
      ..clear()
      ..addAll(newSel);
    _lastSelected = null;
    notifyListeners();
  }

  void clearSelection() {
    _log.debug('clearSelection (was ${_selection.length})');
    _selection.clear();
    _lastSelected = null;
    notifyListeners();
  }

  // --- Cursor (keyboard focus, separate from selection marks) ---

  /// Plain click: move the cursor and clear selection marks without marking
  /// the clicked item (Total Commander / Double Commander behavior).
  /// Ctrl/Shift clicks still select.
  void setCursorOnly(FileItem item) {
    if (_files == null) return;
    final index = _indexOfIdentical(_files!, item);
    if (index < 0) return;
    if (_ref.read(activePanelProvider) != side) {
      _ref.read(activePanelProvider.notifier).state = side;
    }
    _selection.clear();
    _lastSelected = null;
    _cursorIndex = index;
    _itemToScrollTo = item;
    notifyListeners();
  }

  /// Set cursor to a specific item by reference.
  void setCursorToItem(FileItem item) {
    if (_files == null) return;
    final idx = _indexOfIdentical(_files!, item);
    if (idx != -1) {
      _cursorIndex = idx;
      _itemToScrollTo = item;
      notifyListeners();
    }
  }

  /// Move cursor by [delta] rows within the displayed (filtered) list.
  void moveCursor(int delta) {
    final displayed = filteredFiles;
    if (displayed == null || displayed.isEmpty) return;
    final current = cursorItem;
    var position = current == null ? -1 : _indexOfIdentical(displayed, current);
    if (position < 0) {
      position = delta >= 0 ? 0 : displayed.length - 1;
    } else {
      position = (position + delta).clamp(0, displayed.length - 1);
    }
    final item = displayed[position];
    if (current != null && identical(item, current)) return;
    _setCursorToItem(item);
    notifyListeners();
  }

  /// DC-style Space / Insert: toggle selection mark on cursor item, advance down.
  /// When pressed on a folder with no calculated size yet, also triggers async
  /// folder size computation (shown inline in the size column, like DC).
  void spaceSelectAndAdvance() {
    final displayed = filteredFiles;
    if (displayed == null || displayed.isEmpty) return;
    final current = cursorItem;
    var idx = current == null ? 0 : _indexOfIdentical(displayed, current);
    if (idx < 0) idx = 0;
    final item = displayed[idx];
    // ".." cannot be marked
    if (item.name != '..') {
      if (_selection.contains(item)) {
        _selection.remove(item);
      } else {
        _selection.add(item);
      }
      _lastSelected = item;
      // DC: Space on a folder triggers inline size calculation
      if (item.isFolder &&
          item.calculatedSize == null &&
          item.path != null &&
          !kIsWeb) {
        _calculateFolderSizeInBackground(item);
      }
    }
    final next = (idx + 1).clamp(0, displayed.length - 1);
    _setCursorToItem(displayed[next]);
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
    } catch (e) {
      _log.warn('operation failed', e);
    }
    return total;
  }

  /// Shift+Arrow: move cursor AND extend/shrink selection range.
  void shiftMoveCursor(int delta) {
    final displayed = filteredFiles;
    if (displayed == null || displayed.isEmpty) return;
    final current = cursorItem;
    var cur = current == null ? 0 : _indexOfIdentical(displayed, current);
    if (cur < 0) cur = 0;
    final next = (cur + delta).clamp(0, displayed.length - 1);
    if (next == cur) return;
    // Add items swept over to selection
    final start = cur < next ? cur : next;
    final end = cur < next ? next : cur;
    for (var i = start; i <= end; i++) {
      _selection.add(displayed[i]);
    }
    _lastSelected = displayed[next];
    _setCursorToItem(displayed[next]);
    notifyListeners();
  }

  /// Jump cursor to an absolute index in the displayed list.
  /// Used for Home/End/PgUp/PgDn.
  void moveCursorTo(int index) {
    final displayed = filteredFiles;
    if (displayed == null || displayed.isEmpty) return;
    final newIdx = index.clamp(0, displayed.length - 1);
    final item = displayed[newIdx];
    final current = cursorItem;
    if (current != null && identical(item, current)) return;
    _setCursorToItem(item);
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
    final isExtGlob =
        lower.startsWith('*.') && !lower.substring(2).contains('*');
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
    final isExtGlob =
        lower.startsWith('*.') && !lower.substring(2).contains('*');
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
          final rawIdx = _indexOfIdentical(_files!, f);
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
    _log.debug('refresh: side=$side archive=$isInArchive flat=$_isFlatView');
    await _refreshLock.synchronized(() async {
      if (isInArchive) {
        await _loadArchiveFiles();
      } else if (_isFlatView) {
        await _loadFlatFiles();
      } else if (side == PanelSide.local) {
        _localFileService.currentPath = _localPath;
        await _localFileService.refresh();
        await _loadLocalFiles();
      } else if (_ref.read(authProvider).isConnected) {
        await _loadRemoteFiles();
      } else {
        _localFileService.currentPath = _localPath;
        await _localFileService.refresh();
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
    _log.info(
        'navigateUp: currentPath=$currentPath archive=$isInArchive flat=$_isFlatView');
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

  /// Explicitly ask the OS for access to [path] (or the current directory),
  /// persist the security-scoped bookmark, and reload on success.
  Future<bool> grantAccessToPath(String path) async {
    if (side != PanelSide.local && !kIsWeb) return false;
    if (isInArchive) {
      _archiveSource = null;
      _archiveBytes = null;
    }
    var target = path.isEmpty ? currentPath : path;
    if (target.contains(':/')) {
      final archive = target.split(':/').first;
      target = archive.contains('/')
          ? p.dirname(archive)
          : (Platform.environment['HOME'] ?? '/');
    }
    final String? granted = await _localFileService.requestDirectoryAccess(
      initialDirectory: target,
    );
    if (granted == null) return false;
    if (!await _localFileService.hasAccessToPath(target)) {
      _ref.read(errorProvider).addError(
            'Access to "$target" was not granted. Choose the folder itself '
            'or one of its parent folders.',
          );
      return false;
    }
    _localPath = target;
    await _loadLocalFiles();
    _syncTabPath();
    _pushHistory(currentPath);
    notifyListeners();
    return true;
  }

  Future<bool> grantAccessToCurrentPath() =>
      grantAccessToPath(currentPath);

  Future<void> navigateToPath(String path, {FileItem? selectItem}) async {
    _log.info('navigateToPath: $path (side=$side, web=$kIsWeb)');
    // Any explicit path navigation leaves archive mode. Previously the stale
    // ArchivePanelSource kept currentPath virtual and Home/breadcrumbs tried
    // to list "archive.zip:/inner/".
    if (isInArchive) {
      _archiveSource = null;
      _archiveBytes = null;
    }
    if (path.contains(':/')) {
      final archive = path.split(':/').first;
      path = side == PanelSide.local
          ? (archive.contains('/')
              ? p.dirname(archive)
              : (Platform.environment['HOME'] ?? '/'))
          : p.posix.dirname(archive);
    }
    _selection.clear();
    _lastSelected = null;
    if (_isTypeahead) {
      _filterQuery = '';
      _isTypeahead = false;
    }
    if (side == PanelSide.local) {
      if (!kIsWeb && !await _localFileService.hasAccessToPath(path)) {
        final target = path;
        final granted = await _localFileService.requestDirectoryAccess(
          initialDirectory: p.dirname(target),
        );
        if (granted == null) {
          _ref.read(errorProvider).addError(
                'Access to "$target" was not granted.',
              );
          return;
        }
        if (!await _localFileService.hasAccessToPath(target)) {
          _ref.read(errorProvider).addError(
                'Access to "$target" was not granted. '
                'Choose the folder that contains it.',
              );
          return;
        }
        // Stay on the requested path: the user granted a parent folder.
        path = target;
      } else if (kIsWeb && !await _localFileService.hasAccessToPath(path)) {
        return;
      }
      _localPath = path;
      await _loadLocalFiles();
    } else {
      _remotePath = path;
      if (_ref.read(authProvider).isConnected) {
        await _loadRemoteFiles();
      } else {
        _localPath = path;
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
      } catch (e) {
        _log.warn('operation failed', e);
      }
    }

    _syncTabPath();
    _pushHistory(currentPath);
    _ref.read(recentLocationsProvider).add(currentPath, side);
    notifyListeners();
  }

  Future<void> navigateInto(FileItem item) async {
    _log.info(
        'navigateInto: ${item.name} isFolder=${item.isFolder} path=${item.path}');
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
    _log.info('pickLocalDirectory (web=$kIsWeb)');
    final target = _localPath;
    try {
      final dir = await _localFileService.requestDirectoryAccess(
        initialDirectory: target,
      );
      if (dir != null) {
        // If the previously requested folder is now accessible, stay there;
        // otherwise navigate to the folder the user selected.
        if (target != dir && await _localFileService.hasAccessToPath(target)) {
          _localPath = target;
        } else {
          _localPath = dir;
        }
        await _loadLocalFiles();
        notifyListeners();
      }
    } catch (e) {
      _log.warn('operation failed', e);
      _ref.read(errorProvider).addError('Error picking directory: $e');
    }
  }

  /// Update a file item's calculated size (for inline directory size display).
  void updateItemCalculatedSize(FileItem item, int size) {
    if (_files == null) return;
    final idx = _indexOfIdentical(_files!, item);
    if (idx == -1) return;
    final replacement = item.copyWith(calculatedSize: size);
    _fileOrigins[replacement] = _fileOrigins[item];
    _files![idx] = replacement;
    final selected = _selection.map(
      (entry) => identical(entry, item) ? replacement : entry,
    ).toList();
    _selection..clear()..addAll(selected);
    if (identical(_lastSelected, item)) _lastSelected = replacement;
    if (identical(_itemToScrollTo, item)) _itemToScrollTo = replacement;
    notifyListeners();
  }

  // --- File operations (local panel helpers) ---
  Future<void> deleteFiles(List<FileItem> files) async {
    _log.info('deleteFiles: ${files.length} items (web=$kIsWeb, side=$side)');
    final errors = _ref.read(errorProvider);
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final providerName = side == PanelSide.local
        ? 'local'
        : _ref.read(authProvider).client.providerName;
    try {
      for (final file in files) {
        final src = file.path ?? p.posix.join(_remotePath, file.name);
        if (side == PanelSide.local) {
          if (kIsWeb) {
            await _localFileService.deleteEntry(file.path!, file.isFolder);
          } else {
            if (file.isFolder) {
              await Directory(file.path!).delete(recursive: true);
            } else {
              await File(file.path!).delete();
            }
          }
        } else {
          final client = _ref.read(authProvider).client;
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
      _log.warn('operation failed', e);
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
    _log.info('renameFile: ${file.name} → $newName');
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final isLocalSource =
        _ref.read(panelSourceProvider(side)).isLocal || side == PanelSide.local;
    final providerName =
        isLocalSource ? 'local' : _ref.read(authProvider).client.providerName;
    final src = file.path ?? p.posix.join(_remotePath, file.name);
    try {
      String computedNewPath;
      if (isLocalSource && kIsWeb) {
        // Web rename: copy under new name, delete old entry
        final oldPath = file.path!;
        computedNewPath = p.posix.join(p.posix.dirname(oldPath), newName);
        if (!file.isFolder) {
          final bytes =
              await _localFileService.readFile(oldPath, fileItem: file);
          await _localFileService.saveFile(computedNewPath, bytes);
          await _localFileService.deleteEntry(oldPath, false);
        } else {
          // Folder rename on web: recursive copy to new name, delete old
          await _copyDirectoryWeb(oldPath, computedNewPath);
          await _localFileService.deleteEntry(oldPath, true);
        }
      } else if (isLocalSource) {
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
      _log.warn('operation failed', e);
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
    _log.info('createFolder: $name in $currentPath');
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final isLocalSource =
        _ref.read(panelSourceProvider(side)).isLocal || side == PanelSide.local;
    final providerName =
        isLocalSource ? 'local' : _ref.read(authProvider).client.providerName;
    final folderPath = isLocalSource
        ? p.posix.join(currentPath, name)
        : p.posix.join(_remotePath, name);
    try {
      if (isLocalSource && kIsWeb) {
        await _localFileService.createDirectory(folderPath);
      } else if (isLocalSource) {
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
      _log.warn('operation failed', e);
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
    _log.info(
        'moveFiles: ${files.length} items → $targetPath (web=$kIsWeb, side=$side)');
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final isLocalSource =
        _ref.read(panelSourceProvider(side)).isLocal || side == PanelSide.local;
    final providerName =
        isLocalSource ? 'local' : _ref.read(authProvider).client.providerName;
    try {
      for (final file in files) {
        final src = file.path ?? p.posix.join(_remotePath, file.name);
        final String movedToPath;
        if (isLocalSource && kIsWeb) {
          // Web: move = copy bytes to target + delete source
          movedToPath = p.posix.join(targetPath, file.name);
          if (file.path != null && !file.isFolder) {
            final bytes =
                await _localFileService.readFile(file.path!, fileItem: file);
            await _localFileService.saveFile(movedToPath, bytes);
            await _localFileService.deleteEntry(file.path!, false);
          } else if (file.path != null && file.isFolder) {
            await _copyDirectoryWeb(file.path!, movedToPath);
            await _localFileService.deleteEntry(file.path!, true);
          }
        } else if (isLocalSource) {
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
      _log.warn('operation failed', e);
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
    _log.info(
        'copyFiles: ${files.length} items → $targetPath (web=$kIsWeb, side=$side)');
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final isLocalSource =
        _ref.read(panelSourceProvider(side)).isLocal || side == PanelSide.local;
    final providerName =
        isLocalSource ? 'local' : _ref.read(authProvider).client.providerName;
    try {
      for (final file in files) {
        final src = file.path ?? p.posix.join(_remotePath, file.name);
        // copyPath is the new file that was created — used for undo (delete the copy)
        final String copyPath;
        if (isLocalSource && kIsWeb) {
          // Web: copy within virtual filesystem
          copyPath = p.posix.join(targetPath, file.name);
          if (file.path != null) {
            final bytes =
                await _localFileService.readFile(file.path!, fileItem: file);
            await _localFileService.saveFile(copyPath, bytes);
          }
        } else if (isLocalSource) {
          copyPath = p.join(targetPath, file.name);
          if (file.isFolder) {
            await _copyDirectory(file.path!, copyPath);
          } else {
            await File(file.path!).copy(copyPath);
          }
        } else {
          if (kIsWeb)
            throw UnsupportedError('Remote copy not supported on web');
          final client = _ref.read(authProvider).client;
          final sourcePath = file.path ?? p.posix.join(_remotePath, file.name);
          copyPath = p.posix.join(targetPath, file.name);
          if (client.capabilities.serverSideCopy) {
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
          metadata: {
            'name': file.name,
            'sourceDir': p.dirname(src),
            'targetDir': targetPath
          },
        );
      }
      await refresh();
    } catch (e) {
      _log.warn('operation failed', e);
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
    if (kIsWeb) {
      await _copyDirectoryWeb(source, target);
      return;
    }
    await Directory(target).create(recursive: true);
    final entities = await Directory(source).list().toList();
    for (final entity in entities) {
      if (entity is File) {
        await entity.copy(p.join(target, p.basename(entity.path)));
      } else if (entity is Directory) {
        await _copyDirectory(
            entity.path, p.join(target, p.basename(entity.path)));
      }
    }
  }

  /// Recursively copy a directory on web using the virtual filesystem.
  Future<void> _copyDirectoryWeb(String source, String target) async {
    await _localFileService.createDirectory(target);
    final entities = await _localFileService.listDirectory(source);
    if (entities == null) return;
    for (final entity in entities) {
      final name = p.posix.basename(entity.path);
      if (entity is Directory) {
        await _copyDirectoryWeb(entity.path, p.posix.join(target, name));
      } else {
        final bytes = await _localFileService.readFile(entity.path);
        await _localFileService.saveFile(p.posix.join(target, name), bytes);
      }
    }
  }

  // --- Tabs ---
  String _nextTabId() => 'tab_${_tabIdCounter++}';

  String get _tabStorageKey => 'panel_tabs_${side.name}';

  void _initFirstTab() {
    final id = _nextTabId();
    final path = side == PanelSide.local ? _localPath : _remotePath;
    _tabs.add(PanelTab(id: id, path: path));
    _activeTabId = id;
  }

  /// Restore tabs from SharedPreferences. Falls back to single default tab.
  Future<void> _restoreTabs() async {
    // Skip persistence in test environments to avoid pending timer assertions
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
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
            var path = (item['path'] as String?) ?? '/';
            if (path.contains(':/')) {
              // Old tab saved while browsing an archive: fall back to the
              // real parent path (or home) instead of a virtual path.
              final archive = path.split(':/').first;
              path = archive.contains('/')
                  ? archive.substring(0, archive.lastIndexOf('/'))
                  : (Platform.environment['HOME'] ?? '/');
              if (path.isEmpty) path = '/';
            }
            _tabs.add(PanelTab(
              id: id,
              path: path,
              isPinned: item['pinned'] == true,
            ));
          }
          final savedActiveIdx = prefs.getInt('${_tabStorageKey}_active') ?? 0;
          _activeTabId = _tabs[savedActiveIdx.clamp(0, _tabs.length - 1)].id;

          // Sync local path to restored tab
          if (side == PanelSide.local) {
            final tab = activeTab;
            if (tab != null) _localPath = tab.path;
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
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list =
          _tabs.map((t) => {'path': t.path, 'pinned': t.isPinned}).toList();
      await prefs.setString(_tabStorageKey, json.encode(list));
      await prefs.setInt(
          '${_tabStorageKey}_active',
          _tabs
              .indexWhere((t) => t.id == _activeTabId)
              .clamp(0, _tabs.length - 1));
    } catch (e) {
      _log.warn('Tab save failed', e);
    }
  }

  void addTab({String? path}) {
    _log.debug('addTab: path=${path ?? currentPath}');
    final id = _nextTabId();
    _tabs.add(PanelTab(id: id, path: path ?? currentPath));
    _activeTabId = id;
    notifyListeners();
    _saveTabs();
  }

  void closeTab(String tabId) {
    _log.debug('closeTab: $tabId');
    if (_tabs.length <= 1) return;
    final tab =
        _tabs.firstWhere((t) => t.id == tabId, orElse: () => _tabs.first);
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
    _log.debug('selectTab: $tabId');
    _activeTabId = tabId;
    final tab = activeTab;
    if (tab != null) {
      if (tab.path.contains(':/')) return;
      if (side == PanelSide.local) {
        _localPath = tab.path;
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
    final tab =
        _tabs.firstWhere((t) => t.id == tabId, orElse: () => _tabs.first);
    tab.isPinned = !tab.isPinned;
    notifyListeners();
    _saveTabs();
  }

  void renameTab(String tabId, String newLabel) {
    final tab =
        _tabs.firstWhere((t) => t.id == tabId, orElse: () => _tabs.first);
    tab.label = newLabel;
    notifyListeners();
    _saveTabs();
  }

  void _syncTabPath() {
    final tab = activeTab;
    if (tab != null) {
      // Never persist archive virtual paths (e.g. "file.zip:/"): they are not
      // real directories and would break restart/restore.
      var titlePath = side == PanelSide.local ? _localPath : _remotePath;
      if (titlePath.contains(':/')) {
        final archive = titlePath.split(':/').first;
        titlePath = side == PanelSide.local
            ? (archive.contains('/')
                ? p.dirname(archive)
                : (Platform.environment['HOME'] ?? '/'))
            : p.posix.dirname(archive);
      }
      tab.path = titlePath;
      tab.updateLabel();
    }
    _saveTabs();
  }

  // --- Internal loading ---
  Future<void> _initializeLocalPath() async {
    try {
      await _localFileService.getInitialPath();
      if (_isDisposed) return;
      if (!kIsWeb &&
          Platform.isMacOS &&
          _localFileService.grantedBasePath == null) {
        _ref.read(errorProvider).addError(
              'Please select a base directory to grant access (e.g., your home folder)',
            );
        final grantedPath = await _localFileService.requestDirectoryAccess(
          initialDirectory: await _localFileService.getSafeFallbackDirectory(),
        );
        if (_isDisposed) return;
        if (grantedPath != null) {
          _localPath = grantedPath;
          _ref.read(errorProvider).clearErrors();
        } else {
          _localPath = await _localFileService.getSafeFallbackDirectory();
          _ref.read(errorProvider).clearErrors();
          _ref
              .read(errorProvider)
              .addError('Access cancelled. Using fallback directory.');
        }
      }
      await _loadLocalFiles();
      if (_isDisposed) return;
      _pushHistory(currentPath);
      notifyListeners();
    } catch (e) {
      if (_isDisposed) return;
      _log.warn('operation failed', e);
      _localPath = await _localFileService.getSafeFallbackDirectory();
      if (_isDisposed) return;
      _ref.read(errorProvider).addError(e.toString());
      notifyListeners();
    }
  }

  Future<void> _loadLocalFiles() async {
    final generation = ++_listingGeneration;
    // This loader must never receive an archive's virtual path. If an archive
    // failed to open or a stale tab restored one, leave archive mode first.
    if (_archiveSource != null) {
      final archivePath = _archiveSource!.archivePath;
      _archiveSource = null;
      _archiveBytes = null;
      if (side == PanelSide.local && archivePath.contains('/')) {
        _localPath = p.dirname(archivePath);
      }
    }
    if (!kIsWeb && _localPath.contains(':/')) {
      _localPath = await _localFileService.getSafeFallbackDirectory();
    }
    if (_isDisposed || generation != _listingGeneration) return;
    final listingPath = currentPath;
    final origin = PanelFileOrigin._(
      LocalPanelSource(listingPath),
      () => !_isDisposed,
    );
    _log.debug('_loadLocalFiles: $currentPath (web=$kIsWeb)');
    _isLoading = true;
    notifyListeners();

    final dirCache = _ref.read(directoryCacheProvider);
    final cacheKey = DirectoryCacheService.key('local', listingPath);

    // Show the last listing for this folder immediately. It is replaced by
    // the fresh listing below, but makes revisiting large folders instant.
    // Do not stamp origins here: only the fresh directory listing may
    // authorize editing.
    if (!_showingSearchResults) {
      final cached = dirCache.get(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        final prev = cursorItem;
        _files = List.of(cached);
        _sortFiles();
        _resetCursor(preserveItem: prev);
        notifyListeners();
      }
    }

    try {
      final entities = await _localFileService.listDirectory(listingPath);
      if (_isDisposed || generation != _listingGeneration) return;
      if (entities == null) {
        _files = [];
        _isLoading = false;
        if (!kIsWeb) {
          _ref
              .read(errorProvider)
              .addError('Local file access is not supported on this platform.');
        }
        _log.warn('listDirectory returned null for "$listingPath"');
        notifyListeners();
        return;
      }
      _log.debug(
        'listDirectory("$listingPath") returned ${entities.length} entities',
      );

      // Reuse metadata from the cached listing while the fresh stat pass runs.
      final cachedByPath = <String, FileItem>{};
      final cached = dirCache.get(cacheKey);
      if (cached != null) {
        for (final item in cached) {
          final path = item.path;
          if (path != null) cachedByPath[path] = item;
        }
      }

      // Prepend ".." parent-dir entry unless we're at root.
      final items = <FileItem>[];
      final parentPath = p.dirname(listingPath);
      if (parentPath != listingPath && listingPath != '/') {
        items.add(FileItem(name: '..', path: parentPath, isFolder: true));
      }

      // On web, stat is synchronous — no need for progressive loading.
      if (kIsWeb) {
        for (final entity in entities) {
          try {
            final name = p.basename(entity.path);
            if (!_showHiddenFiles && name.startsWith('.')) continue;
            final isFolder = entity is Directory;
            int size = 0;
            DateTime updated = DateTime.now();
            if (!isFolder) {
              final meta = _localFileService.getWebMetadata(entity.path);
              size = meta['size'] ?? 0;
              updated = meta['modified'] ?? DateTime.now();
            }
            items.add(
              FileItem(
                name: name,
                path: entity.path,
                isFolder: isFolder,
                size: size,
                updatedAt: updated,
              ),
            );
          } catch (e) {
            _log.warn('operation failed', e);
            continue;
          }
        }
        final prev = cursorItem;
        _files = items;
        _recordOrigins(items, origin);
        _sortFiles();
        _resetCursor(preserveItem: prev);
        _isLoading = false;
        _ref.read(errorProvider).clearErrors();
        dirCache.put(cacheKey, _files!);
        notifyListeners();
        return;
      }

      // Native: show names immediately, then stat in batches for size/date.
      // Reuse any cached metadata for the same paths so the first paint already
      // has useful sizes/dates even before the stat pass catches up.
      for (final entity in entities) {
        try {
          final name = p.basename(entity.path);
          if (!_showHiddenFiles && name.startsWith('.')) continue;
          final cachedItem = cachedByPath[entity.path];
          if (cachedItem != null) {
            items.add(cachedItem);
          } else {
            // Guess folder vs file from entity type (no stat needed).
            final isFolder = entity is Directory;
            items.add(
              FileItem(name: name, path: entity.path, isFolder: isFolder),
            );
          }
        } catch (e) {
          _log.warn('operation failed', e);
          continue;
        }
      }
      // Show items immediately (possibly with cached size/date).
      _files = items;
      _recordOrigins(items, origin);
      _sortFiles();
      _isLoading = true; // still loading metadata
      _ref.read(errorProvider).clearErrors();
      notifyListeners();

      // Second pass: stat in batches to fill in size, date, symlink info.
      // Only name/extension order is stable while metadata is filled in. For
      // size/date sorts, defer the (expensive) re-sort to the very end.
      final bool metadataSort =
          _sortBy == SortBy.size || _sortBy == SortBy.date;
      const batchSize = 256;
      for (
        var batchStart = 0;
        batchStart < items.length;
        batchStart += batchSize
      ) {
        final end = (batchStart + batchSize).clamp(0, items.length);
        final indices = List.generate(end - batchStart, (j) => batchStart + j);
        await Future.wait(
          indices.map((idx) async {
            final item = items[idx];
            if (item.name == '..') return;
            try {
              final stat = await FileStat.stat(item.path!);
              final linkType = await FileSystemEntity.type(
                item.path!,
                followLinks: false,
              );
              final isLink = linkType == FileSystemEntityType.link;
              String? linkTarget;
              if (isLink) {
                try {
                  linkTarget = await Link(item.path!).target();
                } catch (_) {}
              }
              final isFolder = stat.type == FileSystemEntityType.directory;
              items[idx] = FileItem(
                name: item.name,
                path: item.path,
                isFolder: isFolder,
                size: isFolder ? null : stat.size,
                updatedAt: stat.modified,
                isSymlink: isLink ? true : null,
                symlinkTarget: linkTarget,
              );
            } catch (e) {
              _log.warn('operation failed', e);
            }
          }),
        );
        if (_isDisposed || generation != _listingGeneration) return;
        // _files is the same mutable list, so notifyListeners() is enough for
        // the ListView.builder to refresh visible rows. Re-stamp origins
        // because metadata replaced the FileItem instances.
        _recordOrigins(items, origin);
        notifyListeners();
      }

      if (metadataSort) {
        final prev = cursorItem;
        _sortFiles();
        _resetCursor(preserveItem: prev);
      }
      _isLoading = false;
      if (_isDisposed || generation != _listingGeneration) return;
      dirCache.put(cacheKey, _files!);
      // Fire-and-forget free space fetch (result stored in _freeBytes, shown in status bar)
      if (side == PanelSide.local) _updateFreeSpace(listingPath);
      notifyListeners();
    } catch (e) {
      if (_isDisposed || generation != _listingGeneration) return;
      _log.warn('operation failed', e);
      _isLoading = false;
      if (!kIsWeb &&
          (e is PathAccessException ||
              e.toString().contains('Operation not permitted'))) {
        _files = [];
        _ref
            .read(errorProvider)
            .addError(
              'Permission denied. Use the Browse button to grant access.',
            );
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
    if (kIsWeb) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    // `df` is a Unix utility — skip on Windows to avoid a crash.
    if (Platform.isWindows) return;
    // Debounce: skip if same path was checked within the last 5 seconds.
    final now = DateTime.now();
    if (_lastFreeSpacePath == path &&
        _lastFreeSpaceTime != null &&
        now.difference(_lastFreeSpaceTime!).inSeconds < 5) {
      return;
    }
    _lastFreeSpacePath = path;
    _lastFreeSpaceTime = now;
    Process.run('df', ['-k', path]).then((result) {
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length >= 2) {
        final parts = lines.last.trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final kb = int.tryParse(parts[3]);
          if (kb != null) {
            _freeBytes = kb * 1024;
            notifyListeners();
          }
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

    final generation = ++_listingGeneration;
    final auth = _ref.read(authProvider);
    // This loader currently uses the primary auth adapter, even if the
    // dropdown points elsewhere. Stamp the actual request, never the label.
    final client = auth.client;
    final providerName = auth.providerName;
    final listingPath = _remotePath;
    final origin = _remoteOrigin(client, providerName, listingPath);

    _isLoading = true;
    notifyListeners();
    try {
      if (!client.isAuthenticated && !auth.isConnected) {
        _files = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Show cached listing immediately for smooth UX.
      final dirCache = _ref.read(directoryCacheProvider);
      final cacheKey = DirectoryCacheService.key(
        'remote:$providerName',
        listingPath,
      );
      final cached = dirCache.get(cacheKey);
      if (cached != null && _files == null) {
        _files = List.of(cached);
        // Cached objects retain an origin only if this panel previously saw
        // that exact object under the same live account. Cache entries are
        // not account-scoped, so unknown entries stay uneditable until fresh.
        for (final file in _files!) {
          final previous = _fileOrigins[file];
          final source = previous?.source;
          if (previous == null || !previous.isCurrent ||
              source is! RemotePanelSource ||
              !identical(source.client, client) || source.path != listingPath) {
            _fileOrigins[file] = null;
          }
        }
        _sortFiles();
        notifyListeners();
      }

      // Fetch fresh listing from remote.
      final result = await client.listPath(listingPath);
      if (_isDisposed || generation != _listingGeneration) return;
      if (!origin.isCurrent) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final folders = (result['folders'] as List<dynamic>?)?.map((item) {
            final map = item as Map<String, dynamic>;
            DateTime? folderDate;
            final rawDate = map['modificationTime'] ??
                map['lastModified'] ??
                map['timestamp'];
            if (rawDate != null) {
              try {
                if (rawDate is int) {
                  folderDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
                } else {
                  folderDate = DateTime.parse(rawDate.toString());
                }
              } catch (e) {
                _log.warn('operation failed', e);
              }
            }
            final meta = Map<String, dynamic>.from(map)
              ..removeWhere((k, _) => const {
                    'name',
                    'uuid',
                    'modificationTime',
                    'lastModified',
                    'timestamp'
                  }.contains(k));
            return FileItem(
                name: map['name'] ?? 'Unknown',
                isFolder: true,
                uuid: map['uuid'],
                updatedAt: folderDate,
                metadata: meta.isNotEmpty ? meta : null);
          }).toList() ??
          [];

      final files = (result['files'] as List<dynamic>?)?.map((item) {
            final map = item as Map<String, dynamic>;
            final fileName = map['name'] ?? 'Unknown';
            final rawType = map['fileType'] ?? map['type'] ?? '';
            final fileType = rawType.toString().toLowerCase();
            String fullName = fileName;
            if (fileType.isNotEmpty &&
                fileType != 'file' &&
                !fileName.toLowerCase().endsWith('.$fileType')) {
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
              } catch (e) {
                _log.warn('operation failed', e);
              }
            }
            final meta = Map<String, dynamic>.from(map)
              ..removeWhere((k, _) => const {
                    'name',
                    'uuid',
                    'size',
                    'modificationTime',
                    'lastModified',
                    'fileType',
                    'type',
                    'timestamp'
                  }.contains(k));
            return FileItem(
                name: fullName,
                isFolder: false,
                size: map['size'] as int?,
                uuid: map['uuid'],
                updatedAt: fileDate,
                metadata: meta.isNotEmpty ? meta : null);
          }).toList() ??
          [];

      // Prepend ".." for cloud paths that aren't root
      final allItems = [...folders, ...files];
      if (listingPath != '/' && listingPath.isNotEmpty) {
        final parentRemote = p.posix.dirname(listingPath);
        allItems.insert(
            0,
            FileItem(
              name: '..',
              path: parentRemote.isEmpty ? '/' : parentRemote,
              isFolder: true,
            ));
      }
      final prev = cursorItem;
      _files = allItems;
      _recordOrigins(allItems, origin);
      _sortFiles();
      _resetCursor(preserveItem: prev);
      _ref.read(errorProvider).clearErrors();

      // Update directory cache with fresh listing.
      dirCache.put(cacheKey, _files!);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      if (_isDisposed || generation != _listingGeneration) return;
      _log.error('Refresh error', e);
      _isLoading = false;
      // On error, keep cached files if available instead of clearing.
      if (_files == null || _files!.isEmpty) {
        _files = [];
      }
      _ref.read(errorProvider).addError(e.toString());
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _typeaheadResetTimer?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }
}

final panelProvider =
    ChangeNotifierProvider.family<PanelNotifier, PanelSide>((ref, side) {
  return PanelNotifier(ref, side);
});
