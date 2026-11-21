import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(
  String source, {
  String language = 'vba-word',
  OfficeMacroFormat format = OfficeMacroFormat.docx,
}) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: language,
    format: format,
    moduleName: 'Measurements',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('''
Option Explicit
Sub Main()
$body
End Sub
''');

double _scalar(String expression) {
  final plan = _compile(
    'ActiveDocument.Paragraphs(1).Range.InsertBefore CStr($expression)',
  );
  expect(plan.steps.single.tool, 'docx.replaceText');
  return double.parse(plan.steps.single.arguments['text']! as String);
}

void _reject(String body, String code) => expect(
  () => _compile(body),
  throwsA(
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'Measurements')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0)),
  ),
);

const _target = 'ActiveDocument.Paragraphs(1).Format';
const _conversions = <(String, String, double)>[
  ('InchesToPoints', '0.5', 36),
  ('PointsToInches', '36', 0.5),
  ('CentimetersToPoints', '2.54', 72),
  ('PointsToCentimeters', '72', 2.54),
  ('MillimetersToPoints', '25.4', 72),
  ('PointsToMillimeters', '72', 25.4),
  ('PicasToPoints', '1.5', 18),
  ('PointsToPicas', '18', 1.5),
];

void main() {
  // Independent physical-unit expectations, not the implementation's grid.
  for (final (name, input, expected) in _conversions) {
    for (final prefix in ['', 'Application.']) {
      test('$prefix$name converts $input with the documented ratio', () {
        expect(_scalar('$prefix$name($input)'), expected);
        expect(_scalar('$prefix$name(-$input)'), -expected);
        expect(_scalar('$prefix$name(0)'), 0);
      });
    }

    test('$name supports leading-dot calls in With Application', () {
      final plan = _compile('''
Dim result As Double
With Application
  result = .$name($input)
End With
ActiveDocument.Paragraphs(1).Range.InsertBefore CStr(result)
''');
      expect(
        double.parse(plan.steps.single.arguments['text']! as String),
        expected,
      );
    });

    test('$name accepts a numeric Variant and explicit numeric conversion', () {
      final plan = _compile('''
Dim value As Variant
value = $input
ActiveDocument.Paragraphs(1).Range.InsertBefore CStr($name(value))
''');
      expect(
        double.parse(plan.steps.single.arguments['text']! as String),
        expected,
      );
      expect(_scalar('$name(CDbl("$input"))'), expected);
    });

    for (final value in ['True', '"1"', 'Empty', 'Null']) {
      test('$name refuses implicit conversion of $value', () {
        _reject(
          'Dim result As Double\nresult = $name($value)',
          'vba_type_error',
        );
      });
    }

    test('$name rejects nonnumeric Variant contents at evaluation', () {
      _reject(
        'Dim value As Variant\nDim result As Double\n'
            'value = "1"\nresult = $name(value)',
        'vba_type_error',
      );
    });

    for (final expression in [
      '$name()',
      '$name(1, 2)',
      '$name(Value:=1)',
      '$name(,)',
      'Application.$name',
      'Application.$name()',
      'Application.$name(1, 2)',
      'Application.$name(Value:=1)',
      'ActiveDocument.$name(1)',
    ]) {
      test('check malformed $expression in dormant source', () {
        expect(
          () => _source('''
Sub Unused()
  Dim result As Double
  result = $expression
End Sub
Sub Main()
End Sub
'''),
          throwsA(isA<OfficeVbaCompileException>()),
        );
        expect(
          () => _compile(
            'Dim result As Double\nIf False Then\n'
            'result = $expression\nEnd If',
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }

    test('$name is reserved in Word declarations and helpers', () {
      _reject('Dim $name As Double', 'vba_name_error');
      expect(
        () => _source(
          'Function $name() As Double\nEnd Function\n'
          'Sub Main()\nEnd Sub',
        ),
        throwsA(isA<OfficeVbaCompileException>()),
      );
    });

    for (final (language, format) in [
      ('vba-excel', OfficeMacroFormat.xlsx),
      ('vba-powerpoint', OfficeMacroFormat.pptx),
    ]) {
      test('$language does not acquire Word helper $name', () {
        expect(
          () => _source(
            'Sub Main()\nDim result As Double\nresult = $name(1)\nEnd Sub',
            language: language,
            format: format,
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }
  }

  test('case-insensitive calls compose through scalar helper arguments', () {
    final plan = _source('''
Option Explicit
Function ToInches(ByVal points As Double) As Double
  ToInches = Application.pOiNtStOiNcHeS(points)
End Function
Sub Apply(ByVal layout As ParagraphFormat, ByVal inches As Double)
  layout.LeftIndent = iNcHeStOpOiNtS(inches)
End Sub
Sub Main()
  Apply inches:=ToInches(points:=36), layout:=ActiveDocument.Paragraphs(2).Format
End Sub
''');
    expect(plan.steps.single.arguments, <String, Object?>{
      'paragraph': 1,
      'left': 36.0,
    });
  });

  test('a conversion argument is evaluated exactly once', () {
    final plan = _source('''
Function Measure() As Double
  ActiveDocument.Paragraphs(2).Range.InsertBefore "once"
  Measure = 0.5
End Function
Sub Main()
  $_target.LeftIndent = Application.InchesToPoints(Measure())
End Sub
''');
    expect(plan.steps.map((step) => step.tool), [
      'docx.replaceText',
      'docx.paragraphFormat',
    ]);
    expect(plan.steps.first.arguments['text'], 'once');
    expect(plan.steps.last.arguments['left'], 36);
  });

  test('an omitted optional Variant is not a numeric measurement', () {
    expect(
      () => _source('''
Sub Apply(Optional ByVal value As Variant)
  $_target.LeftIndent = InchesToPoints(value)
End Sub
Sub Main()
  Apply
End Sub
'''),
      throwsA(isA<OfficeVbaCompileException>()),
    );
  });

  for (final (expression, expected) in <(String, double)>[
    ('InchesToPoints(0.1)', 7.2),
    ('InchesToPoints(PointsToInches(7.2))', 7.2),
    ('CentimetersToPoints(0.254)', 7.2),
    ('CentimetersToPoints(PointsToCentimeters(7.2))', 7.2),
    ('MillimetersToPoints(2.54)', 7.2),
    ('MillimetersToPoints(PointsToMillimeters(7.2))', 7.2),
    ('PicasToPoints(1.15)', 13.8),
    ('PicasToPoints(PointsToPicas(13.8))', 13.8),
    ('LinesToPoints(1.15)', 13.8),
    ('PointsToLines(13.8)', 1.15),
    ('InchesToPoints(PointsToInches(0.05))', 0.05),
    ('CentimetersToPoints(PointsToCentimeters(0.05))', 0.05),
    ('MillimetersToPoints(PointsToMillimeters(0.05))', 0.05),
    ('PicasToPoints(PointsToPicas(0.05))', 0.05),
  ]) {
    test('$expression preserves exact native point values', () {
      final plan = _compile('$_target.LeftIndent = $expression');
      expect(plan.steps.single.arguments['left'], expected);
    });
  }

  test('metric conversion remains a scalar even off the native twip grid', () {
    expect(
      _scalar('CentimetersToPoints(1)'),
      closeTo(28.346456692913385, 1e-12),
    );
    expect(
      _scalar('MillimetersToPoints(1)'),
      closeTo(2.8346456692913384, 1e-13),
    );
    _reject('$_target.LeftIndent = CentimetersToPoints(1)', 'vba_type_error');
    _reject('$_target.LeftIndent = MillimetersToPoints(1)', 'vba_type_error');
  });

  for (final expression in [
    'InchesToPoints(0.10000000000000002)',
    'PicasToPoints(1.1499999999999997)',
    'CentimetersToPoints(0.25400000000000006)',
    'MillimetersToPoints(2.5400000000000005)',
  ]) {
    test('$expression does not silently round a nearby off-grid input', () {
      _reject('$_target.LeftIndent = $expression', 'vba_type_error');
    });
  }

  for (final name in [
    'InchesToPoints',
    'CentimetersToPoints',
    'MillimetersToPoints',
    'PicasToPoints',
  ]) {
    test('$name rejects conversion overflow before producing a plan', () {
      _reject(
        'Dim result As Double\nresult = $name(9007199254740991)',
        'vba_type_error',
      );
      _reject(
        'Dim result As Double\nresult = $name(-9007199254740991)',
        'vba_type_error',
      );
    });
  }

  test('large metric intermediates do not wrap signed Dart integers', () {
    expect(
      _scalar('CentimetersToPoints(200000000000000)'),
      closeTo(5669291338582677.0, 1),
    );
    expect(
      _scalar('MillimetersToPoints(2000000000000000)'),
      closeTo(5669291338582677.0, 1),
    );
    expect(
      _scalar('PointsToMillimeters(9007199254740991)'),
      closeTo(3177539737089183.0, 1),
    );
  });

  test('target precision and bounds constrain converted values', () {
    _reject('$_target.SpaceBefore = InchesToPoints(-0.5)', 'vba_type_error');
    _reject('$_target.LeftIndent = InchesToPoints(2000000)', 'vba_type_error');
    _reject(
      'ActiveDocument.Paragraphs(1).TabStops.Add InchesToPoints(22.5)',
      'vba_type_error',
    );
    final plan = _compile(
      'ActiveDocument.Paragraphs(1).TabStops.Add InchesToPoints(22)',
    );
    expect(plan.steps.single.arguments['position'], 1584);
  });

  test('conversion expressions retain the shared source work budget', () {
    _reject('''
Dim i As Long
Dim value As Double
For i = 1 To 100000
  value = InchesToPoints(0.5)
Next i
''', 'vba_limit_exceeded');
  });
}
