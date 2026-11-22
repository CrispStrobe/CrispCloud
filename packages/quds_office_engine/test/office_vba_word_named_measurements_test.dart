import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

const _target = 'ActiveDocument.Paragraphs(1).Format';
const _range = 'ActiveDocument.Paragraphs(1).Range';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'Measurements',
    source: source,
  ),
);

OfficeMacro _compile(String body) =>
    _source('Option Explicit\nSub Main()\n$body\nEnd Sub');

double _value(String expression) => double.parse(
  _compile(
        '$_range.InsertBefore CStr($expression)',
      ).steps.single.arguments['text']!
      as String,
);

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'Measurements')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0));

void _reject(String expression, String code) => expect(
  () => _compile('Dim value As Double\nvalue = $expression'),
  throwsA(_error(code)),
);

// Independently specified physical equivalences, not factors from the compiler.
const _conversions = <(String, String, String, double)>[
  ('InchesToPoints', 'Inches', '1', 72),
  ('CentimetersToPoints', 'Centimeters', '2.54', 72),
  ('MillimetersToPoints', 'Millimeters', '25.4', 72),
  ('PicasToPoints', 'Picas', '6', 72),
  ('LinesToPoints', 'Lines', '6', 72),
  ('PointsToInches', 'Points', '72', 1),
  ('PointsToCentimeters', 'Points', '72', 2.54),
  ('PointsToMillimeters', 'Points', '72', 25.4),
  ('PointsToPicas', 'Points', '72', 6),
  ('PointsToLines', 'Points', '72', 6),
];

