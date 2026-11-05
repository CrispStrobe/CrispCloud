// lib/providers/search_provider.dart
//
// Manages cloud search and find operations, with advanced filters and
// virtual-folder results.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/file_search_query.dart';
import '../services/file_selection_pattern.dart';
import '../services/file_operation_backend.dart';
import '../services/recursive_search_service.dart';
import 'core_providers.dart';
import '../models/panel_side.dart';
import '../services/log_service.dart';
import '../services/saved_search_service.dart';
import 'error_provider.dart';
import 'panel_provider.dart';

// ---------------------------------------------------------------------------
// Filter model
// ---------------------------------------------------------------------------

/// Categories used for the type-chip filter.
enum FileTypeCategory { documents, images, videos, audio, archives, code }

/// Extensions belonging to each category.
const Map<FileTypeCategory, List<String>> _categoryExtensions = {
  FileTypeCategory.documents: [
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'odt',
    'ods',
    'odp',
    'txt',
    'rtf',
    'md',
    'csv',
  ],
  FileTypeCategory.images: [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'svg',
    'webp',
    'tiff',
    'ico',
    'heic',
    'heif',
  ],
  FileTypeCategory.videos: [
    'mp4',
    'mkv',
    'avi',
    'mov',
    'wmv',
    'flv',
    'webm',
    'm4v',
    'mpg',
    'mpeg',
    '3gp',
  ],
  FileTypeCategory.audio: [
    'mp3',
    'aac',
    'wav',
    'flac',
    'ogg',
    'm4a',
    'wma',
    'aiff',
    'opus',
  ],
  FileTypeCategory.archives: [
    'zip',
    'tar',
    'gz',
    'bz2',
    'xz',
    '7z',
    'rar',
    'tgz',
    'zst',
  ],
  FileTypeCategory.code: [
    'dart',
    'js',
    'ts',
    'py',
    'java',
    'kt',
    'swift',
    'go',
    'rs',
    'c',
    'cpp',
    'h',
    'hpp',
    'cs',
    'rb',
    'php',
    'html',
    'css',
    'json',
    'yaml',
    'yml',
    'xml',
    'sh',
    'bash',
    'sql',
  ],
};

/// Returns every extension that belongs to the given categories.
List<String> extensionsForCategories(Set<FileTypeCategory> categories) {
  final result = <String>[];
  for (final cat in categories) {
    result.addAll(_categoryExtensions[cat] ?? []);
  }
  return result;
}

// ---------------------------------------------------------------------------
// SearchNotifier
// ---------------------------------------------------------------------------

class SearchNotifier extends ChangeNotifier {
  static const _log = Log('SearchNotifier');
  final Ref _ref;
  final _resultOrigins = Expando<PanelFileOrigin>('search account origin');
  PanelSide _resultsSide = PanelSide.remote;
  PanelSide get resultsSide => _resultsSide;
  bool _disposed = false;
  bool _cancelRequested = false;
  bool _wasCancelled = false;
  bool get wasCancelled => _wasCancelled;
  int _scannedCount = 0;
  int get scannedCount => _scannedCount;
  List<String> _searchErrors = [];
  List<String> get searchErrors => List.unmodifiable(_searchErrors);
  FileSearchQuery? _lastQuery;
  FileSearchQuery? get lastQuery => _lastQuery;

  void configureQuery(FileSearchQuery query) {
    query.validate();
    _lastQuery = query;
  }

  void cancelSearch() {
    _cancelRequested = true;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    super.dispose();
  }

  PanelFileOrigin? originForResult(FileItem item) {
    final origin = _resultOrigins[item];
    return origin != null && origin.isCurrent ? origin : null;
  }

  void _recordResultOrigins(Iterable<FileItem> items, PanelFileOrigin origin) {
    if (!origin.isCurrent) {
      throw StateError(
        'The cloud account changed during the search. Run it again.',
      );
    }
    for (final item in items) {
      if (item.path != null &&
          (p.posix.isAbsolute(item.path!) || p.isAbsolute(item.path!))) {
        _resultOrigins[item] = origin;
      }
    }
  }

  // ---- Saved searches ----
  final _savedSearchService = SavedSearchService();
  List<SavedSearch> _savedSearches = [];
  List<SavedSearch> get savedSearches => List.unmodifiable(_savedSearches);

  // ---- Search / find state ----
  bool _isSearching = false;
  bool get isSearching => _isSearching;

  /// Last search/find results — kept for "Show as Folder" usage.
  List<FileItem> _searchResults = [];
  List<FileItem> get searchResults => List.unmodifiable(_searchResults);

  /// When true, the remote panel should display [searchResults] instead of
  /// the actual remote directory listing.
  bool _showResultsAsFolder = false;
  bool get showResultsAsFolder => _showResultsAsFolder;

  // ---- Filters ----

  /// Only include files whose extension (lower-case) is in this set.
  /// Empty set means "no filter" (all extensions pass).
  List<String> _filterByType = [];
  List<String> get filterByType => List.unmodifiable(_filterByType);

