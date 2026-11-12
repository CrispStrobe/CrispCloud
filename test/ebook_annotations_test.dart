import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/ebook_annotations.dart';
import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _bytes(int revision) => Uint8List.fromList([80, 75, revision, 4]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'annotation keys include document identity and every source byte',
    () async {
      const documentId = 'provider://account/folder/book.epub';
      final first = await EbookAnnotations.open(documentId, _bytes(1));
      final same = await EbookAnnotations.open(documentId, _bytes(1));
      final edited = await EbookAnnotations.open(documentId, _bytes(2));
      final copied = await EbookAnnotations.open(
        'another-provider/book.epub',
        _bytes(1),
      );
      expect(
        first.key,
        'ebook.annotations.v1.${sha256.convert(utf8.encode(documentId))}.'
        '${sha256.convert(_bytes(1))}',
      );
      expect(first.key, same.key);
      expect(first.key, isNot(edited.key));
      expect(first.key, isNot(copied.key));
      expect(first.key, isNot(contains(documentId)));
    },
  );

  test(
    'progress, bookmarks, highlights, notes and appearance roundtrip',
    () async {
      final sidecar = await EbookAnnotations.open('source', _bytes(1));
      sidecar.location = const EbookLocation(
        cfi: 'epubcfi(/6/2!/4/2:5)',
        fraction: .42,
        chapterTitle: 'Chapter one',
        sectionIndex: 3,
      );
      sidecar.bookmarks.add(sidecar.location!);
      sidecar.highlights.add(
        const EbookHighlight(
          id: 'highlight-1',
          cfi: 'epubcfi(/6/2!/4/2:5,/1:0,/1:8)',
          color: '#ffcc00',
          note: 'Keep this passage — Grüße',
        ),
      );
      sidecar.appearance = const EbookAppearance(
        fontSize: 23,
        lineHeight: 1.8,
        theme: 'sepia',
        flow: 'scrolled',
        fontFamily: 'sans-serif',
      );
      await sidecar.save();
      final restored = await EbookAnnotations.open('source', _bytes(1));
      expect(restored.location!.toJson(), sidecar.location!.toJson());
      expect(
        restored.bookmarks.single.toJson(),
        sidecar.bookmarks.single.toJson(),
      );
      expect(
        restored.highlights.single.toJson(),
        sidecar.highlights.single.toJson(),
      );
      expect(restored.appearance.toJson(), sidecar.appearance.toJson());

      final edited = await EbookAnnotations.open('source', _bytes(2));
      expect(edited.location, isNull);
      expect(edited.bookmarks, isEmpty);
      expect(edited.highlights, isEmpty);
      final copied = await EbookAnnotations.open('copy', _bytes(1));
      expect(copied.location, isNull);
    },
  );

  test(
    'queued saves capture their submitted state and latest progress wins',
    () async {
      final sidecar = await EbookAnnotations.open('source', _bytes(1));
      sidecar.location = const EbookLocation(cfi: 'first', fraction: .1);
      final first = sidecar.save();
      sidecar.location = const EbookLocation(cfi: 'second', fraction: .2);
      final second = sidecar.save();
      sidecar.location = const EbookLocation(
        cfi: 'not-yet-saved',
        fraction: .3,
      );
      await Future.wait([first, second]);
      final restored = await EbookAnnotations.open('source', _bytes(1));
      expect(restored.location!.cfi, 'second');
      expect(restored.location!.fraction, .2);
    },
  );

  test('corrupt local preferences cannot stop a book from opening', () async {
    final preferences = await SharedPreferences.getInstance();
    final original = await EbookAnnotations.open('source', _bytes(1));
    await preferences.setInt(original.key, 42);
    final wrongType = await EbookAnnotations.open(
      'source',
      _bytes(1),
      preferences: preferences,
    );
    expect(wrongType.location, isNull);
    expect(wrongType.highlights, isEmpty);
    for (final invalid in ['{broken', '[]', '{"bookmarks":[42]}']) {
      await preferences.setString(original.key, invalid);
      final restored = await EbookAnnotations.open(
        'source',
        _bytes(1),
        preferences: preferences,
      );
      expect(restored.location, isNull);
      expect(restored.bookmarks, isEmpty);
      expect(restored.highlights, isEmpty);
    }
  });

  test(
    'sidecar bounds cap item counts and reject an oversized write',
    () async {
      final sidecar = await EbookAnnotations.open('source', _bytes(1));
      for (var i = 0; i < 505; i++) {
        sidecar.bookmarks.add(EbookLocation(cfi: 'location-$i', fraction: 0));
        sidecar.highlights.add(EbookHighlight(id: '$i', cfi: 'highlight-$i'));
      }
      await sidecar.save();
      final restored = await EbookAnnotations.open('source', _bytes(1));
      expect(restored.bookmarks, hasLength(500));
      expect(restored.highlights, hasLength(500));

      sidecar.highlights
        ..clear()
        ..add(
          EbookHighlight(id: 'huge', cfi: 'cfi', note: 'a' * (2 * 1024 * 1024)),
        );
      await expectLater(sidecar.save(), throwsStateError);
      final afterFailure = await EbookAnnotations.open('source', _bytes(1));
      expect(afterFailure.highlights, hasLength(500));
      sidecar.highlights.clear();
      await sidecar.save();
      final recovered = await EbookAnnotations.open('source', _bytes(1));
      expect(recovered.highlights, isEmpty);
    },
  );
}
