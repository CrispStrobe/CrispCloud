import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(
  String source, {
  String entryPoint = 'Main',
  OfficeMacroFormat format = OfficeMacroFormat.xlsx,
}) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    source: source,
    format: format,
    moduleName: 'Report',
    entryPoint: entryPoint,
  ),
);

OfficeMacro _body(String body) => _compile('Sub Main()\n$body\nEnd Sub');

Matcher _error(String code) => isA<OfficeVbaCompileException>().having(
  (error) => error.code,
  'code',
  code,
);

List<Object?> _values(OfficeMacro plan) => <Object?>[
  for (final step in plan.steps) step.arguments['value'],
];

void main() {
  group('VBA source and native plan', () {
    test('accepts BOM, exported module header, comments, and empty Sub', () {
      final plan = _compile(
        '\uFEFFAttribute VB_Name = "Report"\r\nOption Explicit\r\nPublic Sub Main()\r\n\' Inert module\r\nRem Another comment\r\nEnd Sub',
      );
      expect(plan.name, 'Report.Main');
      expect(plan.format, OfficeMacroFormat.xlsx);
      expect(plan.steps, isEmpty);
      expect(plan.parameters, isEmpty);
      expect(const OfficeVbaMacroLanguage().id, 'vba-excel');
    });

    test('selects exactly one case-insensitive parameterless entry point', () {
      final plan = _compile('''
Private Sub Other
  Worksheets(1).Range("A1").Value2 = "other"
End Sub
Public Sub BuIlD()
  Worksheets(1).Range("A1").Value2 = "selected"
End Sub
''', entryPoint: 'build');
      expect(_values(plan), <Object?>['selected']);
    });

    test(
      'lexes literal quotes, apostrophes, colons, and continued expressions',
      () {
        final plan = _body('''
Worksheets(1).Range("A1").Value2 = "a:b's ""quoted"" text" 'comment
Worksheets(1).Range("A2").Value2 = _
  "part" & _
  " two": Rem comment after a separator
Worksheets(1).Range("A3").Value2 = .25 + 1.5e1
''');
        expect(_values(plan), <Object?>[
          'a:b\'s "quoted" text',
          'part two',
          15.25,
        ]);
      },
    );

    test(
      'initializes scalar declarations and permits implicit scalar assignments',
      () {
        final plan = _body('''
Dim count As Long, amount As Double, title As String, flag As Boolean
Worksheets(1).Cells(1, 1).Value2 = count
Worksheets(1).Cells(1, 2).Value2 = amount
Worksheets(1).Cells(1, 3).Value2 = title
Worksheets(1).Cells(1, 4).Value2 = flag
implicitValue = 12
Worksheets(1).Cells(1, 5).Value = implicitValue
''');
        expect(_values(plan), <Object?>[0, 0.0, '', false, 12]);
      },
    );

    test('resolves module and procedure constants without document access', () {
      final plan = _compile('''
Option Explicit
Const Base As Long = 6
Sub Main()
  Const Total As Double = Base * 7
  Const Label As String = "total: "
  Worksheets(1).Range("A1").Value2 = Label & Total
End Sub
''');
      expect(_values(plan), <Object?>['total: 42']);
    });

    test(
      'binds explicit Worksheet and Range objects and restores nested With',
      () {
        final plan = _compile('''
Option Explicit
Sub Main()
  Dim sheet As Worksheet, header As Range
  Set sheet = ThisWorkbook.Worksheets("Summary")
  Set header = sheet.Range("A1:B1")
  With sheet
    With header
      .Value2 = "Heading"
      .Font.Bold = True
    End With
    .Cells(2, 1).Value2 = 10
  End With
End Sub
''');
        expect(plan.steps.length, 5);
        expect(
          plan.steps.map((step) => step.arguments['sheet']),
          everyElement('Summary'),
        );
        expect(plan.steps.map((step) => step.arguments['cell']), <Object?>[
          'A1',
          'B1',
          'A1',
          'B1',
          'A2',
        ]);
        expect(plan.steps[2].arguments['bold'], isTrue);
      },
    );

    test('translates one-based coordinates and normalizes A1 rectangles', () {
      final plan = _body(r'''
Worksheets(2).Cells(2, 3).Value2 = "C2"
Worksheets(1).Range("$b$2:$A$1").Value2 = 7
Worksheets(1).Range("XFD1048576").Value2 = 9
''');
      expect(plan.steps.first.arguments, <String, Object?>{
        'sheet': 1,
        'cell': 'C2',
        'value': 'C2',
      });
      expect(
        plan.steps.skip(1).take(4).map((step) => step.arguments['cell']),
        <String>['A1', 'B1', 'A2', 'B2'],
      );
      expect(plan.steps.last.arguments['cell'], 'XFD1048576');
      expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
    });

    test('lowers writes, repeated formulas, formatting, RGB, and clear', () {
      final plan = _body('''
With Worksheets(1)
  .Range("A1:B1").Formula = "=SUM(C1:C3)"
  .Range("A1").Font.Size = 14
  .Range("A1").Font.Color = RGB(1, 2, 3)
  .Range("A1").Interior.Color = RGB(300, 0, 1)
  .Range("A1").Font.Color = 255
  .Range("C1:C2").ClearContents
End With
''');
      expect(
        plan.steps.take(2).map((step) => step.arguments['formula']),
        everyElement('=SUM(C1:C3)'),
      );
      expect(plan.steps[2].arguments['size'], 14);
      expect(plan.steps[3].arguments['color'], '010203');
      expect(plan.steps[4].arguments['fill'], 'FF0001');
      expect(plan.steps[5].arguments['color'], 'FF0000');
      expect(
        plan.steps.skip(6).map((step) => step.arguments['value']),
        everyElement(isNull),
      );
    });
  });

  group('bounded compile-time control flow', () {
    test(
      'loops are inclusive, have optional counters, and retain final value',
      () {
        final plan = _body('''
Dim row As Long
For row = 3 To 1 Step -1
  Worksheets(1).Cells(row, 1).Value2 = row * 10
Next
Worksheets(1).Range("B1").Value2 = row
''');
        expect(_values(plan), <Object?>[30, 20, 10, 0]);
        expect(plan.steps.map((step) => step.arguments['cell']), <String>[
          'A3',
          'A2',
          'A1',
          'B1',
        ]);
      },
    );

    test('empty and nested loops use ordinary VBA counter behavior', () {
      final plan = _body('''
Dim i As Long, j As Long
For i = 4 To 1
  Worksheets(1).Range("A1").Value2 = 999
Next i
Worksheets(1).Range("A1").Value2 = i
For i = 1 To 2
  For j = 1 To 2
    Worksheets(1).Cells(i + 1, j).Value2 = i * 10 + j
  Next j
Next i
''');
      expect(_values(plan), <Object?>[4, 11, 12, 21, 22]);
    });

    test('For snapshots bounds and step before executing its body', () {
      final plan = _body('''
Dim i As Long, limit As Long, stride As Long
limit = 3: stride = 1
For i = 1 To limit Step stride
  limit = 1: stride = 10
  Worksheets(1).Cells(i, 1).Value2 = i
Next i
''');
      expect(_values(plan), <Object?>[1, 2, 3]);
    });

    test('block If evaluates the chosen ElseIf and otherwise branch', () {
      final plan = _body('''
Dim amount As Long
amount = 7
If amount < 0 Then
  Worksheets(1).Range("A1").Value2 = "negative"
ElseIf amount = 7 Then
  Worksheets(1).Range("A1").Value2 = "seven"
Else
  Worksheets(1).Range("A1").Value2 = "other"
End If
If False Then
  amount = 1 / 0
Else
  Worksheets(1).Range("A2").Value2 = "else"
End If
''');
      expect(_values(plan), <Object?>['seven', 'else']);
    });

    test('VBA precedence puts comparison before Not and Or before Xor', () {
      final plan = _body('''
Worksheets(1).Range("A1").Value2 = Not 1 = 2
Worksheets(1).Range("A2").Value2 = True Or False Xor True
Worksheets(1).Range("A3").Value2 = False Or True And False
Worksheets(1).Range("A4").Value2 = "x" & 2 + 3 * 4
Worksheets(1).Range("A5").Value2 = True < False
''');
      expect(_values(plan), <Object?>[true, false, false, 'x14', true]);
    });

    test('And and Or evaluate both operands', () {
      for (final condition in <String>[
        'False And (1 / 0 > 1)',
        'True Or (1 / 0 > 1)',
      ]) {
        expect(
          () => _body('If $condition Then\nEnd If'),
          throwsA(_error('vba_arithmetic_error')),
        );
      }
    });

    test('numeric comparisons treat signed zero as the same value', () {
      final plan = _body('''
Worksheets(1).Range("A1").Value2 = (-0.0 = 0.0)
Worksheets(1).Range("A2").Value2 = (-0.0 < 0.0)
Worksheets(1).Range("A3").Value2 = (0.0 <= -0.0)
Worksheets(1).Range("A4").Value2 = (-0.0 <> 0)
''');
      expect(_values(plan), <Object?>[true, false, true, false]);
    });
  });

  group('diagnostics and rejected semantics', () {
    test('diagnostics retain physical lines through continuations', () {
      try {
        _compile(
          'Sub Main()\n  Worksheets(1).Range( _\n    "A1").Unknown = 1\nEnd Sub',
        );
        fail('Expected a diagnostic');
      } on OfficeVbaCompileException catch (error) {
        expect(error.code, 'vba_unsupported');
        expect(error.line, 3);
        expect(error.column, 11);
        expect(error.toJson(), containsPair('moduleName', 'Report'));
        expect(error.toJson(), containsPair('entryPoint', 'Main'));
        expect(error.toJson(), containsPair('line', 3));
        expect(error.message, contains('Report.Main:3:11'));
      }
    });

    test(
      'format, missing entry point, and duplicate procedure errors are explicit',
      () {
        expect(
          () => _compile('Sub Main()\nEnd Sub', format: OfficeMacroFormat.docx),
          throwsA(_error('vba_unsupported')),
        );
        expect(
          () => _compile('Sub Other()\nEnd Sub'),
          throwsA(_error('vba_entry_point')),
        );
        expect(
          () => _compile('Sub Main()\nEnd Sub\nSub MAIN()\nEnd Sub'),
          throwsA(_error('vba_syntax_error')),
        );
        expect(
          () => _compile('Sub True()\nEnd Sub', entryPoint: 'True'),
          throwsA(_error('vba_name_error')),
        );
      },
    );

    test('Option Explicit rejects undeclared writes and misspelled names', () {
      expect(
        () => _compile('Option Explicit\nSub Main()\nx = 1\nEnd Sub'),
        throwsA(_error('vba_name_error')),
      );
      expect(
        () => _body(
          'Dim total As Long\nWorksheets(1).Range("A1").Value2 = totla',
        ),
        throwsA(_error('vba_name_error')),
      );
    });

    test('unknown operations are rejected in skipped branches and procedures', () {
      expect(
        () => _body(
          'If False Then\nWorksheets(1).Range("A1").FormulaR1C1 = "=1"\nEnd If',
        ),
        throwsA(_error('vba_unsupported')),
      );
      expect(
        () =>
            _compile('Sub Main()\nEnd Sub\nSub Other()\nShell "calc"\nEnd Sub'),
        throwsA(isA<OfficeVbaCompileException>()),
      );
      expect(
        () => _body(
          'For i = 2 To 1\nWorksheets(1).Range("A1").Value2 = Worksheets(1).Range("B1").Value2\nNext',
        ),
        throwsA(_error('vba_unsupported')),
      );
    });

    final unsupported = <String, String>{
      'implicit Range': 'Range("A1").Value2 = 1',
      'active sheet': 'ActiveSheet.Range("A1").Value2 = 1',
      'default range property': 'Worksheets(1).Range("A1") = 1',
      'document getter': 'x = Worksheets(1).Range("A1").Value2',
      'external workbook':
          'Workbooks("other.xlsx").Worksheets(1).Range("A1").Value2 = 1',
      'COM creation': 'x = CreateObject("Excel.Application")',
      'arbitrary function': 'x = CDate(1)',
      'merge fidelity': 'Worksheets(1).Range("A1:B2").Merge',
      'column width units': 'Worksheets(1).Range("A1").ColumnWidth = 12',
      'implicit conversion': 'Dim x As Long\nx = "12"',
      'Null cell value': 'Worksheets(1).Range("A1").Value2 = Null',
      'uninitialized object': 'Dim x As Worksheet\nx.Range("A1").Value2 = 1',
      'reassigned counter': 'For i = 1 To 3\ni = i + 1\nNext',
      'reused counter': 'For i = 1 To 2\nFor i = 1 To 2\nNext\nNext',
      'block declaration': 'If True Then\nDim x As Long\nEnd If',
      'late declaration': 'x = 1\nDim y As Long',
      'constant function call': 'Const c = RGB(1, 2, 3)',
      'constant mutation': 'Const c = 1\nc = 2',
      'constant uses mutable': 'Dim x As Long\nConst c = x',
      'Set scalar': 'Dim x As Long\nSet x = 1',
      'missing Set': 'Dim x As Worksheet\nx = Worksheets(1)',
      'system colors': 'Worksheets(1).Range("A1").Font.Color = -1',
      'formula implicit constant': 'Worksheets(1).Range("A1").Formula = "42"',
      'formula through Value':
          'Worksheets(1).Range("A1").Value2 = "=SUM(B1:B3)"',
      'property invocation': 'Worksheets(1).Range("A1").Value2() = 1',
      'single line If': 'If True Then Worksheets(1).Range("A1").Value2 = 1',
    };
    for (final entry in unsupported.entries) {
      test('rejects ${entry.key}', () {
        expect(
          () => _body(entry.value),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }

    test(
      'coordinate and scalar constraints fail before document execution',
      () {
        for (final body in <String>[
          'Worksheets(0).Range("A1").Value2 = 1',
          'Worksheets(1).Cells(0, 1).Value2 = 1',
          'Worksheets(1).Cells(1, 16385).Value2 = 1',
          'Worksheets(1).Cells(1.5, 1).Value2 = 1',
          'Worksheets(1).Range("XFE1").Value2 = 1',
          'Worksheets(1).Range("A1048577").Value2 = 1',
          'Worksheets(1).Range("A:A").Value2 = 1',
          'Worksheets(1).Range("A1,B2").Value2 = 1',
          'Worksheets(1).Range("A1").Font.Bold = 1',
          'Worksheets(1).Range("A1").Font.Size = 410',
          'Worksheets(1).Range("A1").Font.Color = RGB(-1, 0, 0)',
          'Dim x As Long\nx = 1.1',
          'Dim x As Long\nx = 2147483648',
          'For i = 1 To 3 Step 0\nNext',
          'For i = 1 To 2147483648\nNext',
        ]) {
          expect(
            () => _body(body),
            throwsA(isA<OfficeVbaCompileException>()),
            reason: body,
          );
        }
      },
    );

    test('malformed source is never partly interpreted', () {
      for (final source in <String>[
        'Sub Main(x)\nEnd Sub',
        'Sub Main()\nWorksheets(1).Range("A1").Value2 = "unfinished\nEnd Sub',
        'Sub Main()\nFor i = 1 To 2\nNext j\nEnd Sub',
        'Sub Main()\nWith Worksheets(1)\nEnd Sub',
        'Sub Main()\nIf True Then\nEnd Sub',
        'Sub Main()\nx = 1e\nEnd Sub',
        'Sub Main()\nx = 1 _ comment\nEnd Sub',
        'Sub Main()\nx = 1 _',
        'Sub Main()\nDim x As Long = 1\nEnd Sub',
        'Sub Main()\nEnd Sub\nOption Explicit',
        'Option Base 2\nSub Main()\nEnd Sub',
        'Sub Main()\nx = #1/1/2020#\nEnd Sub',
      ]) {
        expect(
          () => _compile(source),
          throwsA(isA<OfficeVbaCompileException>()),
          reason: source,
        );
      }
    });

    test('quoted text never acts as syntax or an operator', () {
      for (final source in <String>[
        '"Sub" Main()\nEnd Sub',
        'Sub Main()\n"Dim" x As Long\nEnd Sub',
        'Sub Main()\nx = 1 "+" 2\nEnd Sub',
        'Sub Main()\nIf True "Then"\nEnd If\nEnd Sub',
        'Sub Main()\n"End" Sub',
        'Sub Main()\nDim rem As Long\nEnd Sub',
      ]) {
        expect(
          () => _compile(source),
          throwsA(isA<OfficeVbaCompileException>()),
          reason: source,
        );
      }
    });
  });

  group('independent compiler resource limits', () {
    test(
      'large numeric literals and overflowing products are portable refusals',
      () {
        for (final expression in <String>[
          '1e20',
          '1e100 & ""',
          '4294967296 * 4294967296',
          '9007199254740991 + 1',
          '9007199254740991 * 3',
        ]) {
          expect(
            () => _body('Worksheets(1).Range("A1").Value2 = $expression'),
            throwsA(_error('vba_limit_exceeded')),
            reason: expression,
          );
        }
        expect(
          _values(_body('Worksheets(1).Range("A1").Value2 = 9007199254740991')),
          <Object?>[9007199254740991],
        );
        expect(
          _values(_body('Worksheets(1).Range("A1").Value2 = 3 * 4 / 2')),
          <Object?>[6],
        );
      },
    );

    test('loops emitting no operations are still bounded', () {
      expect(
        () => _body('For i = 1 To 2147483647\nNext i'),
        throwsA(_error('vba_limit_exceeded')),
      );
      expect(
        () => _body('For i = 1 To 400\nFor j = 1 To 400\nNext j\nNext i'),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('Long counter increment overflow fails explicitly', () {
      expect(
        () => _body('Dim i As Long\nFor i = 2147483647 To 2147483647\nNext'),
        throwsA(_error('vba_type_error')),
      );
    });

    test('ranges are charged before any enormous cell list is allocated', () {
      expect(
        () => _body('Worksheets(1).Range("A1:A10001").Value2 = 1'),
        throwsA(_error('vba_limit_exceeded')),
      );
      expect(
        () => _body('Worksheets(1).Range("A1:XFD1048576").ClearContents'),
        throwsA(_error('vba_limit_exceeded')),
      );
      final plan = _body('Worksheets(1).Range("A1:A10000").Value2 = 1');
      expect(plan.steps.length, 10000);
      expect(plan.steps.last.arguments['cell'], 'A10000');
    });

    test(
      'many small writes and repeated large values use aggregate limits',
      () {
        expect(
          () => _body(
            'For i = 1 To 10001\nWorksheets(1).Range("A1").Value2 = 1\nNext',
          ),
          throwsA(_error('vba_limit_exceeded')),
        );
        final text = List<String>.filled(500, 'x').join();
        expect(
          () => _body('Worksheets(1).Range("A1:A3000").Value2 = "$text"'),
          throwsA(_error('vba_limit_exceeded')),
        );
      },
    );

    test('source and concatenated strings are bounded before expansion', () {
      final text = List<String>.filled(32768, 'x').join();
      expect(() => _body('x = "$text"'), throwsA(_error('vba_limit_exceeded')));
      expect(
        () => _body('s = "x"\nFor i = 1 To 16\ns = s & s\nNext'),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('lexer, statement count, and parser nesting have independent limits', () {
      expect(
        () => _body(List<String>.filled(50000, ':').join()),
        throwsA(_error('vba_limit_exceeded')),
      );
      expect(
        () => _body(List<String>.filled(10001, 'x = 1').join('\n')),
        throwsA(_error('vba_limit_exceeded')),
      );
      final parentheses =
          '${List<String>.filled(70, '(').join()}1${List<String>.filled(70, ')').join()}';
      expect(
        () => _body('x = $parentheses'),
        throwsA(_error('vba_limit_exceeded')),
      );
      final unary = '${List<String>.filled(70, '-').join()}1';
      expect(() => _body('x = $unary'), throwsA(_error('vba_limit_exceeded')));
      final blocks =
          '${List<String>.filled(34, 'With Worksheets(1)').join('\n')}\n${List<String>.filled(34, 'End With').join('\n')}';
      expect(() => _body(blocks), throwsA(_error('vba_limit_exceeded')));
    });
  });
}
