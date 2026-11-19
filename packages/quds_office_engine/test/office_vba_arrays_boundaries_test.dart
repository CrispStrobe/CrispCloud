import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    source: source,
    format: OfficeMacroFormat.xlsx,
    moduleName: 'ArrayBoundaries',
    entryPoint: 'Main',
  ),
);

String _module(String body) => 'Sub Main()\n$body\nEnd Sub';

String _unused(String body) =>
    'Sub Main()\nEnd Sub\nSub Unused()\n$body\nEnd Sub';

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>().having(
      (error) => error.code,
      'code',
      code,
    );

List<Object?> _values(OfficeMacro plan) => <Object?>[
  for (final step in plan.steps) step.arguments['value'],
];

String _allocationChain(int frames) {
  final result = StringBuffer();
  for (var index = 0; index < frames; index++) {
    final name = index == 0 ? 'Main' : 'Helper$index';
    final next = index + 1;
    result.writeln('Sub $name()');
    result.writeln('Dim values(0 To 4095) As Long');
    if (next < frames) result.writeln('Call Helper$next()');
    result.writeln('End Sub');
  }
  return result.toString();
}

String _nestedEachChain(int frames, int blocks) {
  final result = StringBuffer();
  for (var frame = 0; frame < frames; frame++) {
    final name = frame == 0 ? 'Main' : 'Helper$frame';
    final next = frame + 1;
    result.writeln('Sub $name()');
    result.writeln('Dim values(0) As Long');
    for (var block = 0; block < blocks; block++) {
      result.writeln('Dim item$block As Variant');
    }
    for (var block = 0; block < blocks; block++) {
      result.writeln('For Each item$block In values');
    }
    if (next < frames) {
      result.writeln('Call Helper$next()');
    } else {
      final unary = List<String>.filled(63, '+ ').join();
      result.writeln('Worksheets(1).Range("A1").Value2 = ${unary}1');
    }
    for (var block = blocks - 1; block >= 0; block--) {
      result.writeln('Next item$block');
    }
    result.writeln('End Sub');
  }
  return result.toString();
}

