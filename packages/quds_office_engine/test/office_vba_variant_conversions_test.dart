import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    source: source,
    moduleName: 'Variants',
  ),
);

String _module(String body) => 'Sub Main()\n$body\nEnd Sub';

String _write(String expression) =>
    'Worksheets(1).Range("A1").Value2 = $expression';

List<Object?> _values(OfficeMacro macro) => <Object?>[
  for (final step in macro.steps) step.arguments['value'],
];

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>().having(
      (error) => error.code,
      'code',
      code,
    );

void _reject(String body, String code) =>
    expect(() => _compile(_module(body)), throwsA(_error(code)), reason: body);

void main() {
  group('nullable operator composition', () {
    final expressions = <(String, String, String)>[
      ('(Null & Null) + 1', 'Null & Null', 'value + 1'),
      ('(Null + 1) And True', 'Null + 1', 'value And True'),
      ('(Null = Null) + 1', 'Null = Null', 'value + 1'),
      ('Not (Null & Null)', 'Null & Null', 'Not value'),
      ('(Null + 1) = "x"', 'Null + 1', 'value = "x"'),
      ('(-Null) = "x"', '-Null', 'value = "x"'),
      ('(Null Xor True) * 2', 'Null Xor True', 'value * 2'),
    ];
    for (final (nested, intermediate, assigned) in expressions) {
      test('nested $nested agrees with a Variant intermediate', () {
        final plan = _compile(
          _module('''
Dim value As Variant
value = $intermediate
Worksheets(1).Range("A1").Value2 = IsNull($nested)
Worksheets(1).Range("A2").Value2 = IsNull($assigned)
'''),
        );
        expect(_values(plan), <Object?>[true, true]);
      });
    }
    for (final expression in <String>[
      'Null + "bad"',
      '"bad" * Null',
      'True And 1',
      'Null Or "bad"',
      '1 = "bad"',
      '-"bad"',
      'Not 1',
      'Worksheets(1) & Null',
    ]) {
      test(
        'known invalid operand remains checked in unused code: $expression',
        () {
          expect(
            () => _compile('''
Sub Main()
End Sub
Sub Unused()
  Dim value As Variant
  Exit Sub
  value = $expression
End Sub
'''),
            throwsA(_error('vba_type_error')),
          );
        },
      );
    }
    test(
      'non-Null Variant arithmetic still enforces runtime operand types',
      () {
        _reject('''
Dim value As Variant
value = 1
${_write('(value + 1) = "bad"')}
''', 'vba_type_error');
        _reject(_write('(Empty + 1) And True'), 'vba_type_error');
      },
    );
  });

  group('scalar Variant object boundaries', () {
    for (final type in <String>['Worksheet', 'Range']) {
      for (final value in <String>['Empty', 'Null', 'CVar(Empty)', 'scalar']) {
        test('$type Set rejects scalar $value even after an unused exit', () {
          expect(
            () => _compile('''
Sub Main()
End Sub
Sub Unused()
  Dim target As $type, scalar As Variant
  Exit Sub
  Set target = $value
End Sub
'''),
            throwsA(_error('vba_type_error')),
          );
        });
        test('$type ByVal rejects scalar $value in an unused procedure', () {
          expect(
            () => _compile('''
Sub Main()
End Sub
Sub Unused()
  Dim scalar As Variant
  Call Typed($value)
End Sub
Sub Typed(ByVal target As $type)
End Sub
'''),
            throwsA(_error('vba_type_error')),
          );
        });
      }
    }
    test('ordinary Worksheet and Range bindings still pass ByVal', () {
      final plan = _compile('''
Sub Main()
  Dim sheet As Worksheet, cell As Range
  Set sheet = Worksheets(1)
  Set cell = sheet.Range("A1")
  Call Typed(sheet, cell)
End Sub
Sub Typed(ByVal sheet As Worksheet, ByVal cell As Range)
  cell.Value2 = 42
  sheet.Range("A2").Value2 = "bound"
End Sub
''');
      expect(_values(plan), <Object?>[42, 'bound']);
    });
  });

  group('Variant states and lifetime', () {
    final predicates = <(String, Object?)>[
      ('IsEmpty(Empty)', true),
      ('IsEmpty(Null)', false),
      ('IsNull(Null)', true),
      ('IsNull(Empty)', false),
      ('IsEmpty(0)', false),
      ('IsEmpty(False)', false),
      ('IsEmpty("")', false),
      ('IsNull(0)', false),
      ('IsNull(False)', false),
      ('IsNull("")', false),
      ('iSeMpTy(cVaR(eMpTy))', true),
      ('iSnUlL(cVaR(nUlL))', true),
      ('CVar(7)', 7),
      ('CVar("seven")', 'seven'),
      ('CVar(True)', true),
      ('CVar(Empty)', null),
    ];
    for (final (expression, expected) in predicates) {
      test(expression, () {
        expect(_values(_compile(_module(_write(expression)))), <Object?>[
          expected,
        ]);
      });
    }

    test('declared and implicit Variant locals start as Empty', () {
      final macro = _compile(
        _module('''
Dim declared As Variant, inferred
Worksheets(1).Range("A1").Value2 = IsEmpty(declared)
Worksheets(1).Range("A2").Value2 = IsEmpty(inferred)
Worksheets(1).Range("A3").Value2 = IsEmpty(later)
later = Null
Worksheets(1).Range("A4").Value2 = IsNull(later)
declared = ""
Worksheets(1).Range("A5").Value2 = IsEmpty(declared)
declared = Empty
Worksheets(1).Range("A6").Value2 = IsEmpty(declared)
'''),
      );
      expect(_values(macro), <Object?>[true, true, true, true, false, true]);
    });

    test('Empty converts only at a declared typed scalar assignment', () {
      final macro = _compile(
        _module('''
Dim count As Long, amount As Double, text As String, flag As Boolean
count = 9: amount = 2.5: text = "old": flag = True
count = Empty: amount = Empty: text = Empty: flag = Empty
Worksheets(1).Range("A1").Value2 = count
Worksheets(1).Range("A2").Value2 = amount
Worksheets(1).Range("A3").Value2 = text
Worksheets(1).Range("A4").Value2 = flag
'''),
      );
      expect(_values(macro), <Object?>[0, 0.0, '', false]);
    });

    test(
      'Variant returns and ByVal state bindings have independent lifetime',
      () {
        final macro = _compile('''
Sub Main()
  Dim original As Variant
  original = Null
  Worksheets(1).Range("A1").Value2 = IsEmpty(DefaultValue())
  Worksheets(1).Range("A2").Value2 = IsNull(ChangeValue(original))
  Worksheets(1).Range("A3").Value2 = IsNull(original)
  Call EmptyParameters(Empty, Empty, Empty, Empty)
  Worksheets(1).Range("A4").Value2 = IsEmpty(FreshLocal())
  Worksheets(1).Range("A5").Value2 = IsEmpty(FreshLocal())
End Sub
Function DefaultValue()
End Function
Function ChangeValue(ByVal value As Variant)
  ChangeValue = value
  value = Empty
End Function
Function FreshLocal()
  Dim local As Variant
  FreshLocal = local
  local = Null
End Function
Sub EmptyParameters(ByVal count As Long, ByVal amount As Double, ByVal text As String, ByVal flag As Boolean)
  Worksheets(1).Range("B1").Value2 = count
  Worksheets(1).Range("B2").Value2 = amount
  Worksheets(1).Range("B3").Value2 = text
  Worksheets(1).Range("B4").Value2 = flag
End Sub
''');
        expect(_values(macro), <Object?>[
          true,
          true,
          true,
          0,
          0.0,
          '',
          false,
          true,
          true,
        ]);
      },
    );

    test(
      'Variant arrays preserve states and initialize new slots as Empty',
      () {
        final macro = _compile(
          _module('''
Dim fixed(1 To 2) As Variant, data() As Variant, item As Variant
Dim count As Long
fixed(1) = Null
For Each item In fixed
  If IsEmpty(item) Then
    count = count + 1
  End If
Next item
Worksheets(1).Range("A1").Value2 = count
Erase fixed
Worksheets(1).Range("A2").Value2 = IsEmpty(fixed(1))
ReDim data(1 To 2)
data(1) = Null
data(2) = "discard"
ReDim Preserve data(1 To 1)
ReDim Preserve data(1 To 3)
Worksheets(1).Range("A3").Value2 = IsNull(data(1))
Worksheets(1).Range("A4").Value2 = IsEmpty(data(2))
Worksheets(1).Range("A5").Value2 = IsEmpty(data(3))
ReDim data(1 To 3)
Worksheets(1).Range("A6").Value2 = IsEmpty(data(1))
Erase data
ReDim Preserve data(4 To 4)
Worksheets(1).Range("A7").Value2 = IsEmpty(data(4))
'''),
        );
        expect(_values(macro), <Object?>[
          1,
          true,
          true,
          true,
          true,
          true,
          true,
        ]);
      },
    );

    test(
      'Empty cell writes lower to native clear and round-trip without sentinels',
      () {
        final macro = _compile(
          _module('''
Dim value As Variant
Worksheets(1).Range("A1:B2").Value2 = value
Worksheets(1).Range("C1").Value = CVar(Empty)
'''),
        );
        expect(macro.steps, hasLength(5));
        expect(_values(macro), everyElement(isNull));
        final saved = OfficeMacro.parse(
          utf8.decode(utf8.encode(macro.encode())),
        );
        expect(saved.toJson(), macro.toJson());
        expect(macro.encode(), isNot(contains('_VariantState')));
      },
    );
  });

  group('explicit scalar conversion results', () {
    final conversions = <(String, Object)>[
      ('CBool(Empty)', false),
      ('CBool(0)', false),
      ('CBool(-0.0)', false),
      ('CBool(0.01)', true),
      ('CBool(-3)', true),
      ('CBool(True)', true),
      ('CBool(" true ")', true),
      ('CBool("FaLsE")', false),
      ('CBool("-0e30")', false),
      ('CBool(".5")', true),
      ('CDbl(Empty)', 0),
      ('CDbl(True)', -1),
      ('CDbl(False)', 0),
      ('CDbl(7)', 7),
      ('CDbl("  +1.25e2  ")', 125),
      ('CDbl("-.5")', -0.5),
      ('CDbl("1.")', 1),
      ('CDbl("00017")', 17),
      ('CDbl("1e-7")', 0.0000001),
      ('CLng(Empty)', 0),
      ('CLng(True)', -1),
      ('CLng(False)', 0),
      ('CLng(0.5)', 0),
      ('CLng(-0.5)', 0),
      ('CLng(1.5)', 2),
      ('CLng(2.5)', 2),
      ('CLng(-1.5)', -2),
      ('CLng(-2.5)', -2),
      ('CLng(3.5)', 4),
      ('CLng(-3.5)', -4),
      ('CLng(2.4999999999999996)', 2),
      ('CLng(2.5000000000000004)', 3),
      ('CLng(-2.4999999999999996)', -2),
      ('CLng(-2.5000000000000004)', -3),
      ('CLng(" 2.5 ")', 2),
      ('CLng("-3.5")', -4),
      ('CLng(2147483647.4)', 2147483647),
      ('CLng(-2147483648.5)', -2147483648),
      ('CStr(Empty)', ''),
      ('CStr("")', ''),
      ('CStr("A😀B")', 'A😀B'),
      ('CStr(True)', 'True'),
      ('CStr(False)', 'False'),
      ('CStr(-0.0)', '0'),
      ('CStr(12.0)', '12'),
      ('CStr(-125)', '-125'),
      ('CStr(0.1)', '0.1'),
      ('CStr(1.2345)', '1.2345'),
      ('CStr(0.000001)', '0.000001'),
      ('CStr(0.0000001)', '1e-7'),
      ('CStr(-0.0000001)', '-1e-7'),
      ('CStr(0.10000000000000002)', '0.10000000000000002'),
      ('CStr(9007199254740991)', '9007199254740991'),
      ('CStr(CDbl("4.9406564584124654e-324"))', '5e-324'),
      ('CStr(CDbl("2.2250738585072014e-308"))', '2.2250738585072014e-308'),
      // The input rounds to binary64 0x000ced42ec885d9d; its nearest
      // shortest decimal spelling differs from the supplied decimal text.
      ('CStr(CDbl("1.7976931348623157e-308"))', '1.7976931348623155e-308'),
    ];
    for (final (expression, expected) in conversions) {
      test(expression, () {
        expect(_values(_compile(_module(_write(expression)))), <Object?>[
          expected,
        ]);
      });
    }

    test(
      'accepts all ASCII surrounding whitespace but no Unicode trimming',
      () {
        for (final whitespace in <String>['\t', '\u000B', '\f', ' ']) {
          expect(
            _values(
              _compile(_module(_write('CDbl("${whitespace}2.5$whitespace")'))),
            ),
            <Object?>[2.5],
          );
        }
        _reject(_write('CDbl("\u00a02.5\u00a0")'), 'vba_type_error');
        _reject(_write('CDbl("2.5\u2028")'), 'vba_type_error');
        _reject(_write('CDbl("2.5\u2029")'), 'vba_type_error');
      },
    );

    test('converts each function argument once in source order', () {
      final macro = _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = CStr(CLng(NumberText())) & CStr(IsNull(MissingValue()))
End Sub
Function NumberText() As String
  Worksheets(1).Range("B1").Value2 = "number"
  NumberText = "2.5"
End Function
Function MissingValue() As Variant
  Worksheets(1).Range("B2").Value2 = "missing"
  MissingValue = Null
End Function
''');
      expect(_values(macro), <Object?>['number', 'missing', '2True']);
    });
  });

  group('state operators and conditions', () {
    final operators = <(String, Object)>[
      ('Empty + 4', 4),
      ('4 + Empty', 4),
      ('Empty - 4', -4),
      ('Empty * 4', 0),
      ('Empty / 4', 0),
      ('+Empty', 0),
      ('-Empty', 0),
      ('Empty = 0', true),
      ('Empty = ""', true),
      ('Empty = False', true),
      ('Empty = Empty', true),
      ('Empty <> "x"', true),
      ('Empty < "a"', true),
      ('True < Empty', true),
      ('IsNull(Null + 1)', true),
      ('IsNull(1 - Null)', true),
      ('IsNull(Null * Empty)', true),
      ('IsNull(Null / 0)', true),
      ('IsNull(+Null)', true),
      ('IsNull(-Null)', true),
      ('Empty & "x"', 'x'),
      ('"x" & Empty', 'x'),
      ('Null & "x"', 'x'),
      ('"x" & Null', 'x'),
      ('Null & Empty', ''),
      ('Empty & Null', ''),
      ('IsNull(Null & Null)', true),
      ('IsNull(Not Null)', true),
      ('False And Null', false),
      ('Null And False', false),
      ('IsNull(True And Null)', true),
      ('IsNull(Null And True)', true),
      ('IsNull(Null And Null)', true),
      ('True Or Null', true),
      ('Null Or True', true),
      ('IsNull(False Or Null)', true),
      ('IsNull(Null Or False)', true),
      ('IsNull(Null Or Null)', true),
      ('IsNull(True Xor Null)', true),
      ('IsNull(Null Xor False)', true),
      ('IsNull(Null Xor Null)', true),
      ('Not CBool(Empty)', true),
    ];
    for (final (expression, expected) in operators) {
      test(expression, () {
        expect(_values(_compile(_module(_write(expression)))), <Object?>[
          expected,
        ]);
      });
    }
    for (final operator in <String>['=', '<>', '<', '>', '<=', '>=']) {
      for (final expression in <String>[
        'Null $operator Null',
        'Null $operator 0',
        '"x" $operator Null',
      ]) {
        test('IsNull($expression)', () {
          expect(
            _values(_compile(_module(_write('IsNull($expression)')))),
            <Object?>[true],
          );
        });
      }
    }

    test('Null and Empty conditions are false without typed Null coercion', () {
      final macro = _compile(
        _module('''
Dim count As Long
If Null Then
  count = 999
ElseIf Empty Then
  count = 999
Else
  count = 1
End If
Do While Null
  count = 999
Loop
While Empty
  count = 999
Wend
Do
  count = count + 1
Loop While Null
Do Until Empty
  count = count + 1
  If count = 4 Then
    Exit Do
  End If
Loop
Worksheets(1).Range("A1").Value2 = count
'''),
      );
      expect(_values(macro), <Object?>[4]);
    });

    test('Null Case ranges evaluate both endpoints and never match', () {
      final macro = _compile('''
Sub Main()
  Select Case 5
    Case Low() To High()
      Worksheets(1).Range("A1").Value2 = "wrong"
    Case Else
      Worksheets(1).Range("A1").Value2 = "fallback"
  End Select
  Select Case Empty
    Case 0 To 0
      Worksheets(1).Range("A2").Value2 = "zero"
  End Select
  Select Case Empty
    Case "" To "z"
      Worksheets(1).Range("A3").Value2 = "text"
  End Select
End Sub
Function Low()
  Worksheets(1).Range("B1").Value2 = "lower"
  Low = Null
End Function
Function High()
  Worksheets(1).Range("B2").Value2 = "upper"
  High = 10
End Function
''');
      expect(_values(macro), <Object?>[
        'lower',
        'upper',
        'fallback',
        'zero',
        'text',
      ]);
    });

    test('Boolean Null logic remains eager even when the result is known', () {
      final macro = _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = False And MissingValue()
  Worksheets(1).Range("A2").Value2 = True Or MissingValue()
End Sub
Function MissingValue()
  Worksheets(1).Range("B1").Value2 = "called"
  MissingValue = Null
End Function
''');
      expect(_values(macro), <Object?>['called', false, 'called', true]);
      _reject(_write('False And CBool(Null)'), 'vba_invalid_use_of_null');
      _reject(_write('True Or CBool(Null)'), 'vba_invalid_use_of_null');
    });
  });

  group('conversion and state diagnostics', () {
    for (final name in <String>['CBool', 'CDbl', 'CLng', 'CStr']) {
      test('$name refuses Null at the argument position', () {
        final source = _module(_write('$name(Null)'));
        expect(
          () => _compile(source),
          throwsA(
            _error('vba_invalid_use_of_null')
                .having((e) => e.line, 'line', 2)
                .having(
                  (e) => e.column,
                  'column',
                  source.split('\n')[1].indexOf('Null') + 1,
                ),
          ),
        );
      });
    }
    for (final type in <String>['Long', 'Double', 'String', 'Boolean']) {
      test('$type rejects Null assignment and argument binding', () {
        _reject('Dim value As $type\nvalue = Null', 'vba_invalid_use_of_null');
        expect(
          () => _compile('''
Sub Main()
  Call Typed(Null)
End Sub
Sub Typed(ByVal value As $type)
End Sub
'''),
          throwsA(_error('vba_invalid_use_of_null')),
        );
      });
    }
    for (final expression in <String>[
      'Null',
      'CVar(Null)',
      'Null + 1',
      'Null & Null',
      'Null = Null',
    ]) {
      test('native publication rejects $expression', () {
        _reject(_write(expression), 'vba_invalid_use_of_null');
      });
    }
    for (final expression in <String>[
      'CLng(2147483647.5)',
      'CLng(-2147483648.6)',
      'CLng(2147483648)',
      'CLng(-2147483649)',
      'CDbl("")',
      'CDbl(" ")',
      'CDbl("1,25")',
      'CDbl("1,000")',
      'CDbl("0x10")',
      'CDbl("&H10")',
      'CDbl("NaN")',
      'CDbl("Infinity")',
      'CDbl("1 2")',
      'CDbl("+ 1")',
      'CDbl("12xyz")',
      'CDbl("1e")',
      'CDbl("True")',
      'CBool("yes")',
      'CBool("Falsex")',
      'Not Empty',
      'Empty And True',
      'False And Empty',
      'True Or Empty',
      'Empty Xor Null',
      'Null And Empty',
      'Len(Empty)',
      'Len(Null)',
      r'Left$(Empty, 1)',
      r'Right$("a", Empty)',
      'Worksheets(Empty).Range("A1").Row',
      'RGB(Empty, 0, 0)',
    ]) {
      test('strict refusal $expression', () {
        _reject(_write(expression), 'vba_type_error');
      });
    }
    for (final expression in <String>[
      'CDbl("1e309")',
      'CDbl("9007199254740992")',
      'CLng("1e309")',
      'CBool("1e309")',
    ]) {
      test('portable bound $expression', () {
        _reject(_write(expression), 'vba_limit_exceeded');
      });
    }
    test('Null does not admit unsupported arithmetic operands', () {
      _reject(
        'Dim value As Variant\nvalue = "text"\n${_write('Null + value')}',
        'vba_type_error',
      );
      _reject(
        'Dim value As Variant\nvalue = True\n${_write('value * Null')}',
        'vba_type_error',
      );
    });
    test('explicit conversions do not change implicit scalar typing', () {
      _reject('Dim count As Long\ncount = 2.5', 'vba_type_error');
      _reject('Dim amount As Double\namount = "1.5"', 'vba_type_error');
      _reject('Dim flag As Boolean\nflag = 1', 'vba_type_error');
      _reject(_write('1 + "2"'), 'vba_type_error');
    });
    test('unbound objects still fail instead of becoming Empty', () {
      _reject(
        'Dim sheet As Worksheet\nsheet.Range("A1").Value2 = 1',
        'vba_unsupported',
      );
    });
    for (final name in <String>[
      'IsEmpty',
      'IsNull',
      'CBool',
      'CDbl',
      'CLng',
      'CStr',
      'CVar',
    ]) {
      test('$name is checked in unused code and cannot shadow a builtin', () {
        for (final expression in <String>[
          '$name()',
          '$name(1, 2)',
          '$name(Worksheets(1))',
          '$name(Worksheets(1).Range("A1"))',
        ]) {
          expect(
            () => _compile(
              'Sub Main()\nEnd Sub\nSub Unused()\n${_write(expression)}\nEnd Sub',
            ),
            throwsA(_error('vba_type_error')),
            reason: expression,
          );
        }
        _reject('Dim $name As Variant', 'vba_name_error');
        _reject(
          'Dim data(0) As Variant\n${_write('$name(data)')}',
          'vba_type_error',
        );
      });
    }
    for (final initializer in <String>['Empty', 'Null', 'CVar(1)', 'CLng(1)']) {
      test('constant restriction $initializer', () {
        _reject('Const value = $initializer', 'vba_unsupported');
      });
    }
    test('conversion work is shared across repeated calls and arguments', () {
      for (final conversion in <String>['CDbl', 'CBool', 'CStr']) {
        _reject('''
Dim text As String, index As Long, value As Variant
text = "0"
For index = 1 To 14
  text = text & text
Next index
For index = 1 To 8
  value = $conversion(text)
Next index
''', 'vba_limit_exceeded');
      }
    });
    test(
      'conversion preserves malformed internal UTF-16 until native refusal',
      () {
        expect(
          _values(_compile(_module(_write(r'Len(CStr(Left$("😀", 1)))')))),
          <Object?>[1],
        );
        _reject(_write(r'CStr(Left$("😀", 1))'), 'vba_type_error');
      },
    );
  });
}
