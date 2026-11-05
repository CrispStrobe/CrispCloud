// lib/services/saved_search_service.dart
//
// Saved search persistence and execution.
// Searches are stored as a JSON list in SharedPreferences.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_item.dart';
import '../models/file_search_query.dart';
import '../providers/search_provider.dart';
import 'log_service.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class SavedSearch {
  final String name;
  final String query;
  final List<String> filterByType; // file extensions
  final int? filterByMinSize; // bytes
  final int? filterByMaxSize; // bytes
  final DateTime? filterByDateAfter;
  final DateTime? filterByDateBefore;
  final DateTime createdAt;
  final FileSearchQuery? settings;

  const SavedSearch({
    required this.name,
    required this.query,
    this.filterByType = const [],
    this.filterByMinSize,
    this.filterByMaxSize,
    this.filterByDateAfter,
    this.filterByDateBefore,
    required this.createdAt,
    this.settings,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'query': query,
    'filterByType': filterByType,
    if (filterByMinSize != null) 'filterByMinSize': filterByMinSize,
    if (filterByMaxSize != null) 'filterByMaxSize': filterByMaxSize,
    if (filterByDateAfter != null)
      'filterByDateAfter': filterByDateAfter!.toIso8601String(),
    if (filterByDateBefore != null)
      'filterByDateBefore': filterByDateBefore!.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    if (settings != null) 'settings': settings!.toJson(),
  };

  factory SavedSearch.fromJson(Map<String, dynamic> json) => SavedSearch(
    name: json['name'] as String,
    query: json['query'] as String,
    filterByType:
        (json['filterByType'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
    filterByMinSize: json['filterByMinSize'] as int?,
    filterByMaxSize: json['filterByMaxSize'] as int?,
    filterByDateAfter: json['filterByDateAfter'] != null
        ? DateTime.tryParse(json['filterByDateAfter'] as String)
        : null,
    filterByDateBefore: json['filterByDateBefore'] != null
        ? DateTime.tryParse(json['filterByDateBefore'] as String)
        : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
    settings: json['settings'] is Map
        ? FileSearchQuery.fromJson(
            Map<String, dynamic>.from(json['settings'] as Map),
          )
        : null,
  );

  /// Human-readable summary of active filters.
  String get filterSummary {
    final parts = <String>[];
    if (settings != null) {
      final query = settings!;
      parts.add('${query.nameMode.name}: ${query.namePattern}');
      parts.add(query.recursive ? 'recursive' : 'current directory');
      if (query.maxDepth != null) parts.add('depth ${query.maxDepth}');
      if (query.contentPattern.isNotEmpty) {
        parts.add(
          'content${query.contentRegex ? " regex" : ""}: ${query.contentPattern}',
        );
      }
      if (query.searchArchives) parts.add('inside archives');
      if (query.roots.isNotEmpty) parts.add(query.roots.join('; '));
    }
    if (filterByType.isNotEmpty) {
      parts.add(
        'type: ${filterByType.take(3).join(', ')}${filterByType.length > 3 ? '…' : ''}',
      );
    }
    if (filterByMinSize != null) {
      parts.add('min: ${_fmtSize(filterByMinSize!)}');
    }
    if (filterByMaxSize != null) {
      parts.add('max: ${_fmtSize(filterByMaxSize!)}');
    }
    if (filterByDateAfter != null) {
      parts.add('after: ${_fmtDate(filterByDateAfter!)}');
    }
    if (filterByDateBefore != null) {
      parts.add('before: ${_fmtDate(filterByDateBefore!)}');
    }
    return parts.isEmpty ? 'No filters' : parts.join(' · ');
  }

  static String _fmtSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class SavedSearchService {
  static const _log = Log('SavedSearchService');
  static const _prefsKey = 'saved_searches';

  /// Load all saved searches from SharedPreferences.
  Future<List<SavedSearch>> getAll({bool strict = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SavedSearch.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log.error('Failed to load saved searches: $e');
      if (strict) rethrow;
      return [];
    }
  }

  /// Persist [search]. Replaces any existing search with the same name.
  Future<void> save(SavedSearch search) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final searches = await getAll(strict: true);
      // Remove existing with same name, then add new
      searches.removeWhere((s) => s.name == search.name);
      searches.add(search);
      final saved = await prefs.setString(
        _prefsKey,
        jsonEncode(searches.map((s) => s.toJson()).toList()),
      );
      if (!saved) throw StateError('Saved criteria could not be persisted.');
      _log.info('Saved search "${search.name}"');
    } catch (e) {
      _log.error('Failed to save search "${search.name}": $e');
      rethrow;
    }
  }

  /// Delete the saved search with [name].
  Future<void> delete(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final searches = await getAll(strict: true);
      searches.removeWhere((s) => s.name == name);
      final saved = await prefs.setString(
        _prefsKey,
        jsonEncode(searches.map((s) => s.toJson()).toList()),
      );
      if (!saved) throw StateError('Saved criteria could not be persisted.');
      _log.info('Deleted saved search "$name"');
    } catch (e) {
      _log.error('Failed to delete saved search "$name": $e');
      rethrow;
    }
  }

  /// Apply [search]'s filters to the search provider and execute the query.
  /// Returns the matched files.
  Future<List<FileItem>> run(SavedSearch search, Ref ref) async {
    final searchNotifier = ref.read(searchProvider);
    searchNotifier.clearFilters();
    searchNotifier.setFilters(
      filterByType: search.filterByType,
      filterByMinSize: search.filterByMinSize,
      filterByMaxSize: search.filterByMaxSize,
      filterByDateAfter: search.filterByDateAfter,
      filterByDateBefore: search.filterByDateBefore,
    );
    _log.info(
      'Running saved search "${search.name}" (query: "${search.query}")',
    );
    return search.settings == null
        ? searchNotifier.findFiles(search.query)
        : searchNotifier.runQuery(search.settings!);
  }
}
