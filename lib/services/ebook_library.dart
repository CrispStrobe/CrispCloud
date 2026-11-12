import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/storage_reference.dart';
import '../utils/async_lock.dart';
import 'ebook_reading_data.dart';

export '../models/storage_reference.dart' show FileReference, StorageReference;
export 'ebook_reading_data.dart' show EbookReaderRenderer;

enum EbookReadingStatus { unread, reading, completed }

enum EbookLibrarySort { recent, title, author, progress }

/// A catalog row is a saved reference, never a live filesystem capability.
/// The UI must resolve [source] against the exact current account before use.
class EbookLibraryEntry {
  EbookLibraryEntry._({
    required this.id,
    required this.source,
    required this.contentSha256,
    required this.contentByteLength,
    required this.title,
    required List<String> authors,
    required this.format,
    required this.favorite,
    required List<String> tags,
    required List<String> shelves,
    required this.status,
    required this.firstOpenedAt,
    required this.lastOpenedAt,
    required this.lastReadAt,
    required this.renderer,
    required this.progress,
  }) : authors = List.unmodifiable(authors),
       tags = List.unmodifiable(tags),
       shelves = List.unmodifiable(shelves);

  final String id;
  final FileReference? source;
  final String contentSha256;
  final int contentByteLength;
  final String title;
  final List<String> authors;
  final String format;
  final bool favorite;
  final List<String> tags;
  final List<String> shelves;
  final EbookReadingStatus status;
  final DateTime firstOpenedAt;
  final DateTime lastOpenedAt;
  final DateTime? lastReadAt;
  final EbookReaderRenderer renderer;
  final double? progress;

  /// Only means a persistent reference exists. It does not mean access is live.
  bool get canLocateSource => source?.storage.persistent == true;

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source?.toJson(),
    'contentSha256': contentSha256,
    'contentByteLength': contentByteLength,
    'title': title,
    'authors': authors,
    'format': format,
    'favorite': favorite,
    'tags': tags,
    'shelves': shelves,
    'status': status.name,
    'firstOpenedAt': firstOpenedAt.millisecondsSinceEpoch,
    'lastOpenedAt': lastOpenedAt.millisecondsSinceEpoch,
    'lastReadAt': lastReadAt?.millisecondsSinceEpoch,
    'renderer': renderer.wireName,
    'progress': progress,
  };

  factory EbookLibraryEntry.fromJson(Map<String, dynamic> json) {
    _keys(json, const {
      'id',
      'source',
      'contentSha256',
      'contentByteLength',
      'title',
      'authors',
      'format',
      'favorite',
      'tags',
      'shelves',
      'status',
      'firstOpenedAt',
      'lastOpenedAt',
      'lastReadAt',
      'renderer',
      'progress',
    });
    final hash = _hash(json['contentSha256']);
    final length = _length(json['contentByteLength']);
    final source = json['source'] == null
        ? null
        : _referenceFromJson(json['source']);
    final id = _text(json['id'], 64);
    if (id !=
        EbookLibrary.idFor(
          source: source,
          contentSha256: hash,
          contentByteLength: length,
        )) {
      throw const FormatException('The library source identity is invalid.');
    }
    final status = EbookReadingStatus.values
        .where((item) => item.name == json['status'])
        .firstOrNull;
    final renderer = EbookReaderRenderer.values
        .where((item) => item.wireName == json['renderer'])
        .firstOrNull;
    if (status == null || renderer == null || json['favorite'] is! bool) {
      throw const FormatException('Invalid library reading state.');
    }
    final first = _date(json['firstOpenedAt']);
    final last = _date(json['lastOpenedAt']);
    if (last.isBefore(first)) {
      throw const FormatException('Invalid library dates.');
    }
    final progress = json['progress'];
    if (progress != null &&
        (progress is! num ||
            !progress.isFinite ||
            progress < 0 ||
            progress > 1)) {
      throw const FormatException('Invalid library progress.');
    }
    return EbookLibraryEntry._(
      id: id,
      source: source,
      contentSha256: hash,
      contentByteLength: length,
      title: _text(json['title'], 2048, nonempty: true),
      authors: _texts(json['authors'], count: 32, length: 512),
      format: _format(json['format']),
      favorite: json['favorite'] as bool,
      tags: _labels(_texts(json['tags'], count: 50, length: 100)),
      shelves: _labels(_texts(json['shelves'], count: 50, length: 100)),
      status: status,
      firstOpenedAt: first,
      lastOpenedAt: last,
      lastReadAt: json['lastReadAt'] == null ? null : _date(json['lastReadAt']),
      renderer: renderer,
      progress: (progress as num?)?.toDouble(),
    );
  }
}

