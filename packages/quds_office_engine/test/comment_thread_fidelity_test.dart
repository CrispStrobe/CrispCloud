import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _source() => WordDeserializer().readBytes(
  File('test/fixtures/fidelity/comment-threads.docx').readAsBytesSync(),
);

void _expectThreads(WmlDocument document, {required bool edited}) {
  final WmlComment root = WordComment.byId(document, 41)!;
  final WmlComment reply = WordComment.byId(document, 7)!;
  expect(root.resolved, !edited);
  expect(root.parentId, isNull);
  expect(reply.parentId, 41);
  expect(reply.resolved, edited);
  expect(WordComment.threadRootId(document, 7), 41);
  expect(WordComment.byId(document, 99)!.resolved, isFalse);
  expect(
    root.text,
    'Root opening paragraph\nRoot ${edited ? 'revised final' : 'final'} paragraph',
  );
  expect(
    reply.paragraphs.single.inlines.whereType<WmlRun>().single.properties.bold,
    isTrue,
  );
  expect(document.comments, hasLength(edited ? 4 : 3));
  if (edited) {
    expect(WordComment.byId(document, 55)!.parentId, 7);
    expect(WordComment.threadRootId(document, 55), 41);
  }
}

void main() {
  setUpAll(() {
    final source = File('build/fidelity-comment-threads/threads-source.docx');
    source.parent.createSync(recursive: true);
    File('test/fixtures/fidelity/comment-threads.docx').copySync(source.path);
  });
  test(
    'comment threads join last paragraph IDs rather than numeric comment IDs',
    () {
      _expectThreads(_source(), edited: false);
    },
  );

  for (final bool edited in <bool>[false, true]) {
    test(
      'comment thread ${edited ? 'edits' : 'imports'} survive three async saves',
      () async {
        WmlDocument document = _source();
        _expectThreads(document, edited: false);
        if (edited) {
          final WmlComment root = WordComment.byId(document, 41)!;
          root.paragraphs.last.inlines.whereType<WmlRun>().single.text =
              'Root revised final paragraph';
          root.resolved = false;
          WordComment.byId(document, 7)!.resolved = true;
          document.comments.add(
            WmlComment(
              id: 55,
              author: 'New reviewer',
              parentId: 7,
              text: 'Nested new reply',
            ),
          );
        }
        for (var cycle = 1; cycle <= 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(document);
          final output = File(
            'build/fidelity-comment-threads/threads-${edited ? 'edited' : 'imported'}-$cycle.docx',
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes);
          document = WordDeserializer().readBytes(bytes);
          _expectThreads(document, edited: edited);
        }
      },
    );
  }

  test(
    'comment copies and text replacements retain the native thread anchor',
    () {
      final WmlDocument document = _source();
      final WmlComment original = WordComment.byId(document, 41)!;
      final WmlComment copy = original.copy();
      expect(copy.paragraphId, '00ABC123');
      copy.text = 'Replaced comment text';
      document.comments[document.comments.indexOf(original)] = copy;
      final WmlDocument saved = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(WordComment.byId(saved, 41)!.paragraphId, '00ABC123');
      expect(WordComment.byId(saved, 41)!.text, 'Replaced comment text');
      expect(WordComment.byId(saved, 7)!.parentId, 41);
    },
  );

  test(
    'legacy numeric Quds anchors are repaired when no native anchors exist',
    () {
      final package = _source().package!;
      final comments = package.getPart('/review/threads.xml')!;
      comments.writeText(
        comments.readText().replaceAll(RegExp(r' w14:paraId="[^"]*"'), ''),
      );
      package
          .getPart('/review/thread-state.xml')!
          .writeText(
            '<w15:commentsEx xmlns:w15="${OfficeNamespaces.w15}">'
            '<w15:commentEx w15:paraId="00000007" w15:paraIdParent="00000029" w15:done="0"/>'
            '<w15:commentEx w15:paraId="00000029" w15:done="1"/>'
            '<w15:commentEx w15:paraId="00000063"/>'
            '</w15:commentsEx>',
          );
      final WmlDocument document = WordDeserializer().read(package);
      _expectThreads(document, edited: false);
      final WmlDocument saved = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      _expectThreads(saved, edited: false);
      expect(WordComment.byId(saved, 41)!.paragraphId, isNot('00000029'));
    },
  );

  test(
    'native anchors never fall back to coincidental numeric comment IDs',
    () {
      final package = _source().package!;
      final extensions = package.getPart('/review/thread-state.xml')!;
      extensions.writeText(
        extensions.readText().replaceFirst(
          'w15:paraId="00ABC123"',
          'w15:paraId="00000029"',
        ),
      );
      final WmlDocument document = WordDeserializer().read(package);
      expect(WordComment.byId(document, 41)!.resolved, isFalse);
      expect(WordComment.byId(document, 7)!.parentId, 41);
    },
  );

  test(
    'clearing comments normalizes native content types on empty owning parts',
    () {
      final WmlDocument document = _source();
      for (final uri in <String>[
        '/review/threads.xml',
        '/review/thread-state.xml',
      ]) {
        document.package!.getPart(uri)!.contentType = 'application/xml';
        document.package!.contentTypes.setOverride(uri, 'application/xml');
      }
      document.comments.clear();
      for (final paragraph in document.paragraphs) {
        for (final run in paragraph.inlines.whereType<WmlRun>()) {
          run.commentIds.clear();
        }
      }
      final package = WordSerializer().write(document);
      expect(
        package.getPart('/review/threads.xml')!.contentType,
        OfficeContentTypes.wordComments,
      );
      expect(
        package.getPart('/review/thread-state.xml')!.contentType,
        OfficeContentTypes.wordCommentsExtended,
      );
      expect(
        package.contentTypes.contentTypeFor('/review/threads.xml'),
        OfficeContentTypes.wordComments,
      );
      expect(
        package.contentTypes.contentTypeFor('/review/thread-state.xml'),
        OfficeContentTypes.wordCommentsExtended,
      );
      expect(WordDeserializer().readBytes(package.save()).comments, isEmpty);
    },
  );
}
