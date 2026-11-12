import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _source = 'test/fixtures/fidelity/sheet-rename-native.xlsx';
const _worksheet = '/xl/worksheets/sheet2.xml';

SmlWorkbook _withFormula(String formula, {String value = '42', String? type}) {
  final package = OpcPackage.openBytes(File(_source).readAsBytesSync());
  final part = package.getPart(_worksheet)!;
  final document = XmlDocument.parse(part.readText());
  final cell = _cell(document.root!, 'D1');
  if (type != null) cell.setAttribute('t', type);
  cell.firstChild('f')!.text = formula;
  cell.firstChild('v')!.text = value;
  part.writeText(document.toXmlString());
  return SheetDeserializer().read(package);
}

XmlElement _cell(XmlElement sheet, String address) => sheet
    .firstChild('sheetData')!
    .childrenNamed('row')
    .expand((row) => row.childrenNamed('c'))
    .singleWhere((cell) => cell.getAttribute('r') == address);

void main() {
  final unsupported = <String, String>{
    "'[Remote.xlsx]Data'!B2": "'[Remote.xlsx]Data'!B2",
    '[1]Data!B2': '[1]Data!B2',
    'SUM(Data:Summary!B2)': "SUM('Next:Summary'!B2)",
    "SUM('Data:Summary'!B2)": "SUM('Next:Summary'!B2)",
    "SUM('Data':'Summary'!B2)": "SUM('Next:Summary'!B2)",
    'SUM(Data!A:B)': "SUM('Next'!A:B)",
    r"SUM('Data'!$A:$B)": r"SUM('Next'!$A:$B)",
    'SUM(Data!1:3)': "SUM('Next'!1:3)",
    r"SUM('Data'!$1:$3)": r"SUM('Next'!$1:$3)",
    'SUM(A:A)': 'SUM(A:A)',
    '2+3 unparsed': '2+3 unparsed',
  };
  for (final entry in unsupported.entries) {
    test(
      'unsupported evaluation retains imported cache: ${entry.key}',
      () async {
        var book = _withFormula(entry.key);
        SheetRename.rename(book, book.firstSheet, 'Next');
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = cycle == 1
              ? await OfficeIsolateSave.workbook(book)
              : SheetSerializer().writeBytes(book);
          final package = OpcPackage.openBytes(bytes);
          final cell = _cell(
            XmlDocument.parse(package.getPart(_worksheet)!.readText()).root!,
            'D1',
          );
          expect(cell.firstChild('f')!.text, entry.value);
          expect(double.parse(cell.firstChild('v')!.text), 42);
          book = SheetDeserializer().read(package);
          expect(book.sheets[1].cellA1('D1').value, 42);
        }
      },
    );
  }

  final typed = <String, ({Object value, String? type, String xml})>{
    'Data!LocalRange': (value: 2, type: null, xml: '2'),
    'IF(Data!B2>0,"Data!A1 ""quoted""","unused")': (
      value: 'Data!A1 "quoted"',
      type: 'str',
      xml: 'Data!A1 "quoted"',
    ),
    'IF(Data!B2>0,"0012","0099")': (value: '0012', type: 'str', xml: '0012'),
    'IF(Data!B2>0,"#literal","unused")': (
      value: '#literal',
      type: 'str',
      xml: '#literal',
    ),
    'Data!B2>0': (value: true, type: 'b', xml: '1'),
    'Data!B2<0': (value: false, type: 'b', xml: '0'),
    'Missing!B2': (value: '#REF!', type: 'e', xml: '#REF!'),
    'dAtA!B2+sUmMaRy!B2': (value: 4, type: null, xml: '4'),
    'Data!B2+Summary!B2': (value: 4, type: null, xml: '4'),
  };
  for (final entry in typed.entries) {
    test('formula cache keeps its native scalar type: ${entry.key}', () async {
      var book = _withFormula(entry.key);
      SheetRename.rename(book, book.firstSheet, 'Next');
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = cycle == 1
            ? await OfficeIsolateSave.workbook(book)
            : SheetSerializer().writeBytes(book);
        final package = OpcPackage.openBytes(bytes);
        final cell = _cell(
          XmlDocument.parse(package.getPart(_worksheet)!.readText()).root!,
          'D1',
        );
        expect(cell.getAttribute('t'), entry.value.type);
        if (entry.value.value is num) {
          expect(double.parse(cell.firstChild('v')!.text), entry.value.value);
        } else {
          expect(cell.firstChild('v')!.text, entry.value.xml);
        }
        book = SheetDeserializer().read(package);
        expect(book.sheets[1].cellA1('D1').value, entry.value.value);
      }
    });
  }
  test(
    'unfinished string input stays scannable but cannot replace a cache',
    () {
      const formula = '=Data!B2+"unfinished';
      final refs = FormulaRefScanner.scan(formula);
      expect(refs.single.lexeme, 'Data!B2');
      final book = _withFormula(formula);
      FormulaDepGraph(book).recalculate();
      expect(book.sheets[1].cellA1('D1').value, 42);
    },
  );
  for (final text in ['#REF!', '#N/A', '#NAME?', '#ERROR! literal']) {
    for (final source in ['literal', 'IF', 'reference']) {
      test('error spelling is text when returned by $source: $text', () async {
        final formula = switch (source) {
          'literal' => '"$text"',
          'IF' => 'IF(Data!B2>0,"$text","other")',
          _ => 'Data!F20',
        };
        var book = _withFormula(formula, value: text, type: 'str');
        book.firstSheet.cellA1('F20')
          ..type = SmlCellType.string
          ..value = text;
        SheetRename.rename(book, book.firstSheet, 'Next');
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = cycle == 1
              ? await OfficeIsolateSave.workbook(book)
              : SheetSerializer().writeBytes(book);
          final package = OpcPackage.openBytes(bytes);
          final cell = _cell(
            XmlDocument.parse(package.getPart(_worksheet)!.readText()).root!,
            'D1',
          );
          expect(cell.getAttribute('t'), 'str');
          expect(cell.firstChild('v')!.text, text);
          book = SheetDeserializer().read(package);
          expect(book.sheets[1].cellA1('D1').value, text);
          expect(book.sheets[1].cellA1('D1').type, SmlCellType.string);
        }
      });
    }
  }

  for (final formula in [
    'NA()',
    '1/0',
    'IF(TRUE,NA(),"#N/A")',
    'CONCAT(NA())',
  ]) {
    test('real generated errors retain an error cache: $formula', () async {
      var book = _withFormula(formula);
      final expected = formula == '1/0' ? '#DIV/0!' : '#N/A';
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = cycle == 1
            ? await OfficeIsolateSave.workbook(book)
            : SheetSerializer().writeBytes(book);
        final package = OpcPackage.openBytes(bytes);
        final cell = _cell(
          XmlDocument.parse(package.getPart(_worksheet)!.readText()).root!,
          'D1',
        );
        expect(cell.getAttribute('t'), 'e');
        expect(cell.firstChild('v')!.text, expected);
        book = SheetDeserializer().read(package);
        expect(book.sheets[1].cellA1('D1').type, SmlCellType.error);
      }
    });
  }

  test(
    'referenced native error remains distinct from referenced text',
    () async {
      var book = _withFormula('Data!F20', value: '#REF!', type: 'e');
      book.firstSheet.cellA1('F20')
        ..type = SmlCellType.error
        ..value = '#REF!';
      SheetRename.rename(book, book.firstSheet, 'Next');
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = cycle == 1
            ? await OfficeIsolateSave.workbook(book)
            : SheetSerializer().writeBytes(book);
        book = SheetDeserializer().readBytes(bytes);
        expect(book.firstSheet.cellA1('F20').type, SmlCellType.error);
        expect(book.sheets[1].cellA1('D1').type, SmlCellType.error);
        expect(book.sheets[1].cellA1('D1').value, '#REF!');
      }
    },
  );

  test('untyped manual error-looking cache rejects without recalculation', () {
    final book = SmlWorkbook();
    book.firstSheet.cellA1('A1')
      ..formula = '"#REF!"'
      ..type = SmlCellType.formula
      ..value = '#REF!';
    expect(
      () => SheetSerializer().writeBytes(book, recalculate: false),
      throwsUnsupportedError,
    );
    expect(book.package, isNull);
  });
  for (final type in ['str', 'e']) {
    test(
      'unsupported formula retains an explicit native $type cache',
      () async {
        var book = _withFormula('UnknownCache()', value: '#REF!', type: type);
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = cycle == 1
              ? await OfficeIsolateSave.workbook(book)
              : SheetSerializer().writeBytes(book, recalculate: cycle != 0);
          final package = OpcPackage.openBytes(bytes);
          final cell = _cell(
            XmlDocument.parse(package.getPart(_worksheet)!.readText()).root!,
            'D1',
          );
          expect(cell.getAttribute('t'), type);
          expect(cell.firstChild('v')!.text, '#REF!');
          book = SheetDeserializer().read(package);
        }
      },
    );
  }
  test(
    'public scalar evaluators preserve their return types and error semantics',
    () {
      final book = SmlWorkbook();
      final ctx = FormulaContext(
        workbook: book,
        sheet: book.firstSheet,
        origin: SmlCellRef.parse('A1'),
      );
      expect(evaluateFormula('NA()', ctx), '#N/A');
      expect(parseFormula('NA()').eval(ctx), '#N/A');
      expect(evaluateFormula('IFERROR("#REF!","replaced")', ctx), '#REF!');
      expect(evaluateFormula('IFNA("#N/A","replaced")', ctx), '#N/A');
      expect(evaluateFormula('IFERROR(NA(),"replaced")', ctx), 'replaced');
      expect(evaluateFormula('CONCAT("#","REF!")', ctx), '#REF!');
      expect(evaluateFormula('CONCAT(NA())', ctx), '#N/A');
      expect(evaluateFormula('ISERROR("#REF!")', ctx), isFalse);
      expect(evaluateFormula('ISERROR(NA())', ctx), isTrue);
      expect(evaluateFormula('TYPE("#REF!")', ctx), 2);
      expect(evaluateFormula('TYPE(NA())', ctx), 16);
    },
  );

  test('cycle errors retain explicit error caches', () {
    final book = SmlWorkbook();
    book.firstSheet.cellA1('A1').formula = 'A2';
    book.firstSheet.cellA1('A2').formula = 'A1';
    final bytes = SheetSerializer().writeBytes(book);
    final reopened = SheetDeserializer().readBytes(bytes);
    for (final ref in ['A1', 'A2']) {
      expect(reopened.firstSheet.cellA1(ref).value, '#CIRC!');
      expect(reopened.firstSheet.cellA1(ref).type, SmlCellType.error);
    }
  });
}
