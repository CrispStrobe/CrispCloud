import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Import and export used to resolve every tracked change against every other
// with a whole-document scan each time (revisions² × paragraphs): a real
// document with ~430 tracked changes took over a minute to open and save.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

OpcPackage _package(int paragraphs, int perParagraph) {
  final body = StringBuffer();
  for (var p = 0; p < paragraphs; p++) {
    body.write('<w:p>');
    for (var r = 0; r < perParagraph; r++) {
      body.write(
        '<w:r><w:t xml:space="preserve">plain $p.$r </w:t></w:r>'
        '<w:ins w:id="${p * perParagraph + r + 1}" w:author="A" w:date="2026-01-01T00:00:00Z">'
        '<w:r><w:t xml:space="preserve">added $p.$r </w:t></w:r></w:ins>',
      );
    }
    body.write('</w:p>');
  }
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w"><w:body>$body<w:sectPr/></w:body></w:document>',
      );
  return package;
}

class _CountedDocument extends WmlDocument {
  _CountedDocument(List<WmlParagraph> body)
    : super(
        sections: [
          WmlSection(blocks: <WmlBlock>[...body]),
        ],
      );

  int paragraphsRead = 0;

  @override
  Iterable<WmlParagraph> get paragraphs sync* {
    for (final paragraph in super.paragraphs) {
      paragraphsRead++;
      yield paragraph;
    }
  }
}

void main() {
  test(
    'tracked changes bind and resolve with one body traversal per batch',
    () {
      final body = [
        for (var i = 0; i < 600; i++)
          WmlParagraph(inlines: [WmlRun(text: 'A')]),
      ];
      final document = _CountedDocument(body);
      final header = WmlParagraph(inlines: [WmlRun(text: 'A')]);
      document.sections.single.header.add(header);
      WmlRevision revision(int id, int index, [WmlParagraph? target]) =>
          WmlRevision(
            id: id,
            kind: WmlRevisionKind.insert,
            paragraphIndex: index,
            start: 0,
            end: 1,
            text: 'A',
            targetParagraph: target,
          );
      final legacy = [for (var i = 0; i < 200; i++) revision(i, i + 200)];
      final auxiliary = revision(201, 0, header);
      final missing = revision(202, body.length);
      document.revisions.addAll([...legacy, auxiliary, missing]);

      final original = WordRevisions.capture(document);
      expect(document.paragraphsRead, body.length);
      expect(original.matches(document), isTrue);
      document.paragraphsRead = 0;
      WordRevisions.capture(document);
      expect(document.paragraphsRead, 0);

      final originalTargets = WordRevisions.resolveParagraphs(
        document,
        document.revisions,
      );
      expect(document.paragraphsRead, body.length);
      expect(originalTargets[legacy.first], same(body[200]));
      expect(originalTargets[legacy.last], same(body[399]));
      expect(originalTargets[auxiliary], same(header));
      expect(originalTargets[missing], isNull);

      document.sections.single.blocks
        ..remove(body[200])
        ..addAll([
          WmlParagraph(inlines: [WmlRun(text: 'new 1')]),
          WmlParagraph(inlines: [WmlRun(text: 'new 2')]),
        ]);
      final current = WordRevisions.resolveParagraphs(
        document,
        document.revisions,
      );
      expect(current[legacy.first], isNull);
      expect(current[legacy.last], same(body[399]));
      expect(current[auxiliary], same(header));
      expect(current[missing], isNull);
    },
  );

  test('many tracked changes import and save in linear-ish time', () {
    final watch = Stopwatch()..start();
    final doc = WordDeserializer().read(_package(300, 3));
    expect(doc.revisions, hasLength(900));
    final bytes = WordSerializer().writeBytes(doc);
    final reopened = WordDeserializer().readBytes(bytes);
    expect(reopened.revisions, hasLength(900));
    expect(
      reopened.revisions.map((r) => r.text).toSet(),
      contains('added 299.2 '),
    );
    // Generous bound: the quadratic version needed minutes here.
    expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
  });

  test('overlap detection is unchanged', () {
    final doc = WordDeserializer().read(_package(2, 2));
    final first = doc.revisions.first;
    final p = WordRevisions.resolveParagraph(doc, first)!;
    WordRevisions.record(
      doc,
      kind: first.kind,
      paragraphIndex: 0,
      start: first.start,
      end: first.end,
      text: p.text.substring(first.start, first.end),
      paragraph: p,
    );
    expect(doc.revisions.last.conflict, isNotNull);
    expect(() => WordSerializer().writeBytes(doc), throwsStateError);
  });
}
