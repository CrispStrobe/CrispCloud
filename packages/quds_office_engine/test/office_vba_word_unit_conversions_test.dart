import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'UnitConversions',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('''
Option Explicit
Sub Main()
$body
End Sub
''');

const _target = 'ActiveDocument.Paragraphs(1).Format';
const _range = 'ActiveDocument.Paragraphs(1).Range';
const _cases = <(String, String, double)>[
  ('InchesToPoints', '1', 72),
  ('PointsToInches', '72', 1),
  ('CentimetersToPoints', '2.54', 72),
  ('PointsToCentimeters', '72', 2.54),
  ('MillimetersToPoints', '25.4', 72),
  ('PointsToMillimeters', '72', 25.4),
  ('PicasToPoints', '6', 72),
  ('PointsToPicas', '72', 6),
];

double _value(String expression, {bool withApplication = false}) {
  var body = 'n = $expression';
  if (withApplication) body = 'With Application\n$body\nEnd With';
  final plan = _compile('Dim n As Double\n$body\n$_range.InsertBefore CStr(n)');
  expect(plan.steps.single.tool, 'docx.replaceText');
  return double.parse(plan.steps.single.arguments['text']! as String);
}

void _reject(String body, String code) => expect(
  () => _compile(body),
  throwsA(
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'UnitConversions')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0)),
  ),
);

