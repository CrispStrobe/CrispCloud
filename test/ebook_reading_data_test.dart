import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/ebook_annotations.dart';
import 'package:crisp_cloud/services/ebook_chapter_reader_controller.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _bytes([int revision = 1]) =>
    Uint8List.fromList([80, 75, revision, 4]);
String _cfi(int n) => 'epubcfi(/6/${n * 2 + 2}!/4/2:0)';
EbookLocation _location(int n) => EbookLocation(
  cfi: _cfi(n),
  fraction: n / 1000,
  chapterTitle: 'Chapter $n',
  sectionIndex: n,
);
EbookHighlight _highlight(String id, {String note = ''}) =>
    EbookHighlight(id: id, cfi: _cfi(0), note: note);
Matcher _code(EbookReadingDataError code) => isA<EbookReadingDataException>()
    .having((error) => error.code, 'code', code);

Future<EbookAnnotations> _filled(String source) async {
  final value = await EbookAnnotations.open(source, _bytes());
  value.location = _location(7);
  value.bookmarks.addAll([_location(9), _location(2)]);
  value.highlights.add(
    _highlight('note-1', note: 'Grüße — 日本語 📖\nKeep this passage.'),
  );
  value.appearance = const EbookAppearance(
    fontSize: 24,
    lineHeight: 2,
    theme: 'sepia',
    flow: 'scrolled',
    fontFamily: 'sans-serif',
    maxColumnCount: 3,
    pageMargin: 48,
    pageWidth: 1000,
    usePublisherStyles: false,
  );
  return value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'portable JSON retains all reading data but no source or account metadata',
    () async {
      final first = await _filled(
        'remote://private-account/private-path/secret.epub',
      );
      final encoded = first.exportReadingData();
      expect(encoded, isNot(contains('private-account')));
      expect(encoded, isNot(contains('private-path')));
      expect(encoded, isNot(contains(first.key)));
      final decoded = EbookReadingData.decode(encoded);
      expect(decoded.location!.toJson(), first.location!.toJson());
      expect(decoded.appearance.toJson(), first.appearance.toJson());
      expect(decoded.highlights.single.note, first.highlights.single.note);
      expect(decoded.noteCount, 1);
      expect(decoded.contentSha256, first.contentSha256);
      expect(decoded.contentByteLength, _bytes().length);
      expect(decoded.encode(), encoded);

      final copied = await EbookAnnotations.open(
        'a-different-device-source',
        _bytes(),
      );
      await copied.applyReadingDataImport(
        copied.previewReadingDataImport(
          encoded,
          mode: EbookReadingDataMergeMode.replace,
        ),
      );
      final reopened = await EbookAnnotations.open(
        'a-different-device-source',
        _bytes(),
      );
      expect(reopened.exportReadingData(), encoded);
    },
  );

  test(
    'renderer namespaces stay separate and retain the legacy portable key',
    () async {
      final foliate = await EbookAnnotations.open('book', _bytes());
      final portable = await EbookAnnotations.open(
        'book',
        _bytes(),
        renderer: EbookReaderRenderer.portable,
      );
      final legacyPortable = await EbookAnnotations.open(
        'book:chapter-reader',
        _bytes(),
      );
      expect(portable.key, legacyPortable.key);
      expect(portable.key, isNot(foliate.key));
      const target = EbookChapterTarget(
        path: 'OPS/Grüße.xhtml',
        fragment: '日本語%2F',
        progress: .35,
      );
      portable.location = EbookLocation(
        cfi: target.locator,
        fraction: .25,
        sectionIndex: 2,
      );
      portable.bookmarks.add(portable.location!);
      final decoded = EbookReadingData.decode(portable.exportReadingData());
      expect(decoded.renderer, EbookReaderRenderer.portable);
      expect(decoded.location!.cfi, target.locator);
      portable.location = const EbookLocation(
        cfi: 'crisp-section:3',
        fraction: .3,
      );
      expect(
        EbookReadingData.decode(portable.exportReadingData()).location!.cfi,
        'crisp-section:3',
      );
    },
  );

  test(
    'exact bytes and renderer are both required before applying a batch',
    () async {
      final original = await _filled('source');
      final encoded = original.exportReadingData();
      final edited = await EbookAnnotations.open('source', _bytes(2));
      expect(
        () => edited.previewReadingDataImport(encoded),
        throwsA(_code(EbookReadingDataError.contentMismatch)),
      );
      final portable = await EbookAnnotations.open(
        'source',
        _bytes(),
        renderer: EbookReaderRenderer.portable,
      );
      expect(
        () => portable.previewReadingDataImport(encoded),
        throwsA(_code(EbookReadingDataError.rendererMismatch)),
      );
      expect(edited.bookmarks, isEmpty);
      expect(portable.bookmarks, isEmpty);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), isEmpty);
    },
  );

  test(
    'merge policies resolve duplicate identities deterministically',
    () async {
      final local = await _filled('local');
      local.highlights.add(_highlight('local-only', note: 'local'));
      final incoming = await _filled('incoming');
      incoming.highlights[0] = _highlight('note-1', note: 'replacement');
      incoming.highlights.add(_highlight('import-only', note: 'new'));
      incoming.bookmarks[0] = EbookLocation(
        cfi: _cfi(9),
        fraction: .6,
        chapterTitle: 'Renamed chapter',
        sectionIndex: 9,
      );
      incoming.bookmarks.add(_location(20));
      incoming.location = _location(20);
      incoming.appearance = const EbookAppearance(theme: 'dark');
      final keep = local.previewReadingDataImport(incoming.exportReadingData());
      final prefer = local.previewReadingDataImport(
        incoming.exportReadingData(),
        mode: EbookReadingDataMergeMode.mergePreferImported,
      );
      final replace = local.previewReadingDataImport(
        incoming.exportReadingData(),
        mode: EbookReadingDataMergeMode.replace,
      );
      expect(keep.conflictCount, 2);
      expect(keep.addedBookmarks, 1);
      expect(keep.addedHighlights, 1);
      expect(
        keep.result.highlights.singleWhere((item) => item.id == 'note-1').note,
        local.highlights.first.note,
      );
      expect(keep.result.location!.cfi, local.location!.cfi);
      expect(keep.appearanceChanged, isFalse);
      expect(
        prefer.result.highlights
            .singleWhere((item) => item.id == 'note-1')
            .note,
        'replacement',
      );
      expect(prefer.result.location!.cfi, _cfi(20));
      expect(prefer.appearanceChanged, isTrue);
      expect(
        replace.result.highlights.map((item) => item.id),
        isNot(contains('local-only')),
      );
      await local.applyReadingDataImport(prefer);
      final again = local.previewReadingDataImport(
        incoming.exportReadingData(),
        mode: EbookReadingDataMergeMode.mergePreferImported,
      );
      expect(again.hasChanges, isFalse);
      expect(again.conflictCount, 0);
    },
  );

  test(
    'replace clears absent progress while merges retain the existing position',
    () async {
      final local = await _filled('local');
      final empty = await EbookAnnotations.open('empty', _bytes());
      final merge = local.previewReadingDataImport(
        empty.exportReadingData(),
        mode: EbookReadingDataMergeMode.mergePreferImported,
      );
      final replace = local.previewReadingDataImport(
        empty.exportReadingData(),
        mode: EbookReadingDataMergeMode.replace,
      );
      expect(merge.result.location!.cfi, local.location!.cfi);
      expect(replace.result.location, isNull);
      expect(replace.result.bookmarks, isEmpty);
      expect(replace.result.highlights, isEmpty);
    },
  );

  test(
    'no-op imports write nothing and snapshots cannot be mutated by callers',
    () async {
      final preferences = await SharedPreferences.getInstance();
      var writes = 0;
      final local = await EbookAnnotations.open(
        'local',
        _bytes(),
        preferences: preferences,
        writePreference: (key, value) async {
          writes++;
          return preferences.setString(key, value);
        },
      );
      local.bookmarks.add(_location(1));
      final plan = local.previewReadingDataImport(local.exportReadingData());
      expect(() => plan.result.bookmarks.clear(), throwsUnsupportedError);
      await local.applyReadingDataImport(plan);
      expect(writes, 0);
      expect(preferences.getKeys(), isEmpty);
    },
  );

  test(
    'invalid or future fields and unsupported versions are rejected',
    () async {
      final valid = jsonDecode(
        (await _filled('source')).exportReadingData(),
      ) as Map<String, dynamic>;
      final future = Map<String, dynamic>.from(valid)..['version'] = 2;
      expect(
        () => EbookReadingData.fromJson(future),
        throwsA(_code(EbookReadingDataError.unsupportedVersion)),
      );
      final unsupportedRenderer = Map<String, dynamic>.from(valid)
        ..['renderer'] = 'unknown-v3';
      expect(
        () => EbookReadingData.fromJson(unsupportedRenderer),
        throwsA(_code(EbookReadingDataError.rendererMismatch)),
      );
      for (final key in ['history', 'source', 'credentials']) {
        expect(
          () => EbookReadingData.fromJson({...valid, key: {}}),
          throwsA(_code(EbookReadingDataError.invalid)),
        );
      }
      final missing = Map<String, dynamic>.from(valid)..remove('location');
      expect(
        () => EbookReadingData.fromJson(missing),
        throwsA(_code(EbookReadingDataError.invalid)),
      );
    },
  );

  test(
    'strict schema rejects malformed targets, unsafe styles and duplicate IDs',
    () async {
      final original = (await _filled('source')).exportReadingData();
      final mutations = <void Function(Map<String, dynamic>)>[
        (json) => json['location']['fraction'] = 1.2,
        (json) => json['location']['sectionIndex'] = 1.5,
        (json) => json['location']['cfi'] = 'https://example.test/book',
        (json) => json['location']['cfi'] = 'epubcfi(/6/2))',
        (json) => json['bookmarks'].add(json['bookmarks'][0]),
        (json) => json['highlights'].add(json['highlights'][0]),
        (json) => json['highlights'][0]['color'] = 'red;url',
        (json) => json['highlights'][0]['note'] = null,
        (json) => json['highlights'][0]['note'] = 'a' * 16385,
        (json) =>
            json['appearance']['fontFamily'] = 'url(https://example.test/font)',
        (json) => json['appearance']['fontSize'] = double.nan,
        (json) => json['appearance']['maxColumnCount'] = 2.5,
        (json) => json['appearance']['usePublisherStyles'] = 'true',
        (json) => json['publication']['sha256'] = 'f' * 63,
        (json) => json['publication']['byteLength'] = -1,
      ];
      for (final mutate in mutations) {
        final json = jsonDecode(original) as Map<String, dynamic>;
        mutate(json);
        expect(
          () => EbookReadingData.fromJson(json),
          throwsA(isA<EbookReadingDataException>()),
        );
      }
    },
  );

  test('portable imports reject traversal, foreign targets and unsupported highlights', () async {
    final local = await EbookAnnotations.open(
      'portable',
      _bytes(),
      renderer: EbookReaderRenderer.portable,
    );
    for (final locator in [
      _cfi(0),
      'crisp-reader:v1:not-base64!',
      const EbookChapterTarget(path: '../outside.xhtml').locator,
      const EbookChapterTarget(path: '/outside.xhtml').locator,
      const EbookChapterTarget(path: 'https:outside.xhtml').locator,
    ]) {
      local.location = EbookLocation(cfi: locator, fraction: 0);
      expect(
        local.exportReadingData,
        throwsA(isA<EbookReadingDataException>()),
      );
    }
    local.location = null;
    local.highlights.add(_highlight('unsupported'));
    expect(
      local.exportReadingData,
      throwsA(_code(EbookReadingDataError.invalid)),
    );
  });

  test('UTF-8 and nesting budgets run before decoding, with quoted brackets ignored', () async {
    expect(
      () => EbookReadingData.decode(
        'é' * (EbookReadingData.maximumJsonBytes ~/ 2 + 1),
      ),
      throwsA(_code(EbookReadingDataError.tooLarge)),
    );
    expect(
      () => EbookReadingData.decode('${'[' * 17}0${']' * 17}'),
      throwsA(_code(EbookReadingDataError.invalid)),
    );
    final local = await _filled('local');
    local.highlights[0] = _highlight(
      'note-1',
      note: 'Quoted [ { \\ " brackets ] }',
    );
    expect(
      EbookReadingData.decode(local.exportReadingData()).highlights.single.note,
      local.highlights.single.note,
    );
  });

  test(
    'combined item limits reject the entire merge without dropping records',
    () async {
      final local = await EbookAnnotations.open('local', _bytes());
      local.bookmarks.addAll(List.generate(500, _location));
      await local.save();
      final incoming = await EbookAnnotations.open('incoming', _bytes());
      incoming.bookmarks.add(_location(500));
      final before = local.exportReadingData();
      expect(
        () => local.previewReadingDataImport(incoming.exportReadingData()),
        throwsA(_code(EbookReadingDataError.limitExceeded)),
      );
      expect(local.exportReadingData(), before);
      expect(
        (await EbookAnnotations.open('local', _bytes())).bookmarks,
        hasLength(500),
      );
    },
  );

  test(
    'a changed local draft invalidates a reviewed plan before any write',
    () async {
      final local = await _filled('local');
      await local.save();
      final beforeDisk = (await SharedPreferences.getInstance()).getString(
        local.key,
      );
      final incoming = await _filled('incoming');
      incoming.highlights.add(_highlight('imported'));
      final plan = local.previewReadingDataImport(incoming.exportReadingData());
      local.highlights.add(_highlight('new-local'));
      await expectLater(
        local.applyReadingDataImport(plan),
        throwsA(_code(EbookReadingDataError.stale)),
      );
      expect(local.highlights.map((item) => item.id), contains('new-local'));
      expect(
        local.highlights.map((item) => item.id),
        isNot(contains('imported')),
      );
      expect(
        (await SharedPreferences.getInstance()).getString(local.key),
        beforeDisk,
      );
    },
  );

  test('a plan from another source cannot mutate this sidecar', () async {
    final left = await EbookAnnotations.open('left', _bytes());
    final right = await EbookAnnotations.open('right', _bytes());
    final incoming = await _filled('incoming');
    final plan = left.previewReadingDataImport(incoming.exportReadingData());
    await expectLater(
      right.applyReadingDataImport(plan),
      throwsA(_code(EbookReadingDataError.stale)),
    );
    expect(right.bookmarks, isEmpty);
  });

  test('failed persistence leaves all live data and prior storage intact, then retries', () async {
    final preferences = await SharedPreferences.getInstance();
    var fail = false;
    final local = await EbookAnnotations.open(
      'local',
      _bytes(),
      preferences: preferences,
      writePreference: (key, value) async {
        if (fail) return false;
        return preferences.setString(key, value);
      },
    );
    local.bookmarks.add(_location(1));
    await local.save();
    final before = local.exportReadingData();
    final incoming = await _filled('incoming');
    final plan = local.previewReadingDataImport(
      incoming.exportReadingData(),
      mode: EbookReadingDataMergeMode.replace,
    );
    fail = true;
    await expectLater(local.applyReadingDataImport(plan), throwsStateError);
    expect(local.exportReadingData(), before);
    expect(
      (await EbookAnnotations.open('local', _bytes())).exportReadingData(),
      before,
    );
    expect(local.isApplyingReadingData, isFalse);
    fail = false;
    await local.applyReadingDataImport(plan);
    expect(local.exportReadingData(), incoming.exportReadingData());
  });

  test(
    'a concurrent relocation is preserved and import rolls back before failing',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final started = Completer<void>();
      final release = Completer<void>();
      var block = false;
      var blocked = false;
      final local = await EbookAnnotations.open(
        'local',
        _bytes(),
        preferences: preferences,
        writePreference: (key, value) async {
          if (block && !blocked) {
            blocked = true;
            started.complete();
            await release.future;
          }
          return preferences.setString(key, value);
        },
      );
      local.location = _location(1);
      await local.save();
      final incoming = await _filled('incoming');
      final plan = local.previewReadingDataImport(
        incoming.exportReadingData(),
        mode: EbookReadingDataMergeMode.replace,
      );
      block = true;
      final importing = local.applyReadingDataImport(plan);
      final expectedFailure = expectLater(
        importing,
        throwsA(_code(EbookReadingDataError.stale)),
      );
      await started.future;
      expect(local.isApplyingReadingData, isTrue);
      expect(local.bookmarks, isEmpty);
      local.location = _location(4);
      release.complete();
      await expectedFailure;
      expect(local.location!.cfi, _cfi(4));
      expect(local.bookmarks, isEmpty);
      final reopened = await EbookAnnotations.open('local', _bytes());
      expect(reopened.location!.cfi, _cfi(4));
      expect(reopened.bookmarks, isEmpty);
    },
  );

  test('a second open reader cannot overwrite newly saved notes', () async {
    final first = await EbookAnnotations.open('shared-source', _bytes());
    final second = await EbookAnnotations.open('shared-source', _bytes());
    first.highlights.add(
      _highlight('keep-new-note', note: 'Saved by the other reader'),
    );
    await first.save();
    second.location = _location(3);
    await expectLater(
      second.save(),
      throwsA(_code(EbookReadingDataError.stale)),
    );
    final restored = await EbookAnnotations.open('shared-source', _bytes());
    expect(restored.highlights.single.id, 'keep-new-note');
    expect(restored.location, isNull);
    expect(second.location!.cfi, _cfi(3));
  });

  test(
    'an import preview rejects changes saved by another reader instance',
    () async {
      final first = await EbookAnnotations.open('shared-source', _bytes());
      final second = await EbookAnnotations.open('shared-source', _bytes());
      final incoming = await _filled('incoming');
      final plan = first.previewReadingDataImport(incoming.exportReadingData());
      second.highlights.add(_highlight('new-local-note'));
      await second.save();
      await expectLater(
        first.applyReadingDataImport(plan),
        throwsA(_code(EbookReadingDataError.stale)),
      );
      expect(first.highlights, isEmpty);
      final restored = await EbookAnnotations.open('shared-source', _bytes());
      expect(restored.highlights.single.id, 'new-local-note');
      expect(restored.bookmarks, isEmpty);
    },
  );

  test(
    'queued saves from this instance do not invalidate its own import plan',
    () async {
      final local = await EbookAnnotations.open('source', _bytes());
      local.bookmarks.add(_location(1));
      final pendingSave = local.save();
      final incoming = await _filled('incoming');
      final plan = local.previewReadingDataImport(incoming.exportReadingData());
      final applying = local.applyReadingDataImport(plan);
      await Future.wait([pendingSave, applying]);
      final restored = await EbookAnnotations.open('source', _bytes());
      expect(restored.bookmarks, hasLength(3));
      expect(restored.highlights, hasLength(1));
    },
  );
}
