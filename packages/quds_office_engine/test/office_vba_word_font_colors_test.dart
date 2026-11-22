import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

const _font = 'ActiveDocument.Paragraphs(1).Range.Font';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordFontColors',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Matcher _error(String code) => isA<OfficeVbaCompileException>()
    .having((error) => error.code, 'code', code)
    .having((error) => error.moduleName, 'module', 'WordFontColors')
    .having((error) => error.line, 'line', greaterThan(0))
    .having((error) => error.column, 'column', greaterThan(0));

void main() {
  // Independent WdColorIndex expectations, not imported compiler data.
  for (final (name, index, color) in <(String, int, String)>[
    ('wdAuto', 0, 'auto'),
    ('wdBlack', 1, '000000'),
    ('wdBlue', 2, '0000FF'),
    ('wdTurquoise', 3, '00FFFF'),
    ('wdBrightGreen', 4, '00FF00'),
    ('wdPink', 5, 'FF00FF'),
    ('wdRed', 6, 'FF0000'),
    ('wdYellow', 7, 'FFFF00'),
    ('wdWhite', 8, 'FFFFFF'),
    ('wdDarkBlue', 9, '000080'),
    ('wdTeal', 10, '008080'),
    ('wdGreen', 11, '008000'),
    ('wdViolet', 12, '800080'),
    ('wdDarkRed', 13, '800000'),
    ('wdDarkYellow', 14, '808000'),
    ('wdGray50', 15, '808080'),
    ('wdGray25', 16, 'C0C0C0'),
  ]) {
    test(
      'Font.ColorIndex $name and numeric $index preserve palette identity',
      () {
        final plan = _compile('''
With $_font
  .ColorIndex = $name
  .ColorIndex = $index
End With
''');
        expect(plan.steps, hasLength(2));
        for (final step in plan.steps) {
          expect(step.tool, 'docx.runFormat');
          expect(step.arguments, {'paragraph': 0, 'color': color});
        }
        expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
      },
    );
  }

  for (final (expression, color) in <(String, String)>[
    ('wdColorAutomatic', 'auto'),
    ('-16777216', 'auto'),
    ('wdColorBlack', '000000'),
    ('wdAuto', '000000'),
    ('0', '000000'),
    ('16777215', 'FFFFFF'),
    ('wdColorBlue', '0000FF'),
    ('RGB(18, 52, 86)', '123456'),
    ('RGB(255, 0, 0)', 'FF0000'),
    ('RGB(0, 0, 255)', '0000FF'),
    ('CLng(CVar(-16777216))', 'auto'),
  ]) {
    test(
      'Font.Color preserves packed RGB and automatic identity: $expression',
      () {
        expect(_compile('$_font.Color = $expression').steps.single.arguments, {
          'paragraph': 0,
          'color': color,
        });
      },
    );
  }

  test('automatic is property-specific and does not become a palette RGB', () {
    final plan = _compile('''
$_font.ColorIndex = wdAuto
$_font.Color = wdAuto
$_font.Color = wdColorAutomatic
$_font.ColorIndex = wdBlack
$_font.ColorIndex = wdNoHighlight
''');
    expect(plan.steps.map((step) => step.arguments['color']), [
      'auto',
      '000000',
      'auto',
      '000000',
      'auto',
    ]);
  });

  test(
    'typed aliases, named optional ByVal helpers and rebinding keep identity',
    () {
      final plan = _source('''
Option Explicit
Sub Paint(ByVal target As Font, Optional ByVal index As Long = wdAuto)
  target.ColorIndex = index
  Set target = ThisDocument.Paragraphs(3).Range.Font
  target.Color = wdColorAutomatic
End Sub
Sub Main()
  Dim target As Font, retained As Font, line As Paragraph
  Set line = Application.ActiveDocument.Paragraphs.Item(2)
  With line.Range
    Set target = .Font
    With .Font
      .cOlOrInDeX = wDbLuE
    End With
  End With
  Set retained = target
  Set line = ThisDocument.Paragraphs(4)
  Paint index:=wdRed, target:=target
  Paint target:=retained
  retained.Color = RGB(1, 2, 3)
End Sub
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 1, 'color': '0000FF'},
        {'paragraph': 1, 'color': 'FF0000'},
        {'paragraph': 2, 'color': 'auto'},
        {'paragraph': 1, 'color': 'auto'},
        {'paragraph': 2, 'color': 'auto'},
        {'paragraph': 1, 'color': '010203'},
      ]);
    },
  );

  for (final (collection, index, story) in [
    ('Headers', 'wdHeaderFooterPrimary', 'header'),
    ('Headers', 'wdHeaderFooterFirstPage', 'firstHeader'),
    ('Headers', 'wdHeaderFooterEvenPages', 'evenHeader'),
    ('Footers', 'wdHeaderFooterPrimary', 'footer'),
    ('Footers', 'wdHeaderFooterFirstPage', 'firstFooter'),
    ('Footers', 'wdHeaderFooterEvenPages', 'evenFooter'),
  ]) {
    test('both font color properties preserve the explicit $story target', () {
      final plan = _compile('''
With ThisDocument.Sections.Item(2).$collection.Item($index).Range.Paragraphs.Item(3).Range.Font
  .ColorIndex = wdYellow
  .Color = wdColorAutomatic
End With
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 2, 'section': 1, 'story': story, 'color': 'FFFF00'},
        {'paragraph': 2, 'section': 1, 'story': story, 'color': 'auto'},
      ]);
    });
  }

  for (final (expression, color) in [
    ('CLng("6")', 'FF0000'),
    ('CDbl("2")', '0000FF'),
    ('CVar(0)', 'auto'),
    ('16.0', 'C0C0C0'),
  ]) {
    test(
      'explicit scalar conversions retain exact palette values: $expression',
      () {
        expect(
          _compile(
            '$_font.ColorIndex = $expression',
          ).steps.single.arguments['color'],
          color,
        );
      },
    );
  }

  for (final property in ['ColorIndex', 'Color']) {
    for (final expression in ['True', 'False', '"6"', 'Null', 'Empty', '0.5']) {
      test('$property refuses implicit type coercion from $expression', () {
        expect(
          () => _compile('''
$_font.Bold = True
$_font.$property = $expression
'''),
          throwsA(_error('vba_type_error')),
        );
      });
    }
  }

  for (final expression in ['-1', 'wdByAuthor', '17', 'wdColorAutomatic']) {
    test('ColorIndex refuses unsupported palette value $expression', () {
      expect(
        () => _compile('$_font.ColorIndex = $expression'),
        throwsA(_error('vba_unsupported')),
      );
    });
  }
  for (final expression in ['-1', 'wdByAuthor', '-16777215', '16777216']) {
    test('Color refuses unsupported RGB value $expression', () {
      expect(
        () => _compile('$_font.Color = $expression'),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  for (final property in ['ColorIndex', 'Color']) {
    test('$property retains shared numeric bounds', () {
      expect(
        () => _compile('$_font.$property = 1E100'),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  }

  for (final body in [
    'ActiveDocument.Paragraphs(1).Range.ColorIndex = wdRed',
    'ActiveDocument.Paragraphs(1).Range.ParagraphFormat.ColorIndex = wdRed',
    'ThisDocument.Sections(1).Headers(1).Range.Font.ColorIndex = wdRed',
    'ThisDocument.Tables(1).Cell(1, 1).Range.ColorIndex = wdRed',
    'Dim value As Long\nvalue = $_font.ColorIndex',
    'Dim value As Long\nvalue = $_font.Color',
    '$_font.ColorIndex(wdRed)',
  ]) {
    test(
      'unsupported target/read is rejected even in inactive code: $body',
      () {
        expect(
          () => _compile('If False Then\n$body\nEnd If'),
          throwsA(_error('vba_unsupported')),
        );
      },
    );
  }

  test('unused helpers still check ColorIndex assignment types', () {
    expect(
      () => _source('''
Sub Unused()
  $_font.ColorIndex = True
End Sub
Sub Main()
End Sub
'''),
      throwsA(_error('vba_type_error')),
    );
  });

  for (final assignment in [
    'ColorIndex = wdAuto',
    'Color = wdColorAutomatic',
  ]) {
    test('$assignment cannot split a custom line-spacing pair', () {
      expect(
        () => _compile('''
ActiveDocument.Paragraphs(1).Format.LineSpacingRule = wdLineSpaceExactly
$_font.$assignment
ActiveDocument.Paragraphs(1).Format.LineSpacing = 18
'''),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  for (final (language, format, font) in [
    (
      'vba-excel',
      OfficeMacroFormat.xlsx,
      'ThisWorkbook.Worksheets(1).Range("A1").Font',
    ),
    (
      'vba-powerpoint',
      OfficeMacroFormat.pptx,
      'ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Font',
    ),
  ]) {
    test('Word ColorIndex does not silently extend $language', () {
      expect(
        () => OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: language,
            format: format,
            source: 'Sub Main()\n$font.ColorIndex = 1\nEnd Sub',
          ),
        ),
        throwsA(
          isA<OfficeVbaCompileException>().having(
            (error) => error.code,
            'code',
            'vba_unsupported',
          ),
        ),
      );
    });
  }
}
