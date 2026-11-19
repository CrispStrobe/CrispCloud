import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    source: source,
    format: OfficeMacroFormat.xlsx,
    moduleName: 'ControlFlow',
    entryPoint: 'Main',
  ),
);

List<Object?> _values(OfficeMacro macro) => <Object?>[
  for (final step in macro.steps) step.arguments['value'],
];

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>().having((e) => e.code, 'code', code);

String _deepBody(String body) {
  final openings = <String>[];
  final endings = <String>[];
  for (var index = 0; index < 32; index++) {
    final (opening, ending) = switch (index % 4) {
      0 => ('Do While True', 'Loop'),
      1 => ('While True', 'Wend'),
      2 => ('Select Case 1\nCase 1', 'End Select'),
      _ => ('With Worksheets(1)', 'End With'),
    };
    openings.add(opening);
    endings.insert(0, ending);
  }
  return '${openings.join('\n')}\n$body\n${endings.join('\n')}';
}

void main() {
  test(
    'all published nesting bounds compose without recursive block frames',
    () {
      final unary = List<String>.filled(63, '+').join();
      final mainBody =
          'Worksheets(1).Range("A1").Value2 = ${unary}F1()\nExit Sub';
      final source = StringBuffer(
        'Sub Main()\n${_deepBody(mainBody)}\nEnd Sub',
      );
      for (var index = 1; index < 32; index++) {
        final value = index == 31 ? '42' : 'F${index + 1}()';
        final body = 'F$index = $unary$value\nExit Function';
        source.write(
          '\nFunction F$index() As Long\n${_deepBody(body)}\nEnd Function',
        );
      }
      expect(_values(_compile(source.toString())), <Object?>[42]);
    },
  );

  group('conditional VBA loops', () {
    for (final (start, end) in <(String, String)>[
      ('Do While n < 3', 'Loop'),
      ('Do Until n = 3', 'Loop'),
      ('Do', 'Loop While n < 3'),
      ('Do', 'Loop Until n = 3'),
      ('While n < 3', 'Wend'),
    ]) {
      test('$start / $end reevaluates the changing local condition', () {
        final macro = _compile('''
Option Explicit
Sub Main()
  Dim n As Long
  $start
    n = n + 1
    Worksheets(1).Cells(n, 1).Value2 = n
  $end
  Worksheets(1).Range("B1").Value2 = n
End Sub
''');
        expect(_values(macro), <Object?>[1, 2, 3, 3]);
        expect(macro.steps.map((step) => step.arguments['cell']), <String>[
          'A1',
          'A2',
          'A3',
          'B1',
        ]);
      });
    }

    test('pretests may skip bodies and posttests execute at least once', () {
      final macro = _compile('''
Sub Main()
  Do While False
    Worksheets(1).Range("A1").Value2 = 1
  Loop
  Do Until True
    Worksheets(1).Range("A1").Value2 = 2
  Loop
  While False
    Worksheets(1).Range("A1").Value2 = 3
  Wend
  Do
    Worksheets(1).Range("A1").Value2 = 4
  Loop While False
  Do
    Worksheets(1).Range("A1").Value2 = 5
  Loop Until True
End Sub
''');
      expect(_values(macro), <Object?>[4, 5]);
    });

    test('an unconditional loop can exit after mutable source work', () {
      final macro = _compile('''
Sub Main()
  Dim n As Long
  Do
    n = n + 2
    If n >= 6 Then
      Exit Do
    End If
  Loop
  Worksheets(1).Range("A1").Value2 = n
End Sub
''');
      expect(_values(macro), <Object?>[6]);
    });

    test('conditions invoke helpers in order including the final test', () {
      final macro = _compile('''
Sub Main()
  Dim n As Long
  Do While KeepGoing(n)
    n = n + 1
  Loop
End Sub
Function KeepGoing(ByVal n As Long) As Boolean
  Worksheets(1).Range("A1").Value2 = n
  KeepGoing = n < 2
End Function
''');
      expect(_values(macro), <Object?>[0, 1, 2]);
    });

    test('Exit Do skips a posttest helper with source effects', () {
      final macro = _compile('''
Sub Main()
  Do
    Worksheets(1).Range("A1").Value2 = "body"
    Exit Do
  Loop While Check()
End Sub
Function Check() As Boolean
  Worksheets(1).Range("A1").Value2 = "condition"
  Check = True
End Function
''');
      expect(_values(macro), <Object?>['body']);
    });

    test('Exit Do chooses the nearest Do and allows the outer loop to run', () {
      final macro = _compile('''
Sub Main()
  Dim n As Long
  Do While n < 2
    Do
      Worksheets(1).Range("A1").Value2 = n
      Exit Do
    Loop
    n = n + 1
  Loop
End Sub
''');
      expect(_values(macro), <Object?>[0, 1]);
    });

    test('Exit Do unwinds Select, With, While, and For to its own loop', () {
      final macro = _compile('''
Sub Main()
  Dim row As Long
  With Worksheets(1)
    Do
      For row = 1 To 3
        While True
          With Worksheets(2)
            Select Case row
              Case 1
                .Range("A1").Value2 = "inner"
                Exit Do
            End Select
          End With
        Wend
      Next row
      .Range("A1").Value2 = "unreachable"
    Loop
    .Range("B1").Value2 = row
  End With
End Sub
''');
      expect(_values(macro), <Object?>['inner', 1]);
      expect(macro.steps.map((step) => step.arguments['sheet']), <int>[1, 0]);
    });

    test('Exit For crosses a Do and While without exiting the outer Do', () {
      final macro = _compile('''
Sub Main()
  Dim row As Long, outer As Long
  Do While outer < 2
    For row = 1 To 4
      Do
        While True
          Exit For
        Wend
      Loop
    Next row
    Worksheets(1).Range("A1").Value2 = row
    outer = outer + 1
  Loop
End Sub
''');
      expect(_values(macro), <Object?>[1, 1]);
    });

    test('Exit Function propagates out of mixed new control blocks', () {
      final macro = _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = FindValue()
End Sub
Function FindValue() As Long
  Do
    While True
      Select Case 5
        Case 1 To 10
          FindValue = 42
          Exit Function
      End Select
    Wend
  Loop
End Function
''');
      expect(_values(macro), <Object?>[42]);
    });

    test('implicit variables are discovered within new block bodies', () {
      final macro = _compile('''
Sub Main()
  Do
    value = 3
    Exit Do
  Loop
  While value < 5
    value = value + 1
  Wend
  Select Case value
    Case 5
      result = "done"
  End Select
  Worksheets(1).Range("A1").Value2 = result
End Sub
''');
      expect(_values(macro), <Object?>['done']);
    });

    test('keywords are case-insensitive and support statement separators', () {
      final macro = _compile('''
Sub Main()
  Dim n As Long
  dO: n = n + 1: LoOp UnTiL n = 2
  wHiLe n < 4: n = n + 1: WeNd
  Worksheets(1).Range("A1").Value2 = n
End Sub
''');
      expect(_values(macro), <Object?>[4]);
    });
  });

  group('Select Case', () {
    test('mixes inclusive ranges and values with a final fallback', () {
      final macro = _compile('''
Sub Main()
  Dim n As Long
  For n = 0 To 6
    Worksheets(1).Cells(n + 1, 1).Value2 = Describe(n)
  Next n
End Sub
Function Describe(ByVal n As Long) As String
  Select Case n
    Case 1 To 3, 5
      Describe = "selected"
    Case 6
      Describe = "six"
    Case Else
      Describe = "other"
  End Select
End Function
''');
      expect(_values(macro), <Object?>[
        'other',
        'selected',
        'selected',
        'selected',
        'other',
        'selected',
        'six',
      ]);
    });

    for (final (comparison, matching, missing) in <(String, int, int)>[
      ('=', 3, 4),
      ('<>', 4, 3),
      ('<', 2, 3),
      ('>', 4, 3),
      ('<=', 3, 4),
      ('>=', 3, 2),
    ]) {
      test('Case Is $comparison uses the existing scalar ordering', () {
        final macro = _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = Match($matching)
  Worksheets(1).Range("A2").Value2 = Match($missing)
End Sub
Function Match(ByVal value As Long) As Boolean
  Select Case value
    Case Is $comparison 3
      Match = True
  End Select
End Function
''');
        expect(_values(macro), <Object?>[true, false]);
      });
    }

    test('allows the documented omission of Is before a comparison', () {
      final macro = _compile('''
Sub Main()
  Select Case 12
    Case < 0, >= 10
      Worksheets(1).Range("A1").Value2 = "matched"
  End Select
End Sub
''');
      expect(_values(macro), <Object?>['matched']);
    });

    test('comparison-shaped string literals remain ordinary case values', () {
      final macro = _compile('''
Sub Main()
  Select Case "="
    Case "<", "<>", "="
      Worksheets(1).Range("A1").Value2 = "equal text"
  End Select
  Select Case "is"
    Case "is"
      Worksheets(1).Range("A1").Value2 = "keyword text"
  End Select
End Sub
''');
      expect(_values(macro), <Object?>['equal text', 'keyword text']);
    });

    test(
      'evaluates the selector once and stops after the first alternative',
      () {
        final macro = _compile('''
Sub Main()
  Select Case Mark(7, "selector")
    Case Mark(1, "first"), Mark(7, "match"), Mark(8, "skipped")
      Worksheets(1).Range("A1").Value2 = "selected"
    Case Mark(7, "later")
      Worksheets(1).Range("A1").Value2 = "later body"
    Case Else
      Worksheets(1).Range("A1").Value2 = "fallback"
  End Select
End Sub
Function Mark(ByVal value As Long, ByVal label As String) As Long
  Worksheets(1).Range("A1").Value2 = label
  Mark = value
End Function
''');
        expect(_values(macro), <Object?>[
          'selector',
          'first',
          'match',
          'selected',
        ]);
      },
    );

    test('evaluates both range bounds even when its lower bound fails', () {
      final macro = _compile('''
Sub Main()
  Select Case 1
    Case Mark(2, "lower") To Mark(4, "upper")
      Worksheets(1).Range("A1").Value2 = "range"
    Case Else
      Worksheets(1).Range("A1").Value2 = "fallback"
  End Select
End Sub
Function Mark(ByVal value As Long, ByVal label As String) As Long
  Worksheets(1).Range("A1").Value2 = label
  Mark = value
End Function
''');
      expect(_values(macro), <Object?>['lower', 'upper', 'fallback']);
    });

    test('overlapping clauses use the first match without fallthrough', () {
      final macro = _compile('''
Sub Main()
  Select Case 3
    Case 1 To 4
      Worksheets(1).Range("A1").Value2 = "first"
    Case 3
      Worksheets(1).Range("A1").Value2 = "second"
    Case Else
      Worksheets(1).Range("A1").Value2 = "else"
  End Select
End Sub
''');
      expect(_values(macro), <Object?>['first']);
    });

    test('strings retain binary case-sensitive ordering and ranges', () {
      final macro = _compile('''
Sub Main()
  Select Case "Beta"
    Case "beta"
      Worksheets(1).Range("A1").Value2 = "wrong case"
    Case "Alpha" To "Gamma"
      Worksheets(1).Range("A1").Value2 = "range"
  End Select
  Select Case "z"
    Case Is > "a"
      Worksheets(1).Range("A1").Value2 = "greater"
  End Select
End Sub
''');
      expect(_values(macro), <Object?>['range', 'greater']);
    });

    test('Boolean equality and ordering retain True-before-False behavior', () {
      final macro = _compile('''
Sub Main()
  Select Case True
    Case False
      Worksheets(1).Range("A1").Value2 = "false"
    Case True
      Worksheets(1).Range("A1").Value2 = "true"
  End Select
  Select Case True
    Case Is < False
      Worksheets(1).Range("A1").Value2 = "ordered"
  End Select
End Sub
''');
      expect(_values(macro), <Object?>['true', 'ordered']);
    });

    test('signed zero matches both equality and an inclusive zero range', () {
      final macro = _compile('''
Sub Main()
  Select Case -0.0
    Case 0.0
      Worksheets(1).Range("A1").Value2 = 1
  End Select
  Select Case 0.0
    Case -0.0 To -0.0
      Worksheets(1).Range("A1").Value2 = 2
  End Select
End Sub
''');
      expect(_values(macro), <Object?>[1, 2]);
    });

    test(
      'empty selections and unmatched selections continue after End Select',
      () {
        final macro = _compile('''
Sub Main()
  Select Case 1
  End Select
  Select Case 2
    Case 3
      Worksheets(1).Range("A1").Value2 = "unmatched"
  End Select
  Select Case 1
    Case 1
    Case Else
      Worksheets(1).Range("A1").Value2 = "must not fall through"
  End Select
  Worksheets(1).Range("A1").Value2 = "after"
End Sub
''');
        expect(_values(macro), <Object?>['after']);
      },
    );

    test('nested selections keep independent selectors and With bindings', () {
      final macro = _compile('''
Sub Main()
  With Worksheets(1)
    Select Case "outer"
      Case "outer"
        With Worksheets(2)
          Select Case 2
            Case 1
              .Range("A1").Value2 = "no"
            Case 2
              .Range("A1").Value2 = "inner"
          End Select
        End With
        .Range("A1").Value2 = "outer"
    End Select
  End With
End Sub
''');
      expect(_values(macro), <Object?>['inner', 'outer']);
      expect(macro.steps.map((step) => step.arguments['sheet']), <int>[1, 0]);
    });

    test('Variant selectors are checked against actual scalar case types', () {
      final macro = _compile('''
Sub Main()
  Dim value As Variant
  value = "item"
  Select Case value
    Case "item"
      Worksheets(1).Range("A1").Value2 = True
  End Select
End Sub
''');
      expect(_values(macro), <Object?>[true]);
      expect(
        () => _compile('''
Sub Main()
  Dim value As Variant
  value = "item"
  Select Case value
    Case 1
  End Select
End Sub
'''),
        throwsA(_error('vba_type_error')),
      );
    });

    test('reversed ranges simply do not match', () {
      final macro = _compile('''
Sub Main()
  Select Case 3
    Case 5 To 1
      Worksheets(1).Range("A1").Value2 = "range"
    Case Else
      Worksheets(1).Range("A1").Value2 = "fallback"
  End Select
End Sub
''');
      expect(_values(macro), <Object?>['fallback']);
    });
  });
}
