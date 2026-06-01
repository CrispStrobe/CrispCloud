// lib/services/storage_analytics_service.dart
//
// Storage analytics: categorization, duplicate detection, stale file
// detection, and cleanup suggestions across all connected providers.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_item.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum FileCategory {
  documents,
  images,
  videos,
  audio,
  code,
  archives,
  databases,
  fonts,
  other,
}

// ---------------------------------------------------------------------------
// Extension-to-category mapping
// ---------------------------------------------------------------------------

const Map<String, FileCategory> _extMap = {
  // Documents
  'pdf': FileCategory.documents,
  'doc': FileCategory.documents,
  'docx': FileCategory.documents,
  'odt': FileCategory.documents,
  'rtf': FileCategory.documents,
  'txt': FileCategory.documents,
  'md': FileCategory.documents,
  'markdown': FileCategory.documents,
  'tex': FileCategory.documents,
  'xls': FileCategory.documents,
  'xlsx': FileCategory.documents,
  'ods': FileCategory.documents,
  'csv': FileCategory.documents,
  'ppt': FileCategory.documents,
  'pptx': FileCategory.documents,
  'odp': FileCategory.documents,
  'pages': FileCategory.documents,
  'numbers': FileCategory.documents,
  'keynote': FileCategory.documents,
  'epub': FileCategory.documents,
  'mobi': FileCategory.documents,

  // Images
  'jpg': FileCategory.images,
  'jpeg': FileCategory.images,
  'png': FileCategory.images,
  'gif': FileCategory.images,
  'bmp': FileCategory.images,
  'tiff': FileCategory.images,
  'tif': FileCategory.images,
  'webp': FileCategory.images,
  'svg': FileCategory.images,
  'ico': FileCategory.images,
  'heic': FileCategory.images,
  'heif': FileCategory.images,
  'raw': FileCategory.images,
  'cr2': FileCategory.images,
  'nef': FileCategory.images,
  'arw': FileCategory.images,
  'dng': FileCategory.images,
  'psd': FileCategory.images,
  'ai': FileCategory.images,
  'eps': FileCategory.images,

  // Videos
  'mp4': FileCategory.videos,
  'mkv': FileCategory.videos,
  'avi': FileCategory.videos,
  'mov': FileCategory.videos,
  'wmv': FileCategory.videos,
  'flv': FileCategory.videos,
  'webm': FileCategory.videos,
  'm4v': FileCategory.videos,
  'mpeg': FileCategory.videos,
  'mpg': FileCategory.videos,
  '3gp': FileCategory.videos,
  'ogv': FileCategory.videos,
  'mts': FileCategory.videos,
  'm2ts': FileCategory.videos,
  'vob': FileCategory.videos,

  // Audio
  'mp3': FileCategory.audio,
  'aac': FileCategory.audio,
  'wav': FileCategory.audio,
  'flac': FileCategory.audio,
  'ogg': FileCategory.audio,
  'opus': FileCategory.audio,
  'm4a': FileCategory.audio,
  'wma': FileCategory.audio,
  'aiff': FileCategory.audio,
  'aif': FileCategory.audio,
  'mid': FileCategory.audio,
  'midi': FileCategory.audio,
  'amr': FileCategory.audio,

  // Code
  'dart': FileCategory.code,
  'py': FileCategory.code,
  'js': FileCategory.code,
  'ts': FileCategory.code,
  'jsx': FileCategory.code,
  'tsx': FileCategory.code,
  'java': FileCategory.code,
  'kt': FileCategory.code,
  'swift': FileCategory.code,
  'go': FileCategory.code,
  'rs': FileCategory.code,
  'cpp': FileCategory.code,
  'cc': FileCategory.code,
  'cxx': FileCategory.code,
  'c': FileCategory.code,
  'h': FileCategory.code,
  'hpp': FileCategory.code,
  'cs': FileCategory.code,
  'rb': FileCategory.code,
  'php': FileCategory.code,
  'html': FileCategory.code,
  'htm': FileCategory.code,
  'css': FileCategory.code,
  'scss': FileCategory.code,
  'sass': FileCategory.code,
  'less': FileCategory.code,
  'xml': FileCategory.code,
  'json': FileCategory.code,
  'yaml': FileCategory.code,
  'yml': FileCategory.code,
  'toml': FileCategory.code,
  'ini': FileCategory.code,
  'sh': FileCategory.code,
  'bash': FileCategory.code,
  'zsh': FileCategory.code,
  'fish': FileCategory.code,
  'ps1': FileCategory.code,
  'bat': FileCategory.code,
  'cmd': FileCategory.code,
  'r': FileCategory.code,
  'scala': FileCategory.code,
  'lua': FileCategory.code,
  'pl': FileCategory.code,
  'elm': FileCategory.code,
  'ex': FileCategory.code,
  'exs': FileCategory.code,
  'clj': FileCategory.code,
  'hs': FileCategory.code,
  'vue': FileCategory.code,
  'svelte': FileCategory.code,

  // Archives
  'zip': FileCategory.archives,
  'tar': FileCategory.archives,
  'gz': FileCategory.archives,
  'bz2': FileCategory.archives,
  'xz': FileCategory.archives,
  'zst': FileCategory.archives,
  '7z': FileCategory.archives,
  'rar': FileCategory.archives,
  'cab': FileCategory.archives,
  'iso': FileCategory.archives,
  'dmg': FileCategory.archives,
  'pkg': FileCategory.archives,
  'deb': FileCategory.archives,
  'rpm': FileCategory.archives,
  'apk': FileCategory.archives,
  'ipa': FileCategory.archives,
  'jar': FileCategory.archives,
  'war': FileCategory.archives,
  'ear': FileCategory.archives,
  'tgz': FileCategory.archives,
  'tbz2': FileCategory.archives,
  'txz': FileCategory.archives,
  'lz': FileCategory.archives,
  'lzma': FileCategory.archives,
  'z': FileCategory.archives,

  // Databases
  'db': FileCategory.databases,
  'sqlite': FileCategory.databases,
  'sqlite3': FileCategory.databases,
  'sql': FileCategory.databases,
  'mdb': FileCategory.databases,
  'accdb': FileCategory.databases,
  'dbf': FileCategory.databases,
  'fdb': FileCategory.databases,
  'sdf': FileCategory.databases,
  'nsf': FileCategory.databases,

  // Fonts
  'ttf': FileCategory.fonts,
  'otf': FileCategory.fonts,
  'woff': FileCategory.fonts,
  'woff2': FileCategory.fonts,
  'eot': FileCategory.fonts,
  'fon': FileCategory.fonts,
  'fnt': FileCategory.fonts,
};

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Per-category aggregated stats.
class CategoryStats {
  final int fileCount;
  final int totalBytes;
  final double percentage;

