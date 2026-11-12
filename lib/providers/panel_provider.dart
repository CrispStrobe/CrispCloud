// lib/providers/panel_provider.dart
//
// Per-panel state: file listing, selection, sort, tabs, navigation.
// Used as a family provider keyed by PanelSide.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show FocusNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/file_item.dart';
import '../models/folder_size_measurement.dart';
import '../models/file_view_configuration.dart';
import '../models/panel_side.dart';
import '../models/panel_tab.dart';
import '../models/panel_navigation.dart';
import '../models/sort.dart';
import '../models/storage_reference.dart';
import '../models/file_collection.dart';
import '../models/file_collection_page.dart';
import '../models/file_search_query.dart';
import '../models/rename_batch.dart';
import '../services/recursive_search_service.dart';
import '../services/file_collection_service.dart';
import '../services/collection_panel_state.dart';
import '../services/file_collection_query.dart';
import '../services/file_collection_store.dart';
import '../services/file_operation_service.dart';
import '../services/captured_file_target.dart';
import '../services/storage_identity.dart';
import '../services/storage_scan_backend.dart';
import '../services/storage_scan_service.dart';
import '../services/storage_trash.dart';
import '../services/trash_history_store.dart';
import 'trash_history_provider.dart';
import '../services/native_file_operations.dart';
import '../services/native_system.dart';
import '../services/multi_rename_service.dart';
import '../services/rename_batch_service.dart';
import '../services/rename_batch_storage.dart';
import '../services/rename_batch_store.dart';
import '../services/archive_service.dart';
import '../services/archive_format_registry.dart';
import '../services/archive_browser_session.dart';
import '../services/archive_viewer_service.dart';
import '../services/audit_service.dart';
import '../services/cloud_storage_interface.dart' show CloudStorageClient;
import '../services/directory_cache_service.dart';
import '../services/file_operation_backend.dart';
import '../services/file_selection_pattern.dart';
import '../services/file_search_path_filter.dart';
import '../services/file_list_paths.dart';
import '../services/local_file_service.dart';
import '../services/log_service.dart';
import '../services/panel_source_service.dart';
import '../services/panel_view_mode_service.dart';
import '../utils/async_lock.dart';
import 'action_history_provider.dart';
import 'auth_provider.dart';
import 'core_providers.dart';
import 'error_provider.dart';
import 'panel_source_provider.dart';
import 'quick_search_provider.dart';
import 'recent_locations_provider.dart';
import 'native_file_operations_provider.dart';
import 'multi_cloud_provider.dart';
import 'file_collection_provider.dart';
import 'toolbar_provider.dart';
import 'transfer_provider.dart';

// SortBy and SortOrder are defined in models/sort.dart
export '../models/sort.dart';

/// The storage source that actually produced a listed file, captured before
/// the listing request. It is independent of the pane's label or dropdown.
class PanelFileOrigin {
  PanelFileOrigin._(this.source, this._isCurrent)
    : storageReference = storageReferenceForSource(source);

  PanelFileOrigin._guarded(PanelFileOrigin original, bool Function() available)
    : source = original.source,
      storageReference = original.storageReference,
      _isCurrent = (() => original.isCurrent && available());

  final PanelSource source;
  final bool Function() _isCurrent;

  /// Remains false after the captured account disconnects or changes.
  bool get isCurrent => _isCurrent();

  /// Narrow a captured capability without resolving another account or grant.
  /// The extra guard must describe source availability, so a reviewed operation
  /// can keep running independently of its originating widget or panel view.
  PanelFileOrigin withAvailabilityGuard(bool Function() available) =>
      PanelFileOrigin._guarded(this, available);

  final StorageReference storageReference;
  String get storageId => storageReference.id;
}

/// A replacement approval belongs to one reviewed pane session and its sources.
/// The public rows are fresh candidates; the captured capability stays private.
class CollectionReplacementReview {
  CollectionReplacementReview._({
    required this.items,
    required PanelNotifier owner,
    required Map<String, FileCollectionEntry> replacements,
    required Map<StorageReference, PanelFileOrigin> origins,
    required bool Function(bool checkRevision) isCurrent,
    required String? revision,
  }) : _owner = owner,
       _replacements = Map.unmodifiable(replacements),
       _origins = Map.unmodifiable(origins),
       _isCurrent = isCurrent,
       _revision = revision;

  final List<FileItem> items;
  final PanelNotifier _owner;
  final Map<String, FileCollectionEntry> _replacements;
  final Map<StorageReference, PanelFileOrigin> _origins;
  final bool Function(bool checkRevision) _isCurrent;
  final String? _revision;
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
  int _connectionGeneration = 0;
  bool _swappingViews = false;
  bool _settingSwapSource = false;
  PanelFileOrigin? _currentDirectoryOrigin;
  PanelSource? _requestedListingSource;
  ({int generation, String tabId, PanelFileOrigin origin})?
  _directoryPresentationRequest;
  AppError? _directoryListingFailure;
  late final Set<FileItem> _selection = PanelSelection(
    paged: () => _collectionPage != null,
    canMutate: () =>
        _suppressCollectionMarks || !isPagedCollection || !_collectionBusy,
    onAdd: (file) => _collectionMarkChanged(file, true),
    onRemove: (file) => _collectionMarkChanged(file, false),
    onClear: () {
      if (_suppressCollectionMarks) return;
      _collectionMarks?.desired.clear();
      _scheduleCollectionMarksSave();
    },
  );
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

  // Each tab owns its source-aware history. The revision rejects completions
  // from navigation that has been superseded by a tab or source change.
  int _navigationRevision = 0;

  /// Changes when a navigation intent starts, before access checks or visible
  /// path changes. Background followers can reject an older pending request
  /// even while a newer interactive navigation is still waiting for access.
  int get navigationIntentRevision => _navigationRevision;

  final List<_ClosedPanelTab> _closedTabs = [];
  static const maxClosedTabs = 20;
  bool _reopeningClosedTab = false;

  // Tabs
  int _tabIdCounter = 0;
  final List<PanelTab> _tabs = [];
  String _activeTabId = '';

  final _refreshLock = AsyncLock();
  final _tabSaveLock = AsyncLock();
  StorageReference? _pendingTabStorage;
  Timer? _refreshDebounce;
  late final FocusNode listFocusNode;
  bool _isDisposed = false;

  final _folderSizes = Expando<FolderSizeMeasurement>(
    'folder size observation',
  );
  final _folderSizeRequests = Expando<_FolderSizeRequest>(
    'folder size request',
  );
  final _folderSizeQueue = ListQueue<_FolderSizeRequest>();
  final _activeFolderSizeRequests = <_FolderSizeRequest>{};
  static const maxConcurrentFolderSizeScans = 2;
  static const maxInlineFolderSizeEntries = 20000;

  /// A virtual list retains original item paths across refresh and operations.
  /// Explicit navigation or the Return to folder command leaves this view.
  bool _showingSearchResults = false;
  bool get showingSearchResults => _showingSearchResults;
  String _fileListTitle = 'Search results';
  String get fileListTitle => _fileListTitle;
  PanelFileOrigin? _fileListOrigin;
  final Map<String, _FileListSnapshot> _fileListTabs = {};
  final _collectionEntries = Expando<FileCollectionEntry>(
    'saved collection row',
  );
  String? _collectionId;
  CollectionSearch? _collectionSearch;
  int _collectionRequest = 0;
  bool _collectionBusy = false;
  String _collectionProgress = '';
  FileCollectionPage? _collectionPage;
  CollectionQueryWindow? _collectionWindow;
  bool _applyingCollectionWindow = false;
  Timer? _collectionQueryTimer;
  CollectionViewProjection? _collectionProjection;
  int _collectionQueryRevision = 0;
  int get collectionQueryRevision => _collectionQueryRevision;
  final Map<String, CollectionSelectionMemory> _collectionSelectionMemories =
      {};
  int _collectionSelectionMemoryBytes = 0;
  CollectionMarkSession? _collectionMarks;
  FileCollectionStore? _collectionStoreForMarks;
  Future<void>? _pendingCollectionChanges;
  bool _suppressCollectionMarks = false;
  Timer? _collectionMarksTimer;
  String? _collectionLoadError;
  final _preparedCollectionRows = Expando<bool Function()>(
    'prepared collection row',
  );
  bool get isPagedCollection => _collectionPage != null;
  int get collectionPageIndex => _collectionWindow?.index ?? 0;
  int get collectionPageCount => _collectionWindow?.pageCount ?? 1;
  int get collectionTotalCount =>
      _collectionMarks?.manifest.summary.itemCount ??
      (_collectionId == null
          ? null
          : _ref
                .read(fileCollectionStoreProvider)
                .get(_collectionId!)
                ?.itemCount) ??
      _files?.length ??
      0;
  int get collectionPageStart => _collectionWindow?.start ?? 0;
  int get collectionMatchingCount =>
      _collectionWindow?.total ?? collectionTotalCount;
  String? get collectionLoadError => _collectionLoadError;
  String? get collectionRevision => _collectionMarks?.manifest.summary.revision;
  @visibleForTesting
  int get retainedSavedCollectionRows =>
      (isPagedCollection ? _files?.length ?? 0 : 0) +
      _fileListTabs.values
          .where((tab) => tab.collectionPageIndex != null)
          .fold<int>(0, (sum, tab) => sum + tab.files.length);
  String? get activeCollectionId =>
      _showingSearchResults ? _collectionId : null;
  bool get collectionBusy => _collectionBusy;
  String get collectionProgress => _collectionProgress;
  bool get canRerunCollectionSearch => _collectionSearch != null;
  List<FileItem> get collectionReplacements => (_files ?? const <FileItem>[])
      .where((file) => _collectionEntries[file]?.replacement == true)
      .toList();
  final Map<String, Map<(StorageReference, String), _SelectionMemoryEntry>>
  _selectionMemories = {};

  bool get canOperateOnFileList =>
      !_showingSearchResults ||
      (isPagedCollection && !_collectionBusy && _selection.isNotEmpty) ||
      (_files?.any((file) => _fileOrigins[file]?.isCurrent == true) ?? false);

  /// When non-null, the panel is browsing inside a compressed archive.
  ArchivePanelSource? _archiveSource;
  bool get isInArchive => _archiveSource != null;
  ArchivePanelSource? get archiveSource => _archiveSource;

  /// Secondary sort key for multi-key sorting (Phase 1.2).
  SortBy? _secondarySortBy;
  SortOrder _secondarySortOrder = SortOrder.ascending;
  String? _sortColumnId;
  String? _secondarySortColumnId;
  bool _applyingTabView = false;
  Timer? _viewSaveDebounce;
  String? get sortColumnId => _sortColumnId;
  String? get secondarySortColumnId => _secondarySortColumnId;
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

  /// True when Shift+F6 started the rename and the extension must be kept.
  bool _renameKeepExtension = false;
  bool get renameKeepExtension => _renameKeepExtension;

  // Whether to show hidden (dot-prefixed) files — toggle via Ctrl+.
  bool _showHiddenFiles = false;
  bool get showHiddenFiles => _showHiddenFiles;

  void toggleShowHiddenFiles() {
    _showHiddenFiles = !_showHiddenFiles;
    _rememberTabView();
    refresh();
  }

  // Free space for the current local path (populated after _loadLocalFiles)
  int? _freeBytes;
  int? get freeBytes {
    final source = directorySource;
    return source is LocalPanelSource &&
            directorySourceAvailable &&
            source.currentPath == _lastFreeSpacePath
        ? _freeBytes
        : null;
  }

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
    var connections = _ref
        .read(multiCloudProvider)
        .connections
        .map(
          (entry) => (
            entry.id,
            entry.client,
            storageReferenceForClient(entry.client),
            entry.client.isAuthenticated,
          ),
        )
        .toList();
    _ref.listen<MultiCloudNotifier>(multiCloudProvider, (_, next) {
      final current = next.connections
          .map(
            (entry) => (
              entry.id,
              entry.client,
              storageReferenceForClient(entry.client),
              entry.client.isAuthenticated,
            ),
          )
          .toList();
      if (!listEquals(connections, current)) {
        connections = current;
        _connectionGeneration++;
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
      if (prev == next || _settingSwapSource) return;
      _rememberNavigationCursor();
      final navigation = ++_navigationRevision;
      if (next.isLocal || next.isRemote) {
        final reference = storageReferenceForSource(next);
        final tab = activeTab;
        if (tab != null &&
            (tab.lockMode == TabLockMode.locked ||
                tab.lockMode == TabLockMode.newTab) &&
            _tabLocationDiffers(tab, next.currentPath, reference)) {
          // A source picker changes the source before this callback. Preserve
          // the locked tab's exact account and open the chosen source beside it.
          _createTabLocation(next.currentPath, reference);
        }
      }
      _pendingTabStorage = null;
      _leaveFileList();
      _listingGeneration++;
      _clearArchiveState();
      _log.info(
        'Source switched: ${prev?.displayName} → ${next.displayName} (path=${next.currentPath})',
      );
      final tabId = _activeTabId;
      void rememberSource() {
        if (_isDisposed ||
            navigation != _navigationRevision ||
            tabId != _activeTabId ||
            _currentDirectoryOrigin?.source != next) {
          return;
        }
        _pushHistory(currentPath);
        notifyListeners();
      }

      if (next.isLocal) {
        _localPath = next.currentPath;
        _loadLocalFiles().then((_) => rememberSource());
      } else if (next.isRemote) {
        _remotePath = next.currentPath;
        _loadRemoteFiles().then((_) => rememberSource());
      }
      notifyListeners();
    });
    _ref.listen(columnWidthsProvider(side), (_, _) => _rememberTabView());
    _ref.listen(fileColumnsProvider(side), (_, _) => _rememberTabView());
    _ref.listen(panelViewModeProvider(side), (_, _) => _rememberTabView());
    _ref.listen(
      side == PanelSide.local ? localViewModeProvider : remoteViewModeProvider,
      (_, _) => _rememberTabView(),
    );
  }

  // --- Getters ---
  List<FileItem>? get files => _files;

  bool get _hasCurrentDirectoryRequest {
    final request = _directoryPresentationRequest;
    return request != null &&
        request.generation == _listingGeneration &&
        request.tabId == _activeTabId;
  }

  /// Identity for directory-state presentation, including a saved tab whose
  /// account is unavailable. Never infer this from the pane's visual position.
  StorageReference? get directoryStorage {
    if (isInArchive || _showingSearchResults || _isFlatView) return null;
    if (_pendingTabStorage != null) return _pendingTabStorage;
    if (_verifiedListingGeneration == _listingGeneration &&
        _currentDirectoryOrigin != null) {
      return _currentDirectoryOrigin!.storageReference;
    }
    if (_hasCurrentDirectoryRequest) {
      return _directoryPresentationRequest!.origin.storageReference;
    }
    return activeTab?.storage ??
        storageReferenceForSource(_ref.read(panelSourceProvider(side)));
  }

  /// The captured session behind the current directory presentation, including
  /// an in-flight request. Keep its original availability guard even when a
  /// second live session has the same persisted storage identity.
  ///
  /// This is presentation state, not authorization for file operations; those
  /// still require a verified listing through [captureCurrentOrigin].
  PanelFileOrigin? get directoryPresentationOrigin {
    final storage = directoryStorage;
    if (storage == null) return null;
    if (_pendingTabStorage == null) {
      if (_verifiedListingGeneration == _listingGeneration &&
          _currentDirectoryOrigin != null) {
        return _currentDirectoryOrigin;
      }
      if (_hasCurrentDirectoryRequest) {
        return _directoryPresentationRequest!.origin;
      }
    }
    return resolveStorageReference(storage, activeTab?.path ?? currentPath);
  }

  /// The exact source of the current request/listing. A missing source remains
  /// missing; another connected account must not supply its empty/error state.
  PanelSource? get directorySource => directoryPresentationOrigin?.source;

  bool get directorySourceAvailable =>
      directoryPresentationOrigin?.isCurrent == true;

  bool get hasVerifiedDirectoryListing =>
      !isInArchive &&
      !_showingSearchResults &&
      !_isFlatView &&
      _pendingTabStorage == null &&
      _verifiedListingGeneration == _listingGeneration &&
      _currentDirectoryOrigin?.isCurrent == true;

  /// Failures belong to the directory request that produced them. Reading a
  /// different tab, collection, archive, or generation cannot revive one.
  AppError? get directoryListingError =>
      directoryStorage != null &&
          _pendingTabStorage == null &&
          _hasCurrentDirectoryRequest &&
          _directoryPresentationRequest!.origin.isCurrent
      ? _directoryListingFailure
      : null;

  void _beginDirectoryPresentation(int generation, PanelFileOrigin origin) {
    _directoryPresentationRequest = (
      generation: generation,
      tabId: _activeTabId,
      origin: origin,
    );
    _directoryListingFailure = null;
  }

  /// Returns an origin only for this exact object in the current verified
  /// listing. A same-path object from search, an archive, an old listing, or
  /// another account must never authorize an editor write.
  PanelFileOrigin? originForFile(FileItem file) {
    return originForOperation(file);
  }

  void _recordOrigins(Iterable<FileItem> files, PanelFileOrigin origin) {
    _currentDirectoryOrigin = origin;
    final previousTab = activeTab;
    if (previousTab != null &&
        (previousTab.lockMode == TabLockMode.locked ||
            previousTab.lockMode == TabLockMode.newTab) &&
        _tabLocationDiffers(
          previousTab,
          origin.source.currentPath,
          origin.storageReference,
        )) {
      _createTabLocation(
        origin.source.currentPath,
        origin.storageReference,
        keepListing: true,
      );
    }
    final tab = activeTab;
    if (tab != null &&
        !_showingSearchResults &&
        (tab.storage != origin.storageReference ||
            tab.path != origin.source.currentPath)) {
      tab.storage = origin.storageReference;
      tab.path = origin.source.currentPath;
      tab.collectionId = null;
      tab.updateLabel();
      _saveTabs();
    }
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
      // The browser namespace root can contain several distinct grants. Bind
      // each exact row to its own grant instead of the unscoped root listing.
      _fileOrigins[file] = _guardLocalGrant(origin, file.path);
    }
    _selection
      ..clear()
      ..addAll(selected);
    _lastSelected = lastSelected;
    _itemToScrollTo = scrollTarget;
    if (activeTab?.navigation.entries.isEmpty == true) {
      activeTab!.navigation.push(
        PanelNavigationEntry(
          path: origin.source.currentPath,
          storage: origin.storageReference,
        ),
      );
    }
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

  PanelFileOrigin _guardLocalGrant(
    PanelFileOrigin origin,
    String? path, {
    bool allowNamespaceRoot = false,
  }) {
    final local = _localFileService;
    if (!origin.source.isLocal || local is! LocalFileSourceIdentity) {
      return origin;
    }
    final identities = local as LocalFileSourceIdentity;
    final identity = path == null
        ? null
        : identities.sourceIdentityForPath(path);
    final namespaceRoot = allowNamespaceRoot && path == '/' && identity == null;
    return origin.withAvailabilityGuard(
      () =>
          path != null &&
          (identity != null || namespaceRoot) &&
          identical(identities.sourceIdentityForPath(path), identity),
    );
  }

  PanelFileOrigin _remoteOrigin(
    CloudStorageClient client,
    String providerName,
    String path,
  ) {
    final generation = _accountGeneration;
    final connectionGeneration = _connectionGeneration;
    final email = _ref.read(authProvider).userEmail;
    final primary = identical(_ref.read(authProvider).client, client);
    final reference = storageReferenceForClient(client);
    final userId = client.userId;
    final bucketId = client.bucketId;
    return PanelFileOrigin._(
      RemotePanelSource(providerName: providerName, client: client, path: path),
      () {
        if (_isDisposed ||
            (primary
                ? generation != _accountGeneration
                : connectionGeneration != _connectionGeneration) ||
            !client.isAuthenticated ||
            storageReferenceForClient(client) != reference) {
          return false;
        }
        final auth = _ref.read(authProvider);
        final connected = primary
            ? auth.isConnected &&
                  identical(auth.client, client) &&
                  auth.userEmail == email
            : _isRegisteredClient(client);
        return connected &&
            client.userId == userId &&
            client.bucketId == bucketId;
      },
    );
  }

  bool _isRegisteredClient(CloudStorageClient client) =>
      client.isAuthenticated &&
      _ref
          .read(multiCloudProvider)
          .connections
          .any((entry) => identical(entry.client, client));

  bool _isConnectedClient(CloudStorageClient client) {
    final auth = _ref.read(authProvider);
    return client.isAuthenticated &&
        ((auth.isConnected && identical(auth.client, client)) ||
            _isRegisteredClient(client));
  }

  String storageDisplayName(StorageReference storage) {
    if (storage.isLocal) return 'Local';
    for (final connection in _ref.read(multiCloudProvider).connections) {
      if (storageReferenceForClient(connection.client) == storage) {
        return '${connection.label} (${storage.provider})';
      }
    }
    final auth = _ref.read(authProvider);
    if (storageReferenceForClient(auth.client) == storage &&
        auth.userEmail?.isNotEmpty == true) {
      return '${storage.provider} · ${auth.userEmail}';
    }
    return '${storage.provider} · ${storage.accountKey.substring(0, storage.accountKey.length.clamp(0, 8))}';
  }

  /// Reconnect a persisted location only to its exact account/namespace.
  /// Provider labels and the currently selected account are never substitutes.
  PanelFileOrigin? resolveStorageReference(
    StorageReference reference,
    String path,
  ) {
    if (_isDisposed || path.isEmpty || path.contains('\u0000')) return null;
    final paths = reference.isLocal && !kIsWeb ? p.context : p.posix;
    if (!paths.isAbsolute(path)) return null;
    path = paths.normalize(path);
    if (reference.isLocal) {
      final source = LocalPanelSource(path);
      if (storageReferenceForSource(source) != reference) return null;
      return PanelFileOrigin._(source, () => !_isDisposed);
    }
    final auth = _ref.read(authProvider);
    final clients = <CloudStorageClient>{
      if (auth.isConnected) auth.client,
      ..._ref.read(multiCloudProvider).connections.map((entry) => entry.client),
    };
    for (final client in clients) {
      if (_isConnectedClient(client) &&
          storageReferenceForClient(client) == reference) {
        return _remoteOrigin(client, client.providerName, path);
      }
    }
    return null;
  }

