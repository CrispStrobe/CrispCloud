import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OpcPackage _source({bool withStyle = false}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
<w:p><w:r><w:t>Heading candidate</w:t></w:r></w:p>
<w:p><w:r><w:t>Untouched native paragraph</w:t></w:r></w:p>
<w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:t>Explicit native paragraph</w:t></w:r></w:p>
</w:body></w:document>''');
  if (withStyle) {
    package
        .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
        .writeText('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
<w:style w:type="paragraph" w:styleId="Unrelated">
<w:name w:val="An unrelated style"/>
<w:pPr><w:spacing w:after="500" w:line="480"/></w:pPr>
</w:style></w:styles>''');
    package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.styles, target: 'styles.xml');
  }
  return package;
}

void _expectNativeDefaults(WmlDocument document) {
  for (final paragraph in document.paragraphs.skip(1)) {
    expect(paragraph.properties.spacingAfter, 0, reason: paragraph.text);
    expect(paragraph.properties.lineSpacing, 1, reason: paragraph.text);
  }
}

void main() {
  test('new TOC link appearance survives its first export', () {
    var document = WordDeserializer().read(_source());
    WordToc.applyHeading(document.paragraphs.first, 1);
    final toc = WmlToc();
    document.sections.first.blocks.add(toc);
    WordToc.refresh(toc, document);
    for (var cycle = 0; cycle < 4; cycle++) {
      final current = document.sections.first.blocks.whereType<WmlToc>().single;
      final run = current.itemParagraphs.single.inlines
          .whereType<WmlRun>()
          .single;
      expect(run.properties.underline, WmlUnderline.single);
      expect(run.properties.color, '2E75B6');
      expect(run.hyperlink?.anchor, isNotEmpty);
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
  });

  for (final withStyle in [false, true]) {
    test(
      'unrelated style catalog $withStyle retains native paragraph defaults',
      () async {
        var document = WordDeserializer().read(_source(withStyle: withStyle));
        _expectNativeDefaults(document);
        WordStyles.apply(
          document.paragraphs.first,
          'Heading1',
          document: document,
        );
        final before = WordLayoutEngine(font: null).layout(document);
        final ys = before.pages.single.lines.map((line) => line.y).toList();
        for (var cycle = 0; cycle < 3; cycle++) {
          final package = OpcPackage.openBytes(
            await OfficeIsolateSave.word(document),
          );
          final body = XmlDocument.parse(
            package.getPart('/word/document.xml')!.readText(),
          ).root!.firstChild('body')!;
          final untouched = body.childrenNamed('p').elementAt(1);
          expect(untouched.firstChild('pPr')?.childElements ?? [], isEmpty);
          document = WordDeserializer().read(package);
          _expectNativeDefaults(document);
          expect(
            WordLayoutEngine(font: null)
                .layout(document)
                .pages
                .single
                .lines
                .map((line) => line.y)
                .toList(),
            ys,
          );
        }
      },
    );
  }

  test('declared defaults still cascade and explicit zero overrides them', () {
    final package = _source(withStyle: true);
    package.getPart('/word/styles.xml')!.writeText('''
<w:styles xmlns:w="${OfficeNamespaces.w}"><w:docDefaults>
<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>
</w:docDefaults></w:styles>''');
    var document = WordDeserializer().read(package);
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(document.paragraphs.elementAt(1).properties.spacingAfter, 8);
      expect(document.paragraphs.elementAt(1).properties.lineSpacing, 1.15);
      expect(document.paragraphs.elementAt(2).properties.spacingAfter, 0);
      expect(document.paragraphs.elementAt(2).properties.lineSpacing, 1);
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
  });
}
