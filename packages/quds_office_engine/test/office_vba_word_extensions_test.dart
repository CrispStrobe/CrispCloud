import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String body) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    source:
        '''
Option Explicit
Sub Main()
With ThisDocument.Paragraphs(2).Range
$body
End With
End Sub
''',
  ),
);

void main() {
  // Independently specified WdUnderline -> OOXML ST_Underline mappings.
  // https://learn.microsoft.com/en-us/office/vba/api/word.wdunderline
  for (final (name, value, xml) in <(String, int, String)>[
    ('wdUnderlineNone', 0, 'none'),
    ('wdUnderlineSingle', 1, 'single'),
    ('wdUnderlineWords', 2, 'words'),
    ('wdUnderlineDouble', 3, 'double'),
    ('wdUnderlineDotted', 4, 'dotted'),
    ('wdUnderlineThick', 6, 'thick'),
    ('wdUnderlineDash', 7, 'dash'),
    ('wdUnderlineDotDash', 9, 'dotDash'),
    ('wdUnderlineDotDotDash', 10, 'dotDotDash'),
    ('wdUnderlineWavy', 11, 'wave'),
    ('wdUnderlineDottedHeavy', 20, 'dottedHeavy'),
    ('wdUnderlineDashHeavy', 23, 'dashedHeavy'),
    ('wdUnderlineDotDashHeavy', 25, 'dashDotHeavy'),
    ('wdUnderlineDotDotDashHeavy', 26, 'dashDotDotHeavy'),
    ('wdUnderlineWavyHeavy', 27, 'wavyHeavy'),
    ('wdUnderlineDashLong', 39, 'dashLong'),
    ('wdUnderlineWavyDouble', 43, 'wavyDouble'),
    ('wdUnderlineDashLongHeavy', 55, 'dashLongHeavy'),
  ]) {
    test('$name and numeric $value emit $xml', () {
      final plan = _compile(
        '.Font.Underline = $name\n.Font.Underline = $value',
      );
      for (final step in plan.steps) {
        expect(step.tool, 'docx.runFormat');
        expect(step.arguments, {'paragraph': 1, 'underline': xml});
      }
    });
  }

  test('strikethrough and paragraph pagination use explicit Booleans', () {
    final plan = _compile('''
.Font.StrikeThrough = True
.Font.StrikeThrough = False
.ParagraphFormat.KeepTogether = True
.ParagraphFormat.PageBreakBefore = False
''');
    expect(plan.steps.map((step) => step.arguments), <Object?>[
      {'paragraph': 1, 'strike': true},
      {'paragraph': 1, 'strike': false},
      {'paragraph': 1, 'keepTogether': true},
      {'paragraph': 1, 'pageBreakBefore': false},
    ]);
    expect(plan.steps.map((step) => step.tool), <String>[
      'docx.runFormat',
      'docx.runFormat',
      'docx.paragraphFormat',
      'docx.paragraphFormat',
    ]);
  });

  test('signed paragraph indents clear the mutually exclusive setting', () {
    final plan = _compile('''
.ParagraphFormat.LeftIndent = -18
.ParagraphFormat.RightIndent = 36
.ParagraphFormat.FirstLineIndent = -12.5
.ParagraphFormat.FirstLineIndent = 9.05
.ParagraphFormat.FirstLineIndent = 0
''');
    expect(plan.steps.map((step) => step.arguments), <Object?>[
      {'paragraph': 1, 'left': -18},
      {'paragraph': 1, 'right': 36},
      {'paragraph': 1, 'firstLine': 0, 'hanging': 12.5},
      {'paragraph': 1, 'firstLine': 9.05, 'hanging': 0},
      {'paragraph': 1, 'firstLine': 0, 'hanging': 0},
    ]);
  });

  for (final (body, code) in <(String, String)>[
    ('.Font.Underline = 5', 'vba_unsupported'),
    ('.Font.Underline = -1', 'vba_unsupported'),
    ('.Font.Underline = 1.5', 'vba_type_error'),
    ('.Font.StrikeThrough = 9999998', 'vba_type_error'),
    ('.ParagraphFormat.KeepTogether = 1', 'vba_type_error'),
    ('.ParagraphFormat.PageBreakBefore = "False"', 'vba_type_error'),
    ('.ParagraphFormat.LeftIndent = 0.001', 'vba_type_error'),
    ('.ParagraphFormat.FirstLineIndent = 2147483647', 'vba_type_error'),
  ]) {
    test('unsupported Word extension value fails: $body', () {
      expect(
        () => _compile(body),
        throwsA(
          isA<OfficeVbaCompileException>().having(
            (error) => error.code,
            'code',
            code,
          ),
        ),
      );
    });
  }

  test('new members retain static checking in unused branches', () {
    expect(
      () => _compile('If False Then\n.Font.Underline = "single"\nEnd If'),
      throwsA(
        isA<OfficeVbaCompileException>().having(
          (error) => error.code,
          'code',
          'vba_type_error',
        ),
      ),
    );
  });

  test('new enum names cannot be shadowed', () {
    expect(
      () => OfficeMacroLanguages().compile(
        OfficeMacroSource(
          language: 'vba-word',
          format: OfficeMacroFormat.docx,
          source: 'Sub Main()\nDim wdUnderlineDashLong As Long\nEnd Sub',
        ),
      ),
      throwsA(
        isA<OfficeVbaCompileException>().having(
          (error) => error.code,
          'code',
          'vba_name_error',
        ),
      ),
    );
  });
}
