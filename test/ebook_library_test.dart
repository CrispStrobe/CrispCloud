import 'dart:convert';

import 'package:crisp_cloud/services/ebook_library.dart';
import 'package:crisp_cloud/services/ebook_reading_data.dart'
    show EbookReadingDataException;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String get _hash => 'a' * 64;
String get _otherHash => 'b' * 64;
FileReference _source({
  String account = 'account-a',
  String root = '/',
  String path = '/books/one.epub',
  String? objectId,
  bool persistent = true,
}) => FileReference(
  storage: StorageReference(
    kind: 'remote',
    provider: 'test-provider',
    accountKey: account,
    root: root,
    persistent: persistent,
  ),
  path: path,
  objectId: objectId,
);
Future<EbookLibraryEntry> _open(
  EbookLibrary library, {
  FileReference? source,
  String title = 'A book',
  String? hash,
  EbookReaderRenderer renderer = EbookReaderRenderer.foliate,
  DateTime? at,
}) => library.recordOpened(
  source: source,
  contentSha256: hash ?? _hash,
  contentByteLength: 1234,
  title: title,
  authors: const ['An Author'],
  format: 'epub',
  renderer: renderer,
  openedAt: at ?? DateTime.utc(2026, 11, 12),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'catalog metadata and exact source references persist together',
    () async {
      final library = await EbookLibrary.open();
      final source = _source(objectId: 'object-123');
      final row = await _open(library, source: source, title: '日本語 — Grüße');
      await library.update(
        row.id,
        favorite: true,
        tags: [' Space ', 'space', '', 'Research'],
        shelves: ['To read'],
        status: EbookReadingStatus.completed,
      );
      await library.recordProgress(
        row.id,
        contentSha256: _hash,
        renderer: EbookReaderRenderer.foliate,
        fraction: .72,
        readAt: DateTime.utc(2026, 11, 12, 10),
      );
      final reopened = await EbookLibrary.open();
      final restored = reopened.entries.single;
      expect(restored.source!.toJson(), source.toJson());
      expect(restored.canLocateSource, isTrue);
      expect(restored.favorite, isTrue);
      expect(restored.tags, ['Research', 'Space']);
      expect(restored.shelves, ['To read']);
      expect(restored.status, EbookReadingStatus.completed);
      expect(restored.progress, .72);
      expect(restored.lastReadAt, DateTime.utc(2026, 11, 12, 10));
      expect(restored.title, '日本語 — Grüße');
      expect(() => restored.tags.add('mutation'), throwsUnsupportedError);
      expect(() => reopened.entries.clear(), throwsUnsupportedError);
    },
  );

  test(
    'account and root boundaries remain distinct even at identical paths',
    () async {
      final library = await EbookLibrary.open();
      final a = await _open(library, source: _source());
      final b = await _open(library, source: _source(account: 'account-b'));
      final root = await _open(library, source: _source(root: '/books'));
      final trailing = await _open(library, source: _source(root: '/books/'));
      expect({a.id, b.id, root.id, trailing.id}, hasLength(4));
      expect(trailing.source!.storage.root, '/books/');
      expect(trailing.source!.storage, _source(root: '/books/').storage);
      expect(library.entries, hasLength(4));
      final json = jsonDecode(
        (await SharedPreferences.getInstance()).getString(
          EbookLibrary.preferencesKey,
        )!,
      ) as Map;
      expect(json['entries'], hasLength(4));
    },
  );

  test('renamed object retains catalog identity while a new version resets progress', () async {
    final library = await EbookLibrary.open();
    final row = await _open(
      library,
      source: _source(objectId: 'stable-object'),
    );
    await library.update(
      row.id,
      favorite: true,
      shelves: ['Reference'],
      status: EbookReadingStatus.completed,
    );
    await library.recordProgress(
      row.id,
      contentSha256: _hash,
      renderer: EbookReaderRenderer.foliate,
      fraction: .9,
    );
    final renamed = await _open(
      library,
      source: _source(path: '/books/renamed.epub', objectId: 'stable-object'),
      at: DateTime.utc(2026, 11, 13),
    );
    expect(renamed.id, row.id);
    expect(renamed.progress, .9);
    expect(renamed.status, EbookReadingStatus.completed);
    final edited = await _open(
      library,
      source: _source(path: '/books/renamed.epub', objectId: 'stable-object'),
      hash: _otherHash,
      at: DateTime.utc(2026, 11, 14),
    );
    expect(edited.id, row.id);
    expect(edited.favorite, isTrue);
    expect(edited.shelves, ['Reference']);
    expect(edited.progress, isNull);
    expect(edited.lastReadAt, isNull);
    expect(edited.status, EbookReadingStatus.reading);
    expect(edited.firstOpenedAt, row.firstOpenedAt);
    expect(library.entries, hasLength(1));
  });

  test('attachments and temporary accounts never acquire a persisted reopen reference', () async {
    final library = await EbookLibrary.open();
    final attachment = await _open(library);
    final temporary = await _open(
      library,
      source: _source(account: 'ephemeral-identity', persistent: false),
    );
    expect(attachment.id, temporary.id);
    expect(temporary.source, isNull);
    expect(temporary.canLocateSource, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getString(
        EbookLibrary.preferencesKey,
      ),
      isNot(contains('ephemeral-identity')),
    );
    final differentBytes = await _open(library, hash: _otherHash);
    expect(differentBytes.id, isNot(attachment.id));
    expect(library.entries, hasLength(2));
  });

  test(
    'Windows installation root marker and exact POSIX roots are supported',
    () async {
      final library = await EbookLibrary.open();
      const windows = FileReference(
        storage: StorageReference(
          kind: 'local',
          provider: 'windows',
          accountKey: 'installation-1',
        ),
        path: r'C:\Books\Example.epub',
      );
      final row = await _open(library, source: windows);
      expect(row.source!.storage.root, '/');
      expect(row.source!.path, windows.path);
      expect(
        () => EbookLibrary.idFor(
          source: _source(root: '/original', path: '/different/book.epub'),
          contentSha256: _hash,
          contentByteLength: 1234,
        ),
        throwsFormatException,
      );
      expect(
        () => EbookLibrary.idFor(
          source: _source(path: 'relative/book.epub'),
          contentSha256: _hash,
          contentByteLength: 1234,
        ),
        throwsFormatException,
      );
      expect(
        () => EbookLibrary.idFor(
          source: _source(path: 'https://user:password@example.test/book'),
          contentSha256: _hash,
          contentByteLength: 1234,
        ),
        throwsFormatException,
      );
    },
  );

  test('independent open library instances serialize and retain each other’s edits', () async {
    final left = await EbookLibrary.open();
    final right = await EbookLibrary.open();
    final rows = await Future.wait([
      _open(left, source: _source(path: '/one.epub')),
      _open(right, source: _source(path: '/two.epub')),
    ]);
    await Future.wait([
      left.update(rows.first.id, favorite: true),
      right.update(rows.first.id, tags: ['Shared']),
    ]);
    await left.reload();
    expect(left.entries, hasLength(2));
    expect(left.get(rows.first.id)!.favorite, isTrue);
    expect(left.get(rows.first.id)!.tags, ['Shared']);
    await right.remove(rows.last.id);
    await left.reload();
    expect(left.entries.single.id, rows.first.id);
  });

  test(
    'failed persistence exposes no partial row mutation and can retry',
    () async {
      final preferences = await SharedPreferences.getInstance();
      var fail = false;
      final library = await EbookLibrary.open(
        preferences: preferences,
        writePreference: (key, value) async {
          if (fail) return false;
          return preferences.setString(key, value);
        },
      );
      final row = await _open(library, source: _source());
      final revision = library.revision;
      final before = preferences.getString(EbookLibrary.preferencesKey);
      fail = true;
      await expectLater(
        library.update(row.id, favorite: true, shelves: ['Draft shelf']),
        throwsStateError,
      );
      expect(library.revision, revision);
      expect(library.get(row.id)!.favorite, isFalse);
      expect(library.get(row.id)!.shelves, isEmpty);
      expect(preferences.getString(EbookLibrary.preferencesKey), before);
      fail = false;
      await library.update(row.id, favorite: true, shelves: ['Draft shelf']);
      expect(library.get(row.id)!.favorite, isTrue);
    },
  );

  test('malformed or future catalog data is not silently replaced', () async {
    final preferences = await SharedPreferences.getInstance();
    final library = await EbookLibrary.open(preferences: preferences);
    final row = await _open(library, source: _source());
    for (final raw in [
      '{broken',
      '[]',
      '{"format":"crispcloud-ebook-library","version":2,"entries":[]}',
    ]) {
      await preferences.setString(EbookLibrary.preferencesKey, raw);
      await expectLater(
        library.update(row.id, favorite: true),
        throwsA(
          anyOf(isA<FormatException>(), isA<EbookReadingDataException>()),
        ),
      );
      expect(preferences.getString(EbookLibrary.preferencesKey), raw);
      expect(library.get(row.id)!.favorite, isFalse);
      await expectLater(
        EbookLibrary.open(preferences: preferences),
        throwsA(
          anyOf(isA<FormatException>(), isA<EbookReadingDataException>()),
        ),
      );
    }
  });

  test(
    'entry schema rejects access metadata injection and malformed values',
    () async {
      final library = await EbookLibrary.open();
      final row = await _open(library, source: _source());
      expect(
        () => EbookLibraryEntry.fromJson({
          ...row.toJson(),
          'credentials': 'secret',
        }),
        throwsFormatException,
      );
      final mutations = <void Function(Map<String, dynamic>)>[
        (json) => json['source']['storage']['root'] = 42,
        (json) => json['source']['storage']['persistent'] = false,
        (json) => json['source']['path'] = '/books/\u0000bad.epub',
        (json) => json['source']['credentials'] = 'secret',
        (json) => json['progress'] = 2,
        (json) => json['favorite'] = 'true',
        (json) => json['tags'] = List.filled(51, 'tag'),
        (json) => json['lastOpenedAt'] = -1,
        (json) => json['id'] = '0' * 64,
      ];
      for (final mutate in mutations) {
        final json =
            jsonDecode(jsonEncode(row.toJson())) as Map<String, dynamic>;
        mutate(json);
        expect(() => EbookLibraryEntry.fromJson(json), throwsFormatException);
      }
    },
  );

  test(
    'filters combine literal title, author, tag, shelf, favorite and status',
    () async {
      final library = await EbookLibrary.open();
      final first = await _open(
        library,
        source: _source(path: '/one.epub'),
        title: 'A.* literal title',
      );
      final second = await _open(
        library,
        source: _source(path: '/two.epub'),
        title: 'A second title',
        at: DateTime.utc(2026, 11, 13),
      );
      await library.update(
        first.id,
        favorite: true,
        tags: ['Science'],
        shelves: ['Research'],
        status: EbookReadingStatus.completed,
      );
      expect(library.query(text: 'A.*').single.id, first.id);
      expect(
        library
            .query(
              text: 'author science',
              favoritesOnly: true,
              shelf: 'research',
              tag: 'SCIENCE',
              status: EbookReadingStatus.completed,
            )
            .single
            .id,
        first.id,
      );
      expect(
        library.query(favoritesOnly: true, status: EbookReadingStatus.unread),
        isEmpty,
      );
      expect(library.entries.first.id, second.id);
      expect(library.shelves, ['Research']);
      expect(library.tags, ['Science']);
      expect(library.query(sort: EbookLibrarySort.title).map((row) => row.id), [
        second.id,
        first.id,
      ]);
    },
  );

  test('progress rejects a stale book revision or renderer and validates its range', () async {
    final library = await EbookLibrary.open();
    final row = await _open(library, source: _source());
    await library.recordProgress(
      row.id,
      contentSha256: _hash,
      renderer: EbookReaderRenderer.foliate,
      fraction: .4,
    );
    for (final renderer in [EbookReaderRenderer.portable]) {
      await expectLater(
        library.recordProgress(
          row.id,
          contentSha256: _hash,
          renderer: renderer,
          fraction: .8,
        ),
        throwsStateError,
      );
    }
    await expectLater(
      library.recordProgress(
        row.id,
        contentSha256: _otherHash,
        renderer: EbookReaderRenderer.foliate,
        fraction: .8,
      ),
      throwsStateError,
    );
    expect(
      () => library.recordProgress(
        row.id,
        contentSha256: _hash,
        renderer: EbookReaderRenderer.foliate,
        fraction: double.infinity,
      ),
      throwsFormatException,
    );
    expect(library.get(row.id)!.progress, .4);
    final portable = await _open(
      library,
      source: _source(),
      renderer: EbookReaderRenderer.portable,
    );
    expect(portable.progress, isNull);
  });

  test(
    'capacity rejects another book without evicting favorites or existing rows',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final library = await EbookLibrary.open();
      final seed = await _open(library, source: _source());
      final entries = List.generate(EbookLibrary.maximumEntries, (index) {
        final source = _source(path: '/books/$index.epub');
        return {
          ...seed.toJson(),
          'id': EbookLibrary.idFor(
            source: source,
            contentSha256: _hash,
            contentByteLength: 1234,
          ),
          'source': source.toJson(),
          'favorite': index == 0,
        };
      });
      final raw = jsonEncode({
        'format': 'crispcloud-ebook-library',
        'version': 1,
        'entries': entries,
      });
      await preferences.setString(EbookLibrary.preferencesKey, raw);
      await library.reload();
      await expectLater(
        _open(library, source: _source(path: '/one-more.epub')),
        throwsStateError,
      );
      expect(library.entries, hasLength(EbookLibrary.maximumEntries));
      expect(library.query(favoritesOnly: true), hasLength(1));
      expect(preferences.getString(EbookLibrary.preferencesKey), raw);
    },
  );

  test(
    'clearing a replaced position preserves status and checks both bindings',
    () async {
      final library = await EbookLibrary.open();
      final row = await _open(library, source: _source());
      await library.update(
        row.id,
        favorite: true,
        status: EbookReadingStatus.completed,
      );
      final readAt = DateTime.utc(2026, 11, 12, 12);
      await library.recordProgress(
        row.id,
        contentSha256: _hash,
        renderer: EbookReaderRenderer.foliate,
        fraction: .8,
        readAt: readAt,
      );
      await expectLater(
        library.clearProgress(
          row.id,
          contentSha256: _otherHash,
          renderer: EbookReaderRenderer.foliate,
        ),
        throwsStateError,
      );
      await expectLater(
        library.clearProgress(
          row.id,
          contentSha256: _hash,
          renderer: EbookReaderRenderer.portable,
        ),
        throwsStateError,
      );
      expect(library.get(row.id)!.progress, .8);
      await library.clearProgress(
        row.id,
        contentSha256: _hash,
        renderer: EbookReaderRenderer.foliate,
      );
      final restored = (await EbookLibrary.open()).get(row.id)!;
      expect(restored.progress, isNull);
      expect(restored.status, EbookReadingStatus.completed);
      expect(restored.favorite, isTrue);
      expect(restored.lastReadAt, readAt);
    },
  );
}
