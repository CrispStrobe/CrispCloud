import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('quoted separators and multiline cells are retained', () {
    final sheet = SmlWorkbook().sheets.single;
    SmlPowerQuery.fromCsv(
      sheet,
      'name,note\r\n"A,B","line 1\r\nline ""2"""\r\n',
      detectNumbers: false,
    );
    expect(sheet.cell(const SmlCellRef(0, 1)).value, 'A,B');
    expect(sheet.cell(const SmlCellRef(1, 1)).value, 'line 1\r\nline "2"');
  });
  test('text mode preserves identifiers and literal formulas through XLSX', () {
    final book = SmlWorkbook();
    SmlPowerQuery.fromCsv(
      book.sheets.single,
      '00123,=1+1,9007199254740993',
      detectNumbers: false,
    );
    final copy = SheetDeserializer().readBytes(
      SheetSerializer().writeBytes(book),
    );
    expect(copy.sheets.single.cell(const SmlCellRef(0, 0)).value, '00123');
    expect(copy.sheets.single.cell(const SmlCellRef(1, 0)).formula, isNull);
    expect(copy.sheets.single.cell(const SmlCellRef(1, 0)).value, '=1+1');
    expect(
      copy.sheets.single.cell(const SmlCellRef(2, 0)).value,
      '9007199254740993',
    );
  });
  test('TSV keeps numeric conversion available', () {
    final sheet = SmlWorkbook().sheets.single;
    SmlPowerQuery.fromCsv(sheet, 'id\tamount\n2\t3.5', delimiter: '\t');
    expect(sheet.cell(const SmlCellRef(1, 1)).type, SmlCellType.number);
    expect(sheet.cell(const SmlCellRef(1, 1)).value, 3.5);
  });
  test('blank spreadsheet rows do not change report defaults', () {
    expect(ReportCsv.parse('A\n\nB\n'), [
      ['A'],
      ['B'],
    ]);
    expect(ReportCsv.parse('A\n\nB\n', keepEmptyRows: true), [
      ['A'],
      [''],
      ['B'],
    ]);
    final sheet = SmlWorkbook().sheets.single;
    SmlPowerQuery.fromCsv(sheet, 'A\n\nB\n');
    expect(sheet.cell(const SmlCellRef(0, 2)).value, 'B');
  });
  test('malformed input cannot partially modify a worksheet', () {
    final sheet = SmlWorkbook().sheets.single;
    sheet.cell(const SmlCellRef(0, 0)).value = 'existing';
    expect(
      () => SmlPowerQuery.fromCsv(sheet, 'a,b\n"unterminated'),
      throwsA(isA<ReportDataException>()),
    );
    expect(sheet.cell(const SmlCellRef(0, 0)).value, 'existing');
  });
  test(
    'a final quoted empty record is retained without adding a phantom row',
    () {
      expect(ReportCsv.parse('""', keepEmptyRows: true), [
        [''],
      ]);
      expect(ReportCsv.parse('a\n""', keepEmptyRows: true), [
        ['a'],
        [''],
      ]);
      expect(ReportCsv.parse('a\n', keepEmptyRows: true), [
        ['a'],
      ]);
      expect(ReportCsv.parse('', keepEmptyRows: true), isEmpty);
    },
  );
  test('parsed rows honor the starting cell', () {
    final sheet = SmlWorkbook().sheets.single;
    SmlPowerQuery.fromRows(
      sheet,
      [
        ['01', 'two'],
      ],
      origin: const SmlCellRef(2, 4),
      detectNumbers: false,
    );
    expect(sheet.cell(const SmlCellRef(2, 4)).value, '01');
    expect(sheet.cell(const SmlCellRef(3, 4)).value, 'two');
  });
}
