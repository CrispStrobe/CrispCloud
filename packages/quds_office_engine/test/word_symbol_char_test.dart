import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// w:sym holds a character of a symbol font (bullets, check marks, arrows).
// It used to be skipped on import, so every such glyph vanished on save.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

OpcPackage _package() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="$_w"><w:body>'
        '<w:p><w:pPr><w:pStyle w:val="Quote"/></w:pPr>'
        '<w:r><w:rPr><w:rStyle w:val="Strong"/><w:b/></w:rPr>'
        '<w:t xml:space="preserve">Done </w:t>'
        '<w:sym w:font="Wingdings" w:char="F0FC"/><w:t xml:space="preserve"> next</w:t></w:r>'
        '<w:r><w:sym w:font="Symbol" w:char="F0B7"/></w:r></w:p>'
        '<w:sectPr/></w:body></w:document>',
      );
  // A paragraph style with its own font: the cascade must not replace the
  // symbol font with it.
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="$_w">'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
        '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/>'
        '<w:basedOn w:val="Normal"/><w:rPr><w:rFonts w:ascii="Georgia" w:hAnsi="Georgia"/></w:rPr></w:style>'
        '<w:style w:type="character" w:styleId="Strong"><w:name w:val="Strong"/><w:rPr><w:b/></w:rPr></w:style>'
        '</w:styles>',
      );
  return package;
}

List<(String, String, bool)> _runs(WmlDocument doc) => [
  for (final run in doc.paragraphs.single.inlines.whereType<WmlRun>())
    (run.text, run.properties.asciiFont, run.properties.bold),
];

void main() {
  test('symbol characters import with their symbol font', () {
    final doc = WordDeserializer().read(_package());
    expect(doc.paragraphs.single.text, 'Done  next');
    expect(_runs(doc), [
      ('Done ', 'Georgia', true),
      ('', 'Wingdings', true),
      (' next', 'Georgia', true),
      ('', 'Symbol', false),
    ]);
  });

  test('symbol characters survive repeated isolate saves', () async {
    var doc = WordDeserializer().read(_package());
    final expected = _runs(doc);
    for (var cycle = 0; cycle < 3; cycle++) {
      doc = WordDeserializer().readBytes(await OfficeIsolateSave.word(doc));
      expect(_runs(doc), expected, reason: 'cycle $cycle');
    }
    final xml = WordSerializer()
        .write(doc)
        .getPart('/word/document.xml')!
        .readText();
    expect(
      xml,
      contains('<w:rFonts w:ascii="Wingdings" w:hAnsi="Wingdings" w:cs="Wingdings"/>'),
    );
    // CT_RPr order: rStyle before rFonts.
    expect(xml.indexOf('w:rStyle'), lessThan(xml.indexOf('Wingdings')));
  });
}
