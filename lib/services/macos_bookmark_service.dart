// services/macos_bookmark_service.dart
//
// Persistent macOS security-scoped bookmarks. Multiple folder grants are
// stored so navigating to another volume no longer discards an earlier grant.
// The store is versioned and migrated from the old single-bookmark keys.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/path_access.dart';
import '../l10n/access_and_fkey_strings.dart';
import 'locale_preference.dart';

class MacOSBookmarkService {
  /// Current multi-bookmark store.
  static const String _bookmarksKey = 'macos_bookmarks_v3';

  /// Granted paths kept separately from bookmark data. When macOS invalidates
  /// a bookmark after a rebuild, this still tells us which folder to offer for
  /// re-authorisation instead of silently forgetting the user's choice.
  static const String _pathsKey = 'macos_bookmark_paths_v3';

  /// Legacy single-bookmark keys (read for migration, never removed).
  static const String _legacyDataKey = 'macos_bookmark_data_v2';
  static const String _legacyPathKey = 'macos_bookmark_path_v2';

  static final _bookmarks = SecureBookmarks();

  static Future<List<Map<String, String>>> _loadEntries() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_bookmarksKey);
    if (raw != null) {
      try {
        final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
        return <Map<String, String>>[
              for (final dynamic item in decoded)
                if (item is Map)
                  <String, String>{
                    'path': (item['path'] ?? '').toString(),
                    'data': (item['data'] ?? '').toString(),
                  },
            ]
            .where(
              (Map<String, String> e) =>
                  e['path']!.isNotEmpty && e['data']!.isNotEmpty,
            )
            .toList();
      } catch (_) {
        // Fall through to migration / empty.
      }
    }

    // Migrate the old single bookmark into the new list.
    final String? data = prefs.getString(_legacyDataKey);
    final String? path = prefs.getString(_legacyPathKey);
    if (data != null && path != null && data.isNotEmpty && path.isNotEmpty) {
      final List<Map<String, String>> migrated = <Map<String, String>>[
        <String, String>{'path': path, 'data': data},
      ];
      await _saveEntries(migrated);
      return migrated;
    }
    return <Map<String, String>>[];
  }

  static Future<void> _saveEntries(List<Map<String, String>> entries) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bookmarksKey, json.encode(entries));
  }

  static Future<List<String>> _loadPaths() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_pathsKey);
    if (raw == null) return <String>[];
    try {
      final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
      return <String>[
        for (final dynamic item in decoded)
          if (item is String && item.isNotEmpty) item,
      ];
    } catch (_) {
      return <String>[];
    }
  }

  static Future<void> _rememberPath(String path) async {
    final List<String> paths = await _loadPaths();
    paths.removeWhere((String existing) => isSameOrUnderPath(existing, path));
    paths.add(path);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pathsKey, json.encode(paths));
  }

  static Future<void> _forgetPath(String path) async {
    final List<String> paths = await _loadPaths();
    paths.removeWhere((String existing) => isSameOrUnderPath(existing, path));
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pathsKey, json.encode(paths));
  }

  /// Bookmark [path] and add/replace it in the persisted grant list.
  static Future<void> addBookmark(String path) async {
    final String bookmarkData = await _bookmarks.bookmark(File(path));
    final List<Map<String, String>> entries = await _loadEntries();
    entries.removeWhere(
      (Map<String, String> entry) => isSameOrUnderPath(entry['path']!, path),
    );
    entries.add(<String, String>{'path': path, 'data': bookmarkData});
    await _saveEntries(entries);
    await _rememberPath(path);

    // Keep the legacy path key pointing at the most recent grant for older
    // code paths and for users rolling back a build.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_legacyPathKey, path);
    await prefs.setString(_legacyDataKey, bookmarkData);
    debugPrint('✅ Saved macOS bookmark for: $path');
  }

  /// Request a new folder grant and persist it.
  static Future<String?> requestDirectoryAccess({
    String? initialDirectory,
  }) async {
    if (!Platform.isMacOS) return null;
    try {
      Locale locale;
      try {
        locale =
            await LocalePreference.read(refresh: true) ??
            PlatformDispatcher.instance.locale;
      } catch (_) {
        // A preference read must never prevent the system folder picker.
        locale = PlatformDispatcher.instance.locale;
      }
      final String? directoryPath = await getDirectoryPath(
        initialDirectory: initialDirectory,
        confirmButtonText: AccessAndFKeyStrings(locale).grantAccess,
      );
      if (directoryPath == null) return null;
      await addBookmark(directoryPath);
      return directoryPath;
    } catch (e) {
      debugPrint('❌ Error requesting directory access: $e');
      return null;
    }
  }

  /// Resolve every stored bookmark. Stale entries are dropped.
  static Future<List<FileSystemEntity>> getResolvedBookmarks() async {
    if (!Platform.isMacOS) return <FileSystemEntity>[];
    final List<Map<String, String>> entries = await _loadEntries();
    final List<FileSystemEntity> resolved = <FileSystemEntity>[];
    final List<Map<String, String>> kept = <Map<String, String>>[];
    for (final Map<String, String> entry in entries) {
      try {
        final FileSystemEntity entity = await _bookmarks.resolveBookmark(
          entry['data']!,
        );
        resolved.add(entity);
        kept.add(entry);
      } catch (e) {
        debugPrint('⚠️ Stale bookmark for ${entry['path']}: $e');
      }
    }
    if (kept.length != entries.length) {
      await _saveEntries(kept);
    }
    return resolved;
  }

  /// Legacy accessor: first resolved bookmark.
  static Future<FileSystemEntity?> getResolvedBookmark() async {
    final List<FileSystemEntity> items = await getResolvedBookmarks();
    return items.isEmpty ? null : items.first;
  }

  /// Most recently granted directory path, if any.
  static Future<String?> getLastGrantedDirectory() async {
    if (!Platform.isMacOS) return null;
    final List<Map<String, String>> entries = await _loadEntries();
    if (entries.isNotEmpty) return entries.last['path'];
    // A bookmark may be invalid after a rebuild, but the path hint still lets
    // the next access request open at the folder the user originally chose.
    final List<String> paths = await _loadPaths();
    return paths.isEmpty ? null : paths.last;
  }

  /// True when [path] is covered by any saved grant.
  static Future<bool> hasAccessToPath(String path) async {
    final List<Map<String, String>> entries = await _loadEntries();
    for (final Map<String, String> entry in entries) {
      if (isSameOrUnderPath(path, entry['path']!)) return true;
    }
    return false;
  }

  /// All persisted grant roots (for settings/diagnostics), including paths
  /// whose bookmark needs to be renewed.
  static Future<List<String>> grantedPaths() async {
    final List<Map<String, String>> entries = await _loadEntries();
    final List<String> hints = await _loadPaths();
    return <String>{
      ...entries.map((Map<String, String> e) => e['path']!),
      ...hints,
    }.toList();
  }

  static Future<void> removeBookmark(String path) async {
    final List<Map<String, String>> entries = await _loadEntries();
    entries.removeWhere(
      (Map<String, String> entry) => isSameOrUnderPath(entry['path']!, path),
    );
    await _saveEntries(entries);
    await _forgetPath(path);
  }

  static Future<void> clearBookmarks() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bookmarksKey);
    await prefs.remove(_pathsKey);
    await prefs.remove(_legacyDataKey);
    await prefs.remove(_legacyPathKey);
  }
}
