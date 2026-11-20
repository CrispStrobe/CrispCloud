import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'ParagraphLayout',
    source: source,
  ),
);
OfficeMacro _compile(String body, {String declarations = ''}) => _source('''
Option Explicit
Sub Main()
$declarations
$body
End Sub
''');
void _reject(String body, String code, {String declarations = ''}) {
  expect(
    () => _compile(body, declarations: declarations),
    throwsA(
      isA<OfficeVbaCompileException>()
          .having((error) => error.code, 'code', code)
          .having((error) => error.moduleName, 'module', 'ParagraphLayout')
          .having((error) => error.line, 'line', greaterThan(0))
          .having((error) => error.column, 'column', greaterThan(0)),
    ),
  );
}

void main() {
  test(
    'Word Font and ParagraphFormat helpers retain their bound paragraph',
    () {
      final plan = _source('''
Option Explicit
Sub Style(ByVal face As Font, ByVal layout As ParagraphFormat)
  Dim other As Font
  Set other = face
  With other
    .Bold = True
    .SmallCaps = False
  End With
  With layout
    .ReadingOrder = wdReadingOrderRtl
    .LineSpacingRule = wdLineSpace1pt5
    .SpaceAfter = 7.5
  End With
End Sub
Sub Main()
  Dim face As Font
  Dim layout As ParagraphFormat
  Set face = Application.ActiveDocument.Paragraphs.Item(3).Range.Font
  Set layout = ThisDocument.Paragraphs(3).Format
  Call Style(face, layout)
End Sub
''');
      expect(plan.steps.map((step) => step.tool), [
        'docx.runFormat',
        'docx.runFormat',
        'docx.paragraphFormat',
        'docx.paragraphFormat',
        'docx.paragraphFormat',
      ]);
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 2, 'bold': true},
        {'paragraph': 2, 'smallCaps': false},
        {'paragraph': 2, 'rtl': true},
        {'paragraph': 2, 'lineSpacing': 1.5, 'lineSpacingRule': 'auto'},
        {'paragraph': 2, 'after': 7.5},
      ]);
    },
  );
  test('ByVal rebinding does not change the caller selector', () {
    final plan = _source('''
Sub Rebind(ByVal face As Font, ByVal layout As ParagraphFormat)
  Set face = ActiveDocument.Paragraphs(2).Range.Font
  Set layout = ActiveDocument.Paragraphs(2).Format
  face.Italic = True
  layout.ReadingOrder = wdReadingOrderRtl
End Sub
Sub Main()
  Dim face As Font
  Dim layout As ParagraphFormat
  Set face = ActiveDocument.Paragraphs(1).Range.Font
  Set layout = ActiveDocument.Paragraphs(1).Range.ParagraphFormat
  Rebind face, layout
  face.Italic = False
  layout.ReadingOrder = wdReadingOrderLtr
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 1, 'italic': true},
      {'paragraph': 1, 'rtl': true},
      {'paragraph': 0, 'italic': false},
      {'paragraph': 0, 'rtl': false},
    ]);
  });
  for (final selector in [
    'ActiveDocument.Paragraphs(1).Format',
    'ThisDocument.Paragraphs.Item(1).Format',
    'Application.ActiveDocument.Paragraphs(1).Range.ParagraphFormat',
  ]) {
    test('nested With uses $selector', () {
      final plan = _compile('''
With $selector
  .ReadingOrder = wdReadingOrderLtr
  .LineSpacingRule = wdLineSpaceSingle
End With
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 0, 'rtl': false},
        {'paragraph': 0, 'lineSpacing': 1.0, 'lineSpacingRule': 'auto'},
      ]);
    });
  }
  // Independent expectations from Microsoft's enum documentation.
  for (final (name, value, rtl) in [
    ('wdReadingOrderRtl', 0, true),
    ('wdReadingOrderLtr', 1, false),
  ]) {
    test('$name and $value change reading order without alignment', () {
      final plan = _compile('''
ActiveDocument.Paragraphs(2).Format.ReadingOrder = $name
ActiveDocument.Paragraphs(2).Format.ReadingOrder = $value
''');
      expect(plan.steps, hasLength(2));
      for (final step in plan.steps) {
        expect(step.tool, 'docx.paragraphFormat');
        expect(step.arguments, {'paragraph': 1, 'rtl': rtl});
      }
    });
  }
  for (final (name, value, multiple) in [
    ('wdLineSpaceSingle', 0, 1.0),
    ('wdLineSpace1pt5', 1, 1.5),
    ('wdLineSpaceDouble', 2, 2.0),
  ]) {
    test('$name and $value publish exact line-spacing preset', () {
      final plan = _compile('''
ActiveDocument.Paragraphs(1).Format.LineSpacingRule = $name
ActiveDocument.Paragraphs(1).Format.LineSpacingRule = $value
''');
      expect(plan.steps, hasLength(2));
      for (final step in plan.steps) {
        expect(step.tool, 'docx.paragraphFormat');
        expect(step.arguments, {
          'paragraph': 0,
          'lineSpacing': multiple,
          'lineSpacingRule': 'auto',
        });
      }
    });
  }
  for (final (property, value, code) in <(String, String, String)>[
    ('ReadingOrder', 'True', 'vba_type_error'),
    ('ReadingOrder', '"1"', 'vba_type_error'),
    ('ReadingOrder', '0.5', 'vba_type_error'),
    ('ReadingOrder', '-1', 'vba_unsupported'),
    ('ReadingOrder', '2', 'vba_unsupported'),
    ('ReadingOrder', 'Null', 'vba_type_error'),
    ('LineSpacingRule', 'False', 'vba_type_error'),
    ('LineSpacingRule', '"2"', 'vba_type_error'),
    ('LineSpacingRule', '1.5', 'vba_type_error'),
    ('LineSpacingRule', 'wdLineSpaceAtLeast', 'vba_unsupported'),
    ('LineSpacingRule', 'wdLineSpaceExactly', 'vba_unsupported'),
    ('LineSpacingRule', 'wdLineSpaceMultiple', 'vba_unsupported'),
    ('LineSpacingRule', '-1', 'vba_unsupported'),
    ('LineSpacingRule', '6', 'vba_unsupported'),
    ('LineSpacing', '18', 'vba_unsupported'),
  ]) {
    test(
      'reject $property = $value',
      () => _reject(
        'ActiveDocument.Paragraphs(1).Format.$property = $value',
        code,
      ),
    );
  }
  for (final (declaration, body, code) in <(String, String, String)>[
    ('Dim face As Font', 'face.Bold = True', 'vba_unsupported'),
    (
      'Dim layout As ParagraphFormat',
      'layout.ReadingOrder = 0',
      'vba_unsupported',
    ),
    (
      'Dim face As Font',
      'Set face = ActiveDocument.Paragraphs(1).Format',
      'vba_type_error',
    ),
    (
      'Dim layout As ParagraphFormat',
      'Set layout = ActiveDocument.Paragraphs(1).Range.Font',
      'vba_type_error',
    ),
    (
      'Dim face As Font',
      'face = ActiveDocument.Paragraphs(1).Range.Font',
      'vba_type_error',
    ),
    (
      'Dim layout As ParagraphFormat',
      'Set layout = ActiveDocument.Paragraphs(1).Format(1)',
      'vba_unsupported',
    ),
    (
      'Dim value As Variant',
      'value = ActiveDocument.Paragraphs(1).Format.ReadingOrder',
      'vba_unsupported',
    ),
    (
      'Dim value As Variant',
      'value = ActiveDocument.Paragraphs(1).Format.LineSpacingRule',
      'vba_unsupported',
    ),
    (
      'Dim layout As ParagraphFormat',
      'Set layout = ActiveDocument.Paragraphs(1).Format.Duplicate',
      'vba_unsupported',
    ),
  ]) {
    test(
      'typed aliases retain refusal: $body',
      () => _reject(body, code, declarations: declaration),
    );
  }
  test('unsupported reads and invalid alias types are checked in dead code', () {
    _reject(
      'If False Then\nSet face = ActiveDocument.Paragraphs(1).Format\nEnd If',
      'vba_type_error',
      declarations: 'Dim face As Font',
    );
    _reject(
      'If False Then\nvalue = ActiveDocument.Paragraphs(1).Format.LineSpacingRule\nEnd If',
      'vba_unsupported',
      declarations: 'Dim value As Long',
    );
  });
  test('Word-only constants cannot be shadowed', () {
    _reject(
      '',
      'vba_name_error',
      declarations: 'Dim wdReadingOrderLtr As Long',
    );
    _reject(
      '',
      'vba_name_error',
      declarations: 'Dim wdLineSpaceSingle As Long',
    );
  });
  test('Word Font remains outside Excel declaration vocabulary', () {
    expect(
      () => OfficeMacroLanguages().compile(
        OfficeMacroSource(
          language: 'vba-excel',
          format: OfficeMacroFormat.xlsx,
          source: 'Sub Main()\nDim face As Font\nEnd Sub',
        ),
      ),
      throwsA(isA<OfficeVbaCompileException>()),
    );
  });
}
