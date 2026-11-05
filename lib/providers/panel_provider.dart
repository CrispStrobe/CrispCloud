// lib/providers/panel_provider.dart
//
// Per-panel state: file listing, selection, sort, tabs, navigation.
// Used as a family provider keyed by PanelSide.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show FocusNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/panel_tab.dart';
import '../models/sort.dart';
import '../models/storage_reference.dart';
import '../services/captured_file_target.dart';
import '../services/storage_identity.dart';
import '../services/storage_trash.dart';
import '../services/native_file_operations.dart';
import '../services/native_file_primitives.dart';
import '../services/archive_service.dart';
import '../services/archive_viewer_service.dart';
import '../services/audit_service.dart';
import '../services/cloud_storage_interface.dart'
    show CloudStorageClient, CloudStorageClientCapabilities;
import '../services/directory_cache_service.dart';
import '../services/file_operation_backend.dart';
import '../services/file_selection_pattern.dart';
import '../services/file_list_paths.dart';
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
import 'native_file_operations_provider.dart';

// SortBy and SortOrder are defined in models/sort.dart
export '../models/sort.dart';

/// The storage source that actually produced a listed file, captured before
/// the listing request. It is independent of the pane's label or dropdown.
class PanelFileOrigin {
  PanelFileOrigin._(this.source, this._isCurrent)
    : storageReference = storageReferenceForSource(source);

  final PanelSource source;
  final bool Function() _isCurrent;

  /// Remains false after the captured account disconnects or changes.
  bool get isCurrent => _isCurrent();

  final StorageReference storageReference;
  String get storageId => storageReference.id;
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
  PanelFileOrigin? _currentDirectoryOrigin;
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
  late final FocusNode listFocusNode;
  bool _isDisposed = false;

  /// A virtual list retains original item paths across refresh and operations.
  /// Explicit navigation or the Return to folder command leaves this view.
  bool _showingSearchResults = false;
  bool get showingSearchResults => _showingSearchResults;
  String _fileListTitle = 'Search results';
  String get fileListTitle => _fileListTitle;
  PanelFileOrigin? _fileListOrigin;
  final Map<String, _FileListSnapshot> _fileListTabs = {};
  final Map<String, Map<(StorageReference, String), _SelectionMemoryEntry>>
      _selectionMemories = {};