typedef EbookLibraryPreferenceWriter = Future<bool> Function(
  String key,
  String value,
);

/// A bounded, local catalog over existing account-scoped file references.
/// Edits write one versioned JSON value and publish only after persistence.
/// Separate instances serialize writes and reload the current catalog inside
/// that lock, so two open book dialogs cannot silently erase each other's rows.
class EbookLibrary extends ChangeNotifier {
  EbookLibrary._(this._preferences, this._writer)
    : _lock = _locks[_preferences] ??= AsyncLock();

  static const preferencesKey = 'ebook.library.v1';
  static const maximumEntries = 1000;
  static const maximumJsonBytes = 4 * 1024 * 1024;
  static final _locks = Expando<AsyncLock>('ebook library writes');
  final SharedPreferences _preferences;
  final EbookLibraryPreferenceWriter? _writer;
  final AsyncLock _lock;
  Map<String, EbookLibraryEntry> _entries = {};
  bool _disposed = false;
  int _revision = 0;

  int get revision => _revision;
  List<EbookLibraryEntry> get entries => query();
  EbookLibraryEntry? get(String id) => _entries[id];
  List<String> get shelves => _allLabels((entry) => entry.shelves);
  List<String> get tags => _allLabels((entry) => entry.tags);

  static Future<EbookLibrary> open({
    SharedPreferences? preferences,
    EbookLibraryPreferenceWriter? writePreference,
  }) async {
    final result = EbookLibrary._(
      preferences ?? await SharedPreferences.getInstance(),
      writePreference,
    );
    await result.reload();
    return result;
  }

  Future<void> reload() => _lock.synchronized(() async {
    _ensureAlive();
    _publish(_read());
  });

  static String idFor({
    FileReference? source,
    required String contentSha256,
    required int contentByteLength,
  }) {
    _hash(contentSha256);
    _length(contentByteLength);
    final captured = source?.storage.persistent == true
        ? _reference(source!)
        : null;
    final identity = captured == null
        ? ['attachment', contentSha256, contentByteLength]
        : [
            'source',
            captured.storage.kind,
            captured.storage.provider,
            captured.storage.accountKey,
            captured.storage.root,
            captured.objectId == null ? 'path' : 'object',
            captured.objectId ?? captured.path,
          ];
    return sha256.convert(utf8.encode(jsonEncode(identity))).toString();
  }

  Future<EbookLibraryEntry> recordOpened({
    FileReference? source,
    required String contentSha256,
    required int contentByteLength,
    required String title,
    List<String> authors = const [],
    required String format,
    required EbookReaderRenderer renderer,
    DateTime? openedAt,
  }) {
    final captured = source?.storage.persistent == true
        ? _reference(source!)
        : null;
    final id = idFor(
      source: captured,
      contentSha256: contentSha256,
      contentByteLength: contentByteLength,
    );
    final safeTitle = _text(title.trim(), 2048, nonempty: true);
    final safeAuthors = _texts(authors, count: 32, length: 512);
    final safeFormat = _format(format);
    final now = _date((openedAt ?? DateTime.now()).millisecondsSinceEpoch);
    return _change((entries) {
      final old = entries[id];
      if (old == null && entries.length >= maximumEntries) {
        throw StateError(
          'The ebook library is full. Remove an entry before adding another book.',
        );
      }
      final sameVersion =
          old?.contentSha256 == contentSha256 &&
          old?.contentByteLength == contentByteLength;
      final sameRenderer = sameVersion && old?.renderer == renderer;
      final row = EbookLibraryEntry._(
        id: id,
        source: captured,
        contentSha256: contentSha256,
        contentByteLength: contentByteLength,
        title: safeTitle,
        authors: safeAuthors,
        format: safeFormat,
        favorite: old?.favorite ?? false,
        tags: old?.tags ?? const [],
        shelves: old?.shelves ?? const [],
        status: sameVersion && old!.status == EbookReadingStatus.completed
            ? EbookReadingStatus.completed
            : EbookReadingStatus.reading,
        firstOpenedAt: old?.firstOpenedAt ?? now,
        lastOpenedAt: old != null && old.lastOpenedAt.isAfter(now)
            ? old.lastOpenedAt
            : now,
        lastReadAt: sameRenderer ? old?.lastReadAt : null,
        renderer: renderer,
        progress: sameRenderer ? old?.progress : null,
      );
      entries[id] = row;
      return row;
    });
  }

