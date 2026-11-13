// test/office_pdf_service_test.dart
//
// Verifies the pure-Dart Office→PDF layout used by the viewer's Pages view.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'package:crisp_cloud/services/office_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Pages embeds requested existing families and reports uncovered text',
    () async {
      final package = OpcPackage.empty();
      package.createPart(
        '/word/document.xml',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml',
        utf8.encode('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
 <w:body><w:p>
  <w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/><w:b/></w:rPr><w:t>Arial bold </w:t></w:r>
  <w:r><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/><w:i/></w:rPr><w:t>Times italic </w:t></w:r>
  <w:r><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:b/><w:i/></w:rPr><w:t>Calibri both </w:t></w:r>
  <w:r><w:rPr><w:rFonts w:ascii="Missing Test Font" w:hAnsi="Missing Test Font"/></w:rPr><w:t>Ω Ж א عربي 中</w:t></w:r>
 </w:p></w:body>
</w:document>
'''),
      );
      package.packageRelationships.add(
        type: RelationshipTypes.officeDocument,
        target: 'word/document.xml',
      );
      final result = await convertOfficeToPdfResult(package.save());
      final pdf = latin1.decode(result.bytes);
      for (final family in [
        'LiberationSans',
        'LiberationSerif',
        'Carlito',
        'NotoNaskhArabic',
      ]) {
        expect(pdf, contains('/BaseFont /$family'));
      }
      expect(result.fonts.missingCodePoints, contains(0x4e2d));
      expect(result.fonts.missingCodePoints, isNot(contains(0x0639)));
      expect(
        result.fonts.substitutions.any(
          (value) =>
              value.requestedFamily == 'Calibri' &&
              value.resolvedFamily == 'Carlito',
        ),
        isTrue,
      );
      expect(
        result.fonts.substitutions.any(
          (value) => value.requestedFamily == 'Missing Test Font',
        ),
        isTrue,
      );
      expect(result.fonts.diagnosticsTruncated, isFalse);
      final text = ArabicShaper.foldPresentation(
        PdfExtract.pageText(PdfFile.open(result.bytes), 0),
      );
      for (final cp in 'ΩЖאعربي'.runes) {
        expect(
          text.runes,
          contains(cp),
          reason: 'Text layer U+${cp.toRadixString(16)}',
        );
      }
    },
  );

  test('PPTX is laid out as a PDF', () async {
    final deck =
        (PptxDeckBuilder()
              ..addCoverSlide(title: 'Conversion Test', subtitle: 'Subtitle')
              ..addTitleBodySlide(
                title: 'Second slide',
                bullets: <String>['Revenue up 20%'],
              ))
            .build();

    final pdf = await convertOfficeToPdf(deck);

    expect(pdf.length, greaterThan(1000));
    expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
  });

  for (final entry in {
    'DOCM': 'application/vnd.ms-word.document.macroEnabled.main+xml',
    'DOTM': 'application/vnd.ms-word.template.macroEnabledTemplate.main+xml',
  }.entries) {
    test(
      '${entry.key} with a relocated main part is laid out as a PDF',
      () async {
        final package = OpcPackage.empty();
        package.createPart(
          '/office/text/Main.xml',
          entry.value,
          utf8.encode('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p><w:r><w:t>Relocated macro-enabled Word body</w:t></w:r></w:p></w:body>
</w:document>
'''),
        );
        package.packageRelationships.add(
          type: RelationshipTypes.officeDocument,
          target: 'office/text/Main.xml',
        );
        final bytes = package.save();

        expect(OpcPackage.openBytes(bytes).kind, OpcPackageKind.word);
        final pdf = await convertOfficeToPdf(bytes);

        expect(pdf.length, greaterThan(1000));
        expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
      },
    );
  }

  test('invalid Office input is rejected with a typed error', () async {
    await expectLater(
      convertOfficeToPdf(Uint8List.fromList(<int>[1, 2, 3, 4])),
      throwsA(isA<OfficePdfException>()),
    );
  });

  test('oversized input is rejected before layout', () async {
    final oversized = Uint8List(kOfficePdfInputCap + 1);
    await expectLater(
      convertOfficeToPdf(oversized),
      throwsA(isA<OfficePdfException>()),
    );
  });
}
