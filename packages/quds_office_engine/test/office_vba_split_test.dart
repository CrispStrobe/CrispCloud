import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_split_conformance.dart';
import 'support/vba_conformance.dart';

OfficeMacro _compile(String source, String dialect) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: dialect,
        format: switch (dialect) {
          'vba-word' => OfficeMacroFormat.docx,
          'vba-powerpoint' => OfficeMacroFormat.pptx,
          _ => OfficeMacroFormat.xlsx,
        },
        moduleName: 'SplitTests',
        source: source.replaceAll(splitWordSink, splitSinks[dialect]!),
      ),
    );

String _module(String body) => 'Sub Main()\n$body\nEnd Sub\n';

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>().having(
      (error) => error.code,
      'code',
      code,
    );

void _reject(String source, String dialect, String code) => expect(
  () => _compile(source, dialect),
  throwsA(_error(code)),
  reason: source,
);

List<Object?> _outputs(OfficeMacro macro) => [
  for (final step in macro.steps)
    step.arguments[step.tool == 'xlsx.cellValue' ? 'value' : 'text'],
];

String _liveSlots({required bool overflow}) {
  final separators = List<String>.filled(4095, '|').join();
  return _module('''
Dim a() As String, b() As String, c() As String, d() As String, extra() As String
a = Split("$separators", "|")
b = Split("$separators", "|")
c = Split("$separators", "|")
d = Split("$separators", "|")
${overflow ? 'extra = Split("one", "|")' : 'd = Split("$separators", "|")'}
''');
}

String _stringOccupancy(String after) {
  final text = List<String>.filled(32767, 'x').join();
  return _module('''
Dim keep(31) As String, parts() As String, other() As String, i As Long
For i = 0 To 31
    keep(i) = "$text"
Next i
parts = Split("12345678901234567890123456789012", "|")
$after
''');
}

String _frameSlots(int frames) {
  final separators = List<String>.filled(4095, '|').join();
  final source = StringBuffer();
  for (var index = 0; index < frames; index++) {
    source.writeln('Sub ${index == 0 ? 'Main' : 'Helper$index'}()');
    source.writeln('Dim parts() As String');
    source.writeln('parts = Split("$separators", "|")');
    if (index + 1 < frames) {
      source.writeln('Call Helper${index + 1}()');
    }
    source.writeln('End Sub');
  }
  return source.toString();
}