  Future<EbookLibraryEntry> update(
    String id, {
    bool? favorite,
    List<String>? tags,
    List<String>? shelves,
    EbookReadingStatus? status,
  }) {
    final safeTags = tags == null ? null : _labels(tags);
    final safeShelves = shelves == null ? null : _labels(shelves);
    return _change((entries) {
      final old = _require(entries, id);
      final row = EbookLibraryEntry.fromJson({
        ...old.toJson(),
        if (favorite != null) 'favorite': favorite,
        if (safeTags != null) 'tags': safeTags,
        if (safeShelves != null) 'shelves': safeShelves,
        if (status != null) 'status': status.name,
      });
      entries[id] = row;
      return row;
    });
  }

  /// Reject a late progress event from a book revision or renderer no longer
  /// represented by this row. A fraction is catalog metadata, never a locator.
  Future<EbookLibraryEntry> recordProgress(
    String id, {
    required String contentSha256,
    required EbookReaderRenderer renderer,
    required double fraction,
    DateTime? readAt,
  }) {
    _hash(contentSha256);
    if (!fraction.isFinite || fraction < 0 || fraction > 1) {
      throw const FormatException('Invalid library progress.');
    }
    final now = _date((readAt ?? DateTime.now()).millisecondsSinceEpoch);
    return _change((entries) {
      final old = _require(entries, id);
      if (old.contentSha256 != contentSha256 || old.renderer != renderer) {
        throw StateError(
          'The library book version or reader changed. Reopen the book before saving progress.',
        );
      }
      final row = EbookLibraryEntry.fromJson({
        ...old.toJson(),
        'progress': fraction,
        'lastReadAt': old.lastReadAt != null && old.lastReadAt!.isAfter(now)
            ? old.lastReadAt!.millisecondsSinceEpoch
            : now.millisecondsSinceEpoch,
        'status': old.status == EbookReadingStatus.completed
            ? old.status.name
            : EbookReadingStatus.reading.name,
      });
      entries[id] = row;
      return row;
    });
  }

  Future<void> remove(String id) => _change((entries) {
    entries.remove(id);
  });

  /// A replacement sidecar may intentionally have no current location. Clear
  /// only its displayed fraction; retain the user's status and reading history.
  Future<EbookLibraryEntry> clearProgress(
    String id, {
    required String contentSha256,
    required EbookReaderRenderer renderer,
  }) {
    _hash(contentSha256);
    return _change((entries) {
      final old = _require(entries, id);
      if (old.contentSha256 != contentSha256 || old.renderer != renderer) {
        throw StateError(
          'The library book version or reader changed. Reopen the book before saving progress.',
        );
      }
      final row = EbookLibraryEntry.fromJson({
        ...old.toJson(),
        'progress': null,
      });
      entries[id] = row;
      return row;
    });
  }

