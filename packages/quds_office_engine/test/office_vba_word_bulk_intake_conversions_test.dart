import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

// Independent qualification of the measurement helpers received during the
// mail source intake. These cases also run as JavaScript on Node.
const _target = 'ActiveDocument.Paragraphs(1).Format';
const _conversions = <(String, String, double)>[
  ('InchesToPoints', '1', 72),
  ('PointsToInches', '72', 1),
  ('CentimetersToPoints', '2.54', 72),
  ('PointsToCentimeters', '72', 2.54),
  ('MillimetersToPoints', '25.4', 72),
  ('PointsToMillimeters', '72', 25.4),
  ('PicasToPoints', '6', 72),
  ('PointsToPicas', '72', 6),
];

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'MeasurementIntake',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('''
Option Explicit
Sub Main()
$body
End Sub
''');

double _value(String expression, {bool withApplication = false}) {
  final assignment = withApplication
      ? 'With Application\n  amount = $expression\nEnd With'
      : 'amount = $expression';
  final plan = _compile('''
Dim amount As Double
$assignment
ActiveDocument.Paragraphs(1).Range.InsertBefore CStr(amount)
''');
  expect(plan.steps.single.tool, 'docx.replaceText');
  return double.parse(plan.steps.single.arguments['text']! as String);
}

void _reject(String body, String code) => expect(
  () => _compile(body),
  throwsA(
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'MeasurementIntake')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0)),
  ),
);

void main() {
  group('incoming Word measurement ratios and binding', () {
    for (final (name, input, expected) in _conversions) {
      test('$name uses the physical ratio in every Application form', () {
        expect(_value('$name($input)'), expected);
        expect(_value('Application.$name($input)'), expected);
        expect(_value('.$name($input)', withApplication: true), expected);
        expect(_value('aPpLiCaTiOn.${name.toUpperCase()}($input)'), expected);
      });

      test('$name retains zero and negative scalar values', () {
        expect(_value('$name(0)'), 0);
        expect(_value('$name(-$input)'), -expected);
      });

      test('$name rejects implicit nonnumeric coercion', () {
        for (final value in ['True', '"12"', 'Empty', 'Null']) {
          _reject(
            'Dim amount As Double\namount = $name($value)',
            'vba_type_error',
          );
        }
      });

      test('$name validates call shapes even in unreachable source', () {
        for (final expression in [
          '$name()',
          '$name(1, 2)',
          '$name(Amount:=1)',
          'Application.$name',
          'Application.$name()',
          'ActiveDocument.$name(1)',
        ]) {
          expect(
            () => _compile(
              'Dim amount As Double\nIf False Then\namount = $expression\nEnd If',
            ),
            throwsA(isA<OfficeVbaCompileException>()),
            reason: expression,
          );
        }
      });

      test('$name cannot be shadowed and does not leak into other hosts', () {
        _reject('Dim $name As Double', 'vba_name_error');
        expect(
          () => _source(
            'Function $name() As Double\nEnd Function\nSub Main()\nEnd Sub',
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
        for (final (language, format) in [
          ('vba-excel', OfficeMacroFormat.xlsx),
          ('vba-powerpoint', OfficeMacroFormat.pptx),
        ]) {
          expect(
            () => OfficeMacroLanguages().compile(
              OfficeMacroSource(
                language: language,
                format: format,
                source: 'Sub Main()\nDim n As Double\nn = $name(2)\nEnd Sub',
              ),
            ),
            throwsA(isA<OfficeVbaCompileException>()),
            reason: language,
          );
        }
      });
    }

    for (final (forward, inverse, input) in [
      ('InchesToPoints', 'PointsToInches', '0.1'),
      ('CentimetersToPoints', 'PointsToCentimeters', '0.254'),
      ('MillimetersToPoints', 'PointsToMillimeters', '2.54'),
      ('PicasToPoints', 'PointsToPicas', '0.6'),
    ]) {
      test('$forward retains common decimals through its inverse', () {
        expect(_value('$forward($input)'), 7.2);
        expect(_value('$inverse($forward($input))'), double.parse(input));
        expect(_value('$forward($inverse(7.2))'), 7.2);
        final plan = _compile('$_target.LeftIndent = $forward($input)');
        expect(plan.steps.single.arguments['left'], 7.2);
      });
    }

    test('a conversion evaluates a side-effecting argument exactly once', () {
      final plan = _source('''
Option Explicit
Function Measure() As Double
  ActiveDocument.Paragraphs(2).Range.InsertBefore "measured"
  Measure = 2.54
End Function
Sub Main()
  $_target.LeftIndent = Application.CentimetersToPoints(Measure())
End Sub
''');
      expect(plan.steps.map((step) => step.tool), [
        'docx.replaceText',
        'docx.paragraphFormat',
      ]);
      expect(plan.steps.first.arguments['text'], 'measured');
      expect(plan.steps.last.arguments['left'], 72);
    });

    test(
      'numeric Variants and a typed helper retain the computed quantity',
      () {
        final plan = _source('''
Option Explicit
Sub SetIndent(ByVal amount As Double)
  $_target.LeftIndent = amount
End Sub
Sub Main()
  Dim amount As Variant
  amount = 25.4
  SetIndent amount:=Application.MillimetersToPoints(amount)
End Sub
''');
        expect(plan.steps.single.arguments['left'], 72);
      },
    );
  });

  group('incoming Word measurement numeric limits', () {
    for (final expression in [
      'InchesToPoints(0.001)',
      'CentimetersToPoints(1)',
      'MillimetersToPoints(1)',
      'PicasToPoints(0.001)',
      'PointsToCentimeters(72)',
      'InchesToPoints(0.10000000000000003)',
    ]) {
      test('$expression cannot bypass native twip precision', () {
        expect(_value(expression).isFinite, isTrue);
        _reject('$_target.LeftIndent = $expression', 'vba_type_error');
      });
    }

    for (final name in [
      'InchesToPoints',
      'CentimetersToPoints',
      'MillimetersToPoints',
      'PicasToPoints',
    ]) {
      test(
        '$name refuses positive and negative results outside portable bounds',
        () {
          for (final input in ['9007199254740991', '-9007199254740991']) {
            _reject('Dim n As Double\nn = $name($input)', 'vba_type_error');
          }
        },
      );
    }

    for (final (expression, expected) in <(String, double)>[
      ('PointsToInches(9007199254740991)', 9007199254740991 / 72),
      (
        'PointsToCentimeters(9007199254740991)',
        9007199254740991 * (127 / 3600),
      ),
      ('PointsToMillimeters(9007199254740991)', 9007199254740991 * (127 / 360)),
      ('PointsToPicas(9007199254740991)', 9007199254740991 / 12),
      ('CentimetersToPoints(100000000000000)', 100000000000000 * (3600 / 127)),
      ('MillimetersToPoints(1000000000000000)', 1000000000000000 * (360 / 127)),
    ]) {
      test('$expression avoids overflowing integer intermediates', () {
        final actual = _value(expression);
        expect(actual.isFinite, isTrue);
        expect(actual, greaterThan(0));
        expect(actual, closeTo(expected, expected.abs() * 1e-14));
      });
    }

    test(
      'new physical helpers retain the existing twelve-point line contract',
      () {
        expect(_value('LinesToPoints(1.15)'), 13.8);
        expect(_value('PointsToLines(13.8)'), 1.15);
        expect(
          _value('LinesToPoints(PointsToLines(InchesToPoints(0.1)))'),
          7.2,
        );
      },
    );
  });
}
