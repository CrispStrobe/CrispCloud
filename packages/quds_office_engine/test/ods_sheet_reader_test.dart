import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

/// Synthetic LibreOffice-generated ODS (values, formulas, styles, merge).
void main() {
  final bytes = File(
    'test/fixtures/fidelity/legacy-sheet.ods',
  ).readAsBytesSync();

  test('reads ODS values, formulas, styles and merges', () {
    final book = OdsSheetReader.readBytes(bytes);
    expect(book.sheets.map((sheet) => sheet.name), ['Data', 'Notes']);
    final data = book.sheets.first;

    expect(data.cellA1('A1').asString, 'Item');
    expect(data.cellA1('A1').fontBold, isTrue);
    expect(data.cellA1('A1').fontSize, 12);
    expect(data.cellA1('A1').fillRgb, '4472C4');
    expect(data.cellA1('A1').fontRgb, 'FFFFFF');

    expect(data.cellA1('B2').value, 2);
    expect(data.cellA1('C2').value, 3.5);
    final total = data.cellA1('D2');
    expect(total.formula, 'B2*C2');
    expect(total.value, 7);
    expect(total.type, SmlCellType.formula);
    expect(data.cellA1('D6').formula, 'SUM(D2:D4)');

    expect(data.merges.single.origin.a1, 'A8');
    expect(data.merges.single.c1, 1);
    expect(data.exportColumnWidth(0), greaterThan(data.exportColumnWidth(1)));
    expect(data.allCells.length, lessThan(100));
  });

  test('an imported ODS saves as a readable .xlsx', () async {
    final book = OdsSheetReader.readBytes(bytes);
    final saved = await OfficeIsolateSave.workbook(book, recalculate: false);
    final reopened = SheetDeserializer().readBytes(saved);
    expect(reopened.sheets.map((sheet) => sheet.name), ['Data', 'Notes']);
    expect(reopened.sheets.first.cellA1('A1').asString, 'Item');
    expect(reopened.sheets.first.cellA1('D2').formula, 'B2*C2');
    expect(reopened.sheets.first.cellA1('D2').value, 7);
    expect(reopened.sheets.first.cellA1('B2').value, 2);
    expect(reopened.sheets.first.merges, hasLength(1));
  });

  test(
    'keeps internal repeated blank rows without expanding trailing padding',
    () async {
      final book = OdsSheetReader.readBytes(
        _ods(
          '''
      <table:table-row>
        <table:table-cell office:value-type="string"><text:p>Start</text:p></table:table-cell>
      </table:table-row>
      <table:table-row table:number-rows-repeated="2" table:style-name="tall">
        <table:table-cell table:number-columns-repeated="4096"/>
      </table:table-row>
      <table:table-row>
        <table:table-cell office:value-type="float" office:value="7"/>
        <table:table-cell office:value-type="float" office:value="14" table:formula="of:=[.A4]*2"/>
      </table:table-row>
      <table:table-row table:number-rows-repeated="1048572" table:style-name="tall">
        <table:table-cell table:number-columns-repeated="16384"/>
      </table:table-row>
      ''',
          styles: '''
      <style:style style:name="tall" style:family="table-row">
        <style:table-row-properties style:row-height="24pt"/>
      </style:style>
      ''',
        ),
      );
      for (final current in [book, await _roundTrip(book)]) {
        final sheet = current.sheets.single;
        expect(sheet.cellOrNull(SmlCellRef.parse('A4'))?.value, 7);
        expect(sheet.cellOrNull(SmlCellRef.parse('B4'))?.formula, 'A4*2');
        expect(sheet.cellOrNull(SmlCellRef.parse('B4'))?.value, 14);
        expect(sheet.cellOrNull(SmlCellRef.parse('A2')), isNull);
        expect(sheet.cellOrNull(SmlCellRef.parse('A3')), isNull);
        expect(sheet.allCells, hasLength(3));
        expect(sheet.rowHeights[1], SmlWorksheet.rowHeightFromExcel(24));
        expect(sheet.rowHeights[2], SmlWorksheet.rowHeightFromExcel(24));
        expect(sheet.rowHeights, hasLength(2));
      }
    },
  );

  test('blank runs retain the row limit without materializing empty cells', () {
    final book = OdsSheetReader.readBytes(
      _ods('''
      <table:table-row table:number-rows-repeated="99999"><table:table-cell/></table:table-row>
      <table:table-row><table:table-cell office:value-type="float" office:value="7"/></table:table-row>
      <table:table-row><table:table-cell office:value-type="float" office:value="9"/></table:table-row>
      '''),
    );
    final sheet = book.sheets.single;
    expect(sheet.cellOrNull(const SmlCellRef(0, 99999))?.value, 7);
    expect(sheet.cellOrNull(const SmlCellRef(0, 100000)), isNull);
    expect(sheet.allCells, hasLength(1));
    expect(sheet.rows, hasLength(1));
  });

  for (final merge in [
    (
      name: 'explicit placeholder',
      span: 2,
      covered: '<table:covered-table-cell/>',
      nextColumn: 2,
    ),
    (name: 'omitted placeholder', span: 2, covered: '', nextColumn: 2),
    (
      name: 'repeated placeholders',
      span: 3,
      covered: '<table:covered-table-cell table:number-columns-repeated="2"/>',
      nextColumn: 3,
    ),
    (
      name: 'additional covered column',
      span: 2,
      covered: '<table:covered-table-cell table:number-columns-repeated="2"/>',
      nextColumn: 3,
    ),
  ]) {
    test('horizontal merge consumes ${merge.name} once', () async {
      final book = OdsSheetReader.readBytes(
        _ods('''
        <table:table-row>
          <table:table-cell office:value-type="string" table:number-columns-spanned="${merge.span}"><text:p>Wide</text:p></table:table-cell>
          ${merge.covered}
          <table:table-cell office:value-type="float" office:value="7"/>
        </table:table-row>
        '''),
      );
      for (final current in [book, await _roundTrip(book)]) {
        final sheet = current.sheets.single;
        expect(sheet.cellOrNull(SmlCellRef(merge.nextColumn, 0))?.value, 7);
        expect(sheet.cellOrNull(SmlCellRef(merge.nextColumn + 1, 0)), isNull);
        expect(sheet.merges.single.c0, 0);
        expect(sheet.merges.single.c1, merge.span - 1);
        expect(sheet.allCells, hasLength(2));
      }
    });
  }

  test('a new origin clears unconsumed merge placeholders', () async {
    final book = OdsSheetReader.readBytes(
      _ods('''
      <table:table-row>
        <table:table-cell office:value-type="string" table:number-columns-spanned="2"><text:p>First</text:p></table:table-cell>
        <table:table-cell office:value-type="string" table:number-columns-spanned="2"><text:p>Second</text:p></table:table-cell>
        <table:covered-table-cell/>
        <table:table-cell office:value-type="float" office:value="7"/>
      </table:table-row>
      '''),
    );
    for (final current in [book, await _roundTrip(book)]) {
      final sheet = current.sheets.single;
      expect(sheet.cellOrNull(SmlCellRef.parse('C1'))?.asString, 'Second');
      expect(sheet.cellOrNull(SmlCellRef.parse('E1'))?.value, 7);
      expect(sheet.allCells, hasLength(3));
      expect(sheet.merges.map((merge) => merge.origin.a1), ['A1', 'C1']);
    }
  });

  test('merge spans and repeated covered cells respect the column limit', () {
    final book = OdsSheetReader.readBytes(
      _ods('''
      <table:table-row>
        <table:table-cell table:number-columns-repeated="4094"/>
        <table:table-cell office:value-type="string" table:number-columns-spanned="4096"><text:p>Edge</text:p></table:table-cell>
        <table:covered-table-cell table:number-columns-repeated="4096"/>
        <table:table-cell office:value-type="float" office:value="7"/>
      </table:table-row>
      '''),
    );
    final sheet = book.sheets.single;
    expect(sheet.merges.single.c0, 4094);
    expect(sheet.merges.single.c1, 4095);
    expect(sheet.allCells, hasLength(1));
  });

  for (final formula in {
    'of:="a;b"': '"a;b"',
    'of:="literal [.A1];COM.MICROSOFT.SUM"':
        '"literal [.A1];COM.MICROSOFT.SUM"',
    'of:=IF([.A1]="a;b";"say ""[.B2];""";COM.MICROSOFT.SUM([.A1:.A2];1))':
        'IF(A1="a;b","say ""[.B2];""",SUM(A1:A2,1))',
    'of:=CONCATENATE("";"a;b";"[.A1]")': 'CONCATENATE("","a;b","[.A1]")',
    "of:=SUM(['Semi;Colon'.A1];1)": "SUM('Semi;Colon'!A1,1)",
    "of:=SUM(['COM.MICROSOFT.Data'.A1];1)": "SUM('COM.MICROSOFT.Data'!A1,1)",
  }.entries) {
    test('formula translation preserves literals in ${formula.key}', () async {
      final book = OdsSheetReader.readBytes(
        _ods('''
        <table:table-row>
          <table:table-cell office:value-type="string" office:string-value="cached" table:formula="${_xmlAttribute(formula.key)}"/>
        </table:table-row>
        '''),
      );
      for (final current in [book, await _roundTrip(book)]) {
        expect(current.sheets.single.cellA1('A1').formula, formula.value);
      }
    });
  }

  test('rejects a non-ODF package', () {
    expect(
      () => OdsSheetReader.readBytes(Uint8List.fromList(List.filled(64, 0))),
      throwsA(isA<OdsSheetFormatException>()),
    );
  });
}

Future<SmlWorkbook> _roundTrip(SmlWorkbook book) async => SheetDeserializer()
    .readBytes(await OfficeIsolateSave.workbook(book, recalculate: false));

String _xmlAttribute(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('"', '&quot;');

Uint8List _ods(String rows, {String styles = ''}) {
  final zip = ZipWriter()
    ..addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.spreadsheet'),
      store: true,
    )
    ..addFile(
      'content.xml',
      utf8.encode('''
      <office:document-content
        xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
        xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
        xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
        xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0">
        <office:automatic-styles>$styles</office:automatic-styles>
        <office:body><office:spreadsheet><table:table table:name="Data">$rows</table:table></office:spreadsheet></office:body>
      </office:document-content>
      '''),
    );
  return zip.close();
}
