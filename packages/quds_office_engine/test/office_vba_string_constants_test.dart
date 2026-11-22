import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

const _constants = <String, String>{
  'vbTab': '\t',
  'vbCr': '\r',
  'vbLf': '\n',
  'vbCrLf': '\r\n',
  'vbBack': '\b',
  'vbFormFeed': '\f',
  'vbVerticalTab': '\u000b',
  'vbNullChar': '\u0000',
};

OfficeMacro _compile(String language, String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: language,
        format: switch (language) {
          'vba-word' => OfficeMacroFormat.docx,
          'vba-powerpoint' => OfficeMacroFormat.pptx,
          _ => OfficeMacroFormat.xlsx,
        },
        moduleName: 'StringConstants',
        source: source,
      ),
    );

String _write(String language, String expression) => switch (language) {
  'vba-word' =>
    'ActiveDocument.Paragraphs(1).Range.InsertBefore Text:=$expression',
  'vba-powerpoint' =>
    'ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text = $expression',
  _ => 'ThisWorkbook.Worksheets(1).Range("A1").Value2 = $expression',
};

Object? _output(OfficeMacro plan) =>
    plan.steps.single.arguments[plan.format == OfficeMacroFormat.xlsx
        ? 'value'
        : 'text'];

Matcher _error(String code) => isA<OfficeVbaCompileException>()
    .having((error) => error.code, 'code', code)
    .having((error) => error.moduleName, 'module', 'StringConstants');

void main() {
  for (final language in ['vba-word', 'vba-excel', 'vba-powerpoint']) {
    group('$language portable source constants', () {
      for (final entry in _constants.entries) {
        test(
          '${entry.key} has exact UTF-16 units and case-insensitive lookup',
          () {
            final expected = entry.value.codeUnits.join(',');
            final plan = _compile(language, '''
Sub Main()
  Dim value As String, result As String, i As Long
  value = ${entry.key.toUpperCase()}
  For i = 1 To Len(value)
    If i > 1 Then
      result = result & ","
    End If
    result = result & CStr(AscW(Mid\$(value, i, 1)))
  Next i
  ${_write(language, 'result')}
End Sub
''');
            expect(_output(plan), expected);
            expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
          },
        );

        test('${entry.key} works in Const and optional String defaults', () {
          final plan = _compile(language, '''
Const token As String = ${entry.key}
Sub Main()
  ${_write(language, 'Describe() & ":" & CStr(Len(token))')}
End Sub
Function Describe(Optional ByVal value As String = ${entry.key}) As String
  Describe = CStr(AscW(value))
End Function
''');
          expect(
            _output(plan),
            '${entry.value.codeUnitAt(0)}:${entry.value.length}',
          );
        });
      }

      test('constants compose with arrays, Join and source-only cleanup', () {
        final plan = _compile(language, '''
Sub Main()
  Dim labels(1 To 2) As String
  Dim result As String
  labels(1) = "First"
  labels(2) = "Second"
  result = Replace(Join(labels, vbCrLf), vbCrLf, vbTab)
  ${_write(language, 'result')}
End Sub
''');
        expect(_output(plan), 'First\tSecond');
      });

      test('String constants do not acquire numeric or Boolean coercion', () {
        for (final type in ['Long', 'Double', 'Boolean']) {
          expect(
            () => _compile(language, '''
Sub Main()
  Dim value As $type
  If False Then
    value = vbTab
  End If
End Sub
'''),
            throwsA(_error('vba_type_error')),
          );
        }
      });

      for (final declaration in [
        'Dim vbTab As String',
        'Const vbCr As String = "x"',
      ]) {
        test('shared constants cannot be shadowed by $declaration', () {
          expect(
            () => _compile(language, 'Sub Main()\n$declaration\nEnd Sub'),
            throwsA(_error('vba_name_error')),
          );
        });
      }

      for (final unsupported in ['vbNewLine', 'vbNullString']) {
        test('$unsupported retains its distinct unsupported contract', () {
          expect(
            () => _compile(language, '''
Sub Main()
  ${_write(language, unsupported)}
End Sub
'''),
            throwsA(_error('vba_name_error')),
          );
        });
      }
    });
  }

  for (final name in _constants.keys.where((name) => name != 'vbTab')) {
    test('Word native text still refuses structural control $name', () {
      for (final receiver in [
        'ActiveDocument.Paragraphs(1).Range',
        'ActiveDocument.Tables(1).Cell(1, 1).Range',
      ]) {
        expect(
          () => _compile('vba-word', '''
Sub Main()
  $receiver.InsertBefore Text:=$name
End Sub
'''),
          throwsA(_error('vba_type_error')),
        );
      }
    });
  }
}
