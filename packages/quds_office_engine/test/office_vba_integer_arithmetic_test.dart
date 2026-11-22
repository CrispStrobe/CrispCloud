import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    moduleName: 'IntegerArithmetic',
    source: source,
  ),
);

OfficeMacro _body(String body) => _source('Sub Main()\n$body\nEnd Sub');

String _write(String expression) =>
    'Worksheets(1).Range("A1").Value2 = $expression';

Object? _value(String expression) =>
    _body(_write(expression)).steps.single.arguments['value'];

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'IntegerArithmetic')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0));

void _reject(String expression, String code) =>
    expect(() => _value(expression), throwsA(_error(code)), reason: expression);

void main() {
  // Source-based expectations and the explicitly documented bounded dialect;
  // these tests are not a record of execution by an installed Office host.
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/backslash-operator
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/mod-operator
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/operator-precedence
  // https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/98152b5a-4d86-4acb-b875-66cb1f49433e
  group('integer division and signed remainder', () {
    for (final (expression, expected) in <(String, int)>[
      (r'11 \ 4', 2),
      (r'9 \ 3', 3),
      (r'100 \ 3', 33),
      (r'-11 \ 4', -2),
      (r'11 \ -4', -2),
      (r'-11 \ -4', 2),
      (r'1 \ 4', 0),
      (r'-1 \ 4', 0),
      (r'5.5 \ 2', 3),
      (r'4.5 \ 2', 2),
      (r'-5.5 \ 2', -3),
      (r'-4.5 \ 2', -2),
      (r'7.5 \ 3.5', 2),
      (r'4.5 \ 2.5', 2),
      (r'12.6 \ -4.3', -3),
      (r'7 \ 0.6', 7),
      (r'7 \ -0.6', -7),
      ('10 Mod 5', 0),
      ('10 Mod 3', 1),
      ('12 Mod 4.3', 0),
      ('12.6 Mod 5', 3),
      ('19 Mod 6.7', 5),
      ('-11 Mod 4', -3),
      ('11 Mod -4', 3),
      ('-11 Mod -4', -3),
      ('5.5 Mod 4', 2),
      ('4.5 Mod 4', 0),
      ('-5.5 Mod 4', -2),
      ('-4.5 Mod 4', 0),
      ('-12.6 Mod 5', -3),
      ('7 Mod 0.6', 0),
      ('7 Mod -0.6', 0),
      (r'2147483647 \ 1', 2147483647),
      (r'-2147483648 \ 1', -2147483648),
      (r'-2147483648 \ -2', 1073741824),
      (r'2147483647 \ 2', 1073741823),
      (r'2147483647.49 \ 1', 2147483647),
      (r'-2147483648.5 \ 1', -2147483648),
      ('2147483647 Mod 3', 1),
      ('-2147483648 Mod 3', -2),
      ('-2147483648 Mod 2147483647', -1),
      ('2147483647 Mod -2147483648', 2147483647),
      ('-2147483648 Mod -1', 0),
      ('-2147483648 Mod -2147483648', 0),
      ('2147483647.49 Mod 2', 1),
      ('-2147483648.5 Mod 3', -2),
    ]) {
      test('$expression yields $expected', () {
        expect(_value(expression), expected);
      });
    }

    test('remainder follows dividend, bounds and quotient identity', () {
      // Cover all signs and signed Long edges independently of a native %
      // implementation: Dart's Euclidean modulo has a different sign rule.
      for (final dividend in [
        -2147483648,
        -2147483647,
        -101,
        -11,
        -1,
        0,
        1,
        11,
        101,
        2147483647,
      ]) {
        for (final divisor in [
          -2147483648,
          -101,
          -4,
          -1,
          1,
          4,
          101,
          2147483647,
        ]) {
          final remainder = _value('$dividend Mod $divisor')! as int;
          expect(remainder.abs(), lessThan(divisor.abs()));
          if (remainder != 0) {
            expect(remainder.isNegative, dividend.isNegative);
          }
          if (dividend == -2147483648 && divisor == -1) {
            expect(remainder, 0);
          } else {
            final quotient = _value('$dividend \\ $divisor')! as int;
            expect(quotient * divisor + remainder, dividend);
          }
        }
      }
    });

    test('zero results are normalized and Mod is case insensitive', () {
      for (final expression in [
        r'-0.0 \ 3',
        r'-1 \ 4',
        '-0.0 MoD 3',
        '-8 mOd 4',
      ]) {
        final value = _value(expression)! as num;
        expect(value, 0);
        expect(value.isNegative, isFalse);
      }
    });
  });

  group('VBA precedence and expression contexts', () {
    for (final (expression, expected) in <(String, Object)>[
      (r'20 \ 3 * 2', 3),
      (r'25 \ 4 / 2', 12),
      (r'20 Mod 6 \ 2', 2),
      (r'20 \ 3 Mod 4', 2),
      ('2 + 17 Mod 5 * 2', 9),
      (r'48 \ 4 \ 3', 4),
      ('20 Mod 6 Mod 3', 2),
      ('21 - 17 Mod 5', 19),
      (r'(20 \ 3) * 2', 12),
      (r'(20 Mod 6) \ 2', 1),
      (r'-9 \ 4', -2),
      (r'9 \ -4', -2),
      ('-7 Mod 4', -3),
      ('Not 5 Mod 2 = 1', false),
      (r'8 \ 3 = 2 And 9 Mod 4 = 1', true),
      (r'"P" & 7 \ 2 + 1', 'P4'),
    ]) {
      test('precedence: $expression', () {
        expect(_value(expression), expected);
      });
    }

    test(
      'Const, fixed array bounds and optional defaults use both operators',
      () {
        final plan = _source(r'''
Option Explicit
Const Width As Long = 14 \ 4
Const StartIndex As Long = 5 Mod Width
Sub Emit(Optional ByVal value As Long = 17 Mod Width)
  Worksheets(1).Range("B1").Value2 = value
End Sub
Sub Main()
  Dim values(StartIndex To Width + 2 Mod 2) As Long
  Dim index As Long
  values(2) = -9 \ 4
  values(3) = -9 Mod 4
  For index = LBound(values) To UBound(values)
    Worksheets(1).Cells(index, 1).Value2 = values(index)
  Next index
  Emit
End Sub
''');
        expect(plan.steps.map((step) => step.arguments['value']), [-2, -1, 2]);
      },
    );

    test('helper arguments, dynamic arrays and grouping loops compose', () {
      final plan = _source(r'''
Option Explicit
Function GroupOf(ByVal index As Long, ByVal width As Double) As Long
  GroupOf = (index - 1) \ width + 1
End Function
Sub Main()
  Dim values() As Long
  Dim index As Long
  ReDim values(0 To 11 \ 3 - 1)
  For index = 1 To 6
    values((index - 1) Mod 3) = GroupOf(width:=3, index:=index)
    Worksheets(1).Cells(index, 1).Value2 = values((index - 1) Mod 3)
  Next index
End Sub
''');
      expect(plan.steps.map((step) => step.arguments['value']), [
        1,
        1,
        1,
        2,
        2,
        2,
      ]);
    });

    for (final operator in [r'\', 'Mod']) {
      test('$operator evaluates operands exactly once, left to right', () {
        final plan = _source('''
Function LeftValue() As Long
  Worksheets(1).Range("B1").Value2 = "left"
  LeftValue = 11
End Function
Function RightValue() As Long
  Worksheets(1).Range("C1").Value2 = "right"
  RightValue = 4
End Function
Sub Main()
  ${_write('LeftValue() $operator RightValue()')}
End Sub
''');
        expect(plan.steps.map((step) => step.arguments['value']), [
          'left',
          'right',
          operator == r'\' ? 2 : 3,
        ]);
      });
    }
  });

  group('Variant states and bounded coercion', () {
    for (final operator in [r'\', 'Mod']) {
      test('$operator treats Empty as zero and accepts numeric Variants', () {
        expect(_value('Empty $operator 3'), 0);
        expect(_value('CVar(Empty) $operator 3'), 0);
        expect(_value('CVar(11.5) $operator CVar(5)'), 2);
        expect(
          _value('CDbl("-11") $operator CLng("4")'),
          operator == r'\' ? -2 : -3,
        );
        final plan = _body(
          'Dim value As Variant\n${_write('value $operator 3')}',
        );
        expect(plan.steps.single.arguments['value'], 0);
      });

      test(
        '$operator propagates Null through typed and nested expressions',
        () {
          for (final expression in [
            'Null $operator 3',
            '3 $operator Null',
            'Null $operator Null',
            'Null $operator Empty',
            'Null $operator 0',
            'Null $operator 0.5',
            'CVar(3) $operator CVar(Null)',
            'Null $operator 2147483648',
          ]) {
            expect(_value('IsNull($expression)'), true);
            expect(_value('IsNull(($expression) + 1)'), true);
          }
          _reject('Null $operator 3', 'vba_invalid_use_of_null');
          expect(
            () => _body('Dim result As Long\nresult = Null $operator 3'),
            throwsA(_error('vba_invalid_use_of_null')),
          );
        },
      );

      test('$operator still evaluates a right operand when left is Null', () {
        final plan = _source('''
Function RightValue() As Long
  Worksheets(1).Range("B1").Value2 = "right"
  RightValue = 0
End Function
Sub Main()
  ${_write('IsNull(Null $operator RightValue())')}
End Sub
''');
        expect(plan.steps.map((step) => step.arguments['value']), [
          'right',
          true,
        ]);
        _reject('Null $operator (1 / 0)', 'vba_arithmetic_error');
      });

      test('$operator requires explicit String and Boolean conversions', () {
        for (final value in [
          'True',
          'False',
          '"2"',
          'CVar(True)',
          'CVar("2")',
        ]) {
          _reject('$value $operator 2', 'vba_type_error');
          _reject('2 $operator $value', 'vba_type_error');
          _reject('Null $operator $value', 'vba_type_error');
          _reject('$value $operator Null', 'vba_type_error');
        }
      });

      test('$operator refuses an unhandled missing optional argument', () {
        expect(
          () => _source('''
Sub Helper(Optional ByVal value As Variant)
  ${_write('value $operator 2')}
End Sub
Sub Main()
  Helper
End Sub
'''),
          throwsA(_error('vba_missing_argument')),
        );
      });

      test('$operator rejects rounded zero divisors', () {
        for (final divisor in ['0', '-0.0', '0.5', '-0.5', '0.49', 'Empty']) {
          _reject('11 $operator $divisor', 'vba_arithmetic_error');
          _reject('0 $operator $divisor', 'vba_arithmetic_error');
        }
      });

      test('$operator bounds rounded operands before calculation', () {
        for (final value in [
          '2147483648',
          '-2147483649',
          '2147483647.5',
          '-2147483648.500001',
          '9007199254740991',
        ]) {
          _reject('$value $operator 1', 'vba_type_error');
          _reject('0 $operator $value', 'vba_type_error');
        }
        _reject('(9007199254740991 + 1) $operator 1', 'vba_limit_exceeded');
      });

      test(
        '$operator checks statically incompatible operands in dead code',
        () {
          for (final value in ['True', '"2"', 'Worksheets(1)']) {
            expect(
              () => _source('''
Sub Main()
End Sub
Sub Unused()
  Dim result As Variant
  Exit Sub
  result = $value $operator 2
End Sub
'''),
              throwsA(_error('vba_type_error')),
            );
          }
        },
      );

      test('$operator defers value-dependent failures in inactive paths', () {
        expect(
          _body('''
Dim result As Long
If False Then
  result = 11 $operator 0
  result = 2147483648 $operator 1
End If
${_write('7')}
''').steps.single.arguments['value'],
          7,
        );
      });

      test('$operator failure after a write never returns a partial plan', () {
        expect(
          () => _body('${_write('"earlier"')}\n${_write('11 $operator 0')}'),
          throwsA(_error('vba_arithmetic_error')),
        );
      });
    }

    test('integer division refuses the signed Long quotient overflow', () {
      _reject(r'-2147483648 \ -1', 'vba_type_error');
      _reject(r'CVar(-2147483648) \ CVar(-1)', 'vba_type_error');
      expect(_value('-2147483648 Mod -1'), 0);
    });

    test('Mod is a reserved operator and cannot be shadowed', () {
      for (final source in [
        'Sub Main()\nDim Mod As Long\nEnd Sub',
        'Sub Main()\nEnd Sub\nSub Mod()\nEnd Sub',
        'Sub Main()\nEnd Sub\nSub Helper(ByVal Mod As Long)\nEnd Sub',
      ]) {
        expect(() => _source(source), throwsA(_error('vba_name_error')));
      }
    });

    test('arithmetic remains charged against the shared work budget', () {
      expect(
        () => _body(r'''
Dim index As Long, result As Long
For index = 1 To 100000
  result = (index \ 3) Mod 2
Next index
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('positioned zero-division diagnostic names the operator', () {
      expect(
        () => _source(
          'Sub Main()\nDim result As Long\nresult = 5 Mod 0.5\nEnd Sub',
        ),
        throwsA(
          _error('vba_arithmetic_error')
              .having((error) => error.line, 'operator line', 3)
              .having((error) => error.column, 'operator column', 12)
              .having(
                (error) => error.message,
                'reason',
                contains('Mod by zero'),
              ),
        ),
      );
    });
  });

  group('shared Word and PowerPoint adapters', () {
    test('Word groups source rows into existing table selectors', () {
      final plan = const OfficeVbaWordMacroLanguage().compile(
        OfficeMacroSource(
          language: 'vba-word',
          format: OfficeMacroFormat.docx,
          source: r'''
Sub Main()
  Dim index As Long
  For index = 0 To 3
    ActiveDocument.Tables(1).Cell(index \ 2 + 1, index Mod 2 + 1).Range.Text = CStr(index)
  Next index
End Sub
''',
        ),
      );
      expect(
        plan.steps.map((step) => step.tool),
        everyElement('docx.tableCellRangeText'),
      );
      expect(plan.steps.map((step) => step.arguments), [
        {'table': 0, 'row': 0, 'column': 0, 'text': '0'},
        {'table': 0, 'row': 0, 'column': 1, 'text': '1'},
        {'table': 0, 'row': 1, 'column': 0, 'text': '2'},
        {'table': 0, 'row': 1, 'column': 1, 'text': '3'},
      ]);
    });

    test('PowerPoint uses the same arithmetic to build source text', () {
      final plan = const OfficeVbaPowerPointMacroLanguage().compile(
        OfficeMacroSource(
          language: 'vba-powerpoint',
          format: OfficeMacroFormat.pptx,
          source: r'''
Sub Main()
  ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text = CStr(11 \ 4) & ":" & CStr(-11 Mod 4)
End Sub
''',
        ),
      );
      expect(plan.steps.single.arguments['text'], '2:-3');
    });
  });
}