  /// Inclusive lower bound for file size in bytes. null = no lower bound.
  int? _filterByMinSize;
  int? get filterByMinSize => _filterByMinSize;

  /// Inclusive upper bound for file size in bytes. null = no upper bound.
  int? _filterByMaxSize;
  int? get filterByMaxSize => _filterByMaxSize;

  /// Only include files updated on or after this date. null = no lower bound.
  DateTime? _filterByDateAfter;
  DateTime? get filterByDateAfter => _filterByDateAfter;

  /// Only include files updated on or before this date. null = no upper bound.
  DateTime? _filterByDateBefore;
  DateTime? get filterByDateBefore => _filterByDateBefore;

  SearchNotifier(this._ref) {
    loadSavedSearches();
  }

  // ---------------------------------------------------------------------------
  // Saved searches
  // ---------------------------------------------------------------------------

  Future<void> loadSavedSearches() async {
    _savedSearches = await _savedSearchService.getAll();
    if (!_disposed) notifyListeners();
  }

  /// Persist the current query and active filters as a saved search.
  Future<void> saveCurrentSearch({
    required String name,
    required String query,
  }) async {
    final search = SavedSearch(
      name: name,
      query: query,
      filterByType: List.of(_filterByType),
      filterByMinSize: _filterByMinSize,
      filterByMaxSize: _filterByMaxSize,
      filterByDateAfter: _filterByDateAfter,
      filterByDateBefore: _filterByDateBefore,
      createdAt: DateTime.now(),
      settings: _lastQuery,
    );
    await _savedSearchService.save(search);
    await loadSavedSearches();
  }

  Future<void> deleteSavedSearch(String name) async {
    await _savedSearchService.delete(name);
    await loadSavedSearches();
  }

  /// Run a saved search and return results.
  Future<List<FileItem>> runSavedSearch(SavedSearch search) =>
      _savedSearchService.run(search, _ref);

  // ---------------------------------------------------------------------------
  // Filter management
  // ---------------------------------------------------------------------------

  /// Update all filter fields at once. Pass null to leave a field unchanged;
  /// to explicitly clear a nullable field, pass a dedicated value (see
  /// [clearFilters]).
  void setFilters({
    List<String>? filterByType,
    int? filterByMinSize,
    int? filterByMaxSize,
    DateTime? filterByDateAfter,
    DateTime? filterByDateBefore,
  }) {
    if (filterByType != null) _filterByType = filterByType;
    if (filterByMinSize != null) _filterByMinSize = filterByMinSize;
    if (filterByMaxSize != null) _filterByMaxSize = filterByMaxSize;
    if (filterByDateAfter != null) _filterByDateAfter = filterByDateAfter;
    if (filterByDateBefore != null) _filterByDateBefore = filterByDateBefore;
    _log.debug('Filters updated', {
      'types': _filterByType,
      'minSize': _filterByMinSize,
      'maxSize': _filterByMaxSize,
      'after': _filterByDateAfter?.toIso8601String(),
      'before': _filterByDateBefore?.toIso8601String(),
    });
    notifyListeners();
  }

