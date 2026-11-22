import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source, String dialect) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: dialect,
        format: switch (dialect) {
          'vba-word' => OfficeMacroFormat.docx,
          'vba-powerpoint' => OfficeMacroFormat.pptx,
          _ => OfficeMacroFormat.xlsx,
        },
        moduleName: 'StringReversal',
        source: source,
      ),
    );

String _module(String body) => 'Sub Main()\n$body\nEnd Sub\n';

String _write(String dialect, String expression) {
  final target = switch (dialect) {
    'vba-word' => 'ThisDocument.Tables(1).Cell(1, 1).Range.Text =',
    'vba-powerpoint' =>
      'ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text =',
    _ => 'Worksheets(1).Range("A1").Value2 =',
  };
  return '$target $expression';
}

List<Object?> _outputs(OfficeMacro macro) => [
  for (final step in macro.steps)
    step.arguments.containsKey('value')
        ? step.arguments['value']
        : step.arguments['text'],
];

Object? _value(String expression, String dialect) =>
    _outputs(_compile(_module(_write(dialect, expression)), dialect)).single;

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'StringReversal')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0));

void main() {
  for (final dialect in ['vba-word', 'vba-excel', 'vba-powerpoint']) {
    group('$dialect StrReverse', () {
      // Hand-authored expectations, not observations from installed Office.
      // UTF-16 edge cases and strict types are explicit Quds dialect choices.
      for (final (expression, expected) in <(String, String)>[
        ('StrReverse("")', ''),
        ('StrReverse("A")', 'A'),
        ('StrReverse("ABC")', 'CBA'),
        ('sTrReVeRsE("Report 42")', '24 tropeR'),
        ('StrReverse("a""b")', 'b"a'),
        ('StrReverse("  ab ")', ' ba  '),
        ('StrReverse("éø")', 'øé'),
        ('StrReverse("مرحبا")', 'ابحرم'),
        ('StrReverse("e" & ChrW(769))', '\u0301e'),
        ('StrReverse(CVar("abc"))', 'cba'),
        ('StrReverse(Empty)', ''),
        ('StrReverse(CVar(Empty))', ''),
        ('StrReverse(CStr(123))', '321'),
        ('StrReverse(CStr(True))', 'eurT'),
        ('StrReverse(StrReverse("abc😀"))', 'abc😀'),
        ('StrReverse("A" & vbTab & "B")', 'B\tA'),
        ('CStr(Len(StrReverse(ChrW(0) & "A")))', '2'),
        ('CStr(AscW(StrReverse(ChrW(0) & "A")))', '65'),
        ('CStr(AscW(StrReverse("A" & ChrW(0))))', '0'),
        ('CStr(AscW(StrReverse(ChrW(55357) & ChrW(56832))))', '-8704'),
        (
          r'CStr(AscW(Mid$(StrReverse(ChrW(55357) & ChrW(56832)), 2, 1)))',
          '-10179',
        ),
        (r'CStr(Len(StrReverse(String$(32767, "x"))))', '32767'),
      ]) {
        test(expression, () {
          expect(_value(expression, dialect), expected);
        });
      }

      for (final (expression, code) in <(String, String)>[
        ('StrReverse()', 'vba_type_error'),
        (r'StrReverse$("a")', 'vba_unsupported'),
        ('StrReverse("a", "b")', 'vba_type_error'),
        ('StrReverse(1)', 'vba_type_error'),
        ('StrReverse(True)', 'vba_type_error'),
        ('StrReverse(CVar(1))', 'vba_type_error'),
        ('StrReverse(CVar(False))', 'vba_type_error'),
        ('StrReverse(Null)', 'vba_invalid_use_of_null'),
        ('StrReverse(CVar(Null))', 'vba_invalid_use_of_null'),
        ('StrReverse(Expression:="abc")', 'vba_unsupported'),
        ('StrReverse(,)', 'vba_unsupported'),
        ('StrReverse("😀")', 'vba_type_error'),
      ]) {
        test('rejects $expression with $code', () {
          expect(
            () => _value(expression, dialect),
            throwsA(_error(code)),
          );
        });
      }

      if (dialect != 'vba-excel') {
        test('retains the Word/PowerPoint XML character boundary', () {
          expect(
            () => _value('StrReverse(ChrW(0))', dialect),
            throwsA(_error('vba_type_error')),
          );
        });
      }

      test('returns a String through typed helpers and local array slots', () {
        final first = _write(dialect, 'Restore(items(0))');
        final second = _write(dialect, 'items(0)');
        final third = _write(dialect, 'StrReverse(items(1))');
        final plan = _compile('''
Function Restore(ByVal input As String) As String
  Restore = StrReverse(input)
End Function
Sub Main()
  Dim items(0 To 1) As String
  items(0) = "ABC"
  $first
  $second
  $third
End Sub
''', dialect);
        expect(_outputs(plan), ['CBA', 'ABC', '']);
        expect(_outputs(OfficeMacro.parse(plan.encode())), ['CBA', 'ABC', '']);
      });

      test('evaluates a side-effecting argument exactly once', () {
        final trace = _write(dialect, '"argument"');
        final result = _write(dialect, 'StrReverse(SourceValue())');
        final plan = _compile('''
Function SourceValue() As String
  $trace
  SourceValue = "ABC"
End Function
Sub Main()
  $result
End Sub
''', dialect);
        expect(_outputs(plan), ['argument', 'CBA']);
      });

      test('optional Variant defaults and missing values stay distinct', () {
        final output = _write(dialect, 'Restore()');
        final source = '''
Function Restore(Optional ByVal input As Variant = "") As String
  Restore = StrReverse(input)
End Function
Sub Main()
  $output
End Sub
''';
        expect(_outputs(_compile(source, dialect)), ['']);
        expect(
          () => _compile(source.replaceFirst(' = ""', ''), dialect),
          throwsA(_error('vba_missing_argument')),
        );
      });

      test('checks incompatible arguments in inactive source', () {
        final invalid = _write(dialect, 'StrReverse(False)');
        expect(
          () => _compile(_module('If False Then\n$invalid\nEnd If'), dialect),
          throwsA(_error('vba_type_error')),
        );
        expect(
          () => _compile(
            'Sub Main()\nEnd Sub\nSub Unused()\n$invalid\nEnd Sub\n',
            dialect,
          ),
          throwsA(_error('vba_type_error')),
        );
      });

      test('does not expose object reads or whole-array values', () {
        final read = switch (dialect) {
          'vba-word' => 'ThisDocument.Paragraphs(1).Range.Text',
          'vba-powerpoint' =>
            'ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text',
          _ => 'Worksheets(1).Range("A1").Value2',
        };
        expect(
          () => _value('StrReverse($read)', dialect),
          throwsA(_error('vba_unsupported')),
        );
        final output = _write(dialect, 'StrReverse(items)');
        expect(
          () => _compile(_module('Dim items(0) As String\n$output'), dialect),
          throwsA(_error('vba_type_error')),
        );
      });

      test('runtime functions remain unavailable in Const initializers', () {
        expect(
          () => _compile(
            _module('Const value As String = StrReverse("abc")'),
            dialect,
          ),
          throwsA(_error('vba_unsupported')),
        );
      });

      test('intrinsic names remain reserved', () {
        expect(
          () => _compile(_module('Dim StrReverse As String'), dialect),
          throwsA(_error('vba_name_error')),
        );
      });

      test('reversal work is charged even without document writes', () {
        expect(
          () => _compile(_module(r'''
Dim text As String, index As Long
text = String$(1000, "x")
For index = 1 To 200
  text = StrReverse(text)
Next index
'''), dialect),
          throwsA(_error('vba_limit_exceeded')),
        );
      });

      test('empty results cannot bypass the evaluation budget', () {
        expect(
          () => _compile(_module('''
Dim text As String, index As Long
For index = 1 To 100000
  text = StrReverse("")
Next index
'''), dialect),
          throwsA(_error('vba_limit_exceeded')),
        );
      });
    });
  }
}
