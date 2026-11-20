import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    source: source,
    moduleName: 'Strings',
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
  group('String intrinsic results', () {
    final cases = <(String, Object)>[
      ('Len("")', 0),
      ('Len("Hello")', 5),
      ('Len("a""b")', 3),
      (r'Left$("Hello", 2)', 'He'),
      (r'Right$("Hello", 2)', 'lo'),
      (r'Mid$("Hello", 2, 3)', 'ell'),
      (r'Left$("", 1)', ''),
      (r'Right$("", 1)', ''),
      (r'Mid$("", 1)', ''),
      (r'Left$("Hello", 0)', ''),
      (r'Right$("Hello", 0)', ''),
      (r'Mid$("Hello", 1, 0)', ''),
      (r'Left$("Hello", 2147483647)', 'Hello'),
      (r'Right$("Hello", 2147483647)', 'Hello'),
      (r'Mid$("Hello", 3, 2147483647)', 'llo'),
      (r'Mid$("Hello", 1)', 'Hello'),
      (r'Mid$("Hello", 3)', 'llo'),
      (r'Mid$("Hello", 5)', 'o'),
      (r'Mid$("Hello", 6)', ''),
      (r'Mid$("Hello", 2147483647)', ''),
      (r'Mid$("Hello", 2147483647, 2147483647)', ''),
      (r'Mid$("a""b", 2, 1)', '"'),
      (r'Left$("Hello", 2.0)', 'He'),
      (r'Right$("Hello", -0)', ''),
      (r'lEn(lEfT$(rIgHt$(mId$("abcdef", 2), 4), 3))', 3),
      ('Len("A😀B")', 4),
      (r'Mid$("A😀B", 2, 2)', '😀'),
      (r'Left$("A😀B", 3)', 'A😀'),
      (r'Right$("A😀B", 3)', '😀B'),
      (r'Len(Left$("😀", 1))', 1),
      (r'Len(Right$("😀", 1))', 1),
      ('Len("e\u0301")', 2),
      (r'Left$("東京", 1)', '東'),
      ('Len("a\u0000b")', 3),
    ];
    for (final (expression, expected) in cases) {
      test(expression, () {
        expect(_values(_compile(_module(_write(expression)))), <Object?>[
          expected,
        ]);
      });
    }

    test(
      'recombines internal UTF-16 halves before native plan publication',
      () {
        final macro = _compile(
          _module(r'''
Dim high As String, low As String, parts(0 To 1) As String
high = Left$("😀", 1)
low = Right$("😀", 1)
parts(0) = Mid$("A😀B", 2, 1)
parts(1) = Mid$("A😀B", 3, 1)
Worksheets(1).Range("A1").Value2 = Len(high)
Worksheets(1).Range("A2").Value2 = Len(low)
Worksheets(1).Range("A3").Value2 = high & low
Worksheets(1).Range("A4").Value2 = "A" & parts(0) & parts(1) & "B"
'''),
        );
        final saved = OfficeMacro.parse(
          utf8.decode(utf8.encode(macro.encode())),
        );
        for (final plan in <OfficeMacro>[macro, saved]) {
          expect(_values(plan), <Object?>[1, 1, '😀', 'A😀B']);
        }
      },
    );

    test(
      'accepts String and exact-number Variant values and array elements',
      () {
        final macro = _compile(
          _module(r'''
Dim text As String, value As Variant, count As Variant
Dim parts(1 To 2) As String, numbers(1 To 2) As Long
text = "abcdef"
value = text
count = 2.0
parts(1) = Left$(value, count)
parts(2) = Right$(text, count + 1)
numbers(1) = Len(parts(1))
numbers(2) = 3
Worksheets(1).Range("A1").Value2 = Mid$(parts(2), numbers(1))
Worksheets(1).Range("A2").Value2 = Len(Mid$(value, numbers(2)))
'''),
        );
        expect(_values(macro), <Object?>['ef', 4]);
      },
    );

    test('evaluates helper arguments once from left to right', () {
      final macro = _compile(r'''
Sub Main()
  Worksheets(1).Range("A1").Value2 = Mid$(TextValue(), StartValue(), CountValue())
  Worksheets(1).Range("A2").Value2 = Left$(TextValue(), ZeroValue())
  Worksheets(1).Range("A3").Value2 = Mid$(TextValue(), PastEnd(), CountValue())
End Sub
Function TextValue() As String
  Worksheets(1).Range("Z1").Value2 = "text"
  TextValue = "abcdef"
End Function
Function StartValue() As Long
  Worksheets(1).Range("Z2").Value2 = "start"
  StartValue = 2
End Function
Function CountValue() As Long
  Worksheets(1).Range("Z3").Value2 = "count"
  CountValue = 3
End Function
Function ZeroValue() As Long
  Worksheets(1).Range("Z4").Value2 = "zero"
  ZeroValue = 0
End Function
Function PastEnd() As Long
  Worksheets(1).Range("Z5").Value2 = "past"
  PastEnd = 99
End Function
''');
      expect(_values(macro), <Object?>[
        'text',
        'start',
        'count',
        'bcd',
        'text',
        'zero',
        '',
        'text',
        'past',
        'count',
        '',
      ]);
    });

    test('returns slices through functions without changing caller values', () {
      final macro = _compile(r'''
Sub Main()
  Dim original As String
  original = "ABC-123-END"
  Worksheets(1).Range("A1").Value2 = CodePart(original)
  Worksheets(1).Range("A2").Value2 = original
End Sub
Function CodePart(ByVal text As String) As String
  text = Mid$(text, 5, 3)
  CodePart = text
End Function
''');
      expect(_values(macro), <Object?>['123', 'ABC-123-END']);
    });
  });

  group('String intrinsic diagnostics', () {
    final expressions = <String>[
      'Len()',
      'Len("a", 1)',
      r'Left$("a")',
      r'Left$("a", 1, 2)',
      r'Right$()',
      r'Right$("a", 1, 2)',
      r'Mid$("a")',
      r'Mid$("a", 1, 2, 3)',
      'Len(42)',
      'Len(True)',
      'Len(Worksheets(1))',
      r'Left$(42, 1)',
      r'Right$(True, 1)',
      r'Mid$(Worksheets(1).Range("A1"), 1)',
      r'Left$("a", "1")',
      r'Right$("a", True)',
      r'Mid$("a", "1")',
      r'Mid$("a", 1, False)',
      r'Left$("a", -1)',
      r'Right$("", -1)',
      r'Mid$("a", 0)',
      r'Mid$("a", -1)',
      r'Mid$("a", 99, -1)',
      r'Left$("a", 1.5)',
      r'Right$("a", 2.5)',
      r'Mid$("a", 1.5)',
      r'Mid$("a", 1, 1.5)',
      r'Left$("a", 2147483648)',
      r'Right$("a", 2147483648)',
      r'Mid$("a", 2147483648)',
      r'Mid$("a", 1, 2147483648)',
      r'Mid$("a", 2147483647, 2147483648)',
    ];
    for (final expression in expressions) {
      test('rejects $expression', () {
        _reject(_write(expression), 'vba_type_error');
      });
    }

    test('preserves exact source and module positions for runtime errors', () {
      const body = r'  result = Mid$("😀", 5, -1)';
      expect(
        () => _compile(_module(body)),
        throwsA(
          _error('vba_type_error')
              .having((error) => error.moduleName, 'module', 'Strings')
              .having((error) => error.entryPoint, 'entry', 'Main')
              .having((error) => error.line, 'line', 2)
              .having(
                (error) => error.column,
                'UTF-16 column',
                body.indexOf('-1') + 1,
              ),
        ),
      );
    });

    test('checks static types and arity in inactive and unused code', () {
      _reject(r'''
If False Then
  result = Left$("a", True)
End If
''', 'vba_type_error');
      expect(
        () => _compile(r'''
Sub Main()
End Sub
Sub Unused()
  result = Mid$("a")
End Sub
'''),
        throwsA(_error('vba_type_error')),
      );
    });

    test('keeps helper call-graph checks inside intrinsic arguments', () {
      expect(
        () => _compile(r'''
Sub Main()
End Sub
Function Recursive() As String
  Recursive = Left$(Recursive(), 1)
End Function
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('checks the runtime contents of Variant arguments', () {
      for (final expression in <String>[
        'Len(value)',
        r'Left$(value, 1)',
        r'Right$("abc", value)',
        r'Mid$("abc", 99, value)',
      ]) {
        final assigned = expression.contains('(value') ? '42' : '"1"';
        _reject(
          'Dim value As Variant\nvalue = $assigned\n${_write(expression)}',
          'vba_type_error',
        );
      }
      _reject(
        'Dim value As Variant\n${_write('Len(value)')}',
        'vba_type_error',
      );
    });

    test('does not admit whole arrays as intrinsic arguments', () {
      _reject('Dim texts(1) As String\nresult = Len(texts)', 'vba_type_error');
    });

    test('reserves exact intrinsic names for variables and procedures', () {
      for (final name in <String>['Len', r'Left$', r'Right$', r'Mid$']) {
        _reject('Dim $name As String', 'vba_name_error');
        expect(
          () => _compile(
            'Sub Main()\nEnd Sub\nFunction $name() As String\nEnd Function',
          ),
          throwsA(_error('vba_name_error')),
          reason: name,
        );
      }
    });

    test('refuses unsupported neighboring functions and variable suffixes', () {
      for (final expression in <String>[
        'Left("abc", 1)',
        'Right("abc", 1)',
        'Mid("abc", 1)',
        'LenB("abc")',
        r'LeftB$("abc", 1)',
        r'RightB$("abc", 1)',
        r'MidB$("abc", 1)',
        r'Len$("abc")',
        r'Left$$("abc", 1)',
      ]) {
        _reject(_write(expression), 'vba_unsupported');
      }
      _reject(r'Dim title$ As String', 'vba_unsupported');
      _reject(r'Dim text As String: text$ = "value"', 'vba_unsupported');
      _reject(r'Call Left$("abc", 1)', 'vba_unsupported');
    });

    test(
      'does not introduce constant-function evaluation or omitted arguments',
      () {
        _reject(r'Const value As String = Left$("abc", 1)', 'vba_unsupported');
        _reject('Dim values(0 To Len("abc")) As Long', 'vba_unsupported');
        _reject(_write(r'Mid$("abc",,1)'), 'vba_syntax_error');
        _reject(_write(r'Mid$("abc",1,)'), 'vba_syntax_error');
      },
    );
  });

  group('lossless native spreadsheet text boundary', () {
    for (final expression in <String>[
      r'Left$("😀", 1)',
      r'Right$("😀", 1)',
      r'Mid$("A😀B", 2, 1)',
      r'Mid$("A😀B", 3, 1)',
      r'Left$("😀", 1) & "x"',
      r'"x" & Right$("😀", 1)',
      r'Right$("😀", 1) & Left$("😀", 1)',
      r'"😀" & Left$("😀", 1)',
      r'Right$("😀", 1) & "😀"',
    ]) {
      test('refuses a lossy cell value from $expression', () {
        final body = 'Worksheets(1).Range("A1:B2").Value2 = $expression';
        expect(
          () => _compile(_module(body)),
          throwsA(
            _error('vba_type_error')
                .having((error) => error.line, 'line', 2)
                .having(
                  (error) => error.column,
                  'emission column',
                  body.indexOf('Value2') + 1,
                ),
          ),
        );
      });
    }

    test('refuses a lossy formula at the write property', () {
      const body = r'Worksheets(1).Range("A1").Formula = "=" & Left$("😀", 1)';
      expect(
        () => _compile(_module(body)),
        throwsA(
          _error('vba_type_error')
              .having((error) => error.line, 'line', 2)
              .having(
                (error) => error.column,
                'emission column',
                body.indexOf('Formula') + 1,
              ),
        ),
      );
    });

    for (final (operation, token) in <(String, String)>[
      ('Value = 1', 'Value'),
      ('Value2 = "safe"', 'Value2'),
      ('Formula = "=1"', 'Formula'),
      ('Font.Bold = True', 'Bold'),
      ('Interior.Color = RGB(1, 2, 3)', 'Color'),
      // ClearContents retains its existing statement-start emission position.
      ('ClearContents', 'Worksheets'),
    ]) {
      test('refuses a lossy worksheet selector for $operation', () {
        final body =
            r'Worksheets(Left$("😀", 1)).Range("A1").'
            '$operation';
        expect(
          () => _compile(_module(body)),
          throwsA(
            _error('vba_type_error')
                .having((error) => error.line, 'line', 2)
                .having(
                  (error) => error.column,
                  'emission column',
                  body.indexOf(token) + 1,
                ),
          ),
        );
      });
    }
  });

  group('String intrinsic resource accounting', () {
    final text = List<String>.filled(32767, 'x').join();

    test('accepts the maximum string and charges the clamped output', () {
      final macro = _compile(
        _module(
          'Dim text As String\ntext = "$text"\n'
          '${_write(r'Len(Left$(text, 2147483647))')}',
        ),
      );
      expect(_values(macro), <Object?>[32767]);
    });

    test('Len does not charge a string copy for reading its length', () {
      final macro = _compile(
        _module(
          'Dim text As String, index As Long, size As Long\ntext = "$text"\n'
          '''
For index = 1 To 10
  size = Len(text)
Next index
${_write('size')}
''',
        ),
      );
      expect(_values(macro), <Object?>[32767]);
    });

    for (final expression in <String>[
      r'Left$(text, 2147483647)',
      r'Right$(text, 2147483647)',
      r'Mid$(text, 1)',
    ]) {
      test('charges output copies for $expression across iterations', () {
        String program(int count) => _module(
          'Dim text As String, result As String, index As Long\ntext = "$text"\n'
          'For index = 1 To $count\nresult = $expression\nNext index\n'
          '${_write('Len(result)')}',
        );
        expect(_values(_compile(program(3))), <Object?>[32767]);
        expect(
          () => _compile(program(4)),
          throwsA(_error('vba_limit_exceeded')),
        );
      });
    }

    test('shares slice work across helper procedure calls', () {
      expect(
        () => _compile(
          'Sub Main()\nDim text As String, index As Long\ntext = "$text"\n'
          'For index = 1 To 4\nCall Slice(text)\nNext index\nEnd Sub\n'
          r'''
Sub Slice(ByVal text As String)
  Dim result As String
  result = Mid$(text, 1)
End Sub
''',
        ),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('sliced array values retain the shared occupancy limit', () {
      String program(int length) => _module(
        'Dim text As String, items(0 To 32) As String, index As Long\ntext = "$text"\n'
        'For index = 0 To 31\nitems(index) = text\nNext index\n'
        'items(32) = Left\$(text, $length)\n${_write('Len(items(32))')}',
      );
      expect(_values(_compile(program(32))), <Object?>[32]);
      expect(
        () => _compile(program(33)),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('does not weaken the per-string limit through intrinsic nesting', () {
      _reject(_write('Len(Left\$("$text" & "x", 1))'), 'vba_limit_exceeded');
    });
  });
}
