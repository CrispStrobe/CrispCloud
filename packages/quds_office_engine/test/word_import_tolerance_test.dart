import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Real-world packages that Word opens but the importer used to refuse:
// measurements written with decimals or units, and content controls whose
// native IDs are already duplicated in the source.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

OpcPackage _package(String body) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="$_w"><w:body>$body</w:body></w:document>',
      );
  return package;
}

String _control(String id, String text) =>
    '<w:sdt><w:sdtPr><w:id w:val="$id"/></w:sdtPr><w:sdtContent>'
    '<w:p><w:r><w:t>$text</w:t></w:r></w:p></w:sdtContent></w:sdt>';

void main() {
  test('decimal and unit measurements import instead of aborting', () {
    final doc = WordDeserializer().read(
      _package(
        '<w:p><w:pPr><w:spacing w:before="120.5" w:after="6pt" w:line="276.0" '
        'w:lineRule="auto"/><w:ind w:left="0.5in" w:hanging="18pt"/></w:pPr>'
        '<w:r><w:rPr><w:sz w:val="11.5pt"/></w:rPr><w:t>Text</w:t></w:r></w:p>'
        '<w:p><w:r><w:rPr><w:sz w:val="23"/></w:rPr><w:t>Plain</w:t></w:r></w:p>'
        '<w:sectPr><w:pgMar w:top="1417.5" w:right="1440" w:bottom="2cm" '
        'w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>'
        '<w:cols w:num="x" w:space="708"/></w:sectPr>',
      ),
    );
    final first = doc.paragraphs.first;
    expect(first.properties.spacingBefore, closeTo(6.025, 1e-9));
    expect(first.properties.spacingAfter, 6);
    expect(first.properties.lineSpacing, closeTo(1.15, 1e-9));
    expect(first.properties.indent.left, 36);
    expect(first.properties.indent.hanging, 18);
    final runs = doc.paragraphs.map(
      (p) => p.inlines.whereType<WmlRun>().first.properties.fontSizeHalfPoints,
    );
    expect(runs, [23, 23]);
    final section = doc.sections.single;
    expect(section.margins.top, closeTo(70.875, 1e-9));
    expect(section.margins.bottom, closeTo(56.693, 1e-3));
    expect(section.columnCount, 1);
    WordSerializer().writeBytes(doc);
  });

  test('non-finite parsed measurements cannot escape into layout or save', () {
    final huge = '9' * 400;
    final doc = WordDeserializer().read(
      _package(
        '<w:p><w:pPr><w:spacing w:before="${huge}pt"/></w:pPr>'
        '<w:r><w:rPr><w:sz w:val="$huge"/></w:rPr><w:t>Text</w:t></w:r></w:p>'
        '<w:sectPr/>',
      ),
    );
    expect(doc.paragraphs.first.properties.spacingBefore, 0);
    expect(
      doc.paragraphs.first.inlines
          .whereType<WmlRun>()
          .first
          .properties
          .fontSizeHalfPoints,
      24,
    );
    expect(WordSerializer().writeBytes(doc), isNotEmpty);
  });

  test(
    'duplicate control IDs already in the source do not block saving',
    () async {
      final doc = WordDeserializer().read(
        _package('${_control('7', 'One')}${_control('7', 'Two')}<w:sectPr/>'),
      );
      // The editor saves in a background isolate, which receives a copy of
      // the document; the tolerance must travel with it.
      final bytes = await OfficeIsolateSave.word(doc);
      final reopened = WordDeserializer().readBytes(bytes);
      expect(reopened.paragraphs.map((p) => p.text), ['One', 'Two']);
      // Imported IDs are not rewritten.
      final xml = WordSerializer()
          .write(reopened)
          .getPart('/word/document.xml')!
          .readText();
      expect('w:val="7"'.allMatches(xml), hasLength(2));
    },
  );

  test('a duplicate introduced by an edit is still rejected', () {
    final doc = WordDeserializer().read(
      _package('${_control('7', 'One')}${_control('7', 'Two')}<w:sectPr/>'),
    );
    final extra = WmlClone.block(doc.sections.single.blocks.first);
    expect(
      () => WordContentControls.assertCanInsert(doc, [extra]),
      throwsUnsupportedError,
    );
    doc.sections.single.blocks.add(extra);
    expect(() => WordSerializer().writeBytes(doc), throwsStateError);
  });
}
