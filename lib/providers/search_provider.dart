// lib/providers/search_provider.dart
//
// Manages cloud search and find operations, with advanced filters and
// virtual-folder results.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../services/internxt_client_adapter.dart';
import '../services/log_service.dart';
import '../services/saved_search_service.dart';
import 'auth_provider.dart';
import 'error_provider.dart';
import 'panel_provider.dart';

// ---------------------------------------------------------------------------
// Filter model
// ---------------------------------------------------------------------------

/// Categories used for the type-chip filter.
enum FileTypeCategory { documents, images, videos, audio, archives, code }

/// Extensions belonging to each category.
const Map<FileTypeCategory, List<String>> _categoryExtensions = {
  FileTypeCategory.documents: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'txt', 'rtf', 'md', 'csv'],
  FileTypeCategory.images: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'tiff', 'ico', 'heic', 'heif'],
  FileTypeCategory.videos: ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg', '3gp'],
  FileTypeCategory.audio: ['mp3', 'aac', 'wav', 'flac', 'ogg', 'm4a', 'wma', 'aiff', 'opus'],
  FileTypeCategory.archives: ['zip', 'tar', 'gz', 'bz2', 'xz', '7z', 'rar', 'tgz', 'zst'],
  FileTypeCategory.code: ['dart', 'js', 'ts', 'py', 'java', 'kt', 'swift', 'go', 'rs', 'c', 'cpp', 'h', 'hpp', 'cs', 'rb', 'php', 'html', 'css', 'json', 'yaml', 'yml', 'xml', 'sh', 'bash', 'sql'],
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
    notifyListeners();
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
  void setSearchResults(List<FileItem> results, {bool asFolder = false}) {
    _searchResults = List.of(results);
    _showResultsAsFolder = asFolder;
    _log.info('Search results stored', {'count': results.length, 'asFolder': asFolder});
    if (asFolder) {
      final panel = _ref.read(panelProvider(PanelSide.remote));
      panel.showSearchResults(results);
    }
    notifyListeners();
  }

  /// Clear the virtual-folder view and restore normal directory listing.
  void clearSearchResults() {
    _searchResults = [];
    if (_showResultsAsFolder) {
      _showResultsAsFolder = false;
      _ref.read(panelProvider(PanelSide.remote)).clearSearchResults();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Search operations
  // ---------------------------------------------------------------------------

  Future<Map<String, List<FileItem>>> searchFiles(String query) async {
    if (_isSearching) return {};
    _isSearching = true;
    notifyListeners();

    try {
      final client = _ref.read(authProvider).client;
      if (client is InternxtClientAdapter) {
        final results = await client.search(query, detailed: true);

        final folders = (results['folders'] as List<dynamic>?)
            ?.map((item) => FileItem(
                  name: item['fullPath'] ?? item['name'],
                  isFolder: true,
                  uuid: item['uuid'],
                  path: item['fullPath'],
                ))
            .toList() ?? [];

        final files = (results['files'] as List<dynamic>?)
            ?.map((item) {
              final plainName = item['name'] ?? 'Unknown';
              final fileType = item['type'] ?? '';
              final fullName = (fileType.isNotEmpty && !plainName.endsWith(fileType))
                  ? '$plainName.$fileType'
                  : plainName;
              return FileItem(
                name: item['fullPath'] ?? fullName,
                isFolder: false,
                uuid: item['uuid'],
                path: item['fullPath'],
              );
            })
            .toList() ?? [];

        // Apply client-side filters
        final filteredFolders = applyFilters(folders);
        final filteredFiles = applyFilters(files);

        _isSearching = false;
        notifyListeners();
        return {'folders': filteredFolders, 'files': filteredFiles};
      } else {
        throw UnsupportedError('Search not supported for ${client.providerName}');
      }
    } catch (e) {
      _ref.read(errorProvider).addError('Search failed: $e');
      _isSearching = false;
      notifyListeners();
      return {};
    }
  }

  /// Perform a full-text (content) search using the active provider.
  /// Returns matching files with context snippets.
  Future<List<FileItem>> fullTextSearch(String query) async {
    if (_isSearching) return [];
    _isSearching = true;
    notifyListeners();

    try {
      final client = _ref.read(authProvider).client;
      final remotePath = _ref.read(panelProvider(PanelSide.remote)).currentPath;

      final results = await client.fullTextSearch(query, remotePath);
      final files = results.map((map) => FileItem(
        name: map['name'] as String? ?? 'Unknown',
        isFolder: false,
        uuid: map['uuid'] as String?,
        size: map['size'] as int?,
        path: map['path'] as String?,
        updatedAt: DateTime.tryParse(map['lastModified'] ?? ''),
      )).toList();

      // Apply client-side filters
      final filtered = applyFilters(files);

      // Store snippets for UI display (keyed by file path or name)
      _lastSnippets = {
        for (final map in results)
          (map['path'] ?? map['name']) as String: (map['snippet'] ?? '') as String,
      };

      _isSearching = false;
      notifyListeners();
      return filtered;
    } catch (e) {
      _ref.read(errorProvider).addError('Full-text search failed: $e');
      _isSearching = false;
      notifyListeners();
      return [];
    }
  }

  /// Snippets from the last full-text search, keyed by file path.
  Map<String, String> _lastSnippets = {};
  Map<String, String> get lastSnippets => Map.unmodifiable(_lastSnippets);

  Future<List<FileItem>> findFiles(String pattern) async {
    if (_isSearching) return [];
    _isSearching = true;
    notifyListeners();

    try {
      final client = _ref.read(authProvider).client;
      final remotePath = _ref.read(panelProvider(PanelSide.remote)).currentPath;

      if (client is InternxtClientAdapter) {
        final results = await client.findFiles(remotePath, pattern, maxDepth: -1);
        final files = results.map((item) {
          final plainName = item['name'] ?? 'Unknown';
          final fileType = item['fileType'] ?? '';
          final fullName = (fileType.isNotEmpty && !plainName.endsWith(fileType))
              ? '$plainName.$fileType'
              : plainName;
          return FileItem(
            name: item['fullPath'] ?? fullName,
            isFolder: false,
            uuid: item['uuid'],
            size: item['size'] as int?,
            path: item['fullPath'],
            updatedAt: DateTime.tryParse(item['updatedAt'] ?? ''),
          );
        }).toList();

        // Apply client-side filters
        final filtered = applyFilters(files);

        _isSearching = false;
        notifyListeners();
        return filtered;
      } else {
        throw UnsupportedError('Find not supported for ${client.providerName}');
      }
    } catch (e) {
      _ref.read(errorProvider).addError('Find failed: $e');
      _isSearching = false;
      notifyListeners();
      return [];
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
