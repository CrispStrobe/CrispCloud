import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// Word wraps footer page numbers in a docPartObj gallery control. Such
/// presentation-only wrappers must not make the document unopenable, while
/// data-carrying header/footer controls still fail closed.
void main() {
  const String ns = OfficeNamespaces.w;
  const String rns = OfficeNamespaces.r;

  OpcPackage packageWithFooter(String sdtPr) {
    final OpcPackage package = OpcPackage.create(OpcPackageKind.word);
    package
        .getPart('/word/document.xml')!
        .writeText(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document xmlns:w="$ns" xmlns:r="$rns"><w:body>'
          '<w:p><w:r><w:t>Body</w:t></w:r></w:p>'
          '<w:sectPr><w:footerReference w:type="default" r:id="rIdFtr"/>'
          '</w:sectPr></w:body></w:document>',
        );
    package.createPart(
      '/word/footer1.xml',
      OfficeContentTypes.wordFooter,
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:ftr xmlns:w="$ns"><w:sdt>$sdtPr<w:sdtContent>'
        '<w:p><w:r><w:t>Page 1</w:t></w:r></w:p>'
        '</w:sdtContent></w:sdt></w:ftr>',
      ),
    );
    package
        .relationshipsFor('/word/document.xml')
        .add(
          type: RelationshipTypes.footer,
          target: 'footer1.xml',
          id: 'rIdFtr',
        );
    return package;
  }

  test('a docPartObj page-number footer opens with its text', () {
    final WmlDocument doc = WordDeserializer().read(
      packageWithFooter(
        '<w:sdtPr><w:id w:val="12"/><w:docPartObj>'
        '<w:docPartGallery w:val="Page Numbers (Bottom of Page)"/>'
        '<w:docPartUnique/></w:docPartObj></w:sdtPr>',
      ),
    );
    final String footerText = doc.sections.first.footer
        .map((WmlParagraph p) => p.text)
        .join();
    expect(footerText, contains('Page 1'));
  });

  test('a bare footer wrapper without properties opens', () {
    expect(
      () => WordDeserializer().read(packageWithFooter('')),
      returnsNormally,
    );
  });

  test('a data-carrying footer content control still fails closed', () {
    expect(
      () => WordDeserializer().read(
        packageWithFooter(
          '<w:sdtPr><w:id w:val="9"/><w:tag w:val="client"/></w:sdtPr>',
        ),
      ),
      throwsUnsupportedError,
    );
  });
}
