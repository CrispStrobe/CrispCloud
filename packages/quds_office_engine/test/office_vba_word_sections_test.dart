import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordSections',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('''
Option Explicit
Sub Main()
$body
End Sub
''');

Matcher _error([String? code]) {
  final matcher = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'WordSections')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? matcher
      : matcher.having((error) => error.code, 'code', code);
}

const _page = 'Application.ActiveDocument.Sections.Item(2).PageSetup';

void main() {
  // Values are independent expectations from Microsoft's WdOrientation and
  // WdSectionStart enumerations, not generated from compiler dispatch tables.
  for (final (expression, orientation) in [
    ('wdOrientPortrait', 'portrait'),
    ('wdOrientLandscape', 'landscape'),
    ('wDoRiEnTlAnDsCaPe', 'landscape'),
    ('0', 'portrait'),
    ('1.0', 'landscape'),
    ('CLng(CVar(1))', 'landscape'),
  ]) {
    test('Orientation=$expression emits an explicit section operation', () {
      final step = _compile('$_page.Orientation = $expression').steps.single;
      expect(step.tool, 'docx.pageOrientation');
      expect(step.arguments, {'section': 1, 'orientation': orientation});
    });
  }

  for (final (expression, kind) in [
    ('wdSectionContinuous', 'continuous'),
    ('wdSectionNewPage', 'nextPage'),
    ('wdSectionEvenPage', 'evenPage'),
    ('wdSectionOddPage', 'oddPage'),
    ('wDsEcTiOnOdDpAgE', 'oddPage'),
    ('0', 'continuous'),
    ('2', 'nextPage'),
    ('3.0', 'evenPage'),
    ('4', 'oddPage'),
  ]) {
    test('SectionStart=$expression emits the documented native mode', () {
      final step = _compile('$_page.SectionStart = $expression').steps.single;
      expect(step.tool, 'docx.sectionStart');
      expect(step.arguments, {'section': 1, 'kind': kind});
    });
  }

  for (final statement in [
    '$_page.TogglePortrait',
    '$_page.TogglePortrait()',
    'Call $_page.TogglePortrait',
    'Call $_page.TogglePortrait()',
    'call ${_page.toLowerCase()}.toggleportrait()',
  ]) {
    test('zero-argument method form: $statement', () {
      final step = _compile(statement).steps.single;
      expect(step.tool, 'docx.pageOrientation');
      expect(step.arguments, {'section': 1, 'orientation': 'toggle'});
    });
  }

  test('typed aliases retain selectors through named ByVal helpers', () {
    final plan = _source('''
Option Explicit
Sub Configure(ByVal page As PageSetup, Optional ByVal kind As Long = wdSectionOddPage)
  page.Orientation = wdOrientLandscape
  page.SectionStart = kind
  Set page = ThisDocument.Sections(3).PageSetup
  page.TogglePortrait
