import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/editor_pdf/pdf_font_faces.dart';
import 'package:quds_office_engine/pdf_file.dart';

void main() {
  test(
    'al_tahreer cover display list has translucent map and host title face',
    () {
      final File pdf = File('/home/mohammed/Desktop/al_tahreer_profile.pdf');
      if (!pdf.existsSync()) {
        return;
      }
      final PdfDisplayList list = PdfFile.open(
        pdf.readAsBytesSync(),
      ).displayLists().first;
      final PdfDrawImage map = list.ops.whereType<PdfDrawImage>().firstWhere(
        (PdfDrawImage o) => o.hasAlpha && o.pixelWidth > 1000,
      );
      var maxA = 0;
      for (int i = 3; i < map.bytes.length; i += 4) {
        if (map.bytes[i] > maxA) {
          maxA = map.bytes[i];
        }
      }
      expect(maxA, lessThan(120), reason: 'group /ca must scale map alpha');
      final String title = list.ops
          .whereType<PdfDrawText>()
          .map((PdfDrawText t) => t.text)
          .join();
      expect(title, contains('TAHREER'));
      final PdfDrawText first = list.ops.whereType<PdfDrawText>().first;
      expect(first.fontBytes, isNotNull);
      expect(first.fontBytes!.length, lessThan(48000));
      expect(PdfFontFaces.hostFamily(first.fontFamily), 'Liberation Sans');
      // Embedded face is preferred once FontLoader finishes; until then host.
      expect(
        PdfFontFaces.familyFor(first.fontBytes, first.fontFamily),
        anyOf('Liberation Sans', startsWith('PdfFace-')),
      );
    },
  );
}
