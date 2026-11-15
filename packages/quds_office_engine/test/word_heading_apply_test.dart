import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Applying a heading follows Word: the document's own "heading N" style
// (found by its built-in name, so localized IDs work) replaces conflicting
// direct formatting; without a definition Word 365's built-in one is used.
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

WmlDocument _read({String styles = ''}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w"><w:body><w:p><w:pPr>'
        '<w:spacing w:before="0" w:after="0"/><w:jc w:val="center"/></w:pPr>'
        '<w:r><w:rPr><w:color w:val="000000"/></w:rPr><w:t>Title text</w:t></w:r>'
        '</w:p><w:sectPr/></w:body></w:document>',
      );
  if (styles.isNotEmpty) {
    package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.styles, target: 'styles.xml');
    package
        .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
        .writeText('<w:styles xmlns:w="$_w">$styles</w:styles>');
  }
  return WordDeserializer().read(package);
}

void main() {
  test('uses the document style found by its built-in name', () {
    final doc = _read(
      styles:
          '<w:style w:type="paragraph" w:default="1" w:styleId="Standard"><w:name w:val="Normal"/></w:style>'
          '<w:style w:type="paragraph" w:styleId="berschrift2"><w:name w:val="heading 2"/>'
          '<w:basedOn w:val="Standard"/><w:pPr><w:spacing w:before="160" w:after="80"/>'
          '<w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:color w:val="0F4761"/>'
          '<w:sz w:val="32"/></w:rPr></w:style>',
    );
    final p = doc.paragraphs.single;
    WordHeadingIo.apply(doc, p, 2);
    expect(p.properties.styleId, 'berschrift2');
    expect(p.properties.headingLevel, 2);
    expect(p.properties.spacingBefore, 8);
    expect(p.properties.spacingAfter, 4);
    final run = p.inlines.whereType<WmlRun>().single.properties;
    expect(run.fontSizePoints, 16);
    expect(run.color.toUpperCase(), '0F4761');
    expect(run.bold, isFalse);
  });

  test('falls back to the Word 365 built-in definition', () {
    final doc = _read();
    final p = doc.paragraphs.single;
    WordHeadingIo.apply(doc, p, 1);
    expect(p.properties.styleId, 'Heading1');
    expect(p.properties.spacingBefore, 18);
    expect(p.properties.spacingAfter, 4);
    expect(p.inlines.whereType<WmlRun>().single.properties.fontSizePoints, 20);
    // The document still saves and reopens as a heading.
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(doc),
    );
    expect(reopened.paragraphs.single.properties.headingLevel, 1);
  });
}