  RemotePanelSource? _remoteSourceForListing() {
    final selected = _ref.read(panelSourceProvider(side));
    if (selected is RemotePanelSource && _isConnectedClient(selected.client)) {
      return selected;
    }
    final previous = _currentDirectoryOrigin?.source;
    if (previous is RemotePanelSource && _isConnectedClient(previous.client)) {
      return previous;
    }
    final auth = _ref.read(authProvider);
    return auth.isConnected && auth.client.isAuthenticated
        ? RemotePanelSource(
            providerName: auth.providerName,
            client: auth.client,
            path: _remotePath,
          )
        : null;
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
    _rememberTabView();
    if (isPagedCollection) _scheduleCollectionQuery();
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
    _rememberTabView();
    if (isPagedCollection) _scheduleCollectionQuery();
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
      if (isPagedCollection) _scheduleCollectionQuery();
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
      if (isPagedCollection) _scheduleCollectionQuery();
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
    if (isPagedCollection) _scheduleCollectionQuery();
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
  /// first matching entry as the user types.
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

  // --- Navigation history ---

  List<PanelNavigationEntry> get navigationHistory =>
      activeTab?.navigation.entries ?? const [];
  int get navigationHistoryIndex => activeTab?.navigation.index ?? -1;
  bool get canNavigateBack =>
      isInArchive ||
      _showingSearchResults ||
      (activeTab?.navigation.canGoBack ?? false);
  bool get canNavigateForward =>
      !isInArchive &&
      !_showingSearchResults &&
      (activeTab?.navigation.canGoForward ?? false);

  PanelNavigationEntry? _currentNavigationEntry({bool includeCursor = false}) {
    final origin = _currentDirectoryOrigin;
    if (_isDisposed ||
        isInArchive ||
        _showingSearchResults ||
        origin == null ||
        !origin.isCurrent ||
        _verifiedListingGeneration != _listingGeneration) {
      return null;
    }
    final cursor = includeCursor ? cursorItem : null;
    return PanelNavigationEntry(
      path: origin.source.currentPath,
      storage: origin.storageReference,
      cursorPath: cursor?.name == '..' ? null : cursor?.path,
      cursorObjectId: cursor?.name == '..' ? null : cursor?.uuid,
    );
  }

  void _rememberNavigationCursor() {
    final entry = _currentNavigationEntry(includeCursor: true);
    if (entry != null) activeTab?.navigation.rememberCursor(entry);
  }

  void _pushHistory(String path) {
    final entry = _currentNavigationEntry();
    if (entry == null || entry.path != path) return;
    activeTab?.navigation.push(entry);
    _ref.read(recentLocationsProvider).add(path, side, storage: entry.storage);
    _saveTabs();
  }

  Future<void> navigateBack() async {
    if (isInArchive) {
      await navigateUpArchive();
    } else if (_showingSearchResults) {
      await clearSearchResults();
    } else if (canNavigateBack) {
      await navigateToHistoryEntry(navigationHistoryIndex - 1);
    }
  }

  Future<void> navigateForward() => canNavigateForward
      ? navigateToHistoryEntry(navigationHistoryIndex + 1)
      : Future.value();

  Future<void> navigateToHistoryEntry(int index) async {
    final tab = activeTab;
    if (tab == null || index < 0 || index >= tab.navigation.entries.length) {
      return;
    }
    final entry = tab.navigation.entries[index];
    final origin = resolveStorageReference(entry.storage, entry.path);
    if (origin == null) {
      _ref
          .read(errorProvider)
          .addError(
            'Reconnect the original storage for this location.',
            code: PanelErrorCode.navigationUnavailable,
          );
      return;
    }
    _rememberNavigationCursor();
    try {
      final pending = navigateToPath(
        entry.path,
        origin: origin,
        recordHistory: false,
      );
      final navigation = _navigationRevision;
      await pending;
      if (_isDisposed ||
          navigation != _navigationRevision ||
          _activeTabId != tab.id ||
          !(_currentNavigationEntry()?.sameLocation(entry) ?? false)) {
        return;
      }
      tab.navigation.select(index);
      final matches = (_files ?? const <FileItem>[]).where(
        (file) =>
            file.name != '..' &&
            (entry.cursorObjectId != null
                ? file.uuid == entry.cursorObjectId
                : entry.cursorPath != null && file.path == entry.cursorPath),
      );
      if (matches.length == 1) _setCursorToItem(matches.single);
      _ref
          .read(recentLocationsProvider)
          .add(entry.path, side, storage: entry.storage);
      await _saveTabs();
      if (!_isDisposed) notifyListeners();
    } catch (error) {
      if (!_isDisposed) {
        _ref
            .read(errorProvider)
            .addError(
              'Could not open the saved location: $error',
              code: PanelErrorCode.navigationFailed,
              arguments: {'error': '$error'},
            );
      }
    }
  }

  /// Old unscoped entries cannot choose a current account as a substitute.
  Future<void> openRecentLocation(RecentEntry entry) async {
    final storage = entry.storage;
    final origin = storage == null
        ? null
        : resolveStorageReference(storage, entry.path);
    if (origin == null) {
      _ref
          .read(errorProvider)
          .addError(
            'Reconnect the original storage for this location.',
            code: PanelErrorCode.navigationUnavailable,
          );
      return;
    }
    try {
      await navigateToPath(entry.path, origin: origin);
    } catch (error) {
      if (!_isDisposed) {
        _ref
            .read(errorProvider)
            .addError(
              'Could not open the saved location: $error',
              code: PanelErrorCode.navigationFailed,
              arguments: {'error': '$error'},
            );
      }
    }
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
    final source = _remoteSourceForListing();
    if (source == null) {
      throw StateError('Connect to a cloud account before searching.');
    }
    return _remoteOrigin(source.client, source.providerName, _remotePath);
  }

  /// The OS clipboard supplies paths; callers stat every item before planning.
  PanelFileOrigin captureLocalClipboardOrigin(String parent) {
    if (_isDisposed || kIsWeb || !p.isAbsolute(parent)) {
      throw StateError('The local file clipboard is unavailable.');
    }
    return PanelFileOrigin._(LocalPanelSource(parent), () => !_isDisposed);
  }

  /// Only the exact verified row and its original account authorize operations.
  /// Archive members and unresolved or replacement collection rows stay blocked.
  PanelFileOrigin? originForOperation(FileItem file) {
    if (_isDisposed ||
        _isLoading ||
        isInArchive ||
        _verifiedListingGeneration != _listingGeneration ||
        file.name == '..' ||
        file.name == '.' ||
        (!(_files?.any((candidate) => identical(candidate, file)) ?? false) &&
            !(_preparedCollectionRows[file]?.call() ?? false))) {
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
    if (_showingSearchResults &&
        !canOperateOnFileList &&
        !files.every((file) => originForOperation(file) != null)) {
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

  /// Mixed collections are split into independently captured account groups.
  /// Every row must be verified before any group is allowed to start.
  Map<PanelFileOrigin, List<FileItem>> captureOperationGroups(
    List<FileItem> files,
  ) {
    if (files.isEmpty) throw StateError('Select at least one item.');
    final groups = <String, List<FileItem>>{};
    for (final file in files) {
      final origin = originForOperation(file);
      if (origin == null) {
        throw StateError(
          'Refresh or reconnect the original source of "${file.name}".',
        );
      }
      groups.putIfAbsent(origin.storageId, () => []).add(file);
    }
    return {
      for (final group in groups.values)
        captureOperationOrigin(group): List.unmodifiable(group),
    };
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
    FileCollection? collection,
    CollectionSearch? search,
    FileCollectionPage? page,
  }) {
    if (page == null) {
      _saveDepartingCollectionMarks();
      _collectionMarks = null;
      _collectionWindow = null;
    }
    _collectionPage = page;
    _collectionLoadError = null;
    final items = <FileItem>[];
    final seen = <String>{};
    PanelFileOrigin? commonOrigin = origin;
    var mixed = false;
    final saved = {
      for (final entry in collection?.entries ?? const <FileCollectionEntry>[])
        entry.key: entry,
    };
    for (final result in results) {
      if (result.name == '..' || result.name == '.') continue;
      final verified =
          originForFile?.call(result) ?? origin ?? originForOperation(result);
      if (verified != null &&
          commonOrigin != null &&
          (!_sameStorage(commonOrigin.source, verified.source) ||
              commonOrigin.storageReference != verified.storageReference)) {
        mixed = true;
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
      final storageId = verified?.storageId ?? result.storageId;
      final key =
          '${storageId ?? 'unverified'}\u0000${normalized ?? 'id:${result.uuid ?? identityHashCode(result)}'}';
      if (!seen.add(key)) continue;
      final item = result.copyWith(
        name: normalized == null
            ? paths.basename(result.name)
            : paths.basename(normalized),
        path: normalized,
        storageId: storageId,
        metadata: {
          ...?result.metadata,
          if (verified != null)
            'collectionSource': storageDisplayName(verified.storageReference)
          else if (saved[key] != null)
            'collectionSource': storageDisplayName(
              saved[key]!.reference.storage,
            ),
        },
      );
      final savedEntry = saved[key];
      if (savedEntry != null) _collectionEntries[item] = savedEntry;
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
    final tab = activeTab;
    if (tab != null &&
        (tab.lockMode == TabLockMode.locked ||
            tab.lockMode == TabLockMode.newTab) &&
        (collection == null || collection.id != tab.collectionId)) {
      _createTabLocation(
        commonOrigin?.source.currentPath ?? currentPath,
        commonOrigin?.storageReference ??
            _currentDirectoryOrigin?.storageReference,
      );
    }
    _showingSearchResults = true;
    _fileListTitle = collection?.name ?? title;
    _fileListOrigin = mixed ? null : commonOrigin;
    _collectionId = collection?.id;
    _collectionSearch = collection?.search ?? search;
    _listingGeneration++;
    _verifiedListingGeneration = _listingGeneration;
    _isLoading = false;
    _isFlatView = false;
    _clearArchiveState();
    _selection.clear();
    _lastSelected = null;
    _itemToScrollTo = null;
    _filterQuery = '';
    _isTypeahead = false;
    _typeaheadResetTimer?.cancel();
    _files = items;
    if (collection != null) {
      _selection.addAll(
        items.where(
          (file) => collection.selectedKeys.contains(
            '${file.storageId}\u0000${file.path}',
          ),
        ),
      );
    }
    _sortFiles();
    _cursorIndex = items.isEmpty ? -1 : 0;
    _rememberFileListTab();
    _saveTabs();
    notifyListeners();
  }

  void _rememberFileListTab() {
    if (!_showingSearchResults || _activeTabId.isEmpty) return;
    _fileListTabs[_activeTabId] = _FileListSnapshot(
      files: isPagedCollection ? const [] : List.of(_files ?? []),
      title: _fileListTitle,
      origin: _fileListOrigin,
      selection: isPagedCollection ? const {} : Set.of(_selection),
      cursor: isPagedCollection ? null : cursorItem,
      collectionId: _collectionId,
      search: _collectionSearch,
      collectionPageIndex: isPagedCollection ? collectionPageIndex : null,
    );
  }

  void _collectionMarkChanged(FileItem file, bool selected) {
    if (_suppressCollectionMarks) return;
    final marks = _collectionMarks;
    if (marks == null) return;
    final key = collectionRowKey(file);
    final page = marks.rowPages[key];
    if (page == null) return;
    if (selected) {
      marks.desired[key] = page;
    } else {
      marks.desired.remove(key);
    }
    _scheduleCollectionMarksSave();
  }

  void _scheduleCollectionMarksSave() {
    if (_suppressCollectionMarks || _collectionMarks == null) return;
    _collectionMarksTimer?.cancel();
    final session = _collectionMarks!;
    _collectionMarksTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(
        _persistCollectionMarks(session).catchError((Object error) {
          if (!_isDisposed) {
            _collectionLoadError = '$error';
            _ref
                .read(errorProvider)
                .addError('Could not save collection marks: $error');
            notifyListeners();
          }
        }),
      );
    });
  }

  Future<void> _persistCollectionMarks(CollectionMarkSession session) async {
    final manifest = await session.flush(
      _ref.read(fileCollectionStoreProvider),
    );
    if (_isDisposed || !identical(session, _collectionMarks)) return;
    final page = _collectionPage;
    if (page != null && page.index < manifest.pages.length) {
      _collectionPage = FileCollectionPage(
        manifest: manifest,
        index: page.index,
        collection: page.collection,
      );
    }
    notifyListeners();
  }

  Future<void> flushCollectionMarks() async {
    _collectionMarksTimer?.cancel();
    final session = _collectionMarks;
    if (session != null) await _persistCollectionMarks(session);
  }

  void _saveDepartingCollectionMarks() {
    _collectionMarksTimer?.cancel();
    final session = _collectionMarks;
    if (session == null) return;
    final store = _collectionStoreForMarks;
    if (store == null) return;
    unawaited(
      session.flush(store).catchError((Object error) {
        if (!_isDisposed) {
          _ref
              .read(errorProvider)
              .addError('Could not save collection marks: $error');
        }
        return session.manifest;
      }),
    );
  }

  /// Pin an interactive operation before its first asynchronous read. Paged
  /// selections resolve off-page rows later, but may never substitute a newly
  /// connected account or another tab while doing so.
  bool Function() captureOperationSession() {
    final tab = _activeTabId;
    final listing = _listingGeneration;
    final collection = _collectionId;
    final session = _collectionMarks;
    final account = _accountGeneration;
    final connections = _connectionGeneration;
    return () =>
        !_isDisposed &&
        tab == _activeTabId &&
        listing == _listingGeneration &&
        collection == _collectionId &&
        identical(session, _collectionMarks) &&
        account == _accountGeneration &&
        connections == _connectionGeneration;
  }

  /// Capture all requested original rows, including marks outside the visible
  /// page. No capability is returned if even one original is unavailable,
  /// replaced, or changed accounts while the pages were being resolved.
  Future<List<FileItem>> prepareOperationFiles(Iterable<FileItem> files) =>
      _prepareCollectionFiles(files);

  Future<List<FileItem>> _prepareCollectionFiles(
    Iterable<FileItem> files, {
    int? reuseRequest,
  }) async {
    final requested = files.toList();
    if (!isPagedCollection || requested.isEmpty) return requested;
    if (_collectionBusy && reuseRequest == null) {
      throw StateError('Wait for the collection to finish loading.');
    }
    final session = _collectionMarks!;
    final tab = _activeTabId;
    final generation = _listingGeneration;
    if (reuseRequest == null) {
      final issued = Set<FileItem>.identity()
        ..addAll(_selection)
        ..addAll(_files ?? const []);
      if (requested.any(
        (file) =>
            !issued.contains(file) &&
            !(_preparedCollectionRows[file]?.call() ?? false),
      )) {
        throw StateError(
          'The requested collection rows belong to an older view. Select their current originals again.',
        );
      }
    }
    await flushCollectionMarks();
    if (_isDisposed ||
        !identical(session, _collectionMarks) ||
        tab != _activeTabId ||
        generation != _listingGeneration) {
      throw StateError(
        'The collection view changed while preparing the operation.',
      );
    }
    final manifest = session.manifest;
    final request = reuseRequest ?? ++_collectionRequest;
    bool current() =>
        !_isDisposed &&
        identical(session, _collectionMarks) &&
        request == _collectionRequest &&
        tab == _activeTabId &&
        generation == _listingGeneration &&
        _ref
                .read(fileCollectionStoreProvider)
                .get(manifest.summary.id)
                ?.revision ==
            manifest.summary.revision;
    final wanted = {for (final file in requested) collectionRowKey(file)};
    final pages = <int>{};
    for (final key in wanted) {
      final page = session.rowPages[key];
      if (page == null) {
        throw StateError(
          'A requested row does not belong to this captured collection.',
        );
      }
      pages.add(page);
    }
    final origins = <String, PanelFileOrigin>{};
    final backends = <String, FileOperationBackend>{};
    FileOperationBackend? resolve(StorageReference storage, String path) {
      if (backends.containsKey(storage.id)) return backends[storage.id];
      final origin = resolveStorageReference(storage, path);
      if (origin == null) return null;
      origins[storage.id] = origin;
      return backends[storage.id] = fileOperationBackend(
        source: origin.source,
        local: _localFileService,
        isCurrent: () => current() && origin.isCurrent,
      );
    }

    final resolved = <String, FileItem>{};
    _collectionBusy = true;
    _collectionProgress = '0 / ${wanted.length}';
    notifyListeners();
    try {
      for (final index in pages) {
        if (!current()) {
          throw StateError(
            'The collection changed while preparing the operation.',
          );
        }
        final page = await _ref
            .read(fileCollectionStoreProvider)
            .loadPage(
              manifest.summary.id,
              index,
              revision: manifest.summary.revision,
            );
        final subset = page.collection.copyWith(
          entries: page.collection.entries
              .where((entry) => wanted.contains(entry.key))
              .toList(),
        );
        final refreshed = await const FileCollectionService().refresh(
          subset,
          resolve,
          isCancelled: () => !current(),
          onProgress: (done, _) {
            if (current()) {
              _collectionProgress =
                  '${resolved.length + done} / ${wanted.length}';
              notifyListeners();
            }
          },
        );
        for (final entry in refreshed.collection.entries) {
          if (!refreshed.verifiedKeys.contains(entry.key)) {
            throw StateError(
              'Cannot use "${entry.reference.path}": ${entry.detail ?? 'refresh the original source or review its replacement.'}',
            );
          }
          resolved[entry.key] = entry.file;
        }
      }
      if (!current() ||
          resolved.length != wanted.length ||
          origins.values.any((origin) => !origin.isCurrent)) {
        throw StateError(
          'The complete marked selection could not be verified. Reload its original sources.',
        );
      }
      final result = [
        for (final file in requested) resolved[collectionRowKey(file)]!,
      ];
      for (final file in result) {
        final origin = origins[file.storageId]!;
        final paths = origin.source.isLocal && !kIsWeb ? p.context : p.posix;
        _fileOrigins[file] = _originAt(origin, paths.dirname(file.path!));
        _preparedCollectionRows[file] = current;
      }
      return result;
    } finally {
      if (reuseRequest == null &&
          !_isDisposed &&
          request == _collectionRequest) {
        _collectionBusy = false;
        _collectionProgress = '';
        notifyListeners();
      }
    }
  }

  /// Drag hover is an identity check, never an I/O authorization. Drop handlers
  /// still resolve and verify every returned original before opening a plan.
  bool recognizesCollectionRows(Iterable<FileItem> files) {
    if (!isPagedCollection || _collectionBusy) return false;
    final session = _collectionMarks!;
    final known = Set<FileItem>.identity()
      ..addAll(_selection)
      ..addAll(_files ?? const []);
    return files.isNotEmpty &&
        files.every(
          (file) =>
              known.contains(file) &&
              session.rowPages.containsKey(collectionRowKey(file)),
        );
  }

  FileCollection _collectionSnapshot({
    required String id,
    required String name,
    required Iterable<FileItem> files,
    required Set<FileItem> selection,
    CollectionSearch? search,
  }) {
    final entries = <FileCollectionEntry>[];
    final selected = <String>{};
    for (final file in files) {
      if (file.name == '..' || file.name == '.') continue;
      var entry = _collectionEntries[file];
      if (entry == null) {
        final origin = _fileOrigins[file];
        if (origin == null) {
          throw StateError(
            'The original source of "${file.name}" was never verified.',
          );
        }
        final paths = origin.source.isRemote || kIsWeb ? p.posix : p.context;
        entry = FileCollectionService.capture(
          file.copyWith(
            path: file.path ?? paths.join(origin.source.currentPath, file.name),
          ),
          origin.storageReference,
        );
      }
      entries.add(entry);
      if (selection.contains(file)) selected.add(entry.key);
    }
    return FileCollection(
      id: id,
      name: name,
      entries: entries,
      selectedKeys: selected,
      search: search,
    );
  }

  /// Save the current rows and marks. Authentication and live clients are never serialized.
  Future<String> saveCurrentCollection(
    String name, {
    bool selectedOnly = false,
    bool createNew = false,
  }) async {
    final tabId = _activeTabId;
    final generation = _listingGeneration;
    if (isPagedCollection) {
      final session = _collectionMarks!;
      final original = session.manifest.summary.id;
      final pageIndex = collectionPageIndex;
      await flushCollectionMarks();
      if (_isDisposed ||
          tabId != _activeTabId ||
          generation != _listingGeneration ||
          !identical(session, _collectionMarks)) {
        throw StateError('The collection changed. Reopen it before saving.');
      }
      final store = _ref.read(fileCollectionStoreProvider);
      if (selectedOnly || createNew) {
        final id = const Uuid().v4();
        await store.copyCollection(
          original,
          id: id,
          name: name.trim(),
          selectedOnly: selectedOnly,
        );
        if (!selectedOnly &&
            !_isDisposed &&
            tabId == _activeTabId &&
            generation == _listingGeneration &&
            identical(session, _collectionMarks)) {
          await openCollection(id, pageIndex: pageIndex);
        }
        return id;
      }
      await renameSavedCollection(original, name.trim());
      return original;
    }
    final id = !selectedOnly && !createNew
        ? _collectionId ?? const Uuid().v4()
        : const Uuid().v4();
    final store = _ref.read(fileCollectionStoreProvider);
    final updating = !selectedOnly && !createNew && _collectionId != null;
    final revision = updating ? store.get(id)?.revision : null;
    if (updating && revision == null) {
      throw StateError('The saved collection no longer exists.');
    }
    final collection = _collectionSnapshot(
      id: id,
      name: name.trim(),
      files: selectedOnly ? _selection : _files ?? const [],
      selection: _selection,
      search: selectedOnly ? null : _collectionSearch,
    );
    await store.save(
      collection,
      expectedRevision: revision,
      isCancelled: updating
          ? () =>
                _isDisposed ||
                tabId != _activeTabId ||
                generation != _listingGeneration
          : null,
    );
    if (!_isDisposed &&
        tabId == _activeTabId &&
        generation == _listingGeneration &&
        _showingSearchResults &&
        !selectedOnly) {
      _collectionId = id;
      _fileListTitle = collection.name;
      activeTab?.collectionId = id;
      await openCollection(id);
    }
    return id;
  }

  Future<void> appendToCollection(String id, {bool selectedOnly = true}) async {
    final panels = _collectionPanels();
    if (isPagedCollection) {
      final session = _collectionMarks!;
      final sourceId = session.manifest.summary.id;
      await flushCollectionMarks();
      if (_isDisposed || !identical(session, _collectionMarks)) {
        throw StateError(
          'The collection changed. Reopen it before continuing.',
        );
      }
      await _prepareCollectionMutation(id, panels: panels);
      await _ref
          .read(fileCollectionStoreProvider)
          .appendCollection(id, sourceId, selectedOnly: selectedOnly);
      await _synchronizeCollectionPanels(id, panels: panels);
      return;
    }
    final additions = _collectionSnapshot(
      id: 'pending',
      name: 'Pending',
      files: selectedOnly ? _selection : _files ?? const [],
      selection: _selection,
    );
    await _prepareCollectionMutation(id, panels: panels);
    await _ref.read(fileCollectionStoreProvider).append(id, additions);
    await _synchronizeCollectionPanels(id, panels: panels);
  }

  List<PanelNotifier> _collectionPanels() => [
    this,
    _ref.read(panelProvider(oppositePanel(side))),
  ];

  Future<void> _prepareCollectionMutation(
    String id, {
    required List<PanelNotifier> panels,
    bool preserveMarks = true,
  }) async {
    for (final panel in panels) {
      if (panel._isDisposed || panel.activeCollectionId != id) continue;
      panel._collectionRequest++;
      panel._collectionBusy = false;
      panel._collectionQueryTimer?.cancel();
      panel._collectionMarksTimer?.cancel();
      if (preserveMarks) await panel.flushCollectionMarks();
    }
  }

  Future<void> renameSavedCollection(String id, String name) async {
    final panels = _collectionPanels();
    await _prepareCollectionMutation(id, panels: panels);
    await _ref.read(fileCollectionStoreProvider).rename(id, name.trim());
    await _synchronizeCollectionPanels(id, panels: panels);
  }

  Future<void> removeSavedCollection(String id) async {
    final panels = _collectionPanels();
    await _prepareCollectionMutation(id, panels: panels, preserveMarks: false);
    await _ref.read(fileCollectionStoreProvider).remove(id);
    await _synchronizeCollectionPanels(id, panels: panels);
  }

  Future<void> _synchronizeCollectionPanels(
    String id, {
    required List<PanelNotifier> panels,
  }) async {
    // Invalidate all views before awaiting a reload in either pane. A slow
    // provider cannot leave the other pane operating on obsolete references.
    for (final panel in panels) {
      if (panel._isDisposed) continue;
      final current = panel._ref.read(fileCollectionStoreProvider).get(id);
      for (final tab in panel._tabs) {
        if (tab.collectionId != id &&
            panel._fileListTabs[tab.id]?.collectionId != id) {
          continue;
        }
        panel._fileListTabs.remove(tab.id);
        tab.collectionId = current?.id;
        if (current == null) {
          if (tab.lockedCollectionId == id) tab.lockedCollectionId = null;
          tab.updateLabel();
        } else {
          tab.label = tab.customLabel ?? current.name;
        }
      }
      if (panel.activeCollectionId == id) {
        panel._collectionRequest++;
        panel._collectionBusy = false;
        panel._collectionMarksTimer?.cancel();
        panel._collectionQueryTimer?.cancel();
      }
      panel.notifyListeners();
    }
    for (final panel in panels) {
      if (panel._isDisposed) continue;
      if (panel.activeCollectionId == id) {
        final index = panel.collectionPageIndex;
        final current = panel._ref.read(fileCollectionStoreProvider).get(id);
        panel._collectionMarks = null;
        panel._collectionPage = null;
        panel._collectionWindow = null;
        if (current == null) {
          panel._leaveFileList();
          panel._files = null;
          panel._selection.clear();
          await panel._restoreSelectedTab();
        } else {
          await panel.openCollection(id, pageIndex: index);
        }
      }
      if (!panel._isDisposed) {
        await panel._saveTabs();
        panel.notifyListeners();
      }
    }
  }

  Future<void> openCollection(
    String id, {
    bool newTab = false,
    int pageIndex = 0,
    bool Function()? canContinue,
  }) async {
    if (_isDisposed || !(canContinue?.call() ?? true)) return;
    final requestedTab = _activeTabId;
    final requestedNavigation = _navigationRevision;
    var request = ++_collectionRequest;
    bool stillRequested() =>
        !_isDisposed &&
        requestedTab == _activeTabId &&
        requestedNavigation == _navigationRevision &&
        request == _collectionRequest &&
        (canContinue?.call() ?? true);
    await flushCollectionMarks();
    if (!stillRequested()) return;
    final store = _ref.read(fileCollectionStoreProvider);
    _collectionStoreForMarks = store;
    await store.ready;
    if (!stillRequested()) return;
    final summary = store.get(id);
    if (summary == null) {
      throw StateError('The saved collection no longer exists.');
    }
    final previousTab = activeTab;
    if (newTab ||
        (previousTab != null &&
            previousTab.collectionId != id &&
            (previousTab.lockMode == TabLockMode.locked ||
                previousTab.lockMode == TabLockMode.newTab))) {
      _createTabLocation(
        currentPath,
        _currentDirectoryOrigin?.storageReference,
      );
    }
    request = ++_collectionRequest;
    final tab = _activeTabId;
    bool cancelled() =>
        _isDisposed ||
        request != _collectionRequest ||
        tab != _activeTabId ||
        requestedNavigation != _navigationRevision ||
        !(canContinue?.call() ?? true);
    _collectionBusy = true;
    _collectionLoadError = null;
    _collectionProgress = '';
    notifyListeners();
    try {
      final manifest = await store.manifest(id);
      final marks = CollectionMarkSession(manifest);
      final selected = <FileItem>[];
      for (var index = 0; index < manifest.pages.length; index++) {
        if (cancelled()) return;
        if (manifest.pages[index].selectedCount == 0) continue;
        final page = await store.loadPage(
          id,
          index,
          revision: manifest.summary.revision,
        );
        for (final entry in page.collection.entries) {
          if (!page.collection.selectedKeys.contains(entry.key)) continue;
          marks.rowPages[entry.key] = index;
          marks.saved[entry.key] = index;
          marks.desired[entry.key] = index;
          selected.add(_compactCollectionMark(entry.file));
        }
        _collectionProgress =
            '${selected.length} / ${manifest.summary.selectedCount}';
        notifyListeners();
      }
      if (cancelled()) return;
      _collectionWindow = null;
      final window = await _readCollectionWindow(
        manifest,
        pageIndex,
        cancelled: cancelled,
      );
      if (cancelled()) return;
      _suppressCollectionMarks = true;
      _selection.clear();
      _collectionPage = FileCollectionPage(
        manifest: manifest,
        index: 0,
        collection: FileCollection(
          id: id,
          name: manifest.summary.name,
          entries: const [],
          search: manifest.search,
        ),
      );
      _collectionMarks = marks;
      _selection.addAll(selected);
      _suppressCollectionMarks = false;
      await _displayCollectionWindow(window, cancelled: cancelled);
      if (cancelled()) return;
      activeTab?.collectionId = id;
      _rememberFileListTab();
      await _saveTabs();
    } catch (error) {
      if (!cancelled()) {
        _collectionLoadError = '$error';
        notifyListeners();
      }
      rethrow;
    } finally {
      if (!cancelled()) {
        _collectionBusy = false;
        _collectionProgress = '';
        notifyListeners();
      }
    }
  }

  static FileItem _compactCollectionMark(FileItem file) => FileItem(
    name: file.name,
    path: file.path,
    uuid: file.uuid,
    storageId: file.storageId,
    isFolder: file.isFolder,
    size: file.size,
    updatedAt: file.updatedAt,
  );

  PanelFileOrigin? _resolveCollectionDirectory(
    StorageReference storage,
    String memberPath, {
    CollectionSearch? search,
  }) {
    final paths = storage.isLocal && !kIsWeb ? p.context : p.posix;
    final previous = _fileListOrigin;
    final directory = search?.storage == storage
        ? search!.directory
        : previous?.storageReference == storage
        ? previous!.source.currentPath
        : paths.dirname(memberPath);
    return resolveStorageReference(storage, directory);
  }

  Future<void> _displayCollectionWindow(
    CollectionQueryWindow window, {
    required bool Function() cancelled,
  }) async {
    final page = FileCollectionPage(
      manifest: window.manifest,
      index: 0,
      collection: FileCollection(
        id: window.manifest.summary.id,
        name: window.manifest.summary.name,
        entries: window.rows.map((row) => row.entry).toList(),
        selectedKeys: window.rows
            .where(
              (row) => _collectionMarks!.desired.containsKey(row.entry.key),
            )
            .map((row) => row.entry.key)
            .toSet(),
        search: window.manifest.search,
      ),
    );
    final origins = <String, PanelFileOrigin>{};
    final backends = <String, FileOperationBackend>{};
    FileOperationBackend? resolve(StorageReference storage, String path) {
      if (backends.containsKey(storage.id)) return backends[storage.id];
      final origin = _resolveCollectionDirectory(
        storage,
        path,
        search: window.manifest.search,
      );
      if (origin == null) return null;
      origins[storage.id] = origin;
      return backends[storage.id] = fileOperationBackend(
        source: origin.source,
        local: _localFileService,
        isCurrent: () => !cancelled() && origin.isCurrent,
      );
    }

    final refreshed = await const FileCollectionService().refresh(
      page.collection,
      resolve,
      isCancelled: cancelled,
      onProgress: (done, total) {
        if (!cancelled()) {
          _collectionProgress = '$done / $total';
          notifyListeners();
        }
      },
    );
    if (cancelled()) return;
    final selected = _selection.map(_compactCollectionMark).toList();
    final filter = _filterQuery;
    final typeahead = _isTypeahead;
    final mode = _typeaheadMode;
    _suppressCollectionMarks = true;
    _applyingCollectionWindow = true;
    try {
      _collectionWindow = window;
      showSearchResults(
        refreshed.collection.entries
            .map(
              (entry) => entry.file.copyWith(
                metadata: {
                  ...?entry.file.metadata,
                  'collectionState': entry.state.name,
                  if (entry.detail != null) 'collectionDetail': entry.detail,
                  'collectionReplacement': entry.replacement,
                },
              ),
            )
            .toList(),
        collection: refreshed.collection,
        page: FileCollectionPage(
          manifest: page.manifest,
          index: page.index,
          collection: refreshed.collection,
        ),
        originForFile: (file) =>
            refreshed.verifiedKeys.contains(collectionRowKey(file))
            ? origins[file.storageId]
            : null,
      );
      if (page.summary.sourceCount > 1) _fileListOrigin = null;
      final marks = _collectionMarks!;
      for (final row in window.rows) {
        marks.rowPages[row.entry.key] = row.pageIndex;
      }
      _selection
        ..clear()
        ..addAll(selected);
      for (final file in _files ?? const <FileItem>[]) {
        if (marks.desired.containsKey(collectionRowKey(file))) {
          _selection.add(file);
        }
      }
      _filterQuery = filter;
      _isTypeahead = typeahead;
      _typeaheadMode = mode;
      _resetCursor();
    } finally {
      _suppressCollectionMarks = false;
      _applyingCollectionWindow = false;
    }
    _rememberFileListTab();
    notifyListeners();
  }

  Future<void> loadCollectionPage(int index) async {
    if (!isPagedCollection || _collectionBusy) return;
    if (index < 0 || index >= collectionPageCount) return;
    await flushCollectionMarks();
    final request = ++_collectionRequest;
    final session = _collectionMarks!;
    bool cancelled() =>
        _isDisposed ||
        request != _collectionRequest ||
        !identical(session, _collectionMarks);
    _collectionBusy = true;
    _collectionLoadError = null;
    notifyListeners();
    try {
      final window = await _readCollectionWindow(
        session.manifest,
        index,
        cancelled: cancelled,
      );
      if (cancelled()) return;
      await _displayCollectionWindow(window, cancelled: cancelled);
    } catch (error) {
      if (!cancelled()) _collectionLoadError = '$error';
      rethrow;
    } finally {
      if (!cancelled()) {
        _collectionBusy = false;
        _collectionProgress = '';
        notifyListeners();
      }
    }
  }

  bool Function(FileItem) _collectionFilter() {
    if (!_isFiltering) return (_) => true;
    final settings = _ref.read(quickSearchSettingsProvider);
    final query = settings.caseSensitive
        ? _filterQuery
        : _filterQuery.toLowerCase();
    return (file) => _matchesQuickSearch(file, query, settings);
  }

  Future<CollectionQueryWindow> _readCollectionWindow(
    FileCollectionManifest manifest,
    int index, {
    required bool Function() cancelled,
  }) async {
    final store = _ref.read(fileCollectionStoreProvider);
    final compare = _fileSortComparator();
    final matches = _collectionFilter();
    final projection = _collectionProjection;
    Future<CollectionQueryWindow> scan({
      FileCollectionEntry? after,
      FileCollectionEntry? before,
      bool last = false,
    }) => FileCollectionQuery().run(
      store,
      manifest,
      compare: compare,
      matches: matches,
      matchesEntry: projection?.matches,
      compareEntry: projection?.compare,
      after: after,
      before: before,
      last: last,
      isCancelled: cancelled,
      onProgress: (done, total) {
        if (!cancelled()) {
          _collectionProgress = '$done / $total';
          notifyListeners();
        }
      },
    );
    final current = _collectionWindow;
    if (index > 0 &&
        current != null &&
        current.manifest.summary.id == manifest.summary.id &&
        current.rows.isNotEmpty) {
      if (index == current.pageCount - 1) return scan(last: true);
      if (index == current.index + 1) {
        return scan(after: current.rows.last.entry);
      }
      if (index == current.index - 1) {
        return scan(before: current.rows.first.entry);
      }
    }
    var window = await scan();
    if (index >= window.pageCount - 1 && index > 0) return scan(last: true);
    for (
      var position = 0;
      position < index && window.rows.isNotEmpty;
      position++
    ) {
      window = await scan(after: window.rows.last.entry);
    }
    return window;
  }

  void _scheduleCollectionQuery() {
    if (!isPagedCollection || _applyingCollectionWindow) return;
    _collectionQueryRevision++;
    _collectionRequest++;
    _collectionBusy = false;
    _collectionQueryTimer?.cancel();
    _collectionQueryTimer = Timer(const Duration(milliseconds: 150), () {
      unawaited(
        reloadCollectionQuery().catchError((Object error) {
          if (!_isDisposed) {
            _collectionLoadError = '$error';
            notifyListeners();
          }
        }),
      );
    });
  }

  void setCollectionProjection(
    Object owner, {
    required Object signature,
    required bool Function(FileCollectionEntry) matches,
    required Comparator<FileCollectionEntry> compare,
  }) {
    if (_isDisposed) return;
    final previous = _collectionProjection;
    if (previous != null &&
        identical(previous.owner, owner) &&
        previous.signature == signature) {
      return;
    }
    _collectionProjection = CollectionViewProjection(
      owner: owner,
      signature: signature,
      matches: matches,
      compare: compare,
    );
    _scheduleCollectionQuery();
  }

  void clearCollectionProjection(Object owner) {
    if (_isDisposed || !identical(_collectionProjection?.owner, owner)) return;
    _collectionProjection = null;
    _scheduleCollectionQuery();
  }

  Future<void> reloadCollectionQuery() async {
    if (!isPagedCollection) return;
    _collectionQueryTimer?.cancel();
    _collectionWindow = null;
    await loadCollectionPage(0);
  }

  Future<void> reloadSavedCollection() async {
    final id = _collectionId;
    if (id == null || _collectionBusy) return;
    final index = collectionPageIndex;
    _collectionMarksTimer?.cancel();
    _collectionMarks = null;
    _collectionPage = null;
    await _ref.read(fileCollectionStoreProvider).reload();
    await openCollection(id, pageIndex: index);
  }

  Future<CollectionReplacementReview?>
  captureCollectionReplacementReview() async {
    if (!_showingSearchResults || _collectionBusy || _isDisposed) return null;
    await flushCollectionMarks();
    if (!_showingSearchResults || _collectionBusy || _isDisposed) return null;
    final rows = collectionReplacements;
    if (rows.isEmpty) return null;
    final entries = [for (final row in rows) _collectionEntries[row]!];
    final tab = _activeTabId;
    final generation = _listingGeneration;
    final session = _collectionMarks;
    final id = _collectionId;
    final store = _ref.read(fileCollectionStoreProvider);
    final revision = id == null ? null : store.get(id)?.revision;
    if (id != null && revision == null) {
      throw StateError('The saved collection no longer exists.');
    }
    final origins = <StorageReference, PanelFileOrigin>{};
    bool current(bool checkRevision) =>
        !_isDisposed &&
        _showingSearchResults &&
        tab == _activeTabId &&
        generation == _listingGeneration &&
        id == _collectionId &&
        identical(session, _collectionMarks) &&
        (!checkRevision || id == null || store.get(id)?.revision == revision) &&
        rows.every(
          (row) =>
              (_files?.any((current) => identical(current, row)) ?? false) &&
              _collectionEntries[row]?.replacement == true,
        ) &&
        origins.values.every((origin) => origin.isCurrent);
    final backends = <StorageReference, FileOperationBackend>{};
    FileOperationBackend? resolve(StorageReference storage, String path) {
      if (backends.containsKey(storage)) return backends[storage];
      final origin = _resolveCollectionDirectory(
        storage,
        path,
        search: _collectionSearch,
      );
      if (origin == null || !origin.isCurrent) return null;
      origins[storage] = origin;
      return backends[storage] = fileOperationBackend(
        source: origin.source,
        local: _localFileService,
        isCurrent: () => current(true) && origin.isCurrent,
      );
    }

    final result = await const FileCollectionService().refresh(
      FileCollection(
        id: id ?? 'replacement-review',
        name: _fileListTitle,
        entries: entries,
      ),
      resolve,
      acceptReplacements: true,
      acceptedReplacementKeys: entries.map((entry) => entry.key).toSet(),
      isCancelled: () => !current(true),
    );
    if (!current(true) || result.verifiedKeys.length != entries.length) {
      throw StateError(
        'The collection changed. Refresh it and review its replacements again.',
      );
    }
    return CollectionReplacementReview._(
      items: List.unmodifiable(
        result.collection.entries.map((entry) => entry.file),
      ),
      owner: this,
      replacements: {
        for (final entry in result.collection.entries) entry.key: entry,
      },
      origins: origins,
      isCurrent: current,
      revision: revision,
    );
  }

  Future<void> acceptCollectionReplacements(
    CollectionReplacementReview review,
  ) async {
    if (!identical(review._owner, this) || !review._isCurrent(true)) {
      throw StateError(
        'The collection changed. Review its replacement items again.',
      );
    }
    await refreshCollectionItems(
      acceptReplacements: true,
      acceptedReplacementKeys: review._replacements.keys.toSet(),
      review: review,
    );
  }

  void _checkReviewedReplacementResult(
    FileCollection page,
    CollectionRefreshResult result,
    CollectionReplacementReview? review,
  ) {
    if (review == null) return;
    final expected = page.entries
        .map((entry) => entry.key)
        .where(review._replacements.containsKey);
    if (!result.verifiedKeys.containsAll(expected)) {
      throw StateError(
        'A replacement changed after review. Refresh the collection and review it again.',
      );
    }
  }

  Future<void> _refreshPagedCollection({
    required bool rerunSearch,
    required bool acceptReplacements,
    Set<String>? acceptedReplacementKeys,
    CollectionReplacementReview? review,
  }) async {
    final session = _collectionMarks!;
    final tab = _activeTabId;
    final generation = _listingGeneration;
    await flushCollectionMarks();
    if (_isDisposed ||
        !identical(session, _collectionMarks) ||
        tab != _activeTabId ||
        generation != _listingGeneration) {
      throw StateError('The collection changed. Refresh it again.');
    }
    if (review != null && !review._isCurrent(true)) {
      throw StateError(
        'The collection changed. Review its replacement items again.',
      );
    }
    final store = _ref.read(fileCollectionStoreProvider);
    final id = session.manifest.summary.id;
    final pageIndex = collectionPageIndex;
    final request = ++_collectionRequest;
    bool cancelled() =>
        _isDisposed ||
        request != _collectionRequest ||
        !identical(session, _collectionMarks) ||
        (review != null && !review._isCurrent(false));
    _collectionBusy = true;
    _collectionLoadError = null;
    _collectionProgress = '';
    notifyListeners();
    final backends = <String, FileOperationBackend>{};
    FileOperationBackend? resolve(StorageReference storage, String path) {
      if (backends.containsKey(storage.id)) return backends[storage.id];
      final origin = review == null
          ? _resolveCollectionDirectory(
              storage,
              path,
              search: session.manifest.search,
            )
          : review._origins[storage];
      if (origin == null) return null;
      return backends[storage.id] = fileOperationBackend(
        source: origin.source,
        local: _localFileService,
        isCurrent: () => !cancelled() && origin.isCurrent,
      );
    }

    try {
      const service = FileCollectionService();
      if (rerunSearch) {
        final metadata = FileCollection(
          id: id,
          name: _fileListTitle,
          entries: const [],
          selectedKeys: session.desired.keys.toSet(),
          search: session.manifest.search,
        );
        final result = await service.rerun(
          metadata,
          resolve,
          isCancelled: cancelled,
          onProgress: (scanned, _) {
            if (!cancelled()) {
              _collectionProgress = '$scanned';
              notifyListeners();
            }
          },
        );
        if (cancelled()) return;
        await store.save(
          result.collection,
          expectedRevision: session.manifest.summary.revision,
          isCancelled: cancelled,
        );
      } else {
        var complete = 0;
        await store.transform(
          id,
          (page) async {
            final inspected = review == null
                ? page
                : page.copyWith(
                    entries: page.entries
                        .where(
                          (entry) =>
                              review._replacements.containsKey(entry.key),
                        )
                        .toList(),
                  );
            if (review != null && inspected.entries.isEmpty) return page;
            final result = await service.refresh(
              inspected,
              resolve,
              isCancelled: cancelled,
              acceptReplacements: acceptReplacements,
              acceptedReplacementKeys: acceptedReplacementKeys,
              reviewedReplacements: review?._replacements ?? const {},
              onProgress: (done, _) {
                if (!cancelled()) {
                  _collectionProgress =
                      '${complete + done} / ${session.manifest.summary.itemCount}';
                  notifyListeners();
                }
              },
            );
            _checkReviewedReplacementResult(inspected, result, review);
            complete += page.entries.length;
            if (review == null) return result.collection;
            final replacements = {
              for (final entry in result.collection.entries) entry.key: entry,
            };
            return page.copyWith(
              entries: [
                for (final entry in page.entries)
                  replacements[entry.key] ?? entry,
              ],
            );
          },
          isCancelled: cancelled,
          expectedRevision: session.manifest.summary.revision,
        );
      }
      if (cancelled()) return;
      // The committed revision is authoritative; old page/mark identities must
      // not be used to save again while reopening it.
      _collectionMarks = null;
      _collectionPage = null;
      await openCollection(id, pageIndex: pageIndex);
    } catch (error) {
      if (!cancelled()) _collectionLoadError = '$error';
      rethrow;
    } finally {
      if (!cancelled()) {
        _collectionBusy = false;
        _collectionProgress = '';
        notifyListeners();
      }
    }
  }

  void cancelCollectionRefresh() {
    _collectionRequest++;
    _collectionBusy = false;
    notifyListeners();
  }

  /// Refresh saved paths. Rerunning a saved query is an explicit separate action.
  Future<void> refreshCollectionItems({
    bool rerunSearch = false,
    bool acceptReplacements = false,
    Set<String>? acceptedReplacementKeys,
    CollectionReplacementReview? review,
  }) async {
    if (!_showingSearchResults || _isDisposed) return;
    if (review != null &&
        (!identical(review._owner, this) || !review._isCurrent(true))) {
      throw StateError(
        'The collection changed. Review its replacement items again.',
      );
    }
    if (isPagedCollection) {
      await _refreshPagedCollection(
        rerunSearch: rerunSearch,
        acceptReplacements: acceptReplacements,
        acceptedReplacementKeys:
            acceptedReplacementKeys ??
            (acceptReplacements
                ? collectionReplacements.map(collectionRowKey).toSet()
                : null),
        review: review,
      );
      return;
    }
    final request = ++_collectionRequest;
    final tabId = _activeTabId;
    final generation = _listingGeneration;
    final originalCollectionId = _collectionId;
    final store = _ref.read(fileCollectionStoreProvider);
    final revision = originalCollectionId == null
        ? null
        : store.get(originalCollectionId)?.revision;
    if (originalCollectionId != null && revision == null) {
      throw StateError('The saved collection no longer exists.');
    }
    final collection = _collectionSnapshot(
      id: _collectionId ?? const Uuid().v4(),
      name: _fileListTitle,
      files: _files ?? const [],
      selection: _selection,
      search: _collectionSearch,
    );
    final sources = <String, PanelFileOrigin>{};
    final backends = <String, FileOperationBackend>{};
    FileOperationBackend? resolve(StorageReference storage, String path) {
      if (backends.containsKey(storage.id)) return backends[storage.id];
      final origin = review == null
          ? _resolveCollectionDirectory(
              storage,
              path,
              search: collection.search,
            )
          : review._origins[storage];
      if (origin == null) return null;
      sources[storage.id] = origin;
      return backends[storage.id] = fileOperationBackend(
        source: origin.source,
        local: _localFileService,
        isCurrent: () => origin.isCurrent,
      );
    }

    bool cancelled() =>
        _isDisposed ||
        request != _collectionRequest ||
        tabId != _activeTabId ||
        generation != _listingGeneration ||
        originalCollectionId != _collectionId ||
        (review != null && !review._isCurrent(false));
    _collectionBusy = true;
    _collectionProgress = '';
    notifyListeners();
    try {
      const service = FileCollectionService();
      final inspected = review == null
          ? collection
          : collection.copyWith(
              entries: collection.entries
                  .where((entry) => review._replacements.containsKey(entry.key))
                  .toList(),
            );
      final result = rerunSearch
          ? await service.rerun(
              collection,
              resolve,
              isCancelled: cancelled,
              onProgress: (scanned, _) {
                if (!cancelled()) {
                  _collectionProgress = '$scanned scanned';
                  notifyListeners();
                }
              },
            )
          : await service.refresh(
              inspected,
              resolve,
              isCancelled: cancelled,
              acceptReplacements: acceptReplacements,
              acceptedReplacementKeys: acceptedReplacementKeys,
              reviewedReplacements: review?._replacements ?? const {},
              onProgress: (done, total) {
                if (!cancelled()) {
                  _collectionProgress = '$done / $total';
                  notifyListeners();
                }
              },
            );
      if (cancelled()) return;
      _checkReviewedReplacementResult(inspected, result, review);
      final FileCollection saved;
      if (review == null) {
        saved = result.collection;
      } else {
        final replacements = {
          for (final entry in result.collection.entries) entry.key: entry,
        };
        saved = collection.copyWith(
          entries: [
            for (final entry in collection.entries)
              replacements[entry.key] ?? entry,
          ],
        );
      }
      await store.save(
        saved,
        expectedRevision: review?._revision ?? revision,
        isCancelled: cancelled,
      );
      if (cancelled()) return;
      if (review != null) {
        await openCollection(saved.id);
        return;
      }
      showSearchResults(
        result.collection.entries
            .map(
              (entry) => entry.file.copyWith(
                metadata: {
                  ...?entry.file.metadata,
                  'collectionState': entry.state.name,
                  if (entry.detail != null) 'collectionDetail': entry.detail,
                  'collectionReplacement': entry.replacement,
                },
              ),
            )
            .toList(),
        collection: result.collection,
        originForFile: (file) {
          final key = '${file.storageId}\u0000${file.path}';
          final source = sources[file.storageId];
          return result.verifiedKeys.contains(key) && source?.isCurrent == true
              ? source
              : null;
        },
      );
      activeTab?.collectionId = result.collection.id;
    } finally {
      if (!_isDisposed && request == _collectionRequest) {
        _collectionBusy = false;
        notifyListeners();
      }
    }
  }

  void _leaveFileList({bool forget = true}) {
    _saveDepartingCollectionMarks();
    if (forget) {
      _isFlatView = false;
      _fileListTabs.remove(_activeTabId);
      activeTab?.collectionId = null;
    }
    if (!_showingSearchResults) return;
    _showingSearchResults = false;
    _fileListOrigin = null;
    _collectionId = null;
    _collectionSearch = null;
    _collectionPage = null;
    _collectionMarks = null;
    _collectionWindow = null;
    _collectionQueryTimer?.cancel();
    _collectionLoadError = null;
    _collectionRequest++;
    _collectionBusy = false;
    _selection.clear();
    _lastSelected = null;
    _itemToScrollTo = null;
    _listingGeneration++;
  }

  /// Return to the directory from which this list was opened.
  Future<void> clearSearchResults() async {
    if (!_showingSearchResults) return;
    await flushCollectionMarks();
    final origin = _fileListOrigin;
    if (origin != null && origin.isCurrent) {
      await navigateToPath(
        origin.source.currentPath,
        origin: origin,
        recordHistory: false,
      );
    } else {
      final directory = _currentDirectoryOrigin;
      if (!_allowTabNavigation(
        directory?.source.currentPath ?? currentPath,
        directory?.storageReference,
      )) {
        return;
      }
      _leaveFileList();
      await refresh();
    }
  }

  /// Remove rows only. No filesystem or provider delete call is made.
  Future<void> removeFromFileList(Iterable<FileItem> items) async {
    if (!_showingSearchResults) return;
    if (isPagedCollection) {
      final keys = items.map(collectionRowKey).toSet();
      final id = _collectionId!;
      final index = collectionPageIndex;
      try {
        await flushCollectionMarks();
        await _ref.read(fileCollectionStoreProvider).transform(id, (
          page,
        ) async {
          final rows = page.entries
              .where((entry) => !keys.contains(entry.key))
              .toList();
          if (rows.length == page.entries.length) return page;
          return page.copyWith(
            entries: rows,
            selectedKeys: page.selectedKeys.difference(keys),
          );
        });
        if (_isDisposed || _collectionId != id) return;
        _collectionMarks = null;
        _collectionPage = null;
        await openCollection(id, pageIndex: index);
      } catch (error) {
        if (!_isDisposed) {
          _collectionLoadError = '$error';
          _ref
              .read(errorProvider)
              .addError('Could not remove collection rows: $error');
          notifyListeners();
        }
      }
      return;
    }
    final removed = Set<FileItem>.identity()..addAll(items);
    final cursor = cursorItem;
    _files?.removeWhere(removed.contains);
    _selection.removeWhere(removed.contains);
    if (removed.contains(_lastSelected)) _lastSelected = null;
    if (removed.contains(_itemToScrollTo)) _itemToScrollTo = null;
    _resetCursor(preserveItem: cursor);
    _rememberFileListTab();
    if (_collectionId != null) {
      unawaited(
        saveCurrentCollection(_fileListTitle).catchError((Object error) {
          if (!_isDisposed) {
            _ref
                .read(errorProvider)
                .addError('Could not save collection changes: $error');
          }
          return '';
        }),
      );
    }
    notifyListeners();
  }

  /// Update rows after successful operations; null means moved/deleted away.
  /// Keys are original full paths, never basenames shared by other folders.
  /// Async callers pass their captured [origin] so results cannot affect a
  /// same-path row in another storage account after the pane changes sources.
  /// Matching saved list tabs are updated even while another tab is active.
  /// Visible list changes remain immediate; the returned future acknowledges
  /// saved-reference persistence and any resulting paged collection reload.
  Future<void> applyFileListChanges(
    Map<String, FileItem?> replacements, {
    PanelFileOrigin? origin,
    Set<String> removedDirectories = const {},
  }) {
    if (_isDisposed ||
        replacements.isEmpty ||
        (origin != null && !origin.isCurrent)) {
      return Future<void>.value();
    }
    bool matchesOrigin(PanelFileOrigin? candidate) =>
        origin == null ||
        (candidate != null &&
            candidate.isCurrent &&
            _sameStorage(origin.source, candidate.source));

    final folderMoves =
        replacements.entries
            .where(
              (entry) =>
                  entry.value?.isFolder == true &&
                  entry.value?.isSymlink != true &&
                  entry.value?.path != null,
            )
            .toList()
          ..sort((a, b) => b.key.length.compareTo(a.key.length));
    var completion = Future<void>.value();
    if (origin != null) {
      // Capture the persistence service and account before yielding. The
      // operation already completed on this source; a later panel disposal
      // must not replace or invalidate its accepted saved-reference update.
      final store = _ref.read(fileCollectionStoreProvider);
      final storage = origin.storageReference;
      final changes = Map<String, FileItem?>.of(replacements);
      final removed = Set<String>.of(removedDirectories);
      final previous = _pendingCollectionChanges;
      final pagedId = isPagedCollection ? _collectionId : null;
      final pageIndex = collectionPageIndex;
      final session = _collectionMarks;
      if (pagedId != null) {
        _collectionBusy = true;
        notifyListeners();
      }
      completion = () async {
        try {
          if (previous != null) await previous;
          if (session != null) await session.flush(store);
          await store.applyFileChanges(
            storage,
            changes,
            removedDirectories: removed,
          );
          if (!_isDisposed &&
              pagedId != null &&
              _collectionId == pagedId &&
              identical(session, _collectionMarks)) {
            _collectionMarks = null;
            _collectionPage = null;
            await openCollection(pagedId, pageIndex: pageIndex);
          }
        } catch (error) {
          if (!_isDisposed) {
            if (pagedId != null && _collectionId == pagedId) {
              _collectionBusy = false;
              _collectionLoadError = '$error';
              notifyListeners();
            }
            _ref
                .read(errorProvider)
                .addError('Could not update saved collections: $error');
          }
        }
      }();
      _pendingCollectionChanges = completion;
      final accepted = completion;
      unawaited(
        accepted.whenComplete(() {
          if (identical(_pendingCollectionChanges, accepted)) {
            _pendingCollectionChanges = null;
          }
        }),
      );
      if (pagedId != null) return completion;
    }

    FileItem? replacementFor(FileItem? old) {
      if (old == null || old.path == null) return old;
      final oldOrigin = _fileOrigins[old];
      if (origin != null && !matchesOrigin(oldOrigin)) return old;
      final paths = oldOrigin?.source.isRemote == true ? p.posix : p.context;
      FileItem? item;
      if (replacements.containsKey(old.path)) {
        item = replacements[old.path]?.copyWith(storageId: old.storageId);
      } else if (removedDirectories.any(
        (parent) => paths.isWithin(parent, old.path!),
      )) {
        return null;
      } else {
        for (final folder in folderMoves) {
          if (!paths.isWithin(folder.key, old.path!)) continue;
          item = old.copyWith(
            path: paths.join(
              folder.value!.path!,
              paths.relative(old.path!, from: folder.key),
            ),
          );
          break;
        }
        if (item == null) return old;
      }
      if (item != null &&
          !identical(old, item) &&
          oldOrigin != null &&
          item.path != null) {
        _fileOrigins[item] = _originAt(oldOrigin, paths.dirname(item.path!));
        _collectionEntries[item] = FileCollectionService.capture(
          item,
          oldOrigin.storageReference,
        );
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
          collectionId: snapshot.collectionId,
          search: snapshot.search,
        );
        changed = true;
      }
    }

    if (!_showingSearchResults) {
      if (changed) notifyListeners();
      return completion;
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
    if (!changed) return completion;
    _files = updated;
    if (isPagedCollection) {
      final visibleKeys = _collectionPage!.collection.entries
          .map((entry) => entry.key)
          .toSet();
      _selection.removeWhere(
        (file) => visibleKeys.contains(collectionRowKey(file)),
      );
      _selection.addAll(selected);
    } else {
      _selection
        ..clear()
        ..addAll(selected);
    }
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
    return completion;
  }

  String exportFileListPaths({bool selectedOnly = false}) {
    if (isPagedCollection &&
        !selectedOnly &&
        collectionTotalCount > (_files?.length ?? 0)) {
      throw StateError(
        'Use the complete collection export to include every saved page.',
      );
    }
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

  Future<String> exportAllFileListPaths({bool selectedOnly = false}) async {
    if (!isPagedCollection || selectedOnly) {
      return exportFileListPaths(selectedOnly: selectedOnly);
    }
    await flushCollectionMarks();
    final manifest = _collectionMarks!.manifest;
    final paths = <String>[];
    var bytes = 0;
    await for (final page
        in _ref
            .read(fileCollectionStoreProvider)
            .pages(manifest.summary.id, revision: manifest.summary.revision)) {
      for (final entry in page.collection.entries) {
        bytes += utf8.encode(entry.reference.path).length + 3;
        if (bytes > 32 * 1024 * 1024) {
          throw const FormatException('The exported path list exceeds 32 MiB.');
        }
        paths.add(entry.reference.path);
      }
    }
    return FileListPaths.encode(paths);
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

  final List<_ArchivePanelFrame> _archiveFrames = [];
  PanelFileOrigin? _archiveOrigin;

  void _clearArchiveState() {
    final frames = List<_ArchivePanelFrame>.of(_archiveFrames);
    _archiveFrames.clear();
    _archiveSource = null;
    _archiveOrigin = null;
    for (final frame in frames.reversed) {
      unawaited(
        frame.session.close().catchError((Object error) {
          _log.warn('archive cleanup failed', error);
        }),
      );
    }
  }

  PanelFileOrigin captureArchiveOrigin() {
    final origin = _archiveOrigin;
    if (_isDisposed ||
        !isInArchive ||
        origin == null ||
        !origin.isCurrent ||
        _archiveFrames.isEmpty ||
        !_archiveFrames.last.session.isCurrent) {
      throw StateError('Reopen the archive from its original storage account.');
    }
    return origin;
  }

  ArchiveWorkspaceLocation captureArchiveWorkspaceLocation() {
    captureArchiveOrigin();
    final frame = _archiveFrames.last;
    return ArchiveWorkspaceLocation(
      file: _archiveFrames.first.session.file,
      fingerprint: _archiveFrames.first.session.fingerprint,
      nestedMembers: List.unmodifiable(
        _archiveFrames
            .skip(1)
            .map(
              (entry) =>
                  entry.session.file.path!.replaceFirst(RegExp(r'^/'), ''),
            ),
      ),
      isCurrent: () =>
          !_isDisposed &&
          _archiveFrames.isNotEmpty &&
          identical(_archiveFrames.last, frame) &&
          frame.session.isCurrent,
    );
  }

  Future<void> enterArchive(FileItem file) async {
    if (isInArchive) {
      await _enterNestedArchive(file);
      return;
    }
    if (file.path == null && file.name.isEmpty) return;
    int? requestGeneration;
    List<FileItem>? previousFiles;
    var previousVerified = false;
    ArchiveBrowserSession? opened;
    try {
      final origin = _showingSearchResults
          ? captureOperationOrigin([file])
          : (originForOperation(file) ?? captureCurrentOrigin());
      final paths = origin.source.isRemote ? p.posix : p.context;
      final archivePath =
          file.path ?? paths.join(origin.source.currentPath, file.name);
      final parentSource = origin.source.withPath(paths.dirname(archivePath));
      final tab = activeTab;
      if (tab?.lockMode == TabLockMode.locked) {
        _ref
            .read(errorProvider)
            .addError(
              'The tab "${tab!.label}" is locked. Open the archive in a new tab or unlock it.',
            );
        return;
      }
      if (tab?.lockMode == TabLockMode.newTab) {
        _createTabLocation(parentSource.currentPath, origin.storageReference);
      }
      previousFiles = _files;
      previousVerified = _verifiedListingGeneration == _listingGeneration;
      final generation = ++_listingGeneration;
      requestGeneration = generation;
      _isLoading = true;
      notifyListeners();
      final backend = fileOperationBackend(
        source: origin.source,
        local: _localFileService,
        isCurrent: () => !_isDisposed && origin.isCurrent,
      );
      opened = await ArchiveBrowserSession.open(
        backend,
        file.copyWith(path: archivePath),
        isCancelled: () => _isDisposed || generation != _listingGeneration,
      );
      if (_isDisposed ||
          generation != _listingGeneration ||
          !origin.isCurrent) {
        return;
      }
      _leaveFileList();
      _clearArchiveState();
      final source = const PanelSourceService().enterArchive(
        archivePath,
        parentSource,
      );
      _archiveFrames.add(_ArchivePanelFrame(opened, source));
      opened = null;
      _archiveSource = source;
      _archiveOrigin = origin;
      _filterQuery = '';
      _isFlatView = false;
      await _loadArchiveFiles();
      _log.info('enterArchive: $archivePath (${parentSource.displayName})');
    } catch (error) {
      if (_isDisposed ||
          (requestGeneration != null &&
              requestGeneration != _listingGeneration)) {
        return;
      }
      _log.warn('archive open failed', error);
      _isLoading = false;
      if (previousVerified && identical(previousFiles, _files)) {
        _verifiedListingGeneration = _listingGeneration;
      }
      _ref.read(errorProvider).addError('Cannot open archive: $error');
      notifyListeners();
    } finally {
      await opened?.close();
    }
  }

  bool _isCurrentArchiveRow(FileItem file) =>
      _archiveFrames.isNotEmpty &&
      _archiveFrames.last.session.isCurrent &&
      (_files?.any((row) => identical(row, file)) ?? false);

  Future<void> _enterNestedArchive(FileItem file) async {
    if (!_isCurrentArchiveRow(file) ||
        file.isFolder ||
        file.path == null ||
        !ArchiveService.isArchive(file.name)) {
      return;
    }
    if (_archiveFrames.length >= kArchiveNestingLimit) {
      _ref
          .read(errorProvider)
          .addError('Archive nesting is limited to 8 levels.');
      return;
    }
    final parent = _archiveFrames.last;
    final generation = ++_listingGeneration;
    _isLoading = true;
    notifyListeners();
    ArchiveBrowserSession? opened;
    try {
      opened = await ArchiveBrowserSession.open(
        parent.session.backend,
        file.copyWith(path: '/${file.path}'),
        maxInputBytes: kArchiveReadLimit,
        isCancelled: () => _isDisposed || generation != _listingGeneration,
      );
      if (_isDisposed ||
          generation != _listingGeneration ||
          !identical(_archiveFrames.lastOrNull, parent) ||
          !parent.session.isCurrent) {
        return;
      }
      final source = const PanelSourceService().enterArchive(
        file.path!,
        parent.source,
      );
      _archiveFrames.add(
        _ArchivePanelFrame(opened, source, returnCursor: file.path),
      );
      opened = null;
      _archiveSource = source;
      await _loadArchiveFiles();
    } catch (error) {
      if (_isDisposed || generation != _listingGeneration) return;
      _isLoading = false;
      _ref.read(errorProvider).addError('Cannot open nested archive: $error');
      notifyListeners();
    } finally {
      await opened?.close();
    }
  }

  Future<void> _navigateArchive(String innerPath) async {
    if (_archiveFrames.isEmpty) return;
    final frame = _archiveFrames.last;
    final directory = frame.session.index.directoryPath(innerPath);
    frame.source = frame.source.withPath(
      directory.isEmpty ? '' : '$directory/',
    );
    _archiveSource = frame.source;
    await _loadArchiveFiles();
  }

  Future<void> navigateUpArchive() async {
    if (_archiveFrames.isEmpty) return;
    final inner = _archiveFrames.last.source.innerPath.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    if (inner.isEmpty) {
      await exitArchive();
      return;
    }
    final parent = p.posix.dirname(inner);
    await _navigateArchive(parent == '.' ? '' : parent);
  }

  /// A nested exit restores its exact enclosing directory and cursor. Only
  /// leaving the outermost archive navigates back to physical storage.
  Future<void> exitArchive() async {
    if (_archiveFrames.isEmpty) return;
    if (_archiveFrames.length > 1) {
      final closed = _archiveFrames.removeLast();
      _archiveSource = _archiveFrames.last.source;
      unawaited(closed.session.close());
      await _loadArchiveFiles(cursorPath: closed.returnCursor);
      return;
    }
    final archiveFile = _archiveFrames.first.session.file;
    final source = _archiveFrames.first.source;
    final origin = _archiveOrigin;
    _listingGeneration++;
    _clearArchiveState();
    _isLoading = false;
    final restore = origin != null && origin.isCurrent
        ? navigateToPath(
            source.parent.currentPath,
            origin: origin,
            recordHistory: false,
            selectItem: archiveFile,
          )
        : refresh();
    try {
      await restore;
      if (!_isDisposed) focusList();
    } catch (error) {
      if (!_isDisposed) {
        _ref
            .read(errorProvider)
            .addError('Could not return to the archive folder: $error');
      }
    }
  }

  Future<void> navigateHome() async {
    if (isInArchive) {
      await exitArchive();
      return;
    }
    final path = kIsWeb ? '/' : (Platform.environment['HOME'] ?? '/');
    await navigateToPath(path);
    if (!_isDisposed) focusList();
  }

  Future<void> _loadArchiveFiles({String? cursorPath}) async {
    ++_listingGeneration;
    if (_archiveFrames.isEmpty) return;
    try {
      captureArchiveOrigin();
      final frame = _archiveFrames.last;
      // Navigation belongs to the pane, not the archive member namespace.
      // Keep a parent row even at the archive root (including empty archives)
      // so Enter/double-click can leave this frame just like Backspace does.
      _files = [
        FileItem(name: '..', path: '..', isFolder: true),
        ...frame.session.list(frame.source.innerPath),
      ];
      _selection.clear();
      _lastSelected = null;
      _itemToScrollTo = null;
      _cursorIndex = 0;
      _sortFiles();
      if (cursorPath != null) {
        final index =
            displayedFiles?.indexWhere((row) => row.path == cursorPath) ?? -1;
        if (index >= 0) {
          _cursorIndex = index;
          _itemToScrollTo = displayedFiles![index];
        }
      }
    } catch (error) {
      _files = [];
      _ref.read(errorProvider).addError('Failed to read archive: $error');
    }
    _isLoading = false;
    if (!_isDisposed) notifyListeners();
  }

  /// Refresh the physical snapshot and reopen the same nested route, so edits
  /// committed from the workspace are visible instead of relisting stale bytes.
  Future<void> _reloadArchiveFiles() async {
    if (_archiveFrames.isEmpty) return;
    final oldFrames = List<_ArchivePanelFrame>.of(_archiveFrames);
    final origin = _archiveOrigin!;
    final cursorPath = cursorItem?.path;
    final generation = ++_listingGeneration;
    final fresh = <_ArchivePanelFrame>[];
    _isLoading = true;
    notifyListeners();
    try {
      if (!origin.isCurrent) {
        throw StateError('The archive source account changed.');
      }
      var backend = oldFrames.first.session.source;
      for (var i = 0; i < oldFrames.length; i++) {
        final previous = oldFrames[i];
        final file = await backend.stat(previous.session.file.path!);
        if (file == null) throw StateError('The archive was removed.');
        final session = await ArchiveBrowserSession.open(
          backend,
          file,
          maxInputBytes: i == 0 ? kArchiveBrowseInputLimit : kArchiveReadLimit,
          isCancelled: () => _isDisposed || generation != _listingGeneration,
        );
        fresh.add(
          _ArchivePanelFrame(
            session,
            previous.source,
            returnCursor: previous.returnCursor,
          ),
        );
        session.index.directoryPath(previous.source.innerPath);
        backend = session.backend;
      }
      if (_isDisposed ||
          generation != _listingGeneration ||
          !origin.isCurrent) {
        return;
      }
      _clearArchiveState();
      _archiveFrames.addAll(fresh);
      fresh.clear();
      _archiveOrigin = origin;
      _archiveSource = _archiveFrames.last.source;
      await _loadArchiveFiles(cursorPath: cursorPath);
    } catch (error) {
      if (_isDisposed || generation != _listingGeneration) return;
      _files = [];
      _selection.clear();
      _isLoading = false;
      _ref
          .read(errorProvider)
          .addError(
            'Failed to reload archive: $error',
            code: error is ArchivePasswordRequiredException
                ? PanelErrorCode.archivePassword
                : PanelErrorCode.archiveRead,
            arguments: {'error': error},
          );
      notifyListeners();
    } finally {
      for (final frame in fresh.reversed) {
        await frame.session.close();
      }
    }
  }

  // --- Multi-key sort ---

  void setSecondarySortBy(SortBy? sortBy) {
    _secondarySortBy = sortBy;
    _secondarySortColumnId = null;
    _rememberTabView();
    _sortFiles();
    notifyListeners();
  }

  void toggleSecondarySortOrder() {
    _secondarySortOrder = _secondarySortOrder == SortOrder.ascending
        ? SortOrder.descending
        : SortOrder.ascending;
    _rememberTabView();
    _sortFiles();
    notifyListeners();
  }

  // --- Flat view ---

  Future<void> toggleFlatView() async {
    if (_isFlatView) {
      _isFlatView = false;
      await clearSearchResults();
    } else {
      await _loadFlatFiles();
    }
    notifyListeners();
  }

  Future<void> _loadFlatFiles() async {
    final origin = captureCurrentOrigin();
    final backend = fileOperationBackend(
      source: origin.source,
      local: _localFileService,
      isCurrent: () => origin.isCurrent,
    );
    final generation = _listingGeneration;
    final tab = _activeTabId;
    final request = ++_collectionRequest;
    final query = FileSearchQuery(
      includeFolders: false,
      includeHidden: _showHiddenFiles,
    );
    _collectionBusy = true;
    _collectionProgress = 'Reading branch…';
    notifyListeners();
    bool cancelled() =>
        _isDisposed ||
        request != _collectionRequest ||
        generation != _listingGeneration ||
        tab != _activeTabId ||
        !origin.isCurrent;
    try {
      final result = await RecursiveSearchService().search(
        backend,
        query,
        currentDirectory: origin.source.currentPath,
        isCancelled: cancelled,
        onProgress: (count, path) {
          if (!cancelled() && count % 100 == 0) {
            _collectionProgress = '$count items scanned';
            notifyListeners();
          }
        },
      );
      if (cancelled() || result.cancelled) return;
      if (result.errors.isNotEmpty) {
        _ref
            .read(errorProvider)
            .addError(
              'Branch view has ${result.errors.length} unreadable location(s): ${result.errors.take(3).join('; ')}',
            );
      }
      showSearchResults(
        result.matches.map((match) => match.file).toList(),
        origin: origin,
        title: 'Branch: ${origin.source.currentPath}',
        search: CollectionSearch(
          storage: origin.storageReference,
          directory: origin.source.currentPath,
          query: query,
        ),
      );
      _isFlatView = true;
    } catch (error) {
      if (!cancelled()) {
        _ref.read(errorProvider).addError('Branch view failed: $error');
      }
    } finally {
      if (!_isDisposed && request == _collectionRequest) {
        _collectionBusy = false;
        _collectionProgress = '';
        notifyListeners();
      }
    }
  }

  String get currentPath {
    if (isInArchive) {
      final route = _archiveFrames.indexed
          .map(
            (entry) => entry.$1 == 0
                ? entry.$2.source.archiveName
                : entry.$2.source.archivePath,
          )
          .join('!/');
      return '$route:/${_archiveSource!.innerPath}';
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

  /// A saved location can be a drop destination only when it identifies a real
  /// directory. A transient result tab must not borrow its underlying path.
  bool isDirectoryTab(String id) {
    if (_isDisposed || _fileListTabs.containsKey(id)) return false;
    PanelTab? tab;
    for (final candidate in _tabs) {
      if (candidate.id == id) tab = candidate;
    }
    if (tab == null ||
        tab.storage == null ||
        tab.collectionId != null ||
        _isArchiveVirtualPath(tab.path))
      return false;
    return id != _activeTabId ||
        (!_showingSearchResults && !isInArchive && !_isFlatView);
  }

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
    _sortColumnId = null;
    _rememberTabView();
    _sortFiles();
    notifyListeners();
  }

  void toggleSortOrder() {
    _sortOrder = _sortOrder == SortOrder.ascending
        ? SortOrder.descending
        : SortOrder.ascending;
    _rememberTabView();
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
    if (isPagedCollection &&
        _applyingCollectionWindow &&
        _collectionProjection != null) {
      return;
    }
    if (isPagedCollection && !_applyingCollectionWindow) {
      _scheduleCollectionQuery();
      return;
    }
    _files!.sort(_fileSortComparator());
  }

  Comparator<FileItem> _fileSortComparator() {
    final columns = _ref.read(fileColumnsProvider(side));
    FileColumnDefinition? column(String? id) {
      for (final value in columns) {
        if (value.id == id) return value;
      }
      return null;
    }

    final primaryColumn = column(_sortColumnId);
    final secondaryColumn = column(_secondarySortColumnId);
    final sortBy = _sortBy;
    final sortOrder = _sortOrder;
    final secondarySortBy = _secondarySortBy;
    final secondarySortOrder = _secondarySortOrder;
    return (a, b) {
      // ".." always stays at the top
      if (a.name == '..') return -1;
      if (b.name == '..') return 1;

      if (a.isFolder && !b.isFolder) return -1;
      if (!a.isFolder && b.isFolder) return 1;

      int comparison =
          primaryColumn?.compare(a, b) ?? compareSortKey(a, b, sortBy);
      comparison = sortOrder == SortOrder.ascending ? comparison : -comparison;

      // Secondary sort key when primary ties
      if (comparison == 0 &&
          (secondarySortBy != null || secondaryColumn != null)) {
        final int secondary =
            secondaryColumn?.compare(a, b) ??
            compareSortKey(a, b, secondarySortBy!);
        comparison = secondarySortOrder == SortOrder.ascending
            ? secondary
            : -secondary;
      }

      if (comparison == 0 && (_showingSearchResults || _isFlatView)) {
        comparison = (a.path ?? '').compareTo(b.path ?? '');
        if (sortOrder == SortOrder.descending) comparison = -comparison;
      }
      return comparison;
    };
  }

  // --- Selection ---
  bool isSelected(FileItem item) => _selection.contains(item);

  void toggleSelection(
    FileItem item, {
    bool shiftKey = false,
    bool ctrlKey = false,
  }) {
    if (isPagedCollection && _collectionBusy) return;
    _log.debug(
      'toggleSelection: ${item.name} shift=$shiftKey ctrl=$ctrlKey lastSelected=${_lastSelected?.name} side=$side',
    );
    final files = _files;
    if (files == null || !_containsIdentical(files, item)) return;
    final rangeAnchor = _lastSelected ?? cursorItem;
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
    if (shiftKey && rangeAnchor != null) {
      final displayed = displayedFiles ?? const <FileItem>[];
      final startIdx = _indexOfIdentical(displayed, rangeAnchor);
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
    if (!shiftKey || rangeAnchor == null) _lastSelected = item;
    notifyListeners();
  }

  void selectAll() {
    if (isPagedCollection) {
      _startWholeCollectionSelection(invert: false);
      return;
    }
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
    if (isPagedCollection) {
      _startWholeCollectionSelection(invert: true);
      return;
    }
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
    if (isPagedCollection && _collectionBusy) return;
    _log.debug('clearSelection (was ${_selection.length})');
    _selection.clear();
    _lastSelected = null;
    notifyListeners();
  }

  void _startWholeCollectionSelection({required bool invert}) {
    unawaited(
      selectWholeCollection(invert: invert).catchError((Object error) {
        if (!_isDisposed) {
          _collectionLoadError = '$error';
          _ref
              .read(errorProvider)
              .addError('Could not update collection marks: $error');
          notifyListeners();
        }
      }),
    );
  }

  /// Ctrl+A/invert apply to every matching saved row, including off-page rows.
  Future<void> selectWholeCollection({bool invert = false}) async {
    await _selectSavedRows(
      (_) => true,
      invert ? SelectionAction.invert : SelectionAction.select,
    );
  }

  Future<int> _selectSavedRows(
    bool Function(FileCollectionEntry) extra,
    SelectionAction action, {
    String? replaceStorageId,
    bool preserveOnEmpty = false,
    bool verifyMatches = false,
    bool Function()? isCancelled,
  }) async {
    if (!isPagedCollection || _collectionBusy) return 0;
    await flushCollectionMarks();
    final session = _collectionMarks!;
    final request = ++_collectionRequest;
    bool cancelled() =>
        _isDisposed ||
        request != _collectionRequest ||
        !identical(session, _collectionMarks) ||
        (isCancelled?.call() ?? false);
    _collectionBusy = true;
    _collectionProgress = '';
    notifyListeners();
    try {
      final selected = {
        for (final file in _selection)
          collectionRowKey(file): _compactCollectionMark(file),
      };
      final locations = Map<String, int>.of(session.desired);
      if (action == SelectionAction.replace) {
        if (replaceStorageId == null) {
          selected.clear();
          locations.clear();
        } else {
          final removed = selected.entries
              .where((entry) => entry.value.storageId == replaceStorageId)
              .map((entry) => entry.key)
              .toList();
          for (final key in removed) {
            selected.remove(key);
            locations.remove(key);
          }
        }
      }
      final matches = _collectionFilter();
      final projection = _collectionProjection;
      var done = 0;
      var matched = 0;
      await for (final page
          in _ref
              .read(fileCollectionStoreProvider)
              .pages(
                session.manifest.summary.id,
                revision: session.manifest.summary.revision,
              )) {
        if (cancelled()) throw StateError('Collection selection cancelled.');
        for (final entry in page.collection.entries) {
          if (!matches(entry.file) ||
              !(projection?.matches(entry) ?? true) ||
              !extra(entry)) {
            continue;
          }
          matched++;
          final add =
              action == SelectionAction.select ||
              action == SelectionAction.replace ||
              (action == SelectionAction.invert &&
                  !session.desired.containsKey(entry.key));
          if (add) {
            selected[entry.key] = _compactCollectionMark(entry.file);
            locations[entry.key] = page.index;
          } else {
            selected.remove(entry.key);
            locations.remove(entry.key);
          }
        }
        done += page.collection.entries.length;
        _collectionProgress = '$done / ${session.manifest.summary.itemCount}';
        notifyListeners();
      }
      if (cancelled()) throw StateError('Collection selection cancelled.');
      if (preserveOnEmpty && matched == 0) return 0;
      session.rowPages.addAll(locations);
      if (verifyMatches) {
        await _prepareCollectionFiles(selected.values, reuseRequest: request);
        if (cancelled()) throw StateError('Collection selection cancelled.');
      }
      final manifest = await session.replaceMarks(
        _ref.read(fileCollectionStoreProvider),
        locations,
        isCancelled: cancelled,
      );
      if (cancelled()) return matched;
      final page = _collectionPage;
      if (page != null) {
        _collectionPage = FileCollectionPage(
          manifest: manifest,
          index: page.index,
          collection: page.collection,
        );
      }
      _suppressCollectionMarks = true;
      _selection
        ..clear()
        ..addAll(selected.values);
      for (final file in _files ?? const <FileItem>[]) {
        if (locations.containsKey(collectionRowKey(file))) _selection.add(file);
      }
      _suppressCollectionMarks = false;
      return matched;
    } finally {
      _suppressCollectionMarks = false;
      if (!_isDisposed &&
          request == _collectionRequest &&
          identical(session, _collectionMarks)) {
        _collectionBusy = false;
        _collectionProgress = '';
        notifyListeners();
      }
    }
  }

  bool Function(FileCollectionEntry) _collectionCriteria(
    FileSearchQuery criteria,
  ) {
    criteria.validate();
    if (criteria.contentPattern.isNotEmpty || criteria.searchArchives) {
      throw const FormatException(
        'Run a content or archive search first, then select its result rows.',
      );
    }
    final filters = <String, FileSearchPathFilter>{};
    final pattern = criteria.nameMatcher;
    final search = _collectionSearch;
    return (entry) {
      if (!pattern.matches(entry.file) ||
          !criteria.matchesMetadata(entry.file)) {
        return false;
      }
      final storage = entry.reference.storage;
      final filter = filters.putIfAbsent(
        storage.id,
        () => FileSearchPathFilter(
          criteria,
          paths: storage.isLocal && !kIsWeb ? p.context : p.posix,
        ),
      );
      return filter.allows(
        entry.file,
        root: search?.storage == storage ? search!.directory : storage.root,
      );
    };
  }

  Future<int> applyCollectionCriteriaSelection(
    FileSearchQuery criteria, {
    SelectionAction action = SelectionAction.select,
  }) async {
    if (!isPagedCollection) {
      return applyCriteriaSelection(criteria, action: action);
    }
    return _selectSavedRows(_collectionCriteria(criteria), action);
  }

  Future<int> countCollectionCriteria(
    FileSearchQuery criteria, {
    bool Function()? isCancelled,
  }) async {
    if (!isPagedCollection) return matchingCriteriaFiles(criteria).length;
    final session = _collectionMarks!;
    final matches = _collectionCriteria(criteria);
    final filter = _collectionFilter();
    final projection = _collectionProjection;
    var count = 0;
    await for (final page
        in _ref
            .read(fileCollectionStoreProvider)
            .pages(
              session.manifest.summary.id,
              revision: session.manifest.summary.revision,
            )) {
      if (_isDisposed ||
          isCancelled?.call() == true ||
          !identical(session, _collectionMarks) ||
          !identical(projection, _collectionProjection)) {
        throw StateError('Collection selection preview cancelled.');
      }
      count += page.collection.entries
          .where(
            (entry) =>
                filter(entry.file) &&
                (projection?.matches(entry) ?? true) &&
                matches(entry),
          )
          .length;
    }
    return count;
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

  /// Exchange locations atomically, then verify fresh filesystem listings.
  /// Source listeners must not start loads between the two source assignments.
  /// Virtual lists retain each row's original account; archive sessions move
  /// with their owner rather than being closed by a source-picker callback.
  Future<bool> swapViewWith(PanelNotifier other) async {
    if (identical(this, other) ||
        _isDisposed ||
        other._isDisposed ||
        _swappingViews ||
        other._swappingViews ||
        _collectionBusy ||
        other._collectionBusy ||
        (_isLoading && (isInArchive || _showingSearchResults)) ||
        (other._isLoading &&
            (other.isInArchive || other._showingSearchResults))) {
      return false;
    }
    _swappingViews = other._swappingViews = true;
    _PanelSwapView? left;
    _PanelSwapView? right;
    try {
      await Future.wait([
        if (_collectionMarks != null) flushCollectionMarks(),
        if (other._collectionMarks != null) other.flushCollectionMarks(),
        if (_pendingCollectionChanges != null) _pendingCollectionChanges!,
        if (other._pendingCollectionChanges != null)
          other._pendingCollectionChanges!,
      ]);
      if (_isDisposed || other._isDisposed) return false;
      left = _captureSwapView();
      right = other._captureSwapView();
      // Old asynchronous loads can never publish into the exchanged location.
      _listingGeneration++;
      other._listingGeneration++;
      _verifiedListingGeneration = other._verifiedListingGeneration = -1;
      _archiveFrames.clear();
      other._archiveFrames.clear();
      _settingSwapSource = other._settingSwapSource = true;
      try {
        _ref.read(panelSourceProvider(side).notifier).setSource(right.source);
        other._ref
            .read(panelSourceProvider(other.side).notifier)
            .setSource(left.source);
      } finally {
        _settingSwapSource = other._settingSwapSource = false;
      }
      await Future.wait([
        _restoreSwapView(right),
        other._restoreSwapView(left),
      ]);
      return !_isDisposed && !other._isDisposed;
    } finally {
      // A provider may be disposed by a source/listing notification before it
      // accepts the transferred session. Close only sessions not yet adopted.
      await left?.closeUnclaimedArchives();
      await right?.closeUnclaimedArchives();
      _swappingViews = other._swappingViews = false;
    }
  }

  _PanelSwapView _captureSwapView() {
    _rememberFileListTab();
    final selected = _ref.read(panelSourceProvider(side));
    final origin = _archiveOrigin ?? _fileListOrigin ?? _currentDirectoryOrigin;
    final verified = _verifiedListingGeneration == _listingGeneration;
    var source = origin?.source ?? selected;
    if (!isInArchive && !_showingSearchResults) {
      // The legacy cloud pane may still have a local dropdown label. Capture
      // the endpoint of the actual requested listing during refresh/failure.
      if (_isLoading || !verified) source = _requestedListingSource ?? selected;
      if (source is RemotePanelSource && !_isConnectedClient(source.client)) {
        throw StateError(
          'Reconnect the original account before swapping this pane.',
        );
      }
      source = source.withPath(source.isRemote ? _remotePath : _localPath);
    }
    final rows = verified ? List<FileItem>.of(_files ?? []) : <FileItem>[];
    return _PanelSwapView(
      source: source,
      files: rows,
      selection: verified ? Set<FileItem>.of(_selection) : {},
      cursor: verified ? cursorItem : null,
      origins: Map<FileItem, PanelFileOrigin>.identity()
        ..addEntries(
          rows
              .where((row) => _fileOrigins[row] != null)
              .map((row) => MapEntry(row, _fileOrigins[row]!)),
        ),
      collectionEntries: Map<FileItem, FileCollectionEntry>.identity()
        ..addEntries(
          rows
              .where((row) => _collectionEntries[row] != null)
              .map((row) => MapEntry(row, _collectionEntries[row]!)),
        ),
      directoryOrigin: _currentDirectoryOrigin,
      fileList: _showingSearchResults ? _fileListTabs[_activeTabId] : null,
      archiveFrames: List.of(_archiveFrames),
      archiveOrigin: _archiveOrigin,
      flat: _isFlatView,
    );
  }

  Future<void> _restoreSwapView(_PanelSwapView view) async {
    if (_isDisposed) return;
    _leaveFileList();
    _clearArchiveState();
    _pendingTabStorage = null;
    _renamingItem = null;
    _filterQuery = '';
    _isTypeahead = false;
    _typeaheadResetTimer?.cancel();
    _isFlatView = view.flat;
    _requestedListingSource = view.source;
    if (view.source.isRemote) {
      _remotePath = view.source.currentPath;
    } else {
      _localPath = view.source.currentPath;
    }
    final tab = activeTab;
    if (tab != null) {
      tab.path = view.source.currentPath;
      tab.storage = storageReferenceForSource(view.source);
      tab.collectionId = view.fileList?.collectionId;
      tab.updateLabel();
    }
    for (final entry in view.origins.entries) {
      _fileOrigins[entry.key] = entry.value;
    }
    for (final entry in view.collectionEntries.entries) {
      _collectionEntries[entry.key] = entry.value;
    }
    if (view.archiveFrames.isNotEmpty) {
      _archiveFrames.addAll(view.archiveFrames);
      view.archiveFrames.clear();
      _archiveOrigin = view.archiveOrigin;
      _archiveSource = _archiveFrames.last.source;
    }
    _files = view.files;
    _selection
      ..clear()
      ..addAll(view.selection);
    _lastSelected = null;
    _currentDirectoryOrigin = view.directoryOrigin;
    _resetCursor(preserveItem: view.cursor);
    _isLoading = true;
    notifyListeners();
    if (_isDisposed) return;
    if (view.fileList != null) {
      _fileListTabs[_activeTabId] = view.fileList!;
      await selectTab(_activeTabId);
    } else if (_archiveFrames.isNotEmpty) {
      await _loadArchiveFiles(cursorPath: view.cursor?.path);
      if (!_isDisposed) _saveTabs();
    } else {
      _isFlatView = false;
      if (view.source.isRemote) {
        await _loadRemoteFiles();
      } else {
        await _loadLocalFiles();
      }
      if (!_isDisposed) _syncTabPath();
    }
  }

  /// Remember marks for this tab and storage session, never just basenames.
  /// Restoration resolves fresh, verified rows; saved objects grant no writes.
  int rememberSelection() {
    if (isPagedCollection) {
      _startSavedSelection(rememberCollectionSelection());
      return 0;
    }
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

  int get rememberedSelectionCount => isPagedCollection
      ? _collectionSelectionMemories[_activeTabId]?.rows.length ?? 0
      : _selectionMemories[_activeTabId]?.length ?? 0;

  /// Capture marked operation rows now, but publish their memory only after
  /// the operation is accepted. Cancelled reviews and failed preflight leave
  /// the preceding memory intact. The callback is idempotent and cannot write
  /// into another tab, listing, collection, account or access grant.
  ///
  /// [files] must be the original verified rows returned by operation
  /// preparation. Cursor-only and external clipboard operations do not replace
  /// the user's preceding marked selection with unrelated files.
  VoidCallback? captureSelectionMemoryForOperation(Iterable<FileItem> files) {
    if (!_canUseSelectionMemory || _activeTabId.isEmpty) return null;
    final tab = _activeTabId;
    final current = captureOperationSession();
    final ordinary = <(StorageReference, String), _SelectionMemoryEntry>{};
    final rows = <String, CollectionRememberedRow>{};
    final guards = <String, bool Function()>{};
    final collection = isPagedCollection;
    var bytes = 0;
    for (final file in files) {
      final key = collection ? collectionRowKey(file) : null;
      final marked = collection
          ? _collectionMarks?.desired.containsKey(key) == true
          : _selection.contains(file);
      if (!marked) continue;
      final origin = originForOperation(file);
      if (origin == null || !origin.isCurrent) return null;
      if (collection) {
        final objectId = FileCollectionService.objectIdentity(file);
        bytes +=
            utf8.encode(key!).length + utf8.encode(objectId ?? '').length + 32;
        rows[key] = CollectionRememberedRow(
          objectId: objectId,
          isFolder: file.isFolder,
          isSymlink: file.isSymlink,
          storageId: origin.storageId,
        );
      } else {
        final location = _selectionMemoryKey(file, origin);
        if (location == null) return null;
        bytes +=
            utf8.encode(location.$2).length +
            utf8.encode(file.uuid ?? '').length +
            32;
        ordinary[location] = _SelectionMemoryEntry(
          origin: origin,
          objectId: file.uuid,
          isFolder: file.isFolder,
        );
      }
      guards.putIfAbsent(
        origin.storageId,
        () =>
            () => origin.isCurrent,
      );
      if (bytes > 4 * 1024 * 1024 || rows.length + ordinary.length > 100000) {
        return null;
      }
    }
    if (rows.isEmpty && ordinary.isEmpty) return null;
    var published = false;
    return () {
      if (published || !current() || guards.values.any((guard) => !guard())) {
        return;
      }
      published = true;
      if (collection) {
        _storeCollectionSelectionMemory(
          tab,
          CollectionSelectionMemory(
            rows: Map.unmodifiable(rows),
            sourceGuards: Map.unmodifiable(guards),
            bytes: bytes,
          ),
        );
      } else {
        _selectionMemories[tab] = ordinary;
      }
      notifyListeners();
    };
  }

  Future<int> rememberCollectionSelection() async {
    if (!isPagedCollection) return rememberSelection();
    final tab = _activeTabId;
    final session = _collectionMarks;
    final prepared = await prepareOperationFiles(_selection);
    if (_isDisposed ||
        tab != _activeTabId ||
        !identical(session, _collectionMarks) ||
        prepared.isEmpty) {
      return 0;
    }
    final rows = <String, CollectionRememberedRow>{};
    final guards = <String, bool Function()>{};
    var bytes = 0;
    for (final file in prepared) {
      final origin = originForOperation(file);
      if (origin == null) {
        throw StateError(
          'The original source changed before remembering the selection.',
        );
      }
      final key = collectionRowKey(file);
      final objectId = FileCollectionService.objectIdentity(file);
      bytes +=
          utf8.encode(key).length + utf8.encode(objectId ?? '').length + 32;
      if (bytes > 4 * 1024 * 1024 || rows.length >= 100000) {
        throw StateError(
          'Remembered collection marks exceed 100,000 identities or 4 MiB.',
        );
      }
      guards.putIfAbsent(
        origin.storageId,
        () =>
            () => origin.isCurrent,
      );
      rows[key] = CollectionRememberedRow(
        objectId: objectId,
        isFolder: file.isFolder,
        isSymlink: file.isSymlink,
        storageId: origin.storageId,
      );
    }
    _storeCollectionSelectionMemory(
      tab,
      CollectionSelectionMemory(
        rows: Map.unmodifiable(rows),
        sourceGuards: Map.unmodifiable(guards),
        bytes: bytes,
      ),
    );
    notifyListeners();
    return rows.length;
  }

  void _storeCollectionSelectionMemory(
    String tab,
    CollectionSelectionMemory memory,
  ) {
    final previous = _collectionSelectionMemories.remove(tab);
    if (previous != null) _collectionSelectionMemoryBytes -= previous.bytes;
    while (_collectionSelectionMemories.isNotEmpty &&
        (_collectionSelectionMemoryBytes + memory.bytes > 4 * 1024 * 1024 ||
            _collectionSelectionMemories.values.fold<int>(
                  memory.rows.length,
                  (sum, memory) => sum + memory.rows.length,
                ) >
                100000)) {
      _collectionSelectionMemoryBytes -= _collectionSelectionMemories
          .remove(_collectionSelectionMemories.keys.first)!
          .bytes;
    }
    _collectionSelectionMemories[tab] = memory;
    _collectionSelectionMemoryBytes += memory.bytes;
  }

  Future<int> restoreCollectionSelection() async {
    if (!isPagedCollection) return restoreSelection();
    final memory = _collectionSelectionMemories[_activeTabId];
    if (memory == null) return 0;
    return _selectSavedRows(
      (entry) {
        final saved = memory.rows[entry.key];
        return saved != null &&
            memory.sourceGuards[saved.storageId]?.call() == true &&
            saved.isFolder == entry.file.isFolder &&
            (saved.isSymlink == true) == (entry.file.isSymlink == true) &&
            (saved.objectId == null ||
                saved.objectId == entry.reference.objectId);
      },
      SelectionAction.replace,
      preserveOnEmpty: true,
      verifyMatches: true,
    );
  }

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

  int get restorableSelectionCount {
    if (!isPagedCollection) return _restorableSelection().length;
    final memory = _collectionSelectionMemories[_activeTabId];
    return memory?.rows.values
            .where((row) => memory.sourceGuards[row.storageId]?.call() == true)
            .length ??
        0;
  }

  /// Replace marks with remembered items still visible in this tab and source.
  /// If none can be resolved, retain the current marks instead of erasing them.
  int restoreSelection() {
    if (isPagedCollection) {
      _startSavedSelection(restoreCollectionSelection());
      return 0;
    }
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

  /// Select an explicit projection of the current listing (gallery filters,
  /// visual sort/ranges). Hidden entries must never be added by a range or
  /// Select all action. Only the exact listed objects are accepted.
  void selectVisibleItems(
    Iterable<FileItem> items, {
    FileItem? cursor,
    FileItem? anchor,
  }) {
    final listed = _files;
    if (listed == null) return;
    final valid = Set<FileItem>.identity()..addAll(listed);
    final selected = items
        .where((item) => item.name != '..' && valid.contains(item))
        .toList();
    if (isPagedCollection) {
      final visibleKeys = listed.map(collectionRowKey).toSet();
      _selection.removeWhere(
        (file) => visibleKeys.contains(collectionRowKey(file)),
      );
      _selection.addAll(selected);
    } else {
      _selection
        ..clear()
        ..addAll(selected);
    }
    if (cursor != null && valid.contains(cursor)) {
      _cursorIndex = _indexOfIdentical(listed, cursor);
      _itemToScrollTo = cursor;
    }
    _lastSelected = anchor != null && valid.contains(anchor) ? anchor : cursor;
    if (_ref.read(activePanelProvider) != side) {
      _ref.read(activePanelProvider.notifier).state = side;
    }
    notifyListeners();
  }

  // --- Cursor (keyboard focus, separate from selection marks) ---

  /// Plain click moves the cursor and establishes a range anchor. Existing
  /// marks remain the operation selection until explicitly toggled or cleared.
  void setCursorOnly(FileItem item) {
    if (_files == null) return;
    final index = _indexOfIdentical(_files!, item);
    if (index < 0) return;
    if (_ref.read(activePanelProvider) != side) {
      _ref.read(activePanelProvider.notifier).state = side;
    }
    _lastSelected = item.name == '..' || item.name == '.' ? null : item;
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
    if (_isTypeahead && delta.abs() == 1) {
      if (_ref.read(quickSearchSettingsProvider).arrowNavigation) {
        if (_typeaheadMode != QuickSearchMode.filter) {
          cycleTypeahead(delta);
          return;
        }
        _scheduleTypeaheadReset(_ref.read(quickSearchSettingsProvider));
      } else {
        clearTypeahead();
      }
    }
    final displayed = _isTypeahead && delta.abs() == 1 &&
            _ref.read(quickSearchSettingsProvider).arrowNavigation
        ? _typeaheadMatches()
        : filteredFiles;
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

  /// Space / Insert toggles the cursor's mark and advances. Marking a verified
  /// folder also queues a bounded size scan through its original storage.
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
      if (item.isFolder &&
          _selection.contains(item) &&
          item.isSymlink != true &&
          item.calculatedSize == null &&
          item.path != null) {
        unawaited(calculateFolderSize(item));
      }
    }
    final next = (idx + 1).clamp(0, displayed.length - 1);
    _setCursorToItem(displayed[next]);
    notifyListeners();
  }

  FolderSizeMeasurement? folderSizeFor(FileItem file) {
    final measurement = _folderSizes[file];
    if (measurement != null && originForFile(file)?.isCurrent != true) {
      return const FolderSizeMeasurement(
        phase: FolderSizePhase.failed,
        sourceChanged: true,
      );
    }
    final request = _folderSizeRequests[file];
    if (measurement?.isActive == true &&
        request != null &&
        !request.isCurrent()) {
      return measurement!.withPhase(FolderSizePhase.cancelled);
    }
    return measurement;
  }

  /// Returns null when the exact row can no longer authorize a scan. Repeated
  /// requests share their in-flight work; only complete observations set size.
  Future<FolderSizeMeasurement?> calculateFolderSize(FileItem folder) {
    final origin = originForFile(folder);
    if (_isDisposed ||
        !folder.isFolder ||
        folder.name == '..' ||
        folder.isSymlink == true ||
        folder.path == null ||
        origin?.isCurrent != true) {
      return Future.value(null);
    }
    final existing = _folderSizeRequests[folder];
    if (existing != null && !existing.completed.isCompleted) {
      return existing.completed.future;
    }
    final previous = _folderSizes[folder];
    if (previous?.phase == FolderSizePhase.complete)
      return Future.value(previous);
    final generation = _listingGeneration;
    final tab = _activeTabId;
    var rowIndex = -1;
    final request = _FolderSizeRequest(folder, origin!, () {
      if (_isDisposed ||
          generation != _listingGeneration ||
          tab != _activeTabId ||
          !origin.isCurrent) {
        return false;
      }
      final files = _files;
      if (files == null) return false;
      // The scanner checks its authority for every entry. A stable row must
      // not require searching the whole pane each time. Sorting can move the
      // object, so refresh the hint on a mismatch; never accept an equal-path
      // replacement or retain membership after the original object is gone.
      if (rowIndex >= 0 &&
          rowIndex < files.length &&
          identical(files[rowIndex], folder)) {
        return true;
      }
      rowIndex = _indexOfIdentical(files, folder);
      return rowIndex >= 0;
    });
    _folderSizeRequests[folder] = request;
    _folderSizes[folder] = const FolderSizeMeasurement(
      phase: FolderSizePhase.queued,
    );
    _folderSizeQueue.add(request);
    notifyListeners();
    _pumpFolderSizeQueue();
    return request.completed.future;
  }

  void cancelFolderSize(FileItem folder) {
    final request = _folderSizeRequests[folder];
    if (request == null || request.completed.isCompleted) return;
    request.cancelled = true;
    if (_folderSizeQueue.remove(request)) {
      final stopped =
          (_folderSizes[folder] ??
                  const FolderSizeMeasurement(phase: FolderSizePhase.queued))
              .withPhase(FolderSizePhase.cancelled);
      _folderSizes[folder] = stopped;
      request.completed.complete(stopped);
    } else {
      _folderSizes[folder] =
          (_folderSizes[folder] ??
                  const FolderSizeMeasurement(phase: FolderSizePhase.scanning))
              .withPhase(FolderSizePhase.stopping);
    }
    if (!_isDisposed) notifyListeners();
  }

  void _pumpFolderSizeQueue() {
    while (!_isDisposed &&
        _folderSizeQueue.isNotEmpty &&
        _activeFolderSizeRequests.length < maxConcurrentFolderSizeScans) {
      final request = _folderSizeQueue.removeFirst();
      if (!request.isCurrent() || request.cancelled) {
        _folderSizes[request.folder] =
            (_folderSizes[request.folder] ??
                    const FolderSizeMeasurement(phase: FolderSizePhase.queued))
                .withPhase(FolderSizePhase.cancelled);
        request.completed.complete(null);
        continue;
      }
      _activeFolderSizeRequests.add(request);
      _folderSizes[request.folder] = const FolderSizeMeasurement(
        phase: FolderSizePhase.scanning,
      );
      unawaited(_runFolderSizeScan(request));
    }
  }

  Future<void> _runFolderSizeScan(_FolderSizeRequest request) async {
    FolderSizeMeasurement? measurement;
    StorageScanProgress? lastProgress;
    try {
      final origin = request.origin;
      final backend = storageScanBackend(
        source: origin.source is LocalPanelSource
            ? LocalPanelSource(request.folder.path!)
            : origin.source,
        local: _localFileService,
        isCurrent: request.isCurrent,
      );
      final result = await const StorageScanService().scanSummary(
        backend,
        request.folder.path!,
        maxEntries: maxInlineFolderSizeEntries,
        maxDepth: 128,
        maxIssues: 20,
        isCancelled: () => request.cancelled || !request.isCurrent(),
        onProgress: (progress) {
          if (!request.isCurrent() || request.cancelled) return;
          final previous = lastProgress;
          if (previous != null &&
              previous.bytes == progress.bytes &&
              previous.files == progress.files &&
              previous.folders == progress.folders) {
            return;
          }
          // Keep the initial scanning transition and every changed total. The
          // inline row does not display the scanner's changing directory path.
          lastProgress = progress;
          _folderSizes[request.folder] = FolderSizeMeasurement(
            phase: FolderSizePhase.scanning,
            bytes: progress.bytes,
            files: progress.files,
            folders: progress.folders,
          );
          notifyListeners();
        },
      );
      if (request.isCurrent()) {
        final phase = result.cancelled
            ? FolderSizePhase.cancelled
            : result.isComplete
            ? FolderSizePhase.complete
            : result.issues.any(
                (issue) => issue.code == StorageScanIssueCode.rootUnavailable,
              )
            ? FolderSizePhase.failed
            : FolderSizePhase.partial;
        measurement = FolderSizeMeasurement(
          phase: phase,
          bytes: result.bytes,
          files: result.fileCount,
          folders: result.folderCount,
          unknownSizes: result.unknownSizeCount,
          skippedLinks: result.skippedLinkCount,
          issueCount: result.issues.length + result.suppressedIssueCount,
          limited: result.limited,
          sourceChanged: result.sourceChanged,
        );
        _folderSizes[request.folder] = measurement;
        if (phase == FolderSizePhase.complete) {
          updateItemCalculatedSize(request.folder, result.bytes);
        } else {
          notifyListeners();
        }
      }
    } catch (error) {
      _log.warn('Folder size scan failed', error);
      if (request.isCurrent()) {
        measurement = const FolderSizeMeasurement(
          phase: FolderSizePhase.failed,
        );
        _folderSizes[request.folder] = measurement;
        notifyListeners();
      }
    } finally {
      _activeFolderSizeRequests.remove(request);
      if (measurement == null) {
        _folderSizes[request.folder] =
            (_folderSizes[request.folder] ??
                    const FolderSizeMeasurement(
                      phase: FolderSizePhase.scanning,
                    ))
                .withPhase(FolderSizePhase.cancelled);
      }
      if (!request.completed.isCompleted)
        request.completed.complete(measurement);
      _pumpFolderSizeQueue();
    }
  }

  /// Commander Shift+Arrow toggles the rows being left and moves the cursor.
  /// Existing marks can therefore be removed using the same gesture.
  void shiftMoveCursor(int delta, {List<FileItem>? visibleFiles}) {
    final displayed = visibleFiles ??
        (_isTypeahead && _ref.read(quickSearchSettingsProvider).arrowNavigation
            ? _typeaheadMatches()
            : filteredFiles);
    if (displayed == null || displayed.isEmpty) return;
    if (visibleFiles != null) {
      final listed = Set<FileItem>.identity()..addAll(_files ?? const []);
      if (visibleFiles.any((file) => !listed.contains(file))) return;
    }
    final current = cursorItem;
    var cur = current == null ? 0 : _indexOfIdentical(displayed, current);
    if (cur < 0) cur = 0;
    final next = (cur + delta).clamp(0, displayed.length - 1);
    if (next == cur) return;
    final direction = next > cur ? 1 : -1;
    for (var i = cur; i != next; i += direction) {
      final item = displayed[i];
      if (item.name != '..' && item.name != '.') {
        if (!_selection.remove(item)) _selection.add(item);
      }
    }
    _lastSelected = displayed[next].name == '..' ? null : displayed[next];
    _setCursorToItem(displayed[next]);
    if (_isTypeahead) _scheduleTypeaheadReset(_ref.read(quickSearchSettingsProvider));
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
    if (isPagedCollection) {
      _startSavedSelection(
        _selectSavedRows((entry) => pattern.matches(entry.file), action),
      );
      return 0;
    }
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

  /// Reuse the search model for visible-row name and metadata criteria.
  /// Content/archive searches require the search engine before feeding a list.
  List<FileItem> matchingCriteriaFiles(FileSearchQuery criteria) {
    criteria.validate();
    if (criteria.contentPattern.isNotEmpty || criteria.searchArchives) {
      throw const FormatException(
        'Run a content or archive search first, then select its result rows.',
      );
    }
    final pattern = criteria.nameMatcher;
    final filters = <String, FileSearchPathFilter>{};
    return (displayedFiles ?? const <FileItem>[]).where((file) {
      final origin = originForOperation(file);
      if (origin == null ||
          !pattern.matches(file) ||
          !criteria.matchesMetadata(file)) {
        return false;
      }
      final filter = filters.putIfAbsent(
        origin.storageId,
        () => FileSearchPathFilter(
          criteria,
          paths: origin.source.isLocal && !kIsWeb ? p.context : p.posix,
        ),
      );
      final root = _showingSearchResults
          ? (_collectionSearch?.storage == origin.storageReference
                ? _collectionSearch!.directory
                : _fileListOrigin?.source.currentPath ??
                      origin.storageReference.root)
          : origin.source.currentPath;
      return filter.allows(file, root: root);
    }).toList();
  }

  int applyCriteriaSelection(
    FileSearchQuery criteria, {
    SelectionAction action = SelectionAction.select,
  }) {
    if (isPagedCollection) {
      _startSavedSelection(
        applyCollectionCriteriaSelection(criteria, action: action),
      );
      return 0;
    }
    return _applySelectionMatches(matchingCriteriaFiles(criteria), action);
  }

  void _startSavedSelection(Future<int> operation) {
    unawaited(
      operation.catchError((Object error) {
        if (!_isDisposed) {
          _collectionLoadError = '$error';
          _ref
              .read(errorProvider)
              .addError('Could not select saved collection rows: $error');
          notifyListeners();
        }
        return 0;
      }),
    );
  }

  int _applySelectionMatches(
    List<FileItem> matches,
    SelectionAction action, {
    String? replaceStorageId,
  }) {
    switch (action) {
      case SelectionAction.select:
        _selection.addAll(matches);
      case SelectionAction.deselect:
        _selection.removeAll(matches);
      case SelectionAction.invert:
        for (final file in matches) {
          if (!_selection.remove(file)) _selection.add(file);
        }
      case SelectionAction.replace:
        if (replaceStorageId == null) {
          _selection.clear();
        } else {
          _selection.removeWhere(
            (file) => originForOperation(file)?.storageId == replaceStorageId,
          );
        }
        _selection.addAll(matches);
    }
    _lastSelected = null;
    _rememberFileListTab();
    notifyListeners();
    return matches.length;
  }

  /// Same-name follows Commander semantics: ignore the final file extension.
  /// Dotfiles without another dot are extensionless; folders use their full name.
  int selectSameName({
    FileItem? focused,
    bool caseSensitive = false,
    SelectionAction action = SelectionAction.select,
  }) => _selectRelated('name', focused, caseSensitive, action);

  int selectSameExtension({
    FileItem? focused,
    bool caseSensitive = false,
    SelectionAction action = SelectionAction.select,
  }) => _selectRelated('extension', focused, caseSensitive, action);

  /// A directory path on another account is never the same containing folder.
  int selectSameParent({
    FileItem? focused,
    SelectionAction action = SelectionAction.select,
  }) => _selectRelated('parent', focused, true, action);

  int _selectRelated(
    String kind,
    FileItem? focused,
    bool caseSensitive,
    SelectionAction action,
  ) {
    if (isPagedCollection) {
      _startSavedSelection(
        selectRelatedCollection(
          kind: kind,
          focused: focused,
          caseSensitive: caseSensitive,
          action: action,
        ),
      );
      return 0;
    }
    focused ??= cursorItem;
    if (focused == null) return 0;
    final origin = originForOperation(focused);
    if (origin == null || (kind == 'extension' && focused.isFolder)) return 0;
    final paths = origin.source.isLocal && !kIsWeb ? p.context : p.posix;
    String stem(FileItem file) {
      final dot = file.name.lastIndexOf('.');
      return file.isFolder || dot <= 0
          ? file.name
          : file.name.substring(0, dot);
    }

    String value(FileItem file) {
      if (kind == 'parent') {
        return paths.dirname(
          file.path ?? paths.join(origin.source.currentPath, file.name),
        );
      }
      final result = kind == 'name'
          ? stem(file)
          : file.name.substring(stem(file).length);
      return caseSensitive ? result : result.toLowerCase();
    }

    final target = value(focused);
    final matches = (displayedFiles ?? const <FileItem>[]).where((file) {
      final candidate = originForOperation(file);
      if (candidate == null) return false;
      if (kind == 'parent') {
        if (candidate.storageReference != origin.storageReference) return false;
      } else if (file.isFolder != focused!.isFolder) {
        return false;
      }
      return value(file) == target;
    }).toList();
    return _applySelectionMatches(matches, action);
  }

  Future<int> selectRelatedCollection({
    required String kind,
    FileItem? focused,
    bool caseSensitive = false,
    SelectionAction action = SelectionAction.select,
  }) async {
    if (!isPagedCollection) {
      return _selectRelated(kind, focused, caseSensitive, action);
    }
    focused ??= cursorItem;
    final reference = focused == null
        ? null
        : _collectionEntries[focused]?.reference;
    if (reference == null || (kind == 'extension' && focused!.isFolder)) {
      return 0;
    }
    final targetFile = focused!;
    final paths = reference.storage.isLocal && !kIsWeb ? p.context : p.posix;
    String stem(FileItem file) {
      final dot = file.name.lastIndexOf('.');
      return file.isFolder || dot <= 0
          ? file.name
          : file.name.substring(0, dot);
    }

    String value(FileItem file) {
      if (kind == 'parent') return paths.dirname(file.path!);
      final result = kind == 'name'
          ? stem(file)
          : file.name.substring(stem(file).length);
      return caseSensitive ? result : result.toLowerCase();
    }

    final target = value(targetFile);
    return _selectSavedRows((entry) {
      if (kind == 'parent' && entry.reference.storage != reference.storage) {
        return false;
      }
      if (kind != 'parent' && entry.file.isFolder != targetFile.isFolder) {
        return false;
      }
      return value(entry.file) == target;
    }, action);
  }

  /// A path-only list must be applied to an explicitly captured storage account.
  /// The dialog chooses one source for mixed collections. Captures expire after
  /// navigation/refresh rather than redirecting marks to a replacement listing.
  List<PathSelectionSource> get pathSelectionSources {
    if (!_canUseSelectionMemory) return const [];
    final sources = <String, PanelFileOrigin>{};
    if (isPagedCollection) {
      final storedSources = _collectionMarks!.manifest.pages
          .expand((page) => page.sources)
          .toSet();
      final auth = _ref.read(authProvider);
      final clients = <CloudStorageClient>{
        if (auth.isConnected) auth.client,
        ..._ref
            .read(multiCloudProvider)
            .connections
            .map((connection) => connection.client),
      };
      for (final client in clients) {
        final reference = storageReferenceForClient(client);
        if (storedSources.contains(reference.id) &&
            _isConnectedClient(client)) {
          sources[reference.id] = _remoteOrigin(
            client,
            client.providerName,
            reference.root,
          );
        }
      }
    }
    try {
      final current = captureCurrentOrigin();
      sources[current.storageId] = current;
    } on StateError {
      // Mixed collections have no common source; collect their verified rows.
    }
    for (final file in displayedFiles ?? const <FileItem>[]) {
      final origin = originForOperation(file);
      if (origin != null) sources.putIfAbsent(origin.storageId, () => origin);
    }
    final generation = _listingGeneration;
    final tab = _activeTabId;
    return [
      for (final origin in sources.values)
        PathSelectionSource._(
          this,
          origin,
          () =>
              _canUseSelectionMemory &&
              generation == _listingGeneration &&
              tab == _activeTabId &&
              origin.isCurrent,
        ),
    ];
  }

  Future<FileListImportResult> selectPathsFromListAsync(
    String text, {
    PathSelectionSource? source,
    SelectionAction action = SelectionAction.select,
    bool Function()? isCancelled,
  }) async {
    if (!isPagedCollection) {
      return selectPathsFromList(text, source: source, action: action);
    }
    if (source == null) {
      final sources = pathSelectionSources;
      if (sources.length != 1) {
        throw StateError(
          'Choose the original storage account for this path list.',
        );
      }
      source = sources.single;
    }
    if (!identical(source._owner, this) || !source.isCurrent) {
      throw StateError(
        'The panel or source changed. Open path selection again.',
      );
    }
    final captured = source;
    final origin = captured.origin;
    final backend = fileOperationBackend(
      source: origin.source,
      local: _localFileService,
      isCurrent: () => captured.isCurrent,
    );
    final paths = FileListPaths.parse(
      text,
      basePath: origin.source.currentPath,
      local: origin.source.isLocal,
    );
    final requested = {for (final path in paths) backend.pathKey(path): path};
    final found = <String>{};
    await _selectSavedRows(
      (entry) {
        if (!captured.isCurrent) {
          throw StateError(
            'The original source changed during path selection.',
          );
        }
        if (entry.reference.storage != origin.storageReference) return false;
        final key = backend.pathKey(entry.reference.path);
        if (!requested.containsKey(key)) return false;
        found.add(key);
        return true;
      },
      action,
      replaceStorageId: origin.storageId,
      isCancelled: isCancelled,
    );
    return FileListImportResult(
      loaded: found.length,
      failures: {
        for (final entry in requested.entries)
          if (!found.contains(entry.key)) entry.value: 'No matching collection row in the chosen original account and current filter.',
      },
    );
  }

  FileListImportResult selectPathsFromList(
    String text, {
    PathSelectionSource? source,
    SelectionAction action = SelectionAction.select,
  }) {
    if (source == null) {
      final sources = pathSelectionSources;
      if (sources.length != 1) {
        throw StateError(
          'Choose the original storage account for this path list.',
        );
      }
      source = sources.single;
    }
    if (!identical(source._owner, this) || !source.isCurrent) {
      throw StateError(
        'The panel or source changed. Open path selection again.',
      );
    }
    final origin = source.origin;
    final backend = fileOperationBackend(
      source: origin.source,
      local: _localFileService,
      isCurrent: () => origin.isCurrent,
    );
    final requested = FileListPaths.parse(
      text,
      basePath: origin.source.currentPath,
      local: origin.source.isLocal,
    );
    final candidates = <String, List<FileItem>>{};
    for (final file in displayedFiles ?? const <FileItem>[]) {
      final current = originForOperation(file);
      if (current == null ||
          current.storageReference != origin.storageReference) {
        continue;
      }
      final path =
          file.path ??
          backend.paths.join(current.source.currentPath, file.name);
      candidates.putIfAbsent(backend.pathKey(path), () => []).add(file);
    }
    final matches = <FileItem>[];
    final failures = <String, String>{};
    for (final path in requested) {
      final rows = candidates[backend.pathKey(path)] ?? const <FileItem>[];
      if (rows.length == 1) {
        matches.add(rows.single);
      } else {
        failures[path] = rows.isEmpty
            ? 'No visible, verified row in the chosen source.'
            : 'Several rows identify this path; refresh before selecting it.';
      }
    }
    // Resolve/validate the entire list before changing any selection marks.
    if (!source.isCurrent) {
      throw StateError('The source changed during path selection.');
    }
    _applySelectionMatches(matches, action, replaceStorageId: origin.storageId);
    return FileListImportResult(
      loaded: matches.length,
      failures: Map.unmodifiable(failures),
    );
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
    // Transfer callbacks may deliberately ignore applyFileListChanges's
    // Future. Their following refresh still acknowledges every accepted saved
    // reference update before it reloads rows or reports the operation done.
    while (_pendingCollectionChanges != null) {
      await _pendingCollectionChanges;
      if (_isDisposed) return;
    }
    if (_pendingTabStorage != null) {
      await _restoreSelectedTab();
      return;
    }
    _log.debug('refresh: side=$side archive=$isInArchive flat=$_isFlatView');
    await _refreshLock.synchronized(() async {
      // A tab change can queue this callback while a previous listing is still
      // pending. The container may be disposed before the lock is released.
      if (_isDisposed) return;
      if (_showingSearchResults) {
        try {
          await refreshCollectionItems();
        } catch (error) {
          if (!_isDisposed) {
            _ref
                .read(errorProvider)
                .addError('Collection refresh failed: $error');
          }
        }
      } else if (isInArchive) {
        await _reloadArchiveFiles();
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
            _remoteSourceForListing() != null &&
            (knownSource?.isRemote ??
                (selectedSource.isRemote ||
                    (side == PanelSide.remote &&
                        _currentDirectoryOrigin == null)));
        if (remote) {
          await _loadRemoteFiles();
        } else {
          final tabId = _activeTabId;
          // Reserve this request before preparation yields. An older startup
          // path read must not start a loader that makes this explicit refresh
          // return before a verified listing has been published.
          final generation = ++_listingGeneration;
          final path = _localPath;
          _localFileService.currentPath = path;
          await _localFileService.refresh();
          // Preparing a refresh must not start a new local load after a
          // newer tab, source, or navigation has already taken over.
          if (_isDisposed ||
              tabId != _activeTabId ||
              generation != _listingGeneration ||
              path != _localPath ||
              selectedSource != _ref.read(panelSourceProvider(side))) {
            return;
          }
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
    final PanelFileOrigin origin;
    try {
      origin = captureCurrentOrigin();
    } on StateError {
      _ref
          .read(errorProvider)
          .addError(
            'Reconnect the original storage for this location.',
            code: PanelErrorCode.navigationUnavailable,
          );
      return;
    }
    final paths = origin.source.isLocal && !kIsWeb ? p.context : p.posix;
    final current = paths.normalize(origin.source.currentPath);
    final root = paths.normalize(origin.storageReference.root);
    if (paths.isAbsolute(root) && current == root) return;
    final parent = paths.dirname(current);
    if (parent != current && parent != '.') {
      await navigateToPath(parent, origin: origin);
    }
  }

  /// Explicitly ask the OS for access to [path] (or the current directory),
  /// persist the security-scoped bookmark, and reload on success.
  Future<bool> grantAccessToPath(String path) async {
    final source = _ref.read(panelSourceProvider(side));
    if (!source.isLocal && !kIsWeb) return false;
    if (isInArchive) {
      _clearArchiveState();
    }
    var target = path.isEmpty ? currentPath : path;
    if (_isArchiveVirtualPath(target)) {
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
            code: PanelErrorCode.accessParent,
            arguments: {'path': target},
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

  /// Open a path in its captured source. Background followers set
  /// [allowAccessRequests] to false: local reads then use existing access only,
  /// and failure leaves the prior view in place. [canContinue] is checked before
  /// accepting the intent and after every asynchronous navigation/loading step.
  /// It must allow this call's own navigation-intent increment and path change.
  Future<void> navigateToPath(
    String path, {
    FileItem? selectItem,
    PanelFileOrigin? origin,
    bool recordHistory = true,
    bool bypassTabLock = false,
    bool allowAccessRequests = true,
    bool Function()? canContinue,
  }) async {
    if (_isDisposed || !(canContinue?.call() ?? true)) return;
    _log.info('navigateToPath: $path (side=$side, web=$kIsWeb)');
    _rememberNavigationCursor();
    final navigation = ++_navigationRevision;
    final sourceOrigin =
        origin ??
        (_pendingTabStorage == null
            ? null
            : resolveStorageReference(_pendingTabStorage!, path)) ??
        (_showingSearchResults
            ? _fileListOrigin
            : (_verifiedListingGeneration == _listingGeneration
                  ? _currentDirectoryOrigin
                  : null));
    if (_pendingTabStorage != null && sourceOrigin == null) {
      throw StateError(
        'Reconnect the original account for this tab or choose a different source.',
      );
    }
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
    if (!isRemote) {
      path = _normaliseLocalPath(path);
      if (path.isEmpty) return;
    }
    final requestedStorage =
        sourceOrigin?.storageReference ??
        (isRemote
            ? (_remoteSourceForListing() == null
                  ? null
                  : storageReferenceForSource(_remoteSourceForListing()!))
            : storageReferenceForSource(LocalPanelSource(path)));
    if (!(canContinue?.call() ?? true)) return;
    if (!bypassTabLock && !_allowTabNavigation(path, requestedStorage)) return;
    final targetTabId = _activeTabId;
    bool stillNavigating() =>
        !_isDisposed &&
        navigation == _navigationRevision &&
        targetTabId == _activeTabId &&
        (sourceOrigin?.isCurrent ?? true) &&
        (canContinue?.call() ?? true);
    if (!stillNavigating()) return;
    if (_isArchiveVirtualPath(path)) {
      final archive = path.split(':/').first;
      path = !isRemote
          ? (archive.contains('/')
                ? p.dirname(archive)
                : (kIsWeb ? '/' : (Platform.environment['HOME'] ?? '/')))
          : p.posix.dirname(archive);
    }
    List<FileSystemEntity>? directorySnapshot;
    if (!isRemote && !allowAccessRequests) {
      // A linked/background navigation must never open a folder picker or
      // change the current view before its existing access has been proven.
      try {
        directorySnapshot = await _localFileService.listDirectorySnapshot(path);
      } catch (_) {
        if (!stillNavigating()) return;
        rethrow;
      }
      if (!stillNavigating()) return;
      if (directorySnapshot == null) {
        throw UnsupportedError(
          'Noninteractive directory access is unavailable.',
        );
      }
    }
    if (!stillNavigating()) return;
    _leaveFileList();
    // Explicit path navigation leaves archive mode before loading a real path.
    if (isInArchive) _clearArchiveState();
    _selection.clear();
    _lastSelected = null;
    if (_isTypeahead) {
      _filterQuery = '';
      _isTypeahead = false;
    }
    if (!isRemote) {
      final hasAccess =
          !allowAccessRequests || await _localFileService.hasAccessToPath(path);
      if (!stillNavigating()) return;
      if (!hasAccess) {
        if (kIsWeb) return;
        final target = path;
        final granted = await _localFileService.requestDirectoryAccess(
          initialDirectory: p.dirname(target),
        );
        if (!stillNavigating()) return;
        if (granted == null) {
          _ref
              .read(errorProvider)
              .addError('Access to "$target" was not granted.');
          return;
        }
        final hasGrantedAccess = await _localFileService.hasAccessToPath(
          target,
        );
        if (!stillNavigating()) return;
        if (!hasGrantedAccess) {
          _ref
              .read(errorProvider)
              .addError(
                'Access to "$target" was not granted. '
                'Choose the folder that contains it.',
                code: PanelErrorCode.accessContaining,
                arguments: {'path': target},
              );
          return;
        }
        // Stay on the requested path: the user granted a parent folder.
        path = target;
      }
      if (!stillNavigating()) return;
      final selected = _ref.read(panelSourceProvider(side));
      if (selected is! LocalPanelSource) {
        _settingSwapSource = true;
        try {
          _ref
              .read(panelSourceProvider(side).notifier)
              .setSource(LocalPanelSource(path));
        } finally {
          _settingSwapSource = false;
        }
      }
      if (!stillNavigating()) return;
      _localPath = path;
      await _loadLocalFiles(
        sourceIsCurrent: stillNavigating,
        allowAccessRequests: allowAccessRequests,
        fallbackOnMissing: allowAccessRequests,
        directorySnapshot: directorySnapshot,
      );
    } else {
      if (!stillNavigating()) return;
      _remotePath = path;
      if (sourceOrigin?.source case final RemotePanelSource requested) {
        final selected = _ref.read(panelSourceProvider(side));
        if (selected is! RemotePanelSource ||
            !identical(selected.client, requested.client)) {
          _settingSwapSource = true;
          try {
            _ref
                .read(panelSourceProvider(side).notifier)
                .setSource(requested.withPath(path));
          } finally {
            _settingSwapSource = false;
          }
        }
      }
      if (_remoteSourceForListing() == null ||
          (sourceOrigin != null && !sourceOrigin.isCurrent)) {
        throw StateError('The cloud account is no longer connected.');
      }
      if (!stillNavigating()) return;
      await _loadRemoteFiles(sourceIsCurrent: stillNavigating);
    }
    if (!stillNavigating()) return;

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
        _cursorIndex = _indexOfIdentical(_files!, found);
        _itemToScrollTo = found;
      } catch (e) {
        _log.warn('operation failed', e);
      }
    }

    _syncTabPath();
    if (recordHistory) _pushHistory(currentPath);
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
      if (!_isCurrentArchiveRow(item)) return;
      if (item.name == '..') {
        await navigateUpArchive();
      } else if (item.isFolder && item.path != null) {
        await _navigateArchive(item.path!);
      } else if (ArchiveService.isArchive(item.name)) {
        await _enterNestedArchive(item);
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
      _ref
          .read(errorProvider)
          .addError(
            'Error picking directory: $e',
            code: PanelErrorCode.pickFailed,
            arguments: {'error': e},
          );
    }
  }

  /// Update a file item's calculated size (for inline directory size display).
  void updateItemCalculatedSize(FileItem item, int size) {
    if (_files == null) return;
    final idx = _indexOfIdentical(_files!, item);
    if (idx == -1) return;
    final replacement = item.copyWith(calculatedSize: size);
    _folderSizes[replacement] = _folderSizes[item];
    _fileOrigins[replacement] = _fileOrigins[item];
    _collectionEntries[replacement] = _collectionEntries[item];
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
      return captureOperationGroups(files).keys.every((origin) {
        final source = origin.source;
        return source is LocalPanelSource
            ? NativeFileOperations.supported
            : source is RemotePanelSource &&
                  source.client is StorageTrashOperations;
      });
    } catch (_) {
      return false;
    }
  }

  Future<void> restoreTrashRecord(String id) async {
    final store = _ref.read(trashHistoryProvider);
    await store.ready;
    final record = store.get(id);
    if (record == null || record.receipt == null) {
      throw StateError(
        'No confirmed trash receipt is available. Inspect the original path and the system or provider trash.',
      );
    }
    if (record.state == TrashRecordState.restored) return;
    final origin = resolveStorageReference(
      record.file.storage,
      record.file.path,
    );
    if (origin == null) {
      throw StateError(
        'Reconnect the original storage account before restoring.',
      );
    }
    final source = origin.source;
    final backend = fileOperationBackend(
      source: source,
      local: _localFileService,
      isCurrent: () => origin.isCurrent,
    );
    if (await backend.stat(record.file.path) != null) {
      throw StateError(
        'The original path is occupied. Inspect that item before moving it aside or retrying restore.',
      );
    }
    if (!origin.isCurrent) {
      throw StateError('The original source disconnected.');
    }
    Future<void> restore() async {
      if (source is LocalPanelSource && NativeFileOperations.supported) {
        final native = _ref.read(nativeFileOperationsProvider);
        await _localFileService.withFileOperationAccess(
          record.file.path,
          () => native.restore(record.receipt!),
        );
      } else if (source is RemotePanelSource &&
          source.client is StorageTrashOperations) {
        await (source.client as StorageTrashOperations).restoreTrash(
          record.receipt!,
        );
      } else {
        throw UnsupportedError(
          'This source does not support receipt-based restore.',
        );
      }
    }

    await store.save(record.withState(TrashRecordState.restoring));
    try {
      if (!origin.isCurrent) {
        throw StateError('The original source disconnected.');
      }
      await restore();
      if (!origin.isCurrent) {
        throw StateError(
          'Restore returned after the original source disconnected. Inspect it before retrying.',
        );
      }
      await store.save(
        record.withState(TrashRecordState.restored),
        retainOnFailure: true,
      );
    } catch (error) {
      await store.save(
        record.withState(TrashRecordState.uncertain, detail: '$error'),
        retainOnFailure: true,
      );
      rethrow;
    }
    if (!_isDisposed) await refresh();
  }

  Future<int> deleteFiles(
    List<FileItem> files, {
    bool permanently = false,
  }) async {
    var deleted = 0;
    try {
      final groups = captureOperationGroups(files);
      if (!permanently && !canTrashFiles(files)) {
        throw UnsupportedError(
          'Trash is unavailable for one or more original sources. Choose Delete without restore explicitly.',
        );
      }
      final rememberSelection = captureSelectionMemoryForOperation(files);
      for (final group in groups.entries) {
        deleted += await _deleteCapturedFiles(
          group.value,
          group.key,
          permanently: permanently,
          onDeleted: rememberSelection,
        );
      }
    } catch (error) {
      _ref.read(errorProvider).addError('Delete failed: $error');
    } finally {
      await refresh();
      clearSelection();
    }
    return deleted;
  }

  Future<int> _deleteCapturedFiles(
    List<FileItem> files,
    PanelFileOrigin origin, {
    required bool permanently,
    VoidCallback? onDeleted,
  }) async {
    final audit = _ref.read(auditServiceProvider);
    final history = _ref.read(actionHistoryProvider.notifier);
    var providerName = 'unknown';
    final removed = <String, FileItem?>{};
    final removedDirectories = <String>{};
    var deletedCount = 0;
    try {
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
          final trashStore = _ref.read(trashHistoryProvider);
          final record = await trashStore.begin(
            file: FileReference(
              storage: origin.storageReference,
              path: path,
              objectId: file.uuid,
            ),
            name: file.name,
            isFolder: file.isFolder,
          );
          try {
            if (!origin.isCurrent) {
              throw StateError(
                'The original source disconnected before trashing.',
              );
            }
            if (source is LocalPanelSource) {
              final native = _ref.read(nativeFileOperationsProvider);
              receipt = await _localFileService.withFileOperationAccess(
                path,
                () => native.trash(path),
              );
            } else if (source is RemotePanelSource &&
                source.client is StorageTrashOperations) {
              receipt = await (source.client as StorageTrashOperations)
                  .trashPath(path);
            }
            if (receipt == null || receipt.originalPath != path) {
              throw StateError(
                'The source did not return a matching restore receipt. Inspect its trash before retrying.',
              );
            }
          } catch (error) {
            await trashStore.save(
              record.withState(TrashRecordState.uncertain, detail: '$error'),
              retainOnFailure: true,
            );
            rethrow;
          }
          try {
            await trashStore.save(
              record.withState(TrashRecordState.trashed, receipt: receipt),
              retainOnFailure: true,
            );
          } catch (error) {
            _ref
                .read(errorProvider)
                .addError(
                  'The item was trashed, but its restore receipt could not be saved. Restore it before closing the app: $error',
                );
          }
          restore = () => restoreTrashRecord(record.id);
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
        onDeleted?.call();
        removed[path] = null;
        deletedCount++;
        if (file.isFolder && file.isSymlink != true) {
          removedDirectories.add(path);
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
      await applyFileListChanges(
        removed,
        origin: origin,
        removedDirectories: removedDirectories,
      );
    }
    return deletedCount;
  }

  // --- In-place rename ---

  void startRename(FileItem item, {bool keepExtension = false}) {
    if (item.name == '..') return;
    _renamingItem = item;
    _renameKeepExtension = keepExtension;
    notifyListeners();
  }

  void cancelRename() {
    if (_renamingItem == null) return;
    _renamingItem = null;
    _renameKeepExtension = false;
    notifyListeners();
  }

  Future<void> commitRename(String newName) async {
    final item = _renamingItem;
    if (item == null) return;
    _renamingItem = null;
    _renameKeepExtension = false;
    notifyListeners();
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == item.name) return;
    await renameFile(item, trimmed);
  }

  Future<bool> operationPathExists(String path, PanelFileOrigin origin) async =>
      await operationFileInfo(path, origin) != null;

  /// Read fresh metadata at an original path, including after a rename.
  /// Captured operations and undo must not resolve against a different pane
  /// source or accept metadata fetched across an account change.
  Future<FileItem?> operationFileInfo(
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
      throw const FormatException('Use an absolute original file path.');
    }
    final item = await backend.stat(backend.paths.normalize(path));
    if (!origin.isCurrent) throw StateError('The storage account changed.');
    return item;
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

  /// Single, batch and recovered renames use the same captured storage and
  /// low-level mutation implementation. The fallback never starts another job.
  SourceRenameBatchStorage createRenameStorage(
    PanelFileOrigin origin, {
    bool Function()? isCancelled,
  }) => SourceRenameBatchStorage(
    reference: origin.storageReference,
    source: origin.source,
    local: _localFileService,
    isCurrent: () => origin.isCurrent,
    isCancelled: isCancelled,
  );

  Future<void> renameFile(
    FileItem file,
    String newName, {
    bool refreshAfter = true,
    bool rethrowErrors = false,
    bool recordHistory = true,
    PanelFileOrigin? operationOrigin,
    bool Function()? isCancelled,
  }) async {
    _log.info('renameFile: ${file.name} → $newName');
    final audit = _ref.read(auditServiceProvider);
    final history = _ref.read(actionHistoryProvider.notifier);
    final service = RenameBatchService(_ref.read(renameBatchStoreProvider));
    var providerName = 'unknown';
    final sourcePath = file.path ?? file.name;
    PanelFileOrigin? origin;
    SourceRenameBatchStorage? storage;
    RenameBatchRecord? record;
    final rememberSelection = captureSelectionMemoryForOperation([file]);
    try {
      if (newName == file.name) return;
      final problem = MultiRenameService.validateName(newName);
      if (problem != null) throw FormatException(problem);
      if (file.path == null) {
        throw StateError('The original file path is unavailable.');
      }
      origin = operationOrigin ?? captureOperationOrigin([file]);
      if (!origin.isCurrent) throw StateError('The storage account changed.');
      storage = createRenameStorage(origin, isCancelled: isCancelled);
      providerName = origin.source is RemotePanelSource
          ? (origin.source as RemotePanelSource).providerName
          : 'local';
      final plan = const MultiRenameService().preview(
        [file],
        const MultiRenameOptions(),
        directory: storage.paths.dirname(file.path!),
        pathContext: storage.paths,
        caseSensitivePaths: storage.caseSensitivePaths,
        allowDependencies: true,
        targetNames: {file.path!: newName},
      );
      record = await service.prepare(plan, storage, isCancelled: isCancelled);
      await service.run(record, storage, isCancelled: isCancelled);
      if (!record.isComplete) {
        throw StateError(
          record.message ?? 'Rename stopped. Review rename history.',
        );
      }
      await audit.logSuccess(
        operation: AuditOperation.rename,
        sourcePath: sourcePath,
        targetPath: record.items.single.targetPath,
        provider: providerName,
      );
    } catch (error) {
      if (error is RenameBatchPersistenceException) record = error.record;
      _log.warn('operation failed', error);
      if (!_isDisposed) {
        _ref
            .read(errorProvider)
            .addError(
              'Rename failed: $error',
              code: PanelErrorCode.renameFailed,
              arguments: {'error': error},
            );
      }
      await audit.logError(
        operation: AuditOperation.rename,
        sourcePath: sourcePath,
        targetPath: newName,
        provider: providerName,
        error: error.toString(),
      );
      if (rethrowErrors) rethrow;
    } finally {
      final completed = record;
      final captured = origin;
      final capturedStorage = storage;
      if (completed != null && captured != null && capturedStorage != null) {
        if (completed.canRestore) rememberSelection?.call();
        if (recordHistory && completed.canRestore) {
          history.record(
            type: ActionType.rename,
            originalPath: sourcePath,
            newPath: completed.items.single.targetPath,
            provider: providerName,
            metadata: {
              'oldName': file.name,
              'newName': newName,
              'renameBatchId': completed.id,
              'storage': captured.storageReference.toJson(),
            },
            isCurrent: () => captured.isCurrent,
            undoAction: () async {
              final latest = await service.store.read(completed.id);
              if (latest == null) {
                return const UndoResult.failure(
                  'The rename recovery record is missing.',
                );
              }
              final before = {
                for (final item in latest.items)
                  item.sourcePath: item.currentPath,
              };
              try {
                await service.restore(latest, createRenameStorage(captured));
                return latest.isRestored
                    ? UndoResult.success(
                        'Renamed $newName back to ${file.name}.',
                      )
                    : UndoResult.failure(
                        latest.message ??
                            'Restore stopped. Review rename history.',
                      );
              } finally {
                if (captured.isCurrent) {
                  await applyFileListChanges({
                    for (final item in latest.items)
                      if (before[item.sourcePath] != item.currentPath)
                        before[item.sourcePath]!: item.asFile(
                          capturedStorage.paths.basename(item.currentPath),
                          storageId: latest.storage.id,
                        ),
                  }, origin: captured);
                  await refresh();
                }
              }
            },
          );
        }
        if (refreshAfter && captured.isCurrent) {
          await applyFileListChanges(
            RenameBatchService.changes(completed),
            origin: captured,
          );
          await refresh();
        }
      }
    }
  }

  Future<void> createFolder(
    String name, {
    PanelFileOrigin? operationOrigin,
    bool rethrowErrors = false,
  }) async {
    final audit = _ref.read(auditServiceProvider);
    final actionHistory = _ref.read(actionHistoryProvider.notifier);
    var providerName = 'unknown';
    var folderPath = name;
    var createdPath = folderPath;
    try {
      if (operationOrigin == null && _showingSearchResults) {
        throw StateError('Open a real directory before creating a folder.');
      }
      if (name.isEmpty ||
          name == '.' ||
          name == '..' ||
          name.contains('/') ||
          name.contains(r'\') ||
          name.contains('\u0000')) {
        throw const FormatException(
          'Enter a folder name without path separators.',
        );
      }
      final origin = operationOrigin ?? captureCurrentOrigin();
      if (!origin.isCurrent) {
        throw StateError('The original storage disconnected.');
      }
      final backend = fileOperationBackend(
        source: origin.source,
        local: _localFileService,
        isCurrent: () => origin.isCurrent,
      );
      providerName = backend.label;
      createdPath = backend.paths.join(origin.source.currentPath, name);
      folderPath = createdPath;
      if (await backend.stat(folderPath) != null) {
        throw StateError('An item already exists with that name.');
      }
      if (!origin.isCurrent) {
        throw StateError('The original storage disconnected.');
      }
      await backend.createDirectory(folderPath);
      if (!origin.isCurrent) {
        throw StateError(
          'The original storage changed while creating the folder.',
        );
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
        metadata: {'name': name, 'storage': origin.storageReference.toJson()},
        // Undo must use the same captured account and must never fall back to
        // deleting a remote directory recursively through the active client.
        isCurrent: () =>
            origin.isCurrent && backend.capabilities.deleteEmptyDirectory,
        undoAction: () async {
          if (!origin.isCurrent) {
            return const UndoResult.failure('The storage account changed.');
          }
          await backend.deleteEmptyDirectory(createdPath);
          return UndoResult.success('Deleted folder $name.');
        },
      );
      await refresh();
    } catch (error) {
      _log.warn('operation failed', error);
      if (!_isDisposed) {
        _ref.read(errorProvider).addError('Create folder failed: $error');
      }
      await audit.logError(
        operation: AuditOperation.createFolder,
        sourcePath: folderPath,
        provider: providerName,
        error: error.toString(),
      );
      if (rethrowErrors) rethrow;
    }
  }

  /// Non-interactive compatibility entry points share the same captured-source
  /// planner, staged writes and durable queue as the foreground operation dialog.
  /// Existing targets are skipped; callers needing a decision use the dialog.
  Future<void> moveFiles(List<FileItem> files, String targetPath) =>
      _transferFiles(files, targetPath, FileOperationKind.move);

  Future<void> copyFiles(List<FileItem> files, String targetPath) =>
      _transferFiles(files, targetPath, FileOperationKind.copy);

  Future<void> _transferFiles(
    List<FileItem> files,
    String targetPath,
    FileOperationKind kind,
  ) async {
    if (files.isEmpty) return;
    try {
      final targetOrigin = captureCurrentOrigin();
      final groups = captureOperationGroups(files);
      FileOperationBackend backend(PanelFileOrigin origin) =>
          fileOperationBackend(
            source: origin.source,
            local: _localFileService,
            isCurrent: () => origin.isCurrent,
          );
      final destination = backend(targetOrigin);
      final plans = <(PanelFileOrigin, FileOperationPlan)>[];
      // Validate every selected source before starting any mutation.
      for (final group in groups.entries) {
        final plan = await const FileOperationService().prepare(
          files: group.value,
          source: backend(group.key),
          destination: destination,
          targetDirectory: targetPath,
          options: FileOperationOptions(
            kind: kind,
            fileConflict: FileConflictPolicy.skip,
          ),
          protectedDestinationPaths: [
            for (final file in files)
              if (originForOperation(file)?.storageId ==
                      targetOrigin.storageId &&
                  file.path != null)
                file.path!,
          ],
        );
        if (plan.errors.isNotEmpty) throw StateError(plan.errors.join('\n'));
        plans.add((group.key, plan));
      }
      for (final (origin, plan) in plans) {
        if (!plan.canExecute) continue;
        await _ref
            .read(transferProvider)
            .runFileOperation(
              plan,
              control: FileOperationControl(),
              onEntryComplete: (entry) {
                if (entry.outcome == FileOperationOutcome.moved) {
                  applyFileListChanges({
                    entry.source.path!: null,
                  }, origin: origin);
                }
              },
            );
      }
      if (!_isDisposed) {
        await refresh();
        if (kind == FileOperationKind.move) clearSelection();
      }
    } catch (error) {
      _log.warn('file transfer failed', error);
      if (!_isDisposed) {
        _ref.read(errorProvider).addError('File transfer failed: $error');
      }
    }
  }

  static bool _isArchiveVirtualPath(String path) => isArchiveVirtualPath(path);

  // --- Tabs ---
  FileViewConfiguration captureViewConfiguration() {
    final mode = _ref.read(
      side == PanelSide.local ? localViewModeProvider : remoteViewModeProvider,
    );
    final density = _ref.read(panelViewModeProvider(side));
    final columns = _ref.read(fileColumnsProvider(side));
    if (!columns.any((column) => column.id == _sortColumnId)) {
      _sortColumnId = null;
    }
    if (!columns.any((column) => column.id == _secondarySortColumnId)) {
      _secondarySortColumnId = null;
    }
    return FileViewConfiguration(
      display: FileViewDisplay.values.firstWhere(
        (display) =>
            display.name == (mode == ViewMode.list ? density.name : mode.name),
        orElse: () => FileViewDisplay.full,
      ),
      columns: columns,
      widths: _ref.read(columnWidthsProvider(side)),
      sortBy: _sortBy,
      sortOrder: _sortOrder,
      secondarySortBy: _secondarySortBy,
      secondarySortOrder: _secondarySortOrder,
      sortColumnId: _sortColumnId,
      secondarySortColumnId: _secondarySortColumnId,
      showHidden: _showHiddenFiles,
      filter: _isTypeahead ? '' : _filterQuery,
    );
  }

  void _captureTabView() {
    if (_isDisposed || _applyingTabView) return;
    final index = _tabs.indexWhere((tab) => tab.id == _activeTabId);
    if (index >= 0) _tabs[index].view = captureViewConfiguration();
  }

  void _rememberTabView() {
    if (_isDisposed || _applyingTabView) return;
    _captureTabView();
    _viewSaveDebounce?.cancel();
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;
    _viewSaveDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _saveTabs(),
    );
  }

  void _applyTabView(FileViewConfiguration? view) {
    if (view == null || _isDisposed) return;
    _applyingTabView = true;
    try {
      _sortBy = view.sortBy;
      _sortOrder = view.sortOrder;
      _secondarySortBy = view.secondarySortBy;
      _secondarySortOrder = view.secondarySortOrder;
      _sortColumnId = view.sortColumnId;
      _secondarySortColumnId = view.secondarySortColumnId;
      _showHiddenFiles = view.showHidden;
      _filterQuery = view.filter;
      _isTypeahead = false;
      _typeaheadResetTimer?.cancel();
      _ref.read(columnWidthsProvider(side).notifier).applyWidths(view.widths);
      _ref.read(fileColumnsProvider(side).notifier).applyColumns(view.columns);
      _ref
          .read(panelViewModeProvider(side).notifier)
          .applyMode(
            view.display == FileViewDisplay.tree
                ? PanelViewMode.tree
                : view.display == FileViewDisplay.brief
                ? PanelViewMode.brief
                : PanelViewMode.full,
          );
      _ref
          .read(
            (side == PanelSide.local
                    ? localViewModeProvider
                    : remoteViewModeProvider)
                .notifier,
          )
          .state = ViewMode.values.firstWhere(
        (mode) => mode.name == view.display.name,
        orElse: () => ViewMode.list,
      );
    } finally {
      _applyingTabView = false;
    }
  }

  Future<void> applyViewConfiguration(
    FileViewConfiguration view, {
    String? profileId,
  }) async {
    final reload = _showHiddenFiles != view.showHidden;
    _applyTabView(view);
    activeTab?.viewProfileId = profileId;
    _captureTabView();
    _sortFiles();
    notifyListeners();
    if (reload) await refresh();
    await _saveTabs();
  }

  void setColumnSort(String id, {bool secondary = false}) {
    final columns = _ref.read(fileColumnsProvider(side));
    if (!columns.any((column) => column.id == id)) return;
    if (secondary) {
      _secondarySortColumnId = _secondarySortColumnId == id ? null : id;
      _secondarySortBy = null;
    } else if (_sortColumnId == id) {
      _sortOrder = _sortOrder == SortOrder.ascending
          ? SortOrder.descending
          : SortOrder.ascending;
    } else {
      _sortColumnId = id;
      _sortOrder = SortOrder.ascending;
    }
    _sortFiles();
    _rememberTabView();
    notifyListeners();
  }

  String _nextTabId() => 'tab_${_tabIdCounter++}';

  String get _tabStorageKey => 'panel_tabs_${side.name}';
  String get _closedTabStorageKey => '${_tabStorageKey}_closed';

  bool get canReopenClosedTab => _closedTabs.isNotEmpty && !_reopeningClosedTab;
  int get closedTabCount => _closedTabs.length;

  bool _tabLocationDiffers(
    PanelTab tab,
    String path,
    StorageReference? storage,
  ) {
    final paths = storage?.isLocal == true && !kIsWeb ? p.context : p.posix;
    return tab.collectionId != null ||
        _fileListTabs.containsKey(tab.id) ||
        tab.storage != storage ||
        paths.normalize(tab.path) != paths.normalize(path);
  }

  void _departTab() {
    // Closing or replacing the active tab can remove it before selection.
    // Never capture its old view into activeTab's fallback (the first tab).
    if (!_tabs.any((tab) => tab.id == _activeTabId)) return;
    _rememberNavigationCursor();
    _captureTabView();
    _rememberFileListTab();
    final tab = activeTab;
    if (tab != null && tab.resetToLockedLocation()) {
      _fileListTabs.remove(tab.id);
    }
  }

  PanelTab _createTabLocation(
    String path,
    StorageReference? storage, {
    bool keepListing = false,
  }) {
    _departTab();
    _leaveFileList(forget: false);
    final tab = PanelTab(
      id: _nextTabId(),
      path: path,
      storage: storage,
      view: activeTab?.view,
      viewProfileId: activeTab?.viewProfileId,
    );
    final index = _tabs.indexWhere((value) => value.id == _activeTabId);
    _tabs.insert(index < 0 ? _tabs.length : index + 1, tab);
    _activeTabId = tab.id;
    _pendingTabStorage = null;
    if (!keepListing) {
      _files = null;
      _selection.clear();
      _lastSelected = null;
      _listingGeneration++;
      _verifiedListingGeneration = -1;
    }
    return tab;
  }

  bool _allowTabNavigation(String path, StorageReference? storage) {
    final tab = activeTab;
    if (tab == null || !_tabLocationDiffers(tab, path, storage)) return true;
    if (tab.lockMode == TabLockMode.locked) {
      _ref
          .read(errorProvider)
          .addError(
            'The tab "${tab.label}" is locked. Unlock it or open the location in a new tab.',
          );
      return false;
    }
    if (tab.lockMode == TabLockMode.newTab) {
      _createTabLocation(path, storage);
    }
    return true;
  }

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
      final closedRaw = prefs.getString(_closedTabStorageKey);
      if (closedRaw != null) {
        try {
          final savedClosed = json.decode(closedRaw) as List;
          for (final value
              in savedClosed.reversed.take(maxClosedTabs).toList().reversed) {
            try {
              final entry = Map<String, dynamic>.from(value as Map);
              final tab = PanelTab.fromJson(
                _nextTabId(),
                Map<String, dynamic>.from(entry['tab'] as Map),
              );
              if (tab.storage == null && tab.collectionId == null) continue;
              _closedTabs.add(
                _ClosedPanelTab(tab: tab, index: entry['index'] as int? ?? 0),
              );
            } on Object {
              // Retain usable recovery entries if one saved entry is invalid.
            }
          }
        } on Object {
          // Invalid recovery data must not prevent normal tabs from opening.
        }
      }
      final raw = prefs.getString(_tabStorageKey);
      if (raw != null) {
        final List<dynamic> list = json.decode(raw);
        if (list.isNotEmpty) {
          _tabs.clear();
          for (final item in list) {
            final id = _nextTabId();
            var path = (item['path'] as String?) ?? '/';
            if (_isArchiveVirtualPath(path)) {
              // Old tab saved while browsing an archive: fall back to the
              // real parent path (or home) instead of a virtual path.
              final archive = path.split(':/').first;
              path = archive.contains('/')
                  ? archive.substring(0, archive.lastIndexOf('/'))
                  : (Platform.environment['HOME'] ?? '/');
              if (path.isEmpty) path = '/';
            }
            final restored = PanelTab.fromJson(
              id,
              Map<String, dynamic>.from(item as Map)..['path'] = path,
            );
            if (restored.storage == null && restored.collectionId == null) {
              restored.storage = const StorageReference(
                kind: 'remote',
                provider: 'Original source',
                accountKey: 'legacy-unscoped-tab',
              );
            }
            _tabs.add(restored);
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
          await _restoreSelectedTab();
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
  Future<void> _saveTabs({
    bool force = false,
    bool rethrowErrors = false,
  }) async {
    _captureTabView();
    _viewSaveDebounce?.cancel();
    if (!force && !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    await _tabSaveLock.synchronized(() async {
      if (_isDisposed) return;
      try {
        _rememberFileListTab();
        for (final tab in List.of(_tabs)) {
          final snapshot = _fileListTabs[tab.id];
          if (snapshot == null) continue;
          if (snapshot.collectionPageIndex != null) {
            tab.collectionId = snapshot.collectionId;
            continue;
          }
          final existingId = snapshot.collectionId ?? tab.collectionId;
          final id = existingId ?? const Uuid().v4();
          try {
            final store = _ref.read(fileCollectionStoreProvider);
            final revision = existingId == null
                ? null
                : store.get(id)?.revision;
            if (existingId != null && revision == null) continue;
            final collection = _collectionSnapshot(
              id: id,
              name: snapshot.title,
              files: snapshot.files,
              selection: snapshot.selection,
              search: snapshot.search,
            );
            await store.save(
              collection,
              expectedRevision: revision,
              isCancelled: () =>
                  _isDisposed || !identical(_fileListTabs[tab.id], snapshot),
            );
            if (_isDisposed) return;
            if (!identical(_fileListTabs[tab.id], snapshot)) continue;
            tab.collectionId = id;
            if (tab.id == _activeTabId && _showingSearchResults) {
              _collectionId = id;
            }
            _fileListTabs[tab.id] = _FileListSnapshot(
              files: const [],
              title: snapshot.title,
              origin: snapshot.origin,
              selection: const {},
              cursor: null,
              collectionId: id,
              search: snapshot.search,
              collectionPageIndex: 0,
            );
          } catch (error) {
            _log.warn('Could not persist unverified list tab', error);
            if (rethrowErrors) rethrow;
          }
        }
        for (final closed in List.of(_closedTabs)) {
          final snapshot = closed.fileList;
          if (snapshot == null || snapshot.collectionId != null) continue;
          try {
            final id = const Uuid().v4();
            final collection = _collectionSnapshot(
              id: id,
              name: snapshot.title,
              files: snapshot.files,
              selection: snapshot.selection,
              search: snapshot.search,
            );
            await _ref
                .read(fileCollectionStoreProvider)
                .save(
                  collection,
                  isCancelled: () =>
                      _isDisposed || !_closedTabs.contains(closed),
                );
            if (_isDisposed) return;
            if (!_closedTabs.contains(closed)) continue;
            closed.tab.collectionId = id;
            closed.fileList = _FileListSnapshot(
              files: const [],
              title: snapshot.title,
              origin: snapshot.origin,
              selection: const {},
              cursor: null,
              collectionId: id,
              search: snapshot.search,
              collectionPageIndex: 0,
            );
          } catch (error) {
            _log.warn('Could not persist a closed file-list tab', error);
            if (rethrowErrors) rethrow;
          }
        }
        final prefs = await SharedPreferences.getInstance();
        final list = _tabs.map((t) => t.toJson()).toList();
        final saved = await prefs.setString(_tabStorageKey, json.encode(list));
        final savedActive = await prefs.setInt(
          '${_tabStorageKey}_active',
          _tabs
              .indexWhere((t) => t.id == _activeTabId)
              .clamp(0, _tabs.length - 1),
        );
        final savedClosed = await prefs.setString(
          _closedTabStorageKey,
          json.encode([
            for (final closed in _closedTabs)
              if (closed.fileList == null ||
                  closed.fileList!.collectionId != null)
                {'tab': closed.tab.toJson(), 'index': closed.index},
          ]),
        );
        if (!saved || !savedActive || !savedClosed) {
          throw StateError('The tab configuration could not be saved.');
        }
      } catch (e) {
        _log.warn('Tab save failed', e);
        if (rethrowErrors) rethrow;
      }
    });
  }

  Future<void> _restoreSelectedTab({
    PanelFileOrigin? capturedOrigin,
    bool allowAccessRequests = true,
    bool Function()? canContinue,
    bool requireAvailable = false,
  }) async {
    final tab = activeTab;
    final revision = _navigationRevision;
    bool stillSelected() =>
        !_isDisposed &&
        tab != null &&
        _activeTabId == tab.id &&
        (canContinue?.call() ?? true) &&
        (capturedOrigin?.isCurrent ?? true);
    if (!stillSelected()) {
      if (requireAvailable) throw StateError('The tab request is no longer current.');
      return;
    }
    final target = tab!;
    final savedView = target.view;
    _applyTabView(savedView);
    try {
      if (target.collectionId != null) {
        bool currentCollection() =>
            stillSelected() && _navigationRevision == revision;
        await openCollection(
          target.collectionId!,
          canContinue: currentCollection,
        );
        if (!currentCollection() || _collectionId != target.collectionId) {
          if (requireAvailable) {
            throw StateError('The saved collection could not be opened.');
          }
          return;
        }
        if (savedView != null) {
          _applyTabView(savedView);
          _sortFiles();
          _captureTabView();
          notifyListeners();
          await _saveTabs();
        }
        return;
      }
      final storage = target.storage;
      if (storage == null) {
        if (requireAvailable) {
          throw StateError('The saved tab has no storage account.');
        }
        await refresh();
        return;
      }
      final origin = capturedOrigin ??
          (requireAvailable ? null : resolveStorageReference(storage, target.path));
      if (origin == null ||
          !origin.isCurrent ||
          origin.storageReference != storage) {
        if (requireAvailable) {
          throw StateError('The saved tab\'s original source is unavailable.');
        }
        _pendingTabStorage = storage;
        _files = [];
        _isLoading = false;
        _selection.clear();
        _currentDirectoryOrigin = null;
        _listingGeneration++;
        _verifiedListingGeneration = -1;
        _ref
            .read(errorProvider)
            .addError(
              storage.accountKey == 'legacy-unscoped-tab'
                  ? 'Choose a source for the older saved tab "${target.label}". Its previous format did not identify the account.'
                  : 'Reconnect ${storage.provider} for the saved tab "${target.label}". Its original account is unavailable.',
            );
        notifyListeners();
        return;
      }
      _pendingTabStorage = null;
      final requestedPath = target.path;
      final expectedPath = origin.source.isLocal
          ? _normaliseLocalPath(requestedPath)
          : requestedPath;
      await navigateToPath(
        requestedPath,
        origin: origin,
        recordHistory: false,
        bypassTabLock: true,
        allowAccessRequests: allowAccessRequests,
        canContinue: () =>
            stillSelected() &&
            origin.isCurrent &&
            _navigationRevision >= revision &&
            _navigationRevision <= revision + 1,
      );
      if (!stillSelected() || _navigationRevision != revision + 1) {
        if (requireAvailable) {
          throw StateError('The tab request is no longer current.');
        }
        return;
      }
      if (requireAvailable &&
          (!hasVerifiedDirectoryListing ||
              currentPath != expectedPath ||
              _currentDirectoryOrigin?.storageReference != storage ||
              !_sameFileSource(
                _currentDirectoryOrigin!.source,
                origin.source.withPath(expectedPath),
              ))) {
        throw StateError(
          directoryListingError?.message ?? 'The saved folder could not be opened.',
        );
      }
      _pushHistory(currentPath);
    } catch (error) {
      if (requireAvailable) rethrow;
      if (!_isDisposed) {
        _ref.read(errorProvider).addError('Could not reopen tab: $error');
      }
    }
  }

  void addTab({String? path}) {
    _log.debug('addTab: path=${path ?? currentPath}');
    final directory = path ?? currentPath;
    if (path == null && activeTab != null) {
      duplicateTab(activeTab!.id);
      return;
    }
    _createTabLocation(
      directory,
      _currentDirectoryOrigin?.storageReference ?? activeTab?.storage,
    );
    if (side == PanelSide.local) {
      _localPath = directory;
    } else {
      _remotePath = directory;
    }
    notifyListeners();
    _saveTabs();
    _restoreSelectedTab();
  }

  void closeTab(String tabId, {bool force = false}) {
    _log.debug('closeTab: $tabId');
    if (_tabs.length <= 1) return;
    final index = _tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    final tab = _tabs[index];
    if (tab.isProtected && !force) return;
    if (_activeTabId == tabId) {
      _rememberNavigationCursor();
      _captureTabView();
      _rememberFileListTab();
    }
    final idx = _tabs.indexOf(tab);
    final snapshot = _fileListTabs[tabId];
    final closedTab = PanelTab.fromJson(tab.id, tab.toJson());
    closedTab.storage ??= snapshot?.origin?.storageReference;
    if (closedTab.storage == null && closedTab.collectionId == null) {
      closedTab.storage = const StorageReference(
        kind: 'remote',
        provider: 'Original source',
        accountKey: 'legacy-unscoped-tab',
      );
    }
    _closedTabs.add(
      _ClosedPanelTab(tab: closedTab, index: idx, fileList: snapshot),
    );
    if (_closedTabs.length > maxClosedTabs) _closedTabs.removeAt(0);
    _tabs.remove(tab);
    _fileListTabs.remove(tabId);
    _selectionMemories.remove(tabId);
    final remembered = _collectionSelectionMemories.remove(tabId);
    if (remembered != null) _collectionSelectionMemoryBytes -= remembered.bytes;
    if (_activeTabId == tabId) {
      // The closing ID no longer exists. Do not let activeTab's fallback
      // clear the surviving tab's saved collection while leaving this list.
      _leaveFileList(forget: false);
      final newIdx = idx.clamp(0, _tabs.length - 1);
      selectTab(_tabs[newIdx].id);
    }
    notifyListeners();
    _saveTabs();
  }

  /// Restores the exact source, view and history of the most recently closed
  /// tab. Disconnected sources stay visibly unavailable until reconnected.
  Future<void> reopenClosedTab() async {
    if (!canReopenClosedTab || _isDisposed) return;
    _reopeningClosedTab = true;
    final closed = _closedTabs.removeLast();
    try {
      _departTab();
      final tab = PanelTab.fromJson(_nextTabId(), closed.tab.toJson());
      _tabs.insert(closed.index.clamp(0, _tabs.length), tab);
      if (closed.fileList != null) _fileListTabs[tab.id] = closed.fileList!;
      await selectTab(tab.id);
      await _saveTabs();
    } catch (error) {
      if (!_isDisposed) {
        _ref
            .read(errorProvider)
            .addError(
              'Could not open the saved location: $error',
              code: PanelErrorCode.navigationFailed,
              arguments: {'error': '$error'},
            );
      }
    } finally {
      _reopeningClosedTab = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> selectTab(
    String tabId, {
    PanelFileOrigin? capturedOrigin,
    bool allowAccessRequests = true,
    bool Function()? canContinue,
    bool requireAvailable = false,
  }) async {
    _log.debug('selectTab: $tabId');
    bool requestAvailable() =>
        !_isDisposed &&
        _tabs.any((tab) => tab.id == tabId) &&
        (capturedOrigin?.isCurrent ?? true) &&
        (canContinue?.call() ?? true);
    if (!requestAvailable()) {
      if (requireAvailable) throw StateError('The tab request is no longer current.');
      return;
    }
    _rememberNavigationCursor();
    final navigation = ++_navigationRevision;
    ++_listingGeneration;
    if (_collectionMarks != null) await flushCollectionMarks();
    if (!requestAvailable() || navigation != _navigationRevision) {
      if (requireAvailable) throw StateError('The tab request is no longer current.');
      return;
    }
    if (tabId != _activeTabId) {
      _departTab();
    } else {
      _rememberFileListTab();
    }
    _leaveFileList(forget: false);
    _activeTabId = tabId;
    _pendingTabStorage = null;
    final tab = activeTab;
    _applyTabView(tab?.view);
    if (tab != null) {
      if (_isArchiveVirtualPath(tab.path)) return;
      if (side == PanelSide.local) {
        _localPath = tab.path;
      } else {
        _remotePath = tab.path;
      }
    }
    final list = _fileListTabs[tabId];
    if (list != null) {
      if (list.collectionPageIndex != null && list.collectionId != null) {
        await openCollection(
          list.collectionId!,
          pageIndex: list.collectionPageIndex!,
          canContinue: () =>
              requestAvailable() &&
              navigation == _navigationRevision &&
              _activeTabId == tabId,
        );
        if (requireAvailable &&
            (!requestAvailable() ||
                navigation != _navigationRevision ||
                _activeTabId != tabId ||
                _collectionId != list.collectionId)) {
          throw StateError('The saved collection could not be opened.');
        }
        return;
      }
      _showingSearchResults = true;
      _fileListTitle = list.title;
      _fileListOrigin = list.origin;
      _collectionId = list.collectionId;
      _collectionSearch = list.search;
      _files = List.of(list.files);
      _sortFiles();
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
    await _restoreSelectedTab(
      capturedOrigin: capturedOrigin,
      allowAccessRequests: allowAccessRequests,
      canContinue: canContinue,
      requireAvailable: requireAvailable,
    );
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
    final index = _tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    final tab = _tabs[index];
    tab.isPinned = !tab.isPinned;
    notifyListeners();
    _saveTabs();
  }

  void renameTab(String tabId, String newLabel) {
    final index = _tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    final tab = _tabs[index];
    tab.renameLabel(newLabel);
    notifyListeners();
    _saveTabs();
  }

  void setTabLock(String tabId, TabLockMode mode) {
    final index = _tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    final tab = _tabs[index];
    if (mode == TabLockMode.resetOnLeave &&
        _fileListTabs.containsKey(tabId) &&
        tab.collectionId == null) {
      _ref
          .read(errorProvider)
          .addError(
            'Save this file list as a collection before using a return-to-location lock.',
          );
      return;
    }
    tab.setLock(mode);
    notifyListeners();
    _saveTabs();
  }

  void reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _tabs.length ||
        newIndex < 0 ||
        newIndex > _tabs.length) {
      return;
    }
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == newIndex) return;
    final tab = _tabs.removeAt(oldIndex);
    _tabs.insert(newIndex, tab);
    notifyListeners();
    _saveTabs();
  }

  void duplicateTab(String tabId) {
    final index = _tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    _rememberNavigationCursor();
    _captureTabView();
    _rememberFileListTab();
    final original = _tabs[index];
    final snapshot = _fileListTabs[tabId];
    final duplicate = PanelTab(
      id: _nextTabId(),
      path: original.path,
      label: original.label,
      customLabel: original.customLabel,
      storage: original.storage,
      collectionId: original.collectionId,
      view: original.view,
      viewProfileId: original.viewProfileId,
      navigation: original.navigation.copy(),
    );
    _tabs.insert(index + 1, duplicate);
    if (snapshot != null) _fileListTabs[duplicate.id] = snapshot;
    selectTab(duplicate.id);
  }

  int closeDuplicateTabs() {
    final survivors = <String, PanelTab>{};
    final remove = <String>[];
    int priority(PanelTab tab) =>
        (tab.isPinned ? 4 : 0) +
        (tab.isLocked ? 2 : 0) +
        (tab.customLabel != null ? 1 : 0);
    for (final tab in _tabs) {
      if (tab.storage == null && tab.collectionId == null) continue;
      final paths = tab.storage?.isLocal == true && !kIsWeb
          ? p.context
          : p.posix;
      final key = tab.collectionId == null
          ? '${tab.storage!.id}\u0000${paths.normalize(tab.path)}'
          : 'collection:${tab.collectionId}';
      final other = survivors[key];
      if (other == null) {
        survivors[key] = tab;
      } else if (priority(tab) > priority(other) && !other.isProtected) {
        remove.add(other.id);
        survivors[key] = tab;
      } else if (!tab.isProtected) {
        remove.add(tab.id);
      }
    }
    for (final id in remove) {
      closeTab(id);
    }
    return remove.length;
  }

  /// Captures only serializable, source-bound locations. Virtual lists are
  /// first persisted as collections so a saved group never becomes a folder
  /// belonging to whichever account happens to be active on restoration.
  Future<List<Map<String, dynamic>>> exportTabs() async {
    await _saveTabs(force: true, rethrowErrors: true);
    return _tabs.map((tab) => tab.toJson()).toList(growable: false);
  }

  /// Opens a bookmark against its original account. Locked tabs remain intact;
  /// opening a bookmark beside them does not alter their saved lock anchors.
  Future<void> openSavedLocation(
    Map<String, dynamic> saved, {
    bool newTab = false,
  }) async {
    final target = PanelTab.fromJson('bookmark', saved);
    if (target.collectionId != null) {
      final store = _ref.read(fileCollectionStoreProvider);
      await store.ready;
      if (store.get(target.collectionId!) == null) {
        throw StateError('The bookmarked collection is unavailable.');
      }
    } else if (target.storage == null ||
        resolveStorageReference(target.storage!, target.path) == null) {
      throw StateError('Reconnect the original account for this bookmark.');
    }
    final locked = activeTab?.lockMode;
    if (newTab ||
        locked == TabLockMode.locked ||
        locked == TabLockMode.newTab) {
      await restoreTabs([saved]);
      return;
    }
    if (target.collectionId != null) {
      await openCollection(target.collectionId!);
    } else {
      final origin = resolveStorageReference(target.storage!, target.path);
      if (origin == null || !origin.isCurrent) {
        throw StateError('The bookmarked storage account disconnected.');
      }
      await navigateToPath(target.path, origin: origin);
    }
    if (target.view != null) {
      await applyViewConfiguration(
        target.view!,
        profileId: target.viewProfileId,
      );
    }
  }

  Future<void> restoreTabs(
    List<Map<String, dynamic>> saved, {
    int activeIndex = 0,
    bool replace = false,
    bool keepProtected = true,
    PanelFileOrigin? capturedOrigin,
    bool allowAccessRequests = true,
    bool Function()? canContinue,
    bool requireAvailable = false,
  }) async {
    if (saved.isEmpty || saved.length > 500) {
      throw const FormatException('A panel group must contain 1–500 tabs.');
    }
    final incoming = [
      for (final value in saved) PanelTab.fromJson(_nextTabId(), value),
    ];
    for (final tab in incoming) {
      if (tab.storage == null && tab.collectionId == null) {
        throw const FormatException(
          'Saved tabs must identify their storage account.',
        );
      }
      final paths =
          tab.storage?.isLocal == true && tab.storage?.provider == 'windows'
          ? p.windows
          : p.posix;
      if (!paths.isAbsolute(tab.path) || _isArchiveVirtualPath(tab.path)) {
        throw const FormatException(
          'Saved tabs must use absolute storage paths.',
        );
      }
    }
    bool requestAvailable() =>
        !_isDisposed &&
        (capturedOrigin?.isCurrent ?? true) &&
        (canContinue?.call() ?? true);
    if (!requestAvailable()) {
      if (requireAvailable) throw StateError('The tab request is no longer current.');
      return;
    }
    final selected = incoming[activeIndex.clamp(0, incoming.length - 1)];
    if (requireAvailable &&
        selected.collectionId == null &&
        (capturedOrigin == null ||
            capturedOrigin.storageReference != selected.storage)) {
      throw StateError('The saved tab\'s original source is unavailable.');
    }
    if (requireAvailable || canContinue != null) {
      final previousTab = _activeTabId;
      final navigation = _navigationRevision;
      // A guarded action must recheck its captured source and intent after
      // saving marks, before it appends or selects any restored tab.
      await flushCollectionMarks();
      if (!requestAvailable() ||
          navigation != _navigationRevision ||
          previousTab != _activeTabId) {
        if (requireAvailable) throw StateError('The tab request is no longer current.');
        return;
      }
    }
    _departTab();
    _leaveFileList(forget: false);
    if (replace) {
      final removed = _tabs
          .where((tab) => !keepProtected || !tab.isProtected)
          .toList();
      for (final tab in removed) {
        _tabs.remove(tab);
        _fileListTabs.remove(tab.id);
        _selectionMemories.remove(tab.id);
      }
    }
    _tabs.addAll(incoming);
    await selectTab(
      selected.id,
      capturedOrigin: capturedOrigin,
      allowAccessRequests: allowAccessRequests,
      canContinue: canContinue,
      requireAvailable: requireAvailable,
    );
    if (!requestAvailable()) {
      if (requireAvailable) throw StateError('The tab request is no longer current.');
      return;
    }
    await _saveTabs(force: true, rethrowErrors: true);
  }

  void _syncTabPath() {
    final tab = activeTab;
    if (tab != null) {
      // Never persist archive virtual paths (e.g. "file.zip:/"): they are not
      // real directories and would break restart/restore.
      var titlePath = _currentDirectoryOrigin?.source.isRemote == true
          ? _remotePath
          : _localPath;
      if (_isArchiveVirtualPath(titlePath)) {
        final archive = titlePath.split(':/').first;
        titlePath = side == PanelSide.local
            ? (archive.contains('/')
                  ? p.dirname(archive)
                  : (kIsWeb ? '/' : (Platform.environment['HOME'] ?? '/')))
            : p.posix.dirname(archive);
      }
      tab.path = titlePath;
      tab.storage = _currentDirectoryOrigin?.storageReference;
      tab.collectionId = _showingSearchResults ? _collectionId : null;
      tab.updateLabel();
    }
    _saveTabs();
  }

  // --- Internal loading ---
  Future<void> _initializeLocalPath() async {
    var generation = _listingGeneration;
    bool isCurrent() => !_isDisposed && generation == _listingGeneration;
    try {
      await _localFileService.getInitialPath();
      if (!isCurrent()) return;
      if (!kIsWeb &&
          Platform.isMacOS &&
          _localFileService.grantedBasePath == null) {
        _ref
            .read(errorProvider)
            .addError(
              'Please select a base directory to grant access (e.g., your home folder)',
              code: PanelErrorCode.selectBase,
            );
        final initialDirectory = await _localFileService
            .getSafeFallbackDirectory();
        if (!isCurrent()) return;
        final grantedPath = await _localFileService.requestDirectoryAccess(
          initialDirectory: initialDirectory,
        );
        if (!isCurrent()) return;
        if (grantedPath != null) {
          _localPath = grantedPath;
          _ref.read(errorProvider).clearErrors();
        } else {
          final fallback = await _localFileService.getSafeFallbackDirectory();
          if (!isCurrent()) return;
          _localPath = fallback;
          _ref.read(errorProvider).clearErrors();
          _ref
              .read(errorProvider)
              .addError(
                'Access cancelled. Using fallback directory.',
                code: PanelErrorCode.accessCancelled,
              );
        }
      }
      final loading = _loadLocalFiles();
      generation = _listingGeneration;
      await loading;
      if (!isCurrent()) return;
      _pushHistory(currentPath);
      notifyListeners();
    } catch (e) {
      if (!isCurrent()) return;
      _log.warn('operation failed', e);
      final String fallback;
      try {
        fallback = await _localFileService.getSafeFallbackDirectory();
      } catch (_) {
        if (!isCurrent()) return;
        rethrow;
      }
      if (!isCurrent()) return;
      _localPath = fallback;
      _ref.read(errorProvider).addError(e.toString(), cause: e);
      notifyListeners();
    }
  }

  Future<void> _loadLocalFiles({
    bool fallbackOnMissing = true,
    bool Function()? sourceIsCurrent,
    bool allowAccessRequests = true,
    List<FileSystemEntity>? directorySnapshot,
  }) async {
    if (_showingSearchResults || !(sourceIsCurrent?.call() ?? true)) return;
    final generation = ++_listingGeneration;
    // This loader must never receive an archive's virtual path. If an archive
    // failed to open or a stale tab restored one, leave archive mode first.
    if (_archiveSource != null) {
      final archivePath =
          _archiveFrames.firstOrNull?.source.archivePath ??
          _archiveSource!.archivePath;
      _clearArchiveState();
      if (side == PanelSide.local && archivePath.contains('/')) {
        _localPath = p.dirname(archivePath);
      }
    }
    if (!kIsWeb && _isArchiveVirtualPath(_localPath)) {
      _localPath = await _localFileService.getSafeFallbackDirectory();
    }
    if (_isDisposed || generation != _listingGeneration) return;
    final listingPath = _localPath;
    _requestedListingSource = LocalPanelSource(listingPath);
    final origin = _guardLocalGrant(
      PanelFileOrigin._(LocalPanelSource(listingPath), () => !_isDisposed),
      listingPath,
      allowNamespaceRoot: true,
    );
    bool stillCurrent() {
      if (_isDisposed || generation != _listingGeneration) return false;
      if (origin.isCurrent && (sourceIsCurrent?.call() ?? true)) return true;
      // Discard the result without keeping a dead request in a loading state.
      // The owning presentation exposes its unavailable source until refresh.
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _beginDirectoryPresentation(generation, origin);
    _log.debug('_loadLocalFiles: $currentPath (web=$kIsWeb)');
    _isLoading = true;
    notifyListeners();
    if (!stillCurrent()) return;

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
        _files = cached
            .where(
              (file) =>
                  _showHiddenFiles ||
                  !file.name.startsWith('.') ||
                  file.name == '..',
            )
            .toList();
        _sortFiles();
        _resetCursor(preserveItem: prev);
        notifyListeners();
      }
    }

    try {
      List<FileSystemEntity>? entities;
      try {
        entities =
            directorySnapshot ??
            await (allowAccessRequests
                ? _localFileService.listDirectory(listingPath)
                : _localFileService.listDirectorySnapshot(listingPath));
      } on FileSystemException catch (e) {
        if (!stillCurrent()) return;
        if (!allowAccessRequests || !_isPermissionDenied(e)) rethrow;
        // A symlinked folder may point outside the granted root, or a saved
        // bookmark may no longer resolve after a rebuild. Ask for the target
        // folder and retry once.
        final granted = await _localFileService.ensureAccess(listingPath);
        if (!stillCurrent()) return;
        if (!granted) rethrow;
        entities = await _localFileService.listDirectory(listingPath);
      }
      if (!stillCurrent()) return;
      if (entities == null) {
        _files = [];
        _isLoading = false;
        _directoryListingFailure = AppError(
          'Local file access is not supported on this platform.',
          code: PanelErrorCode.localUnsupported,
        );
        if (!kIsWeb) {
          _ref
              .read(errorProvider)
              .addError(
                'Local file access is not supported on this platform.',
                code: PanelErrorCode.localUnsupported,
              );
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
        final metadata = await Future.wait<FileItem?>(
          indices.map((idx) async {
            final item = items[idx];
            if (item.name == '..') return null;
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
              return FileItem(
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
              return null;
            }
          }),
        );
        if (!stillCurrent()) return;
        // Do not mutate the visible list from delayed stat futures. A newer
        // navigation may own it before a batch finishes.
        for (var offset = 0; offset < indices.length; offset++) {
          final updated = metadata[offset];
          if (updated != null) items[indices[offset]] = updated;
        }
        // Re-stamp origins because metadata replaced the FileItem instances.
        _recordOrigins(items, origin);
        notifyListeners();
      }

      if (metadataSort) {
        final prev = cursorItem;
        _sortFiles();
        _resetCursor(preserveItem: prev);
      }
      _isLoading = false;
      if (!stillCurrent()) return;
      dirCache.put(cacheKey, _files!);
      // Fire-and-forget free space fetch (result stored in _freeBytes, shown in status bar)
      _updateFreeSpace(listingPath);
      notifyListeners();
    } catch (e) {
      if (!stillCurrent()) return;
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
        if (!stillCurrent()) return;
        if (fallback != _localPath) {
          _localPath = fallback;
          await _loadLocalFiles(
            fallbackOnMissing: false,
            sourceIsCurrent: sourceIsCurrent,
            allowAccessRequests: allowAccessRequests,
          );
          if (_isDisposed) return;
          _syncTabPath();
          _ref
              .read(errorProvider)
              .addError(
                'Folder not found. Returned to your Home folder.',
                code: PanelErrorCode.homeFallback,
              );
          return;
        }
      }
      if (!kIsWeb &&
          (e is PathAccessException ||
              e.toString().contains('Operation not permitted'))) {
        _files = [];
        _directoryListingFailure = AppError(
          'Permission denied. Use the Browse button to grant access.',
          code: PanelErrorCode.permissionDenied,
          cause: e,
        );
        _ref
            .read(errorProvider)
            .addError(
              'Permission denied. Use the Browse button to grant access.',
              code: PanelErrorCode.permissionDenied,
            );
        notifyListeners();
        return;
      }
      _files = [];
      _directoryListingFailure = AppError(e.toString(), cause: e);
      _ref.read(errorProvider).addError(e.toString(), cause: e);
      notifyListeners();
    }
  }

  /// Read the exact row in the current archive. A same-basename member from
  /// another directory or a row retained from a previous archive is rejected.
  Future<Uint8List> readArchiveMember(
    FileItem file, {
    int maxBytes = kArchiveReadLimit,
  }) async {
    if (!_isCurrentArchiveRow(file) || file.isFolder || file.path == null) {
      throw const ArchiveViewException(
        'This archive row is no longer current. Reopen it.',
      );
    }
    final frame = _archiveFrames.last;
    final generation = _listingGeneration;
    final bytes = await frame.session.read(file.path!, maxBytes: maxBytes);
    if (_isDisposed ||
        generation != _listingGeneration ||
        !identical(_archiveFrames.lastOrNull, frame) ||
        !frame.session.isCurrent) {
      throw const ArchiveViewException(
        'The archive changed while reading this member.',
      );
    }
    return bytes;
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
    if (kIsWeb) return;
    // Debounce: skip if same path was checked within the last 5 seconds.
    final now = DateTime.now();
    if (_lastFreeSpacePath == path &&
        _lastFreeSpaceTime != null &&
        now.difference(_lastFreeSpaceTime!).inSeconds < 5) {
      return;
    }
    _lastFreeSpacePath = path;
    _lastFreeSpaceTime = now;
    final bytes = freeDiskBytes(path);
    _freeBytes = bytes;
    notifyListeners();
  }

  Future<void> _loadRemoteFiles({bool Function()? sourceIsCurrent}) async {
    // When the panel is showing search results, skip the normal directory
    // listing unless clearSearchResults() has already reset the flag.
    if (_showingSearchResults || !(sourceIsCurrent?.call() ?? true)) {
      _log.debug('Skipping _loadRemoteFiles — panel is showing search results');
      return;
    }

    final generation = ++_listingGeneration;
    final auth = _ref.read(authProvider);
    final selected = _remoteSourceForListing();
    final client = selected?.client ?? auth.client;
    final providerName = selected?.providerName ?? auth.providerName;
    final listingPath = _remotePath;
    final origin = _remoteOrigin(client, providerName, listingPath);
    bool stillCurrent() {
      if (_isDisposed || generation != _listingGeneration) return false;
      if (origin.isCurrent && (sourceIsCurrent?.call() ?? true)) return true;
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _requestedListingSource = origin.source;
    _beginDirectoryPresentation(generation, origin);

    _isLoading = true;
    notifyListeners();
    if (sourceIsCurrent != null && !stillCurrent()) return;
    try {
      if (!_isConnectedClient(client)) {
        _files = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Show cached listing immediately for smooth UX.
      final dirCache = _ref.read(directoryCacheProvider);
      final cacheKey = DirectoryCacheService.key(origin.storageId, listingPath);
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
      if (!stillCurrent()) return;

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
      final allItems = [...folders, ...files]
          .where((file) => _showHiddenFiles || !file.name.startsWith('.'))
          .toList();
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
      if (!stillCurrent()) return;
      _log.error('Refresh error', e);
      _isLoading = false;
      // On error, keep cached files if available instead of clearing.
      if (_files == null || _files!.isEmpty) {
        _files = [];
      }
      _directoryListingFailure = AppError(e.toString(), cause: e);
      _ref.read(errorProvider).addError(e.toString(), cause: e);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _saveDepartingCollectionMarks();
    _collectionMarksTimer?.cancel();
    _collectionQueryTimer?.cancel();
    _isDisposed = true;
    for (final request in _activeFolderSizeRequests) {
      request.cancelled = true;
    }
    for (final request in _folderSizeQueue) {
      request.cancelled = true;
      if (!request.completed.isCompleted) request.completed.complete(null);
    }
    _folderSizeQueue.clear();
    _clearArchiveState();
    _typeaheadResetTimer?.cancel();
    _refreshDebounce?.cancel();
    _viewSaveDebounce?.cancel();
    listFocusNode.dispose();
    super.dispose();
  }
}

class _FolderSizeRequest {
  _FolderSizeRequest(this.folder, this.origin, this.isCurrent);
  final FileItem folder;
  final PanelFileOrigin origin;
  final bool Function() isCurrent;
  final completed = Completer<FolderSizeMeasurement?>();
  bool cancelled = false;
}

class FileListImportResult {
  const FileListImportResult({required this.loaded, required this.failures});
  final int loaded;
  final Map<String, String> failures;
}

class PathSelectionSource {
  PathSelectionSource._(this._owner, this.origin, this._isCurrent);
  final PanelNotifier _owner;
  final PanelFileOrigin origin;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();
  String get label => _owner.storageDisplayName(origin.storageReference);
  String get basePath => origin.source.currentPath;
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

class _PanelSwapView {
  const _PanelSwapView({
    required this.source,
    required this.files,
    required this.selection,
    required this.cursor,
    required this.origins,
    required this.collectionEntries,
    required this.directoryOrigin,
    required this.fileList,
    required this.archiveFrames,
    required this.archiveOrigin,
    required this.flat,
  });
  final PanelSource source;
  final List<FileItem> files;
  final Set<FileItem> selection;
  final FileItem? cursor;
  final Map<FileItem, PanelFileOrigin> origins;
  final Map<FileItem, FileCollectionEntry> collectionEntries;
  final PanelFileOrigin? directoryOrigin;
  final _FileListSnapshot? fileList;
  final List<_ArchivePanelFrame> archiveFrames;
  final PanelFileOrigin? archiveOrigin;
  final bool flat;

  Future<void> closeUnclaimedArchives() async {
    final unclaimed = List<_ArchivePanelFrame>.of(archiveFrames);
    archiveFrames.clear();
    for (final frame in unclaimed.reversed) {
      try {
        await frame.session.close();
      } catch (error) {
        PanelNotifier._log.warn('unclaimed archive cleanup failed', error);
      }
    }
  }
}

class _FileListSnapshot {
  const _FileListSnapshot({
    required this.files,
    required this.title,
    required this.origin,
    required this.selection,
    required this.cursor,
    this.collectionId,
    this.search,
    this.collectionPageIndex,
  });
  final List<FileItem> files;
  final String title;
  final PanelFileOrigin? origin;
  final Set<FileItem> selection;
  final FileItem? cursor;
  final String? collectionId;
  final CollectionSearch? search;
  final int? collectionPageIndex;
}

class _ClosedPanelTab {
  _ClosedPanelTab({required this.tab, required this.index, this.fileList});
  final PanelTab tab;
  final int index;
  _FileListSnapshot? fileList;
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

class _ArchivePanelFrame {
  _ArchivePanelFrame(this.session, this.source, {this.returnCursor});
  final ArchiveBrowserSession session;
  ArchivePanelSource source;
  final String? returnCursor;
}
