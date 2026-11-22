import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    moduleName: 'NumericIntrinsics',
    source: source,
  ),
);

OfficeMacro _body(String body) => _source('Sub Main()\n$body\nEnd Sub');

String _write(String expression) =>
    'Worksheets(1).Range("A1").Value2 = $expression';

Object? _value(String expression) =>
    _body(_write(expression)).steps.single.arguments['value'];

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'NumericIntrinsics')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0));

void _reject(String expression, String code) =>
    expect(() => _value(expression), throwsA(_error(code)), reason: expression);

void main() {
  // Specification-derived expectations, not recordings from an Office host.
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/abs-function
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/int-fix-functions
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/sgn-function
  group('numeric values and signed fractions', () {
    for (final (source, expected) in <(String, num)>[
      ('Abs(-50.3)', 50.3),
      ('Abs(50.3)', 50.3),
      ('Abs(-2147483648)', 2147483648),
      ('Abs(-9007199254740991)', 9007199254740991),
      ('Abs(9007199254740991)', 9007199254740991),
      ('Int(99.8)', 99),
      ('Fix(99.2)', 99),
      ('Int(-99.8)', -100),
      ('Fix(-99.8)', -99),
      ('Int(-99.2)', -100),
      ('Fix(-99.2)', -99),
      ('Int(-0.25)', -1),
      ('Fix(-0.25)', 0),
      ('Int(0.25)', 0),
      ('Fix(0.25)', 0),
      ('Int(-2)', -2),
      ('Fix(-2)', -2),
      ('Int(2147483648)', 2147483648),
      ('Fix(-2147483649)', -2147483649),
      ('Int(9007199254740991)', 9007199254740991),
      ('Fix(-9007199254740991)', -9007199254740991),
      ('Int(-0.000000000001)', -1),
      ('Fix(-0.000000000001)', 0),
      ('Sgn(12)', 1),
      ('Sgn(-2.4)', -1),
      ('Sgn(0)', 0),
      ('Sgn(9007199254740991)', 1),
      ('Sgn(-9007199254740991)', -1),
      ('Sgn(-0.000000000001)', -1),
      ('Sgn(-3.4) * Int(Abs(-3.4))', -3),
      ('CLng(-2.5) - Int(-2.5)', 1),
      ('CLng(-2.5) - Fix(-2.5)', 0),
    ]) {
      test('$source yields $expected', () => expect(_value(source), expected));
    }

    for (final name in ['Abs', 'Int', 'Fix', 'Sgn']) {
      test('$name recognizes mixed case and normalizes both zero signs', () {
        final mixed =
            '${name[0].toLowerCase()}${name.substring(1).toUpperCase()}';
        expect(_value('$mixed(-3.25)'), _value('$name(-3.25)'));
        for (final input in ['0', '0.0', '-0.0', '-(0 / 2)']) {
          final value = _value('$name($input)')! as num;
          expect(value, 0);
          expect(value.isNegative, isFalse);
        }
      });
      test('$name accepts numeric Variants and explicit conversions', () {
        expect(_value('$name(CVar(-3.75))'), _value('$name(-3.75)'));
        expect(_value('$name(CDbl("-3.75"))'), _value('$name(-3.75)'));
        expect(_value('$name(CDbl(True))'), _value('$name(-1)'));
        expect(_value('$name(CLng("-3"))'), _value('$name(-3)'));
      });
      test('$name treats Empty and uninitialized Variant as zero', () {
        expect(_value('$name(Empty)'), 0);
        expect(_value('$name(CVar(Empty))'), 0);
        final plan = _body('Dim value As Variant\n${_write('$name(value)')}');
        expect(plan.steps.single.arguments['value'], 0);
      });
    }
  });

  group('Null propagation and typed results', () {
    for (final name in ['Abs', 'Int', 'Fix']) {
      test('$name preserves Null through nested and assigned forms', () {
        expect(_value('IsNull($name(Null))'), true);
        expect(_value('IsNull($name(CVar(Null)))'), true);
        expect(_value('IsNull($name($name(Null)))'), true);
        expect(_value('IsNull($name(Null) + 3)'), true);
        expect(_value('IsNull($name(Null) = 3)'), true);
        // Concatenation retains the existing Null-as-empty String rule.
        expect(_value('$name(Null) & "suffix"'), 'suffix');
        final plan = _body('''
Dim value As Variant
value = $name(Null)
${_write('IsNull(value)')}
''');
        expect(plan.steps.single.arguments['value'], true);
      });
      test('$name Null result cannot be published or assigned to Double', () {
        _reject('$name(Null)', 'vba_invalid_use_of_null');
        expect(
          () => _body('Dim value As Double\nvalue = $name(Null)'),
          throwsA(_error('vba_invalid_use_of_null')),
        );
      });
    }
    test('Sgn refuses Null instead of publishing a misleading sign', () {
      for (final value in ['Null', 'CVar(Null)', 'Abs(Null)', 'Fix(Null)']) {
        _reject('Sgn($value)', 'vba_invalid_use_of_null');
      }
    });
    test('typed numeric results compose with helpers and typed arrays', () {
      final plan = _source('''
Option Explicit
Function Whole(ByVal input As Double) As Long
  Whole = Fix(input)
End Function
Sub Main()
  Dim values(1 To 3) As Double, result As Long, index As Long
  values(1) = -3.75
  values(2) = 0
  values(3) = 4.25
  For index = 1 To 3
    result = Whole(values(index))
    Worksheets(1).Cells(index, 1).Value2 = Abs(result)
    Worksheets(1).Cells(index, 2).Value2 = Sgn(result)
  Next index
End Sub
''');
      expect(plan.steps.map((step) => step.arguments['value']), [
        3,
        -1,
        0,
        0,
        4,
        1,
      ]);
    });
    test('Long assignment keeps its existing signed 32-bit bound', () {
      for (final source in [
        'Abs(-2147483648)',
        'Int(2147483648)',
        'Fix(-2147483649)',
      ]) {
        expect(
          () => _body('Dim result As Long\nresult = $source'),
          throwsA(_error('vba_type_error')),
        );
      }
    });
  });

  group('source validation and evaluation boundaries', () {
    for (final name in ['Abs', 'Int', 'Fix', 'Sgn']) {
      for (final expression in ['$name()', '$name(1, 2)']) {
        test('wrong arity is checked: $expression', () {
          _reject(expression, 'vba_type_error');
        });
      }
      for (final expression in ['$name(number:=1)', '$name(,)', '$name(1,)']) {
        test('unsupported argument shape is checked: $expression', () {
          _reject(expression, 'vba_unsupported');
        });
      }
      for (final value in ['True', 'False', '"2"', 'CVar(True)', 'CVar("2")']) {
        test('$name rejects implicit scalar conversion of $value', () {
          _reject('$name($value)', 'vba_type_error');
        });
      }
      for (final expression in [
        '$name()',
        '$name(1, 2)',
        '$name(True)',
        '$name("2")',
        '$name(Worksheets(1))',
      ]) {
        test('unused invalid call is checked: $expression', () {
          expect(
            () => _source('''
Sub Main()
End Sub
Sub Unused()
  Dim value As Variant
  Exit Sub
  value = $expression
End Sub
'''),
            throwsA(_error('vba_type_error')),
          );
        });
      }
      test('$name cannot be shadowed by local, helper, or parameter', () {
        expect(
          () => _body('Dim $name As Long'),
          throwsA(_error('vba_name_error')),
        );
        expect(
          () => _source('Sub Main()\nEnd Sub\nSub $name()\nEnd Sub'),
          throwsA(_error('vba_name_error')),
        );
        expect(
          () => _source(
            'Sub Main()\nEnd Sub\nSub Helper(ByVal $name As Long)\nEnd Sub',
          ),
          throwsA(_error('vba_name_error')),
        );
      });
      test('$name argument helper runs exactly once before its result', () {
        final plan = _source('''
Function Value() As Double
  Worksheets(1).Range("B1").Value2 = "argument"
  Value = -3.75
End Function
Sub Main()
  ${_write('$name(Value())')}
End Sub
''');
        expect(plan.steps.length, 2);
        expect(plan.steps.first.arguments['value'], 'argument');
        expect(plan.steps.last.arguments['value'], _value('$name(-3.75)'));
      });
      test('$name does not broaden Const or optional-default expressions', () {
        expect(
          () => _source('Const Size As Long = $name(2)\nSub Main()\nEnd Sub'),
          throwsA(_error('vba_unsupported')),
        );
        expect(
          () => _source(
            'Sub Main()\nEnd Sub\nSub Helper(Optional ByVal value As Long = $name(2))\nEnd Sub',
          ),
          throwsA(_error('vba_unsupported')),
        );
      });
      test('$name validates finite inputs before its bounded result', () {
        for (final input in [
          '9007199254740991 + 1',
          '-9007199254740991 - 1',
          'CDbl("1e100")',
          'CDbl("-1e100")',
        ]) {
          _reject('$name($input)', 'vba_limit_exceeded');
        }
      });
    }
    test('numeric calls consume the existing shared work budget', () {
      expect(
        () => _body('''
Dim index As Long, result As Double
For index = 1 To 100000
  result = Abs(Fix(-3.75))
Next index
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
    test('an invalid late numeric value never returns a partial plan', () {
      expect(
        () => _body('${_write('"earlier"')}\n${_write('Sgn(Null)')}'),
        throwsA(_error('vba_invalid_use_of_null')),
      );
    });
  });

  group('shared Word and PowerPoint source adapters', () {
    test('Word uses source-known numbers for native paragraph formatting', () {
      final plan = const OfficeVbaWordMacroLanguage().compile(
        OfficeMacroSource(
          language: 'vba-word',
          format: OfficeMacroFormat.docx,
          source: '''
Sub Main()
  With ActiveDocument.Paragraphs(1).Range
    .Font.Position = Fix(-2.75)
    .ParagraphFormat.LeftIndent = Abs(-18)
    .ParagraphFormat.FirstLineIndent = Int(-2.25)
    .InsertBefore CStr(Sgn(-1)) & ": "
  End With
End Sub
''',
        ),
      );
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 0, 'position': -2},
        {'paragraph': 0, 'left': 18},
        {'paragraph': 0, 'hanging': 3, 'firstLine': 0},
        {'paragraph': 0, 'start': 0, 'end': 0, 'text': '-1: '},
      ]);
    });
    test(
      'PowerPoint shares the same number construction without new writes',
      () {
        final plan = const OfficeVbaPowerPointMacroLanguage().compile(
          OfficeMacroSource(
            language: 'vba-powerpoint',
            format: OfficeMacroFormat.pptx,
            source: '''
Sub Main()
  With ActivePresentation.Slides(1).Shapes(1)
    .Left = Abs(-12.5)
    .Top = Int(3.75)
    .TextFrame.TextRange.Text = CStr(Fix(-4.75)) & "/" & CStr(Sgn(0))
  End With
End Sub
''',
          ),
        );
        expect(plan.steps[0].arguments['x'], 12.5);
        expect(plan.steps[1].arguments['y'], 3);
        expect(plan.steps[2].arguments['text'], '-4/0');
      },
    );
  });
}
