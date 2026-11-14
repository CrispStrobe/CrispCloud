import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

SmlCell _formula(
  SmlWorksheet sheet,
  String address,
  String formula,
  Object? cache, {
  SmlCellType type = SmlCellType.formula,
}) => sheet.cellA1(address)
  ..formula = formula
  ..value = cache
  ..type = type;

void main() {
  for (final reverse in [false, true]) {
    test('unsupported dependencies retain every cache; reverse=$reverse', () {
      final book = SmlWorkbook();
      final sheet = book.firstSheet;
      final values = <String, (String, num)>{
        'A1': ('A2*2', 83),
        'A2': ('UNMODELED(2)', 41),
        'A3': ('A1+5', 97),
        'A4': ('2+3', 999),
      };
      for (final key in reverse ? values.keys.toList().reversed : values.keys) {
        final (formula, cache) = values[key]!;
        _formula(sheet, key, formula, cache);
      }
      final graph = FormulaDepGraph(book)..recalculate();
      expect(graph.circular, isEmpty);
      expect(sheet.cellA1('A1').value, 83);
      expect(sheet.cellA1('A2').value, 41);
      expect(sheet.cellA1('A3').value, 97);
      expect(sheet.cellA1('A4').value, 5);
      graph.recalculate();
      expect(sheet.cellA1('A1').value, 83);
      expect(sheet.cellA1('A3').value, 97);
    });
  }

  for (final formula in [
    'A1+1',
    '-A1',
    'SUM(A1:A2)',
    'COUNT(A1:A2)',
    'COUNTA(A1:A2)',
    'ISERROR(A1)',
    'ISNUMBER(A1)',
    'AND(A1,TRUE)',
    'CONCAT(A1,"tail")',
    'IFERROR(A1,0)',
    'IFNA(A1,0)',
    'IF(A1,1,0)',
    'IF(A1:A2,1,0)',
    'IFERROR(A1:A2,0)',
    '(A1:A2)+0',
    '-(A1:A2)',
    'LET(values,A1:A2,COUNT(values))',
    'SUM(IF(TRUE,A1:A2,A3:A4))',
    'INDIRECT("A1")+1',
    'SUM(INDIRECT("A1:A2"))',
    'OFFSET(B1,0,-1)+1',
    'SUM(OFFSET(B1,0,-1,2,1))',
  ]) {
    test('unsupported capability survives nested consumption: $formula', () {
      final book = SmlWorkbook();
      final sheet = book.firstSheet;
      _formula(sheet, 'D1', formula, 'authored', type: SmlCellType.string);
      _formula(sheet, 'A1', 'UNMODELED(2)', 41);
      sheet.cellA1('A2').value = 3;
      FormulaDepGraph(book).recalculate();
      expect(sheet.cellA1('D1').value, 'authored');
      expect(sheet.cellA1('D1').type, SmlCellType.string);
      expect(sheet.cellA1('A1').value, 41);
    });
  }

  for (final formula in [
    'COUNT(UNMODELED(2))',
    'ISERROR(UNMODELED(2))',
    'IFERROR(COUNT(UNMODELED(2)),0)',
    'AND(TRUE,UNMODELED(2))',
  ]) {
    test('own nested unsupported expression retains cache: $formula', () {
      final book = SmlWorkbook();
      final cell = _formula(book.firstSheet, 'A1', formula, 71);
      FormulaDepGraph(book).recalculate();
      expect(cell.value, 71);
    });
  }

  test(
    'cross-sheet runtime references read fresh values in their own scope',
    () {
      final book = SmlWorkbook(
        sheets: [
          SmlWorksheet(name: 'Summary', sheetId: 1),
          SmlWorksheet(name: "O'Brien Data", sheetId: 2),
        ],
      );
      final summary = book.firstSheet;
      final data = book.sheets[1];
      _formula(summary, 'A1', 'INDIRECT("\'O\'\'Brien Data\'!A1")', 99);
      _formula(summary, 'A2', "OFFSET('O''Brien Data'!B1,0,-1)", 99);
      _formula(summary, 'A3', "SUM(OFFSET('O''Brien Data'!B1:B2,0,-1))", 99);
      _formula(data, 'A1', '2+3', 71);
      data.cellA1('A2').value = 7;
      final graph = FormulaDepGraph(book)..recalculate();
      expect(graph.circular, isEmpty);
      expect(summary.cellA1('A1').value, 5);
      expect(summary.cellA1('A2').value, 5);
      expect(summary.cellA1('A3').value, 12);

      data.cellA1('A1').formula = 'UNMODELED(2)';
      _formula(summary, 'A1', 'INDIRECT("\'O\'\'Brien Data\'!A1")', 88);
      _formula(summary, 'A2', "OFFSET('O''Brien Data'!B1,0,-1)", 89);
      _formula(summary, 'A3', "SUM('O''Brien Data'!A1:A2)", 90);
      graph.recalculate();
      expect(summary.cellA1('A1').value, 88);
      expect(summary.cellA1('A2').value, 89);
      expect(summary.cellA1('A3').value, 90);
      expect(data.cellA1('A1').value, 5);
    },
  );

  test(
    'OFFSET reads the target and does not evaluate its address argument',
    () {
      final book = SmlWorkbook();
      final sheet = book.firstSheet;
      _formula(sheet, 'A1', 'OFFSET(A1,1,0)', 88);
      sheet.cellA1('A2').value = 6;
      _formula(sheet, 'B1', 'UNMODELED(2)', 71);
      _formula(sheet, 'B2', 'OFFSET(B1,1,0)', 99);
      final graph = FormulaDepGraph(book)..recalculate();
      expect(sheet.cellA1('A1').value, 6);
      expect(sheet.cellA1('B1').value, 71);
      expect(sheet.cellA1('B2').value, '#CIRC!');
      expect(graph.circular, {'Sheet1!B2'});
    },
  );

  for (final dynamicFormula in ['INDIRECT("A1")', 'OFFSET(A2,-1,0)']) {
    test(
      'runtime cycles invalidate all participating caches: $dynamicFormula',
      () {
        final book = SmlWorkbook();
        final sheet = book.firstSheet;
        _formula(sheet, 'A1', 'A2+1', 11);
        _formula(sheet, 'A2', dynamicFormula, 22);
        _formula(sheet, 'A3', 'IFERROR(A1,7)', 33);
        final graph = FormulaDepGraph(book)..recalculate();
        expect(graph.circular, {'Sheet1!A1', 'Sheet1!A2'});
        expect(sheet.cellA1('A1').value, '#CIRC!');
        expect(sheet.cellA1('A2').value, '#CIRC!');
        expect(sheet.cellA1('A1').type, SmlCellType.error);
        expect(sheet.cellA1('A2').type, SmlCellType.error);
        expect(sheet.cellA1('A3').value, 7);
      },
    );
  }

  test('unused dynamic branches cannot manufacture a cycle', () {
    final book = SmlWorkbook();
    final sheet = book.firstSheet;
    _formula(sheet, 'A1', 'IF(B1,A2,7)', 99);
    _formula(sheet, 'A2', 'A1+1', 88);
    _formula(sheet, 'B1', '1>2', true);
    final graph = FormulaDepGraph(book)..recalculate();
    expect(graph.circular, isEmpty);
    expect(sheet.cellA1('A1').value, 7);
    expect(sheet.cellA1('A2').value, 8);
    expect(sheet.cellA1('B1').value, false);
  });

  test('ordinary native errors are recalculated and remain handleable', () {
    final book = SmlWorkbook();
    final sheet = book.firstSheet;
    _formula(sheet, 'A1', '1/0', 41);
    _formula(sheet, 'B1', 'A1+1', 87);
    _formula(sheet, 'C1', 'IFERROR(A1,7)', 99);
    _formula(sheet, 'D1', 'ISERROR(A1)', false);
    _formula(sheet, 'E1', 'IF(FALSE,UNMODELED(2),8)', 99);
    _formula(sheet, 'F1', 'IFERROR("#REF!",7)', 99);
    _formula(sheet, 'G1', 'INDIRECT(A1)', 99);
    FormulaDepGraph(book).recalculate();
    expect(sheet.cellA1('A1').value, '#DIV/0!');
    expect(sheet.cellA1('B1').value, '#DIV/0!');
    expect(sheet.cellA1('A1').type, SmlCellType.error);
    expect(sheet.cellA1('B1').type, SmlCellType.error);
    expect(sheet.cellA1('C1').value, 7);
    expect(sheet.cellA1('D1').value, true);
    expect(sheet.cellA1('E1').value, 8);
    expect(sheet.cellA1('F1').value, '#REF!');
    expect(sheet.cellA1('F1').type, SmlCellType.string);
    expect(sheet.cellA1('G1').value, '#DIV/0!');
    expect(sheet.cellA1('G1').type, SmlCellType.error);
  });

  test(
    'disabling preservation exposes unsupported results to all dependents',
    () {
      final book = SmlWorkbook();
      final sheet = book.firstSheet;
      _formula(sheet, 'A1', 'UNMODELED(2)', 41);
      _formula(sheet, 'A2', 'A1+1', 87);
      _formula(sheet, 'A3', 'A2+1', null);
      FormulaDepGraph(book).recalculate(keepCachedOnUnsupported: false);
      for (final address in ['A1', 'A2', 'A3']) {
        expect(sheet.cellA1(address).value, '#NAME?');
        expect(sheet.cellA1(address).type, SmlCellType.error);
      }
    },
  );

  test('a missing dependent cache receives an explicit unsupported error', () {
    final book = SmlWorkbook();
    final sheet = book.firstSheet;
    _formula(sheet, 'A1', 'UNMODELED(2)', 41);
    _formula(sheet, 'A2', 'A1+1', null);
    FormulaDepGraph(book).recalculate();
    expect(sheet.cellA1('A1').value, 41);
    expect(sheet.cellA1('A2').value, '#NAME?');
    expect(sheet.cellA1('A2').type, SmlCellType.error);
  });

  for (final formula in [
    'OFFSET(A1,-1,0)',
    'OFFSET(A1,0,-1)',
    'OFFSET(A1,0,0,0,1)',
    'OFFSET(Missing!A1,0,0)',
    'INDIRECT("Missing!A1")',
    'INDIRECT("A0")',
    'INDIRECT("XFE1")',
    'INDIRECT("A1+2")',
  ]) {
    test('invalid dynamic target is a genuine reference error: $formula', () {
      final book = SmlWorkbook();
      final cell = _formula(book.firstSheet, 'B1', formula, 41);
      FormulaDepGraph(book).recalculate();
      expect(cell.value, '#REF!');
      expect(cell.type, SmlCellType.error);
    });
  }

  for (final formula in [
    'INDIRECT("R2C1",FALSE)',
    'INDIRECT("[1]Data!B2")',
    'INDIRECT("Table1[Amount]")',
  ]) {
    test(
      'unsupported dynamic reference preserves dependent caches: $formula',
      () {
        final book = SmlWorkbook();
        final sheet = book.firstSheet;
        _formula(sheet, 'A1', formula, 41);
        _formula(sheet, 'A2', 'A1+1', 87);
        FormulaDepGraph(book).recalculate();
        expect(sheet.cellA1('A1').value, 41);
        expect(sheet.cellA1('A2').value, 87);
      },
    );
  }

  test(
    'imported scalar cache types survive three direct/isolate saves',
    () async {
      final package = OpcPackage.openBytes(
        File('test/fixtures/fidelity/sheet-rename-native.xlsx')
            .readAsBytesSync(),
      );
      const worksheet = '/xl/worksheets/sheet2.xml';
      // Independently authored native values intentionally disagree with a
      // calculation using A1's stale 41. Expected caches are never derived from
      // the serializer under test.
      package.getPart(worksheet)!.writeText('''
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1"><f>UNMODELED(2)</f><v>41</v></c></row>
    <row r="2"><c r="A2"><f>A1*2</f><v>87</v></c></row>
    <row r="3"><c r="A3" t="b"><f>A1&gt;0</f><v>0</v></c></row>
    <row r="4"><c r="A4" t="str"><f>A1&amp;"text"</f><v>0007</v></c></row>
    <row r="5"><c r="A5" t="e"><f>A1+1</f><v>#N/A</v></c></row>
    <row r="6"><c r="A6" t="str"><f>A1&amp;"error"</f><v>#REF!</v></c></row>
    <row r="7"><c r="A7" t="str"><f>A1&amp;"empty"</f><v></v></c></row>
    <row r="8"><c r="A8"><f>A2+1</f><v>101</v></c></row>
  </sheetData>
</worksheet>''');
      var book = SheetDeserializer().read(package);
      final expected = <String, (String?, String, String)>{
        'A1': (null, '41', 'UNMODELED(2)'),
        'A2': (null, '87', 'A1*2'),
        'A3': ('b', '0', 'A1>0'),
        'A4': ('str', '0007', 'A1&"text"'),
        'A5': ('e', '#N/A', 'A1+1'),
        'A6': ('str', '#REF!', 'A1&"error"'),
        'A7': ('str', '', 'A1&"empty"'),
        'A8': (null, '101', 'A2+1'),
      };
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = cycle == 1
            ? await OfficeIsolateSave.workbook(book)
            : SheetSerializer().writeBytes(book);
        final saved = OpcPackage.openBytes(bytes);
        final root = XmlDocument.parse(saved.getPart(worksheet)!.readText())
            .root!;
        final cells = root
            .firstChild('sheetData')!
            .childrenNamed('row')
            .expand((row) => row.childrenNamed('c'));
        for (final entry in expected.entries) {
          final cell = cells.singleWhere(
            (cell) => cell.getAttribute('r') == entry.key,
          );
          final (type, value, formula) = entry.value;
          expect(
            cell.firstChild('f')!.text,
            formula,
            reason: '${entry.key} cycle $cycle',
          );
          expect(
            cell.getAttribute('t'),
            type,
            reason: '${entry.key} cycle $cycle',
          );
          final savedValue = cell.firstChild('v')!.text;
          expect(
            type == null ? double.parse(savedValue) : savedValue,
            type == null ? double.parse(value) : value,
            reason: '${entry.key} cycle $cycle',
          );
        }
        book = SheetDeserializer().read(saved);
      }
    },
  );
}