End Sub
Sub Main()
  Dim original As PageSetup
  Dim retained As PageSetup
  Set original = ThisDocument.Sections(1).PageSetup
  Set retained = original
  Set original = ActiveDocument.Sections(2).PageSetup
  Configure page:=retained
  original.SectionStart = wdSectionContinuous
  retained.TogglePortrait()
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'section': 0, 'orientation': 'landscape'},
      {'section': 0, 'kind': 'oddPage'},
      {'section': 2, 'orientation': 'toggle'},
      {'section': 1, 'kind': 'continuous'},
      {'section': 0, 'orientation': 'toggle'},
    ]);
  });

  test('nested With captures selectors and restores its outer receiver', () {
    final plan = _compile('''
Dim page As PageSetup
Set page = ThisDocument.Sections(1).PageSetup
With page
  Set page = ThisDocument.Sections(3).PageSetup
  With Application.ActiveDocument.Sections
    With .Item(2).PageSetup
      .Orientation = wdOrientLandscape
      Call .TogglePortrait()
    End With
  End With
  .SectionStart = wdSectionNewPage
  page.TogglePortrait
End With
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'section': 1, 'orientation': 'landscape'},
      {'section': 1, 'orientation': 'toggle'},
      {'section': 0, 'kind': 'nextPage'},
      {'section': 2, 'orientation': 'toggle'},
    ]);
  });

  test('TogglePortrait evaluates a side-effecting selector exactly once', () {
    final plan = _source('''
Function PickSection() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "selector"
  PickSection = 2
End Function
Sub Main()
  Call ThisDocument.Sections(PickSection()).PageSetup.TogglePortrait()
End Sub
''');
    expect(plan.steps.map((step) => step.tool), [
      'docx.replaceText',
      'docx.pageOrientation',
    ]);
    expect(plan.steps.last.arguments, {'section': 1, 'orientation': 'toggle'});
  });

  test('bounded loops retain repeated toggles in execution order', () {
    final plan = _compile('''
Dim i As Long
$_page.Orientation = wdOrientLandscape
For i = 1 To 3
  $_page.TogglePortrait
Next i
$_page.SectionStart = wdSectionEvenPage
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'section': 1, 'orientation': 'landscape'},
      {'section': 1, 'orientation': 'toggle'},
      {'section': 1, 'orientation': 'toggle'},
      {'section': 1, 'orientation': 'toggle'},
      {'section': 1, 'kind': 'evenPage'},
    ]);
  });

  for (final (property, expression) in [
    ('Orientation', '2'),
    ('Orientation', '-1'),
    ('Orientation', '9999999'),
    ('SectionStart', 'wdSectionNewColumn'),
    ('SectionStart', '1'),
    ('SectionStart', '-1'),
    ('SectionStart', '5'),
  ]) {
    test('$property rejects unsupported enumeration $expression', () {
      expect(
        () => _compile('$_page.$property = $expression'),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  for (final property in ['Orientation', 'SectionStart']) {
    for (final value in ['True', '"1"', '0.5', 'Null', 'Empty']) {
      test('$property refuses nonintegral/nonnumeric $value', () {
        expect(
          () => _compile('$_page.$property = $value'),
          throwsA(_error('vba_type_error')),
        );
      });
    }
    test('$property is write-only', () {
      expect(
        () => _compile('Dim value As Long\nvalue = $_page.$property'),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  for (final body in [
    '$_page.TogglePortrait 1',
    '$_page.TogglePortrait(1)',
    'Call $_page.TogglePortrait(Orientation:=1)',
    '$_page.TogglePortrait = True',
    'Dim value As Long\nvalue = $_page.TogglePortrait()',
    'ThisDocument.TogglePortrait',
    'ThisDocument.Sections(1).TogglePortrait',
    'ThisDocument.Paragraphs(1).Range.TogglePortrait',
    'ThisDocument.PageSetup.TogglePortrait',
    'ThisDocument.Sections.PageSetup.Orientation = 0',
    'ThisDocument.Sections(1).Range.PageSetup.SectionStart = 0',
    '$_page.Orientation(1) = 0',
    '$_page.SectionStart(1) = 0',
    'Set $_page.Orientation = 0',
    'Dim page As PageSetup\npage.TogglePortrait',
  ]) {
    test('rejects unsupported scope, arguments or values: $body', () {
      expect(() => _compile(body), throwsA(_error()));
    });
  }

  test(
    'unused procedures are checked for invalid TogglePortrait arguments',
    () {
      expect(
        () => _source('''
Sub Main()
  $_page.Orientation = wdOrientLandscape
End Sub
Sub Unused()
  $_page.TogglePortrait 1
End Sub
'''),
        throwsA(_error()),
      );
    },
  );

  for (final body in [
    '$_page.Orientation = 1',
    '$_page.SectionStart = 2',
    '$_page.TogglePortrait',
  ]) {
    test(
      'section operation cannot split a custom line-spacing pair: $body',
      () {
        expect(
          () => _compile('''
ThisDocument.Paragraphs(1).Format.LineSpacingRule = wdLineSpaceExactly
$body
ThisDocument.Paragraphs(1).Format.LineSpacing = 18
'''),
          throwsA(_error('vba_unsupported')),
        );
      },
    );
  }

  test('repeated section methods honor the shared emitted-operation limit', () {
    expect(
      () => _compile('''
Dim i As Long
For i = 1 To 10001
  $_page.TogglePortrait
Next i
'''),
      throwsA(_error('vba_limit_exceeded')),
    );
  });

  for (final constant in [
    'wdOrientPortrait',
    'wdOrientLandscape',
    'wdSectionContinuous',
    'wdSectionNewColumn',
    'wdSectionNewPage',
    'wdSectionEvenPage',
    'wdSectionOddPage',
  ]) {
    test('$constant is reserved only in the Word adapter', () {
      expect(
        () => _compile('Dim $constant As Long'),
        throwsA(_error('vba_name_error')),
      );
      for (final (language, format) in [
        ('vba-excel', OfficeMacroFormat.xlsx),
        ('vba-powerpoint', OfficeMacroFormat.pptx),
      ]) {
        final macro = OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: language,
            format: format,
            source: 'Sub Main()\nDim $constant As Long\nEnd Sub',
          ),
        );
        expect(macro.steps, isEmpty);
      }
    });
  }
}
