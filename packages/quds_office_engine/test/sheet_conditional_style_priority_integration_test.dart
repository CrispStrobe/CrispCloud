import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'differential colors and native priority survive the same edited rule',
    () async {
      var book = SmlWorkbook(sheets: [SmlWorksheet(name: 'Rules', sheetId: 1)]);
      book.firstSheet.conditionalFormats.add(
        SmlConditionalRule(
          range: SmlRange.parse('A1:A5'),
          kind: SmlConditionalKind.top,
          rank: 3,
          priority: 7,
          stopIfTrue: true,
          fillRgb: '00FF00',
          fontRgb: '0000FF',
        ),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.workbook(
          book,
          recalculate: false,
        );
        book = SheetDeserializer().readBytes(bytes);
        final rule = book.firstSheet.conditionalFormats.single;
        expect(rule.fillRgb, '00FF00');
        expect(rule.fontRgb, '0000FF');
        expect(rule.priority, 7);
        expect(rule.stopIfTrue, isTrue);
        expect(rule.rank, cycle == 0 ? 3 : 2);
        expect(rule.dxfId, isNotNull);
        rule.rank = 2;
      }
    },
  );
}
