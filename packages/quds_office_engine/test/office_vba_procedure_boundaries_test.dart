import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    source: source,
    format: OfficeMacroFormat.xlsx,
    moduleName: 'ProcedureBoundaries',
    entryPoint: 'Main',
  ),
);

Matcher _error(String code) => isA<OfficeVbaCompileException>().having(
  (error) => error.code,
  'code',
  code,
);

List<Object?> _values(OfficeMacro plan) => <Object?>[
  for (final step in plan.steps) step.arguments['value'],
];

String _chain(int frames, {bool unused = false, bool afterExit = false}) {
  final source = StringBuffer();
  if (unused) source.writeln('Sub Main()\nEnd Sub');
  for (var i = 0; i < frames; i++) {
    final name = !unused && i == 0 ? 'Main' : 'Helper$i';
    source.writeln('Sub $name()');
    if (afterExit) source.writeln('Exit Sub');
    if (i + 1 < frames) source.writeln('Call Helper${i + 1}()');
    source.writeln('End Sub');
  }
  return source.toString();
}

void main() {
  group('procedure isolation and control transfer', () {
    test(
      'ByVal rebinding isolates scalars, objects, With, and loop counters',
      () {
        final plan = _compile('''
Option Explicit
Sub Main()
  Dim i As Long, amount As Long, target As Worksheet
  amount = 7
  Set target = Worksheets("Summary")
  With target
    For i = 1 To 2
      Rewrite amount, target, .Range("A1"), i
      .Cells(i + 1, 1).Value2 = amount * 10 + i
    Next i
  End With
  target.Range("A4").Value2 = amount
End Sub
Sub Rewrite(ByVal amount As Long, ByVal target As Worksheet, ByVal cell As Range, ByVal i As Long)
  amount = 99
  Set target = Worksheets("Other")
  Set cell = target.Range("Z1")
  With target
    For i = 4 To 4
      cell.Value2 = amount + i
      Exit For
    Next i
  End With
End Sub
''');
        expect(_values(plan), <Object?>[103, 71, 103, 72, 7]);
        expect(plan.steps.map((step) => step.arguments['sheet']), <Object?>[
          'Other',
          'Summary',
          'Other',
          'Summary',
          'Summary',
        ]);
        expect(plan.steps.map((step) => step.arguments['cell']), <Object?>[
          'Z1',
          'A2',
          'Z1',
          'A3',
          'A4',
        ]);
      },
    );

    test(
      'Exit Sub unwinds callee loops and With without exiting the caller',
      () {
        final plan = _compile('''
Sub Main()
  With Worksheets("Summary")
    Call StopEarly()
    .Range("A1").Value2 = 3
  End With
End Sub
Sub StopEarly()
  With Worksheets("Other")
    For i = 1 To 2
      .Range("B1").Value2 = 2
      Exit Sub
      .Range("B1").Value2 = 999
    Next i
  End With
End Sub
''');
        expect(_values(plan), <Object?>[2, 3]);
        expect(plan.steps.map((step) => step.arguments['sheet']), <Object?>[
          'Other',
          'Summary',
        ]);
      },
    );

    test(
      'Exit For stops only the innermost loop without increment overflow',
      () {
        final plan = _compile('''
Sub Main()
  Dim i As Long, j As Long
  For i = 1 To 2
    For j = 2147483647 To 2147483647
      Worksheets(1).Cells(i, 1).Value2 = j
      Exit For
    Next j
    Worksheets(1).Cells(i, 2).Value2 = i
  Next i
End Sub
''');
        expect(_values(plan), <Object?>[2147483647, 1, 2147483647, 2]);
      },
    );

    test('nested argument functions run once and in left-to-right order', () {
      final plan = _compile('''
Sub Main()
  Call Sink(Mark(1), Mark(2))
  Worksheets(1).Range("A2").Value2 = Mark(3) + Mark(4)
End Sub
Function Mark(ByVal value As Long) As Long
  Worksheets(1).Range("A1").Value2 = value
  Mark = value
End Function
Sub Sink(ByVal first As Long, ByVal second As Long)
  Worksheets(1).Range("A2").Value2 = first * 10 + second
End Sub
''');
      expect(_values(plan), <Object?>[1, 2, 12, 3, 4, 7]);
    });

    test(
      'function result slots are fresh on every invocation and early exit',
      () {
        final plan = _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = Maybe(True)
  Worksheets(1).Range("A2").Value2 = Maybe(False)
End Sub
Function Maybe(ByVal assign As Boolean) As Long
  If assign Then
    Maybe = 9
    Exit Function
  End If
End Function
''');
        expect(_values(plan), <Object?>[9, 0]);
      },
    );

    test(
      'discarded Variant results are legal but cannot become cell values',
      () {
        const helper = '''
Function Probe() As Variant
  Worksheets(1).Range("A1").Value2 = 17
End Function
''';
        expect(
          _values(
            _compile('Sub Main()\nCall Probe()\nProbe\nEnd Sub\n$helper'),
          ),
          <Object?>[17, 17],
        );
        expect(
          () => _compile('''
Sub Main()
  Worksheets(1).Range("A2").Value2 = Probe()
End Sub
$helper
'''),
          throwsA(_error('vba_unsupported')),
        );
      },
    );

    test('completed invocations do not accumulate active frames', () {
      final plan = _compile('''
Sub Main()
  For i = 1 To 40
    Call EmptyHelper()
  Next i
End Sub
Sub EmptyHelper()
  Exit Sub
End Sub
''');
      expect(plan.steps, isEmpty);
    });
  });

  group('whole-module lexical checks', () {
    test(
      'callee cannot read caller locals or inherit the caller With target',
      () {
        expect(
          () => _compile('''
Option Explicit
Sub Main()
  Dim secret As Long
  secret = 7
  Helper
End Sub
Sub Helper()
  Worksheets(1).Range("A1").Value2 = secret
End Sub
'''),
          throwsA(_error('vba_name_error')),
        );
        expect(
          () => _compile('''
Sub Main()
  With Worksheets(1)
    Helper
  End With
End Sub
Sub Helper()
  .Range("A1").Value2 = 7
End Sub
'''),
          throwsA(_error('vba_unsupported')),
        );
      },
    );

    test('Exit For in a callee cannot target a caller loop', () {
      expect(
        () => _compile('''
Sub Main()
  For i = 1 To 2
    Helper
  Next i
End Sub
Sub Helper()
  Exit For
End Sub
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('unused procedures and text after Exit retain static checks', () {
      for (final helper in <String>[
        'Sub Unused()\nExit Sub\nShell "calc"\nEnd Sub',
        'Function Unused() As Long\nExit Function\nUnused = Worksheets(1).Range("A1").Value2\nEnd Function',
        'Sub Unused()\nExit Function\nEnd Sub',
        'Function Unused() As Long\nExit Sub\nEnd Function',
      ]) {
        expect(
          () => _compile('Sub Main()\nEnd Sub\n$helper'),
          throwsA(_error('vba_unsupported')),
          reason: helper,
        );
      }
    });

    test('dead calls still check arity and scalar versus object types', () {
      for (final call in <String>[
        'Call Takes()',
        'Call Takes(1, 2)',
        'Call Takes(Worksheets(1))',
        'Call Takes("wrong type")',
      ]) {
        expect(
          () => _compile('''
Sub Main()
End Sub
Sub Unused()
  Exit Sub
  If False Then
    $call
  End If
End Sub
Sub Takes(ByVal value As Long)
End Sub
'''),
          throwsA(_error('vba_type_error')),
          reason: call,
        );
      }
    });

    test(
      'unsupported argument conventions cannot hide in unused signatures',
      () {
        for (final parameter in <String>[
          'value As Long',
          'ByRef value As Long',
          'Optional ByVal value As Long',
          'ParamArray values()',
        ]) {
          expect(
            () => _compile(
              'Sub Main()\nEnd Sub\nSub Unused($parameter)\nEnd Sub',
            ),
            throwsA(_error('vba_unsupported')),
            reason: parameter,
          );
        }
      },
    );

    test(
      'parameter names cannot obscure procedure names case-insensitively',
      () {
        expect(
          () => _compile('''
Sub Main()
End Sub
Sub Helper(ByVal hElPeR As Long)
End Sub
'''),
          throwsA(_error('vba_name_error')),
        );
      },
    );
  });

  group('static call graph and shared budgets', () {
    test(
      'cycles are rejected even unused, after Exit, or only in arguments',
      () {
        for (final source in <String>[
          '''
Sub Main()
End Sub
Sub Unused()
  If False Then
    uNuSeD
  End If
End Sub
''',
          '''
Sub Main()
End Sub
Function First() As Long
  Exit Function
  First = Second()
End Function
Function Second() As Long
  Second = First()
End Function
''',
          '''
Sub Main()
End Sub
Sub Alpha()
  Call Sink(Beta())
End Sub
Sub Sink(ByVal value As Long)
End Sub
Function Beta() As Long
  Call Alpha()
End Function
''',
        ]) {
          expect(
            () => _compile(source),
            throwsA(_error('vba_unsupported')),
            reason: source,
          );
        }
      },
    );

    test('32 frames includes entry and 33 are rejected even unreachable', () {
      expect(_compile(_chain(32)).steps, isEmpty);
      expect(
        _compile(_chain(32, unused: true, afterExit: true)).steps,
        isEmpty,
      );
      for (final source in <String>[
        _chain(33),
        _chain(33, afterExit: true),
        _chain(33, unused: true, afterExit: true),
      ]) {
        expect(() => _compile(source), throwsA(_error('vba_limit_exceeded')));
      }
    });

    test('16 parameters and arguments work while 17 fail before execution', () {
      String parameters(int count) =>
          List<String>.generate(count, (i) => 'ByVal arg$i As Long').join(', ');
      String arguments(int count) =>
          List<String>.generate(count, (i) => '${i + 1}').join(', ');
      final sum = List<String>.generate(16, (i) => 'arg$i').join(' + ');
      final helper =
          '''
Function Total(${parameters(16)}) As Long
  Total = $sum
End Function
''';
      expect(
        _values(
          _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = Total(${arguments(16)})
End Sub
$helper
'''),
        ),
        <Object?>[136],
      );
      expect(
        () => _compile(
          'Sub Main()\nEnd Sub\nSub Unused(${parameters(17)})\nEnd Sub',
        ),
        throwsA(_error('vba_limit_exceeded')),
      );
      expect(
        () => _compile('''
Sub Main()
  Exit Sub
  Call Total(${arguments(17)})
End Sub
$helper
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('empty helper loops consume one work budget across invocations', () {
      const helper = '''
Sub Burn()
  For i = 1 To 60000
  Next i
End Sub
''';
      expect(_compile('Sub Main()\nBurn\nEnd Sub\n$helper').steps, isEmpty);
      expect(
        () => _compile('Sub Main()\nBurn\nBurn\nEnd Sub\n$helper'),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test(
      'range operations share the emitted-step budget across invocations',
      () {
        const helper = '''
Sub Paint()
  Worksheets(1).Range("A1:A6000").Value2 = 1
End Sub
''';
        expect(
          _compile('Sub Main()\nPaint\nEnd Sub\n$helper').steps,
          hasLength(6000),
        );
        expect(
          () => _compile('Sub Main()\nPaint\nPaint\nEnd Sub\n$helper'),
          throwsA(_error('vba_limit_exceeded')),
        );
      },
    );

    test('large values share the encoded-byte budget across invocations', () {
      final text = List<String>.filled(6000, 'x').join();
      final helper =
          '''
Sub Emit()
  Worksheets(1).Range("A1:A100").Value2 = "$text"
End Sub
''';
      expect(
        _compile('Sub Main()\nEmit\nEnd Sub\n$helper').steps,
        hasLength(100),
      );
      expect(
        () => _compile('Sub Main()\nEmit\nEmit\nEnd Sub\n$helper'),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  });
}
