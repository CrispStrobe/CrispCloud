import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _instruction =
    ' ADDIN ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY ';
const _preferences =
    '{"dataVersion":4,"prefs":{"fieldType":"Field","noteType":0}}';

List<WmlParagraph> _bibliography() => WordZotero.nativeBibliographyParagraphs(
  instruction: _instruction,
  text: 'First source.\nSecond source.',
  formattedText: ZoteroFormattedText.fromHtml(
    '<div><i>First source.</i></div><div>Second source.</div>',
  ),
);

WmlDocument _fresh() => WmlDocument(
  // The public constructor accepts this paragraph-list subtype. Transfer must
  // keep it usable rather than relying on a widened List<WmlBlock> fixture.
  sections: [WmlSection(blocks: _bibliography())],
  zoteroDocumentData: _preferences,
);

List<XmlElement> _styles(OpcPackage package) => XmlDocument.parse(
  package.getPart('/word/styles.xml')!.readText(),
).root!.childrenNamed('style', namespaceUri: OfficeNamespaces.w).toList();

XmlElement _body(OpcPackage package) => XmlDocument.parse(
  package.getPart('/word/document.xml')!.readText(),
).root!.firstChild('body', namespaceUri: OfficeNamespaces.w)!;

void _export(WmlDocument document) => WordZoteroTransfer.prepareExport(
  document,
  instructions: 'Open this document and refresh Zotero.',
  documentData: _preferences,
).apply();

void main() {
  for (final transfer in [false, true]) {
    test(
      'fresh bibliography has one defined style after repeated ${transfer ? 'transfer' : 'active'} saves',
      () {
        var document = _fresh();
        if (transfer) _export(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          final saved = WordSerializer().write(document);
          final bibliography = _styles(saved)
              .where((style) => style.getAttribute('styleId') == 'Bibliography')
              .single;
          expect(bibliography.getAttribute('type'), 'paragraph');
          expect(
            bibliography.firstChild('name')!.getAttribute('val'),
            'Bibliography',
          );
          document = WordDeserializer().readBytes(saved.save());
          expect(
            document.styles.where((style) => style.id == 'Bibliography'),
            hasLength(1),
          );
          if (transfer) {
            expect(WordZoteroTransfer.isTransferDocument(document), isTrue);
            expect(
              document.paragraphs
                  .singleWhere((p) => p.properties.styleId == 'Bibliography')
                  .text,
              'BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY',
            );
          } else {
            final field = WordZotero.fields(document).single;
            expect(field.kind, ZoteroFieldKind.bibliography);
            expect(field.paragraphs, hasLength(2));
          }
        }
      },
    );
  }

  test(
    'adding a bibliography to a styleless import defines only its referenced style',
    () {
      final source = OpcPackage.create(OpcPackageKind.word);
      source
          .getPart('/word/document.xml')!
          .writeText(
            '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>'
            '<w:p><w:r><w:t>Untouched native paragraph</w:t></w:r></w:p>'
            '</w:body></w:document>',
          );
      var document = WordDeserializer().read(source);
      document.sections.single.blocks.addAll(_bibliography());
      for (var cycle = 0; cycle < 3; cycle++) {
        final saved = WordSerializer().write(document);
        expect(_styles(saved).map((style) => style.getAttribute('styleId')), [
          'Bibliography',
        ]);
        final untouched = _body(saved).childrenNamed('p').first;
        expect(
          untouched.firstChild('pPr')?.childElements ?? <XmlElement>[],
          isEmpty,
        );
        expect(
          untouched.firstChild('r')!.firstChild('rPr')?.childElements ??
              <XmlElement>[],
          isEmpty,
        );
        document = WordDeserializer().readBytes(saved.save());
        expect(document.paragraphs.first.properties.spacingAfter, 0);
        expect(document.paragraphs.first.properties.lineSpacing, 1);
      }
    },
  );

  for (final transfer in [false, true]) {
    test(
      'an imported custom Bibliography definition is unchanged during ${transfer ? 'transfer' : 'active'} saves',
      () {
        final package = WordSerializer().write(_fresh());
        package
            .getPart('/word/styles.xml')!
            .writeText(
              '<n:styles xmlns:n="${OfficeNamespaces.w}" xmlns:x="urn:author-style">'
              '<n:style n:type="paragraph" n:styleId="Bibliography" x:owned="yes">'
              '<n:name n:val="User references"/><n:aliases n:val="Works cited"/>'
              '<n:pPr><n:keepNext/><n:spacing n:after="240"/></n:pPr>'
              '<n:rPr><n:rFonts n:ascii="Times New Roman" n:hAnsi="Times New Roman"/>'
              '<n:color n:val="123456"/><n:sz n:val="28"/><x:extension x:value="keep"/>'
              '</n:rPr></n:style></n:styles>',
            );
        final original = XmlDocument(
          root: _styles(package).single.copy(),
        ).toXmlString(declaration: false);
        var document = WordDeserializer().read(package);
        if (transfer) _export(document);
        for (var cycle = 0; cycle < 3; cycle++) {
          final saved = WordSerializer().write(document);
          expect(
            XmlDocument(
              root: _styles(saved).single.copy(),
            ).toXmlString(declaration: false),
            original,
          );
          document = WordDeserializer().readBytes(saved.save());
          final style = document.styles.single;
          expect(style.id, 'Bibliography');
          expect(style.name, 'User references');
          expect(style.font, 'Times New Roman');
          expect(style.fontSizePoints, 14);
          expect(style.color, '123456');
        }
      },
    );
  }

  test('an authored Bibliography style takes precedence over the built-in', () {
    final document = _fresh();
    document.styles.add(
      const WmlStyle(
        id: 'Bibliography',
        name: 'Our references',
        nameAr: 'مراجعنا',
        fontSizePoints: 15,
        color: '445566',
      ),
    );
    final saved = WordSerializer().write(document);
    final style = _styles(saved).single;
    expect(style.getAttribute('styleId'), 'Bibliography');
    expect(style.firstChild('name')!.getAttribute('val'), 'Our references');
    expect(
      style.firstChild('rPr')!.firstChild('color')!.getAttribute('val'),
      '445566',
    );
    expect(
      style.firstChild('rPr')!.firstChild('sz')!.getAttribute('val'),
      '30',
    );
  });
}
