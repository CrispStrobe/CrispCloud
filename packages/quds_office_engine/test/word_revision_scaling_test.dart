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

void main() {
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
