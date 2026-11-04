import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/opc/repair/xml_repair.dart';
import 'package:test/test.dart';

void main() {
  group('XmlRepair', () {
    test('closes leftover tags and drops extras', () {
      const String raw =
          '<w:document xmlns:w="http://example"><w:body><w:p></w:body></w:document>';
      final String fixed = XmlRepair.sanitize(raw);
      expect(fixed, contains('</w:p>'));
      expect(() {
        final XmlPullReader reader = XmlPullReader(fixed);
        while (reader.next()) {}
      }, returnsNormally);
    });

    test('escapes bare ampersands and strips NULs on decode', () {
      expect(XmlRepair.sanitize('<t>A & B</t>'), '<t>A &amp; B</t>');
      expect(XmlRepair.decode(<int>[0x3C, 0x00, 0x61, 0x3E]), '<a>');
    });
  });

  group('OfficeRepair', () {
    test('diagnoses empty and non-office buffers as fatal', () {
      final OfficeDiagnosis empty = OfficeRepair.diagnose(Uint8List(0));
      expect(empty.canOpen, isFalse);
      expect(empty.canRepair, isFalse);
      expect(empty.issues.first.code, OfficeIssueCode.emptyFile);

      final OfficeDiagnosis junk = OfficeRepair.diagnose(
        Uint8List.fromList(utf8.encode('this is not an office file')),
      );
      expect(
        junk.issues.any(
          (OfficeIssue i) => i.code == OfficeIssueCode.unknownFormat,
        ),
        isTrue,
      );
    });

    test('strips leading junk so a Word package opens', () {
      final Uint8List valid = WordSerializer()
          .write(WmlDocument.empty(text: 'Recovered'))
          .save();
      final Uint8List damaged = Uint8List.fromList(<int>[
        ...utf8.encode('EMAIL HEADER\r\n\r\n'),
        ...valid,
      ]);

      expect(() => OpcPackage.openBytes(damaged), throwsA(isA<ZipException>()));

      final OfficeDiagnosis diagnosis = OfficeRepair.diagnose(damaged);
      expect(
        diagnosis.issues.any(
          (OfficeIssue i) => i.code == OfficeIssueCode.leadingJunk,
        ),
        isTrue,
      );
      expect(diagnosis.canRepair, isTrue);

      final OfficeRepairResult result = OfficeRepair.repair(damaged);
      expect(result.succeeded, isTrue);
      expect(result.package!.kind, OpcPackageKind.word);
      expect(
        WordDeserializer().read(result.package!).plainText(),
        contains('Recovered'),
      );
      expect(OfficeRepair.open(damaged).kind, OpcPackageKind.word);
    });

    test('rebuilds a ZIP whose end-of-central-directory was truncated', () {
      final Uint8List valid = OpcPackage.create(OpcPackageKind.word).save();
      expect(valid.length > 40, isTrue);
      final Uint8List truncated = Uint8List.sublistView(
        valid,
        0,
        valid.length - 22,
      );

      expect(
        () => OpcPackage.openBytes(truncated),
        throwsA(isA<ZipException>()),
      );

      final OfficeDiagnosis diagnosis = OfficeRepair.diagnose(truncated);
      expect(
        diagnosis.issues.any(
          (OfficeIssue i) => i.code == OfficeIssueCode.missingZipDirectory,
        ),
        isTrue,
      );

      final OfficeRepairResult result = OfficeRepair.repair(truncated);
      expect(result.succeeded, isTrue);
      expect(result.package!.getPart('/word/document.xml'), isNotNull);
    });

    test('rebuilds [Content_Types].xml and package relationships', () {
      final ZipWriter writer = ZipWriter();
      writer.addFile(
        'word/document.xml',
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<w:document xmlns:w="${OfficeNamespaces.w}">'
          '<w:body><w:p><w:r><w:t>Solo</w:t></w:r></w:p></w:body></w:document>',
        ),
      );
      final Uint8List bytes = writer.close();

      final OfficeDiagnosis diagnosis = OfficeRepair.diagnose(bytes);
      expect(
        diagnosis.issues.map((OfficeIssue i) => i.code),
        containsAll(<OfficeIssueCode>[
          OfficeIssueCode.missingContentTypes,
          OfficeIssueCode.missingPackageRels,
        ]),
      );

      final OfficeRepairResult result = OfficeRepair.repair(bytes);
      expect(result.succeeded, isTrue);
      expect(result.package!.kind, OpcPackageKind.word);
      expect(
        result.package!.contentTypes.contentTypeFor('/word/document.xml'),
        OfficeContentTypes.wordMain,
      );
    });

    test('sanitizes broken document XML so the Word model can load', () {
      final OpcPackage package = OpcPackage.create(OpcPackageKind.word);
      package
          .getPart('/word/document.xml')!
          .writeText(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<w:document xmlns:w="${OfficeNamespaces.w}">'
            '<w:body><w:p><w:r><w:t>Broken</w:t></w:r></w:body></w:document>',
          );
      final Uint8List bytes = package.save();

      expect(
        () => WordDeserializer().read(OpcPackage.openBytes(bytes)),
        throwsA(isA<XmlParseException>()),
      );

      final OfficeDiagnosis diagnosis = OfficeRepair.diagnose(bytes);
      expect(
        diagnosis.issues.any(
          (OfficeIssue i) => i.code == OfficeIssueCode.brokenXml,
        ),
        isTrue,
      );

      final OfficeRepairResult result = OfficeRepair.repair(bytes);
      expect(result.succeeded, isTrue);
      expect(
        WordDeserializer().read(result.package!).plainText(),
        contains('Broken'),
      );
    });

    test('removes NUL bytes inside XML parts', () {
      final List<int> xml = utf8.encode(
        '<?xml version="1.0"?>'
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p/></w:body></w:document>',
      );
      xml[10] = 0;
      final ZipWriter writer = ZipWriter();
      writer.addFile(
        '[Content_Types].xml',
        utf8.encode(
          '<?xml version="1.0"?>'
          '<Types xmlns="${OfficeNamespaces.contentTypes}">'
          '<Default Extension="rels" ContentType="${OfficeContentTypes.relationships}"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="${OfficeContentTypes.wordMain}"/>'
          '</Types>',
        ),
      );
      writer.addFile(
        '_rels/.rels',
        utf8.encode(
          '<?xml version="1.0"?>'
          '<Relationships xmlns="${OfficeNamespaces.relationships}">'
          '<Relationship Id="rId1" Type="${RelationshipTypes.officeDocument}" '
          'Target="word/document.xml"/>'
          '</Relationships>',
        ),
      );
      writer.addFile('word/document.xml', Uint8List.fromList(xml));
      final Uint8List bytes = writer.close();

      final OfficeDiagnosis diagnosis = OfficeRepair.diagnose(bytes);
      expect(
        diagnosis.issues.any(
          (OfficeIssue i) => i.code == OfficeIssueCode.illegalXmlCharacters,
        ),
        isTrue,
      );
      final OfficeRepairResult result = OfficeRepair.repair(bytes);
      expect(result.succeeded, isTrue);
      expect(
        result.package!.getPart('/word/document.xml')!.readBytes().contains(0),
        isFalse,
      );
    });

    test('recreates a missing worksheet referenced by the workbook', () {
      final OpcPackage package = OpcPackage.create(OpcPackageKind.sheet);
      expect(package.deletePart('/xl/worksheets/sheet1.xml'), isTrue);
      final Uint8List bytes = package.save();

      final OfficeDiagnosis diagnosis = OfficeRepair.diagnose(bytes);
      expect(
        diagnosis.issues.any(
          (OfficeIssue i) => i.code == OfficeIssueCode.missingWorksheet,
        ),
        isTrue,
      );

      final OfficeRepairResult result = OfficeRepair.repair(bytes);
      expect(result.succeeded, isTrue);
      expect(result.package!.getPart('/xl/worksheets/sheet1.xml'), isNotNull);
    });

    test('encrypted files stay fatal without a password', () {
      final Uint8List clear = OpcPackage.create(OpcPackageKind.word).save();
      final Uint8List locked = OfficeCrypto.encrypt(clear, 'secret');

      final OfficeDiagnosis diagnosis = OfficeRepair.diagnose(locked);
      expect(diagnosis.encrypted, isTrue);
      expect(diagnosis.canRepair, isFalse);
      expect(
        diagnosis.issues.any(
          (OfficeIssue i) => i.code == OfficeIssueCode.passwordRequired,
        ),
        isTrue,
      );

      final OfficeRepairResult unlocked = OfficeRepair.repair(
        locked,
        password: 'secret',
      );
      expect(unlocked.succeeded, isTrue);
      expect(unlocked.package!.kind, OpcPackageKind.word);
    });
  });
}

extension on WmlDocument {
  String plainText() {
    final StringBuffer buffer = StringBuffer();
    for (final WmlSection section in sections) {
      for (final WmlBlock block in section.blocks) {
        if (block is WmlParagraph) {
          for (final WmlInline inline in block.inlines) {
            if (inline is WmlRun) {
              buffer.write(inline.text);
            }
          }
        }
      }
    }
    return buffer.toString();
  }
}
