import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source, {String language = 'vba-word'}) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: language,
        format: switch (language) {
          'vba-word' => OfficeMacroFormat.docx,
          'vba-excel' => OfficeMacroFormat.xlsx,
          _ => OfficeMacroFormat.pptx,
        },
        moduleName: 'JoinTests',
        source: source,
      ),
    );

OfficeMacro _body(String body, {String language = 'vba-word'}) =>
    _source('Sub Main()\n$body\nEnd Sub', language: language);

String _write(
  String value, [
  String language = 'vba-word',
]) => switch (language) {
  'vba-word' => 'ActiveDocument.Tables(1).Cell(1, 1).Range.Text = $value',
  'vba-excel' => 'Worksheets(1).Range("A1").Value2 = $value',
  _ =>
    'ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text = $value',
};

List<Object?> _texts(OfficeMacro macro) => [
  for (final step in macro.steps)
    step.arguments[macro.format == OfficeMacroFormat.xlsx ? 'value' : 'text'],
];

Matcher _error(String code) => isA<OfficeVbaCompileException>()
    .having((error) => error.code, 'code', code)
    .having((error) => error.moduleName, 'module', 'JoinTests')
    .having((error) => error.line, 'line', greaterThan(0))
    .having((error) => error.column, 'column', greaterThan(0));

