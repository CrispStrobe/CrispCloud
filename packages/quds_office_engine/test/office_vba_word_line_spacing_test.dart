import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'LineSpacing',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('''
Option Explicit
Sub Main()
$body
End Sub
''');

void _reject(String body, String code) => expect(
  () => _compile(body),
  throwsA(
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'LineSpacing')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0)),
  ),
);

const _target = 'ActiveDocument.Paragraphs(1).Format';
String _pair(String rule, String points, {String target = _target}) =>
    '''
$target.LineSpacingRule = $rule
$target.LineSpacing = $points
''';

void main() {
  for (final (constant, value, native) in [
    ('wdLineSpaceAtLeast', 3, 'atLeast'),
    ('wdLineSpaceExactly', 4, 'exact'),
    ('wdLineSpaceMultiple', 5, 'multiple'),
  ]) {
    test('$constant and numeric $value lower a pair to one explicit edit', () {
      final plan = _compile(_pair(constant, '18.25') + _pair('$value', '21'));
      expect(plan.steps.map((step) => step.tool), [
        'docx.lineSpacing',
        'docx.lineSpacing',
      ]);
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 0, 'rule': native, 'points': 18.25},
        {'paragraph': 0, 'rule': native, 'points': 21.0},
      ]);
    });
  }

  for (final points in ['0.05', '0.15', '12.3', '107374182.35']) {
    test('point precision accepts $points without integer rounding', () {
      final plan = _compile(_pair('wdLineSpaceMultiple', points));
      expect(plan.steps.single.arguments, {
        'paragraph': 0,
        'rule': 'multiple',
        'points': double.parse(points),
      });
    });
  }

  test('typed aliases and ByVal helpers complete one selector pair', () {
    final plan = _source('''
Option Explicit
Sub SetAmount(ByVal layout As ParagraphFormat, ByVal amount As Double)
  layout.LineSpacing = amount
  Set layout = ActiveDocument.Paragraphs(3).Format
  layout.Space2
End Sub
Sub Rule(ByVal layout As ParagraphFormat)
  layout.LineSpacingRule = wdLineSpaceExactly
End Sub
Sub Main()
  Dim original As ParagraphFormat
  Dim savedFormat As ParagraphFormat
  Dim amount As Double
  Set original = ThisDocument.Paragraphs(2).Range.ParagraphFormat
  Set savedFormat = original
  Rule layout:=savedFormat
  Set original = ActiveDocument.Paragraphs(1).Format
  amount = LinesToPoints(PointsToLines(14.25))
  SetAmount amount:=amount, layout:=savedFormat
  original.Space1
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 1, 'rule': 'exact', 'points': 14.25},
      {'paragraph': 2, 'lineSpacing': 2.0, 'lineSpacingRule': 'auto'},
      {'paragraph': 0, 'lineSpacing': 1.0, 'lineSpacingRule': 'auto'},
    ]);
  });

  test('nested With and scalar branches preserve the pending selector', () {
    final plan = _compile('''
Dim amount As Double
With Application
  amount = .LinesToPoints(.PointsToLines(21))
  With .ActiveDocument.Paragraphs.Item(2)
    With .Range.ParagraphFormat
      .LineSpacingRule = wdLineSpaceMultiple
      If amount > 0 Then
        .LineSpacing = amount
      End If
    End With
  End With
End With
''');
    expect(plan.steps.single.arguments, {
      'paragraph': 1,
      'rule': 'multiple',
      'points': 21.0,
    });
  });

  test('scalar loop can complete a fresh pair on each selected paragraph', () {
    final plan = _compile('''
Dim i As Long
For i = 1 To 3
  With ActiveDocument.Paragraphs(i).Format
    .LineSpacingRule = wdLineSpaceAtLeast
    .LineSpacing = 12 + i
  End With
Next i
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 0, 'rule': 'atLeast', 'points': 13.0},
      {'paragraph': 1, 'rule': 'atLeast', 'points': 14.0},
      {'paragraph': 2, 'rule': 'atLeast', 'points': 15.0},
    ]);
  });

  test('selector expressions execute exactly once for each setter', () {
    final plan = _source('''
Function Target() As Long
  ActiveDocument.Paragraphs(3).Range.InsertBefore "selector"
  Target = 1
End Function
Sub Main()
  ActiveDocument.Paragraphs(Target()).Format.LineSpacingRule = wdLineSpaceExactly
  ActiveDocument.Paragraphs(1).Format.LineSpacing = 12
End Sub
''');
    expect(plan.steps.map((step) => step.tool), [
      'docx.replaceText',
      'docx.lineSpacing',
    ]);
    expect(plan.steps.first.arguments['text'], 'selector');
  });

  test('numeric Variants retain explicit rule and amount typing', () {
    final plan = _compile('''
Dim rule As Variant
Dim amount As Variant
rule = 4
amount = 12.3
$_target.LineSpacingRule = rule
$_target.LineSpacing = amount
''');
    expect(plan.steps.single.arguments, {
      'paragraph': 0,
      'rule': 'exact',
      'points': 12.3,
    });
  });

  for (final (method, multiple) in [
    ('Space1', 1.0),
    ('Space15', 1.5),
    ('Space2', 2.0),
  ]) {
    for (final call in [
      '$_target.$method',
      '$_target.$method()',
      'Call $_target.$method',
      'Call $_target.$method()',
      'With $_target\n.$method\nEnd With',
      'With $_target\nCall .$method()\nEnd With',
    ]) {
      test('preset statement $call', () {
        final plan = _compile(call);
        expect(plan.steps.single.tool, 'docx.paragraphFormat');
        expect(plan.steps.single.arguments, {
          'paragraph': 0,
          'lineSpacing': multiple,
          'lineSpacingRule': 'auto',
        });
      });
    }
  }

  for (final (expression, expected) in <(String, double)>[
    ('LinesToPoints(1.75)', 21),
    ('Application.LinesToPoints(1.75)', 21),
    ('PointsToLines(21)', 1.75),
    ('Application.PointsToLines(21)', 1.75),
    ('LinesToPoints(0)', 0),
    ('PointsToLines(0)', 0),
    ('LinesToPoints(-2)', -24),
    ('PointsToLines(-24)', -2),
  ]) {
    test('unit conversion $expression uses twelve points per line', () {
      final plan = _compile('$_target.LeftIndent = $expression');
      expect(plan.steps.single.arguments['left'], expected);
    });
  }

  for (final (lines, points) in <(String, double)>[
    ('1.1', 13.2),
    ('1.15', 13.8),
    ('1.2', 14.4),
    ('1.3', 15.6),
    ('1.4', 16.8),
    ('1.6', 19.2),
  ]) {
    test('native-grid conversion retains common $lines-line spacing', () {
      final plan = _compile(
        _pair('wdLineSpaceMultiple', 'LinesToPoints($lines)') +
            _pair(
              'wdLineSpaceMultiple',
              'Application.LinesToPoints(Application.PointsToLines($points))',
            ),
      );
      expect(plan.steps, hasLength(2));
      for (final step in plan.steps) {
        expect(step.arguments['points'], points);
      }
    });
  }

  for (final expression in [
    'LinesToPoints(1.1000000000000003)',
    'LinesToPoints(1.1499999999999997)',
  ]) {
    test('conversion does not widen native precision: $expression', () {
      _reject(_pair('wdLineSpaceMultiple', expression), 'vba_type_error');
    });
  }

  test('off-grid unit inputs retain ordinary numeric arithmetic', () {
    final plan = _compile(
      _pair('wdLineSpaceMultiple', 'LinesToPoints(1.1500000000000001)'),
    );
    // This multiplication already rounds to the canonical double 13.8.
    // No tolerance-based snapping of the input is needed or performed.
    expect(plan.steps.single.arguments['points'], 13.8);
  });

  for (final (amount, code) in <(String, String)>[
    ('0', 'vba_type_error'),
    ('-0.05', 'vba_type_error'),
    ('0.01', 'vba_type_error'),
    ('12.333', 'vba_type_error'),
    ('13.200000000000003', 'vba_type_error'),
    ('107374182.4', 'vba_type_error'),
    ('True', 'vba_type_error'),
    ('"12"', 'vba_type_error'),
    ('Empty', 'vba_type_error'),
    ('Null', 'vba_type_error'),
  ]) {
    test('invalid point value $amount refuses compilation', () {
      _reject(_pair('wdLineSpaceExactly', amount), code);
    });
  }

  for (final body in [
    '$_target.LineSpacingRule = wdLineSpaceExactly',
    '$_target.LineSpacing = 12',
    '$_target.LineSpacingRule = wdLineSpaceSingle\n$_target.LineSpacing = 12',
    '$_target.LineSpacingRule = wdLineSpaceExactly\nExit Sub',
    '$_target.LineSpacingRule = wdLineSpaceExactly\n$_target.Space1',
    '$_target.LineSpacingRule = wdLineSpaceExactly\n$_target.LineSpacingRule = wdLineSpaceMultiple',
    '$_target.LineSpacingRule = wdLineSpaceExactly\n$_target.SpaceAfter = 12',
    '$_target.LineSpacingRule = wdLineSpaceExactly\nActiveDocument.Paragraphs(2).Format.LineSpacing = 12',
    '$_target.LineSpacingRule = wdLineSpaceExactly\nActiveDocument.Paragraphs(2).Range.InsertBefore "x"',
    '${_pair('wdLineSpaceExactly', '12')}$_target.LineSpacing = 18',
    '$_target.LineSpacingRule = wdLineSpaceExactly\nIf False Then\n$_target.LineSpacing = 12\nEnd If',
  ]) {
    test('incomplete or interleaved pair refuses: $body', () {
      _reject(body, 'vba_unsupported');
    });
  }

  test(
    'amount helper cannot publish another mutation inside a pending pair',
    () {
      expect(
        () => _source('''
Function Amount() As Double
  ActiveDocument.Paragraphs(2).Range.Font.Bold = True
  Amount = 12
End Function
Sub Main()
  $_target.LineSpacingRule = wdLineSpaceExactly
  $_target.LineSpacing = Amount()
End Sub
'''),
        throwsA(
          isA<OfficeVbaCompileException>().having(
            (error) => error.code,
            'code',
            'vba_unsupported',
          ),
        ),
      );
    },
  );

  test('optional omitted Variant cannot supply a point value', () {
    expect(
      () => _source('''
Sub SetSpacing(Optional ByVal amount As Variant)
  $_target.LineSpacingRule = wdLineSpaceExactly
  $_target.LineSpacing = amount
End Sub
Sub Main()
  SetSpacing
End Sub
'''),
      throwsA(isA<OfficeVbaCompileException>()),
    );
  });

  for (final statement in [
    '$_target.Space1(1)',
    'Call $_target.Space15(Amount:=12)',
    '$_target.Space2 ,',
    'ActiveDocument.Paragraphs(1).Range.Space1',
    'ActiveDocument.Paragraphs(1).Space2',
    '$_target.LineSpacing(1) = 12',
    'Set $_target.LineSpacing = ActiveDocument.Paragraphs(1).Format',
  ]) {
    test(
      'malformed spacing member is checked in unused source: $statement',
      () {
        expect(
          () =>
              _source('Sub Unused()\n$statement\nEnd Sub\nSub Main()\nEnd Sub'),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      },
    );
  }

  for (final expression in [
    'LinesToPoints()',
    'LinesToPoints(1, 2)',
    'LinesToPoints(Lines:=2)',
    'PointsToLines(Points:=24)',
    'Application.LinesToPoints',
    'Application.PointsToLines()',
    'Application.LinesToPoints(1, 2)',
    'Application.LinesToPoints(Lines:=2)',
    'ActiveDocument.LinesToPoints(2)',
    '$_target.LineSpacing',
    '$_target.Space1()',
  ]) {
    test(
      'unsupported call/read shape is checked in dead source: $expression',
      () {
        expect(
          () => _compile(
            'Dim n As Double\nIf False Then\nn = $expression\nEnd If',
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      },
    );
  }

  for (final expression in [
    'LinesToPoints(True)',
    'PointsToLines("24")',
    'Application.LinesToPoints(Empty)',
    'Application.PointsToLines(Null)',
    'LinesToPoints(9007199254740991)',
  ]) {
    test('unit conversion refuses invalid runtime value: $expression', () {
      _reject('Dim n As Double\nn = $expression', 'vba_type_error');
    });
  }

  for (final name in ['LinesToPoints', 'PointsToLines']) {
    test('Word conversion $name cannot be shadowed', () {
      _reject('Dim $name As Double', 'vba_name_error');
      expect(
        () => _source(
          'Function $name() As Double\nEnd Function\nSub Main()\nEnd Sub',
        ),
        throwsA(isA<OfficeVbaCompileException>()),
      );
    });
    for (final (language, format) in [
      ('vba-excel', OfficeMacroFormat.xlsx),
      ('vba-powerpoint', OfficeMacroFormat.pptx),
    ]) {
      test('$language does not acquire Word conversion $name', () {
        expect(
          () => OfficeMacroLanguages().compile(
            OfficeMacroSource(
              language: language,
              format: format,
              source: 'Sub Main()\nDim n As Double\nn = $name(2)\nEnd Sub',
            ),
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }
  }
}
