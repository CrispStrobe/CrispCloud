import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    source: source,
    format: OfficeMacroFormat.xlsx,
    moduleName: 'Arrays',
    entryPoint: 'Main',
  ),
);

OfficeMacro _body(String source) => _compile('Sub Main()\n$source\nEnd Sub');

List<Object?> _values(OfficeMacro macro) => <Object?>[
  for (final step in macro.steps) step.arguments['value'],
];

Matcher _error(String code) => isA<OfficeVbaCompileException>().having(
  (error) => error.code,
  'code',
  code,
);

void main() {
  group('fixed scalar arrays', () {
    test(
      'initializes all typed element kinds and leaves scalars independent',
      () {
        final macro = _body('''
Dim ints(1 To 2) As Long, doubles(1) As Double
Dim texts(-1 To 0) As String, flags(4 To 4) As Boolean
Dim scalar As Long
Worksheets(1).Range("A1").Value2 = ints(2)
Worksheets(1).Range("A2").Value2 = doubles(0)
Worksheets(1).Range("A3").Value2 = texts(-1)
Worksheets(1).Range("A4").Value2 = flags(4)
Worksheets(1).Range("A5").Value2 = scalar
''');
        expect(_values(macro), <Object?>[0, 0.0, '', false, 0]);
      },
    );

    test('indexes read/write with optional Let and case-insensitive names', () {
      final macro = _body('''
Dim Values(-2 To 0) As Long
values(-2) = 5
Let VALUES(-1) = values(-2) * 2
values(0) = VALUES(-1) + 7
Worksheets(1).Range("A1").Value2 = values(-2)
Worksheets(1).Range("A2").Value2 = values(-1)
Worksheets(1).Range("A3").Value2 = values(0)
''');
      expect(_values(macro), <Object?>[5, 10, 17]);
    });

    test('uses prior module and local constant expressions for bounds', () {
      final macro = _compile('''
Const Start As Long = -3
Const Size As Long = 2
Sub Main()
  Const Last As Long = Start + Size
  Const Final As Long = Last + 1
  Dim data(Start To Final) As String
  data(Final) = "last"
  Worksheets(1).Range("A1").Value2 = LBound(data)
  Worksheets(1).Range("A2").Value2 = UBound(data, 1)
  Worksheets(1).Range("A3").Value2 = data(Final)
End Sub
''');
      expect(_values(macro), <Object?>[-3, 0, 'last']);
    });

    test('constant values resolve independently in different helpers', () {
      final macro = _compile('''
Sub Main()
  Call One
  Call Two
End Sub
Sub One()
  Const N = 2
  Dim data(N) As Long
  Worksheets(1).Range("A1").Value2 = UBound(data)
End Sub
Sub Two()
  Const N = 7
  Dim data(N) As Long
  Worksheets(1).Range("A2").Value2 = UBound(data)
End Sub
''');
      expect(_values(macro), <Object?>[2, 7]);
    });

    test(
      'a long constant dependency chain uses ordered bounded evaluation',
      () {
        final source = StringBuffer('Sub Main()\nConst C0 = 1\n');
        for (var index = 1; index < 250; index++) {
          source.writeln('Const C$index = C${index - 1} + 1');
        }
        source.write('''
Dim data(C249 To C249 + 1) As Long
Worksheets(1).Range("A1").Value2 = LBound(data)
Worksheets(1).Range("A2").Value2 = UBound(data)
End Sub
''');
        expect(_values(_compile(source.toString())), <Object?>[250, 251]);
      },
    );

    test('Variant array elements hold independent supported scalar types', () {
      final macro = _body('''
Dim data(2)
data(0) = 12
data(1) = "text"
data(2) = True
Worksheets(1).Range("A1").Value2 = data(0)
Worksheets(1).Range("A2").Value2 = data(1)
Worksheets(1).Range("A3").Value2 = data(2)
''');
      expect(_values(macro), <Object?>[12, 'text', true]);
    });

    test(
      'array elements pass to ByVal helpers and return as scalar results',
      () {
        final macro = _compile('''
Sub Main()
  Dim data(1 To 1) As Long
  data(1) = Twice(21)
  Call Put(data(1))
  Worksheets(1).Range("A2").Value2 = data(1)
End Sub
Function Twice(ByVal value As Long) As Long
  Dim local(0) As Long
  local(0) = value * 2
  Twice = local(0)
End Function
Sub Put(ByVal value As Long)
  value = value + 1
  Worksheets(1).Range("A1").Value2 = value
End Sub
''');
        expect(_values(macro), <Object?>[43, 42]);
      },
    );

    test('assignment evaluates index once before RHS and subsequent reads', () {
      final macro = _compile('''
Sub Main()
  Dim data(1 To 2) As Long
  data(Index()) = Value()
  Worksheets(1).Range("B1").Value2 = data(Index())
End Sub
Function Index() As Long
  Worksheets(1).Range("A1").Value2 = "index"
  Index = 2
End Function
Function Value() As Long
  Worksheets(1).Range("A2").Value2 = "rhs"
  Value = 42
End Function
''');
      expect(_values(macro), <Object?>['index', 'rhs', 'index', 42]);
    });

    test('indexed assignment lookahead ignores parentheses inside strings', () {
      final macro = _compile('''
Sub Main()
  Dim data(1) As Long
  data(Index(")")) = 17
  Worksheets(1).Range("A1").Value2 = data(1)
End Sub
Function Index(ByVal label As String) As Long
  Index = 1
End Function
''');
      expect(_values(macro), <Object?>[17]);
    });

    test(
      'preserves bare helper calls with parenthesized comparison arguments',
      () {
        final macro = _compile('''
Sub Main()
  Helper (1) = 2
  Helper (1 + 1) = 2
End Sub
Sub Helper(ByVal flag As Boolean)
  Worksheets(1).Range("A1").Value2 = flag
End Sub
''');
        expect(_values(macro), <Object?>[false, true]);
      },
    );

    test('declared arrays accept parenthesized assignment subscripts', () {
      final macro = _body('''
Dim data(1 To 2) As Long
data((1)) = 2
Let data((2)) = data((1)) + 1
Worksheets(1).Range("A1").Value2 = data(1)
Worksheets(1).Range("A2").Value2 = data(2)
''');
      expect(_values(macro), <Object?>[2, 3]);
    });

    test('helper calls allocate fresh local arrays for every invocation', () {
      final macro = _compile('''
Sub Main()
  Call Increment
  Call Increment
End Sub
Sub Increment()
  Dim data(1) As Long
  data(0) = data(0) + 1
  Worksheets(1).Range("A1").Value2 = data(0)
End Sub
''');
      expect(_values(macro), <Object?>[1, 1]);
    });

    test('counted loops use bounds without exposing the entire array', () {
      final macro = _body('''
Dim data(-1 To 1) As Long, i As Long
For i = LBound(data) To UBound(data)
  data(i) = (i + 2) * 10
Next i
For i = UBound(data) To LBound(data) Step -1
  Worksheets(1).Cells(2 - i, 1).Value2 = data(i)
Next
''');
      expect(_values(macro), <Object?>[30, 20, 10]);
    });

    test('bound helpers evaluate the dimension argument once', () {
      final macro = _compile('''
Sub Main()
  Dim data(7 To 9) As Long
  Worksheets(1).Range("A2").Value2 = LBound(data, Dimension())
  Worksheets(1).Range("A3").Value2 = UBound(data, Dimension())
End Sub
Function Dimension() As Long
  Worksheets(1).Range("A1").Value2 = "dimension"
  Dimension = 1
End Function
''');
      expect(_values(macro), <Object?>['dimension', 7, 'dimension', 9]);
    });

    test(
      'does not evaluate unrelated unused constant values while checking bounds',
      () {
        expect(
          _body('''
Dim data(1) As Long
Worksheets(1).Range("A1").Value2 = UBound(data)
''').steps,
          hasLength(1),
        );
        final macro = _compile('''
Sub Main()
End Sub
Sub Unused()
  Const Bad As Long = 1 / 0
  Const Good As Long = 1
  Dim data(Good) As Long
End Sub
''');
        expect(macro.steps, isEmpty);
      },
    );

    test(
      'replacing strings or Variant slots releases occupied string units',
      () {
        final chunk = List<String>.filled(32767, 'x').join();
        final macro = _body('''
Dim data(32), i As Long, chunk As String
chunk = "$chunk"
For i = 0 To 31
  data(i) = chunk
Next
data(0) = False
data(32) = chunk
data(1) = ""
data(0) = chunk
Worksheets(1).Range("A1").Value2 = "replaced"
''');
        expect(_values(macro), <Object?>['replaced']);
      },
    );

    test('procedure returns release occupied array string units', () {
      final chunk = List<String>.filled(32767, 'x').join();
      final macro = _compile('''
Sub Main()
  Call Fill
  Call Fill
  Worksheets(1).Range("A1").Value2 = "released"
End Sub
Sub Fill()
  Dim data(31) As String, i As Long
  For i = 0 To 31
    data(i) = "$chunk"
  Next
End Sub
''');
      expect(_values(macro), <Object?>['released']);
    });
  });

  group('For Each arrays', () {
    test('visits ascending subscripts and retains the last scalar item', () {
      final macro = _body('''
Dim data(-2 To 0) As Long, item As Variant, row As Long
data(-2) = 9
data(-1) = 4
data(0) = 7
For Each item In data
  row = row + 1
  Worksheets(1).Cells(row, 1).Value2 = item
Next item
Worksheets(1).Range("B1").Value2 = item
''');
      expect(_values(macro), <Object?>[9, 4, 7, 7]);
    });

    test(
      'implicit Variant iteration variable follows Option Explicit rules',
      () {
        final macro = _body('''
Dim data(0) As String
data(0) = "implicit"
For Each item In data
  Worksheets(1).Range("A1").Value2 = item
Next
''');
        expect(_values(macro), <Object?>['implicit']);
        expect(
          () => _compile('''
Option Explicit
Sub Main()
  Dim data(0) As Long
  For Each item In data
  Next
End Sub
'''),
          throwsA(_error('vba_name_error')),
        );
      },
    );

    test(
      'reads future mutated slots live without writing back control changes',
      () {
        final macro = _body('''
Dim data(1 To 3) As Long, item As Variant, row As Long
data(1) = 10
data(2) = 20
data(3) = 30
For Each item In data
  row = row + 1
  Worksheets(1).Cells(row, 1).Value2 = item
  data(2) = 99
  item = -1
Next
Worksheets(1).Range("B1").Value2 = data(1)
Worksheets(1).Range("B2").Value2 = data(2)
Worksheets(1).Range("B3").Value2 = item
''');
        expect(_values(macro), <Object?>[10, 99, 30, 10, 99, -1]);
      },
    );

    test('Variant iteration can change scalar types between elements', () {
      final macro = _body('''
Dim data(2), item As Variant
data(0) = True
data(1) = 17
data(2) = "end"
For Each item In data
  Worksheets(1).Range("A1").Value2 = item
Next
''');
      expect(_values(macro), <Object?>[true, 17, 'end']);
    });

    test(
      'Exit For skips later uninitialized slots and preserves the current item',
      () {
        final macro = _body('''
Dim data(1 To 2), item As Variant
data(1) = "first"
For Each item In data
  Exit For
Next
Worksheets(1).Range("A1").Value2 = item
''');
        expect(_values(macro), <Object?>['first']);
      },
    );

    test('For Each and counted For exits select the nearest For kind', () {
      final macro = _body('''
Dim data(1 To 2) As Long, item As Variant, i As Long
data(1) = 11
data(2) = 22
For Each item In data
  For i = 1 To 3
    Worksheets(1).Range("A1").Value2 = item + i
    Exit For
  Next i
Next item
For i = 1 To 2
  For Each item In data
    Worksheets(1).Range("B1").Value2 = i + item
    Exit For
  Next item
Next i
''');
      expect(_values(macro), <Object?>[12, 23, 12, 13]);
    });

    test('Exit For traverses Do, Select and With then restores outer With', () {
      final macro = _body('''
Dim data(0) As Long, item As Variant
With Worksheets(1)
  For Each item In data
    Do
      Select Case item
        Case 0
          With Worksheets(2)
            .Range("A1").Value2 = "inner"
            Exit For
          End With
      End Select
    Loop
  Next
  .Range("A1").Value2 = "outer"
End With
''');
      expect(_values(macro), <Object?>['inner', 'outer']);
      expect(macro.steps.map((step) => step.arguments['sheet']), <Object?>[
        1,
        0,
      ]);
    });

    test('Exit Do crosses a For Each and restores enclosing execution', () {
      final macro = _body('''
Dim data(0) As Long, item As Variant
Do
  For Each item In data
    Exit Do
  Next
  Worksheets(1).Range("A1").Value2 = "unreached"
Loop
Worksheets(1).Range("A1").Value2 = "done"
''');
      expect(_values(macro), <Object?>['done']);
    });

    test('an array inside a Function can be iterated before early return', () {
      final macro = _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = First()
End Sub
Function First() As String
  Dim data(1 To 2) As String, item As Variant
  data(1) = "first"
  data(2) = "second"
  For Each item In data
    First = item
    Exit Function
  Next
End Function
''');
      expect(_values(macro), <Object?>['first']);
    });
  });

  group('For Each explicit ranges and metadata', () {
    test('visits a rectangle row-major with one-based source coordinates', () {
      final macro = _body('''
Dim cell As Range
For Each cell In Worksheets("Summary").Range("B2:C3")
  cell.Value2 = cell.Row * 100 + cell.Column
Next cell
''');
      expect(_values(macro), <Object?>[202, 203, 302, 303]);
      expect(macro.steps.map((step) => step.arguments['cell']), <Object?>[
        'B2',
        'C2',
        'B3',
        'C3',
      ]);
      expect(
        macro.steps.map((step) => step.arguments['sheet']),
        everyElement('Summary'),
      );
    });

    test(
      'captures the source range once across rebinding of source and control',
      () {
        final macro = _body('''
Dim source As Range, cell As Range
Set source = Worksheets(1).Range("A1:B1")
For Each cell In source
  cell.Value2 = cell.Column
  Set source = Worksheets(2).Range("D4")
  Set cell = Worksheets(2).Range("E5")
Next
cell.Value2 = "last binding"
source.Value2 = "source binding"
''');
        expect(_values(macro), <Object?>[
          1,
          2,
          'last binding',
          'source binding',
        ]);
        expect(macro.steps.map((step) => step.arguments['cell']), <Object?>[
          'A1',
          'B1',
          'E5',
          'D4',
        ]);
        expect(macro.steps.map((step) => step.arguments['sheet']), <Object?>[
          0,
          0,
          1,
          1,
        ]);
      },
    );

    test('evaluates source selector helpers once before range iteration', () {
      final macro = _compile('''
Sub Main()
  Dim cell As Range
  For Each cell In Worksheets(Sheet()).Range("A1:B1")
    cell.Value2 = cell.Column
  Next
End Sub
Function Sheet() As Long
  Worksheets(2).Range("A1").Value2 = "selector"
  Sheet = 1
End Function
''');
      expect(_values(macro), <Object?>['selector', 1, 2]);
    });

    test('nested With range metadata retains outer worksheet after exit', () {
      final macro = _body('''
Dim cell As Range
With Worksheets(1)
  For Each cell In .Range("C4:D5")
    With cell
      .Value2 = .Row + .Column
      Exit For
    End With
  Next
  .Range("A1").Value2 = 42
End With
''');
      expect(_values(macro), <Object?>[7, 42]);
      expect(macro.steps.map((step) => step.arguments['cell']), <Object?>[
        'C4',
        'A1',
      ]);
    });

    test('normalizes reversed range endpoints for metadata and iteration', () {
      final macro = _body('''
Dim cell As Range
Worksheets(1).Range("D5:C4").Font.Size = 12
Worksheets(1).Range("A1").Value2 = Worksheets(1).Range("D5:C4").Row
Worksheets(1).Range("A2").Value2 = Worksheets(1).Range("D5:C4").Column
For Each cell In Worksheets(1).Range("D5:C4")
  cell.Value2 = cell.Row * 10 + cell.Column
Next
''');
      expect(_values(macro).skip(4), <Object?>[4, 3, 43, 44, 53, 54]);
    });

    test(
      'a range control variable is a normal ByVal Range helper argument',
      () {
        final macro = _compile('''
Sub Main()
  Dim cell As Range
  For Each cell In Worksheets(1).Range("A1:B2")
    Call Put(cell)
  Next
End Sub
Sub Put(ByVal target As Range)
  target.Value2 = target.Row * target.Column
End Sub
''');
        expect(_values(macro), <Object?>[1, 2, 2, 4]);
      },
    );
  });
}
