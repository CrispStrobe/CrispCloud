import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

WmlDocument read(String content, {String? styles}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$w"><w:body>$content<w:sectPr/></w:body></w:document>',
      );
  if (styles != null) {
    package.createPart(
      '/word/styles.xml',
      OfficeContentTypes.wordStyles,
      Uint8List.fromList(styles.codeUnits),
    );
    package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.styles, target: 'styles.xml');
  }
  return WordDeserializer().read(package);
}

void main() {
  final sans = SfntFont.parse(
    File(
      '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
    ).readAsBytesSync(),
  );
  final mono = SfntFont.parse(
    File(
      '../quds_office_editor/fonts/LiberationMono-Regular.ttf',
    ).readAsBytesSync(),
  );
  final engine = WordLayoutEngine(
    font: null,
    measureFont: (_, size, props) => FontMetrics(
      font: props.asciiFont == 'Liberation Mono' ? mono : sans,
      fontSizePoints: size,
    ),
  );
  const mark =
      '<w:rPr><w:rFonts w:ascii="Liberation Mono"/><w:sz w:val="72"/></w:rPr>';
  const text =
      '<w:r><w:rPr><w:rFonts w:ascii="Arial"/><w:sz w:val="24"/></w:rPr><w:t>Visible</w:t></w:r>';

  test(
    'empty paragraph uses the authored mark font instead of an invented 11pt run',
    () {
      final doc = read('<w:p><w:pPr>$mark</w:pPr></w:p>');
      expect(doc.paragraphs.single.inlines.whereType<WmlRun>(), isEmpty);
      expect(
        doc.paragraphs.single.properties.importedParagraphMark!.fontSizePoints,
        36,
      );
      final laid = engine.layout(doc);
      // Blank paragraphs are a line advance, without a visible glyph.
      final expected = FontMetrics(
        font: mono,
        fontSizePoints: 36,
      ).typographicLineHeight;
      final next = read('<w:p><w:pPr>$mark</w:pPr></w:p><w:p>$text</w:p>');
      expect(
        engine.layout(next).pages.first.lines.first.y,
        closeTo(72 + expected, .001),
      );
      expect(laid.pages, hasLength(1));
    },
  );

  test(
    'mark resolves document defaults and paragraph style, not visible run overrides',
    () {
      final doc = read(
        '<w:p><w:pPr><w:pStyle w:val="Marked"/></w:pPr>$text</w:p>',
        styles:
            '<w:styles xmlns:w="$w"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Liberation Mono"/><w:sz w:val="36"/></w:rPr></w:rPrDefault></w:docDefaults>'
            '<w:style w:type="paragraph" w:styleId="Marked"><w:rPr><w:sz w:val="40"/></w:rPr></w:style></w:styles>',
      );
      final p = doc.paragraphs.single;
      expect(p.properties.importedParagraphMark!.asciiFont, 'Liberation Mono');
      expect(p.properties.importedParagraphMark!.fontSizePoints, 20);
      expect(
        p.inlines.whereType<WmlRun>().single.properties.asciiFont,
        'Arial',
      );
      expect(
        p.inlines.whereType<WmlRun>().single.properties.fontSizePoints,
        12,
      );
    },
  );

  test('repeated styled paragraph marks retain independent properties', () {
    final doc = read(
      '<w:p><w:pPr>$mark</w:pPr>$text</w:p>'
      '<w:p><w:pPr>$mark</w:pPr>$text</w:p>',
      styles:
          '<w:styles xmlns:w="$w"><w:docDefaults><w:rPrDefault><w:rPr>'
          '<w:color w:val="336699"/>'
          '</w:rPr></w:rPrDefault></w:docDefaults></w:styles>',
    );
    final paragraphs = doc.paragraphs.toList();
    final first = paragraphs.first.properties.importedParagraphMark!;
    final second = paragraphs.last.properties.importedParagraphMark!;
    expect(first, isNot(same(second)));
    expect(second.fontSizePoints, 36);
    expect(second.color, '336699');
    expect(second.explicitProperties, contains('color'));

    first
      ..fontSizeHalfPoints = 20
      ..color = 'FF0000'
      ..explicitProperties.clear();
    expect(second.fontSizePoints, 36);
    expect(second.color, '336699');
    expect(second.explicitProperties, contains('color'));
  });

  test(
    'mark metadata is independent in clones and survives three isolate saves',
    () async {
      var doc = read('<w:p><w:pPr>$mark</w:pPr>$text</w:p>');
      final clone = WmlClone.paragraph(doc.paragraphs.single);
      clone.properties.importedParagraphMark!.fontSizeHalfPoints = 20;
      expect(
        doc.paragraphs.single.properties.importedParagraphMark!.fontSizePoints,
        36,
      );
      for (var i = 0; i < 3; i++) {
        doc = WordDeserializer().readBytes(await OfficeIsolateSave.word(doc));
        final p = doc.paragraphs.single;
        expect(
          p.properties.importedParagraphMark!.asciiFont,
          'Liberation Mono',
        );
        expect(p.properties.importedParagraphMark!.fontSizePoints, 36);
        expect(p.text, 'Visible');
        expect(p.inlines.whereType<WmlRun>(), hasLength(1));
      }
    },
  );
}
