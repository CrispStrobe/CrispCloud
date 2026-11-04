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

  test('PPTX is laid out as a PDF', () async {
    final deck = (PptxDeckBuilder()
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
