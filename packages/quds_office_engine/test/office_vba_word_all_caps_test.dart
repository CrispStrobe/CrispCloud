import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

const _range = 'ActiveDocument.Paragraphs(1).Range';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordAllCaps',
    source: source,
  ),
);

OfficeMacro _plan(String body) => _source('Sub Main()\n$body\nEnd Sub');

void _reject(String body, String code) => expect(
  () => _plan(body),
  throwsA(
    isA<OfficeVbaCompileException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.moduleName, 'module', 'WordAllCaps')
        .having((e) => e.line, 'line', greaterThan(0))
        .having((e) => e.column, 'column', greaterThan(0)),
  ),
);

void main() {
  for (final selector in [
    'ThisDocument.Paragraphs(2)',
    'ThisDocument.Paragraphs.Item(2)',
    'ActiveDocument.Paragraphs(2)',
    'Application.ActiveDocument.Paragraphs.Item(2)',
  ]) {
    test('AllCaps uses the explicit paragraph: $selector', () {
      final plan = _plan('$selector.Range.Font.AllCaps = True');
      expect(plan.steps.single.tool, 'docx.runFormat');
      expect(plan.steps.single.arguments, {'paragraph': 1, 'allCaps': true});
      expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
    });
  }

  test('case-insensitive Boolean writes retain ordered capital intent', () {
    final plan = _plan('''
With $_range.Font
  .ALLCAPS = True
  .SmallCaps = True
  .allcaps = False
  .SmallCaps = False
End With
''');
    expect(plan.steps.map((s) => s.tool), everyElement('docx.runFormat'));
    expect(plan.steps.map((s) => s.arguments), [
      {'paragraph': 0, 'allCaps': true},
      {'paragraph': 0, 'smallCaps': true},
      {'paragraph': 0, 'allCaps': false},
      {'paragraph': 0, 'smallCaps': false},
    ]);
  });

  test('typed aliases, nested With and named ByVal helpers retain targets', () {
    final plan = _source('''
Sub Capitalize(ByVal face As Font, Optional ByVal enabled As Boolean = True)
  face.AllCaps = enabled
  Set face = ThisDocument.Paragraphs(3).Range.Font
  face.AllCaps = False
End Sub
Sub Main()
  Dim target As Range, face As Font
  Set target = ThisDocument.Paragraphs(2).Range
  With target
    Set face = .Font
    With .Font
      .AllCaps = False
    End With
  End With
  Set target = ThisDocument.Paragraphs(4).Range
  Capitalize face:=face
  face.AllCaps = True
End Sub
''');
    expect(plan.steps.map((s) => s.arguments), [
      {'paragraph': 1, 'allCaps': false},
      {'paragraph': 1, 'allCaps': true},
      {'paragraph': 2, 'allCaps': false},
      {'paragraph': 1, 'allCaps': true},
    ]);
  });

  test('Boolean expressions, scalar Variants and explicit coercions work', () {
    final plan = _plan('''
Dim value As Variant
value = True
$_range.Font.AllCaps = value
$_range.Font.AllCaps = CBool(0)
$_range.Font.AllCaps = Not False
''');
    expect(plan.steps.map((s) => s.arguments['allCaps']), [true, false, true]);
  });

  for (final (collection, constant, story) in [
    ('Headers', 'wdHeaderFooterPrimary', 'header'),
    ('Headers', 'wdHeaderFooterFirstPage', 'firstHeader'),
    ('Headers', 'wdHeaderFooterEvenPages', 'evenHeader'),
    ('Footers', 'wdHeaderFooterPrimary', 'footer'),
    ('Footers', 'wdHeaderFooterFirstPage', 'firstFooter'),
    ('Footers', 'wdHeaderFooterEvenPages', 'evenFooter'),
  ]) {
    test('AllCaps retains independent $story selector identity', () {
      final plan = _plan('''
ThisDocument.Sections.Item(2).$collection.Item($constant).Range.Paragraphs.Item(3).Range.Font.AllCaps = True
''');
      expect(plan.steps.single.arguments, {
        'section': 1,
        'story': story,
        'paragraph': 2,
        'allCaps': true,
      });
    });
  }

  for (final value in [
    '-1',
    '0',
    '1',
    '1.5',
    '"True"',
    'Empty',
    'Null',
    '9999998',
    'wdToggle',
    'wdUndefined',
  ]) {
    test('AllCaps refuses implicit or mixed state value $value', () {
      _reject(
        '$_range.Font.AllCaps = $value',
        value == 'wdToggle' ? 'vba_name_error' : 'vba_type_error',
      );
    });
  }

  test(
    'runtime Variant type is checked before any partial plan is returned',
    () {
      _reject('''
Dim value As Variant
value = "True"
$_range.InsertBefore "prefix"
$_range.Font.AllCaps = value
''', 'vba_type_error');
    },
  );

  for (final body in [
    'Dim value As Boolean\nvalue = $_range.Font.AllCaps',
    '$_range.AllCaps = True',
    '$_range.Font.AllCaps True',
    '$_range.Font.AllCaps = ThisDocument.Paragraphs(2).Range.Font.AllCaps',
  ]) {
    test('unsupported capital access is checked in inactive code: $body', () {
      _reject('If False Then\n$body\nEnd If', 'vba_unsupported');
    });
  }

  test('inactive branches still check Boolean assignment types', () {
    _reject(
      'If False Then\n$_range.Font.AllCaps = 1\nEnd If',
      'vba_type_error',
    );
  });

  test('unused helpers still reject AllCaps reads', () {
    expect(
      () => _source('''
Sub Unused(ByVal face As Font)
  Dim value As Boolean
  value = face.AllCaps
End Sub
Sub Main()
End Sub
'''),
      throwsA(
        isA<OfficeVbaCompileException>().having(
          (e) => e.code,
          'code',
          'vba_unsupported',
        ),
      ),
    );
  });

  test('capital writes cannot interrupt a pending custom spacing pair', () {
    _reject('''
$_range.ParagraphFormat.LineSpacingRule = wdLineSpaceExactly
$_range.Font.AllCaps = True
$_range.ParagraphFormat.LineSpacing = 14
''', 'vba_unsupported');
  });

  test('AllCaps remains unavailable in spreadsheet dialect', () {
    expect(
      () => OfficeMacroLanguages().compile(
        OfficeMacroSource(
          language: 'vba-excel',
          format: OfficeMacroFormat.xlsx,
          source:
              'Sub Main()\nThisWorkbook.Worksheets(1).Range("A1").Font.AllCaps = True\nEnd Sub',
        ),
      ),
      throwsA(
        isA<OfficeVbaCompileException>().having(
          (e) => e.code,
          'code',
          'vba_unsupported',
        ),
      ),
    );
  });
}
