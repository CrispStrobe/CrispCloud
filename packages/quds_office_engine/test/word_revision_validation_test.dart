import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlRevision _record(
  WmlDocument document,
  int start,
  int end, {
  WmlRevisionKind kind = WmlRevisionKind.insert,
}) => WordRevisions.record(
  document,
  kind: kind,
  paragraphIndex: 0,
  start: start,
  end: end,
  text: document.paragraphs.single.text.substring(start, end),
);

void main() {
  for (final isolate in [false, true]) {
    test(
      '${isolate ? 'isolate' : 'direct'} export rejects stale spans before package mutation',
      () async {
        var document = WmlDocument.empty(text: 'abXYZcd');
        _record(document, 2, 5);
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        final package = document.package!;
        final parts = <String, List<int>>{
          for (final uri in package.partNames)
            uri: package.getPart(uri)!.readBytes(),
        };
        final revision = document.revisions.single;
        WmlRunEdit.replaceRange(document.paragraphs.single, 0, 0, '!');
        if (isolate) {
          await expectLater(OfficeIsolateSave.word(document), throwsStateError);
        } else {
          expect(() => WordSerializer().write(document), throwsStateError);
        }
        expect(package.partNames, unorderedEquals(parts.keys));
        for (final part in package.parts) {
          expect(part.readBytes(), parts[part.uri], reason: part.uri);
        }
        expect(document.paragraphs.single.text, '!abXYZcd');
        expect(revision.accepted, isNull);
        expect(document.revisions, [same(revision)]);
        expect(
          () => WordRevisions.reject(document, revision),
          throwsStateError,
        );
        expect(document.paragraphs.single.text, '!abXYZcd');
      },
    );
  }

  test('batch validation is atomic when a later revision is invalid', () {
    final document = WmlDocument.empty(text: 'abXXcdYYef');
    final first = _record(document, 2, 4, kind: WmlRevisionKind.delete);
    final last = _record(document, 6, 8, kind: WmlRevisionKind.delete);
    last.text = 'mismatch';
    expect(() => WordRevisions.acceptAll(document), throwsStateError);
    expect(document.paragraphs.single.text, 'abXXcdYYef');
    expect(first.accepted, isNull);
    expect(last.accepted, isNull);
    expect(document.revisions, [same(first), same(last)]);
  });

  test(
    'invalid ranges cannot be clamped into unrelated text on resolution',
    () {
      for (final bounds in [(-1, 2), (4, 3), (2, 99)]) {
        final document = WmlDocument.empty(text: 'abXYZcd');
        final revision = _record(document, 2, 5)
          ..start = bounds.$1
          ..end = bounds.$2;
        expect(
          () => WordRevisions.reject(document, revision),
          throwsStateError,
        );
        expect(document.paragraphs.single.text, 'abXYZcd');
        expect(revision.accepted, isNull);
      }
    },
  );

  test('engine batch resolution rebases later ranges in insertion order', () {
    final document = WmlDocument.empty(text: 'abXXcdYYef');
    final first = _record(document, 2, 4);
    final last = _record(document, 6, 8);
    WordRevisions.rejectAll(document);
    expect(document.paragraphs.single.text, 'abcdef');
    expect(document.revisions, isEmpty);
    expect(first.accepted, isFalse);
    expect(last.accepted, isFalse);
    expect((last.start, last.end), (4, 6));
  });

  test(
    'recorded partial atomic spans expand with matching text immediately',
    () {
      final paragraph = WmlParagraph(
        inlines: [
          WmlRun(text: 'ab'),
          WmlRun(text: 'FIELD', fieldInstruction: ' REF target '),
          WmlRun(text: 'cd'),
        ],
      );
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      );
      final revision = _record(document, 3, 4);
      expect((revision.start, revision.end, revision.text), (2, 7, 'FIELD'));
      WordRevisions.validate(document);
      WordRevisions.reject(document, revision);
      expect(paragraph.text, 'abcd');
      expect(
        paragraph.inlines.whereType<WmlRun>().where((run) => run.isAtomic),
        isEmpty,
      );
    },
  );
}
