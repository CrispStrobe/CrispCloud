import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../services/log_service.dart';
import '../utils/async_lock.dart';

/// Older bookmarks are retained with no storage reference. They can be
/// explicitly rebound, but opening one never guesses its original account.
class Bookmark {
  const Bookmark({
    required this.name,
    required this.path,
    required this.side,
    this.storage,
    this.collectionId,
    this.group = '',
  });
  final String name;
  final String path;
  final PanelSide side;
  final StorageReference? storage;
  final String? collectionId;
  final String group;
  bool get isBound => storage != null || collectionId != null;
  String get identity =>
      '${side.name}\u0000${collectionId == null
          ? storage == null
                ? 'unbound'
                : '${storage!.id}\u0000${storage!.root}'
          : 'collection:$collectionId'}\u0000$path';

  /// A favorite can open in either pane. Import deduplication therefore uses
  /// the exact source/root and normalized path, independently of the old pane
  /// preference, display name, or group. The stored path itself is unchanged.
  String get destinationIdentity => jsonEncode(
    collectionId != null
        ? ['collection', collectionId, _paths.normalize(path)]
        : [
            storage?.kind,
            storage?.provider,
            storage?.accountKey,
            storage?.root,
            _paths.normalize(path),
          ],
  );

  p.Context get _paths =>
      (storage?.isLocal == true && storage?.provider == 'windows') ||
          (storage == null && p.windows.isAbsolute(path))
      ? p.windows
      : p.posix;

  Bookmark copyWith({String? name, String? path, String? group}) => Bookmark(
    name: name ?? this.name,
    path: path ?? this.path,
    side: side,
    storage: storage,
    collectionId: collectionId,
    group: group ?? this.group,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'side': side.name,
    if (storage != null) 'storage': storage!.toJson(),
    if (collectionId != null) 'collectionId': collectionId,
    if (group.isNotEmpty) 'group': group,
  };
  Map<String, dynamic> toTabJson() => {
    'label': name,
    'customLabel': name,
    'path': path,
    if (storage != null) 'storage': storage!.toJson(),
    if (collectionId != null) 'collectionId': collectionId,
  };
  void validate() {
    if (name.trim().isEmpty ||
        name.length > 160 ||
        name.contains('\u0000') ||
        path.length > 8192 ||
        path.contains('\u0000') ||
        !_paths.isAbsolute(path)) {
      throw const FormatException(
        'A bookmark needs a short name and an absolute storage path.',
      );
    }
    validateGroup(group);
  }

  static void validateGroup(String group) {
    if (group != group.trim() ||
        group.length > 80 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(group)) {
      throw const FormatException(
        'A favorite group must have at most 80 characters.',
      );
    }
  }

  factory Bookmark.fromJson(Map<String, dynamic> value) {
    final bookmark = Bookmark(
      name: value['name'] as String,
      path: value['path'] as String,
      side: PanelSide.values.firstWhere(
        (side) => side.name == value['side'],
        orElse: () => PanelSide.local,
      ),
      storage: value['storage'] == null
          ? null
          : StorageReference.fromJson(
              Map<String, dynamic>.from(value['storage'] as Map),
            ),
      collectionId: value['collectionId'] as String?,
      group: value['group'] as String? ?? '',
    );
    // An old native Windows bookmark has no source yet. Retain it for explicit
    // migration on any platform without granting access to the path.
    bookmark.validate();
    return bookmark;
  }
}

/// Validated, non-mutating merge plan. Existing names, groups, and account
/// references win duplicates; a merge only adds genuinely new destinations.
class BookmarkImportPreview {
  BookmarkImportPreview._({
    required List<Bookmark> entries,
    required List<Bookmark> additions,
    required this.duplicates,
  }) : _entries = List.unmodifiable(entries),
       additions = List.unmodifiable(additions);

  final List<Bookmark> _entries;
  final List<Bookmark> additions;
  final int duplicates;
  int get total => _entries.length;
}