  const CategoryStats({
    required this.fileCount,
    required this.totalBytes,
    required this.percentage,
  });

  Map<String, dynamic> toJson() => {
        'fileCount': fileCount,
        'totalBytes': totalBytes,
        'percentage': percentage,
      };

  factory CategoryStats.fromJson(Map<String, dynamic> j) => CategoryStats(
        fileCount: (j['fileCount'] as num).toInt(),
        totalBytes: (j['totalBytes'] as num).toInt(),
        percentage: (j['percentage'] as num).toDouble(),
      );
}

/// A file that hasn't been accessed recently.
class StaleFile {
  final String path;
  final String provider;
  final int sizeBytes;
  final DateTime? lastAccessed;
  final int daysSinceAccess;

  const StaleFile({
    required this.path,
    required this.provider,
    required this.sizeBytes,
    this.lastAccessed,
    required this.daysSinceAccess,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'provider': provider,
        'sizeBytes': sizeBytes,
        'lastAccessed': lastAccessed?.toIso8601String(),
        'daysSinceAccess': daysSinceAccess,
      };

  factory StaleFile.fromJson(Map<String, dynamic> j) => StaleFile(
        path: j['path'] as String,
        provider: j['provider'] as String,
        sizeBytes: (j['sizeBytes'] as num).toInt(),
        lastAccessed: j['lastAccessed'] != null
            ? DateTime.tryParse(j['lastAccessed'] as String)
            : null,
        daysSinceAccess: (j['daysSinceAccess'] as num).toInt(),
      );
}

/// One entry in a duplicate group.
class DuplicateEntry {
  final String path;
  final String provider;
  final int sizeBytes;
  final DateTime? modifiedAt;