  List<EbookLibraryEntry> query({
    String text = '',
    bool favoritesOnly = false,
    String? shelf,
    String? tag,
    EbookReadingStatus? status,
    EbookLibrarySort sort = EbookLibrarySort.recent,
  }) {
    final words = text.trim().toLowerCase().split(RegExp(r'\s+'));
    final matches = _entries.values.where((entry) {
      if (favoritesOnly && !entry.favorite ||
          status != null && entry.status != status) {
        return false;
      }
      if (shelf != null &&
          !entry.shelves.any(
            (value) => value.toLowerCase() == shelf.toLowerCase(),
          )) {
        return false;
      }
      if (tag != null &&
          !entry.tags.any(
            (value) => value.toLowerCase() == tag.toLowerCase(),
          )) {
        return false;
      }
      final search =
          '${entry.title} ${entry.authors.join(' ')} ${entry.tags.join(' ')} ${entry.shelves.join(' ')}'
              .toLowerCase();
      return words.every(search.contains);
    }).toList();
    matches.sort((a, b) {
      final order = switch (sort) {
        EbookLibrarySort.recent => b.lastOpenedAt.compareTo(a.lastOpenedAt),
        EbookLibrarySort.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        EbookLibrarySort.author =>
          a.authors
              .join(' ')
              .toLowerCase()
              .compareTo(b.authors.join(' ').toLowerCase()),
        EbookLibrarySort.progress => (b.progress ?? -1).compareTo(
          a.progress ?? -1,
        ),
      };
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    return List.unmodifiable(matches);
  }

  List<String> _allLabels(List<String> Function(EbookLibraryEntry) values) {
    final result = <String, String>{};
    for (final entry in _entries.values) {
      for (final label in values(entry)) {
        result.putIfAbsent(label.toLowerCase(), () => label);
      }
    }
    return List.unmodifiable(
      result.values.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    );
  }

  Map<String, EbookLibraryEntry> _read() {
    final raw = _preferences.get(preferencesKey);
    if (raw == null) return {};
    if (raw is! String) {
      throw const FormatException('The saved ebook library is damaged.');
    }
    checkEbookJsonBounds(raw, maximumBytes: maximumJsonBytes);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid ebook library.');
    }
    _keys(decoded, const {'format', 'version', 'entries'});
    if (decoded['format'] != 'crispcloud-ebook-library' ||
        decoded['version'] != 1) {
      throw const FormatException('Unsupported ebook library version.');
    }
    final values = decoded['entries'];
    if (values is! List || values.length > maximumEntries) {
      throw const FormatException('Invalid ebook library size.');
    }
    final entries = <String, EbookLibraryEntry>{};
    for (final value in values) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid ebook library entry.');
      }
      final entry = EbookLibraryEntry.fromJson(value);
      if (entries.containsKey(entry.id)) {
        throw const FormatException('Duplicate ebook library entry.');
      }
      entries[entry.id] = entry;
    }
    return entries;
  }

  Future<T> _change<T>(T Function(Map<String, EbookLibraryEntry>) mutation) =>
      _lock.synchronized(() async {
        _ensureAlive();
        final current = _read();
        final next = Map<String, EbookLibraryEntry>.of(current);
        final result = mutation(next);
        final sorted = next.values.toList()
          ..sort((a, b) => a.id.compareTo(b.id));
        final encoded = jsonEncode({
          'format': 'crispcloud-ebook-library',
          'version': 1,
          'entries': sorted.map((entry) => entry.toJson()).toList(),
        });
        checkEbookJsonBounds(encoded, maximumBytes: maximumJsonBytes);
        if (encoded != _preferences.get(preferencesKey)) {
          try {
            if (!await (_writer?.call(preferencesKey, encoded) ??
                _preferences.setString(preferencesKey, encoded))) {
              throw StateError(
                'The ebook library could not be saved on this device.',
              );
            }
          } on Object {
            try {
              await _preferences.reload();
            } on Object {
              /* Preserve the write failure. */
            }
            rethrow;
          }
        }
        _publish(next);
        return result;
      });

  void _publish(Map<String, EbookLibraryEntry> entries) {
    _entries = entries;
    _revision++;
    if (!_disposed) notifyListeners();
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('The ebook library is closed.');
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

EbookLibraryEntry _require(Map<String, EbookLibraryEntry> entries, String id) =>
    entries[id] ?? (throw StateError('This book is no longer in the library.'));

FileReference _referenceFromJson(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid library source.');
  }
  final expected = {
    'storage',
    'path',
    if (value.containsKey('objectId')) 'objectId',
    if (value.containsKey('version')) 'version',
  };
  _keys(value, expected);
  final storage = value['storage'];
  if (storage is! Map<String, dynamic>) {
    throw const FormatException('Invalid library storage.');
  }
  _keys(storage, const {
    'version',
    'kind',
    'provider',
    'accountKey',
    'root',
    'persistent',
  });
  if (storage['persistent'] != true) {
    throw const FormatException(
      'A temporary source cannot be restored from the library.',
    );
  }
  if (storage['version'] != 1 ||
      !const {'local', 'remote'}.contains(storage['kind'])) {
    throw const FormatException('Invalid library storage.');
  }
  return _reference(
    FileReference(
      storage: StorageReference(
        kind: storage['kind'] as String,
        provider: _text(storage['provider'], 128, nonempty: true),
        accountKey: _text(storage['accountKey'], 256, nonempty: true),
        root: _text(storage['root'], 8192, nonempty: true),
      ),
      path: _text(value['path'], 8192, nonempty: true),
      objectId: value.containsKey('objectId')
          ? _text(value['objectId'], 1024, nonempty: true)
          : null,
      version: value.containsKey('version')
          ? _text(value['version'], 1024)
          : null,
    ),
  );
}

