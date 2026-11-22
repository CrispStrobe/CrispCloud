import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordShading',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Matcher _error([String? code]) {
  final matcher = isA<OfficeVbaCompileException>()
      .having((e) => e.moduleName, 'module', 'WordShading')
      .having((e) => e.line, 'line', greaterThan(0))
      .having((e) => e.column, 'column', greaterThan(0));
  return code == null ? matcher : matcher.having((e) => e.code, 'code', code);
}

const _shade = 'ActiveDocument.Paragraphs(1).Shading';

void main() {
  for (final selector in [
    'ThisDocument.Paragraphs(2).Shading',
    'ThisDocument.Paragraphs.Item(2).Shading',
    'ActiveDocument.Paragraphs(2).Range.Shading',
    'Application.ActiveDocument.Paragraphs.Item(2).Range.Shading',
    'ActiveDocument.Paragraphs(2).Range.Paragraphs.Item(1).Shading',
  ]) {
    test('selected paragraph background: $selector', () {
      final plan = _compile('$selector.BackgroundPatternColor = RGB(18,52,86)');
      expect(plan.steps.single.tool, 'docx.paragraphShading');
      expect(plan.steps.single.arguments, {'paragraph': 1, 'color': '123456'});
      expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
    });
  }

  for (final (expression, color) in [
    ('0', '000000'),
    ('16777215', 'FFFFFF'),
    ('RGB(255,0,0)', 'FF0000'),
    ('RGB(0,0,255)', '0000FF'),
    ('CLng(CVar(255))', 'FF0000'),
    ('wdColorAutomatic', 'auto'),
    ('-16777216', 'auto'),
  ]) {
    test('packed RGB and automatic: $expression', () {
      expect(
        _compile(
          '$_shade.BackgroundPatternColor = $expression',
        ).steps.single.arguments,
        {'paragraph': 0, 'color': color},
      );
    });
  }

  // Independent published WdColorIndex palette, rather than compiler data.
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
    test('$name and index $index preserve palette identity', () {
      final plan = _compile('''
With $_shade
  .BackgroundPatternColorIndex = $name
  .BackgroundPatternColorIndex = $index
End With
''');
      expect(plan.steps, hasLength(2));
      for (final step in plan.steps) {
        expect(step.arguments, {'paragraph': 0, 'color': color});
      }
    });
  }

  // Exact reference colors from Microsoft's WdColor enum. Test both new
  // background writes and the existing packed-RGB Font.Color path.
  for (final (name, rgb) in <(String, String)>[
    ('wdColorAqua', '33CCCC'),
    ('wdColorBlack', '000000'),
    ('wdColorBlue', '0000FF'),
    ('wdColorBlueGray', '666699'),
    ('wdColorBrightGreen', '00FF00'),
    ('wdColorBrown', '993300'),
    ('wdColorDarkBlue', '000080'),
    ('wdColorDarkGreen', '003300'),
    ('wdColorDarkRed', '800000'),
    ('wdColorDarkTeal', '003366'),
    ('wdColorDarkYellow', '808000'),
    ('wdColorGold', 'FFCC00'),
    ('wdColorGray05', 'F3F3F3'),
    ('wdColorGray10', 'E6E6E6'),
    ('wdColorGray125', 'E0E0E0'),
    ('wdColorGray15', 'D9D9D9'),
    ('wdColorGray20', 'CCCCCC'),
    ('wdColorGray25', 'C0C0C0'),
    ('wdColorGray30', 'B3B3B3'),
    ('wdColorGray35', 'A6A6A6'),
    ('wdColorGray375', 'A0A0A0'),
    ('wdColorGray40', '999999'),
    ('wdColorGray45', '8C8C8C'),
    ('wdColorGray50', '808080'),
    ('wdColorGray55', '737373'),
    ('wdColorGray60', '666666'),
    ('wdColorGray625', '606060'),
    ('wdColorGray65', '595959'),
    ('wdColorGray70', '4C4C4C'),
    ('wdColorGray75', '404040'),
    ('wdColorGray80', '333333'),
    ('wdColorGray85', '262626'),
    ('wdColorGray875', '202020'),
    ('wdColorGray90', '191919'),
    ('wdColorGray95', '0C0C0C'),
    ('wdColorGreen', '008000'),
    ('wdColorIndigo', '333399'),
    ('wdColorLavender', 'CC99FF'),
    ('wdColorLightBlue', '3366FF'),
    ('wdColorLightGreen', 'CCFFCC'),
    ('wdColorLightOrange', 'FF9900'),
    ('wdColorLightTurquoise', 'CCFFFF'),
    ('wdColorLightYellow', 'FFFF99'),
    ('wdColorLime', '99CC00'),
    ('wdColorOliveGreen', '333300'),
    ('wdColorOrange', 'FF6600'),
    ('wdColorPaleBlue', '99CCFF'),
    ('wdColorPink', 'FF00FF'),
    ('wdColorPlum', '993366'),
    ('wdColorRed', 'FF0000'),
    ('wdColorRose', 'FF99CC'),
    ('wdColorSeaGreen', '339966'),
    ('wdColorSkyBlue', '00CCFF'),
    ('wdColorTan', 'FFCC99'),
    ('wdColorTeal', '008080'),
    ('wdColorTurquoise', '00FFFF'),
    ('wdColorViolet', '800080'),
    ('wdColorWhite', 'FFFFFF'),
    ('wdColorYellow', 'FFFF00'),
  ]) {
    test('Word named RGB constant $name', () {
      final plan = _compile('''
$_shade.BackgroundPatternColor = $name
ActiveDocument.Paragraphs(1).Range.Font.Color = $name
''');
      expect(plan.steps.map((s) => s.arguments['color']), [rgb, rgb]);
    });
  }

  test(
    'typed aliases, nested With, named ByVal and rebinding retain targets',
    () {
      final plan = _source('''
Option Explicit
Sub Paint(ByVal target As Shading, Optional ByVal color As Long = 255)
  target.BackgroundPatternColor = color
  Set target = ThisDocument.Paragraphs(3).Shading
  target.BackgroundPatternColorIndex = wdAuto
End Sub
Sub Main()
  Dim item As Paragraph, target As Shading, retained As Shading
  Set item = ActiveDocument.Paragraphs(2)
  With item
    Set target = .Shading
    With .Range.Shading
      .BackgroundPatternColorIndex = wdBlue
    End With
  End With
  Set retained = target
  Set item = ThisDocument.Paragraphs(4)
  Paint target:=target
  retained.BackgroundPatternColor = wdColorTurquoise
End Sub
''');
      expect(plan.steps.map((s) => s.arguments), [
        {'paragraph': 1, 'color': '0000FF'},
        {'paragraph': 1, 'color': 'FF0000'},
        {'paragraph': 2, 'color': 'auto'},
        {'paragraph': 1, 'color': '00FFFF'},
      ]);
    },
  );

  for (final (collection, variant, story) in [
    ('Headers', 1, 'header'),
    ('Headers', 2, 'firstHeader'),
    ('Headers', 3, 'evenHeader'),
    ('Footers', 1, 'footer'),
    ('Footers', 2, 'firstFooter'),
    ('Footers', 3, 'evenFooter'),
  ]) {
    test('shading retains independent $story identity', () {
      final step = _compile('''
ThisDocument.Sections(2).$collection($variant).Range.Paragraphs(3).Shading.BackgroundPatternColorIndex = wdYellow
''').steps.single;
      expect(step.arguments, {
        'paragraph': 2,
        'section': 1,
        'story': story,
        'color': 'FFFF00',
      });
    });
  }

  for (final expression in ['True', '"255"', '0.5', 'Null', 'Empty']) {
    test('reject invalid RGB value $expression', () {
      expect(
        () => _compile('$_shade.BackgroundPatternColor = $expression'),
        throwsA(_error('vba_type_error')),
      );
    });
  }
  for (final expression in ['-1', '16777216']) {
    test('reject unsupported packed RGB color $expression', () {
      expect(
        () => _compile('$_shade.BackgroundPatternColor = $expression'),
        throwsA(_error('vba_unsupported')),
      );
    });
  }
  for (final expression in ['True', '"7"', '0.5', 'Null', 'Empty']) {
    test('reject invalid palette type $expression', () {
      expect(
        () => _compile('$_shade.BackgroundPatternColorIndex = $expression'),
        throwsA(_error('vba_type_error')),
      );
    });
  }
  for (final expression in ['-1', 'wdByAuthor', '17', 'wdColorAutomatic']) {
    test('reject unsupported palette value $expression', () {
      expect(
        () => _compile('$_shade.BackgroundPatternColorIndex = $expression'),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  for (final body in [
    '$_shade.Texture = 0',
    '$_shade.ForegroundPatternColor = 255',
    'Dim value As Long\nvalue = $_shade.BackgroundPatternColor',
    'ActiveDocument.Shading.BackgroundPatternColor = 0',
    'ActiveDocument.Paragraphs(1).Format.Shading.BackgroundPatternColor = 0',
    'ThisDocument.Sections(1).Headers(1).Range.Shading.BackgroundPatternColor = 0',
  ]) {
    test('unsupported member/read is checked even when unreachable: $body', () {
      expect(
        () => _compile('If False Then\n$body\nEnd If'),
        throwsA(_error('vba_unsupported')),
      );
    });
  }
  for (final body in [
    'Dim target As Shading\nSet target = ActiveDocument.Paragraphs(1).Range.Font',
    'Dim target As Shading, value As Variant\nSet target = value',
    '$_shade.BackgroundPatternColor = True',
    'ActiveDocument.Paragraphs(1).Shading(1).BackgroundPatternColor = 0',
  ]) {
    test('bad binding/type is checked in an unused helper: $body', () {
      expect(
        () => _source('Sub NeverUsed()\n$body\nEnd Sub\nSub Main()\nEnd Sub'),
        throwsA(_error()),
      );
    });
  }

  for (final name in ['Shading', 'wdColorAutomatic', 'wdColorRed']) {
    test('new Word names cannot be shadowed: $name', () {
      expect(
        () => _compile('Dim $name As Long'),
        throwsA(_error('vba_name_error')),
      );
    });
  }
  test('custom spacing pair cannot be split by a shading write', () {
    expect(
      () => _compile('''
ActiveDocument.Paragraphs(1).Format.LineSpacingRule = wdLineSpaceExactly
$_shade.BackgroundPatternColorIndex = wdYellow
ActiveDocument.Paragraphs(1).Format.LineSpacing = 18
'''),
      throwsA(_error('vba_unsupported')),
    );
  });
}