  bool get canOperateOnFileList =>
      !_showingSearchResults || (_fileListOrigin?.isCurrent ?? false);

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
    listFocusNode = FocusNode(debugLabel: 'panel-${side.name}');
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
      _leaveFileList();
      _listingGeneration++;
      _log.info(
        'Source switched: ${prev?.displayName} → ${next.displayName} (path=${next.currentPath})',
      );
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
    if (_isLoading ||
        _showingSearchResults ||
        _verifiedListingGeneration != _listingGeneration ||
        selectedSource.isArchive ||
        selectedSource.isContainer ||
        isInArchive ||
        _isFlatView ||
        !(_files?.any((item) => identical(item, file)) ?? false)) {
      return null;
    }
    final origin = _fileOrigins[file];
    return origin != null && origin.isCurrent ? origin : null;
  }

  void _recordOrigins(Iterable<FileItem> files, PanelFileOrigin origin) {
    _currentDirectoryOrigin = origin;
    final listed = files.toList(growable: false);
    // The preview uses selection.first; keeping the old object here would
    // leave it permanently outside the exact-identity origin gate after a
    // refresh or the native metadata pass. Resolve references while their
    // old origin is still available, before stamping the new publication.
    FileItem? replacement(FileItem? previous) {
      if (previous == null) return null;
      final before = _fileOrigins[previous];
      if (before == null ||
          !before.isCurrent ||
          !origin.isCurrent ||
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
    _selection
      ..clear()
      ..addAll(selected);
    _lastSelected = lastSelected;
    _itemToScrollTo = scrollTarget;
  }

  static bool _sameFileSource(PanelSource before, PanelSource after) {
    if (before is LocalPanelSource && after is LocalPanelSource) {
      return before.path == after.path;
    }
    if (before is RemotePanelSource && after is RemotePanelSource) {
      return identical(before.client, after.client) &&
          before.providerName == after.providerName &&
          before.path == after.path;
    }
    return false;
  }

  PanelFileOrigin _remoteOrigin(
    CloudStorageClient client,
    String providerName,
    String path,
  ) {
    final generation = _accountGeneration;
    final email = _ref.read(authProvider).userEmail;
    final userId = client.userId;
    final bucketId = client.bucketId;
    return PanelFileOrigin._(
      RemotePanelSource(providerName: providerName, client: client, path: path),
      () {
        if (_isDisposed || generation != _accountGeneration) return false;
        final auth = _ref.read(authProvider);
        return auth.isConnected &&
            identical(auth.client, client) &&
            auth.userEmail == email &&
            client.isAuthenticated &&
            client.userId == userId &&
            client.bucketId == bucketId;
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
    await navigateToPath(path, recordHistory: false);
  }

  // --- Search results and Commander file lists ---

  /// Capture the actual, verified storage endpoint behind this panel.
  /// In particular, a legacy remote listing may have a local dropdown label;
  /// that label must never redirect an operation to another filesystem.
  PanelFileOrigin captureCurrentOrigin() {
    if (_isDisposed || _isLoading || isInArchive) {
      throw StateError(
        'Wait for a real filesystem listing before starting an operation.',
      );
    }
    final origin = _showingSearchResults
        ? _fileListOrigin
        : _currentDirectoryOrigin;
    if (origin == null ||
        !origin.isCurrent ||
        _verifiedListingGeneration != _listingGeneration) {
      throw StateError(
        'The source is no longer current. Refresh the folder or run the search again.',
      );
    }
    return origin;
  }

  /// Capture the account before an asynchronous provider search begins.
  /// Only SearchNotifier uses this for provider-returned result objects.
  PanelFileOrigin captureRemoteSearchOrigin() {
    final auth = _ref.read(authProvider);
    if (!auth.isConnected || !auth.client.isAuthenticated) {
      throw StateError('Connect to a cloud account before searching.');
    }
    return _remoteOrigin(auth.client, auth.providerName, _remotePath);
  }

  /// The OS clipboard supplies paths; callers stat every item before planning.
  PanelFileOrigin captureLocalClipboardOrigin(String parent) {
    if (_isDisposed || kIsWeb || !p.isAbsolute(parent)) {
      throw StateError('The local file clipboard is unavailable.');
    }
    return PanelFileOrigin._(LocalPanelSource(parent), () => !_isDisposed);
  }

  /// Origins for file operations are deliberately separate from editor origins.
  /// A result can be copied/moved/renamed at its captured full path while
  /// [originForFile] continues to reject virtual lists for editor writeback.
  PanelFileOrigin? originForOperation(FileItem file) {
    if (_isDisposed ||
        _isLoading ||
        isInArchive ||
        _verifiedListingGeneration != _listingGeneration ||
        file.name == '..' ||
        file.name == '.' ||
        !(_files?.any((candidate) => identical(candidate, file)) ?? false)) {
      return null;
    }
    final origin = _fileOrigins[file];
    if (origin == null || !origin.isCurrent) return null;
    if (_showingSearchResults && (file.path == null || file.path!.isEmpty)) {
      return null;
    }
    return origin;
  }

  /// Capture once when an editor opens, including verified collection rows.
  /// Later tab/account changes never choose a new save destination.
  CapturedFileTarget captureFileTarget(
    FileItem file, {
    int maxBytes = 64 * 1024 * 1024,
  }) {
    final origin = originForOperation(file);
    if (origin == null || file.isFolder) {
      throw StateError(
        'Refresh or reopen the original file before editing. Its storage could not be verified.',
      );
    }
    final source = origin.source;
    final path =
        file.path ??
        (source.isLocal && !kIsWeb
            ? p.join(source.currentPath, file.name)
            : p.posix.join(source.currentPath, file.name));
    final original = file.copyWith(path: path);
    final reference = FileReference(
      storage: origin.storageReference,
      path: path,
      objectId: file.uuid,
      version:
          (file.metadata?['etag'] ??
                  file.metadata?['versionId'] ??
                  file.metadata?['revision'])
              ?.toString(),
    );
    if (source is LocalPanelSource) {
      return CapturedFileTarget.local(
        reference: reference,
        service: _localFileService,
        file: original,
        isCurrent: () => origin.isCurrent,
        maxBytes: maxBytes,
      );
    }
    if (source is RemotePanelSource) {
      return CapturedFileTarget.remote(
        reference: reference,
        client: source.client,
        cache: _ref.read(fileCacheProvider),
        file: original,
        isCurrent: () => origin.isCurrent,
        maxBytes: maxBytes,
      );
    }
    throw UnsupportedError('Extract this file before editing it.');
  }

  /// Pin all selected items to one storage/account snapshot before mutation.
  /// The returned guard stays false after account disconnection/reconnection.
  PanelFileOrigin captureOperationOrigin(List<FileItem> files) {
    if (files.isEmpty) throw StateError('Select at least one file or folder.');
    if (_showingSearchResults && !canOperateOnFileList) {
      throw StateError(
        'The file list source changed. Run the search or import again.',
      );
    }
    final origins = <PanelFileOrigin>[];
    for (final file in files) {
      final origin = originForOperation(file);
      if (origin == null) {
        throw StateError(
          'The source of "${file.name}" is not verified. Refresh its folder or run the search again.',
        );
      }
      if (origins.isNotEmpty &&
          !_sameStorage(origins.first.source, origin.source)) {
        throw StateError(
          'A single operation cannot mix files from different storage accounts.',
        );
      }
      origins.add(origin);
    }
    final listOrigin = _showingSearchResults ? _fileListOrigin : null;
    if (listOrigin != null &&
        !_sameStorage(listOrigin.source, origins.first.source)) {
      throw StateError(
        'These results belong to a different storage source. Open separate lists for each source.',
      );
    }
    final source = listOrigin?.source ?? origins.first.source;
    return PanelFileOrigin._(
      source,
      () =>
          (listOrigin == null || listOrigin.isCurrent) &&
          origins.every((origin) => origin.isCurrent),
    );
  }

  static bool _sameStorage(PanelSource a, PanelSource b) =>
      (a is LocalPanelSource && b is LocalPanelSource) ||
      (a is RemotePanelSource &&
          b is RemotePanelSource &&
          identical(a.client, b.client) &&
          a.providerName == b.providerName);

  static PanelFileOrigin _originAt(PanelFileOrigin origin, String path) =>
      PanelFileOrigin._(origin.source.withPath(path), () => origin.isCurrent);

  /// Feed a search/selection to a persistent, actionable panel list.
  /// Externally fetched results must carry an origin captured before the query.
  /// Passing arbitrary objects without a verified origin displays them, but
  /// never grants permission to mutate them.
  void showSearchResults(
    List<FileItem> results, {
    PanelFileOrigin? origin,
    PanelFileOrigin? Function(FileItem)? originForFile,
    String title = 'Search results',
  }) {
    final items = <FileItem>[];
    final seen = <String>{};
    PanelFileOrigin? commonOrigin = origin;
    for (final result in results) {
      if (result.name == '..' || result.name == '.') continue;
      final verified =
          originForFile?.call(result) ?? origin ?? originForOperation(result);
      if (verified != null &&
          commonOrigin != null &&
          (!_sameStorage(commonOrigin.source, verified.source) ||
              commonOrigin.storageReference != verified.storageReference)) {
        throw StateError(
          'A file list cannot mix storage accounts. Open a separate list for each source.',
        );
      }
      var path = result.path;
      if ((path == null || path.isEmpty) &&
          verified != null &&
          _files?.any((item) => identical(item, result)) == true) {
        final paths = verified.source.isRemote ? p.posix : p.context;
        path = paths.join(verified.source.currentPath, result.name);
      }
      final paths = verified?.source.isRemote == true ? p.posix : p.context;
      final normalized = path == null || path.isEmpty
          ? null
          : paths.normalize(path);
      final key = normalized == null
          ? 'id:${result.uuid ?? identityHashCode(result)}'
          : 'path:$normalized';
      if (!seen.add(key)) continue;
      final item = result.copyWith(
        name: normalized == null
            ? paths.basename(result.name)
            : paths.basename(normalized),
        path: normalized,
      );
      if (verified != null &&
          verified.isCurrent &&
          normalized != null &&
          paths.isAbsolute(normalized)) {
        _fileOrigins[item] = _originAt(verified, paths.dirname(normalized));
        commonOrigin ??= verified;
      }
      items.add(item);
    }
    _log.info('Showing ${items.length} items in $title');
    _showingSearchResults = true;
    _fileListTitle = title;
    _fileListOrigin = commonOrigin;
    _listingGeneration++;
    _verifiedListingGeneration = _listingGeneration;
    _isLoading = false;
    _isFlatView = false;
    _archiveSource = null;
    _archiveOrigin = null;
    _archiveBytes = null;
    _selection.clear();
    _lastSelected = null;
    _itemToScrollTo = null;
    _filterQuery = '';
    _isTypeahead = false;
    _typeaheadResetTimer?.cancel();
    _files = items;
    _sortFiles();
    _cursorIndex = items.isEmpty ? -1 : 0;
    _rememberFileListTab();
    notifyListeners();
  }

  void _rememberFileListTab() {
    if (!_showingSearchResults || _activeTabId.isEmpty) return;
    _fileListTabs[_activeTabId] = _FileListSnapshot(
      files: List.of(_files ?? []),
      title: _fileListTitle,
      origin: _fileListOrigin,
      selection: Set.of(_selection),
      cursor: cursorItem,
    );
  }

  void _leaveFileList({bool forget = true}) {
    if (forget) _fileListTabs.remove(_activeTabId);
    if (!_showingSearchResults) return;
    _showingSearchResults = false;
    _fileListOrigin = null;
    _selection.clear();
    _lastSelected = null;
    _itemToScrollTo = null;
    _listingGeneration++;
  }

  /// Return to the directory from which this list was opened.
  Future<void> clearSearchResults() async {
    if (!_showingSearchResults) return;
    final origin = _fileListOrigin;
    _leaveFileList();
    if (origin != null && origin.isCurrent) {
      await navigateToPath(
        origin.source.currentPath,
        origin: origin,
        recordHistory: false,
      );
    } else {
      await refresh();
    }
  }

  /// Remove rows only. No filesystem or provider delete call is made.
  void removeFromFileList(Iterable<FileItem> items) {
    if (!_showingSearchResults) return;
    final removed = Set<FileItem>.identity()..addAll(items);
    final cursor = cursorItem;
    _files?.removeWhere(removed.contains);
    _selection.removeWhere(removed.contains);
    if (removed.contains(_lastSelected)) _lastSelected = null;
    if (removed.contains(_itemToScrollTo)) _itemToScrollTo = null;
    _resetCursor(preserveItem: cursor);
    _rememberFileListTab();
    notifyListeners();
  }

  /// Update rows after successful operations; null means moved/deleted away.
  /// Keys are original full paths, never basenames shared by other folders.
  /// Async callers pass their captured [origin] so results cannot affect a
  /// same-path row in another storage account after the pane changes sources.
  /// Matching saved list tabs are updated even while another tab is active.
  void applyFileListChanges(
    Map<String, FileItem?> replacements, {
    PanelFileOrigin? origin,
  }) {
    if (_isDisposed ||
        replacements.isEmpty ||
        (origin != null && !origin.isCurrent)) {
      return;
    }
    bool matchesOrigin(PanelFileOrigin? candidate) =>
        origin == null ||
        (candidate != null &&
            candidate.isCurrent &&
            _sameStorage(origin.source, candidate.source));

    FileItem? replacementFor(FileItem? old) {
      if (old == null || !replacements.containsKey(old.path)) return old;
      final oldOrigin = _fileOrigins[old];
      if (origin != null && !matchesOrigin(oldOrigin)) return old;
      final item = replacements[old.path];
      if (item != null &&
          !identical(old, item) &&
          oldOrigin != null &&
          item.path != null) {
        final paths = oldOrigin.source.isRemote ? p.posix : p.context;
        _fileOrigins[item] = _originAt(oldOrigin, paths.dirname(item.path!));
      }
      return item;
    }

    var changed = false;
    // Without an explicit operation origin, preserve the synchronous API's
    // scope to the active list. Async callers always supply their origin.
    if (origin != null) {
      for (final entry in _fileListTabs.entries.toList()) {
        if (_showingSearchResults && entry.key == _activeTabId) continue;
        final snapshot = entry.value;
        if (!matchesOrigin(snapshot.origin)) continue;
        final updated = <FileItem>[];
        final selected = <FileItem>{};
        var tabChanged = false;
        for (final old in snapshot.files) {
          final item = replacementFor(old);
          tabChanged = tabChanged || !identical(old, item);
          if (item == null) continue;
          updated.add(item);
          if (snapshot.selection.contains(old)) selected.add(item);
        }
        if (!tabChanged) continue;
        _fileListTabs[entry.key] = _FileListSnapshot(
          files: updated,
          title: snapshot.title,
          origin: snapshot.origin,
          selection: selected,
          cursor: replacementFor(snapshot.cursor),
        );
        changed = true;
      }
    }

    if (!_showingSearchResults || !matchesOrigin(_fileListOrigin)) {
      if (changed) notifyListeners();
      return;
    }
    final previousCursor = cursorItem;
    final updated = <FileItem>[];
    final selected = <FileItem>{};
    for (final old in _files ?? const <FileItem>[]) {
      final item = replacementFor(old);
      changed = changed || !identical(old, item);
      if (item == null) continue;
      updated.add(item);
      if (_selection.contains(old)) selected.add(item);
      if (identical(_lastSelected, old)) _lastSelected = item;
      if (identical(_itemToScrollTo, old)) _itemToScrollTo = item;
    }
    if (!changed) return;
    _files = updated;
    _selection
      ..clear()
      ..addAll(selected);
    if (_lastSelected != null &&
        !updated.any((item) => identical(item, _lastSelected))) {
      _lastSelected = null;
    }
    if (_itemToScrollTo != null &&
        !updated.any((item) => identical(item, _itemToScrollTo))) {
      _itemToScrollTo = null;
    }
    _sortFiles();
    _resetCursor(preserveItem: replacementFor(previousCursor));
    _rememberFileListTab();
    notifyListeners();
  }

  String exportFileListPaths({bool selectedOnly = false}) {
    final files = selectedOnly ? _selection : (_files ?? const <FileItem>[]);
    return FileListPaths.encode(
      files.where((item) => item.name != '..').map((item) {
        if (item.path != null && item.path!.isNotEmpty) return item.path!;
        final origin = originForOperation(item);
        if (origin == null) {
          throw StateError(
            'The original path of "${item.name}" is unavailable.',
          );
        }
        final paths = origin.source.isRemote ? p.posix : p.context;
        return paths.join(origin.source.currentPath, item.name);
      }),
    );
  }

  Future<void> openContainingFolder(FileItem item) async {
    final origin = originForOperation(item);
    if (origin == null) {
      throw StateError(
        'This result no longer has a verified source. Run the search again.',
      );
    }
    final paths = origin.source.isRemote ? p.posix : p.context;
    final path = item.path ?? paths.join(origin.source.currentPath, item.name);
    _leaveFileList();
    await navigateToPath(paths.dirname(path), selectItem: item, origin: origin);
    focusList();
  }

  /// Resolve an imported path list through the current source. Every imported
  /// row must be present in a real parent-directory listing before it gains an
  /// operation origin. The panel/account may not change during the import.
  Future<FileListImportResult> importFileListPaths(
    String text, {
    String title = 'File list',
    bool Function()? isCancelled,
  }) async {
    final origin = captureCurrentOrigin();
    final generation = _listingGeneration;
    final paths = origin.source.isRemote ? p.posix : p.context;
    final requested = FileListPaths.parse(
      text,
      basePath: origin.source.currentPath,
      local: origin.source.isLocal,
    );
    final byParent = <String, List<String>>{};
    for (final path in requested) {
      (byParent[paths.dirname(path)] ??= []).add(path);
    }
    final found = <String, FileItem>{};
    final failures = <String, String>{};
    for (final entry in byParent.entries) {
      if (isCancelled?.call() == true) {
        throw StateError('File list import cancelled.');
      }
      if (!origin.isCurrent || generation != _listingGeneration) {
        throw StateError(
          'The panel or account changed during import. Open the list again.',
        );
      }
      try {
        final listed = <FileItem>[];
        if (origin.source is RemotePanelSource) {
          final result = await (origin.source as RemotePanelSource).client
              .listPath(entry.key);
          for (final kind in const ['folders', 'files']) {
            for (final value in (result[kind] as List? ?? const [])) {
              final map = Map<String, dynamic>.from(value as Map);
              var name = map['name']?.toString() ?? '';
              if (name.isEmpty ||
                  name == '..' ||
                  name == '.' ||
                  name.contains('/')) {
                continue;
              }
              if (kind == 'files') {
                final extension = (map['fileType'] ?? map['type'] ?? '')
                    .toString();
                if (extension.isNotEmpty &&
                    extension.toLowerCase() != 'file' &&
                    !name.toLowerCase().endsWith(
                      '.${extension.toLowerCase()}',
                    )) {
                  name = '$name.$extension';
                }
              }
              final modified =
                  map['lastModified'] ??
                  map['modificationTime'] ??
                  map['updatedAt'];
              listed.add(
                FileItem(
                  name: name,
                  path: paths.join(entry.key, name),
                  isFolder: kind == 'folders',
                  uuid: map['uuid']?.toString(),
                  size: (map['size'] as num?)?.toInt(),
                  updatedAt: modified is int
                      ? DateTime.fromMillisecondsSinceEpoch(modified)
                      : DateTime.tryParse(modified?.toString() ?? ''),
                  metadata: map,
                ),
              );
            }
          }
        } else {
          final entities = await _localFileService.listDirectory(entry.key);
          if (entities == null) {
            throw StateError('This folder could not be listed.');
          }
          for (final entity in entities) {
            if (!entry.value.contains(paths.normalize(entity.path))) continue;
            var folder = entity is Directory;
            int? size;
            DateTime? modified;
            bool? symlink;
            String? symlinkTarget;
            if (kIsWeb) {
              final metadata = _localFileService.getWebMetadata(entity.path);
              size = metadata['size'] as int?;
              modified = metadata['modified'] as DateTime?;
            } else {
              final stat = await entity.stat();
              folder = stat.type == FileSystemEntityType.directory;
              size = folder ? null : stat.size;
              modified = stat.modified;
              symlink =
                  await FileSystemEntity.type(
                    entity.path,
                    followLinks: false,
                  ) ==
                  FileSystemEntityType.link;
              if (symlink) symlinkTarget = await Link(entity.path).target();
            }
            listed.add(
              FileItem(
                name: paths.basename(entity.path),
                path: paths.normalize(entity.path),
                isFolder: folder,
                size: size,
                updatedAt: modified,
                isSymlink: symlink,
                symlinkTarget: symlinkTarget,
              ),
            );
          }
        }
        for (final path in entry.value) {
          final candidates = listed.where((item) => item.path == path).toList();
          if (candidates.length == 1) {
            found[path] = candidates.single;
          } else {
            failures[path] = candidates.isEmpty
                ? 'Not found or inaccessible'
                : 'Ambiguous directory entry';
          }
        }
      } catch (e) {
        for (final path in entry.value) {
          failures[path] = e.toString();
        }
      }
    }
    if (isCancelled?.call() == true) {
      throw StateError('File list import cancelled.');
    }
    if (!origin.isCurrent || generation != _listingGeneration) {
      throw StateError(
        'The panel or account changed during import. Open the list again.',
      );
    }
    if (found.isEmpty) {
      throw StateError(
        'None of the listed paths could be found in ${origin.source.displayName}. '
        '${failures.isEmpty ? '' : failures.values.first}',
      );
    }
    final ordered = requested
        .map((path) => found[path])
        .whereType<FileItem>()
        .toList();
    showSearchResults(ordered, origin: origin, title: title);
    return FileListImportResult(
      loaded: ordered.length,
      failures: Map.unmodifiable(failures),
    );
  }

  // --- Archive navigation ---

  /// Enter a compressed archive for browsing.
  /// Cached archive bytes for web browsing (native reads from disk each time).
  Uint8List? _archiveBytes;
  PanelFileOrigin? _archiveOrigin;

  Future<void> enterArchive(FileItem file) async {
    if (file.path == null && file.name.isEmpty) return;
    int? requestGeneration;
    try {
      // A list entry must be the exact captured result. For a regular folder,
      // read-only archive callers may provide a same-path FileItem wrapper.
      final origin = _showingSearchResults
          ? captureOperationOrigin([file])
          : (originForOperation(file) ?? captureCurrentOrigin());
      final paths = origin.source.isRemote ? p.posix : p.context;
      final archivePath =
          file.path ?? paths.join(origin.source.currentPath, file.name);
      final parentSource = origin.source.withPath(paths.dirname(archivePath));
      _leaveFileList();
      final generation = ++_listingGeneration;
      requestGeneration = generation;
      _archiveSource = const PanelSourceService().enterArchive(
        archivePath,
        parentSource,
      );
      _archiveOrigin = origin;
      _archiveBytes = null;
      _isLoading = true;
      notifyListeners();
      _log.info('enterArchive: $archivePath (${parentSource.displayName})');
      Uint8List bytes;
      if (origin.source is RemotePanelSource) {
        bytes = await (origin.source as RemotePanelSource).client
            .downloadFileBytes(archivePath);
      } else {
        if (!await _localFileService.ensureAccess(archivePath)) {
          throw StateError('Access to the archive was not granted.');
        }
        bytes = await _localFileService.readFile(archivePath, fileItem: file);
      }
      if (_isDisposed || generation != _listingGeneration) return;
      if (!origin.isCurrent) {
        throw StateError(
          'The storage account changed while opening the archive.',
        );
      }
      _archiveBytes = bytes;
      _isLoading = false;
      await _loadArchiveFiles();
      if (!_isDisposed) notifyListeners();
    } catch (e) {
      if (_isDisposed ||
          (requestGeneration != null &&
              requestGeneration != _listingGeneration)) {
        return;
      }
      _log.warn('archive open failed', e);
      _archiveSource = null;
      _archiveOrigin = null;
      _archiveBytes = null;
      _isLoading = false;
      _ref.read(errorProvider).addError('Cannot open archive: $e');
      notifyListeners();
    }
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
    var parent = inner.endsWith('/')
        ? inner.substring(0, inner.length - 1)
        : inner;
    final lastSlash = parent.lastIndexOf('/');
    parent = lastSlash > 0 ? parent.substring(0, lastSlash + 1) : '';
    _archiveSource = _archiveSource!.withPath(parent);
    await _loadArchiveFiles();
    notifyListeners();
  }

  /// Exit the archive and restore the parent directory listing.
  void exitArchive() {
    final source = _archiveSource;
    final origin = _archiveOrigin;
    _archiveSource = null;
    _archiveOrigin = null;
    _archiveBytes = null;
    if (source != null) {
      if (source.parent.isRemote) {
        _remotePath = p.posix.dirname(source.archivePath);
      } else {
        _localPath = p.dirname(source.archivePath);
      }
    }
    final restore = source != null && origin != null && origin.isCurrent
        ? navigateToPath(
            source.parent.currentPath,
            origin: origin,
            recordHistory: false,
          )
        : refresh();
    unawaited(
      restore
          .then((_) {
            if (!_isDisposed) focusList();
          })
          .catchError((Object error) {
            if (!_isDisposed) {
              _ref
                  .read(errorProvider)
                  .addError('Could not return to the archive folder: $error');
            }
          }),
    );
  }

  /// Leave an archive and go to the home directory. Used by the error banner
  /// when a stale archive path cannot be listed.
  Future<void> navigateHome() async {
    if (isInArchive) {
      exitArchive();
      return;
    }
    final path = kIsWeb ? '/' : (Platform.environment['HOME'] ?? '/');
    await navigateToPath(path);
    if (!_isDisposed) focusList();
  }

  Future<void> _loadArchiveFiles() async {
    final generation = ++_listingGeneration;
    final source = _archiveSource;
    if (source == null) return;
    if (_archiveOrigin != null && !_archiveOrigin!.isCurrent) {
      _files = [];
      _ref
          .read(errorProvider)
          .addError(
            'The archive source account changed. Open the archive again.',
          );
      return;
    }
    final bytes = _archiveBytes;
    if (bytes == null) {
      // Fallback for sources without cached bytes (legacy path).
      if (source.parent.isRemote) {
        _files = [];
        _ref
            .read(errorProvider)
            .addError('Open this remote archive again to read its contents.');
        return;
      }
      final files = await const PanelSourceService().listFiles(source);
      if (_isDisposed || generation != _listingGeneration) return;
      _files = files;
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
            items.add(
              FileItem(
                name: relative,
                path: '$prefix$relative',
                isFolder: false,
                size: member.size,
              ),
            );
          }
        } else {
          final folder = relative.substring(0, slash);
          if (folders.add(folder)) {
            items.add(
              FileItem(name: folder, path: '$prefix$folder/', isFolder: true),
            );
          }
        }
      }
      if (_isDisposed ||
          generation != _listingGeneration ||
          !identical(_archiveSource, source)) {
        return;
      }
      _files = items;
      _sortFiles();
    } on ArchivePasswordRequiredException {
      if (_isDisposed || generation != _listingGeneration) return;
      _files = [];
      _ref.read(errorProvider).addError('This archive is password-protected.');
    } on ArchiveViewException catch (e) {
      if (_isDisposed || generation != _listingGeneration) return;
      _files = [];
      _ref.read(errorProvider).addError('Failed to read archive: ${e.message}');
    } catch (e) {
      if (_isDisposed || generation != _listingGeneration) return;
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
    final PanelSource source =
        _currentDirectoryOrigin?.source ??
        _ref.read<PanelSource>(panelSourceProvider(side));
    if (kIsWeb || !source.isLocal) {
      _ref
          .read(errorProvider)
          .addError('Flat view is only available for local directories');
      _isFlatView = false;
      return;
    }
    _leaveFileList();
    final generation = ++_listingGeneration;
    final path = _localPath;
    final origin = PanelFileOrigin._(
      LocalPanelSource(path),
      () => !_isDisposed,
    );
    _isLoading = true;
    notifyListeners();
    try {
      final items = await _localFileService.walkFiles(
        path,
        includeHidden: _showHiddenFiles,
        maxItems: 10000,
      );
      if (_isDisposed || generation != _listingGeneration) return;
      final prev = cursorItem;
      _files = items;
      _recordOrigins(items, origin);
      _sortFiles();
      _resetCursor(preserveItem: prev);
    } catch (e) {
      if (_isDisposed || generation != _listingGeneration) return;
      _log.warn('operation failed', e);
      _ref.read(errorProvider).addError('Flat view failed: $e');
      _isFlatView = false;
    } finally {
      if (!_isDisposed && generation == _listingGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  String get currentPath {
    if (isInArchive) {
      return '${_archiveSource!.archiveName}:/${_archiveSource!.innerPath}';
    }
    if (_showingSearchResults && _fileListOrigin != null) {
      return _fileListOrigin!.source.currentPath;
    }
    if (_currentDirectoryOrigin != null &&
        _verifiedListingGeneration == _listingGeneration) {
      return _currentDirectoryOrigin!.source.isRemote
          ? _remotePath
          : _localPath;
    }
    final source = _ref.read(panelSourceProvider(side));
    return source.isRemote ? _remotePath : _localPath;
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
        return (a.updatedAt ?? DateTime(1970)).compareTo(
          b.updatedAt ?? DateTime(1970),
        );
      case SortBy.extension:
        if (a.isFolder || b.isFolder) return 0;
        final extA = a.name.contains('.')
            ? a.name.split('.').last.toLowerCase()
            : '';
        final extB = b.name.contains('.')
            ? b.name.split('.').last.toLowerCase()
            : '';
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
        comparison = _secondarySortOrder == SortOrder.ascending
            ? secondary
            : -secondary;
      }

      if (comparison == 0 && (_showingSearchResults || _isFlatView)) {
        comparison = (a.path ?? '').compareTo(b.path ?? '');
        if (_sortOrder == SortOrder.descending) comparison = -comparison;
      }
      return comparison;
    });
  }

  // --- Selection ---
  bool isSelected(FileItem item) => _selection.contains(item);

  void toggleSelection(
    FileItem item, {
    bool shiftKey = false,
    bool ctrlKey = false,
  }) {
    _log.debug(
      'toggleSelection: ${item.name} shift=$shiftKey ctrl=$ctrlKey lastSelected=${_lastSelected?.name} side=$side',
    );
    final files = _files;
    if (files == null || !_containsIdentical(files, item)) return;
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
    if (item.name == '..' || item.name == '.') {
      _lastSelected = null;
      notifyListeners();
      return;
    }
    if (shiftKey && _lastSelected != null) {
      final displayed = displayedFiles ?? const <FileItem>[];
      final startIdx = _indexOfIdentical(displayed, _lastSelected!);
      final endIdx = _indexOfIdentical(displayed, item);
      if (startIdx != -1 && endIdx != -1) {
        final start = startIdx < endIdx ? startIdx : endIdx;
        final end = startIdx < endIdx ? endIdx : startIdx;
        for (var i = start; i <= end; i++) {
          if (displayed[i].name != '..' && displayed[i].name != '.') {
            _selection.add(displayed[i]);
          }
        }
      } else if (endIdx != -1) {
        // A previous anchor can disappear when a filter is applied.
        _selection.add(item);
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
    final displayed = displayedFiles;
    _log.debug('selectAll (${displayed?.length ?? 0} visible files)');
    if (displayed != null) {
      _selection.addAll(
        displayed.where((f) => f.name != '..' && f.name != '.'),
      );
      notifyListeners();
    }
  }

  void invertSelection() {
    _log.debug('invertSelection (was ${_selection.length} selected)');
    final displayed = displayedFiles;
    if (displayed == null) return;
    for (final item in displayed) {
      if (item.name == '..' || item.name == '.') continue;
      if (!_selection.remove(item)) _selection.add(item);
    }
    _lastSelected = null;
    notifyListeners();
  }

  void clearSelection() {
    _log.debug('clearSelection (was ${_selection.length})');
    _selection.clear();
    _lastSelected = null;
    notifyListeners();
  }

  bool get _canUseSelectionMemory =>
      !_isDisposed &&
      !_isLoading &&
      !isInArchive &&
      _verifiedListingGeneration == _listingGeneration;

  (StorageReference, String)? _selectionMemoryKey(
    FileItem item,
    PanelFileOrigin origin,
  ) {
    if (item.name == '..' || item.name == '.') return null;
    final paths = origin.source.isRemote || kIsWeb ? p.posix : p.context;
    final path = item.path ?? paths.join(origin.source.currentPath, item.name);
    if (!paths.isAbsolute(path)) return null;
    return (origin.storageReference, paths.normalize(path));
  }

  /// Remember marks for this tab and storage session, never just basenames.
  /// Restoration resolves fresh, verified rows; saved objects grant no writes.
  int rememberSelection() {
    if (!_canUseSelectionMemory || _activeTabId.isEmpty) return 0;
    final remembered = <(StorageReference, String), _SelectionMemoryEntry>{};
    for (final item in _files ?? const <FileItem>[]) {
      if (!_selection.contains(item)) continue;
      final origin = _fileOrigins[item];
      if (origin == null || !origin.isCurrent) continue;
      final key = _selectionMemoryKey(item, origin);
      if (key != null) {
        remembered[key] = _SelectionMemoryEntry(
          origin: origin,
          objectId: item.uuid,
          isFolder: item.isFolder,
        );
      }
    }
    if (remembered.isEmpty) return 0;
    _selectionMemories[_activeTabId] = remembered;
    notifyListeners();
    return remembered.length;
  }

  int get rememberedSelectionCount =>
      _selectionMemories[_activeTabId]?.length ?? 0;

  List<FileItem> _restorableSelection() {
    if (!_canUseSelectionMemory) return const [];
    final remembered = _selectionMemories[_activeTabId];
    if (remembered == null || remembered.isEmpty) return const [];
    final matches = <(StorageReference, String), FileItem?>{};
    for (final item in displayedFiles ?? const <FileItem>[]) {
      final origin = _fileOrigins[item];
      if (origin == null || !origin.isCurrent) continue;
      final key = _selectionMemoryKey(item, origin);
      if (key == null) continue;
      final memory = remembered[key];
      if (memory == null ||
          !memory.origin.isCurrent ||
          !_sameStorage(memory.origin.source, origin.source) ||
          memory.isFolder != item.isFolder ||
          (memory.objectId != null && memory.objectId != item.uuid)) {
        continue;
      }
      // An ambiguous directory entry is never chosen by a saved mark.
      matches[key] = matches.containsKey(key) ? null : item;
    }
    return matches.values.whereType<FileItem>().toList();
  }

  int get restorableSelectionCount => _restorableSelection().length;

  /// Replace marks with remembered items still visible in this tab and source.
  /// If none can be resolved, retain the current marks instead of erasing them.
  int restoreSelection() {
    final restored = _restorableSelection();
    if (restored.isEmpty) return 0;
    _selection
      ..clear()
      ..addAll(restored);
    _lastSelected = null;
    _rememberFileListTab();
    notifyListeners();
    return restored.length;
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
    _computeFolderSize(folder.path!)
        .then((size) {
          updateItemCalculatedSize(folder, size);
        })
        .catchError((_) {});
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
      if (displayed[i].name != '..') _selection.add(displayed[i]);
    }
    _lastSelected = displayed[next].name == '..' ? null : displayed[next];
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

  /// Apply a compiled pattern to visible items without changing the filter.
  /// Validation happens when [pattern] is constructed, before marks change.
  int applyPatternSelection(
    FileSelectionPattern pattern, {
    SelectionAction action = SelectionAction.select,
  }) {
    final matches = (displayedFiles ?? const <FileItem>[])
        .where(pattern.matches)
        .toList();
    switch (action) {
      case SelectionAction.select:
        _selection.addAll(matches);
      case SelectionAction.deselect:
        _selection.removeAll(matches);
      case SelectionAction.invert:
        for (final item in matches) {
          if (!_selection.remove(item)) _selection.add(item);
        }
      case SelectionAction.replace:
        _selection
          ..clear()
          ..addAll(matches);
    }
    _lastSelected = null;
    notifyListeners();
    return matches.length;
  }

  /// Compatibility entry points used by existing keypad commands.
  void selectByPattern(String glob) =>
      applyPatternSelection(FileSelectionPattern(glob));

  void deselectByPattern(String glob) => applyPatternSelection(
    FileSelectionPattern(glob),
    action: SelectionAction.deselect,
  );

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
      var idx = _indexOfIdentical(_files!, anchor);
      if (idx == -1 && anchor.path != null) {
        idx = _files!.indexWhere((f) => f.path == anchor.path);
      }
      if (idx == -1 && anchor.uuid != null) {
        idx = _files!.indexWhere((f) => f.uuid == anchor.uuid);
      }
      if (idx == -1 && anchor.path == null && anchor.uuid == null) {
        idx = _files!.indexWhere((f) => f.name == anchor.name);
      }
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

  /// Refresh the current directory listing, serializing overlapping requests.
  /// Queued work must not outlive the panel that requested it.
  Future<void> refresh() async {
    if (_isDisposed) return;
    _log.debug('refresh: side=$side archive=$isInArchive flat=$_isFlatView');
    await _refreshLock.synchronized(() async {
      // A tab change can queue this callback while a previous listing is still
      // pending. The container may be disposed before the lock is released.
      if (_isDisposed) return;
      if (_showingSearchResults) {
        // Virtual lists are snapshots. Refresh must not replace them with the
        // directory behind the list; mutation callers update successful rows.
        if (!canOperateOnFileList) {
          _ref
              .read(errorProvider)
              .addError(
                'The list source is disconnected or changed. Run the search or import again.',
              );
        }
        notifyListeners();
      } else if (isInArchive) {
        await _loadArchiveFiles();
      } else if (_isFlatView) {
        await _loadFlatFiles();
      } else {
        // Panel position is not storage identity: either pane can show a
        // cloud account or local files. Reconnect refreshes a fresh listing
        // from the active account; old origins never authorize its writes.
        final knownSource = _verifiedListingGeneration == _listingGeneration
            ? _currentDirectoryOrigin?.source
            : null;
        final selectedSource = _ref.read(panelSourceProvider(side));
        final remote =
            _ref.read(authProvider).isConnected &&
            (knownSource?.isRemote ??
                (selectedSource.isRemote ||
                    (side == PanelSide.remote &&
                        _currentDirectoryOrigin == null)));
        if (remote) {
          await _loadRemoteFiles();
        } else {
          _localFileService.currentPath = _localPath;
          await _localFileService.refresh();
          if (_isDisposed) return;
          await _loadLocalFiles();
        }
      }
    });
  }

  /// Debounced refresh — coalesces rapid refresh calls within [delay].
  void refreshDebounced({Duration delay = const Duration(milliseconds: 500)}) {
    if (_isDisposed) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(delay, () => refresh());
  }

  /// Alias used by widgets and keyboard shortcuts.
  void refreshFiles() => refresh();

  Future<void> navigateUp() async {
    _log.info(
      'navigateUp: currentPath=$currentPath archive=$isInArchive flat=$_isFlatView',
    );
    if (_showingSearchResults) {
      await clearSearchResults();
      return;
    }
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
      _archiveOrigin = null;
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
      _ref
          .read(errorProvider)
          .addError(
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

  Future<bool> grantAccessToCurrentPath() => grantAccessToPath(currentPath);

  /// Normalise user-entered paths and repair the common macOS failure where
  /// an absolute path was appended to the current directory by a non-selecting
  /// text field.
  String _normaliseLocalPath(String raw) {
    var path = raw.trim();
    if (path.isEmpty) return path;
    if (path.startsWith('"') && path.endsWith('"') && path.length > 1) {
      path = path.substring(1, path.length - 1);
    }
    if (path.startsWith('file://')) {
      try {
        path = Uri.parse(path).toFilePath();
      } catch (_) {
        // Keep the original value; the loader will report a friendly error.
      }
    }
    final home = kIsWeb ? null : Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      if (path == '~') {
        path = home;
      } else if (path.startsWith('~/')) {
        path = '$home/${path.substring(2)}';
      }
      // A path such as "/container/Data/Users/me/Downloads" or
      // "/Users/me/Downloads/Users/me/Downloads" contains HOME after a wrong
      // prefix. Keep the last real absolute path.
      final homeIndex = path.lastIndexOf(home);
      if (homeIndex > 0) {
        path = path.substring(homeIndex);
      }
    }
    if (!kIsWeb) {
      if (!p.isAbsolute(path)) path = p.join(currentPath, path);
      path = p.normalize(path);
    }
    return path;
  }

  Future<void> navigateToPath(
    String path, {
    FileItem? selectItem,
    PanelFileOrigin? origin,
    bool recordHistory = true,
  }) async {
    _log.info('navigateToPath: $path (side=$side, web=$kIsWeb)');
    final sourceOrigin =
        origin ??
        (_showingSearchResults
            ? _fileListOrigin
            : (_verifiedListingGeneration == _listingGeneration
                  ? _currentDirectoryOrigin
                  : null));
    if (sourceOrigin != null && !sourceOrigin.isCurrent) {
      throw StateError(
        'The storage account changed. Refresh the folder or run the search again.',
      );
    }
    final selectedSource = _ref.read(panelSourceProvider(side));
    final isRemote =
        sourceOrigin?.source.isRemote ??
        (selectedSource.isRemote ||
            (side == PanelSide.remote && _ref.read(authProvider).isConnected));
    _leaveFileList();
    // Any explicit path navigation leaves archive mode. Previously the stale
    // ArchivePanelSource kept currentPath virtual and Home/breadcrumbs tried
    // to list "archive.zip:/inner/".
    if (isInArchive) {
      _archiveSource = null;
      _archiveOrigin = null;
      _archiveBytes = null;
    }
    if (path.contains(':/')) {
      final archive = path.split(':/').first;
      path = !isRemote
          ? (archive.contains('/')
                ? p.dirname(archive)
                : (kIsWeb ? '/' : (Platform.environment['HOME'] ?? '/')))
          : p.posix.dirname(archive);
    }
    if (!isRemote) {
      path = _normaliseLocalPath(path);
      if (path.isEmpty) return;
    }
    _selection.clear();
    _lastSelected = null;
    if (_isTypeahead) {
      _filterQuery = '';
      _isTypeahead = false;
    }
    if (!isRemote) {
      if (!kIsWeb && !await _localFileService.hasAccessToPath(path)) {
        final target = path;
        final granted = await _localFileService.requestDirectoryAccess(
          initialDirectory: p.dirname(target),
        );
        if (granted == null) {
          _ref
              .read(errorProvider)
              .addError('Access to "$target" was not granted.');
          return;
        }
        if (!await _localFileService.hasAccessToPath(target)) {
          _ref
              .read(errorProvider)
              .addError(
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
      if (!_ref.read(authProvider).isConnected ||
          (sourceOrigin != null && !sourceOrigin.isCurrent)) {
        throw StateError('The cloud account is no longer connected.');
      }
      await _loadRemoteFiles();
    }

    if (selectItem != null && _files != null) {
      try {
        final found = _files!.firstWhere(
          (f) =>
              (selectItem.path != null && f.path == selectItem.path) ||
              (selectItem.uuid != null && f.uuid == selectItem.uuid),
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
    if (recordHistory) _pushHistory(currentPath);
    _ref.read(recentLocationsProvider).add(currentPath, side);
    notifyListeners();
  }

  Future<void> navigateInto(FileItem item) async {
    _log.info(
      'navigateInto: ${item.name} isFolder=${item.isFolder} path=${item.path}',
    );
    final operationOrigin = _showingSearchResults
        ? originForOperation(item)
        : null;
    if (_showingSearchResults && operationOrigin == null) {
      _ref
          .read(errorProvider)
          .addError(
            'This result no longer has a verified source. Run the search again.',
          );
      return;
    }
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
    if (operationOrigin != null) {
      await navigateToPath(item.path!, origin: operationOrigin);
    } else if (side == PanelSide.local) {
      if (item.path != null) await navigateToPath(item.path!);
    } else {
      await navigateToPath(item.path ?? p.posix.join(_remotePath, item.name));
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
    final selected = _selection
        .map((entry) => identical(entry, item) ? replacement : entry)
        .toList();
    _selection
      ..clear()
      ..addAll(selected);
    if (identical(_lastSelected, item)) _lastSelected = replacement;
    if (identical(_itemToScrollTo, item)) _itemToScrollTo = replacement;
    notifyListeners();
  }

  // --- File operations (local panel helpers) ---
  bool canTrashFiles(List<FileItem> files) {
    try {
      final source = captureOperationOrigin(files).source;
      return source is LocalPanelSource
          ? NativeFileOperations.supported
          : source is RemotePanelSource &&
                source.client is StorageTrashOperations;
    } catch (_) {
      return false;
    }
  }

  Future<int> deleteFiles(
    List<FileItem> files, {
    bool permanently = false,
  }) async {
    final audit = _ref.read(auditServiceProvider);
    final history = _ref.read(actionHistoryProvider.notifier);
    var providerName = 'unknown';
    final removed = <String, FileItem?>{};
    PanelFileOrigin? operationOrigin;
    var deletedCount = 0;
    try {
      final origin = captureOperationOrigin(files);
      if (!permanently && !canTrashFiles(files)) {
        throw UnsupportedError(
          'Trash is unavailable for this source. Choose Delete without restore explicitly.',
        );
      }
      operationOrigin = origin;
      final source = origin.source;
      final paths = source.isLocal && !kIsWeb ? p.context : p.posix;
      providerName = source is RemotePanelSource
          ? source.providerName
          : 'local';
      final roots = files
          .where(
            (file) => !files.any(
              (parent) =>
                  parent.isFolder &&
                  parent.isSymlink != true &&
                  !identical(file, parent) &&
                  parent.path != null &&
                  file.path != null &&
                  paths.isWithin(parent.path!, file.path!),
            ),
          )
          .toList();
      for (final file in roots) {
        if (!origin.isCurrent) throw StateError('The storage account changed.');
        final path = file.path;
        if (path == null) throw StateError('The original path is unavailable.');
        TrashReceipt? receipt;
        Future<void> Function()? restore;
        if (!permanently) {
          if (source is LocalPanelSource) {
            final native = _ref.read(nativeFileOperationsProvider);
            receipt = await _localFileService.withFileOperationAccess(
              path,
              () => native.trash(path),
            );
            final capturedReceipt = receipt!;
            restore = () => _localFileService.withFileOperationAccess(
              path,
              () => native.restore(capturedReceipt),
            );
          } else if (source is RemotePanelSource &&
              source.client is StorageTrashOperations) {
            final trash = source.client as StorageTrashOperations;
            receipt = await trash.trashPath(path);
            final capturedReceipt = receipt;
            restore = () => trash.restoreTrash(capturedReceipt);
          }
        } else if (source is LocalPanelSource) {
          if (kIsWeb) {
            await _localFileService.deleteEntry(path, file.isFolder);
          } else {
            await _localFileService.withFileOperationAccess(path, () async {
              if (!origin.isCurrent) {
                throw StateError('The source is no longer available.');
              }
              if (file.isSymlink == true) {
                await Link(path).delete();
              } else if (file.isFolder) {
                await Directory(path).delete(recursive: true);
              } else {
                await File(path).delete();
              }
            });
          }
        } else if (source is RemotePanelSource) {
          final client = source.client;
          if (client is StorageTrashOperations) {
            await (client as StorageTrashOperations).deletePermanently(path);
          } else {
            await client.deletePath(path);
          }
        } else {
          throw UnsupportedError('This source cannot be deleted from here.');
        }
        removed[path] = null;
        deletedCount++;
        if (file.isFolder) {
          for (final child in _files ?? const <FileItem>[]) {
            if (child.path != null && paths.isWithin(path, child.path!)) {
              removed[child.path!] = null;
            }
          }
        }
        await audit.logSuccess(
          operation: AuditOperation.delete,
          sourcePath: path,
          provider: providerName,
          sizeBytes: file.size,
        );
        history.record(
          type: ActionType.delete,
          originalPath: path,
          provider: providerName,
          metadata: {
            'name': file.name,
            'isFolder': file.isFolder,
            'permanent': permanently,
            'storage': origin.storageReference.toJson(),
            if (receipt != null) 'trash': receipt.toJson(),
          },
          isCurrent: () => origin.isCurrent,
          undoAction: restore == null
              ? null
              : () async {
                  if (!origin.isCurrent) {
                    return const UndoResult.failure(
                      'Reconnect the original storage before restoring.',
                    );
                  }
                  await restore!();
                  await refresh();
                  return UndoResult.success(
                    'Restored ${file.name} from trash.',
                  );
                },
        );
      }
    } catch (error) {
      _log.warn('Delete failed', error);
      _ref.read(errorProvider).addError('Delete failed: $error');
    } finally {
      if (operationOrigin != null) {
        applyFileListChanges(removed, origin: operationOrigin);
      }
      await refresh();
      clearSelection();
    }
    return deletedCount;
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

  Future<bool> operationPathExists(String path, PanelFileOrigin origin) async {
    if (!origin.isCurrent) throw StateError('The storage account changed.');
    final backend = fileOperationBackend(
      source: origin.source,
      local: _localFileService,
      isCurrent: () => origin.isCurrent,
    );
    final item = await backend.stat(path);
    if (!origin.isCurrent) throw StateError('The storage account changed.');
    return item != null;
  }

  /// Read siblings from the storage captured when an operation was opened.
  /// A tab/source change must never redirect a preview to the current pane.
  Future<List<FileItem>> listOperationDirectory(
    String path,
    PanelFileOrigin origin,
  ) async {
    if (!origin.isCurrent) throw StateError('The storage account changed.');
    final backend = fileOperationBackend(
      source: origin.source,
      local: _localFileService,
      isCurrent: () => origin.isCurrent,
    );
    if (!backend.paths.isAbsolute(path)) {
      throw const FormatException('Use an absolute original directory path.');
    }
    final items = await backend.list(backend.paths.normalize(path));
    if (!origin.isCurrent) throw StateError('The storage account changed.');
    return List.unmodifiable(items);
  }

  Future<void> renameFile(
    FileItem file,
    String newName, {
    bool refreshAfter = true,
    bool rethrowErrors = false,
    bool recordHistory = true,
    PanelFileOrigin? operationOrigin,
  }) async {
    _log.info('renameFile: ${file.name} → $newName');
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    var providerName = 'unknown';
    final src = file.path ?? file.name;
    try {
      if (newName == file.name) return;
      if (newName.trim().isEmpty ||
          newName == '.' ||
          newName == '..' ||
          RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(newName)) {
        throw const FormatException(
          'Enter a filename without path separators or control characters.',
        );
      }
      final origin = operationOrigin ?? captureOperationOrigin([file]);
      if (!origin.isCurrent) throw StateError('The storage account changed.');
      final source = origin.source;
      final isLocalSource = source is LocalPanelSource;
      providerName = source is RemotePanelSource
          ? source.providerName
          : 'local';
      if (file.path == null) {
        throw StateError('The original file path is unavailable.');
      }
      final paths = isLocalSource && !kIsWeb ? p.context : p.posix;
      final target = paths.join(paths.dirname(src), newName);
      if (await operationPathExists(target, origin)) {
        throw StateError(
          'A destination already exists: $target. For case-only renames, use an unused temporary name first.',
        );
      }
      if (!origin.isCurrent) throw StateError('The storage account changed.');
      String computedNewPath;
      if (isLocalSource && kIsWeb) {
        // Web rename: copy under new name, delete old entry
        final oldPath = file.path!;
        computedNewPath = p.posix.join(p.posix.dirname(oldPath), newName);
        if (!file.isFolder) {
          final bytes = await _localFileService.readFile(
            oldPath,
            fileItem: file,
          );
          final saved = await _localFileService.saveFileReportingResult(
            computedNewPath,
            bytes,
            overwrite: false,
          );
          if (saved != LocalFileSaveResult.written) {
            throw StateError(
              'The browser downloaded a copy; the source was retained.',
            );
          }
          if (!origin.isCurrent) {
            throw StateError('The source is no longer available.');
          }
          await _localFileService.deleteEntry(oldPath, false);
        } else {
          throw UnsupportedError(
            'Folder rename requires a native filesystem or cloud provider.',
          );
        }
      } else if (isLocalSource) {
        computedNewPath = p.join(p.dirname(file.path!), newName);
        await _localFileService.withFileOperationAccess(src, () async {
          if (!origin.isCurrent) {
            throw StateError('The source is no longer available.');
          }
          if (!await moveNativeNoReplace(src, computedNewPath)) {
            throw UnsupportedError(
              'This filesystem cannot safely rename without replacing an existing item.',
            );
          }
        });
      } else {
        if (source is! RemotePanelSource) {
          throw UnsupportedError('This source cannot be renamed.');
        }
        final client = source.client;
        final sourcePath = src;
        computedNewPath = p.posix.join(p.posix.dirname(sourcePath), newName);
        await client.renamePath(sourcePath, newName);
      }
      await audit.logSuccess(
        operation: AuditOperation.rename,
        sourcePath: src,
        targetPath: newName,
        provider: providerName,
      );
      if (recordHistory) {
        actionHistory.record(
          type: ActionType.rename,
          originalPath: src,
          newPath: computedNewPath,
          provider: providerName,
          metadata: {'oldName': file.name, 'newName': newName},
          isCurrent: () => origin.isCurrent,
          undoAction: () async {
            if (!origin.isCurrent) {
              return const UndoResult.failure('The storage account changed.');
            }
            final renamed = file.copyWith(name: newName, path: computedNewPath);
            await renameFile(
              renamed,
              file.name,
              operationOrigin: origin,
              refreshAfter: false,
              rethrowErrors: true,
              recordHistory: false,
            );
            applyFileListChanges({computedNewPath: file}, origin: origin);
            await refresh();
            return UndoResult.success('Renamed $newName back to ${file.name}.');
          },
        );
      }
      if (refreshAfter) {
        applyFileListChanges({
          src: file.copyWith(name: newName, path: computedNewPath),
        }, origin: origin);
        await refresh();
      }
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
      if (rethrowErrors) rethrow;
    }
  }

  Future<void> createFolder(String name) async {
    _log.info('createFolder: $name in $currentPath');
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final isLocalSource =
        _ref.read(panelSourceProvider(side)).isLocal || side == PanelSide.local;
    final providerName = isLocalSource
        ? 'local'
        : _ref.read(authProvider).client.providerName;
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
      'moveFiles: ${files.length} items → $targetPath (web=$kIsWeb, side=$side)',
    );
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final isLocalSource =
        _ref.read(panelSourceProvider(side)).isLocal || side == PanelSide.local;
    final providerName = isLocalSource
        ? 'local'
        : _ref.read(authProvider).client.providerName;
    try {
      for (final file in files) {
        final src = file.path ?? p.posix.join(_remotePath, file.name);
        final String movedToPath;
        if (isLocalSource && kIsWeb) {
          // Web: move = copy bytes to target + delete source
          movedToPath = p.posix.join(targetPath, file.name);
          if (file.path != null && !file.isFolder) {
            final bytes = await _localFileService.readFile(
              file.path!,
              fileItem: file,
            );
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
      'copyFiles: ${files.length} items → $targetPath (web=$kIsWeb, side=$side)',
    );
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    final isLocalSource =
        _ref.read(panelSourceProvider(side)).isLocal || side == PanelSide.local;
    final providerName = isLocalSource
        ? 'local'
        : _ref.read(authProvider).client.providerName;
    try {
      for (final file in files) {
        final src = file.path ?? p.posix.join(_remotePath, file.name);
        // copyPath is the new file that was created — used for undo (delete the copy)
        final String copyPath;
        if (isLocalSource && kIsWeb) {
          // Web: copy within virtual filesystem
          copyPath = p.posix.join(targetPath, file.name);
          if (file.path != null) {
            final bytes = await _localFileService.readFile(
              file.path!,
              fileItem: file,
            );
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
          if (kIsWeb) {
            throw UnsupportedError('Remote copy not supported on web');
          }
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
            'targetDir': targetPath,
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
          entity.path,
          p.join(target, p.basename(entity.path)),
        );
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
            _tabs.add(
              PanelTab(id: id, path: path, isPinned: item['pinned'] == true),
            );
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
      final list = _tabs
          .map((t) => {'path': t.path, 'pinned': t.isPinned})
          .toList();
      await prefs.setString(_tabStorageKey, json.encode(list));
      await prefs.setInt(
        '${_tabStorageKey}_active',
        _tabs
            .indexWhere((t) => t.id == _activeTabId)
            .clamp(0, _tabs.length - 1),
      );
    } catch (e) {
      _log.warn('Tab save failed', e);
    }
  }

  void addTab({String? path}) {
    _log.debug('addTab: path=${path ?? currentPath}');
    final directory = path ?? currentPath;
    _rememberFileListTab();
    _leaveFileList(forget: false);
    final id = _nextTabId();
    _tabs.add(PanelTab(id: id, path: directory));
    _activeTabId = id;
    if (side == PanelSide.local) {
      _localPath = directory;
    } else {
      _remotePath = directory;
    }
    notifyListeners();
    _saveTabs();
    refresh();
  }

  void closeTab(String tabId) {
    _log.debug('closeTab: $tabId');
    if (_tabs.length <= 1) return;
    final tab = _tabs.firstWhere(
      (t) => t.id == tabId,
      orElse: () => _tabs.first,
    );
    if (tab.isPinned) return;
    final idx = _tabs.indexOf(tab);
    _tabs.remove(tab);
    _fileListTabs.remove(tabId);
    _selectionMemories.remove(tabId);
    if (_activeTabId == tabId) {
      _leaveFileList();
      final newIdx = idx.clamp(0, _tabs.length - 1);
      selectTab(_tabs[newIdx].id);
    }
    notifyListeners();
    _saveTabs();
  }

  void selectTab(String tabId) {
    _log.debug('selectTab: $tabId');
    if (!_tabs.any((tab) => tab.id == tabId)) return;
    _rememberFileListTab();
    _leaveFileList(forget: false);
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
    final list = _fileListTabs[tabId];
    if (list != null) {
      _showingSearchResults = true;
      _fileListTitle = list.title;
      _fileListOrigin = list.origin;
      _files = List.of(list.files);
      _selection
        ..clear()
        ..addAll(list.selection);
      _listingGeneration++;
      _verifiedListingGeneration = _listingGeneration;
      _isLoading = false;
      _resetCursor(preserveItem: list.cursor);
      notifyListeners();
      _saveTabs();
      return;
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
    final tab = _tabs.firstWhere(
      (t) => t.id == tabId,
      orElse: () => _tabs.first,
    );
    tab.isPinned = !tab.isPinned;
    notifyListeners();
    _saveTabs();
  }

  void renameTab(String tabId, String newLabel) {
    final tab = _tabs.firstWhere(
      (t) => t.id == tabId,
      orElse: () => _tabs.first,
    );
    tab.label = newLabel;
    notifyListeners();
    _saveTabs();
  }

  void _syncTabPath() {
    final tab = activeTab;
    if (tab != null) {
      // Never persist archive virtual paths (e.g. "file.zip:/"): they are not
      // real directories and would break restart/restore.
      var titlePath = _currentDirectoryOrigin?.source.isRemote == true
          ? _remotePath
          : _localPath;
      if (titlePath.contains(':/')) {
        final archive = titlePath.split(':/').first;
        titlePath = side == PanelSide.local
            ? (archive.contains('/')
                  ? p.dirname(archive)
                  : (kIsWeb ? '/' : (Platform.environment['HOME'] ?? '/')))
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
        _ref
            .read(errorProvider)
            .addError(
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

  Future<void> _loadLocalFiles({bool fallbackOnMissing = true}) async {
    if (_showingSearchResults) return;
    final generation = ++_listingGeneration;
    // This loader must never receive an archive's virtual path. If an archive
    // failed to open or a stale tab restored one, leave archive mode first.
    if (_archiveSource != null) {
      final archivePath = _archiveSource!.archivePath;
      _archiveSource = null;
      _archiveOrigin = null;
      _archiveBytes = null;
      if (side == PanelSide.local && archivePath.contains('/')) {
        _localPath = p.dirname(archivePath);
      }
    }
    if (!kIsWeb && _localPath.contains(':/')) {
      _localPath = await _localFileService.getSafeFallbackDirectory();
    }
    if (_isDisposed || generation != _listingGeneration) return;
    final listingPath = _localPath;
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
      List<FileSystemEntity>? entities;
      try {
        entities = await _localFileService.listDirectory(listingPath);
      } on FileSystemException catch (e) {
        if (!_isPermissionDenied(e)) rethrow;
        // A symlinked folder may point outside the granted root, or a saved
        // bookmark may no longer resolve after a rebuild. Ask for the target
        // folder and retry once.
        final granted = await _localFileService.ensureAccess(listingPath);
        if (!granted) rethrow;
        entities = await _localFileService.listDirectory(listingPath);
      }
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
      final description = e.toString();
      final missing =
          e is PathNotFoundException ||
          description.contains('No such file') ||
          description.contains('PathNotFoundException') ||
          description.contains('Not a directory') ||
          description.contains('errno = 20');
      if (fallbackOnMissing && missing) {
        final fallback = await _localFileService.getSafeFallbackDirectory();
        if (_isDisposed || generation != _listingGeneration) return;
        if (fallback != _localPath) {
          _localPath = fallback;
          await _loadLocalFiles(fallbackOnMissing: false);
          if (_isDisposed) return;
          _syncTabPath();
          _ref
              .read(errorProvider)
              .addError('Folder not found. Returned to your Home folder.');
          return;
        }
      }
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

  /// Read one member of the currently opened archive for the internal viewer.
  /// The archive is reopened metadata-only, so F3 works for files inside ZIP,
  /// TAR, 7z and RAR archives that the panel is browsing.
  Future<Uint8List> readArchiveMember(FileItem file) async {
    final source = _archiveSource;
    final bytes = _archiveBytes;
    if (source == null ||
        bytes == null ||
        (_archiveOrigin != null && !_archiveOrigin!.isCurrent)) {
      throw const ArchiveViewException(
        'This archive is no longer open. Return to the archive and try again.',
      );
    }

    ViewerArchive? archive;
    try {
      archive = await openViewerArchive(bytes, name: source.archivePath);
      final wanted = (file.path ?? file.name);
      String normalise(String name) =>
          name.startsWith('./') ? name.substring(2) : name;
      ViewerArchiveMember? match;
      for (final member in archive.members) {
        final name = normalise(member.name);
        if (name == wanted || name == file.name) {
          match = member;
          break;
        }
      }
      if (match == null || !match.isFile) {
        throw ArchiveViewException(
          'Could not find "${file.name}" inside ${source.archiveName}.',
        );
      }
      return await archive.readMember(match, maxBytes: kArchiveReadLimit);
    } finally {
      await archive?.close();
    }
  }

  /// Return keyboard focus to this panel's file list.
  void focusList() {
    if (!_isDisposed) listFocusNode.requestFocus();
  }

  /// Re-select [item] by path/name after a viewer or editor closes, then return
  /// keyboard focus to this panel.
  void restoreCursorAndFocus(FileItem item) {
    final files = _files;
    if (files != null) {
      final index = files.indexWhere(
        (candidate) => item.path != null
            ? candidate.path == item.path
            : item.uuid != null
            ? candidate.uuid == item.uuid
            : candidate.name == item.name,
      );
      if (index != -1) {
        _cursorIndex = index;
        _itemToScrollTo = files[index];
        notifyListeners();
      }
    }
    if (!_isDisposed) listFocusNode.requestFocus();
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
    Process.run('df', ['-k', path])
        .then((result) {
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
        })
        .catchError((_) {});
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
          if (previous == null ||
              !previous.isCurrent ||
              source is! RemotePanelSource ||
              !identical(source.client, client) ||
              source.path != listingPath) {
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

      final folders =
          (result['folders'] as List<dynamic>?)?.map((item) {
            final map = item as Map<String, dynamic>;
            DateTime? folderDate;
            final rawDate =
                map['modificationTime'] ??
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
              ..removeWhere(
                (k, _) => const {
                  'name',
                  'uuid',
                  'modificationTime',
                  'lastModified',
                  'timestamp',
                }.contains(k),
              );
            return FileItem(
              name: map['name'] ?? 'Unknown',
              path: p.posix.join(listingPath, map['name'] ?? 'Unknown'),
              isFolder: true,
              uuid: map['uuid'],
              updatedAt: folderDate,
              metadata: meta.isNotEmpty ? meta : null,
            );
          }).toList() ??
          [];

      final files =
          (result['files'] as List<dynamic>?)?.map((item) {
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
              ..removeWhere(
                (k, _) => const {
                  'name',
                  'uuid',
                  'size',
                  'modificationTime',
                  'lastModified',
                  'fileType',
                  'type',
                  'timestamp',
                }.contains(k),
              );
            return FileItem(
              name: fullName,
              path: p.posix.join(listingPath, fullName),
              isFolder: false,
              size: map['size'] as int?,
              uuid: map['uuid'],
              updatedAt: fileDate,
              metadata: meta.isNotEmpty ? meta : null,
            );
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
          ),
        );
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
    listFocusNode.dispose();
    super.dispose();
  }
}

class FileListImportResult {
  const FileListImportResult({required this.loaded, required this.failures});
  final int loaded;
  final Map<String, String> failures;
}

class _SelectionMemoryEntry {
  const _SelectionMemoryEntry({
    required this.origin,
    required this.objectId,
    required this.isFolder,
  });

  final PanelFileOrigin origin;
  final String? objectId;
  final bool isFolder;
}

class _FileListSnapshot {
  const _FileListSnapshot({
    required this.files,
    required this.title,
    required this.origin,
    required this.selection,
    required this.cursor,
  });
  final List<FileItem> files;
  final String title;
  final PanelFileOrigin? origin;
  final Set<FileItem> selection;
  final FileItem? cursor;
}

final panelProvider = ChangeNotifierProvider.family<PanelNotifier, PanelSide>((
  ref,
  side,
) {
  return PanelNotifier(ref, side);
});

bool _isPermissionDenied(FileSystemException error) {
  if (error is PathAccessException) return true;
  final code = error.osError?.errorCode;
  return code == 1 || code == 13;
}
