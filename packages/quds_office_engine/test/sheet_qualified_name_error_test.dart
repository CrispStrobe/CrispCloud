import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _problem = "'O''Brien Data'!Problem";
const _text = "'O''Brien Data'!Text";
const _unsupported = "'O''Brien Data'!Computed";

SmlWorkbook _read() => SheetDeserializer().readBytes(
  File(
    'test/fixtures/fidelity/sheet-qualified-names-native.xlsx',
  ).readAsBytesSync(),
);

Object? _eval(SmlWorkbook book, String formula) => evaluateFormula(
  formula,
  FormulaContext(
    workbook: book,
    sheet: book.sheets[2],
    origin: SmlCellRef.parse('Z30'),
  ),
);

void main() {
  for (final prefix in ['', '_xlfn.', '_xlfn._xlws.']) {
    test('qualified-name LET shadowing agrees with graph for $prefix', () {
      final book = _read();
      final formula = '${prefix}LET(Price,6,Price+1)';
      final cell = book.firstSheet.cellA1('B3')
        ..formula = formula
        ..value = 42;
      final graph = FormulaDepGraph(book)..recalculate();
      expect(_eval(book, formula), 7);
      expect(graph.circular, isEmpty);
      expect(cell.value, 7);
    });
  }

  const numeric = [
    'ABS(@)',
    'ROUND(@,0)',
    'ROUND(3,@)',
    'ROUNDUP(@,0)',
    'ROUNDDOWN(@,0)',
    'MOD(@,2)',
    'POWER(2,@)',
    'POW(@,2)',
    'SQRT(@)',
    'EXP(@)',
    'LN(@)',
    'LOG(2,@)',
    '_xlfn.LOG10(@)',
    'SIGN(@)',
    'INT(@)',
    'TRUNC(@)',
    'CEILING(@)',
    'FLOOR(@)',
    'EVEN(@)',
    'ODD(@)',
    'FACT(@)',
    'GCD(1,@)',
    'LCM(1,@)',
    'QUOTIENT(8,@)',
    'MROUND(8,@)',
    'MEDIAN(1,@)',
    'AVEDEV(1,@)',
    'STDEV(1,@)',
    'STDEVP(1,@)',
    'VAR(1,@)',
    'VARP(1,@)',
    'RANDBETWEEN(1,@)',
    'IRR(@)',
    'TIME(1,@,0)',
    'DAYS(2,@)',
    'VALUE(@)',
    'CHAR(@)',
    'CODE(@)',
    'UNICHAR(@)',
    'UNICODE(@)',
    'LEN(@)',
    'FIND(@,"text")',
    'SEARCH("t",@)',
    'N(@)',
    'ADDRESS(1,@)',
    'FIXED(@)',
    'DOLLAR(@)',
    'RMB(@)',
    'YEN(@)',
    'BAHTTEXT(@)',
    'DATE(2026,1,@)',
    'YEAR(@)',
    'MONTH(@)',
    'DAY(@)',
    'HOUR(@)',
    'MINUTE(@)',
    'SECOND(@)',
    'WEEKDAY(@)',
    'PV(0.1,1,@)',
    'FV(0.1,1,@)',
    'PMT(0.1,1,@)',
    'NPV(0.1,1,@)',
    'SIN(@)',
    'COS(@)',
    'TAN(@)',
    'EDATE(1,@)',
    'EOMONTH(1,@)',
    'NETWORKDAYS(1,@)',
    'SEQUENCE(1,1,@)',
  ];
  for (final pattern in numeric) {
    test('numeric consumer retains a genuine named error: $pattern', () {
      final book = _read();
      final formula = pattern.replaceAll('@', _problem);
      expect(_eval(book, formula), '#REF!');
      final cell = book.sheets[2].cellA1('Z30')
        ..formula = formula
        ..value = 42;
      FormulaDepGraph(book).recalculate();
      expect(cell.value, '#REF!');
      expect(cell.type, SmlCellType.error);
    });
  }

  test(
    'error handlers and type predicates consume genuine errors explicitly',
    () {
      final book = _read();
      expect(_eval(book, 'IFERROR(ABS($_problem),12)'), 12);
      expect(_eval(book, 'ISERROR(ROUND($_problem,0))'), isTrue);
      expect(_eval(book, 'ISERROR($_text)'), isFalse);
      expect(_eval(book, 'IFERROR($_text,12)'), '#REF!');
      expect(_eval(book, 'MEDIAN(1,$_text,3)'), 2);
      expect(_eval(book, 'N($_text)'), 0);
      expect(_eval(book, 'TYPE($_problem)'), 16);
      expect(_eval(book, 'TYPE($_text)'), 2);
    },
  );

  test(
    'IF evaluates only its selected branch and preserves predicate errors',
    () {
      final book = _read();
      expect(_eval(book, 'IF(FALSE,$_problem,7)'), 7);
      expect(_eval(book, 'IF(TRUE,7,$_problem)'), 7);
      expect(_eval(book, 'IF($_problem,7,9)'), '#REF!');
      expect(_eval(book, 'IF(FALSE,$_unsupported,7)'), 7);
      expect(_eval(book, 'IF(TRUE,7,$_unsupported)'), 7);
    },
  );

  test('IFERROR and IFNA evaluate fallback expressions only when selected', () {
    final book = _read();
    expect(_eval(book, 'IFERROR(7,$_unsupported)'), 7);
    expect(_eval(book, 'IFNA(7,$_unsupported)'), 7);
    expect(_eval(book, 'IFERROR($_problem,12)'), 12);
    expect(_eval(book, 'IFNA($_problem,12)'), '#REF!');
    expect(_eval(book, 'IFNA(NA(),12)'), 12);
  });

  test(
    'counting, criteria and type functions keep their explicit error policy',
    () {
      final book = _read();
      const errors = "'O''Brien Data'!Errors";
      expect(_eval(book, 'COUNT(1,$_problem,$errors)'), 1);
      expect(_eval(book, 'COUNTA($_problem,$errors)'), 3);
      expect(_eval(book, 'COUNTBLANK($errors)'), 0);
      expect(_eval(book, 'ISNUMBER($_problem)'), isFalse);
      expect(_eval(book, 'ISNUMBER($_text)'), isFalse);
      expect(_eval(book, 'ISERROR($_problem)'), isTrue);
      expect(_eval(book, 'ISTEXT($_text)'), isTrue);
      expect(_eval(book, 'TYPE($_problem)'), 16);
      final sheet = book.sheets[2];
      sheet.cellA1('Z2').value = 1;
      sheet.cellA1('Z3').value = 2;
      sheet.cellA1('AA2').value = 5;
      sheet.cellA1('AA3')
        ..value = '#REF!'
        ..type = SmlCellType.error;
      expect(_eval(book, 'SUMIF(Z2:Z3,1,AA2:AA3)'), 5);
      expect(_eval(book, 'AVERAGEIF(Z2:Z3,1,AA2:AA3)'), 5);
      expect(_eval(book, 'COUNTIF(Z2:Z3,1)'), 1);
    },
  );

  test('unsupported parser/function/name paths keep authored caches', () {
    final book = _read();
    for (final formula in [
      // Bare LOG10 is an existing cell-token ambiguity; the supported future
      // prefix reaches the numeric function. This change does not alter lexing.
      'LOG10($_problem)',
      'IFERROR(UnmodeledFunction(),12)',
      'IFERROR($_unsupported,12)',
    ]) {
      final cell = book.sheets[2].cellA1('Z30')
        ..formula = formula
        ..value = 97;
      FormulaDepGraph(book).recalculate();
      expect(cell.value, 97, reason: formula);
    }
  });

  test(
    'unused opaque constant branches cannot discard needed dependencies',
    () {
      final book = _read();
      final source = book.sheets[2].cellA1('Z30')
        ..formula = '2+5'
        ..value = 42;
      final target = book.firstSheet.cellA1('D1')
        ..formula = 'IF(FALSE,$_unsupported,Summary!Z30)'
        ..value = 97;
      FormulaDepGraph(book).recalculate();
      expect(source.value, 7);
      expect(target.value, 7);
      for (final formula in [
        'IFERROR(7,$_unsupported)',
        'IFNA(7,$_unsupported)',
      ]) {
        target
          ..formula = formula
          ..value = 97;
        FormulaDepGraph(book).recalculate();
        expect(target.value, 7);
      }
    },
  );

  test('dynamic opaque branches stay explicit cache fallbacks', () {
    final book = _read();
    book.firstSheet.cellA1('Z1').value = false;
    final target = book.firstSheet.cellA1('D1')
      ..formula = 'IF(Z1,$_unsupported,Summary!Z30)'
      ..value = 97;
    book.sheets[2].cellA1('Z30')
      ..formula = '2+5'
      ..value = 42;
    FormulaDepGraph(book).recalculate();
    expect(target.value, 97);
    FormulaDepGraph(book).recalculate(keepCachedOnUnsupported: false);
    expect(target.value, startsWith('#ERROR!'));
    expect(target.type, SmlCellType.error);
  });

  test(
    'numeric named errors retain error caches through three direct/isolate saves',
    () async {
      var book = _read();
      for (final entry in {
        'Z30': 'ABS($_problem)',
        'Z31': 'ROUND($_problem,0)',
        'Z32': 'MEDIAN($_problem)',
      }.entries) {
        book.sheets[2].cellA1(entry.key)
          ..formula = entry.value
          ..value = 42;
      }
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = cycle == 1
            ? await OfficeIsolateSave.workbook(book)
            : SheetSerializer().writeBytes(book);
        final package = OpcPackage.openBytes(bytes);
        final xml = XmlDocument.parse(
          package.getPart('/xl/worksheets/sheet3.xml')!.readText(),
        );
        final cells = xml.root!
            .firstChild('sheetData')!
            .childrenNamed('row')
            .expand((row) => row.childrenNamed('c'));
        for (final ref in ['Z30', 'Z31', 'Z32']) {
          final cell = cells.singleWhere(
            (cell) => cell.getAttribute('r') == ref,
          );
          expect(cell.getAttribute('t'), 'e');
          expect(cell.firstChild('v')!.text, '#REF!');
        }
        book = SheetDeserializer().read(package);
      }
    },
  );
}