void main() {
  final source = File(
    'test/fixtures/vba_conformance/split_v1.json',
  ).readAsStringSync();
  final suites = splitSuites(source);
  for (final suite in suites) {
    group('${suite.dialect} independent Split corpus', () {
      for (final fixture in suite.cases) {
        test(fixture.id, () {
          expect(runVbaConformanceCase(fixture)['actual'], fixture.expected);
        });
      }
    });
  }

  test('corpus keeps specification and dialect evidence separate', () {
    expect(
      suites.map((suite) => suite.dialect).toSet(),
      splitSinks.keys.toSet(),
    );
    for (final suite in suites) {
      expect(suite.id, 'vba-split');
      expect(suite.cases, hasLength(58));
      expect(suite.cases.map((fixture) => fixture.provenance['kind']).toSet(), {
        'spec-derived',
        'dialect-contract',
      });
      expect(
        suite.cases.where((fixture) => fixture.provenance.containsKey('host')),
        isEmpty,
      );
    }
  });

  for (final dialect in splitSinks.keys) {
    group('$dialect Split supported target and static shape', () {
      for (final declaration in [
        'Dim parts As String',
        'Dim parts As Variant',
        'Dim parts(1) As String',
        'Dim parts() As Variant',
        'Dim parts()',
        'Dim parts() As Long',
        'Dim parts() As Double',
        'Dim parts() As Boolean',
      ]) {
        test('refuses $declaration', () {
          _reject(
            _module('$declaration\nparts = Split("a|b", "|")'),
            dialect,
            'vba_unsupported',
          );
        });
      }

      for (final (statement, code) in [
        ('Set parts = Split("a|b", "|")', 'vba_unsupported'),
        ('parts(0) = Split("a|b", "|")', 'vba_unsupported'),
        ('$splitWordSink = Split("a|b", "|")', 'vba_unsupported'),
        ('parts = Join(Split("a|b", "|"), "/")', 'vba_type_error'),
        ('parts = Split("a|b", "|") & "suffix"', 'vba_unsupported'),
        ('parts = Split("a|b", "|")(0)', 'vba_syntax_error'),
        ('parts = Split(Expression:="a|b", Delimiter:="|")', 'vba_unsupported'),
        ('parts = Split("a|b", , 2)', 'vba_unsupported'),
        ('parts = Split("a|b", "|", , 0)', 'vba_unsupported'),
      ]) {
        test('refuses unsupported source $statement', () {
          _reject(_module('Dim parts() As String\n$statement'), dialect, code);
        });
      }

      test('whole-array copying remains outside the dialect', () {
        _reject(
          _module('''
Dim parts() As String, other() As String
parts = Split("a|b", "|")
other = parts
'''),
          dialect,
          'vba_type_error',
        );
      });

      for (final arguments in ['', '"a", "|", -1, 0, 0']) {
        test('checks arity in unused procedures: ($arguments)', () {
          _reject(
            '''
Sub Main()
End Sub
Sub Unused()
    Dim parts() As String
    parts = Split($arguments)
End Sub
''',
            dialect,
            'vba_type_error',
          );
        });
      }

      test('checks target and argument shapes in inactive branches', () {
        _reject(
          _module('''
Dim parts() As Variant
If False Then
    parts = Split("a|b", "|")
End If
'''),
          dialect,
          'vba_unsupported',
        );
        _reject(
          _module('''
Dim parts() As String
Exit Sub
parts = Split(True, "|")
'''),
          dialect,
          'vba_type_error',
        );
      });
    });

    group('$dialect Split strict values and empty-result validation', () {
      for (final value in ['1', 'True']) {
        for (final arguments in ['$value, "|"', '"a|b", $value']) {
          test('requires explicit String conversion for ($arguments)', () {
            _reject(
              _module('Dim parts() As String\nparts = Split($arguments)'),
              dialect,
              'vba_type_error',
            );
          });
        }
      }

      for (final arguments in [
        'Null, "|"',
        '"", Null',
        '"a|b", "|", Null',
        '"", "|", 0, Null',
      ]) {
        test('rejects Null for ($arguments)', () {
          _reject(
            _module('Dim parts() As String\nparts = Split($arguments)'),
            dialect,
            'vba_invalid_use_of_null',
          );
        });
      }

      for (final limit in [
        '-2',
        '-2147483648',
        '2147483648',
        '0.5',
        '"2"',
        'True',
        'Empty',
      ]) {
        test('validates limit $limit even for empty input', () {
          _reject(
            _module('Dim parts() As String\nparts = Split("", "|", $limit)'),
            dialect,
            'vba_type_error',
          );
        });
      }

      for (final mode in [
        'vbTextCompare',
        'vbDatabaseCompare',
        'vbUseCompareOption',
        '3',
      ]) {
        test('refuses comparison mode $mode for a zero result', () {
          _reject(
            _module('Dim parts() As String\nparts = Split("", "|", 0, $mode)'),
            dialect,
            'vba_unsupported',
          );
        });
      }

      for (final mode in ['0.5', '"0"', 'True', 'Empty']) {
        test('comparison mode $mode must be an exact number', () {
          _reject(
            _module('Dim parts() As String\nparts = Split("", "|", 0, $mode)'),
            dialect,
            'vba_type_error',
          );
        });
      }

      test('evaluates later arguments before semantic value validation', () {
        _reject(
          '''
Sub Main()
    Dim parts() As String
    parts = Split(Null, "|", FailingLimit())
End Sub
Function FailingLimit() As Long
    FailingLimit = 1 / 0
End Function
''',
          dialect,
          'vba_arithmetic_error',
        );
      });

      test('locked array refuses before argument evaluation', () {
        _reject(
          '''
Sub Main()
    Dim parts() As String, item As Variant
    parts = Split("a|b", "|")
    For Each item In parts
        parts = Split(FailingText(), "|")
    Next item
End Sub
Function FailingText() As String
    FailingText = CStr(1 / 0)
End Function
''',
          dialect,
          'vba_array_locked',
        );
      });

      test('Exit For releases the descriptor for replacement', () {
        final macro = _compile(
          _module('''
Dim parts() As String, item As Variant
parts = Split("a|b", "|")
For Each item In parts
    Exit For
Next item
parts = Split("new|values", "|")
$splitWordSink = Join(parts, "/")
'''),
          dialect,
        );
        expect(_outputs(macro), ['new/values']);
      });

      for (final access in ['parts(0)', 'parts(-1)', 'parts(1)']) {
        test('allocated empty result refuses element $access', () {
          _reject(
            _module('''
Dim parts() As String
parts = Split("")
$splitWordSink = $access
'''),
            dialect,
            'vba_subscript_out_of_range',
          );
        });
      }

      test('Erase restores the unallocated descriptor state', () {
        _reject(
          _module('''
Dim parts() As String
parts = Split("")
Erase parts
$splitWordSink = CStr(LBound(parts))
'''),
          dialect,
          'vba_subscript_out_of_range',
        );
      });
    });

    group('$dialect Split resource ownership', () {
      test('exact per-array slot limit succeeds including empty slots', () {
        final separators = List<String>.filled(4095, '|').join();
        final macro = _compile(
          _module('''
Dim parts() As String
parts = Split("$separators", "|")
$splitWordSink = CStr(UBound(parts))
'''),
          dialect,
        );
        expect(_outputs(macro), ['4095']);
      });

      test('the first excess slot fails before storage construction', () {
        final separators = List<String>.filled(4096, '|').join();
        _reject(
          _module('Dim parts() As String\nparts = Split("$separators", "|")'),
          dialect,
          'vba_limit_exceeded',
        );
      });

      test(
        'an explicit limit keeps the long unsplit tail within slot limits',
        () {
          final separators = List<String>.filled(5000, '|').join();
          final macro = _compile(
            _module('''
Dim parts() As String
parts = Split("$separators", "|", 2)
$splitWordSink = CStr(UBound(parts)) & ":" & CStr(Len(parts(1)))
'''),
            dialect,
          );
          expect(_outputs(macro), ['1:4999']);
        },
      );

      test('replacement credits old slots at the active-array limit', () {
        expect(_compile(_liveSlots(overflow: false), dialect).steps, isEmpty);
      });

      test('a fifth independent allocation exceeds the active-array limit', () {
        _reject(_liveSlots(overflow: true), dialect, 'vba_limit_exceeded');
      });

      test('active caller arrays remain charged inside helpers', () {
        expect(_compile(_frameSlots(4), dialect).steps, isEmpty);
        _reject(_frameSlots(5), dialect, 'vba_limit_exceeded');
      });

      test('helper return releases local descriptors', () {
        final separators = List<String>.filled(4095, '|').join();
        final macro = _compile('''
Sub Main()
    Dim parts() As String
    Call Allocate()
    Call Allocate()
    Call Allocate()
    Call Allocate()
    Call Allocate()
    parts = Split("retained", "|")
    $splitWordSink = Join(parts, "/")
End Sub
Sub Allocate()
    Dim parts() As String
    parts = Split("$separators", "|")
End Sub
''', dialect);
        expect(_outputs(macro), ['retained']);
      });

      test('equal-size replacement credits retired String occupancy', () {
        expect(
          _compile(
            _stringOccupancy(
              'parts = Split("abcdefghijklmnopqrstuvwxyzABCDEF", "|")',
            ),
            dialect,
          ).steps,
          isEmpty,
        );
      });

      test('the next occupied String unit exceeds the live budget', () {
        _reject(
          _stringOccupancy(
            'parts = Split("abcdefghijklmnopqrstuvwxyzABCDEFG", "|")',
          ),
          dialect,
          'vba_limit_exceeded',
        );
      });

      test('empty reassignment retires old String occupancy', () {
        expect(
          _compile(
            _stringOccupancy('''
parts = Split("")
other = Split("abcdefghijklmnopqrstuvwxyzABCDEF", "|")
'''),
            dialect,
          ).steps,
          isEmpty,
        );
      });

      test('unsplit copies consume the cumulative work budget', () {
        final text = List<String>.filled(32767, 'x').join();
        _reject(
          _module('''
Dim parts() As String, i As Long
For i = 1 To 4
    parts = Split("$text", "", 1)
Next i
'''),
          dialect,
          'vba_limit_exceeded',
        );
      });

      test('repeated empty replacement still consumes work', () {
        _reject(
          _module('''
Dim parts() As String, i As Long
For i = 1 To 50000
    parts = Split("", "|", 0)
Next i
'''),
          dialect,
          'vba_limit_exceeded',
        );
      });
    });
  }
}
