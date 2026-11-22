import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    source: source,
    moduleName: 'MidAssignment',
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

List<Object?> _values(OfficeMacro macro) => <Object?>[
  for (final step in macro.steps) step.arguments['value'],
];

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'MidAssignment')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0));

void main() {
  // Specification-derived replacement rules plus explicit Quds restrictions.
  // These tests are not observations from an installed Microsoft Office host.
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/mid-statement
  // https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/2a8f3567-c8e0-4176-a802-cf2edeba425f
  group('length-preserving local Mid assignments', () {
    for (final name in <String>['Mid', r'Mid$', 'mId', r'mID$']) {
      test('$name preserves surrounding text and never grows the target', () {
        expect(
          _values(
            _compile('''
Dim text As String
text = "The dog jumps"
$name(text, 5, 3) = "fox"
Worksheets(1).Range("A1").Value2 = text
$name(text, 5) = "cow jumped over"
Worksheets(1).Range("A2").Value2 = text
$name(text, 5, 3) = "duck"
Worksheets(1).Range("A3").Value2 = text
'''),
          ),
          <Object?>['The fox jumps', 'The cow jumpe', 'The duc jumpe'],
        );
      });
    }
    for (final (arguments, replacement, expected) in <(String, String, String)>[
      ('1, 2', 'XYZZ', 'XYcdef'),
      ('3, 4', 'X', 'abXdef'),
      ('5, 9', 'XYZ', 'abcdXY'),
      ('6', 'XYZ', 'abcdeX'),
      ('1', 'ABCDEF-extra', 'ABCDEF'),
      ('3, 0', 'XYZ', 'abcdef'),
      ('3, 5', '', 'abcdef'),
      ('3', '', 'abcdef'),
      ('3, 2147483647', 'XYZ', 'abXYZf'),
    ]) {
      test('Mid(text, $arguments) uses only the admitted replacement span', () {
        expect(
          _values(
            _compile('''
Dim text As String
text = "abcdef"
Mid(text, $arguments) = "$replacement"
Worksheets(1).Range("A1").Value2 = text
'''),
          ),
          <Object?>[expected],
        );
      });
    }
    test('replacement may read its original target', () {
      expect(
        _values(
          _compile(r'''
Dim text As String
text = "abcdef"
Mid(text, 2, 4) = Mid$(text, 1, 4)
Worksheets(1).Range("A1").Value2 = text
'''),
        ),
        <Object?>['aabcdf'],
      );
    });
    test('String Variants and implicit Variant locals preserve type', () {
      expect(
        _values(
          _compile('''
Dim text As Variant
Dim replacement As Variant
text = "abc"
replacement = "Z"
Mid(text, 2) = replacement
other = "xyz"
Mid(other, 1) = text
Worksheets(1).Range("A1").Value2 = text
Worksheets(1).Range("A2").Value2 = other
Worksheets(1).Range("A3").Value2 = Len(text)
'''),
        ),
        <Object?>['aZc', 'aZc', 3],
      );
    });
    test('statement separators and continued arguments remain supported', () {
      expect(
        _values(
          _compile('''
Dim text As String
text = "abc": Mid(text, _
  2, 1) = "Z": Worksheets(1).Range("A1").Value2 = text
'''),
        ),
        <Object?>['aZc'],
      );
    });
  });

  group('array slots and procedure ownership', () {
    test(
      'fixed and dynamic String/Variant arrays retain bounds and neighbors',
      () {
        expect(
          _values(
            _compile(r'''
Dim fixed(-1 To 1) As String
Dim dynamic() As Variant
fixed(-1) = "first"
fixed(0) = "middle"
fixed(1) = "last"
ReDim dynamic(4 To 5)
dynamic(4) = "abcd"
dynamic(5) = "safe"
Mid$(fixed(0), 2, 3) = "XYZ"
Mid(dynamic(4), 3) = "QR"
ReDim Preserve dynamic(4 To 6)
Worksheets(1).Range("A1").Value2 = Join(fixed, "|")
Worksheets(1).Range("A2").Value2 = dynamic(4)
Worksheets(1).Range("A3").Value2 = dynamic(5)
Worksheets(1).Range("A4").Value2 = LBound(dynamic)
Worksheets(1).Range("A5").Value2 = UBound(dynamic)
Worksheets(1).Range("A6").Value2 = IsEmpty(dynamic(6))
'''),
          ),
          <Object?>['first|mXYZle|last', 'abQR', 'safe', 4, 6, true],
        );
      },
    );
    test(
      'String helper parameters are local and function results are writable',
      () {
        expect(
          _values(
            _source(r'''
Function Edit(ByVal text As String) As String
  Mid$(text, 2, 1) = "X"
  Edit = text
  Mid(Edit, 3, 1) = "Y"
End Function
Sub Alter(ByVal text As Variant)
  Mid(text, 1, 1) = "Z"
  Worksheets(1).Range("A2").Value2 = text
End Sub
Sub Main()
  Dim text As String
  text = "abcd"
  Worksheets(1).Range("A1").Value2 = Edit(text:=text)
  Alter text
  Worksheets(1).Range("A3").Value2 = text
End Sub
'''),
          ),
          <Object?>['aXYd', 'Zbcd', 'abcd'],
        );
      },
    );
    test(
      'array indexes, start, length and replacement execute once in order',
      () {
        expect(
          _values(
            _source('''
Function Pick(ByVal label As String, ByVal value As Long) As Long
  Worksheets(1).Range("A1").Value2 = label
  Pick = value
End Function
Function Text() As String
  Worksheets(1).Range("A1").Value2 = "replacement"
  Text = "XY"
End Function
Sub Main()
  Dim values(2 To 3) As String
  values(2) = "abcdef"
  values(3) = "safe"
  Mid(values(Pick("index", 2)), Pick("start", 3), Pick("length", 2)) = Text()
  Worksheets(1).Range("A1").Value2 = values(2)
  Worksheets(1).Range("A1").Value2 = values(3)
End Sub
'''),
          ),
          <Object?>[
            'index',
            'start',
            'length',
            'replacement',
            'abXYef',
            'safe',
          ],
        );
      },
    );
    test('element writes inside For Each retain the locked descriptor', () {
      expect(
        _values(
          _compile('''
Dim parts(0 To 1) As String
Dim item As Variant
parts(0) = "ab"
parts(1) = "cd"
For Each item In parts
  Mid(parts(1), 1) = "X"
  Mid(item, 2) = "Y"
  Worksheets(1).Range("A1").Value2 = item
Next item
Worksheets(1).Range("A2").Value2 = Join(parts, "|")
'''),
        ),
        <Object?>['aY', 'XY', 'ab|Xd'],
      );
    });
    test('array Erase and ReDim retain ordinary defaults after Mid', () {
      expect(
        _values(
          _compile('''
Dim parts() As String
ReDim parts(0 To 1)
parts(0) = "abc"
Mid(parts(0), 2) = "XY"
Erase parts
ReDim parts(0 To 0)
Worksheets(1).Range("A1").Value2 = parts(0)
'''),
        ),
        <Object?>[''],
      );
    });
  });

  group('UTF-16 source values and publication', () {
    test('offsets count UTF-16 units and combining marks independently', () {
      expect(
        _values(
          _compile('''
Dim text As String
text = "A😀B"
Mid(text, 2, 2) = "😃"
Worksheets(1).Range("A1").Value2 = text
Worksheets(1).Range("A2").Value2 = Len(text)
text = "AéB"
Mid(text, 3, 1) = "!"
Worksheets(1).Range("A3").Value2 = text
'''),
        ),
        <Object?>['A😃B', 4, 'Ae!B'],
      );
    });
    test(
      'surrogate halves can be replaced locally and repaired before output',
      () {
        expect(
          _values(
            _compile(r'''
Dim text As String
text = "A😀B"
Mid(text, 3, 1) = "x"
Worksheets(1).Range("A1").Value2 = AscW(Mid$(text, 2, 1))
Mid$(text, 3, 1) = ChrW(56835)
Worksheets(1).Range("A2").Value2 = text
'''),
          ),
          <Object?>[-10179, 'A😃B'],
        );
      },
    );
    test('unpaired surrogate output still refuses the complete plan', () {
      expect(
        () => _compile('''
Dim text As String
text = "A😀B"
Worksheets(1).Range("A1").Value2 = "earlier"
Mid(text, 3, 1) = "x"
Worksheets(1).Range("A2").Value2 = text
'''),
        throwsA(_error('vba_type_error')),
      );
    });
  });

  group('strict scalar and index boundaries', () {
    for (final start in <String>[
      '0',
      '-1',
      '4',
      '1.5',
      '2147483648',
      'True',
      '"1"',
      'Empty',
      'Null',
    ]) {
      test('invalid start $start refuses even a zero-length replacement', () {
        expect(
          () => _compile('''
Dim text As String
text = "abc"
Mid(text, $start, 0) = ""
'''),
          throwsA(_error('vba_type_error')),
        );
      });
    }
    for (final length in <String>[
      '-1',
      '1.5',
      '2147483648',
      'True',
      '"1"',
      'Empty',
      'Null',
    ]) {
      test('invalid length $length refuses even an empty replacement', () {
        expect(
          () => _compile('''
Dim text As String
text = "abc"
Mid(text, 1, $length) = ""
'''),
          throwsA(_error('vba_type_error')),
        );
      });
    }
    test('an empty String has no writable Mid position', () {
      expect(
        () => _compile('Dim text As String\nMid(text, 1, 0) = ""'),
        throwsA(_error('vba_type_error')),
      );
    });
    for (final value in <String>['42', 'True', 'Empty', 'Null']) {
      test(
        'Variant target and replacement must actually hold Strings: $value',
        () {
          expect(
            () => _compile('''
Dim text As Variant
text = $value
Mid(text, 1) = "X"
'''),
            throwsA(_error('vba_type_error')),
          );
          expect(
            () => _compile('''
Dim text As String
Dim replacement As Variant
text = "abc"
replacement = $value
Mid(text, 1, 0) = replacement
'''),
            throwsA(_error('vba_type_error')),
          );
        },
      );
    }
    test('non-String Variant array slots refuse at runtime', () {
      expect(
        () => _compile('''
Dim values(0 To 0) As Variant
values(0) = 42
Mid(values(0), 1) = "X"
'''),
        throwsA(_error('vba_type_error')),
      );
    });
    for (final body in <String>[
      'Dim values() As String\nMid(values(0), 1) = "X"',
      'Dim values(2 To 3) As String\nMid(values(1), 1) = "X"',
      'Dim values() As String\nReDim values(0 To 0)\nErase values\nMid(values(0), 1) = "X"',
    ]) {
      test(
        'array allocation and subscript checks precede source edits: $body',
        () {
          expect(
            () => _compile(body),
            throwsA(_error('vba_subscript_out_of_range')),
          );
        },
      );
    }
  });

  group('static structure and lvalue refusals', () {
    for (final (body, code) in <(String, String)>[
      ('Dim number As Long\nMid(number, 1) = "X"', 'vba_type_error'),
      (
        'Dim values(0 To 0) As Double\nMid(values(0), 1) = "X"',
        'vba_type_error',
      ),
      ('Const text As String = "abc"\nMid(text, 1) = "X"', 'vba_unsupported'),
      ('Dim values(0 To 0) As String\nMid(values, 1) = "X"', 'vba_unsupported'),
      ('Mid("abc", 1) = "X"', 'vba_unsupported'),
      ('Dim text As String\nMid(text & "x", 1) = "X"', 'vba_unsupported'),
      ('Mid(Worksheets(1).Range("A1").Value2, 1) = "X"', 'vba_unsupported'),
      (r'Mid(Mid$("abc", 1), 1) = "X"', 'vba_unsupported'),
      ('Dim text As String\nMid(text) = "X"', 'vba_type_error'),
      ('Dim text As String\nMid(text, 1, 2, 3) = "X"', 'vba_type_error'),
      ('Dim text As String\nMid(text, , 2) = "X"', 'vba_unsupported'),
      ('Dim text As String\nMid(text, 1,) = "X"', 'vba_unsupported'),
      ('Dim text As String\nMid(text, start:=1) = "X"', 'vba_unsupported'),
      ('Dim text As String\nSet Mid(text, 1) = "X"', 'vba_unsupported'),
      ('Dim text As String\nLet Mid(text, 1) = "X"', 'vba_unsupported'),
      ('Dim text As String\nCall Mid(text, 1)', 'vba_unsupported'),
      ('Dim text As String\nMidB(text, 1) = "X"', 'vba_unsupported'),
      (
        r'Dim text As String'
            '\n'
            r'MidB$(text, 1) = "X"',
        'vba_unsupported',
      ),
    ]) {
      test('refuses invalid Mid source: $body', () {
        expect(() => _compile(body), throwsA(_error(code)));
      });
    }
    test('temporary helper return values are not writable', () {
      expect(
        () => _source('''
Function Label() As String
  Label = "abc"
End Function
Sub Main()
  Mid(Label(), 1) = "X"
End Sub
'''),
        throwsA(_error('vba_unsupported')),
      );
    });
    test(
      'undeclared Option Explicit target produces a positioned name error',
      () {
        expect(
          () => _source(
            'Option Explicit\nSub Main()\nMid(text, 1) = "X"\nEnd Sub',
          ),
          throwsA(
            _error('vba_name_error')
                .having((error) => error.line, 'line', 3)
                .having((error) => error.column, 'column', 5),
          ),
        );
      },
    );
    test('invalid lvalues are rejected in unused procedures', () {
      expect(
        () => _source('''
Sub Unused()
  Dim number As Long
  Mid(number, 1) = "X"
End Sub
Sub Main()
  Worksheets(1).Range("A1").Value2 = "unchanged"
End Sub
'''),
        throwsA(_error('vba_type_error')),
      );
    });
    test(
      'runtime-only invalid offsets are not executed in inactive branches',
      () {
        expect(
          _values(
            _compile('''
Dim text As String
text = "abc"
If False Then
  Mid(text, 0, -1) = "X"
End If
Worksheets(1).Range("A1").Value2 = text
'''),
          ),
          <Object?>['abc'],
        );
      },
    );
    test('Mid keyword cannot shadow a variable or procedure', () {
      expect(
        () => _compile('Dim Mid As String'),
        throwsA(_error('vba_name_error')),
      );
      expect(
        () => _source('Sub Mid()\nEnd Sub\nSub Main()\nEnd Sub'),
        throwsA(_error('vba_name_error')),
      );
    });
  });

  group('shared compiler budgets', () {
    test('large replacement copies are charged before allocation', () {
      expect(
        () => _compile('''
Dim text As String
Dim index As Long
text = String(32767, "a")
For index = 1 To 3
  Mid(text, 1, 1) = "b"
Next index
Worksheets(1).Range("A1").Value2 = text
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
    test(
      'identical nonempty replacements retain copied-string work accounting',
      () {
        expect(
          () => _compile('''
Dim text As String
Dim index As Long
text = String(32767, "a")
For index = 1 To 3
  Mid(text, 1, 1) = "a"
Next index
'''),
          throwsA(_error('vba_limit_exceeded')),
        );
      },
    );
    test('zero-length edits validate but do not copy the retained text', () {
      expect(
        _values(
          _compile('''
Dim text As String
Dim index As Long
text = String(32767, "a")
For index = 1 To 20
  Mid(text, 1, 0) = "b"
  Mid(text, 32767) = ""
Next index
Worksheets(1).Range("A1").Value2 = Len(text)
'''),
        ),
        <Object?>[32767],
      );
    });
    test(
      'zero-length edit loops still consume expression and instruction work',
      () {
        expect(
          () => _compile('''
Dim text As String
Dim index As Long
text = "a"
For index = 1 To 20000
  Mid(text, 1, 0) = ""
Next index
'''),
          throwsA(_error('vba_limit_exceeded')),
        );
      },
    );
    test('array element copies share the same aggregate work bound', () {
      expect(
        () => _compile('''
Dim parts(0 To 0) As String
Dim index As Long
parts(0) = String(32767, "a")
For index = 1 To 3
  Mid(parts(0), 1, 1) = "b"
Next index
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
    test('same-length slot writes retain exact occupied String accounting', () {
      final text = 'a' * 32767;
      final source =
          '''
Const sample As String = "$text"
Sub Main()
  Dim parts() As String, extra(0 To 0) As String, index As Long
  ReDim parts(0 To 31)
  For index = 0 To 31
    parts(index) = sample
  Next index
  Mid(parts(0), 1, 1) = "b"
  extra(0) = String(32, "x")
  Worksheets(1).Range("A1").Value2 = Left\$(parts(0), 2)
  Worksheets(1).Range("A2").Value2 = Len(extra(0))
End Sub
''';
      expect(_values(_source(source)), <Object?>['ba', 32]);
      expect(
        () =>
            _source(source.replaceFirst('String(32, "x")', 'String(33, "x")')),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
    test('Preserve shrink and Erase release occupied strings after Mid', () {
      final text = 'a' * 32767;
      expect(
        _values(
          _source('''
Const sample As String = "$text"
Sub Main()
  Dim parts() As Variant, other() As String, index As Long
  ReDim parts(0 To 31)
  For index = 0 To 31
    parts(index) = sample
  Next index
  Mid(parts(31), 1, 1) = "b"
  ReDim Preserve parts(0 To 30)
  ReDim other(0 To 0)
  other(0) = sample
  Worksheets(1).Range("A1").Value2 = Len(other(0))
  Erase parts
  ReDim other(0 To 31)
  For index = 0 To 31
    other(index) = sample
  Next index
  Worksheets(1).Range("A2").Value2 = Len(other(31))
End Sub
'''),
        ),
        <Object?>[32767, 32767],
      );
    });
    test(
      'helper return releases Mid-edited array strings before the next call',
      () {
        final text = 'a' * 32767;
        expect(
          _values(
            _source('''
Const sample As String = "$text"
Sub Fill()
  Dim parts(0 To 31) As String, index As Long
  For index = 0 To 31
    parts(index) = sample
  Next index
  Mid(parts(0), 1, 1) = "b"
  Worksheets(1).Range("A1").Value2 = Left\$(parts(0), 2)
End Sub
Sub Main()
  Call Fill()
  Call Fill()
End Sub
'''),
          ),
          <Object?>['ba', 'ba'],
        );
      },
    );
  });
}
