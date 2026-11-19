import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    source: source,
    format: OfficeMacroFormat.xlsx,
    moduleName: 'ControlFlowBoundaries',
  ),
);

Matcher _error(String code) => isA<OfficeVbaCompileException>().having(
  (error) => error.code,
  'code',
  code,
);

String _module(String body) => 'Sub Main()\n$body\nEnd Sub';

String _nested(String opening, String closing, int depth) => _module(
  '${List<String>.filled(depth, '$opening\n').join()}'
  '${List<String>.filled(depth, '$closing\n').join()}',
);

void main() {
  group('conditional control flow resource bounds', () {
    for (final body in <String>[
      'Do\nLoop',
      'Do While True\nLoop',
      'Do Until False\nLoop',
      'Do\nLoop While True',
      'Do\nLoop Until False',
      'While True\nWend',
    ]) {
      test('empty ${body.replaceAll('\n', ' / ')} exhausts shared work', () {
        expect(
          () => _compile(_module(body)),
          throwsA(_error('vba_limit_exceeded')),
        );
      });
    }

    test('work accumulates across sequential loops and procedure calls', () {
      expect(
        () => _compile('''
Sub Main()
  Dim repeat As Long
  For repeat = 1 To 100
    Call Spend()
  Next repeat
End Sub
Sub Spend()
  Dim count As Long
  Do Until count = 1000
    count = count + 1
  Loop
End Sub
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('nonmatching comma alternatives consume work in empty cases', () {
      final alternatives = List<int>.generate(30, (index) => index).join(', ');
      expect(
        () => _compile(
          _module('''
For row = 1 To 2000
  Select Case 999
    Case $alternatives
  End Select
Next row
'''),
        ),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('case clauses count toward the statement budget', () {
      final source = _module(
        'Select Case 0\n${List<String>.filled(10000, 'Case 1\n').join()}End Select',
      );
      expect(
        () => _compile(source),
        throwsA(
          isA<OfficeVbaCompileException>()
              .having((error) => error.code, 'code', 'vba_limit_exceeded')
              .having(
                (error) => error.message,
                'message',
                contains('statements'),
              ),
        ),
      );
    });

    for (final (opening, closing) in <(String, String)>[
      ('Do While False', 'Loop'),
      ('While False', 'Wend'),
      ('Select Case 0\nCase 0', 'End Select'),
    ]) {
      test('$opening honors the shared block nesting boundary', () {
        expect(_compile(_nested(opening, closing, 32)).steps, isEmpty);
        expect(
          () => _compile(_nested(opening, closing, 33)),
          throwsA(_error('vba_limit_exceeded')),
        );
      });
    }

    test('Case expressions retain the expression-depth bound', () {
      final expression = '${List<String>.filled(65, '+ ').join()}1';
      expect(
        () => _compile(_module('Select Case 1\nCase $expression\nEnd Select')),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('operation and encoded-byte budgets are shared across cases', () {
      expect(
        () => _compile(
          _module('''
Select Case 1
  Case 1
    Worksheets(1).Range("A1:A10000").Value2 = 1
End Select
Do
  Worksheets(1).Range("B1").Value2 = 2
  Exit Do
Loop
'''),
        ),
        throwsA(_error('vba_limit_exceeded')),
      );
      final text = List<String>.filled(20000, 'x').join();
      expect(
        () => _compile(
          _module('''
Select Case 1
  Case 1
    Worksheets(1).Range("A1:A60").Value2 = "$text"
End Select
'''),
        ),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  });

  group('whole-module checks include inactive new constructs', () {
    test('unknown names in skipped loops and later cases are rejected', () {
      for (final body in <String>[
        'Do While False\nWorksheets(1).Range("A1").Value2 = missing\nLoop',
        'While False\nWorksheets(1).Range("A1").Value2 = missing\nWend',
        'Select Case 1\nCase 1\nCase missing\nEnd Select',
        'Select Case 1\nCase 1\nCase 2 To missing\nEnd Select',
      ]) {
        expect(
          () => _compile(_module(body)),
          throwsA(_error('vba_name_error')),
          reason: body,
        );
      }
    });

    test(
      'unsupported calls and workbook reads remain invalid after a match',
      () {
        for (final statement in <String>[
          'Call Shell("unsafe")',
          'Worksheets(1).Range("A1").Value2 = Worksheets(1).Range("B1").Value2',
          'Exit Select',
        ]) {
          expect(
            () => _compile(
              _module(
                'Select Case 1\nCase 1\nCase Else\n$statement\nEnd Select',
              ),
            ),
            throwsA(_error('vba_unsupported')),
            reason: statement,
          );
        }
      },
    );

    test('typed conditions and comparisons are checked in unused helpers', () {
      for (final body in <String>[
        'Do While 1\nLoop',
        'Do\nLoop Until "False"',
        'While Worksheets(1)\nWend',
        'Select Case Worksheets(1)\nCase 1\nEnd Select',
        'Select Case 1\nCase "1"\nEnd Select',
        'Select Case True\nCase True To False\nEnd Select',
      ]) {
        expect(
          () => _compile('Sub Main()\nEnd Sub\nSub Hidden()\n$body\nEnd Sub'),
          throwsA(_error('vba_type_error')),
          reason: body,
        );
      }
    });

    test('new nested blocks do not allow declarations or counter writes', () {
      for (final body in <String>[
        'Do While False\nDim value As Long\nLoop',
        'While False\nConst value = 1\nWend',
        'Select Case 0\nCase Else\nDim value As Long\nEnd Select',
        'For row = 1 To 2\nDo While False\nrow = 5\nLoop\nNext row',
        'For row = 1 To 2\nSelect Case 0\nCase Else\nrow = 5\nEnd Select\nNext row',
      ]) {
        expect(
          () => _compile(_module(body)),
          throwsA(_error('vba_unsupported')),
          reason: body,
        );
      }
    });

    test('a helper cannot exit a caller loop or inherit its With binding', () {
      expect(
        () => _compile('''
Sub Main()
  Do
    Call StopLoop()
    Exit Do
  Loop
End Sub
Sub StopLoop()
  Exit Do
End Sub
'''),
        throwsA(_error('vba_unsupported')),
      );
      expect(
        () => _compile('''
Sub Main()
  With Worksheets(1)
    Call WriteHidden()
  End With
End Sub
Sub WriteHidden()
  Select Case 1
    Case 1
      .Range("A1").Value2 = 3
  End Select
End Sub
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('recursion in an unselected case alternative is still rejected', () {
      expect(
        () => _compile('''
Sub Main()
End Sub
Function Hidden() As Long
  Select Case 0
    Case 0
      Hidden = 1
    Case Hidden()
      Hidden = 2
  End Select
End Function
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('calls in untaken Case bounds count toward call-graph depth', () {
      final source = StringBuffer('Sub Main()\nEnd Sub\n');
      for (var index = 0; index < 33; index++) {
        source.writeln('Function Helper$index() As Long');
        if (index < 32) {
          source.writeln(
            'Select Case 0\nCase 0\nCase 1 To Helper${index + 1}()\nEnd Select',
          );
        }
        source.writeln('End Function');
      }
      expect(
        () => _compile(source.toString()),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('invalid exits after an early return are still checked', () {
      for (final body in <String>[
        'Exit Sub\nExit Do',
        'While False\nExit Do\nWend',
        'Do While False\nExit For\nLoop',
        'Select Case 0\nCase 0\nExit Sub\nExit Do\nEnd Select',
      ]) {
        expect(
          () => _compile(_module(body)),
          throwsA(_error('vba_unsupported')),
          reason: body,
        );
      }
    });
  });

  group('control-flow structure rejects malformed source', () {
    final malformed = <String, String>{
      'two Do conditions': 'Do While True\nLoop Until True',
      'missing Do condition': 'Do While\nLoop',
      'orphan Loop': 'Loop',
      'orphan Wend': 'Wend',
      'While ending with Loop': 'While False\nLoop',
      'Do ending with Wend': 'Do\nWend',
      'unsupported End While': 'While False\nEnd While',
      'unsupported Exit While': 'While False\nExit While\nWend',
      'orphan Case': 'Case 1',
      'orphan End Select': 'End Select',
      'missing selector': 'Select Case\nEnd Select',
      'missing Case keyword': 'Select 1\nEnd Select',
      'missing Case alternative': 'Select Case 1\nCase\nEnd Select',
      'missing range upper bound': 'Select Case 1\nCase 0 To\nEnd Select',
      'missing Is operator': 'Select Case 1\nCase Is 1\nEnd Select',
      'trailing alternative comma': 'Select Case 1\nCase 1,\nEnd Select',
      'duplicate fallback': 'Select Case 1\nCase Else\nCase Else\nEnd Select',
      'nonfinal fallback': 'Select Case 1\nCase Else\nCase 1\nEnd Select',
      'fallback with an alternative': 'Select Case 1\nCase Else, 1\nEnd Select',
      'non-clause before first Case':
          'Select Case 1\nx = 1\nCase 1\nEnd Select',
    };
    for (final entry in malformed.entries) {
      test(entry.key, () {
        expect(
          () => _compile(_module(entry.value)),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }
  });
}
