import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  group('numeric evaluation stays finite and bounded', () {
    for (final function in ['ROUND', 'ROUNDUP', 'ROUNDDOWN']) {
      for (final digits in ['1000000000', '-1000000000', '1e308']) {
        for (final referenced in [false, true]) {
          test(
            '$function rejects $digits precision (reference=$referenced)',
            () {
              final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
              sheet.cellA1('B1').value = double.parse(digits);
              final expression = '$function(1,${referenced ? 'B1' : digits})';
              final context = FormulaContext(
                workbook: SmlWorkbook(sheets: [sheet]),
                sheet: sheet,
                origin: _a1,
              );
              final value = evaluateFormulaForCache(expression, context);
              expect(
                value,
                isA<FormulaErrorValue>().having(
                  (error) => error.code,
                  'code',
                  '#NUM!',
                ),
              );
              expect(
                _rule(
                  formula: '$expression>0',
                ).matches(SmlCell(ref: _a1), sheet),
                isFalse,
              );
            },
          );
        }
      }
    }

    for (final expression in [
      '(1e308*1e308)>0',
      'SUM(1e308,1e308)>0',
      'IF(1e308*1e308,TRUE,FALSE)',
      '(1e308*1e308)^2>0',
      '2^1000000000>0',
      '1e999>0',
      'ROUND(1,1e999)>0',
      'ROUNDUP(1,1e999)>0',
      'ROUNDDOWN(1,1e999)>0',
    ]) {
      test(
        'numeric overflow cannot become a matching Boolean: $expression',
        () {
          final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
          final context = FormulaContext(
            workbook: SmlWorkbook(sheets: [sheet]),
            sheet: sheet,
            origin: _a1,
          );
          expect(
            evaluateFormulaForCache(expression, context),
            isA<FormulaErrorValue>().having(
              (error) => error.code,
              'code',
              '#NUM!',
            ),
          );
          expect(
            _rule(formula: expression).matches(SmlCell(ref: _a1), sheet),
            isFalse,
          );
        },
      );
    }

    test(
      'nonfinite referenced caches and uncached intermediates stay errors',
      () {
        final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
        for (final value in [
          double.infinity,
          double.negativeInfinity,
          double.nan,
        ]) {
          sheet.cellA1('B1').value = value;
          for (final expression in ['B1>0', 'B1^2>0', 'IF(B1,TRUE,FALSE)']) {
            expect(
              _rule(formula: expression).matches(SmlCell(ref: _a1), sheet),
              isFalse,
              reason: expression,
            );
          }
        }
        sheet.cellA1('B1')
          ..value = null
          ..formula = 'SUM(1e308,1e308)';
        expect(
          _rule(formula: 'B1>0').matches(SmlCell(ref: _a1), sheet),
          isFalse,
        );
        expect(sheet.cellA1('B1').value, isNull);
      },
    );

    test('ordinary rounding and powers retain finite scalar results', () {
      final book = SmlWorkbook();
      final context = FormulaContext(
        workbook: book,
        sheet: book.firstSheet,
        origin: _a1,
      );
      for (final entry in <String, double>{
        'ROUND(12.345,2)': 12.35,
        'ROUND(1234,-2)': 1200,
        'ROUNDUP(1.231,2)': 1.24,
        'ROUNDUP(-1.231,2)': -1.24,
        'ROUNDDOWN(-1.239,2)': -1.23,
        'ROUND(1e308,2)': 1e308,
        'ROUND(1e-308,308)': 1e-308,
        '2^10': 1024,
        '(-2)^3': -8,
        '4^0.5': 2,
        '2^-3': 0.125,
        '(-2)^1000000000': double.infinity,
      }.entries) {
        if (entry.value.isInfinite) {
          expect(
            evaluateFormulaForCache(entry.key, context),
            isA<FormulaErrorValue>(),
          );
        } else {
          final value = evaluateFormulaForCache(entry.key, context);
          expect(value, isA<num>(), reason: entry.key);
          expect(
            (value as num).toDouble() / entry.value,
            closeTo(1, 1e-12),
            reason: entry.key,
          );
        }
      }
    });

    test('explicit error handlers can handle numeric failures', () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      for (final expression in [
        'ISERROR(SUM(1e308,1e308))',
        'IFERROR(ROUND(1,1000000000),TRUE)',
        'IFERROR((1e308*1e308)^2,TRUE)',
      ]) {
        expect(
          _rule(formula: expression).matches(SmlCell(ref: _a1), sheet),
          isTrue,
          reason: expression,
        );
      }
    });

    test(
      'shared power and logarithm functions reject nonfinite input promptly',
      () {
        final book = SmlWorkbook();
        final context = FormulaContext(
          workbook: book,
          sheet: book.firstSheet,
          origin: _a1,
        );
        for (final expression in [
          'POWER(1e308,1000000000)',
          'POWER("Infinity",2)',
          'LN("Infinity")',
          'EXP("Infinity")',
        ]) {
          expect(
            evaluateFormulaForCache(expression, context),
            isA<FormulaErrorValue>().having(
              (error) => error.code,
              'code',
              '#NUM!',
            ),
            reason: expression,
          );
        }
      },
    );
  });

  test('authored priority wins independently for fill and font', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    final low = _rule(priority: 8, fill: '0000FF', font: '112233');
    final high = _rule(priority: 2, fill: 'FF0000');
    sheet.conditionalFormats.addAll([low, high]);
    final before = sheet.conditionalFormatState();
    final style = SmlConditionalResolver(sheet: sheet).resolve(_a1);
    expect(style.fillRgb, 'FF0000');
    expect(style.fontRgb, '112233');
    expect(sheet.conditionalFormats, [low, high]);
    expect(sheet.conditionalFormatState(), before);
    expect(sheet.rows, isEmpty);
  });

  for (final withStyle in [false, true]) {
    test('matching stop rule blocks lower properties (style=$withStyle)', () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      sheet.conditionalFormats.addAll([
        _rule(priority: 9, fill: '0000FF', font: '112233'),
        _rule(priority: 1, fill: withStyle ? 'FF0000' : '', stop: true),
      ]);
      final style = SmlConditionalResolver(sheet: sheet).resolve(_a1);
      expect(style.fillRgb, withStyle ? 'FF0000' : null);
      expect(style.fontRgb, isNull);
    });
  }

  test('a false stopping rule permits the lower rule', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.conditionalFormats.addAll([
      _rule(priority: 1, fill: 'FF0000', stop: true, formula: 'FALSE'),
      _rule(priority: 2, fill: '0000FF'),
    ]);
    expect(SmlConditionalResolver(sheet: sheet).resolve(_a1).fillRgb, '0000FF');
  });

  test('generated priorities agree before and after XLSX serialization', () {
    var book = SmlWorkbook();
    book.firstSheet.conditionalFormats.addAll([
      _rule(fill: '111111'),
      _rule(priority: 3, fill: '333333'),
      _rule(priority: 3, fill: '444444'),
      _rule(priority: -1, fill: '555555'),
    ]);
    final initial = SmlConditionalResolver.effectivePriorities(
      book.firstSheet.conditionalFormats,
    );
    expect(initial, [4, 3, 5, 6]);
    for (var cycle = 0; cycle < 2; cycle++) {
      expect(
        SmlConditionalResolver(
          sheet: book.firstSheet,
          workbook: book,
        ).resolve(_a1).fillRgb,
        '333333',
      );
      book = SheetDeserializer().read(
        OpcPackage.openBytes(
          SheetSerializer().writeBytes(book, recalculate: false),
        ),
      );
      expect(
        book.firstSheet.conditionalFormats.map((r) => r.priority),
        initial,
      );
    }
  });

  test('native font-only and no-style rules do not synthesize a fill', () {
    final book = SmlWorkbook();
    book.firstSheet.conditionalFormats.addAll([
      _rule(priority: 1, font: '12AB34'),
      _rule(priority: 2, stop: true),
      _rule(priority: 3, fill: 'ABCDEF'),
    ]);
    final reopened = SheetDeserializer().read(
      OpcPackage.openBytes(
        SheetSerializer().writeBytes(book, recalculate: false),
      ),
    );
    expect(
      reopened.firstSheet.conditionalFormats.take(2).map((r) => r.fillRgb),
      ['', ''],
    );
    final style = SmlConditionalResolver(
      sheet: reopened.firstSheet,
      workbook: reopened,
    ).resolve(_a1);
    expect(style.fillRgb, isNull);
    expect(style.fontRgb, '12AB34');
  });

  test('relative expression rules follow the range anchor', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A2').value = 2;
    sheet.cellA1('A3').value = 9;
    final rule = SmlConditionalRule(
      range: SmlRange.parse('B2:B3'),
      kind: SmlConditionalKind.expression,
      formula: 'A2>5',
    );
    expect(rule.matches(sheet.cellA1('B2'), sheet), isFalse);
    expect(rule.matches(sheet.cellA1('B3'), sheet), isTrue);
  });

  test('ODS retains an unstyled expression and does not invent a fill', () {
    final book = SmlWorkbook();
    book.firstSheet.conditionalFormats.add(_rule());
    final reopened = OdsSheetReader.readBytes(OdsSheetWriter.writeBytes(book));
    final rule = reopened.firstSheet.conditionalFormats.single;
    expect(rule.kind, SmlConditionalKind.expression);
    expect(rule.formula, 'TRUE');
    expect(rule.fillRgb, isEmpty);
    expect(rule.fontRgb, isEmpty);
  });

  for (final literal in ['تم', 'größer', 'gro\u0308ßer', '完成 ✓']) {
    test('legacy equality accepts Unicode text: $literal', () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      final cell = sheet.cellA1('A1')..value = literal;
      final rule = SmlConditionalRule(
        range: SmlRange.parse('A1'),
        kind: SmlConditionalKind.equal,
        formula: literal,
      );
      expect(rule.matches(cell, sheet), isTrue);
      rule.kind = SmlConditionalKind.notEqual;
      expect(rule.matches(cell, sheet), isFalse);
    });
  }

  test('equality text with formula syntax must be quoted explicitly', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    final cell = sheet.cellA1('A1')..value = 'SUM(';
    final rule = SmlConditionalRule(
      range: SmlRange.parse('A1'),
      kind: SmlConditionalKind.notEqual,
      formula: 'SUM(',
    );
    expect(rule.matches(cell, sheet), isFalse);
    rule.kind = SmlConditionalKind.equal;
    rule.formula = '"SUM("';
    expect(rule.matches(cell, sheet), isTrue);
  });

  test(
    'unsupported defined-name formulas cannot bypass the formula subset',
    () {
      final book = SmlWorkbook(
        formulaNames: [
          SmlFormulaName(name: 'Huge', formula: 'SEQUENCE(1000000000)'),
          SmlFormulaName(name: 'Dynamic', formula: 'INDIRECT("A1")'),
        ],
      );
      for (final name in ['Huge', 'Dynamic']) {
        expect(
          _rule(
            formula: name,
          ).matches(SmlCell(ref: _a1), book.firstSheet, workbook: book),
          isFalse,
        );
        final equality = SmlConditionalRule(
          range: SmlRange.parse('A1'),
          kind: SmlConditionalKind.notEqual,
          formula: name,
        );
        expect(
          equality.matches(SmlCell(ref: _a1), book.firstSheet, workbook: book),
          isFalse,
        );
      }
      expect(book.firstSheet.rows, isEmpty);
    },
  );

  test('numeric bounds can reference an absolute source cell', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A1').value = 8;
    sheet.cellA1('D1').value = 5;
    final rule = SmlConditionalRule(
      range: SmlRange.parse('A1:A2'),
      kind: SmlConditionalKind.greaterThan,
      formula: r'$D$1',
    );
    expect(rule.matches(sheet.cellA1('A1'), sheet), isTrue);
  });

  test('mixed references and ROW/COLUMN use the evaluated cell origin', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A3').value = 5;
    sheet.cellA1('C1').value = 7;
    final rule = _rule(
      range: 'B2:C3',
      formula: r'AND($A2=5,B$1=7,ROW()=3,COLUMN()=3)',
    );
    expect(rule.matches(SmlCell(ref: SmlCellRef.parse('C3')), sheet), isTrue);
    expect(rule.matches(SmlCell(ref: SmlCellRef.parse('B2')), sheet), isFalse);
  });

  test('cross-sheet and local names use the supplied workbook scope', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    final other = SmlWorksheet(name: "Other's data", sheetId: 2);
    other.cellA1('A1').value = 8;
    final book = SmlWorkbook(
      sheets: [sheet, other],
      formulaNames: [
        SmlFormulaName(name: 'Limit', formula: '100'),
        SmlFormulaName(name: 'Limit', formula: '5', localSheetId: 0),
      ],
      namedRanges: [
        SmlNamedRange(
          name: 'Chosen',
          sheetName: other.name,
          range: SmlRange.parse('A1'),
        ),
      ],
    );
    final rule = _rule(formula: "AND('Other''s data'!\$A\$1>Limit,Chosen=8)");
    expect(rule.matches(SmlCell(ref: _a1), sheet, workbook: book), isTrue);
    expect(rule.matches(SmlCell(ref: _a1), sheet), isFalse);
  });

  test('between rules shift both formula bounds', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('A2').value = 6;
    sheet.cellA1('B2').value = 5;
    sheet.cellA1('C2').value = 7;
    final rule = SmlConditionalRule(
      range: SmlRange.parse('A1:A2'),
      kind: SmlConditionalKind.between,
      formula: 'B1',
      formula2: 'C1',
    );
    expect(rule.matches(sheet.cellA1('A2'), sheet), isTrue);
    rule.formula2 = 'C1-2';
    expect(rule.matches(sheet.cellA1('A2'), sheet), isFalse);
  });

  test(
    'numeric equality compares values and legacy bare text remains usable',
    () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      final cell = sheet.cellA1('A1')..value = 5;
      final rule = SmlConditionalRule(
        range: SmlRange.parse('A1'),
        kind: SmlConditionalKind.equal,
        formula: '5.0',
      );
      expect(rule.matches(cell, sheet), isTrue);
      cell.value = 'approved';
      rule.formula = 'approved';
      expect(rule.matches(cell, sheet), isTrue);
      rule.formula = '"approved"';
      expect(rule.matches(cell, sheet), isTrue);
    },
  );

  test(
    'read-only formulas use absent and uncached cells without changing them',
    () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      sheet.cellA1('B1').formula = 'SUM(C1,2)';
      final rule = _rule(formula: 'AND(B1=2,ISBLANK(Z99))');
      final before = sheet.allCells.map((cell) => cell.ref.a1).toList();
      expect(rule.matches(SmlCell(ref: _a1), sheet), isTrue);
      expect(sheet.allCells.map((cell) => cell.ref.a1), before);
      expect(sheet.cellA1('B1').value, isNull);
    },
  );

  test(
    'new resolver observes edits without persisting a stale style cache',
    () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      sheet.cellA1('B1').value = 2;
      sheet.conditionalFormats.add(_rule(formula: 'B1>5', fill: '123456'));
      expect(SmlConditionalResolver(sheet: sheet).resolve(_a1).fillRgb, isNull);
      sheet.cellA1('B1').value = 9;
      expect(
        SmlConditionalResolver(sheet: sheet).resolve(_a1).fillRgb,
        '123456',
      );
    },
  );

  for (final formula in [
    '1/0',
    'UNKNOWN(A1)',
    '"arbitrary text"',
    'SUM(A1:XFD1048576)>0',
    'SEQUENCE(1000000000)',
    'REPT("a",1000000000)',
    'INDIRECT("A1")',
    'SUM(',
    'A0=0',
    'A1048577=0',
  ]) {
    test('unsupported or erroneous predicate safely declines: $formula', () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      expect(
        _rule(formula: formula).matches(SmlCell(ref: _a1), sheet),
        isFalse,
      );
      expect(sheet.rows, isEmpty);
    });
  }

  test('cyclic referenced formulas and typed native errors do not match', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('B1').formula = 'C1';
    sheet.cellA1('C1').formula = 'B1';
    expect(_rule(formula: 'B1<>0').matches(SmlCell(ref: _a1), sheet), isFalse);
    sheet.cellA1('B1')
      ..formula = null
      ..type = SmlCellType.error
      ..value = '#REF!';
    expect(_rule(formula: 'B1<>0').matches(SmlCell(ref: _a1), sheet), isFalse);
    expect(
      _rule(formula: 'ISERROR(B1)').matches(SmlCell(ref: _a1), sheet),
      isTrue,
    );
  });

  test('large named ranges are rejected before materializing cells', () {
    final book = SmlWorkbook(
      namedRanges: [
        SmlNamedRange(
          name: 'Huge',
          sheetName: 'Sheet1',
          range: SmlRange.parse('A1:XFD1048576'),
        ),
      ],
    );
    expect(
      _rule(
        formula: 'SUM(Huge)>0',
      ).matches(SmlCell(ref: _a1), book.firstSheet, workbook: book),
      isFalse,
    );
    expect(book.firstSheet.rows, isEmpty);
  });

  for (final formula in [
    'AND(1/0,TRUE)',
    'OR(1/0,FALSE)',
    'XOR(1/0,FALSE)',
    'NOT(NOT(1/0))',
  ]) {
    test('Boolean error predicate cannot stop valid lower rules: $formula', () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      sheet.conditionalFormats.addAll([
        _rule(priority: 1, formula: formula, stop: true, fill: 'FF0000'),
        _rule(priority: 2, fill: '00FF00'),
      ]);
      expect(
        SmlConditionalResolver(sheet: sheet).resolve(_a1).fillRgb,
        '00FF00',
      );
    });
  }

  test(
    'explicit error handling and Boolean constant calls remain supported',
    () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      for (final formula in [
        'AND(TRUE(),NOT(FALSE()))',
        'ISERROR(1/0)',
        'IFERROR(1/0,TRUE)',
        'AND(ISERROR(1/0),TRUE)',
      ]) {
        expect(
          _rule(formula: formula).matches(SmlCell(ref: _a1), sheet),
          isTrue,
          reason: formula,
        );
      }
    },
  );

  for (final function in ['AND', 'OR', 'XOR']) {
    test('$function evaluates each Boolean range value', () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      sheet.cellA1('B1').value = false;
      sheet.cellA1('B2').value = false;
      final rule = _rule(formula: '$function(B1:B2)');
      expect(rule.matches(SmlCell(ref: _a1), sheet), isFalse);
      sheet.cellA1('B1').value = true;
      expect(rule.matches(SmlCell(ref: _a1), sheet), function != 'AND');
      sheet.cellA1('B2').value = true;
      expect(rule.matches(SmlCell(ref: _a1), sheet), function != 'XOR');
      sheet.cellA1('B2')
        ..type = SmlCellType.error
        ..value = '#DIV/0!';
      expect(rule.matches(SmlCell(ref: _a1), sheet), isFalse);
    });
  }

  test('NOT declines a range instead of coercing its container to true', () {
    final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
    sheet.cellA1('B1').value = false;
    sheet.cellA1('B2').value = false;
    expect(
      _rule(formula: 'NOT(B1:B2)').matches(SmlCell(ref: _a1), sheet),
      isFalse,
    );
    expect(
      _rule(formula: 'TRUE(1)').matches(SmlCell(ref: _a1), sheet),
      isFalse,
    );
    expect(
      _rule(formula: 'IF(B1:B2,TRUE,FALSE)').matches(SmlCell(ref: _a1), sheet),
      isFalse,
    );
  });

  test(
    'logical ranges ignore text and blanks instead of treating them as true',
    () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      sheet.cellA1('B1').value = 'text';
      sheet.cellA1('B2').value = true;
      expect(
        _rule(formula: 'AND(B1:B3)').matches(SmlCell(ref: _a1), sheet),
        isTrue,
      );
      expect(
        _rule(formula: 'XOR(B1:B3)').matches(SmlCell(ref: _a1), sheet),
        isTrue,
      );
      for (final formula in [
        'AND("arbitrary text")',
        'AND()',
        'AND(B1)',
        'NOT("arbitrary text")',
        'NOT(NOT("arbitrary text"))',
      ]) {
        expect(
          _rule(formula: formula).matches(SmlCell(ref: _a1), sheet),
          isFalse,
          reason: formula,
        );
      }
    },
  );

  for (final kind in [
    SmlConditionalKind.duplicate,
    SmlConditionalKind.top,
    SmlConditionalKind.bottom,
    SmlConditionalKind.aboveAverage,
    SmlConditionalKind.belowAverage,
    SmlConditionalKind.topPercent,
    SmlConditionalKind.bottomPercent,
  ]) {
    test('sparse ${kind.name} scans stored cells across a whole worksheet', () {
      final sheet = SmlWorksheet(name: 'Data', sheetId: 1);
      sheet.cellA1('A1').value = 9;
      sheet.cellA1('XFD1048576').value = 9;
      sheet.cellA1('A2').value = 1;
      final rule = SmlConditionalRule(
        range: SmlRange.parse('A1:XFD1048576'),
        kind: kind,
        rank: 1,
      );
      final expected = ![
        SmlConditionalKind.bottom,
        SmlConditionalKind.belowAverage,
        SmlConditionalKind.bottomPercent,
      ].contains(kind);
      expect(rule.matches(sheet.cellA1('A1'), sheet), expected);
      expect(sheet.allCells, hasLength(3));
    });
  }

  test('worksheet PDF uses conditional fill and font colors', () {
    final book = SmlWorkbook();
    final sheet = book.sheets.single;
    sheet.cellA1('A1').value = 8;
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('A1'),
        kind: SmlConditionalKind.greaterThan,
        formula: '5',
        fillRgb: '123456',
        priority: 1,
      ),
    );
    sheet.conditionalFormats.insert(
      0,
      _rule(priority: 9, fill: 'FF0000', font: 'ABCDEF'),
    );
    final bytes = OfficePdfExport.workbook(book);
    final output = Platform.environment['QUDS_CONDITIONAL_RENDER_OUTPUT'];
    if (output != null && output.isNotEmpty) {
      Directory(output).createSync(recursive: true);
      File('$output/conditional-styles.pdf').writeAsBytesSync(bytes);
    }
    final display = PdfFile.open(bytes).displayList(0);
    expect(
      display.ops.whereType<PdfFillPath>().map((op) => op.color),
      contains(0xff123456),
    );
    expect(
      display.ops
          .whereType<PdfDrawText>()
          .where((op) => op.text == '8')
          .map((op) => op.color),
      everyElement(0xffabcdef),
    );
    expect(
      display.ops.whereType<PdfDrawText>().where((op) => op.text == '8'),
      isNotEmpty,
    );
  });

  test('worksheet PDF colors blank cells in the selected print area', () {
    final book = SmlWorkbook();
    final sheet = book.sheets.single;
    sheet.printArea = SmlRange.parse('A1:B2');
    sheet.cellA1('A1').value = 'anchor';
    sheet.conditionalFormats.add(
      SmlConditionalRule(
        range: SmlRange.parse('B2'),
        kind: SmlConditionalKind.expression,
        formula: 'TRUE',
        fillRgb: '12AB34',
      ),
    );
    final display = PdfFile.open(OfficePdfExport.workbook(book)).displayList(0);
    expect(
      display.ops.whereType<PdfFillPath>().map((op) => op.color),
      contains(0xff12ab34),
    );
    expect(sheet.cellOrNull(SmlCellRef.parse('B2')), isNull);
  });
}

const _a1 = SmlCellRef(0, 0);

SmlConditionalRule _rule({
  int? priority,
  String fill = '',
  String font = '',
  bool stop = false,
  String formula = 'TRUE',
  String range = 'A1',
}) => SmlConditionalRule(
  range: SmlRange.parse(range),
  kind: SmlConditionalKind.expression,
  formula: formula,
  fillRgb: fill,
  fontRgb: font,
  priority: priority,
  stopIfTrue: stop,
);