  const DuplicateEntry({
    required this.path,
    required this.provider,
    required this.sizeBytes,
    this.modifiedAt,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'provider': provider,
        'sizeBytes': sizeBytes,
        'modifiedAt': modifiedAt?.toIso8601String(),
      };

  factory DuplicateEntry.fromJson(Map<String, dynamic> j) => DuplicateEntry(
        path: j['path'] as String,
        provider: j['provider'] as String,
        sizeBytes: (j['sizeBytes'] as num).toInt(),
        modifiedAt: j['modifiedAt'] != null
            ? DateTime.tryParse(j['modifiedAt'] as String)
            : null,
      );
}

/// A group of files that appear to be duplicates (same name + same size).
class DuplicateGroup {
  /// Key is "<size>:<lowercased-basename>".
  final String key;
  final List<DuplicateEntry> entries;

  const DuplicateGroup({required this.key, required this.entries});

  /// Bytes that could be reclaimed by keeping only one copy.
  int get wastedBytes {
    if (entries.isEmpty) return 0;
    return entries.first.sizeBytes * (entries.length - 1);
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory DuplicateGroup.fromJson(Map<String, dynamic> j) => DuplicateGroup(
        key: j['key'] as String,
        entries: (j['entries'] as List)
            .map((e) => DuplicateEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

enum CleanupType { duplicate, stale, large }

/// A single actionable cleanup recommendation.
class CleanupSuggestion {
  final CleanupType type;
  final String description;
  final int savingsBytes;
  final List<String> files;

  const CleanupSuggestion({
    required this.type,
    required this.description,
    required this.savingsBytes,
    required this.files,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'description': description,
        'savingsBytes': savingsBytes,
        'files': files,
      };

  factory CleanupSuggestion.fromJson(Map<String, dynamic> j) =>
      CleanupSuggestion(
        type: CleanupType.values.firstWhere((t) => t.name == j['type']),
        description: j['description'] as String,
        savingsBytes: (j['savingsBytes'] as num).toInt(),
        files: List<String>.from(j['files'] as List),
      );
}

/// Full storage analysis for one provider.
class StorageBreakdown {
  final String providerId;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final Map<FileCategory, CategoryStats> categoryBreakdowns;
  final List<StaleFile> staleFiles;
  final List<FileItem> largestFiles;
  final DateTime analyzedAt;

  const StorageBreakdown({
    required this.providerId,
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.categoryBreakdowns,
    required this.staleFiles,
    required this.largestFiles,
    required this.analyzedAt,
  });

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'totalBytes': totalBytes,
        'usedBytes': usedBytes,
        'freeBytes': freeBytes,
        'categoryBreakdowns': categoryBreakdowns.map(
          (k, v) => MapEntry(k.name, v.toJson()),
        ),
        'staleFiles': staleFiles.map((f) => f.toJson()).toList(),
        'analyzedAt': analyzedAt.toIso8601String(),
      };

  factory StorageBreakdown.fromJson(Map<String, dynamic> j) {
    final catMap = <FileCategory, CategoryStats>{};
    final rawCat = j['categoryBreakdowns'] as Map<String, dynamic>? ?? {};
    for (final entry in rawCat.entries) {
      final cat = FileCategory.values.firstWhere(
        (c) => c.name == entry.key,
        orElse: () => FileCategory.other,
      );
      catMap[cat] = CategoryStats.fromJson(entry.value as Map<String, dynamic>);
    }
    return StorageBreakdown(
      providerId: j['providerId'] as String,
      totalBytes: (j['totalBytes'] as num).toInt(),
      usedBytes: (j['usedBytes'] as num).toInt(),
      freeBytes: (j['freeBytes'] as num).toInt(),
      categoryBreakdowns: catMap,
      staleFiles: (j['staleFiles'] as List? ?? [])
          .map((e) => StaleFile.fromJson(e as Map<String, dynamic>))
          .toList(),
      largestFiles: const [],
      analyzedAt: DateTime.parse(j['analyzedAt'] as String),
    );
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class StorageAnalyticsService {
  static const _cacheKeyPrefix = 'analytics_cache_';
  static const _cacheTtlHours = 1;

  // -------------------------------------------------------------------------
  // File categorization
  // -------------------------------------------------------------------------

  /// Returns the [FileCategory] for [filename] based on its extension.
  FileCategory categorizeFile(String filename) {
    final name = filename.trim();
    if (name.isEmpty) return FileCategory.other;

    // Extract extension: take everything after the LAST dot.
    final lastDot = name.lastIndexOf('.');
    if (lastDot < 0 || lastDot == name.length - 1) return FileCategory.other;

    final ext = name.substring(lastDot + 1).toLowerCase();
    return _extMap[ext] ?? FileCategory.other;
  }

  // -------------------------------------------------------------------------
  // Provider analysis
  // -------------------------------------------------------------------------

  /// Analyse a flat list of [FileItem]s for a provider and return a
  /// [StorageBreakdown].  [staleDays] defaults to 180 days.
  StorageBreakdown analyzeProvider(
    String providerId,
    List<FileItem> files, {
    int staleDays = 180,
    int topN = 10,
  }) {
    final fileItems = files.where((f) => !f.isFolder).toList();

    // Accumulate per-category byte/count totals.
    final counts = <FileCategory, int>{};
    final bytes = <FileCategory, int>{};
    var usedBytes = 0;

    for (final f in fileItems) {
      final size = f.size ?? 0;
      final cat = categorizeFile(f.name);
      counts[cat] = (counts[cat] ?? 0) + 1;
      bytes[cat] = (bytes[cat] ?? 0) + size;
      usedBytes += size;
    }

    final categoryBreakdowns = <FileCategory, CategoryStats>{};
    for (final cat in FileCategory.values) {
      final cnt = counts[cat] ?? 0;
      final b = bytes[cat] ?? 0;
      final pct = usedBytes > 0 ? (b / usedBytes) * 100.0 : 0.0;
      categoryBreakdowns[cat] = CategoryStats(
        fileCount: cnt,
        totalBytes: b,
        percentage: pct,
      );
    }

    final stale = findStaleFiles(fileItems, staleDays, providerId: providerId);
    final largest = findLargestFiles(fileItems, topN);

    return StorageBreakdown(
      providerId: providerId,
      totalBytes: 0, // provider quota unknown without API call
      usedBytes: usedBytes,
      freeBytes: 0,
      categoryBreakdowns: categoryBreakdowns,
      staleFiles: stale,
      largestFiles: largest,
      analyzedAt: DateTime.now(),
    );
  }

  // -------------------------------------------------------------------------
  // Stale files
  // -------------------------------------------------------------------------

  /// Returns files not modified for [staleDays] or more.
  List<StaleFile> findStaleFiles(
    List<FileItem> files,
    int staleDays, {
    String providerId = '',
  }) {
    final now = DateTime.now();
    final result = <StaleFile>[];

    for (final f in files) {
      if (f.isFolder) continue;
      final updated = f.updatedAt;
      if (updated == null) continue;

      final age = now.difference(updated).inDays;
      if (age >= staleDays) {
        result.add(StaleFile(
          path: f.path ?? f.name,
          provider: providerId,
          sizeBytes: f.size ?? 0,
          lastAccessed: updated,
          daysSinceAccess: age,
        ));
      }
    }

    // Largest stale files first.
    result.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return result;
  }

  // -------------------------------------------------------------------------
  // Largest files
  // -------------------------------------------------------------------------

  /// Returns the [topN] largest files (folders excluded), sorted descending.
  List<FileItem> findLargestFiles(List<FileItem> files, int topN) {
    final sortable = files.where((f) => !f.isFolder && f.size != null).toList();
    sortable.sort((a, b) => (b.size ?? 0).compareTo(a.size ?? 0));
    return sortable.take(topN).toList();
  }

  // -------------------------------------------------------------------------
  // Cross-provider duplicate detection
  // -------------------------------------------------------------------------

  /// Finds files with the same name (case-insensitive) AND the same size
  /// across all providers in [allFiles].  Returns groups with >= 2 entries.
  List<DuplicateGroup> findDuplicatesAcrossProviders(
    Map<String, List<FileItem>> allFiles,
  ) {
    // bucket key → list of DuplicateEntry
    final buckets = <String, List<DuplicateEntry>>{};

    allFiles.forEach((providerId, files) {
      for (final f in files) {
        if (f.isFolder) continue;
        final size = f.size;
        if (size == null || size == 0) continue;

        final basename = f.name.toLowerCase();
        final key = '$size:$basename';

        buckets.putIfAbsent(key, () => []).add(DuplicateEntry(
          path: f.path ?? f.name,
          provider: providerId,
          sizeBytes: size,
          modifiedAt: f.updatedAt,
        ));
      }
    });

    final groups = <DuplicateGroup>[];
    buckets.forEach((key, entries) {
      if (entries.length >= 2) {
        groups.add(DuplicateGroup(key: key, entries: entries));
      }
    });

    // Most wasteful groups first.
    groups.sort((a, b) => b.wastedBytes.compareTo(a.wastedBytes));
    return groups;
  }

  // -------------------------------------------------------------------------
  // Cleanup suggestions
  // -------------------------------------------------------------------------

  /// Generates actionable [CleanupSuggestion]s from analysis results.
  List<CleanupSuggestion> generateCleanupSuggestions(
    List<StorageBreakdown> breakdowns,
    List<DuplicateGroup> duplicates,
    List<StaleFile> staleFiles,
  ) {
    final suggestions = <CleanupSuggestion>[];

    // 1. Duplicate groups
    for (final group in duplicates) {
      if (group.wastedBytes <= 0) continue;
      final providerList =
          group.entries.map((e) => '${e.provider}:${e.path}').toSet().toList();
      final providers = group.entries.map((e) => e.provider).toSet().toList()
        ..sort();

      final basename = group.key.split(':').skip(1).join(':');
      suggestions.add(CleanupSuggestion(
        type: CleanupType.duplicate,
        description:
            'Duplicate "$basename" found on ${providers.join(", ")} '
            '(${_fmtBytes(group.wastedBytes)} wasted)',
        savingsBytes: group.wastedBytes,
        files: providerList,
      ));
    }

    // 2. Stale files (grouped into a single suggestion if many)
    if (staleFiles.isNotEmpty) {
      final totalStaleBytes =
          staleFiles.fold<int>(0, (s, f) => s + f.sizeBytes);
      suggestions.add(CleanupSuggestion(
        type: CleanupType.stale,
        description:
            '${staleFiles.length} stale file(s) not modified recently '
            '(${_fmtBytes(totalStaleBytes)} recoverable)',
        savingsBytes: totalStaleBytes,
        files: staleFiles.map((f) => '${f.provider}:${f.path}').toList(),
      ));
    }

    // 3. Large files from every breakdown
    for (final breakdown in breakdowns) {
      for (final f in breakdown.largestFiles) {
        final size = f.size ?? 0;
        if (size < 100 * 1024 * 1024) continue; // only flag ≥100 MB
        suggestions.add(CleanupSuggestion(
          type: CleanupType.large,
          description:
              'Large file "${f.name}" on ${breakdown.providerId} '
              '(${_fmtBytes(size)})',
          savingsBytes: size,
          files: ['${breakdown.providerId}:${f.path ?? f.name}'],
        ));
      }
    }

    // Highest savings first.
    suggestions.sort((a, b) => b.savingsBytes.compareTo(a.savingsBytes));
    return suggestions;
  }

  /// Total bytes recoverable if all [suggestions] are acted upon.
  int estimateSavings(List<CleanupSuggestion> suggestions) {
    return suggestions.fold<int>(0, (s, c) => s + c.savingsBytes);
  }

  // -------------------------------------------------------------------------
  // Persistence (SharedPreferences cache)
  // -------------------------------------------------------------------------

  /// Persist a [StorageBreakdown] to SharedPreferences.
  Future<void> cacheBreakdown(StorageBreakdown breakdown) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_cacheKeyPrefix${breakdown.providerId}';
      await prefs.setString(key, jsonEncode(breakdown.toJson()));
    } catch (_) {}
  }

  /// Load a cached [StorageBreakdown] for [providerId].
  /// Returns null if absent or expired (> [_cacheTtlHours] hours old).
  Future<StorageBreakdown?> loadCachedBreakdown(String providerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_cacheKeyPrefix$providerId';
      final raw = prefs.getString(key);
      if (raw == null) return null;

      final json = jsonDecode(raw) as Map<String, dynamic>;
      final breakdown = StorageBreakdown.fromJson(json);
      final age = DateTime.now().difference(breakdown.analyzedAt);
      if (age.inHours >= _cacheTtlHours) return null;
      return breakdown;
    } catch (_) {
      return null;
    }
  }

  /// Clear the cached breakdown for [providerId].
  Future<void> clearCache(String providerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_cacheKeyPrefix$providerId');
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static String _fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
