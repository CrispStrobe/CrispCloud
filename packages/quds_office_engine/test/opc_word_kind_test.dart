import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  for (final entry in {
    'DOCX': OfficeContentTypes.wordMain,
    'DOTX': OfficeContentTypes.wordTemplate,
    'DOCM': 'application/vnd.ms-word.document.macroEnabled.main+xml',
    'DOTM': 'application/vnd.ms-word.template.macroEnabledTemplate.main+xml',
  }.entries) {
    test('${entry.key} recognizes the exact relocated mixed-case main part', () {
      var package = OpcPackage.empty();
      const mainPart = '/office/text/Main.xml';
      package.createPart(
        mainPart,
        entry.value,
        utf8.encode('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body><w:p><w:r><w:t>Relocated ${entry.key} body</w:t></w:r></w:p></w:body>
</w:document>'''),
      );
      // A differently cased key is a different OPC part. It must not determine
      // the format of the relationship's actual target.
      package.createPart(
        mainPart.toLowerCase(),
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
        utf8.encode('<decoy/>'),
      );
      package.packageRelationships.add(
        type: RelationshipTypes.officeDocument,
        target: mainPart.substring(1),
      );

      for (var cycle = 0; cycle < 3; cycle++) {
        package = OpcPackage.openBytes(package.save());
        expect(package.kind, OpcPackageKind.word);
        expect(package.contentTypes.contentTypeFor(mainPart), entry.value);
        expect(
          WordDeserializer().read(package).paragraphs.single.text,
          'Relocated ${entry.key} body',
        );
      }
    });
  }

  test('an unrelated relocated content type stays unknown', () {
    final package = OpcPackage.empty();
    package.createPart(
      '/office/Main.xml',
      'application/vnd.example.document+xml',
      utf8.encode('<example/>'),
    );
    package.packageRelationships.add(
      type: RelationshipTypes.officeDocument,
      target: 'office/Main.xml',
    );
    expect(OpcPackage.openBytes(package.save()).kind, OpcPackageKind.unknown);
  });
}