FileReference _reference(FileReference source) {
  final storage = source.storage;
  if (!storage.persistent ||
      !const {'local', 'remote'}.contains(storage.kind)) {
    throw const FormatException(
      'A library source needs a persistent storage reference.',
    );
  }
  final windowsLocal = storage.isLocal && storage.provider == 'windows';
  final paths = windowsLocal ? p.windows : p.posix;
  final path = _text(source.path, 8192, nonempty: true);
  final root = _text(storage.root, 8192, nonempty: true);
  // Existing Windows local StorageReferences use '/' as the installation-wide
  // root marker; it must not be rewritten to a different account namespace.
  final windowsRootMarker = windowsLocal && root == '/';
  if (!paths.isAbsolute(path) ||
      (!windowsRootMarker && !paths.isAbsolute(root))) {
    throw const FormatException(
      'A library source needs an absolute storage path.',
    );
  }
  final normalPath = paths.normalize(path);
  final normalRoot = paths.normalize(root);
  if (!windowsRootMarker &&
      !paths.equals(normalRoot, normalPath) &&
      !paths.isWithin(normalRoot, normalPath)) {
    throw const FormatException(
      'The library file is outside its original storage root.',
    );
  }
  return FileReference(
    storage: StorageReference(
      kind: storage.kind,
      provider: _text(storage.provider, 128, nonempty: true),
      accountKey: _text(storage.accountKey, 256, nonempty: true),
      root: root,
    ),
    path: normalPath,
    objectId: source.objectId == null
        ? null
        : _text(source.objectId, 1024, nonempty: true),
    version: source.version == null ? null : _text(source.version, 1024),
  );
}

void _keys(Map<String, dynamic> json, Set<String> expected) {
  if (json.keys.any((key) => !expected.contains(key)) ||
      expected.any((key) => !json.containsKey(key))) {
    throw const FormatException('Missing or unsupported library fields.');
  }
}

String _text(Object? value, int maximum, {bool nonempty = false}) {
  if (value is! String ||
      value.length > maximum ||
      nonempty && value.trim().isEmpty ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw const FormatException('Invalid library text.');
  }
  return value;
}

List<String> _texts(Object? value, {required int count, required int length}) {
  if (value is! List || value.length > count) {
    throw const FormatException('The library text-list limit was exceeded.');
  }
  return value.map((item) => _text(item, length)).toList();
}

List<String> _labels(List<String> values) {
  if (values.length > 50) {
    throw const FormatException('Use at most 50 tags or shelves for one book.');
  }
  final unique = <String, String>{};
  for (final raw in values) {
    final label = _text(raw.trim(), 100);
    if (label.isEmpty) continue;
    final key = label.toLowerCase();
    final old = unique[key];
    if (old == null || label.compareTo(old) < 0) unique[key] = label;
  }
  final keys = unique.keys.toList()..sort();
  return keys.map((key) => unique[key]!).toList();
}

String _hash(Object? value) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('Invalid library content version.');
  }
  return value;
}

int _length(Object? value) {
  if (value is! int || value < 0 || value > EbookReadingData.maximumBookBytes) {
    throw const FormatException('Invalid library content size.');
  }
  return value;
}

String _format(Object? value) {
  if (value is! String ||
      !const {
        'epub',
        'mobi',
        'azw',
        'azw3',
        'fb2',
        'fbz',
        'cbz',
      }.contains(value)) {
    throw const FormatException('Unsupported library book format.');
  }
  return value;
}

DateTime _date(Object? value) {
  if (value is! int || value < 0 || value > 253402300799999) {
    throw const FormatException('Invalid library timestamp.');
  }
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}