  /// Reset every filter to its default (no restriction) state.
  void clearFilters() {
    _filterByType = [];
    _filterByMinSize = null;
    _filterByMaxSize = null;
    _filterByDateAfter = null;
    _filterByDateBefore = null;
    _log.debug('Filters cleared');
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Filter matching
  // ---------------------------------------------------------------------------

  /// Returns true when [item] satisfies all currently active filters.
  bool matchesFilters(FileItem item) {
    // Type filter (folders always pass)
    if (_filterByType.isNotEmpty && !item.isFolder) {
      final ext = _extensionOf(item.name);
      if (!_filterByType.contains(ext)) return false;
    }

    // Size filters (folders have no size — skip size filter for them)
    if (!item.isFolder) {
      if (_filterByMinSize != null && (item.size ?? 0) < _filterByMinSize!) {
        return false;
      }
      if (_filterByMaxSize != null && (item.size ?? 0) > _filterByMaxSize!) {
        return false;
      }
    }

    // Date filters
    if (_filterByDateAfter != null) {
      final d = item.updatedAt;
      if (d == null || d.isBefore(_filterByDateAfter!)) return false;
    }
    if (_filterByDateBefore != null) {
      final d = item.updatedAt;
      if (d == null || d.isAfter(_filterByDateBefore!)) return false;
    }

    return true;
  }

  /// Apply [matchesFilters] to a list and return the passing items.
  List<FileItem> applyFilters(List<FileItem> items) =>
      items.where(matchesFilters).toList();

  // ---------------------------------------------------------------------------
  // Virtual-folder / show-as-folder
  // ---------------------------------------------------------------------------

  /// Store [results] and, when [asFolder] is true, tell the remote panel to
  /// display them as a virtual folder.
  void setSearchResults(
    List<FileItem> results, {
    bool asFolder = false,
    PanelSide side = PanelSide.remote,
    String title = 'Search results',
  }) {
    _searchResults = List.of(results);
    _showResultsAsFolder = asFolder;
    _resultsSide = side;
    _log.info('Search results stored', {
      'count': results.length,
      'asFolder': asFolder,
    });
    if (asFolder) {
      final panel = _ref.read(panelProvider(side));
      panel.showSearchResults(
        results,
        title: title,
        originForFile: (item) =>
            originForResult(item) ?? panel.originForOperation(item),
      );
    }
    notifyListeners();
  }

  /// Clear the virtual-folder view and restore normal directory listing.
  void clearSearchResults() {
    _searchResults = [];
    if (_showResultsAsFolder) {
      _showResultsAsFolder = false;
      _ref.read(panelProvider(_resultsSide)).clearSearchResults();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Search operations
  // ---------------------------------------------------------------------------

  FileSearchQuery queryWithFilters({
    String namePattern = '*',
    FilePatternMode nameMode = FilePatternMode.wildcard,
    String contentPattern = '',
  }) => FileSearchQuery(
    namePattern: namePattern,
    nameMode: nameMode,
    contentPattern: contentPattern,
    extensions: _filterByType,
    minSize: _filterByMinSize,
    maxSize: _filterByMaxSize,
    modifiedAfter: _filterByDateAfter,
    modifiedBefore: _filterByDateBefore,
  );

  /// All entry points now use the same recursive source-bound search engine.
  Future<Map<String, List<FileItem>>> searchFiles(String text) async {
    final files = await runQuery(
      queryWithFilters(
        namePattern: RegExp.escape(text),
        nameMode: FilePatternMode.regex,
      ),
    );
    return {
      'folders': files.where((file) => file.isFolder).toList(),
      'files': files.where((file) => !file.isFolder).toList(),
    };
  }

  Future<List<FileItem>> findFiles(String pattern) =>
      runQuery(queryWithFilters(namePattern: pattern));

  Future<List<FileItem>> fullTextSearch(String text) =>
      runQuery(queryWithFilters(contentPattern: text));

  Map<String, String> _lastSnippets = {};
  Map<String, String> get lastSnippets => Map.unmodifiable(_lastSnippets);

  Future<List<FileItem>> runQuery(
    FileSearchQuery query, {
    PanelSide? side,
  }) async {
    if (_isSearching || _disposed) return [];
    query.validate();
    _lastQuery = query;
    _isSearching = true;
    _cancelRequested = false;
    _wasCancelled = false;
    _searchResults = [];
    _lastSnippets = {};
    _searchErrors = [];
    _scannedCount = 0;
    _resultsSide = side ?? _ref.read(activePanelProvider);
    notifyListeners();
    try {
      final panel = _ref.read(panelProvider(_resultsSide));
      final origin = panel.captureCurrentOrigin();
      final source = fileOperationBackend(
        source: origin.source,
        local: _ref.read(localFileServiceProvider),
        isCurrent: () => !_disposed && origin.isCurrent,
      );
      final result = await RecursiveSearchService().search(
        source,
        query,
        currentDirectory: panel.currentPath,
        isCancelled: () => _cancelRequested || _disposed,
        onMatch: (match) {
          if (_disposed || !origin.isCurrent) return;
          final index = _searchResults.indexWhere(
            (item) => item.path == match.file.path,
          );
          var file = match.file;
          var snippet = match.snippet;
          if (match.archiveMember != null) {
            snippet = '${match.archiveMember}: $snippet';
            final previous = index < 0 ? null : _searchResults[index];
            file = file.copyWith(
              metadata: {
                ...?file.metadata,
                'matchingArchiveMembers': [
                  ...?(previous?.metadata?['matchingArchiveMembers'] as List?),
                  match.archiveMember,
                ],
              },
            );
          }
          if (index < 0) {
            _searchResults.add(file);
          } else {
            _searchResults[index] = file;
          }
          _recordResultOrigins([file], origin);
          if (snippet.isNotEmpty) _lastSnippets[file.path!] = snippet;
          notifyListeners();
        },
        onProgress: (count, path) {
          _scannedCount = count;
          if (!_disposed && count % 32 == 0) notifyListeners();
        },
      );
      if (_disposed) return [];
      _searchErrors = result.errors;
      _wasCancelled = result.cancelled;
      _scannedCount = result.scanned;
      if (!origin.isCurrent) {
        _searchResults = [];
        _lastSnippets = {};
        _searchErrors.add(
          'The storage connection changed. Run the search again.',
        );
      }
      return List.of(_searchResults);
    } catch (error) {
      if (!_disposed) {
        _searchErrors.add(error.toString());
        _ref.read(errorProvider).addError('Search failed: $error');
      }
      return [];
    } finally {
      _isSearching = false;
      if (!_disposed) notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _extensionOf(String name) {
    final idx = name.lastIndexOf('.');
    if (idx == -1 || idx == name.length - 1) return '';
    return name.substring(idx + 1).toLowerCase();
  }
}

final searchProvider = ChangeNotifierProvider<SearchNotifier>((ref) {
  return SearchNotifier(ref);
});
