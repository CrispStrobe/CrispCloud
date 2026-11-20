import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    source: source,
    moduleName: 'DynamicArrays',
  ),
);

String _module(String body) => 'Sub Main()\n$body\nEnd Sub';

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

String _stringOccupancy(String after, {String type = 'String'}) {
  final longText = List<String>.filled(32767, 'x').join();
  final smallText = List<String>.filled(32, 'y').join();
  return _module('''
Dim data() As $type, other() As String, index As Long
ReDim data(0 To 32)
For index = 0 To 31
  data(index) = "$longText"
Next index
data(32) = "$smallText"
$after
''');
}

String _allocationChain(int frames) {
  final source = StringBuffer();
  for (var index = 0; index < frames; index++) {
    final name = index == 0 ? 'Main' : 'Helper$index';
    source.writeln('Sub $name()');
    source.writeln('Dim data() As Long');
    source.writeln('ReDim data(0 To 4095)');
    if (index + 1 < frames) source.writeln('Call Helper${index + 1}()');
    source.writeln('End Sub');
  }
  return source.toString();
}

void main() {
  group('dynamic array allocation and resizing', () {
    test('allocates each scalar element type with its typed default', () {
      final macro = _compile(
        _module('''
Dim ints() As Long, doubles() As Double, texts() As String
Dim flags() As Boolean, variants() As Variant, inferred()
ReDim ints(1), doubles(1), texts(1), flags(1), variants(1), inferred(1)
variants(0) = "variant"
inferred(0) = True
Worksheets(1).Range("A1").Value2 = ints(0)
Worksheets(1).Range("A2").Value2 = doubles(0)
Worksheets(1).Range("A3").Value2 = texts(0)
Worksheets(1).Range("A4").Value2 = flags(0)
Worksheets(1).Range("A5").Value2 = variants(0)
Worksheets(1).Range("A6").Value2 = inferred(0)
'''),
      );
      expect(_values(macro), <Object?>[0, 0.0, '', false, 'variant', true]);
    });

    test('declaring or erasing an unallocated array needs no storage', () {
      expect(
        _compile(
          _module('''
Dim data() As Long
Erase data, data
'''),
        ).steps,
        isEmpty,
      );
    });

    test('Preserve grows, shrinks, and discards truncated values', () {
      final macro = _compile(
        _module('''
Dim data() As Long
ReDim data(-2 To 0)
data(-2) = 11
data(-1) = 22
data(0) = 33
ReDim Preserve data(-2 To 2)
Worksheets(1).Range("A1").Value2 = data(-2)
Worksheets(1).Range("A2").Value2 = data(0)
Worksheets(1).Range("A3").Value2 = data(2)
data(1) = 44
ReDim Preserve data(-2 To -1)
ReDim Preserve data(-2 To 1)
Worksheets(1).Range("A4").Value2 = data(-1)
Worksheets(1).Range("A5").Value2 = data(0)
Worksheets(1).Range("A6").Value2 = data(1)
Worksheets(1).Range("A7").Value2 = UBound(data)
'''),
      );
      expect(_values(macro), <Object?>[11, 33, 0, 22, 0, 0, 1]);
    });

    test('ReDim without Preserve resets data and allows new lower bounds', () {
      final macro = _compile(
        _module('''
Dim data() As String
ReDim data(2 To 3)
data(2) = "discard"
ReDim data(2 To 3)
Worksheets(1).Range("A1").Value2 = data(2)
data(3) = "discard again"
ReDim data(-1 To 1)
Worksheets(1).Range("A2").Value2 = data(1)
Worksheets(1).Range("A3").Value2 = LBound(data)
'''),
      );
      expect(_values(macro), <Object?>['', '', -1]);
    });

    test('Preserve can allocate a new array and reallocate after Erase', () {
      final macro = _compile(
        _module('''
Dim data() As Long
ReDim Preserve data(3 To 4)
data(3) = 8
Erase data
ReDim Preserve data(-3 To -2)
Worksheets(1).Range("A1").Value2 = LBound(data)
Worksheets(1).Range("A2").Value2 = UBound(data)
Worksheets(1).Range("A3").Value2 = data(-3)
'''),
      );
      expect(_values(macro), <Object?>[-3, -2, 0]);
    });

    test('accepts a matching As clause separately for each resized array', () {
      final macro = _compile(
        _module('''
Dim data() As Long, labels() As String
ReDim DATA(1 To 2) As Long, labels(0) As String
Let Data((1)) = 23
labels(0) = "kept"
ReDim Preserve data(1 To 3) As Long, labels(1) As String
Worksheets(1).Range("A1").Value2 = data(1)
Worksheets(1).Range("A2").Value2 = labels(0)
Worksheets(1).Range("A3").Value2 = labels(1)
'''),
      );
      expect(_values(macro), <Object?>[23, 'kept', '']);
    });

    test('bounds evaluate once in order before the next ReDim target', () {
      final macro = _compile('''
Sub Main()
  Dim data() As Long, other() As Long
  ReDim data(Low() To High()), other(LBound(data) To UBound(data) + 1)
  ReDim Preserve data(LBound(data) To UBound(data) + 1)
  Worksheets(1).Range("A1").Value2 = LBound(other)
  Worksheets(1).Range("A2").Value2 = UBound(other)
  Worksheets(1).Range("A3").Value2 = UBound(data)
End Sub
Function Low() As Long
  Worksheets(1).Range("Z1").Value2 = "lower"
  Low = 2
End Function
Function High() As Long
  Worksheets(1).Range("Z2").Value2 = "upper"
  High = 4
End Function
''');
      expect(_values(macro), <Object?>['lower', 'upper', 2, 5, 5]);
    });

    test('repeated target entries observe the preceding resize', () {
      final macro = _compile(
        _module('''
Dim data() As Long
ReDim data(1 To 2), data(LBound(data) To UBound(data) + 2)
data(4) = 42
ReDim Preserve data(1 To 5), data(1 To UBound(data) + 1)
Worksheets(1).Range("A1").Value2 = data(4)
Worksheets(1).Range("A2").Value2 = UBound(data)
'''),
      );
      expect(_values(macro), <Object?>[42, 6]);
    });

    test('arrays are fresh on each helper call and isolated from caller', () {
      final macro = _compile('''
Sub Main()
  Dim data() As Long
  ReDim data(0)
  data(0) = 99
  Call WriteOne()
  Call WriteOne()
  Worksheets(1).Range("A2").Value2 = data(0)
End Sub
Sub WriteOne()
  Dim data() As Long
  ReDim Preserve data(0)
  data(0) = data(0) + 1
  Worksheets(1).Range("A1").Value2 = data(0)
End Sub
''');
      expect(_values(macro), <Object?>[1, 1, 99]);
    });

    test('dynamic array bounds support signed 32-bit endpoints exactly', () {
      final macro = _compile(
        _module('''
Dim low() As Long, high() As Long
ReDim low(-2147483648 To -2147483647), high(2147483646 To 2147483647)
low(-2147483648) = 11
high(2147483647) = 22
ReDim Preserve low(-2147483648 To -2147483646)
Worksheets(1).Range("A1").Value2 = low(-2147483648)
Worksheets(1).Range("A2").Value2 = high(2147483647)
Worksheets(1).Range("A3").Value2 = LBound(low)
Worksheets(1).Range("A4").Value2 = UBound(high)
'''),
      );
      expect(_values(macro), <Object?>[11, 22, -2147483648, 2147483647]);
    });
  });

  group('module Option Base', () {
    test('sets omitted bounds for both fixed and dynamic arrays', () {
      final macro = _compile('''
Option Base 1
Option Explicit
Sub Main()
  Dim fixed(2) As Long, data() As Long, explicitZero(0 To 1) As Long
  ReDim data(2)
  Worksheets(1).Range("A1").Value2 = LBound(fixed)
  Worksheets(1).Range("A2").Value2 = LBound(data)
  Worksheets(1).Range("A3").Value2 = LBound(explicitZero)
  ReDim Preserve data(3)
  Worksheets(1).Range("A4").Value2 = UBound(data)
  ReDim data(-2 To -1)
  Worksheets(1).Range("A5").Value2 = LBound(data)
End Sub
''');
      expect(_values(macro), <Object?>[1, 1, 0, 3, -2]);
    });

    test('Option Explicit can precede Option Base zero', () {
      final macro = _compile('''
Option Explicit
Option Base 0
Sub Main()
  Dim fixed(0) As Long, data() As Long
  ReDim data(0)
  Worksheets(1).Range("A1").Value2 = LBound(fixed) + LBound(data)
End Sub
''');
      expect(_values(macro), <Object?>[0]);
    });

    test('module base applies inside helper procedures without leaking', () {
      final one = _compile('''
Option Base 1
Sub Main()
  Call Helper()
End Sub
Sub Helper()
  Dim data() As Long
  ReDim data(2)
  Worksheets(1).Range("A1").Value2 = LBound(data)
End Sub
''');
      final zero = _compile(
        _module('''
Dim data() As Long
ReDim data(2)
Worksheets(1).Range("A1").Value2 = LBound(data)
'''),
      );
      expect(_values(one), <Object?>[1]);
      expect(_values(zero), <Object?>[0]);
    });

    test('invalid, repeated, or late Option Base fails structurally', () {
      for (final source in <String>[
        'Option Base 2\nSub Main()\nEnd Sub',
        'Option Base -1\nSub Main()\nEnd Sub',
        'Option Base 1.5\nSub Main()\nEnd Sub',
        'Option Base True\nSub Main()\nEnd Sub',
        'Option Base 1\nOption Base 1\nSub Main()\nEnd Sub',
        'Option Base 0\nOption Base 1\nSub Main()\nEnd Sub',
        'Sub Main()\nEnd Sub\nOption Base 1',
        _module('Option Base 1'),
      ]) {
        expect(
          () => _compile(source),
          throwsA(isA<OfficeVbaCompileException>()),
          reason: source,
        );
      }
    });

    test('omitted Preserve lower bound obeys the module base', () {
      expect(
        () => _compile('''
Option Base 1
Sub Main()
  Dim data() As Long
  ReDim data(0 To 1)
  ReDim Preserve data(2)
End Sub
'''),
        throwsA(_error('vba_subscript_out_of_range')),
      );
    });
  });

  group('Erase lifecycle and enumeration locks', () {
    test('Erase resets each fixed scalar type without changing bounds', () {
      final macro = _compile(
        _module('''
Dim ints(3 To 3) As Long, doubles(3 To 3) As Double
Dim labels(3 To 3) As String, flags(3 To 3) As Boolean
ints(3) = 9
doubles(3) = 1.5
labels(3) = "old"
flags(3) = True
Erase ints, doubles, labels, flags
Worksheets(1).Range("A1").Value2 = ints(3)
Worksheets(1).Range("A2").Value2 = doubles(3)
Worksheets(1).Range("A3").Value2 = labels(3)
Worksheets(1).Range("A4").Value2 = flags(3)
Worksheets(1).Range("A5").Value2 = LBound(ints)
Worksheets(1).Range("A6").Value2 = UBound(labels)
'''),
      );
      expect(_values(macro), <Object?>[0, 0.0, '', false, 3, 3]);
    });

    test('Erase resets fixed Variant elements to Empty', () {
      expect(
        _values(
          _compile(
            _module('''
Dim data(0) As Variant
data(0) = 12
Erase data
Worksheets(1).Range("A1").Value2 = IsEmpty(data(0))
'''),
          ),
        ),
        <Object?>[true],
      );
    });

    for (final action in <String>[
      'Worksheets(1).Range("A1").Value2 = data(0)',
      'data(0) = 1',
      'Worksheets(1).Range("A1").Value2 = LBound(data)',
      'Worksheets(1).Range("A1").Value2 = UBound(data, 1)',
      'For Each item In data\nNext item',
    ]) {
      test('unallocated array rejects $action before and after Erase', () {
        for (final allocation in <String>[
          '',
          'ReDim data(0)\ndata(0) = 12\nErase data',
        ]) {
          _reject('''
Dim data() As Long, item As Variant
$allocation
$action
''', 'vba_subscript_out_of_range');
        }
      });
    }

    for (final operation in <String>[
      'ReDim data(0 To 2)',
      'ReDim Preserve data(0 To 2)',
      'Erase data',
    ]) {
      test('active For Each rejects $operation through nested blocks', () {
        _reject('''
Dim data() As Long, item As Variant
ReDim data(0 To 1)
For Each item In data
  Do
    With Worksheets(1)
      Select Case item
        Case 0
          $operation
      End Select
    End With
    Exit Do
  Loop
Next item
''', 'vba_array_locked');
      });
    }

    test('fixed arrays are also locked against Erase during enumeration', () {
      _reject('''
Dim data(0) As Long, item As Variant
For Each item In data
  Erase data
Next item
''', 'vba_array_locked');
    });

    test('each active enumeration owns its lock on the same array', () {
      _reject('''
Dim data() As Long, outerItem As Variant, innerItem As Variant
ReDim data(0)
For Each outerItem In data
  For Each innerItem In data
    Exit For
  Next innerItem
  Erase data
Next outerItem
''', 'vba_array_locked');
    });

    test('Exit Do unwinds nested For Each locks but retains outer locks', () {
      final macro = _compile(
        _module('''
Dim data() As Long, item As Variant
ReDim data(0)
Do
  For Each item In data
    Exit Do
  Next item
Loop
ReDim Preserve data(1)
Worksheets(1).Range("A1").Value2 = UBound(data)
'''),
      );
      expect(_values(macro), <Object?>[1]);
      _reject('''
Dim data() As Long, item As Variant
ReDim data(0)
For Each item In data
  Do
    Exit Do
  Loop
  ReDim Preserve data(1)
Next item
''', 'vba_array_locked');
    });

    test('completion and Exit For release locks for later resizing', () {
      final macro = _compile(
        _module('''
Dim data() As Long, item As Variant
ReDim data(0)
For Each item In data
Next item
ReDim Preserve data(1)
For Each item In data
  Exit For
Next item
Erase data
ReDim data(3 To 3)
Worksheets(1).Range("A1").Value2 = LBound(data)
'''),
      );
      expect(_values(macro), <Object?>[3]);
    });

    test('element writes remain visible while unrelated arrays may resize', () {
      final macro = _compile(
        _module('''
Dim data() As Long, other() As Long, item As Variant, count As Long
ReDim data(0 To 1), other(0)
data(0) = 1
data(1) = 2
For Each item In data
  count = count + 1
  If count = 1 Then
    data(1) = 20
  End If
  Erase other
  ReDim other(2)
  Worksheets(1).Cells(count, 1).Value2 = item
Next item
'''),
      );
      expect(_values(macro), <Object?>[1, 20]);
    });

    test('same-named helper array does not inherit a caller array lock', () {
      final macro = _compile('''
Sub Main()
  Dim data() As Long, item As Variant
  ReDim data(0)
  data(0) = 7
  For Each item In data
    Call Helper()
    Worksheets(1).Range("A2").Value2 = item
  Next item
End Sub
Sub Helper()
  Dim data() As Long
  ReDim data(0)
  Erase data
  ReDim data(1)
  Worksheets(1).Range("A1").Value2 = UBound(data)
End Sub
''');
      expect(_values(macro), <Object?>[1, 7]);
    });
  });

  group('dynamic array structural and value diagnostics', () {
    test('rejects changing a preserved lower bound with source location', () {
      expect(
        () => _compile(
          _module('''
Dim data() As Long
ReDim data(1 To 2)
ReDim Preserve data(0 To 2)
'''),
        ),
        throwsA(
          _error('vba_subscript_out_of_range')
              .having((error) => error.moduleName, 'module', 'DynamicArrays')
              .having((error) => error.entryPoint, 'entry', 'Main')
              .having((error) => error.line, 'line', 4)
              .having((error) => error.column, 'column', greaterThan(0)),
        ),
      );
    });

    test(
      'ReDim keeps declarations explicit and cannot resize fixed arrays',
      () {
        for (final body in <String>[
          'ReDim missing(2)',
          'Dim scalar As Variant\nReDim scalar(2)',
          'Dim scalar As Long\nReDim scalar(2)',
          'Dim fixed(2) As Long\nReDim fixed(3)',
          'Dim data() As Long\nReDim data(2) As String',
          'Dim data() As Variant\nReDim data(2) As Long',
        ]) {
          expect(
            () => _compile(_module(body)),
            throwsA(isA<OfficeVbaCompileException>()),
            reason: body,
          );
        }
      },
    );

    test(
      'unsupported array shape and operations fail in unused procedures',
      () {
        for (final body in <String>[
          'Dim data() As Range',
          'Dim data() As Worksheet',
          'Dim data() As Long\nReDim data(1 To 2, 1 To 3)',
          'Dim data() As Long\nReDim data()',
          'Dim data() As Long\nReDim data(2) As String',
          'Dim data() As Long\nReDim data(Worksheets(1).Range("A1").Value2)',
          'Dim data() As Long\nReDim data("two")',
          'Dim data() As Long\nErase data(0)',
          'Dim data As Long\nErase data',
          'Dim data() As Long\nSet data(0) = Worksheets(1)',
          'Dim data() As Long\ndata = 12',
          'Dim data() As Long\nWorksheets(1).Range("A1").Value2 = data',
        ]) {
          expect(
            () => _compile('Sub Main()\nEnd Sub\nSub Hidden()\n$body\nEnd Sub'),
            throwsA(isA<OfficeVbaCompileException>()),
            reason: body,
          );
        }
      },
    );

    test(
      'checks ReDim target and bound types after exits and in dead blocks',
      () {
        for (final body in <String>[
          'Dim data() As Long\nExit Sub\nReDim data(True)',
          'Dim fixed(0) As Long\nIf False Then\nReDim fixed(1)\nEnd If',
          'Dim data() As Long\nDo While False\nErase unknown\nLoop',
        ]) {
          expect(
            () => _compile(_module(body)),
            throwsA(isA<OfficeVbaCompileException>()),
            reason: body,
          );
        }
      },
    );

    test(
      'value-dependent allocation faults are not evaluated in dead code',
      () {
        expect(
          _compile(
            _module('''
Dim data() As Long
If False Then
  ReDim data(0 To 4096)
  ReDim Preserve data(1 To 2)
End If
'''),
          ).steps,
          isEmpty,
        );
      },
    );

    test(
      'array lifecycle names cannot be shadowed as locals or procedures',
      () {
        for (final name in <String>['ReDim', 'Erase']) {
          expect(
            () => _compile(_module('Dim $name As Long')),
            throwsA(isA<OfficeVbaCompileException>()),
            reason: name,
          );
        }
      },
    );

    test('dynamic bounds keep integer and signed 32-bit constraints', () {
      for (final bounds in <String>[
        '0.5 To 2',
        '0 To 1.5',
        '-2147483649 To -2147483648',
        '2147483647 To 2147483648',
        '2 To 1',
      ]) {
        _reject('Dim data() As Long\nReDim data($bounds)', 'vba_type_error');
      }
    });

    test('new Variant slots are Empty after grow or reset', () {
      for (final action in <String>[
        'ReDim Preserve data(1)\nWorksheets(1).Range("A1").Value2 = IsEmpty(data(1))',
        'ReDim data(0)\nWorksheets(1).Range("A1").Value2 = IsEmpty(data(0))',
      ]) {
        expect(
          _values(
            _compile(
              _module('''
Dim data() As Variant
ReDim data(0)
data(0) = 12
$action
'''),
            ),
          ),
          <Object?>[true],
        );
      }
    });

    test('ReDim bound helpers participate in recursion checking', () {
      expect(
        () => _compile('''
Sub Main()
End Sub
Function Hidden() As Long
  Dim data() As Long
  ReDim data(Hidden())
End Function
'''),
        throwsA(_error('vba_unsupported')),
      );
    });
  });

  group('dynamic array cumulative resource accounting', () {
    test('every unallocated Erase target consumes shared work', () {
      final targets = List<String>.filled(256, 'data').join(', ');
      expect(
        _compile(_module('Dim data() As Long\nErase $targets')).steps,
        isEmpty,
      );
      _reject('''
Dim data() As Long, index As Long
For index = 1 To 450
  Erase $targets
Next index
''', 'vba_limit_exceeded');
    });

    test('exact per-array bound is accepted and the next slot is refused', () {
      final macro = _compile(
        _module('''
Dim data() As Long
ReDim data(-2048 To 2047)
data(2047) = 23
Worksheets(1).Range("A1").Value2 = data(2047)
'''),
      );
      expect(_values(macro), <Object?>[23]);
      for (final bounds in <String>['0 To 4096', '-2147483648 To 2147483647']) {
        _reject(
          'Dim data() As Long\nReDim data($bounds)',
          'vba_limit_exceeded',
        );
      }
    });

    test(
      'replacement allocation at the active-slot ceiling reuses its quota',
      () {
        expect(
          _compile(
            _module('''
Dim a() As Long, b() As Long, c() As Long, d() As Long
ReDim a(4095), b(4095), c(4095), d(4095)
ReDim a(4095)
ReDim Preserve b(4095)
'''),
          ).steps,
          isEmpty,
        );
        _reject('''
Dim a() As Long, b() As Long, c() As Long, d() As Long, extra() As Long
ReDim a(4095), b(4095), c(4095), d(4095), extra(0)
''', 'vba_limit_exceeded');
      },
    );

    test('shrink and Erase release dynamic slots before later allocations', () {
      final macro = _compile(
        _module('''
Dim a() As Long, b() As Long, c() As Long, d() As Long, extra() As Long
ReDim a(4095), b(4095), c(4095), d(4095)
ReDim Preserve a(2047)
ReDim extra(2047)
Erase d
ReDim Preserve extra(4095)
Worksheets(1).Range("A1").Value2 = UBound(extra)
'''),
      );
      expect(_values(macro), <Object?>[4095]);
    });

    test('Erase does not release fixed-array slot capacity', () {
      _reject('''
Dim fixed(4095) As Long, a() As Long, b() As Long, c() As Long, extra() As Long
ReDim a(4095), b(4095), c(4095)
Erase fixed
ReDim extra(0)
''', 'vba_limit_exceeded');
    });

    test('active-slot quota is shared across calls and released on return', () {
      expect(_compile(_allocationChain(4)).steps, isEmpty);
      expect(
        () => _compile(_allocationChain(5)),
        throwsA(_error('vba_limit_exceeded')),
      );
      expect(
        _compile('''
Sub Main()
  Dim data() As Long
  ReDim data(4095)
  Call Helper()
  Call Helper()
End Sub
Sub Helper()
  Dim a() As Long, b() As Long, c() As Long
  ReDim a(4095), b(4095), c(4095)
End Sub
''').steps,
        isEmpty,
      );
    });

    test('string occupancy survives Preserve and releases discarded slots', () {
      for (final type in <String>['String', 'Variant']) {
        final macro = _compile(
          _stringOccupancy('''
ReDim Preserve data(0 To 33)
ReDim Preserve data(0 To 31)
ReDim other(0)
other(0) = "${List<String>.filled(32, 'z').join()}"
Worksheets(1).Range("A1").Value2 = other(0)
''', type: type),
        );
        expect(_values(macro), <Object?>[List<String>.filled(32, 'z').join()]);
        expect(
          () => _compile(
            _stringOccupancy('''
ReDim Preserve data(0 To 33)
data(33) = "z"
''', type: type),
          ),
          throwsA(_error('vba_limit_exceeded')),
        );
      }
    });

    test('plain ReDim and Erase release all old string occupancy', () {
      for (final release in <String>[
        'ReDim data(0)',
        'Erase data\nReDim data(0)',
      ]) {
        expect(
          _compile(
            _stringOccupancy('''
$release
data(0) = "replacement"
Worksheets(1).Range("A1").Value2 = data(0)
'''),
          ).steps.single.arguments['value'],
          'replacement',
        );
      }
    });

    test('fixed-array Erase also releases occupied strings', () {
      final text = List<String>.filled(32767, 'x').join();
      final macro = _compile(
        _module('''
Dim fixed(0 To 31) As String, other() As String, index As Long
For index = 0 To 31
  fixed(index) = "$text"
Next index
Erase fixed
ReDim other(0 To 31)
For index = 0 To 31
  other(index) = "$text"
Next index
Worksheets(1).Range("A1").Value2 = fixed(0)
'''),
      );
      expect(_values(macro), <Object?>['']);
    });

    test('array lifecycle work remains charged after storage is released', () {
      for (final body in <String>[
        '''
Dim data() As Long, index As Long
For index = 1 To 30
  ReDim data(0 To 4095)
  Erase data
Next index
''',
        '''
Dim data(0 To 4095) As Long, index As Long
For index = 1 To 30
  Erase data
Next index
''',
        '''
Dim data() As Long, index As Long
ReDim data(0 To 4095)
For index = 1 To 30
  ReDim Preserve data(0 To 4095)
Next index
''',
      ]) {
        _reject(body, 'vba_limit_exceeded');
      }
    });
  });
}