void main() {
  for (final (method, parameter, input, expected) in _conversions) {
    for (final prefix in ['', 'Application.']) {
      test('$prefix$method positional and official named argument agree', () {
        expect(_value('$prefix$method($input)'), expected);
        expect(_value('$prefix$method($parameter:=$input)'), expected);
        expect(
          _value(
            '$prefix${method.toUpperCase()}(${parameter.toUpperCase()}:=$input)',
          ),
          expected,
        );
      });
    }

    // Retained from the independently authored 4d0086ab measurement fixtures.
    test('$method accepts an explicitly converted numeric string', () {
      expect(_value('$method(CDbl("$input"))'), expected);
    });

    test('$method works inside With Application with a numeric Variant', () {
      final plan = _compile('''
Dim value As Variant
Dim result As Double
value = $input
With Application
  result = .$method($parameter:=value)
End With
$_range.InsertBefore CStr(result)
''');
      expect(
        double.parse(plan.steps.single.arguments['text']! as String),
        expected,
      );
    });

    test('$method preserves zero and signed measurements', () {
      expect(_value('$method(0)'), 0);
      expect(_value('$method(-$input)'), -expected);
    });

    test('$method arguments are checked in an unused helper and dead code', () {
      for (final expression in [
        '$method()',
        'Application.$method',
        '$method(,)',
        '$method($input, $parameter:=$input)',
        'Application.$method($parameter:=$input, $parameter:=$input)',
      ]) {
        expect(
          () => _source('''
Sub Unused()
  Dim value As Double
  If False Then
    value = $expression
  End If
End Sub
Sub Main()
End Sub
'''),
          throwsA(_error('vba_type_error')),
          reason: expression,
        );
      }
      for (final prefix in ['', 'Application.']) {
        expect(
          () => _source('''
Sub Unused()
  Dim value As Double
  value = $prefix$method(Unknown:=1)
End Sub
Sub Main()
End Sub
'''),
          throwsA(_error('vba_name_error')),
        );
      }
    });

    test('$method rejects scalar coercions and document objects', () {
      for (final argument in [
        'True',
        '"1"',
        'Empty',
        'Null',
        'ActiveDocument',
        'ActiveDocument.Paragraphs(1).Range',
      ]) {
        _reject('$method($parameter:=$argument)', 'vba_type_error');
      }
      for (final value in ['True', '"1"', 'Empty', 'Null']) {
        expect(
          () => _compile('''
Dim value As Variant
Dim result As Double
value = $value
result = Application.$method($parameter:=value)
'''),
          throwsA(_error('vba_type_error')),
        );
      }
    });

    test('$method cannot shadow a Word builtin', () {
      expect(
        () => _source('''
Function $method(ByVal value As Double) As Double
  $method = value
End Function
Sub Main()
End Sub
'''),
        throwsA(isA<OfficeVbaCompileException>()),
      );
    });

    for (final (language, format) in [
      ('vba-excel', OfficeMacroFormat.xlsx),
      ('vba-powerpoint', OfficeMacroFormat.pptx),
    ]) {
      test('$method does not add a builtin or reserved name to $language', () {
        OfficeMacro compile(String source) => OfficeMacroLanguages().compile(
          OfficeMacroSource(language: language, format: format, source: source),
        );
        for (final prefix in ['', 'Application.']) {
          expect(
            () => compile('''
Sub Main()
  Dim value As Double
  value = $prefix$method($input)
End Sub
'''),
            throwsA(isA<OfficeVbaCompileException>()),
          );
        }
        expect(
          () => compile('''
Function $method(ByVal value As Double) As Double
  $method = value
End Function
Sub Main()
  Dim value As Double
  value = $method(1)
End Sub
'''),
          returnsNormally,
        );
      });
    }
  }

  for (final (expression, expected) in <(String, double)>[
    ('InchesToPoints(0.1)', 7.2),
    ('InchesToPoints(0.65)', 46.8),
    ('CentimetersToPoints(0.127)', 3.6),
    ('CentimetersToPoints(1.27)', 36),
    ('CentimetersToPoints(3.81)', 108),
    ('MillimetersToPoints(1.27)', 3.6),
    ('MillimetersToPoints(12.7)', 36),
    ('PicasToPoints(1.15)', 13.8),
    ('PointsToCentimeters(3.6)', 0.127),
    ('PointsToMillimeters(3.6)', 1.27),
  ]) {
    test('$expression has canonical native-grid precision', () {
      expect(_value(expression), expected);
      // Inverse metric results are scalar values, not necessarily twip values.
      if (!expression.startsWith('PointsTo')) {
        final plan = _compile('$_target.LeftIndent = $expression');
        expect(plan.steps.single.arguments['left'], expected);
      }
    });
  }

  for (final unit in [
    'Inches',
    'Centimeters',
    'Millimeters',
    'Picas',
    'Lines',
  ]) {
    for (final points in [0.05, 0.15, 13.2, 13.8, 107374182.35]) {
      test('$unit inverse-forward round-trip retains $points points', () {
        final expression = '${unit}ToPoints(PointsTo$unit($points))';
        final plan = _compile('$_target.LeftIndent = $expression');
        expect(plan.steps.single.arguments['left'], points);
        expect(_value(expression), points);
      });
    }
  }

  test(
    'metric conversions use exact physical ratios for scalar arithmetic',
    () {
      expect(
        _value('CentimetersToPoints(1)'),
        closeTo(28.346456692913385, 1e-13),
      );
      expect(
        _value('MillimetersToPoints(1)'),
        closeTo(2.834645669291339, 1e-14),
      );
      expect(
        _value('PointsToCentimeters(1)'),
        closeTo(0.03527777777777778, 1e-16),
      );
      expect(
        _value('PointsToMillimeters(1)'),
        closeTo(0.3527777777777778, 1e-15),
      );
      expect(
        _value('InchesToPoints(PointsToInches(CentimetersToPoints(2.54)))'),
        72,
      );
    },
  );

  for (final expression in [
    'CentimetersToPoints(1)',
    'CentimetersToPoints(2.5)',
    'MillimetersToPoints(1)',
    'InchesToPoints(0.001)',
    'PicasToPoints(0.001)',
    'CentimetersToPoints(0.12700000000000003)',
    'MillimetersToPoints(1.2700000000000002)',
    'InchesToPoints(0.10000000000000002)',
    'PicasToPoints(1.1000000000000003)',
  ]) {
    test(
      'off-grid $expression remains scalar but fails native-unit writes',
      () {
        expect(_value(expression).isFinite, isTrue);
        expect(
          () => _compile('$_target.LeftIndent = $expression'),
          throwsA(_error('vba_type_error')),
        );
      },
    );
  }

  test(
    'ordinary arithmetic remains available when native normalization fails',
    () {
      expect(_value('PicasToPoints(1.1500000000000001)'), 13.8);
      expect(
        _compile(
          '$_target.LeftIndent = PicasToPoints(1.1500000000000001)',
        ).steps.single.arguments['left'],
        13.8,
      );
    },
  );

  test('conversion arguments execute once in source order inside helpers', () {
    final plan = _source('''
Function ReadAmount() As Double
  $_range.InsertBefore "evaluated"
  ReadAmount = 0.5
End Function
Sub Apply(ByVal layout As ParagraphFormat, ByVal amount As Double)
  layout.LeftIndent = amount
End Sub
Sub Main()
  Apply amount:=Application.InchesToPoints(Inches:=ReadAmount()), _
        layout:=ActiveDocument.Paragraphs(2).Format
  With Application
    .ActiveDocument.Paragraphs(3).Format.RightIndent = .InchesToPoints(ReadAmount())
  End With
End Sub
''');
    expect(plan.steps.map((step) => step.tool), [
      'docx.replaceText',
      'docx.paragraphFormat',
      'docx.replaceText',
      'docx.paragraphFormat',
    ]);
    expect(plan.steps[1].arguments, {'paragraph': 1, 'left': 36.0});
    expect(plan.steps[3].arguments, {'paragraph': 2, 'right': 36.0});
  });

  test('typed arrays, optional defaults and scalar functions compose', () {
    final plan = _source('''
Function Points(Optional ByVal inches As Double = 0.5) As Double
  Points = InchesToPoints(Inches:=inches)
End Function
Sub Main()
  Dim positions(1 To 2) As Double
  Dim index As Long
  positions(1) = Points()
  positions(2) = Points(inches:=0.75)
  For index = 1 To 2
    ActiveDocument.Paragraphs(index).Format.LeftIndent = positions(index)
  Next index
End Sub
''');
    expect(plan.steps.map((step) => step.arguments['left']), [36, 54]);
  });

  test('omitted optional Variant is not a unit value', () {
    expect(
      () => _source('''
Sub Apply(Optional ByVal amount As Variant)
  $_target.LeftIndent = InchesToPoints(Inches:=amount)
End Sub
Sub Main()
  Apply
End Sub
'''),
      throwsA(isA<OfficeVbaCompileException>()),
    );
  });

  test('unit conversions preserve pending custom line spacing boundaries', () {
    final plan = _compile('''
$_target.LineSpacingRule = wdLineSpaceExactly
$_target.LineSpacing = InchesToPoints(Inches:=0.25)
''');
    expect(plan.steps.single.arguments, {
      'paragraph': 0,
      'rule': 'exact',
      'points': 18.0,
    });
    expect(
      () => _source('''
Function Inches() As Double
  $_range.InsertBefore "unexpected"
  Inches = 0.25
End Function
Sub Main()
  $_target.LineSpacingRule = wdLineSpaceExactly
  $_target.LineSpacing = InchesToPoints(Inches:=Inches())
End Sub
'''),
      throwsA(_error('vba_unsupported')),
    );
  });

  test('numeric bounds apply to inputs and converted outputs', () {
    for (final method in [
      'InchesToPoints',
      'CentimetersToPoints',
      'MillimetersToPoints',
      'PicasToPoints',
      'LinesToPoints',
    ]) {
      _reject('$method(9007199254740991)', 'vba_type_error');
      _reject('$method(-9007199254740991)', 'vba_type_error');
    }
    for (final method in [
      'PointsToInches',
      'PointsToCentimeters',
      'PointsToMillimeters',
      'PointsToPicas',
      'PointsToLines',
    ]) {
      expect(_value('$method(9007199254740991)').isFinite, isTrue);
      expect(_value('$method(-9007199254740991)').isNegative, isTrue);
      _reject('$method(9007199254740991 + 1)', 'vba_limit_exceeded');
    }
  });

  for (final expression in [
    'ActiveDocument.InchesToPoints(1)',
    '$_target.CentimetersToPoints(1)',
    'Application.PixelsToPoints(1)',
    'Application.PointsToPixels(72)',
  ]) {
    test('unsupported receiver or screen conversion $expression', () {
      _reject(expression, 'vba_unsupported');
    });
  }

  test('conversion calls do not become Const/default expressions', () {
    for (final source in [
      'Const Width As Double = InchesToPoints(1)\nSub Main()\nEnd Sub',
      'Sub Main()\nEnd Sub\nSub Unused(Optional ByVal n As Double = InchesToPoints(1))\nEnd Sub',
    ]) {
      expect(() => _source(source), throwsA(_error('vba_unsupported')));
    }
  });

  test('named support stays confined to explicitly supported Word calls', () {
    for (final expression in [
      'RGB(Red:=1, Green:=2, Blue:=3)',
      'Len(String:="text")',
      'ActiveDocument.Paragraphs(1).Range.Characters(Index:=1)',
    ]) {
      expect(
        () => _compile('Dim value As Variant\nvalue = $expression'),
        throwsA(_error('vba_unsupported')),
      );
    }
  });

  test('large metric conversions retain portable numeric results', () {
    // Accepted scalar results must not wrap when products exceed integer range.
    for (final (expression, expected) in <(String, double)>[
      ('CentimetersToPoints(200000000000000)', 5669291338582677.0),
      ('MillimetersToPoints(2000000000000000)', 5669291338582677.0),
      ('PointsToMillimeters(9007199254740991)', 3177539737089183.0),
    ]) {
      expect(_value(expression), closeTo(expected, 1));
      expect(_value('-$expression'), closeTo(-expected, 1));
    }
  });

  test('converted tab positions retain the exact native upper boundary', () {
    final plan = _compile(
      'ActiveDocument.Paragraphs(1).TabStops.Add InchesToPoints(22)',
    );
    expect(plan.steps.single.arguments['position'], 1584);
    expect(
      () => _compile(
        'ActiveDocument.Paragraphs(1).TabStops.Add InchesToPoints(22.5)',
      ),
      throwsA(_error('vba_type_error')),
    );
  });

  test('conversion-only loops retain the shared source work budget', () {
    expect(
      () => _compile('''
Dim i As Long
Dim value As Double
For i = 1 To 100000
  value = InchesToPoints(0.5)
Next i
'''),
      throwsA(_error('vba_limit_exceeded')),
    );
  });
}
