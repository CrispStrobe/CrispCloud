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
  });
  final String name;
  final String path;
  final PanelSide side;
  final StorageReference? storage;
  final String? collectionId;
  bool get isBound => storage != null || collectionId != null;
  String get identity =>
      '${side.name}\u0000${collectionId == null ? storage?.id ?? 'unbound' : 'collection:$collectionId'}\u0000$path';

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'side': side.name,
    if (storage != null) 'storage': storage!.toJson(),
    if (collectionId != null) 'collectionId': collectionId,
  };
  Map<String, dynamic> toTabJson() => {
    'label': name,
    'customLabel': name,
    'path': path,
    if (storage != null) 'storage': storage!.toJson(),
    if (collectionId != null) 'collectionId': collectionId,
  };
  void validate() {
    final paths =
        (storage?.isLocal == true && storage?.provider == 'windows') ||
            (storage == null && p.windows.isAbsolute(path))
        ? p.windows
        : p.posix;
    if (name.trim().isEmpty ||
        name.length > 160 ||
        name.contains('\u0000') ||
        path.length > 8192 ||
        path.contains('\u0000') ||
        !paths.isAbsolute(path)) {
      throw const FormatException(
        'A bookmark needs a short name and an absolute storage path.',
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
    );
    // An old native Windows bookmark has no source yet. Retain it for explicit
    // migration on any platform without granting access to the path.
    bookmark.validate();
    return bookmark;
  }
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
  }) {
    final bookmark = Bookmark(
      name: name,
      path: path,
      side: side,
      storage: storage,
      collectionId: collectionId,
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
  Future<void> move(Bookmark bookmark, int direction) async {
    if (direction != -1 && direction != 1) {
      throw ArgumentError.value(direction, 'direction', 'Use -1 or 1.');
    }
    await ready;
    await _change((items) {
      final index = items.indexWhere(
        (item) => item.identity == bookmark.identity,
      );
      if (index < 0) throw StateError('The bookmark no longer exists.');
      final target = index + direction;
      if (target < 0 || target >= items.length) return;
      final current = items.removeAt(index);
      items.insert(target, current);
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
      'version': 2,
      'bookmarks': _bookmarks.map((bookmark) => bookmark.toJson()).toList(),
    });
  }

  static List<Bookmark> decodeImport(String text) {
    if (utf8.encode(text).length > 2 * 1024 * 1024) {
      throw const FormatException(
        'Bookmark files must be no larger than 2 MiB.',
      );
    }
    final value = Map<String, dynamic>.from(jsonDecode(text) as Map);
    if (value['format'] != 'crispcloud.bookmarks' || value['version'] != 2) {
      throw const FormatException('Unsupported bookmark exchange format.');
    }
    final result = (value['bookmarks'] as List)
        .map(
          (value) => Bookmark.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList();
    if (result.length > 10000 ||
        result.map((bookmark) => bookmark.identity).toSet().length !=
            result.length) {
      throw const FormatException(
        'Bookmark files require unique source/path pairs and at most 10000 entries.',
      );
    }
    return result;
  }

  Future<void> importText(String text) async {
    final imported = decodeImport(text);
    await ready;
    await _change((items) {
      for (final bookmark in imported) {
        final index = items.indexWhere(
          (item) => item.identity == bookmark.identity,
        );
        if (index < 0) {
          items.add(bookmark);
        } else {
          items[index] = bookmark;
        }
      }
    });
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
