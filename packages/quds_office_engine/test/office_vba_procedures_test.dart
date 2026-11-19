import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source, {String entryPoint = 'Main'}) =>
    const OfficeVbaMacroLanguage().compile(
      OfficeMacroSource(
        language: 'vba-excel',
        source: source,
        format: OfficeMacroFormat.xlsx,
        moduleName: 'Procedures',
        entryPoint: entryPoint,
      ),
    );

List<Object?> _values(OfficeMacro macro) => <Object?>[
  for (final step in macro.steps) step.arguments['value'],
];

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>().having(
      (error) => error.code,
      'code',
      code,
    );

void main() {
  group('reusable VBA procedures', () {
    test('calls forward Sub definitions with positional typed arguments', () {
      final macro = _compile('''
Option Explicit
Sub Main()
  Call WriteAmount(Worksheets("Summary"), 2, "total", 6 * 7)
End Sub
Private Sub WriteAmount(ByVal sheet As Worksheet, ByVal row As Long, _
    ByVal label As String, ByVal amount As Double)
  sheet.Cells(row, 1).Value2 = label
  sheet.Cells(row, 2).Value2 = amount
End Sub
''');
      expect(_values(macro), <Object?>['total', 42.0]);
      expect(macro.steps.first.arguments['sheet'], 'Summary');
      expect(macro.steps.first.arguments['cell'], 'A2');
      expect(macro.steps.last.arguments['cell'], 'B2');
    });

    test(
      'supports bare calls, grouped expressions, and statement separators',
      () {
        final macro = _compile('''
Sub Main()
  Put (1 + 2) * 3, "first": Put -2, "second"
End Sub
Sub Put(ByVal amount As Long, ByVal label As String)
  Worksheets(1).Range("A1").Value2 = amount
  Worksheets(1).Range("B1").Value2 = label
End Sub
''');
        expect(_values(macro), <Object?>[9, 'first', -2, 'second']);
      },
    );

    test('supports case-insensitive zero-argument invocation forms', () {
      final macro = _compile('''
Sub MAIN
  marker
  Call MARKER
  Call Marker()
  Marker()
End Sub
Private Sub Marker
  Worksheets(1).Range("A1").Value2 = "called"
End Sub
''');
      expect(_values(macro), List<String>.filled(4, 'called'));
    });

    test('each invocation initializes its own locals and constants', () {
      final macro = _compile('''
Option Explicit
Const Increment As Long = 3
Sub Main()
  Dim count As Long
  count = 99
  Call Emit()
  Call Emit()
  Worksheets(1).Range("B1").Value2 = count
End Sub
Sub Emit()
  Dim count As Long
  Const Starting As Long = Increment * 2
  count = count + Starting
  Worksheets(1).Range("A1").Value2 = count
End Sub
''');
      expect(_values(macro), <Object?>[6, 6, 99]);
    });

    test(
      'implicit local variables are isolated across procedures and calls',
      () {
        final macro = _compile('''
Sub Main()
  value = 11
  Change 4
  Change 7
  Worksheets(1).Range("A1").Value2 = value
End Sub
Sub Change(ByVal value)
  computed = value * 2
  value = computed
  Worksheets(1).Range("A1").Value2 = value
End Sub
''');
        expect(_values(macro), <Object?>[8, 14, 11]);
      },
    );

    test('Range parameters preserve exact explicit target bindings', () {
      final macro = _compile('''
Sub Main()
  Call Style(Worksheets("Summary").Range("B2:C2"), True)
End Sub
Sub Style(ByVal target As Range, ByVal enabled As Boolean)
  With target
    .Font.Bold = enabled
    .Interior.Color = RGB(10, 20, 30)
  End With
End Sub
''');
      expect(macro.steps.length, 4);
      expect(macro.steps.map((step) => step.arguments['cell']), <String>[
        'B2',
        'C2',
        'B2',
        'C2',
      ]);
      expect(macro.steps.first.arguments['bold'], isTrue);
      expect(macro.steps.last.arguments['fill'], '0A141E');
    });

    test('custom entry selection remains parameterless Sub only', () {
      final macro = _compile('''
Sub Main()
  Put "main"
End Sub
Sub Build()
  Put "build"
End Sub
Sub Put(ByVal value As String)
  Worksheets(1).Range("A1").Value2 = value
End Sub
''', entryPoint: 'bUiLd');
      expect(macro.name, 'Procedures.Build');
      expect(_values(macro), <Object?>['build']);
    });
  });

  group('scalar VBA functions', () {
    test('composes typed functions and reads the current return variable', () {
      final macro = _compile('''
Option Explicit
Sub Main()
  Worksheets(1).Range("A1").Value2 = Label(Twice(21))
End Sub
Function Twice(ByVal value As Long) As Long
  Twice = value
  Twice = Twice + value
End Function
Function Label(ByVal amount As Long) As String
  Label = "Total: " & amount
End Function
''');
      expect(_values(macro), <Object?>['Total: 42']);
    });

    test('returns all supported scalar types and omitted Variant types', () {
      final macro = _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = NumberValue(2.5)
  Worksheets(1).Range("A2").Value2 = Flag(True)
  Worksheets(1).Range("A3").Value2 = Identity("text")
  Worksheets(1).Range("A4").Value2 = Identity(7)
End Sub
Function NumberValue(ByVal value As Double) As Double
  NumberValue = value * 2
End Function
Function Flag(ByVal value As Boolean) As Boolean
  Flag = Not value
End Function
Function Identity(ByVal value)
  Identity = value
End Function
''');
      expect(_values(macro), <Object?>[5.0, false, 'text', 7]);
    });

    test('typed result defaults match the existing scalar defaults', () {
      final macro = _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = LongValue()
  Worksheets(1).Range("A2").Value2 = DoubleValue()
  Worksheets(1).Range("A3").Value2 = StringValue()
  Worksheets(1).Range("A4").Value2 = BooleanValue()
End Sub
Function LongValue() As Long
End Function
Function DoubleValue() As Double
End Function
Function StringValue() As String
End Function
Function BooleanValue() As Boolean
End Function
''');
      expect(_values(macro), <Object?>[0, 0.0, '', false]);
    });

    test(
      'functions may emit ordinary operations and have results discarded',
      () {
        final macro = _compile('''
Sub Main()
  Call Mark(1)
  Mark 2
  Worksheets(1).Range("B1").Value2 = Mark(3)
End Sub
Function Mark(ByVal value As Long) As Long
  Worksheets(1).Range("A1").Value2 = value
  Mark = value * 10
End Function
''');
        expect(_values(macro), <Object?>[1, 2, 3, 30]);
      },
    );

    test('function calls work in conditions, bounds, and object selectors', () {
      final macro = _compile('''
Sub Main()
  Dim row As Long
  If Enabled() Then
    For row = StartAt() To StartAt() + 1
      Worksheets(SheetName()).Cells(row, 1).Value2 = row
    Next row
  End If
End Sub
Function Enabled() As Boolean
  Enabled = True
End Function
Function StartAt() As Long
  StartAt = 2
End Function
Function SheetName() As String
  SheetName = "Summary"
End Function
''');
      expect(_values(macro), <Object?>[2, 3]);
      expect(macro.steps.first.arguments['sheet'], 'Summary');
      expect(macro.steps.last.arguments['cell'], 'A3');
    });

    test('return conversion retains the strict existing numeric rules', () {
      for (final value in <String>['1.5', '2147483648']) {
        expect(
          () => _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = ConvertValue($value)
End Sub
Function ConvertValue(ByVal value As Variant) As Long
  ConvertValue = value
End Function
'''),
          throwsA(_error('vba_type_error')),
          reason: value,
        );
      }
    });
  });

  group('structured early exits', () {
    test('Exit Sub unwinds nested loops and With to the caller', () {
      final macro = _compile('''
Sub Main()
  With Worksheets("Summary")
    WriteFirst .Range("A1")
    .Range("B1").Value2 = "after"
  End With
End Sub
Sub WriteFirst(ByVal target As Range)
  Dim row As Long
  With target
    For row = 1 To 3
      If row = 1 Then
        .Value2 = row
        Exit Sub
      End If
      .Value2 = 99
    Next
  End With
  target.Value2 = 100
End Sub
''');
      expect(_values(macro), <Object?>[1, 'after']);
      expect(macro.steps.last.arguments['cell'], 'B1');
    });

    test('Exit Function returns the current result from nested blocks', () {
      final macro = _compile('''
Sub Main()
  Worksheets(1).Range("B1").Value2 = First()
End Sub
Function First() As Long
  Dim row As Long
  First = 42
  For row = 1 To 3
    With Worksheets(1)
      .Range("A1").Value2 = row
      Exit Function
    End With
  Next
  First = 99
End Function
''');
      expect(_values(macro), <Object?>[1, 42]);
    });

    test(
      'Exit For retains the current counter and only exits innermost loop',
      () {
        final macro = _compile('''
Sub Main()
  Dim outer As Long, inner As Long
  For outer = 1 To 2
    For inner = 3 To 1 Step -1
      Worksheets(1).Range("A1").Value2 = inner
      Exit For
    Next
    Worksheets(1).Range("B1").Value2 = inner
  Next
  Worksheets(1).Range("C1").Value2 = outer
End Sub
''');
        expect(_values(macro), <Object?>[3, 3, 3, 3, 3]);
      },
    );

    test('an Exit For at the Long boundary avoids post-loop overflow', () {
      final macro = _compile('''
Sub Main()
  Dim row As Long
  For row = 2147483647 To 2147483647
    Exit For
  Next
  Worksheets(1).Range("A1").Value2 = row
End Sub
''');
      expect(_values(macro), <Object?>[2147483647]);
    });
  });

  group('procedure source diagnostics', () {
    test(
      'helper errors retain module, entry point, and source coordinates',
      () {
        expect(
          () => _compile('''Sub Main()
  Call Helper()
End Sub
Sub Helper()
  Shell "unavailable"
End Sub
'''),
          throwsA(
            _error('vba_unsupported')
                .having((error) => error.moduleName, 'moduleName', 'Procedures')
                .having((error) => error.entryPoint, 'entryPoint', 'Main')
                .having((error) => error.line, 'line', 5)
                .having((error) => error.column, 'column', 3),
          ),
        );
      },
    );

    test('parameters and local variables cannot duplicate one another', () {
      for (final helper in <String>[
        'Sub Helper(ByVal item As Long, ByVal ITEM As Long)\nEnd Sub',
        'Sub Helper(ByVal item As Long)\nDim item As Long\nEnd Sub',
        'Function Helper(ByVal Helper As Long) As Long\nEnd Function',
        'Function Helper() As Long\nDim Helper As Long\nEnd Function',
      ]) {
        expect(
          () => _compile('Sub Main()\nEnd Sub\n$helper'),
          throwsA(_error('vba_name_error')),
          reason: helper,
        );
      }
    });

    test('Function object return types remain explicitly unsupported', () {
      for (final type in <String>['Worksheet', 'Range']) {
        expect(
          () => _compile(
            'Sub Main()\nEnd Sub\nFunction F() As $type\nEnd Function',
          ),
          throwsA(_error('vba_unsupported')),
        );
      }
    });

    test('procedure calls remain unavailable in constant expressions', () {
      expect(
        () => _compile('''
Const Value = Compute()
Sub Main()
End Sub
Function Compute() As Long
  Compute = 42
End Function
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test(
      'bare multiargument parentheses do not silently change VBA syntax',
      () {
        expect(
          () => _compile('''
Sub Main()
  Put(1, 2)
End Sub
Sub Put(ByVal first As Long, ByVal second As Long)
End Sub
'''),
          throwsA(_error('vba_syntax_error')),
        );
      },
    );

    test('Call requires parentheses around nonempty arguments', () {
      expect(
        () => _compile('''
Sub Main()
  Call Put 1
End Sub
Sub Put(ByVal value As Long)
End Sub
'''),
        throwsA(_error('vba_syntax_error')),
      );
    });

    test('labels never invoke same-named helper procedures', () {
      for (final body in <String>[
        'Helper:',
        'Helper: Worksheets(1).Range("A1").Value2 = 99',
        '  helper :',
        'UnknownLabel:',
        'Exit Sub\nHelper:',
        'If False Then\nHelper:\nEnd If',
      ]) {
        expect(
          () => _compile('''
Sub Main()
$body
End Sub
Sub Helper()
  Worksheets(1).Range("A1").Value2 = "must not run"
End Sub
'''),
          throwsA(_error('vba_unsupported')),
          reason: body,
        );
      }
    });

    test('labels are rejected in unused procedures as well', () {
      expect(
        () => _compile('''
Sub Main()
End Sub
Sub Unused()
Helper:
End Sub
Sub Helper()
  Worksheets(1).Range("A1").Value2 = "must not run"
End Sub
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test(
      'explicit zero-argument calls remain valid before colon separators',
      () {
        final macro = _compile('''
Sub Main()
  Call Helper: Helper(): Call Helper()
End Sub
Sub Helper()
  Worksheets(1).Range("A1").Value2 = "called"
End Sub
''');
        expect(_values(macro), List<String>.filled(3, 'called'));
      },
    );
  });
}
