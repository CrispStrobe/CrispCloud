import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordPageSetup',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Matcher _error([String? code]) {
  final result = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'WordPageSetup')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? result
      : result.having((error) => error.code, 'code', code);
}

const _setup = 'ActiveDocument.Sections(2).PageSetup';

void main() {
  // Microsoft Section.PageSetup and the eight geometry-property references
  // specify points and explicit section scope. The native names below are
  // independent expectations, not read from the compiler's dispatch map.
  for (final (property, expression, native, points)
      in <(String, String, String, num)>[
        ('PageWidth', 'InchesToPoints(8.5)', 'width', 612),
        ('PageHeight', 'Application.InchesToPoints(Inches:=11)', 'height', 792),
        ('TopMargin', 'CentimetersToPoints(2.54)', 'top', 72),
        (
          'BottomMargin',
          'MillimetersToPoints(Millimeters:=12.7)',
          'bottom',
          36,
        ),
        ('LeftMargin', 'PicasToPoints(3)', 'left', 36),
        ('RightMargin', '54.05', 'right', 54.05),
        ('HeaderDistance', '18', 'header', 18),
        ('FooterDistance', '0', 'footer', 0),
      ]) {
    test('$property emits a section-scoped $native write in points', () {
      final step = _compile('$_setup.$property = $expression').steps.single;
      expect(step.tool, 'docx.pageSetup');
      expect(step.arguments, {
        'section': 1,
        'property': native,
        'points': points,
      });
    });
  }

  for (final selector in <String>[
    'ThisDocument.Sections(2)',
    'ActiveDocument.Sections.Item(2)',
    'Application.ActiveDocument.Sections(2)',
    'aPpLiCaTiOn.AcTiVeDoCuMeNt.SeCtIoNs.ItEm(2)',
  ]) {
    test('typed Section and PageSetup aliases retain $selector', () {
      final plan = _compile('''
Dim target As Section
Dim geometry As PageSetup
Set target = $selector
Set geometry = target.PageSetup
Set target = ThisDocument.Sections(3)
geometry.TopMargin = 36
target.PageSetup.BottomMargin = 18
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'section': 1, 'property': 'top', 'points': 36},
        {'section': 2, 'property': 'bottom', 'points': 18},
      ]);
    });
  }

  test('nested With supports Document, Sections, Section and PageSetup', () {
    final plan = _compile('''
Dim doc As Document
Set doc = ThisDocument
With doc
  With .Sections
    With .Item(2)
      With .PageSetup
        .LeftMargin = 36
        .RightMargin = 54
      End With
      .PageSetup.TopMargin = 18
    End With
  End With
  .Sections(1).PageSetup.BottomMargin = 24
End With
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'section': 1, 'property': 'left', 'points': 36},
      {'section': 1, 'property': 'right', 'points': 54},
      {'section': 1, 'property': 'top', 'points': 18},
      {'section': 0, 'property': 'bottom', 'points': 24},
    ]);
  });

  test('Section and PageSetup type names remain usable as local names', () {
    final plan = _compile('''
Dim section As Section
Dim pageSetup As PageSetup
Set section = ThisDocument.Sections(2)
Set pageSetup = section.PageSetup
pageSetup.LeftMargin = 36
''');
    expect(plan.steps.single.arguments, {
      'section': 1,
      'property': 'left',
      'points': 36,
    });
  });

  test('named ByVal helpers rebind only their local section selectors', () {
    final plan = _source('''
Sub Main()
  Dim target As Section
  Dim geometry As PageSetup
  Set target = ThisDocument.Sections(2)
  Set geometry = target.PageSetup
  ApplySection target:=target
  ApplyPage geometry:=geometry, margin:=18
  target.PageSetup.HeaderDistance = 12
  geometry.FooterDistance = 12
End Sub
Sub ApplySection(ByVal target As Section)
  target.PageSetup.LeftMargin = 36
  Set target = ThisDocument.Sections(3)
  target.PageSetup.RightMargin = 54
End Sub
Sub ApplyPage(ByVal geometry As PageSetup, Optional ByVal margin As Double = 36)
  geometry.TopMargin = margin
  Set geometry = ThisDocument.Sections(4).PageSetup
  geometry.BottomMargin = margin
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'section': 1, 'property': 'left', 'points': 36},
      {'section': 2, 'property': 'right', 'points': 54},
      {'section': 1, 'property': 'top', 'points': 18},
      {'section': 3, 'property': 'bottom', 'points': 18},
      {'section': 1, 'property': 'header', 'points': 12},
      {'section': 1, 'property': 'footer', 'points': 12},
    ]);
  });

  test('a selector helper executes once and before its geometry write', () {
    final plan = _source('''
Function PickSection() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "selector"
  PickSection = 2
End Function
Sub Main()
  ThisDocument.Sections(PickSection()).PageSetup.TopMargin = 36
End Sub
''');
    expect(plan.steps.map((step) => step.tool), [
      'docx.replaceText',
      'docx.pageSetup',
    ]);
    expect(plan.steps.last.arguments, {
      'section': 1,
      'property': 'top',
      'points': 36,
    });
  });

  test('a With receiver is evaluated once for all contained setters', () {
    final plan = _source('''
Function PickSection() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "selector"
  PickSection = 2
End Function
Sub Main()
  With ThisDocument.Sections(PickSection()).PageSetup
    .PageWidth = 612
    .PageHeight = 792
  End With
End Sub
''');
    expect(plan.steps.map((step) => step.tool), [
      'docx.replaceText',
      'docx.pageSetup',
      'docx.pageSetup',
    ]);
  });

  test('geometry setters preserve surrounding paragraph operation order', () {
    final plan = _compile('''
ThisDocument.Paragraphs(1).Range.InsertBefore "before"
$_setup.LeftMargin = 36
ThisDocument.Paragraphs(2).Format.SpaceAfter = 18
$_setup.HeaderDistance = 12
''');
    expect(plan.steps.map((step) => step.tool), [
      'docx.replaceText',
      'docx.pageSetup',
      'docx.paragraphFormat',
      'docx.pageSetup',
    ]);
  });

  for (final (property, points) in <(String, double)>[
    ('PageWidth', 1),
    ('PageHeight', 1.05),
    ('TopMargin', 0),
    ('BottomMargin', 0.05),
    ('LeftMargin', 72.15),
    ('HeaderDistance', 107374182.35),
  ]) {
    test(
      'exact twentieth-point boundary $property=$points is source-valid',
      () {
        expect(
          _compile(
            '$_setup.$property = $points',
          ).steps.single.arguments['points'],
          points,
        );
      },
    );
  }

  test('source selectors defer section existence to native execution', () {
    final plan = _compile(
      'ThisDocument.Sections(9007199254740991).PageSetup.TopMargin = 0',
    );
    expect(plan.steps.single.arguments['section'], 9007199254740990);
  });

  test(
    'numeric Variants require explicit values and retain finite precision',
    () {
      final plan = _compile('''
Dim index As Variant
Dim margin As Variant
index = CVar(2)
margin = CDbl(36.05)
ThisDocument.Sections(index).PageSetup.LeftMargin = margin
''');
      expect(plan.steps.single.arguments, {
        'section': 1,
        'property': 'left',
        'points': 36.05,
      });
    },
  );

  for (final selector in <String>[
    '0',
    '-1',
    '1.5',
    'True',
    '"2"',
    'Empty',
    'Null',
    '9007199254740992',
  ]) {
    test('invalid section index $selector has a source diagnostic', () {
      expect(
        () => _compile(
          'ThisDocument.Sections($selector).PageSetup.TopMargin = 36',
        ),
        throwsA(
          _error(
            selector == '9007199254740992'
                ? 'vba_limit_exceeded'
                : 'vba_type_error',
          ),
        ),
      );
    });
  }

  for (final statement in <String>[
    'PageWidth = 0.95',
    'PageHeight = 0',
    'TopMargin = -0.05',
    'BottomMargin = 0.001',
    'LeftMargin = 107374182.4',
    'RightMargin = "72"',
    'HeaderDistance = True',
    'FooterDistance = Empty',
    'PageWidth = Null',
    'TopMargin = 72.00000000000001',
    'HeaderDistance = 1 / 0',
  ]) {
    test('invalid geometry value is refused: $statement', () {
      expect(() => _compile('$_setup.$statement'), throwsA(_error()));
    });
  }

  for (final source in <String>[
    'Dim target As Section\nSet target = ThisDocument',
    'Dim target As PageSetup\nSet target = ThisDocument.Sections(1)',
    'Dim target As Section\nSet target = $_setup',
    'Dim target As Section\ntarget = ThisDocument.Sections(1)',
    'Dim target As PageSetup\ntarget = $_setup',
    'Dim target As PageSetup\nSet target = New PageSetup',
    'Dim target As Section\ntarget.PageSetup.TopMargin = 36',
    'Dim target As PageSetup\ntarget.TopMargin = 36',
    'Dim target As Variant\ntarget = $_setup',
    'Set $_setup.TopMargin = 36',
    '$_setup = $_setup',
  ]) {
    test('invalid object binding is refused: $source', () {
      expect(() => _compile(source), throwsA(_error()));
    });
  }

  for (final type in <String>['Section', 'PageSetup']) {
    test('$type cannot receive scalar Variant even in unreachable code', () {
      expect(
        () => _compile('''
Dim target As $type
Dim value As Variant
If False Then
  Set target = value
End If
'''),
        throwsA(_error('vba_type_error')),
      );
    });

    test('$type helper is checked when unused and cannot receive Variant', () {
      expect(
        () => _source('''
Sub Main()
End Sub
Sub Unused()
  Dim value As Variant
  Apply target:=value
End Sub
Sub Apply(ByVal target As $type)
End Sub
'''),
        throwsA(_error('vba_type_error')),
      );
    });

    test('$type is not an optional object parameter', () {
      expect(
        () => _source('''
Sub Main()
End Sub
Sub Unused(Optional ByVal target As $type)
End Sub
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('$type is unavailable to other application adapters', () {
      for (final (language, format) in [
        ('vba-excel', OfficeMacroFormat.xlsx),
        ('vba-powerpoint', OfficeMacroFormat.pptx),
      ]) {
        expect(
          () => OfficeMacroLanguages().compile(
            OfficeMacroSource(
              language: language,
              format: format,
              source: 'Sub Main()\nDim target As $type\nEnd Sub',
            ),
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      }
    });
  }

  for (final statement in <String>[
    'ThisDocument.PageSetup.TopMargin = 36',
    'ThisDocument.Sections.PageSetup.TopMargin = 36',
    'ThisDocument.Paragraphs(1).Range.PageSetup.TopMargin = 36',
    '$_setup.PaperSize = 1',
    '$_setup.Gutter = 18',
    '$_setup.DifferentFirstPageHeaderFooter = True',
    '$_setup.OddAndEvenPagesHeaderFooter = True',
    'Dim width As Double\nwidth = $_setup.PageWidth',
    'Dim count As Long\ncount = ThisDocument.Sections.Count',
    'Dim target As Section\nSet target = ThisDocument.Sections.First',
    'Dim target As Section\nSet target = ThisDocument.Sections.Last',
    'Dim target As Range\nSet target = ThisDocument.Sections(1).Range',
    'ThisDocument.Sections(1).Headers(1).Range.InsertBefore "header"',
    'ThisDocument.Sections()',
    'ThisDocument.Sections(1, 2).PageSetup.TopMargin = 36',
    'ThisDocument.Sections(Position:=1).PageSetup.TopMargin = 36',
    'ThisDocument.Sections.Item().PageSetup.TopMargin = 36',
    'ThisDocument.Sections(1).PageSetup(1).TopMargin = 36',
    '$_setup.TopMargin(1) = 36',
  ]) {
    test('scope, reads and argument shapes are refused: $statement', () {
      expect(() => _compile(statement), throwsA(_error()));
    });
  }

  test('the whole module is checked before a native plan is returned', () {
    expect(
      () => _source('''
Sub Main()
  $_setup.TopMargin = 36
End Sub
Sub Unused()
  $_setup.TopMargin = "36"
End Sub
'''),
      throwsA(_error('vba_type_error')),
    );
    expect(
      () => _compile('If False Then\n$_setup.PageWidth = True\nEnd If'),
      throwsA(_error('vba_type_error')),
    );
  });

  test('unexecuted valid page geometry emits no operation', () {
    final plan = _compile('''
If False Then
  $_setup.TopMargin = 36
End If
$_setup.FooterDistance = 18
''');
    expect(plan.steps.single.arguments, {
      'section': 1,
      'property': 'footer',
      'points': 18,
    });
  });

  test('page geometry cannot interrupt a pending custom line-spacing pair', () {
    expect(
      () => _compile('''
ThisDocument.Paragraphs(1).Format.LineSpacingRule = wdLineSpaceExactly
$_setup.TopMargin = 36
ThisDocument.Paragraphs(1).Format.LineSpacing = 12
'''),
      throwsA(_error('vba_unsupported')),
    );
  });

  test('a completed custom spacing pair can precede section geometry', () {
    final plan = _compile('''
ThisDocument.Paragraphs(1).Format.LineSpacingRule = wdLineSpaceExactly
ThisDocument.Paragraphs(1).Format.LineSpacing = 12
$_setup.TopMargin = 36
''');
    expect(plan.steps.map((step) => step.tool), [
      'docx.lineSpacing',
      'docx.pageSetup',
    ]);
  });

  test('geometry writes share the aggregate native operation limit', () {
    const body = '''
Dim geometry As PageSetup
Dim i As Long
Set geometry = ActiveDocument.Sections(1).PageSetup
For i = 1 To 10000
  geometry.TopMargin = 36
Next i
''';
    expect(_compile(body).steps, hasLength(10000));
    expect(
      () => _compile('$body\ngeometry.FooterDistance = 18'),
      throwsA(_error('vba_limit_exceeded')),
    );
  });
}