void main() {
  for (final (name, input, expected) in _cases) {
    test('$name works unqualified and through Application and With', () {
      expect(_value('$name($input)'), expected);
      expect(_value('Application.$name($input)'), expected);
      expect(_value('.$name($input)', withApplication: true), expected);
    });

    test('$name is case insensitive', () {
      final lower = name.toLowerCase();
      final upper = name.toUpperCase();
      expect(_value('$lower($input)'), expected);
      expect(_value('APPLICATION.$upper($input)'), expected);
    });

    test('$name preserves zero and sign', () {
      expect(_value('$name(0)'), 0);
      expect(_value('$name(-$input)'), -expected);
    });

    test('$name accepts a numeric Variant and emits no scalar operation', () {
      final plan = _compile('''
Dim measurement As Variant
Dim result As Double
measurement = $input
result = $name(measurement)
''');
      expect(plan.steps, isEmpty);
      final result = _compile('''
Dim measurement As Variant
measurement = $input
$_range.InsertBefore CStr($name(measurement))
''');
      expect(
        double.parse(result.steps.single.arguments['text']! as String),
        expected,
      );
    });

    test('$name evaluates a helper argument once before its result write', () {
      final plan = _source('''
Function Amount() As Double
  $_range.InsertBefore "once"
  Amount = $input
End Function
Sub Main()
  $_range.InsertBefore CStr(Application.$name(Amount()))
End Sub
''');
      expect(plan.steps, hasLength(2));
      expect(plan.steps.first.arguments['text'], 'once');
      expect(
        double.parse(plan.steps.last.arguments['text']! as String),
        expected,
      );
    });

    for (final invalid in ['True', '"1"', 'Empty', 'Null']) {
      test('$name refuses implicit numeric coercion of $invalid', () {
        _reject('Dim n As Double\nn = $name($invalid)', 'vba_type_error');
      });
    }

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
      test('dead and unused source reject $expression', () {
        expect(
          () => _compile(
            'Dim n As Double\nIf False Then\nn = $expression\nEnd If',
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
        expect(
          () => _source('''
Sub Unused()
  Dim n As Double
  n = $expression
End Sub
Sub Main()
End Sub
'''),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }

    test('$name cannot shadow a Word intrinsic', () {
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
      test('$language does not acquire $name as an intrinsic', () {
        expect(
          () => OfficeMacroLanguages().compile(
            OfficeMacroSource(
              language: language,
              format: format,
              source: 'Sub Main()\nDim n As Double\nn = $name(1)\nEnd Sub',
            ),
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }
  }

  for (final (expression, expected) in <(String, double)>[
    ('InchesToPoints(0.2)', 14.4),
    ('InchesToPoints(0.1)', 7.2),
    ('InchesToPoints(0.05)', 3.6),
    ('PicasToPoints(1.15)', 13.8),
    ('CentimetersToPoints(0.127)', 3.6),
    ('CentimetersToPoints(0.254)', 7.2),
    ('CentimetersToPoints(0.635)', 18),
    ('CentimetersToPoints(1.27)', 36),
    ('MillimetersToPoints(1.27)', 3.6),
    ('MillimetersToPoints(2.54)', 7.2),
    ('MillimetersToPoints(6.35)', 18),
    ('MillimetersToPoints(12.7)', 36),
    ('InchesToPoints(PointsToInches(14.4))', 14.4),
    ('CentimetersToPoints(PointsToCentimeters(3.6))', 3.6),
    ('MillimetersToPoints(PointsToMillimeters(3.6))', 3.6),
    ('PicasToPoints(PointsToPicas(13.8))', 13.8),
    ('LinesToPoints(PointsToLines(13.8))', 13.8),
  ]) {
    test('canonical conversion keeps native precision: $expression', () {
      final plan = _compile('$_target.LeftIndent = $expression');
      expect(plan.steps.single.arguments['left'], expected);
    });
  }

  test('metric conversions retain fractional points as scalar values', () {
    expect(_value('CentimetersToPoints(1)'), closeTo(3600 / 127, 1e-12));
    expect(_value('MillimetersToPoints(1)'), closeTo(360 / 127, 1e-12));
    expect(_value('PointsToCentimeters(1)'), closeTo(127 / 3600, 1e-15));
    expect(_value('PointsToMillimeters(1)'), closeTo(127 / 360, 1e-15));
  });

  for (final expression in [
    'CentimetersToPoints(1)',
    'MillimetersToPoints(1)',
    'InchesToPoints(0.20000000000000004)',
    'PicasToPoints(1.1499999999999997)',
    'CentimetersToPoints(2.5400000000000005)',
    'MillimetersToPoints(25.40000000000001)',
  ]) {
    test('conversion does not bypass native twip checks: $expression', () {
      _reject('$_target.LeftIndent = $expression', 'vba_type_error');
    });
  }

  test(
    'explicit CLng lets the author choose twip rounding for metric input',
    () {
      final plan = _compile(
        '$_target.LeftIndent = CLng(CentimetersToPoints(1) * 20) / 20',
      );
      expect(plan.steps.single.arguments['left'], 28.35);
    },
  );

  test('legacy PointsToLines keeps division on the off-grid fallback', () {
    final plan = _compile('''
Dim n As Double
n = PointsToLines(9007199254740991)
If n = 9007199254740991 / 12 Then
  $_range.InsertBefore "same"
Else
  $_range.InsertBefore "changed"
End If
''');
    expect(plan.steps.single.arguments['text'], 'same');
  });

  for (final name in [
    'InchesToPoints',
    'CentimetersToPoints',
    'MillimetersToPoints',
    'PicasToPoints',
  ]) {
    test('$name refuses output beyond the portable numeric bound', () {
      _reject('Dim n As Double\nn = $name(9007199254740991)', 'vba_type_error');
    });
  }

  test('large scalar conversions do not overflow grid intermediates', () {
    expect(
      _value('CentimetersToPoints(200000000000000)'),
      closeTo(200000000000000 * 3600 / 127, 1),
    );
    expect(
      _value('PointsToCentimeters(9007199254740991)'),
      closeTo(9007199254740991 * 127 / 3600, 0.125),
    );
  });

  test(
    'omitted Optional Variant cannot silently become a zero measurement',
    () {
      expect(
        () => _source('''
Sub Convert(Optional ByVal amount As Variant)
  Dim n As Double
  n = InchesToPoints(amount)
End Sub
Sub Main()
  Convert
End Sub
'''),
        throwsA(isA<OfficeVbaCompileException>()),
      );
    },
  );

  test('conversion composes with a pending custom line-spacing pair', () {
    final plan = _compile('''
Dim n As Double
$_target.LineSpacingRule = wdLineSpaceExactly
n = Application.CentimetersToPoints(0.635)
$_target.LineSpacing = n
''');
    expect(plan.steps.single.arguments, {
      'paragraph': 0,
      'rule': 'exact',
      'points': 18.0,
    });
  });

  test(
    'argument side effects still cannot interrupt a pending spacing pair',
    () {
      expect(
        () => _source('''
Function Amount() As Double
  $_range.InsertBefore "intervening write"
  Amount = 1
End Function
Sub Main()
  $_target.LineSpacingRule = wdLineSpaceExactly
  $_target.LineSpacing = InchesToPoints(Amount())
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
}
