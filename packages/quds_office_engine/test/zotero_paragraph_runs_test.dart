import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

List<String> _paragraphs(ZoteroFormattedText value) => value
    .toParagraphRuns()
    .map((runs) => runs.map((r) => r.text).join())
    .toList();

void main() {
  test('CSL entry blocks split paragraphs while br stays within its entry', () {
    final value = ZoteroFormattedText.fromHtml(
      '<div class="csl-bib-body"><div class="csl-entry">Alpha <i>Book</i><br/>Details</div>'
      '<div class="csl-entry"><span style="font-variant:small-caps">Beta</span>.</div></div>',
    );
    expect(value.plainText, 'Alpha Book\nDetails\nBeta.');
    expect(value.paragraphBreakOffsets, [18]);
    expect(_paragraphs(value), ['Alpha Book\nDetails', 'Beta.']);
    final runs = value.toParagraphRuns(
      baseProperties: WmlRunProps(color: '123456', smallCaps: true),
    );
    expect(
      runs.first.singleWhere((r) => r.text.trim() == 'Book').properties.italic,
      isTrue,
    );
    expect(runs.last.first.properties.smallCaps, isTrue);
    expect(runs.last.last.properties.smallCaps, isFalse);
    expect(
      runs.expand((p) => p).every((r) => r.properties.color == '123456'),
      isTrue,
    );
    expect(runs.first.first.properties.smallCaps, isFalse);
  });

  test('nested and empty outer blocks add no empty paragraphs', () {
    for (final html in [
      '<div><div><p>A</p><p>B</p></div></div>',
      '<div></div><div>A</div><div></div><div>B</div><div></div>',
      '<div class="csl-bib-body"><div class="csl-entry">A</div><div class="csl-entry">B</div></div>',
    ]) {
      final value = ZoteroFormattedText.fromHtml(html);
      expect(value.plainText, 'A\nB');
      expect(value.paragraphBreakOffsets, [1]);
      expect(_paragraphs(value), ['A', 'B']);
    }
  });

  test('explicit leading, repeated and trailing breaks stay soft', () {
    final value = ZoteroFormattedText.fromHtml(
      '<div><br/>A<br/><br/>B<br/></div>',
    );
    expect(value.plainText, '\nA\n\nB\n');
    expect(value.paragraphBreakOffsets, isEmpty);
    expect(_paragraphs(value), ['\nA\n\nB\n']);
  });

  test(
    'structural offsets use UTF-16 and splitting does not share properties',
    () {
      final value = ZoteroFormattedText.fromHtml(
        '<p><i>📚 A</i></p><p><i>B</i></p>',
      );
      expect(value.paragraphBreakOffsets, [4]);
      final paragraphs = value.toParagraphRuns();
      expect(_paragraphs(value), ['📚 A', 'B']);
      paragraphs.first.first.properties.italic = false;
      expect(paragraphs.last.first.properties.italic, isTrue);
      expect(value.toParagraphRuns().first.first.properties.italic, isTrue);
    },
  );
}
