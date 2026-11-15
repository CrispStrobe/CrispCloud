import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

void main() {
  test(
    'legacy HTML spreadsheet caption and header emphasis survive OOXML copy',
    () async {
      final imported = LegacySheetReader.readBytes(
        Uint8List.fromList(
          utf8.encode(
            '<html><body><table><caption>Quarterly &amp; annual</caption>'
            '<tr><th>Period</th><th>Amount</th></tr>'
            '<tr><td>Q1</td><td x:num="42">42</td></tr></table></body></html>',
          ),
        ),
      );
      final bytes = await OfficeIsolateSave.workbook(
        imported,
        recalculate: false,
      );
      final sheet = SheetDeserializer().readBytes(bytes).sheets.single;
      expect(sheet.cellA1('A1').asString, 'Quarterly & annual');
      expect(
        sheet.merges.any((m) => m.r0 == 0 && m.c0 == 0 && m.c1 == 1),
        isTrue,
      );
      expect(sheet.cellA1('A2').asString, 'Period');
      expect(sheet.cellA1('B2').fontBold, isTrue);
      expect(sheet.cellA1('B3').value, 42);
    },
  );
}