void main() {
  group('array bounds are finite portable constant shapes', () {
    test('narrow arrays retain both signed 32-bit endpoint indexes', () {
      final plan = _compile(
        _module('''
Dim low(-2147483648 To -2147483647) As Long
Dim high(2147483646 To 2147483647) As Long
low(-2147483648) = 11
low(-2147483647) = 12
high(2147483646) = 21
high(2147483647) = 22
Worksheets(1).Range("A1").Value2 = LBound(low)
Worksheets(1).Range("A2").Value2 = UBound(high)
Worksheets(1).Range("A3").Value2 = low(-2147483648)
Worksheets(1).Range("A4").Value2 = low(-2147483647)
Worksheets(1).Range("A5").Value2 = high(2147483646)
Worksheets(1).Range("A6").Value2 = high(2147483647)
'''),
      );
      expect(_values(plan), <Object?>[-2147483648, 2147483647, 11, 12, 21, 22]);
    });

    test('exact 4096-slot array supports its last slot and full traversal', () {
      final plan = _compile(
        _module('''
Dim values(-2048 To 2047) As Long, item As Variant, count As Long
values(2047) = 17
For Each item In values
  count = count + 1
Next item
Worksheets(1).Range("A1").Value2 = count
Worksheets(1).Range("A2").Value2 = values(2047)
'''),
      );
      expect(_values(plan), <Object?>[4096, 17]);
    });

    for (final bounds in <String>[
      '0 To 4096',
      '-2048 To 2048',
      '-2147483648 To -2147479552',
      '0 To 2147483647',
      '-2147483648 To 2147483647',
    ]) {
      test('oversized $bounds is rejected even in unused procedure', () {
        expect(
          () => _compile(_unused('Dim values($bounds) As Long\nExit Sub')),
          throwsA(_error('vba_limit_exceeded')),
        );
      });
    }

    for (final bounds in <String>[
      '2 To 1',
      '-1',
      '-2147483649 To -2147483648',
      '2147483647 To 2147483648',
      '0.5 To 2',
      '0 To 2.5',
      '"0" To 2',
      '0 To True',
    ]) {
      test('invalid constant bounds $bounds fail in unused code', () {
        expect(
          () => _compile(_unused('Dim values($bounds) As Long')),
          throwsA(_error('vba_type_error')),
        );
      });
    }

    test('prior constant expressions determine signed bounds exactly', () {
      final plan = _compile('''
Option Explicit
Const Base As Long = -2147483648
Sub Main()
  Const Last As Long = Base + 2
  Dim values(Base To Last) As Double
  values(Base + 1) = 2.5
  Worksheets(1).Range("A1").Value2 = LBound(values, 1)
  Worksheets(1).Range("A2").Value2 = UBound(values, 1)
  Worksheets(1).Range("A3").Value2 = values(Base + 1)
End Sub
''');
      expect(_values(plan), <Object?>[-2147483648, -2147483646, 2.5]);
    });

    for (final body in <String>[
      'Dim count As Long\nDim values(count) As Long',
      'Dim values(Later) As Long\nConst Later As Long = 2',
      'Dim values(Worksheets(1).Range("A1").Value2) As Long',
      'Dim values(LBound(other)) As Long\nDim other(2) As Long',
    ]) {
      test('nonconstant declaration shape is rejected: $body', () {
        expect(
          () => _compile(_unused(body)),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }

    test(
      'bounds cannot call a user function even if it returns a constant',
      () {
        expect(
          () => _compile('''
Sub Main()
End Sub
Sub Unused()
  Dim values(Size()) As Long
End Sub
Function Size() As Long
  Size = 2
End Function
'''),
          throwsA(_error('vba_unsupported')),
        );
      },
    );

    for (final declaration in <String>[
      'Dim values() As Long',
      'Dim values(1 To 2, 1 To 2) As Long',
      'Dim values(1 To 2) As Range',
      'Dim values(1 To 2) As Worksheet',
      'Const values(1 To 2) As Long = 0',
    ]) {
      test('unsupported declaration is rejected: $declaration', () {
        expect(
          () => _compile(_unused(declaration)),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }

    test(
      'array declaration cannot be global or hidden inside a dead block',
      () {
        for (final source in <String>[
          'Dim values(2) As Long\nSub Main()\nEnd Sub',
          _module('If False Then\nDim values(2) As Long\nEnd If'),
          _module('Do While False\nDim values(2) As Long\nLoop'),
        ]) {
          expect(
            () => _compile(source),
            throwsA(_error('vba_unsupported')),
            reason: source,
          );
        }
      },
    );

    for (final keyword in <String>['LBound', 'uBoUnD']) {
      test('bound builtin $keyword cannot be shadowed', () {
        expect(
          () => _compile(_unused('Dim $keyword(2) As Long')),
          throwsA(_error('vba_name_error')),
        );
      });
    }
  });

  group('array indexing has explicit diagnostics and scalar storage', () {
    for (final index in <String>['0', '3', '-2147483648', '2147483647']) {
      for (final write in <bool>[false, true]) {
        final access = write ? 'write' : 'read';
        test('$access index $index outside 1..2 fails', () {
          final operation = write
              ? 'values($index) = 4'
              : 'Worksheets(1).Range("A1").Value2 = values($index)';
          expect(
            () => _compile(_module('Dim values(1 To 2) As Long\n$operation')),
            throwsA(
              _error('vba_subscript_out_of_range')
                  .having(
                    (error) => error.moduleName,
                    'module',
                    'ArrayBoundaries',
                  )
                  .having((error) => error.entryPoint, 'entry point', 'Main')
                  .having((error) => error.line, 'line', greaterThan(0))
                  .having((error) => error.column, 'column', greaterThan(0)),
            ),
          );
        });
      }
    }

    for (final index in <String>['1.5', '"1"', 'True']) {
      test('index $index is not coerced to an integer', () {
        expect(
          () => _compile(
            _module('''
Dim values(1 To 2) As Long
values($index) = 4
'''),
          ),
          throwsA(_error('vba_type_error')),
        );
      });
    }

    test('integral doubles and negative zero are valid indexes', () {
      final plan = _compile(
        _module('''
Dim values(0 To 1) As Long
values(-0.0) = 7
values(1.0) = 8
Worksheets(1).Range("A1").Value2 = values(0)
Worksheets(1).Range("A2").Value2 = values(1)
'''),
      );
      expect(_values(plan), <Object?>[7, 8]);
    });

    test('read and write index functions each execute once', () {
      final plan = _compile('''
Sub Main()
  Dim values(1 To 1) As Long
  Let values(Index()) = 42
  Worksheets(1).Range("A2").Value2 = values(Index())
End Sub
Function Index() As Long
  Worksheets(1).Range("A1").Value2 = 7
  Index = 1
End Function
''');
      expect(_values(plan), <Object?>[7, 7, 42]);
    });

    for (final operation in <String>[
      'values() = 1',
      'values(0, 1) = 1',
      'Worksheets(1).Range("A1").Value2 = values()',
      'Worksheets(1).Range("A1").Value2 = values(0, 1)',
      'Set values(0) = Worksheets(1).Range("A1")',
      'values(0).Value2 = 7',
    ]) {
      test(
        'invalid index/object shape remains checked after Exit: $operation',
        () {
          expect(
            () => _compile(
              _unused('Dim values(0 To 1) As Long\nExit Sub\n$operation'),
            ),
            throwsA(isA<OfficeVbaCompileException>()),
          );
        },
      );
    }

    for (final (type, value) in <(String, String)>[
      ('Long', '1.5'),
      ('Long', '2147483648'),
      ('Long', '"1"'),
      ('Double', 'True'),
      ('String', '1'),
      ('Boolean', '1'),
      ('Variant', 'Worksheets(1)'),
      ('Variant', 'Worksheets(1).Range("A1")'),
    ]) {
      test('$type slot rejects incompatible $value', () {
        expect(
          () => _compile(_module('Dim values(0) As $type\nvalues(0) = $value')),
          throwsA(_error('vba_type_error')),
        );
      });
    }

    test('unused code still checks element assignment types and names', () {
      for (final statement in <String>[
        'values(0) = "wrong"',
        'values(missing) = 1',
        'values(True) = 1',
        'Worksheets(1).Range("A1").Value2 = values("0")',
      ]) {
        expect(
          () => _compile('''
Option Explicit
Sub Main()
End Sub
Sub Unused()
  Dim values(0) As Long
  Exit Sub
  If False Then
    $statement
  End If
End Sub
'''),
          throwsA(isA<OfficeVbaCompileException>()),
          reason: statement,
        );
      }
    });

    test(
      'For Each binding reads an Empty Variant even if its body does not',
      () {
        expect(
          () => _compile(
            _module('''
Dim values(0 To 2) As Variant, item As Variant, count As Long
For Each item In values
  count = count + 1
Next item
Worksheets(1).Range("A1").Value2 = count
'''),
          ),
          throwsA(_error('vba_unsupported')),
        );
      },
    );

    test('early Exit For does not read later uninitialized Variant slots', () {
      final plan = _compile(
        _module('''
Dim values(0 To 2) As Variant, item As Variant
values(0) = 7
For Each item In values
  Worksheets(1).Range("A1").Value2 = item
  Exit For
Next item
'''),
      );
      expect(_values(plan), <Object?>[7]);
    });
  });

  group('arrays cannot escape through scalar or object APIs', () {
    for (final operation in <String>[
      'copy = values',
      'values = 1',
      'values = other',
      'values(0) = other',
      'copy = LBound',
      'Worksheets(1).Range("A1").Value2 = values',
      'Worksheets(1).Range("A1").Value2 = values & ""',
      'If values = other Then\nEnd If',
      'If values Then\nEnd If',
      'Select Case values\nCase Else\nEnd Select',
      'With values\nEnd With',
      'Set target = values',
      'ReDim values(4)',
      'Erase values',
    ]) {
      test('array escape stays invalid in inactive code: $operation', () {
        expect(
          () => _compile(
            _unused('''
Dim values(0) As Variant, other(0) As Variant, copy As Variant, target As Range
Exit Sub
If False Then
  $operation
End If
'''),
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }

    test('whole arrays cannot be passed ByVal as Variant or typed scalar', () {
      for (final type in <String>['Variant', 'Long', 'Range']) {
        expect(
          () => _compile('''
Sub Main()
End Sub
Sub Unused()
  Dim values(0) As Long
  Exit Sub
  Call Sink(values)
End Sub
Sub Sink(ByVal value As $type)
End Sub
'''),
          throwsA(_error('vba_type_error')),
          reason: type,
        );
      }
    });

    test('whole arrays cannot be returned by a Variant function', () {
      expect(
        () => _compile('''
Sub Main()
End Sub
Function Unused() As Variant
  Dim values(0) As Long
  Unused = values
End Function
'''),
        throwsA(_error('vba_type_error')),
      );
    });

    test('array parameter syntax is unsupported in unused helpers', () {
      for (final parameter in <String>[
        'ByVal values() As Long',
        'ByVal values(0 To 1) As Long',
        'ByRef values() As Variant',
        'ParamArray values()',
      ]) {
        expect(
          () =>
              _compile('Sub Main()\nEnd Sub\nSub Unused($parameter)\nEnd Sub'),
          throwsA(isA<OfficeVbaCompileException>()),
          reason: parameter,
        );
      }
    });

    test('scalar element arguments remain isolated ByVal copies', () {
      final plan = _compile('''
Sub Main()
  Dim values(0) As Long
  values(0) = 7
  Call Rewrite(values(0))
  Worksheets(1).Range("A2").Value2 = values(0)
End Sub
Sub Rewrite(ByVal value As Long)
  value = 99
  Worksheets(1).Range("A1").Value2 = value
End Sub
''');
      expect(_values(plan), <Object?>[99, 7]);
    });

    for (final expression in <String>[
      'LBound(1)',
      'UBound("values")',
      'LBound(values(0))',
      'UBound(Worksheets(1).Range("A1"))',
      'LBound()',
      'UBound(values, 1, 1)',
    ]) {
      test('invalid bound query is statically checked: $expression', () {
        expect(
          () => _compile(
            _unused('''
Dim values(0) As Long
Exit Sub
Worksheets(1).Range("A1").Value2 = $expression
'''),
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }

    for (final dimension in <String>['0', '2', '-1', '2147483647']) {
      test('nonexistent dimension $dimension has subscript diagnostic', () {
        expect(
          () => _compile(
            _module('''
Dim values(0 To 1) As Long
Worksheets(1).Range("A1").Value2 = UBound(values, $dimension)
'''),
          ),
          throwsA(_error('vba_subscript_out_of_range')),
        );
      });
    }

    for (final dimension in <String>['1.5', '"1"', 'True']) {
      test('dimension $dimension cannot be coerced', () {
        expect(
          () => _compile(
            _module('''
Dim values(0 To 1) As Long
Worksheets(1).Range("A1").Value2 = LBound(values, $dimension)
'''),
          ),
          throwsA(_error('vba_type_error')),
        );
      });
    }
  });

  group('For Each keeps typed controls and captures its collection', () {
    for (final type in <String>[
      'Long',
      'Double',
      'String',
      'Boolean',
      'Range',
    ]) {
      test('array iteration rejects $type controller even on dead path', () {
        expect(
          () => _compile(
            _unused('''
Dim values(0) As Long, item As $type
Exit Sub
For Each item In values
Next item
'''),
          ),
          throwsA(_error('vba_type_error')),
        );
      });
    }

    test('array control itself cannot be an array or a constant', () {
      for (final declaration in <String>[
        'Dim item(0) As Variant',
        'Const item = 1',
      ]) {
        expect(
          () => _compile(
            _unused('''
Dim values(0) As Long
$declaration
For Each item In values
Next item
'''),
          ),
          throwsA(_error('vba_type_error')),
          reason: declaration,
        );
      }
    });

    test('Option Explicit requires a declared For Each controller', () {
      expect(
        () => _compile('''
Option Explicit
Sub Main()
  Dim values(0) As Long
  For Each missing In values
  Next missing
End Sub
'''),
        throwsA(_error('vba_name_error')),
      );
    });

    test('implicit array controllers are scalar Variants', () {
      final plan = _compile(
        _module('''
Dim values(0) As Long
values(0) = 3
For Each item In values
  Worksheets(1).Range("A1").Value2 = item
Next item
item = "finished"
Worksheets(1).Range("A2").Value2 = item
'''),
      );
      expect(_values(plan), <Object?>[3, 'finished']);
    });

    test('controller assignment is a copy while future slots remain live', () {
      final plan = _compile(
        _module('''
Dim values(0 To 2) As Long, item As Variant, seen As Long
values(0) = 1
values(1) = 2
values(2) = 3
For Each item In values
  seen = seen + 1
  Worksheets(1).Cells(seen, 1).Value2 = item
  values(2) = 30
  item = 999
Next item
Worksheets(1).Range("B1").Value2 = values(0)
Worksheets(1).Range("B2").Value2 = values(1)
Worksheets(1).Range("B3").Value2 = values(2)
'''),
      );
      expect(_values(plan), <Object?>[1, 2, 30, 1, 2, 30]);
    });

    for (final declaration in <String>[
      'Dim cell As Variant',
      'Dim cell As Worksheet',
      '',
    ]) {
      test(
        'Range traversal requires an explicitly typed Range: $declaration',
        () {
          expect(
            () => _compile(
              _unused('''
$declaration
For Each cell In Worksheets(1).Range("A1:B2")
Next cell
'''),
            ),
            throwsA(_error('vba_type_error')),
          );
        },
      );
    }

    for (final expression in <String>[
      '1',
      '"A1:B2"',
      'Worksheets(1)',
      'values(0)',
      'Worksheets(1).Range("A1").Value2',
    ]) {
      test('unsupported iteration collection is rejected: $expression', () {
        expect(
          () => _compile(
            _unused('''
Dim values(0) As Long, item As Variant
Exit Sub
For Each item In $expression
Next item
'''),
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }

    test('Range source is captured before source and controller rebinding', () {
      final plan = _compile(
        _module('''
Dim source As Range, cell As Range
Set source = Worksheets("Summary").Range("B2:C3")
For Each cell In source
  cell.Value2 = cell.Row * 100 + cell.Column
  Set source = Worksheets("Other").Range("Z9")
  Set cell = Worksheets("Other").Range("Y8")
Next cell
Worksheets("Summary").Range("A1").Value2 = source.Row
Worksheets("Summary").Range("A2").Value2 = cell.Column
'''),
      );
      expect(_values(plan), <Object?>[202, 203, 302, 303, 9, 25]);
      expect(plan.steps.take(4).map((step) => step.arguments['cell']), <String>[
        'B2',
        'C2',
        'B3',
        'C3',
      ]);
      expect(
        plan.steps.take(4).map((step) => step.arguments['sheet']),
        everyElement('Summary'),
      );
    });

    test(
      'Range collection function arguments execute once before traversal',
      () {
        final plan = _compile('''
Sub Main()
  Dim cell As Range
  For Each cell In Worksheets(1).Range(Address())
    cell.Value2 = cell.Column
  Next cell
End Sub
Function Address() As String
  Worksheets(1).Range("D1").Value2 = 9
  Address = "A1:C1"
End Function
''');
        expect(_values(plan), <Object?>[9, 1, 2, 3]);
      },
    );

    for (final operation in <String>[
      'cell.Row = 1',
      'cell.Column = 1',
      'Worksheets(1).Range("A1").Value2 = cell.Value2',
      'Worksheets(1).Range("A1").Value2 = cell.Formula',
      'copy = cell',
      'Set copy = cell',
    ]) {
      test(
        'Range loop preserves readonly/write-only boundaries: $operation',
        () {
          expect(
            () => _compile(
              _unused('''
Dim cell As Range, copy As Variant
For Each cell In Worksheets(1).Range("A1")
  If False Then
    $operation
  End If
Next cell
'''),
            ),
            throwsA(isA<OfficeVbaCompileException>()),
          );
        },
      );
    }
  });

  group('active loop controls and procedure frames unwind consistently', () {
    for (final loops in <String>[
      'For Each item In values\nFor Each item In values\nNext item\nNext item',
      'For Each item In values\nFor item = 1 To 2\nNext item\nNext item',
      'For item = 1 To 2\nFor Each item In values\nNext item\nNext item',
      'For Each item In values\nDo While False\nFor Each ITEM In values\nNext ITEM\nLoop\nNext item',
    ]) {
      test('nested reuse is rejected even when inactive: $loops', () {
        expect(
          () => _compile(
            _unused('''
Dim values(0) As Long, item As Variant
Exit Sub
$loops
'''),
          ),
          throwsA(_error('vba_unsupported')),
        );
      });
    }

    test('numeric For counter is not assignable inside an array traversal', () {
      expect(
        () => _compile(
          _module('''
Dim values(0) As Long, item As Variant, row As Long
For row = 1 To 2
  For Each item In values
    If False Then
      row = 9
    End If
  Next item
Next row
'''),
        ),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('Exit For targets nearest mixed loop and retains outer iteration', () {
      final plan = _compile(
        _module('''
Dim values(0 To 1) As Long, item As Variant, row As Long
values(0) = 3
values(1) = 7
For row = 1 To 2
  For Each item In values
    Do
      With Worksheets(1)
        .Cells(row, 1).Value2 = item
        Exit For
      End With
    Loop
  Next item
  Worksheets(1).Cells(row, 2).Value2 = row
Next row
For Each item In values
  For row = 1 To 2
    Worksheets(1).Range("C1").Value2 = item
    Exit For
  Next row
Next item
'''),
      );
      expect(_values(plan), <Object?>[3, 1, 3, 2, 3, 7]);
    });

    test(
      'Exit Do unwinds inner each and With then permits controller reuse',
      () {
        final plan = _compile(
          _module('''
Dim values(0 To 1) As Long, item As Variant
values(0) = 3
values(1) = 7
With Worksheets("Summary")
  Do
    For Each item In values
      With Worksheets("Other")
        .Range("A1").Value2 = item
        Exit Do
      End With
    Next item
  Loop
  For Each item In values
    .Range("B1").Value2 = item
  Next item
End With
'''),
        );
        expect(_values(plan), <Object?>[3, 3, 7]);
        expect(plan.steps.map((step) => step.arguments['sheet']), <String>[
          'Other',
          'Summary',
          'Summary',
        ]);
      },
    );

    test('callee can reuse caller names and Exit Sub restores caller With', () {
      final plan = _compile('''
Option Explicit
Sub Main()
  Dim values(0 To 1) As Long, item As Variant
  values(0) = 3
  values(1) = 7
  With Worksheets("Summary")
    For Each item In values
      Call Helper()
      .Range("A1").Value2 = item
    Next item
  End With
End Sub
Sub Helper()
  Dim values(0) As Long, item As Variant
  values(0) = 99
  For Each item In values
    With Worksheets("Other")
      .Range("B1").Value2 = item
      Exit Sub
    End With
  Next item
End Sub
''');
      expect(_values(plan), <Object?>[99, 3, 99, 7]);
      expect(plan.steps.map((step) => step.arguments['sheet']), <String>[
        'Other',
        'Summary',
        'Other',
        'Summary',
      ]);
    });

    test('callee cannot target caller each with Exit For', () {
      expect(
        () => _compile('''
Sub Main()
  Dim values(0) As Long, item As Variant
  For Each item In values
    Call Helper()
  Next item
End Sub
Sub Helper()
  Exit For
End Sub
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('index function edges participate in unused recursion validation', () {
      expect(
        () => _compile('''
Sub Main()
End Sub
Function Recursive() As Long
  Dim values(0) As Long
  Exit Function
  Recursive = values(Recursive())
End Function
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('separate invocations receive fresh scalar array storage', () {
      final plan = _compile('''
Sub Main()
  Call Helper()
  Call Helper()
End Sub
Sub Helper()
  Dim values(0) As Long
  Worksheets(1).Range("A1").Value2 = values(0)
  values(0) = 9
End Sub
''');
      expect(_values(plan), <Object?>[0, 0]);
    });
  });

  group('arrays and iteration share compilation resource limits', () {
    for (final type in <String>['String', 'Variant']) {
      test('$type slots honor exact aggregate string bound and one over', () {
        final text = List<String>.filled(32767, 'x').join();
        String filled(int tail) {
          final end = List<String>.filled(tail, 'y').join();
          return _module('''
Const Text As String = "$text"
Dim values(0 To 32) As $type, index As Long
For index = 0 To 31
  values(index) = Text
Next index
values(32) = "$end"
''');
        }

        expect(_compile(filled(32)).steps, isEmpty);
        expect(
          () => _compile(filled(33)),
          throwsA(_error('vba_limit_exceeded')),
        );
      });
    }

    test(
      'array string budget counts UTF-16 units, including surrogate pairs',
      () {
        final pairs = List<String>.filled(16383, '😀').join();
        final text = '${pairs}x';
        String filled(int tail) {
          final end = List<String>.filled(tail, 'y').join();
          return _module('''
Const Text As String = "$text"
Dim values(0 To 32) As String, index As Long
For index = 0 To 31
  values(index) = Text
Next index
values(32) = "$end"
''');
        }

        expect(_compile(filled(32)).steps, isEmpty);
        expect(
          () => _compile(filled(33)),
          throwsA(_error('vba_limit_exceeded')),
        );
      },
    );

    test('same-value writes preserve budget and replacing a slot frees it', () {
      final text = List<String>.filled(32767, 'x').join();
      final tail = List<String>.filled(32, 'y').join();
      final plan = _compile(
        _module('''
Const Text As String = "$text"
Dim values(0 To 32) As String, index As Long
For index = 0 To 31
  values(index) = Text
Next index
values(32) = "$tail"
values(0) = values(0)
values(0) = ""
values(32) = Text
Worksheets(1).Range("A1").Value2 = values(0)
'''),
      );
      expect(_values(plan), <Object?>['']);
    });

    test(
      'array string occupancy is shared across frames and released on exit',
      () {
        final text = List<String>.filled(32767, 'x').join();
        String source(int tail) {
          final end = List<String>.filled(tail, 'y').join();
          return '''
Sub Main()
  Const Text As String = "$text"
  Dim values(0 To 31) As String, index As Long
  For index = 0 To 31
    values(index) = Text
  Next index
  Call Extra("$end")
  Call Extra("$end")
End Sub
Sub Extra(ByVal text As String)
  Dim values(0) As String
  values(0) = text
  Exit Sub
End Sub
''';
        }

        expect(_compile(source(32)).steps, isEmpty);
        expect(
          () => _compile(source(33)),
          throwsA(_error('vba_limit_exceeded')),
        );
      },
    );

    test('16384 active slots across four frames work; a fifth frame fails', () {
      expect(_compile(_allocationChain(4)).steps, isEmpty);
      expect(
        () => _compile(_allocationChain(5)),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('one procedure may use four 4096-slot arrays but not five', () {
      String arrays(int count) => List<String>.generate(
        count,
        (index) => 'Dim values$index(0 To 4095) As Long',
      ).join('\n');
      expect(_compile(_module(arrays(4))).steps, isEmpty);
      expect(
        () => _compile(_module(arrays(5))),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test(
      'sequential early returns release slots while allocations charge work',
      () {
        const helper = '''
Sub Allocate()
  Dim values(0 To 4095) As Long, item As Variant
  For Each item In values
    Exit Sub
  Next item
End Sub
''';
        String repeat(int count) =>
            '''
Sub Main()
  For repeat = 1 To $count
    Call Allocate()
  Next repeat
End Sub
$helper
''';
        expect(_compile(repeat(20)).steps, isEmpty);
        expect(
          () => _compile(repeat(25)),
          throwsA(_error('vba_limit_exceeded')),
        );
      },
    );

    test('unused procedures do not allocate active array storage', () {
      final helpers = List<String>.generate(
        20,
        (index) =>
            '''
Sub Unused$index()
  Dim values(0 To 4095) As Long
End Sub
''',
      ).join();
      expect(_compile('Sub Main()\nEnd Sub\n$helpers').steps, isEmpty);
    });

    test('empty-body iteration still consumes cumulative work', () {
      expect(
        () => _compile(
          _module('''
Dim values(0 To 4095) As Long, item As Variant, repeat As Long
For repeat = 1 To 30
  For Each item In values
  Next item
Next repeat
'''),
        ),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    for (final range in <String>['A1:A100001', 'A1:XFD1048576']) {
      test('oversized range $range fails even with empty body', () {
        expect(
          () => _compile(
            _module('''
Dim cell As Range
For Each cell In Worksheets(1).Range("$range")
Next cell
'''),
          ),
          throwsA(_error('vba_limit_exceeded')),
        );
      });
    }

    test('For Each emitted operations retain the shared 10000-step cap', () {
      expect(
        () => _compile(
          _module('''
Dim cell As Range
For Each cell In Worksheets(1).Range("A1:A10001")
  cell.Value2 = 1
Next cell
'''),
        ),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('array strings do not bypass the per-string limit', () {
      final text = List<String>.filled(20000, 'x').join();
      expect(
        () => _compile(
          _module('''
Dim values(0) As String
values(0) = "$text"
values(0) = values(0) & values(0)
'''),
        ),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('array iteration retains the encoded-plan byte cap', () {
      final text = List<String>.filled(20000, 'x').join();
      expect(
        () => _compile(
          _module('''
Dim values(0 To 29) As String, index As Long, item As Variant
For index = LBound(values) To UBound(values)
  values(index) = "$text"
Next index
For Each item In values
  Worksheets(1).Range("A1:B1").Value2 = item
Next item
'''),
        ),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('32 frames with 32 each blocks and 63 unary operators compose', () {
      expect(_values(_compile(_nestedEachChain(32, 32))), <Object?>[1]);
    });

    test('33 For Each blocks fail the shared nesting boundary', () {
      expect(
        () => _compile(_nestedEachChain(1, 33)),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('33 procedure frames fail before any array traversal executes', () {
      expect(
        () => _compile(_nestedEachChain(33, 1)),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  });
}