void main() {
  group('source String array joining', () {
    for (final host in ['vba-word', 'vba-excel', 'vba-powerpoint']) {
      for (final (call, expected) in <(String, String)>[
        ('Join(parts)', 'first  last'),
        ('jOiN(parts, "|")', 'first||last'),
        ('Join(parts, "")', 'firstlast'),
        ('Join(parts, " :: ")', 'first ::  :: last'),
        ('Join(parts, CVar("|"))', 'first||last'),
        ('Join(parts, Empty)', 'firstlast'),
        ('Join(parts, CVar(Empty))', 'firstlast'),
      ]) {
        test('$host $call preserves empty slots and order', () {
          final plan = _body('''
Dim parts(-3 To -1) As String
parts(-3) = "first"
parts(-1) = "last"
${_write(call, host)}
''', language: host);
          expect(_texts(plan), [expected]);
          expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
        });
      }
    }

    test('both Option Base values retain the complete declared bounds', () {
      for (final base in [0, 1]) {
        final plan = _source('''
Option Base $base
Sub Main()
  Dim parts(2) As String
  parts($base) = "first"
  parts(2) = "last"
  ${_write('Join(parts, "/")')}
End Sub
''');
        expect(_texts(plan), [base == 0 ? 'first//last' : 'first/last']);
      }
    });

    test('single-element arrays add no leading or trailing separator', () {
      final plan = _body('''
Dim parts(7 To 7) As String
${_write('Join(parts, "--")')}
parts(7) = "item"
${_write('Join(parts, "--")')}
''');
      expect(_texts(plan), ['', 'item']);
    });

    test(
      'Unicode and embedded units are concatenated without normalization',
      () {
        final plan = _body('''
Dim parts(1 To 4) As String
parts(1) = "العربية"
parts(2) = "é"
parts(3) = ChrW(-10179)
parts(4) = ChrW(-8704)
${_write('Join(parts, "")')}
''');
        expect(_texts(plan), ['العربيةé😀']);
      },
    );

    test('Join follows Preserve, shrink, regrow and fixed-array Erase', () {
      final plan = _body('''
Dim parts() As String, fixed(1 To 2) As String
ReDim parts(3 To 5)
parts(3) = "a"
parts(4) = "b"
parts(5) = "c"
${_write('Join(parts, "|")')}
ReDim Preserve parts(3 To 4)
${_write('Join(parts, "|")')}
ReDim Preserve parts(3 To 6)
${_write('Join(parts, "|")')}
fixed(1) = "old"
Erase fixed
${_write('Join(fixed, "|")')}
''');
      expect(_texts(plan), ['a|b|c', 'a|b', 'a|b||', '|']);
    });

    test('joining during For Each reads without mutating or locking anew', () {
      final plan = _body('''
Dim parts(0 To 1) As String, item As Variant
parts(0) = "a"
parts(1) = "b"
For Each item In parts
  ${_write('Join(parts, "-") & ":" & CStr(item)')}
Next item
${_write('parts(0) & parts(1)')}
''');
      expect(_texts(plan), ['a-b:a', 'a-b:b', 'ab']);
    });

    test('delimiter helper evaluates once before the joined write', () {
      final plan = _source('''
Sub Main()
  Dim parts(1 To 2) As String
  parts(1) = "a"
  parts(2) = "b"
  ${_write('Join(parts, Separator())')}
  ${_write('Join(parts, "")')}
End Sub
Function Separator() As String
  Dim parts(9 To 9) As String
  parts(9) = "helper"
  ${_write('Join(parts)')}
  Separator = ":"
End Function
''');
      expect(_texts(plan), ['helper', 'a:b', 'ab']);
    });

    test('typed scalar helper result can return Join of its local array', () {
      final plan = _source('''
Sub Main()
  ${_write('Label("first", "last")')}
End Sub
Function Label(ByVal first As String, ByVal last As String) As String
  Dim parts(1 To 2) As String
  parts(1) = first
  parts(2) = last
  Label = Join(parts)
End Function
''');
      expect(_texts(plan), ['first last']);
    });
  });

  group('Join type and source boundaries', () {
    for (final declaration in [
      'Dim parts(1) As Long',
      'Dim parts(1) As Double',
      'Dim parts(1) As Boolean',
      'Dim parts(1) As Variant',
      'Dim parts(1)',
      'Dim parts As String',
      'Dim parts As Variant',
      'Dim parts As Document',
    ]) {
      test('$declaration is refused without implicit element coercion', () {
        expect(
          () => _body('$declaration\n${_write('Join(parts)')}'),
          throwsA(_error('vba_type_error')),
        );
      });
    }

    for (final call in [
      'Join()',
      'Join(parts, ",", 1)',
      'Join(parts(1))',
      'Join("text")',
      'Join(sourcearray:=parts)',
    ]) {
      test('refuses invalid source/arity $call', () {
        expect(
          () => _body('Dim parts(1) As String\n${_write(call)}'),
          throwsA(_error('vba_type_error')),
        );
      });
    }

    test('an application root cannot act as a local array name', () {
      expect(
        () => _body(_write('Join(ActiveDocument)')),
        throwsA(_error('vba_name_error')),
      );
    });

    for (final call in ['Join(parts, delimiter:=",")', 'Join(parts,)']) {
      test('refuses unsupported argument shape $call', () {
        expect(
          () => _body('Dim parts(1) As String\n${_write(call)}'),
          throwsA(_error('vba_unsupported')),
        );
      });
    }

    for (final delimiter in ['1', 'True', 'CVar(1)', 'CVar(False)']) {
      test('rejects delimiter conversion $delimiter even for one element', () {
        expect(
          () => _body(
            'Dim parts(1 To 1) As String\n${_write('Join(parts, $delimiter)')}',
          ),
          throwsA(_error('vba_type_error')),
        );
      });
    }
    for (final delimiter in ['Null', 'CVar(Null)']) {
      test('Null delimiter $delimiter produces a positioned diagnostic', () {
        expect(
          () => _body(
            'Dim parts(1 To 1) As String\n${_write('Join(parts, $delimiter)')}',
          ),
          throwsA(_error('vba_invalid_use_of_null')),
        );
      });
    }

    for (final setup in [
      'Dim parts() As String',
      'Dim parts() As String\nReDim parts(1 To 2)\nErase parts',
    ]) {
      test('unallocated dynamic array is not silently treated as empty', () {
        expect(
          () => _body('$setup\n${_write('Join(parts)')}'),
          throwsA(_error('vba_subscript_out_of_range')),
        );
      });
    }

    test('unused code receives static array and delimiter validation', () {
      for (final body in [
        'Dim parts(1) As Long\n${_write('Join(parts)')}',
        'Dim parts(1) As String\n${_write('Join(parts, True)')}',
        'Dim parts(1) As String\n${_write('Join(parts(1))')}',
      ]) {
        expect(
          () => _source('Sub Main()\nEnd Sub\nSub Unused()\n$body\nEnd Sub'),
          throwsA(_error('vba_type_error')),
        );
      }
    });

    test('Join cannot be shadowed by local, helper or parameter', () {
      for (final source in [
        'Sub Main()\nDim Join As String\nEnd Sub',
        'Sub Main()\nEnd Sub\nSub Helper(ByVal Join As String)\nEnd Sub',
        'Sub Main()\nEnd Sub\nSub Join()\nEnd Sub',
      ]) {
        expect(() => _source(source), throwsA(_error('vba_name_error')));
      }
    });

    test('bare arrays remain unavailable to ordinary expressions', () {
      for (final use in [
        'Dim value As Variant\nvalue = parts',
        'Dim value As String\nvalue = CStr(parts)',
        'parts = "replacement"',
      ]) {
        expect(
          () => _body('Dim parts(1) As String\n$use'),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      }
    });
  });

  group('Join resource limits', () {
    test('accepts exact UTF-16 output limit and refuses one excess unit', () {
      for (final length in [32766, 32767]) {
        final source =
            '''
Dim parts(1 To 2) As String
parts(1) = "${'x' * length}"
${_write('Join(parts, "|")')}
''';
        if (length == 32766) {
          expect(_texts(_body(source)).single, '${'x' * length}|');
        } else {
          expect(() => _body(source), throwsA(_error('vba_limit_exceeded')));
        }
      }
    });

    test('meters repeated copies even when the result is discarded', () {
      expect(
        () => _body('''
Dim parts(1 To 2) As String, result As String, index As Long
parts(1) = "${'x' * 15000}"
parts(2) = parts(1)
For index = 1 To 4
  result = Join(parts, "")
Next index
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('meters array visits even for empty joined output', () {
      expect(
        () => _body('''
Dim parts(0 To 4095) As String, result As String, index As Long
For index = 1 To 30
  result = Join(parts, "")
Next index
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('separator expansion is bounded before materializing output', () {
      expect(
        () => _body('''
Dim parts(0 To 4095) As String
${_write('Join(parts, "0123456789")')}
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  });
}
