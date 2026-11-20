import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(
  String source, {
  OfficeMacroFormat format = OfficeMacroFormat.xlsx,
}) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: switch (format) {
      OfficeMacroFormat.docx => 'vba-word',
      OfficeMacroFormat.pptx => 'vba-powerpoint',
      _ => 'vba-excel',
    },
    format: format,
    moduleName: 'Arguments',
    source: source,
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
  group('named helper arguments', () {
    for (final call in <String>[
      'Call Put(second:=2, FIRST:=1)',
      'Put second:=2, FIRST:=1',
      'Call Put(1, second:=2)',
      'Put 1, second:=2',
    ]) {
      test('binds case-insensitively: $call', () {
        expect(
          _values(
            _compile('''
Sub Main()
  $call
End Sub
Sub Put(ByVal first As Long, ByVal second As Long)
  Worksheets(1).Range("A1").Value2 = first
  Worksheets(1).Range("A2").Value2 = second
End Sub
'''),
          ),
          <Object?>[1, 2],
        );
      });
    }

    test('functions evaluate supplied expressions once in source order', () {
      final macro = _compile('''
Sub Main()
  Worksheets(1).Range("B1").Value2 = Pair(second:=Mark(2), first:=Mark(1))
  Call Pair(second:=Mark(4), first:=Mark(3))
End Sub
Function Mark(ByVal value As Long) As Long
  Worksheets(1).Range("A1").Value2 = value
  Mark = value
End Function
Function Pair(ByVal first As Long, ByVal second As Long) As Long
  Pair = first * 10 + second
End Function
''');
      expect(_values(macro), <Object?>[2, 1, 12, 4, 3]);
    });

    test('nested calls retain the caller With context', () {
      final macro = _compile('''
Sub Main()
  With Worksheets(1)
    Put amount:=DoubleIt(value:=5), target:=.Range("C3")
    .Range("D3").Value2 = 99
  End With
End Sub
Sub Put(ByVal target As Range, ByVal amount As Long)
  target.Value2 = amount
End Sub
Function DoubleIt(ByVal value As Long) As Long
  DoubleIt = value * 2
End Function
''');
      expect(_values(macro), <Object?>[10, 99]);
      expect(macro.steps.map((step) => step.arguments['cell']), <String>[
        'C3',
        'D3',
      ]);
    });

    test(
      'named delimiter remains distinct from colon statement separators',
      () {
        expect(
          _values(
            _compile('''
Sub Main()
  Put amount:=1: Put amount:=2 ' comment
  Put amount:= _
    3
End Sub
Sub Put(ByVal amount As Long)
  Worksheets(1).Range("A1").Value2 = amount
End Sub
'''),
          ),
          <Object?>[1, 2, 3],
        );
      },
    );
  });

  group('optional ByVal scalar parameters', () {
    test('uses declaration-time module constants and typed defaults', () {
      expect(
        _values(
          _compile('''
Option Explicit
Const BaseAmount As Long = 4
Const Label As String = "default"
Sub Main()
  Put
  Put amount:=8
End Sub
Sub Put(Optional ByVal amount As Long = BaseAmount * 3, _
    ByVal Optional text As String = Label & "!", _
    Optional ByVal flag As Boolean = Not False)
  Worksheets(1).Range("A1").Value2 = amount
  Worksheets(1).Range("A2").Value2 = text
  Worksheets(1).Range("A3").Value2 = flag
  amount = 999
End Sub
'''),
        ),
        <Object?>[12, 'default!', true, 8, 'default!', true],
      );
    });

    test('omitted typed scalar parameters receive their type defaults', () {
      expect(
        _values(
          _compile('''
Sub Main()
  Call Put()
End Sub
Sub Put(Optional ByVal count As Long, Optional ByVal amount As Double, _
    Optional ByVal text As String, Optional ByVal flag As Boolean)
  Worksheets(1).Range("A1").Value2 = count
  Worksheets(1).Range("A2").Value2 = amount
  Worksheets(1).Range("A3").Value2 = text
  Worksheets(1).Range("A4").Value2 = flag
End Sub
'''),
        ),
        <Object?>[0, 0.0, '', false],
      );
    });

    for (final call in <String>[
      'Call Put(, , 9)',
      'Put , , 9',
      'Call Put(, last:=9)',
      'Put last:=9',
    ]) {
      test('fills optional comma holes: $call', () {
        expect(
          _values(
            _compile('''
Sub Main()
  $call
End Sub
Sub Put(Optional ByVal first As Long = 1, _
    Optional ByVal second As Long = 2, Optional ByVal last As Long = 3)
  Worksheets(1).Range("A1").Value2 = first
  Worksheets(1).Range("A2").Value2 = second
  Worksheets(1).Range("A3").Value2 = last
End Sub
'''),
          ),
          <Object?>[1, 2, 9],
        );
      });
    }

    test(
      'function holes and trailing omissions retain parameter positions',
      () {
        expect(
          _values(
            _compile('''
Sub Main()
  Worksheets(1).Range("A1").Value2 = Pair(, 7)
  Worksheets(1).Range("A2").Value2 = Pair(8,)
  Worksheets(1).Range("A3").Value2 = Pair()
End Sub
Function Pair(Optional ByVal first As Long = 1, Optional ByVal second As Long = 2) As Long
  Pair = first * 10 + second
End Function
'''),
          ),
          <Object?>[17, 82, 12],
        );
      },
    );

    test(
      'explicit Empty uses typed conversion rather than the optional default',
      () {
        expect(
          _values(
            _compile('''
Sub Main()
  Call Put(Empty)
  Call Put()
End Sub
Sub Put(Optional ByVal count As Long = 8)
  Worksheets(1).Range("A1").Value2 = count
End Sub
'''),
          ),
          <Object?>[0, 8],
        );
      },
    );
  });

  group('Missing is distinct from Empty and Null', () {
    test('IsMissing distinguishes omitted and explicit Variant states', () {
      expect(
        _values(
          _compile('''
Sub Main()
  Inspect
  Inspect Empty
  Inspect Null
  Inspect "present"
End Sub
Sub Inspect(Optional ByVal item As Variant)
  Worksheets(1).Range("A1").Value2 = IsMissing(item)
  If IsMissing(item) Then
    Worksheets(1).Range("A2").Value2 = "missing"
  Else
    Worksheets(1).Range("A2").Value2 = IsEmpty(item)
    Worksheets(1).Range("A3").Value2 = IsNull(item)
  End If
End Sub
'''),
        ),
        <Object?>[
          true,
          'missing',
          false,
          true,
          false,
          false,
          false,
          true,
          false,
          false,
          false,
        ],
      );
    });

    test('default Variant and assignment both clear Missing', () {
      expect(
        _values(
          _compile('''
Sub Main()
  Defaults
  SetPresent
End Sub
Sub Defaults(Optional ByVal item = "default")
  Worksheets(1).Range("A1").Value2 = IsMissing(item)
  Worksheets(1).Range("A2").Value2 = item
End Sub
Sub SetPresent(Optional ByVal item)
  Worksheets(1).Range("A1").Value2 = IsMissing(item)
  item = Empty
  Worksheets(1).Range("A2").Value2 = IsMissing(item)
  Worksheets(1).Range("A3").Value2 = IsEmpty(item)
End Sub
'''),
        ),
        <Object?>[false, 'default', true, false, true],
      );
    });

    for (final expression in <String>[
      'item',
      'CVar(item)',
      'IsEmpty(item)',
      'IsNull(item)',
      'item & "x"',
      'item + 1',
      'item = Null',
    ]) {
      test('refuses an unhandled missing read: $expression', () {
        expect(
          () => _compile('''
Sub Main()
  Inspect
End Sub
Sub Inspect(Optional ByVal item)
  Worksheets(1).Range("A1").Value2 = $expression
End Sub
'''),
          throwsA(_error('vba_missing_argument')),
        );
      });
    }
  });

  group('argument diagnostics are static', () {
    final calls = <String, String>{
      'Call Put()': 'vba_type_error',
      'Call Put(, 2)': 'vba_type_error',
      'Call Put(first:=1, second:=2, third:=3)': 'vba_type_error',
      'Call Put(noSuchName:=1)': 'vba_name_error',
      'Call Put(first:=1, FIRST:=2)': 'vba_type_error',
      'Call Put(1, first:=2)': 'vba_type_error',
      'Call Put(first:=1, 2)': 'vba_type_error',
      'Call Put(first:=1,)': 'vba_type_error',
      'Call Put(second:=2)': 'vba_type_error',
      'Call Put(first:="wrong")': 'vba_type_error',
      'Call Put(first:=)': 'vba_syntax_error',
    };
    for (final entry in calls.entries) {
      test('checks unused call ${entry.key}', () {
        expect(
          () => _compile('''
Sub Main()
End Sub
Sub Unused()
  Exit Sub
  ${entry.key}
End Sub
Sub Put(ByVal first As Long, Optional ByVal second As Long = 2)
End Sub
'''),
          throwsA(_error(entry.value)),
        );
      });
    }

    final parameters = <String, String>{
      'Optional value As Long': 'vba_unsupported',
      'Optional ByRef value As Long': 'vba_unsupported',
      'Optional ByVal values() As Long': 'vba_unsupported',
      'Optional ByVal item As Range': 'vba_unsupported',
      'Optional ByVal item As Range = Nothing': 'vba_unsupported',
      'Optional ByVal value As Long, ByVal nextValue As Long':
          'vba_syntax_error',
      'ByVal value As Long = 1': 'vba_syntax_error',
      'Optional ByVal Optional value As Long': 'vba_syntax_error',
      'Optional ByVal value As Long = "text"': 'vba_type_error',
      'Optional ByVal value As Long = 1 / 0': 'vba_arithmetic_error',
      'Optional ByVal value As Long = 2147483648': 'vba_type_error',
      'Optional ByVal value As Long = 1.5': 'vba_type_error',
      'Optional ByVal value = Empty': 'vba_unsupported',
      'Optional ByVal value = Null': 'vba_unsupported',
      'Optional ByVal value = Nothing': 'vba_unsupported',
      'Optional ByVal value = Compute()': 'vba_unsupported',
      'ByVal first As Long, Optional ByVal value As Long = first':
          'vba_unsupported',
    };
    for (final entry in parameters.entries) {
      test('checks unused signature ${entry.key}', () {
        expect(
          () => _compile('''
Sub Main()
End Sub
Sub Unused(${entry.key})
End Sub
Function Compute() As Long
  Compute = 1
End Function
'''),
          throwsA(_error(entry.value)),
        );
      });
    }

    test('unknown named argument has its exact source location', () {
      expect(
        () => _compile('''Sub Main()
  Call Put(noSuchName:=1)
End Sub
Sub Put(Optional ByVal value As Long)
End Sub
'''),
        throwsA(
          _error('vba_name_error')
              .having((error) => error.moduleName, 'moduleName', 'Arguments')
              .having((error) => error.line, 'line', 2)
              .having((error) => error.column, 'column', 12),
        ),
      );
    });

    for (final expression in <String>[
      'IsMissing(Empty)',
      'IsMissing(Null)',
      'IsMissing(1)',
      'IsMissing(typed)',
      'IsMissing(required)',
      'IsMissing(item + 1)',
      'IsMissing(value:=item)',
    ]) {
      test('restricts IsMissing target $expression', () {
        expect(
          () => _compile('''
Sub Main()
End Sub
Sub Unused(ByVal required As Variant, Optional ByVal typed As Long, Optional ByVal item)
  Worksheets(1).Range("A1").Value2 = $expression
End Sub
'''),
          throwsA(_error('vba_unsupported')),
        );
      });
    }

    test(
      'entry point remains parameterless even with only optional parameters',
      () {
        expect(
          () => _compile('Sub Main(Optional ByVal value As Long)\nEnd Sub'),
          throwsA(_error('vba_entry_point')),
        );
      },
    );

    for (final expression in <String>[
      'RGB(red:=1, green:=2, blue:=3)',
      'Len(text:="hello")',
      'Worksheets(index:=1)',
      'Worksheets(1).Range(address:="A1")',
    ]) {
      test('refuses object-model or intrinsic named arguments $expression', () {
        expect(
          () => _compile('''
Sub Main()
  Dim value
  value = $expression
End Sub
'''),
          throwsA(_error('vba_unsupported')),
        );
      });
    }
  });

  group('shared compilation budgets', () {
    test('optional defaults still count toward the parameter limit', () {
      final parameters = List<String>.generate(
        17,
        (index) => 'Optional ByVal argument$index As Long',
      ).join(', ');
      expect(
        () => _compile('Sub Main()\nEnd Sub\nSub Many($parameters)\nEnd Sub'),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('repeated large default strings share the copy-work budget', () {
      final text = 'a' * 20000;
      expect(
        () => _compile('''
Sub Main()
  Dim index As Long
  For index = 1 To 6
    Call Work()
  Next index
End Sub
Sub Work(Optional ByVal text As String = "$text")
End Sub
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('default expressions in unused procedures retain string limits', () {
      final text = 'a' * 20000;
      expect(
        () => _compile('''
Sub Main()
End Sub
Sub Unused(Optional ByVal text As String = "$text" & "$text")
End Sub
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  });
}