class BookmarksNotifier extends ChangeNotifier {
  BookmarksNotifier() {
    ready = _load();
  }
  static const _log = Log('BookmarksNotifier');
  static const _storageKey = 'bookmarks';
  final _lock = AsyncLock();
  final List<Bookmark> _bookmarks = [];
  final List<void Function(List<Bookmark>)> _pending = [];
  late final Future<void> ready;
  bool _loaded = false;
  bool _disposed = false;
  String? _loadError;
  String? lastError;
  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);
  List<String> get groups => List.unmodifiable(
    _bookmarks
        .map((item) => item.group)
        .where((group) => group.isNotEmpty)
        .toSet(),
  );
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        _storageKey,
      );
      final loaded = raw == null
          ? <Bookmark>[]
          : (jsonDecode(raw) as List)
                .map(
                  (value) => Bookmark.fromJson(
                    Map<String, dynamic>.from(value as Map),
                  ),
                )
                .toList();
      for (final change in _pending) {
        change(loaded);
      }
      _bookmarks
        ..clear()
        ..addAll(loaded);
    } catch (error) {
      _loadError = 'Existing bookmarks could not be read: $error';
      lastError = _loadError;
      _log.warn('Bookmarks load failed', error);
    } finally {
      _loaded = true;
      _pending.clear();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _save() async {
    await ready;
    await _lock.synchronized(() async {
      try {
        if (_loadError != null) throw StateError(_loadError!);
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(
          _storageKey,
          jsonEncode(_bookmarks.map((bookmark) => bookmark.toJson()).toList()),
        )) {
          throw StateError('Bookmarks could not be saved.');
        }
        lastError = null;
      } catch (error) {
        lastError = error.toString();
        if (!_disposed) notifyListeners();
        rethrow;
      }
    });
  }

  Future<void> _change(void Function(List<Bookmark>) change) {
    change(_bookmarks);
    if (!_loaded) _pending.add(change);
    if (!_disposed) notifyListeners();
    return _save();
  }

  Future<void> add(
    String name,
    String path,
    PanelSide side, {
    StorageReference? storage,
    String? collectionId,
    String group = '',
  }) {
    final bookmark = Bookmark(
      name: name,
      path: path,
      side: side,
      storage: storage,
      collectionId: collectionId,
      group: group.trim(),
    );
    bookmark.validate();
    return _change((items) {
      if (!items.any((item) => item.identity == bookmark.identity)) {
        items.add(bookmark);
      }
    });
  }

  Future<void> remove(
    String path,
    PanelSide side, {
    StorageReference? storage,
    String? collectionId,
  }) {
    final identity = Bookmark(
      name: '',
      path: path,
      side: side,
      storage: storage,
      collectionId: collectionId,
    ).identity;
    return _change(
      (items) => items.removeWhere((item) => item.identity == identity),
    );
  }

  Future<void> replace(Bookmark original, Bookmark replacement) {
    replacement.validate();
    return _change((items) {
      final index = items.indexWhere(
        (item) => item.identity == original.identity,
      );
      if (index < 0) throw StateError('The bookmark no longer exists.');
      if (items.any(
        (item) =>
            item.identity != original.identity &&
            item.identity == replacement.identity,
      )) {
        throw StateError('This source and location are already bookmarked.');
      }
      items[index] = replacement;
    });
  }

  /// Move the saved item one place without applying a stale row index to a
  /// different favorite after another window edits the list.
  Future<void> move(
    Bookmark bookmark,
    int direction, {
    bool withinGroup = false,
  }) async {
    if (direction != -1 && direction != 1) {
      throw ArgumentError.value(direction, 'direction', 'Use -1 or 1.');
    }
    await ready;
    await _change((items) {
      final index = items.indexWhere(
        (item) => item.identity == bookmark.identity,
      );
      if (index < 0) throw StateError('The bookmark no longer exists.');
      final currentGroup = items[index].group;
      var target = index + direction;
      while (withinGroup &&
          target >= 0 &&
          target < items.length &&
          items[target].group != currentGroup) {
        target += direction;
      }
      if (target < 0 || target >= items.length) return;
      if (withinGroup) {
        final other = items[target];
        items[target] = items[index];
        items[index] = other;
      } else {
        final current = items.removeAt(index);
        items.insert(target, current);
      }
    });
  }

  /// An empty replacement removes the group, retaining every favorite.
  Future<void> renameGroup(String original, String replacement) async {
    final next = replacement.trim();
    Bookmark.validateGroup(next);
    await ready;
    await _change((items) {
      for (var i = 0; i < items.length; i++) {
        if (items[i].group == original) {
          items[i] = items[i].copyWith(group: next);
        }
      }
    });
  }

  bool isBookmarked(
    String path,
    PanelSide side, {
    StorageReference? storage,
    String? collectionId,
  }) {
    final identity = Bookmark(
      name: '',
      path: path,
      side: side,
      storage: storage,
      collectionId: collectionId,
    ).identity;
    return _bookmarks.any((item) => item.identity == identity);
  }

  Future<String> exportText() async {
    await ready;
    if (_loadError != null) throw StateError(_loadError!);
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'crispcloud.bookmarks',
      'version': 3,
      'bookmarks': _bookmarks.map((bookmark) => bookmark.toJson()).toList(),
    });
  }

  static List<Bookmark> decodeImport(String text) {
    if (text.length > 2 * 1024 * 1024 ||
        utf8.encode(text).length > 2 * 1024 * 1024) {
      throw const FormatException(
        'Bookmark files must be no larger than 2 MiB.',
      );
    }
    try {
      final value = Map<String, dynamic>.from(jsonDecode(text) as Map);
      if (value['format'] != 'crispcloud.bookmarks' ||
          !const {2, 3}.contains(value['version']) ||
          value.keys.any(
            (key) => !const {'format', 'version', 'bookmarks'}.contains(key),
          ) ||
          value['bookmarks'] is! List) {
        throw const FormatException();
      }
      final entries = value['bookmarks'] as List;
      if (entries.length > 10000) throw const FormatException();
      final result = <Bookmark>[];
      for (final entry in entries) {
        final json = Map<String, dynamic>.from(entry as Map);
        if (json.keys.any(
              (key) => !const {
                'name',
                'path',
                'side',
                'storage',
                'collectionId',
                'group',
              }.contains(key),
            ) ||
            json['name'] is! String ||
            json['path'] is! String ||
            !PanelSide.values.any((side) => side.name == json['side']) ||
            (json.containsKey('group') && json['group'] is! String) ||
            (json.containsKey('collectionId') &&
                (json['collectionId'] is! String ||
                    (json['collectionId'] as String).isEmpty ||
                    (json['collectionId'] as String).length > 512 ||
                    RegExp(r'[\x00-\x1f\x7f]')
                        .hasMatch(json['collectionId'] as String)))) {
          throw const FormatException();
        }
        if (json['storage'] != null) {
          final storage = Map<String, dynamic>.from(json['storage'] as Map);
          if (storage.keys.any(
                (key) => !const {
                  'version',
                  'kind',
                  'provider',
                  'accountKey',
                  'root',
                  'persistent',
                }.contains(key),
              ) ||
              storage['provider'] is! String ||
              (storage['provider'] as String).isEmpty ||
              (storage['provider'] as String).length > 120 ||
              storage['accountKey'] is! String ||
              (storage['accountKey'] as String).length > 512 ||
              (storage.containsKey('root') && storage['root'] is! String) ||
              (storage.containsKey('persistent') &&
                  storage['persistent'] is! bool)) {
            throw const FormatException();
          }
          for (final field in ['provider', 'accountKey', 'root']) {
            final value = storage[field];
            if (value is String &&
                (value.length > 8192 ||
                    RegExp(r'[\x00-\x1f\x7f]').hasMatch(value))) {
              throw const FormatException();
            }
          }
        }
        result.add(Bookmark.fromJson(json));
      }
      return List.unmodifiable(result);
    } catch (_) {
      // Do not echo imported JSON: unknown fields may contain credentials.
      throw const FormatException(
        'Invalid favorites JSON. Use a version 2 or 3 CrispCloud export with at most 10000 favorites.',
      );
    }
  }

  BookmarkImportPreview previewImport(String text) =>
      _previewEntries(decodeImport(text));

  BookmarkImportPreview _previewEntries(List<Bookmark> entries) {
    if (!_loaded || _loadError != null) {
      throw StateError('Existing favorites must be readable before importing.');
    }
    final seen = _bookmarks.map((item) => item.destinationIdentity).toSet();
    final additions = <Bookmark>[];
    var duplicates = 0;
    for (final bookmark in entries) {
      if (seen.add(bookmark.destinationIdentity)) {
        additions.add(bookmark);
      } else {
        duplicates++;
      }
    }
    return BookmarkImportPreview._(
      entries: entries,
      additions: additions,
      duplicates: duplicates,
    );
  }

  Future<int> mergeImport(BookmarkImportPreview preview) async {
    await ready;
    // Another window can add favorites while a preview is open. Recheck the
    // destination identities at commit so those rows are never overwritten.
    final current = _previewEntries(preview._entries);
    if (current.additions.isEmpty) {
      if (lastError != null) await _save();
      return 0;
    }
    await _change((items) => items.addAll(current.additions));
    return current.additions.length;
  }

  Future<void> importText(String text) async {
    final imported = decodeImport(text);
    await ready;
    await mergeImport(_previewEntries(imported));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final bookmarksProvider = ChangeNotifierProvider<BookmarksNotifier>(
  (ref) => BookmarksNotifier(),
);
