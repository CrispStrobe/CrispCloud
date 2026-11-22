import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

const _paragraph = 'ActiveDocument.Paragraphs(1)';
const _range = '$_paragraph.Range';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordStyles',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('''
Option Explicit
Sub Main()
$body
End Sub
''');

Matcher _error(String code) => isA<OfficeVbaCompileException>()
    .having((error) => error.code, 'code', code)
    .having((error) => error.moduleName, 'module', 'WordStyles')
    .having((error) => error.line, 'line', greaterThan(0))
    .having((error) => error.column, 'column', greaterThan(0));

void _reject(String body, String code) =>
    expect(() => _compile(body), throwsA(_error(code)));

// Specification-derived expectations, independent of the compiler's table.
// https://learn.microsoft.com/en-us/office/vba/api/word.wdbuiltinstyle
// These cases qualify this bounded source subset, not an installed Word host.
const _builtins = <(String, int)>[
  ('wdStyleNormal', -1),
  ('wdStyleHeading1', -2),
  ('wdStyleHeading2', -3),
  ('wdStyleHeading3', -4),
  ('wdStyleHeading4', -5),
  ('wdStyleHeading5', -6),
  ('wdStyleHeading6', -7),
  ('wdStyleHeading7', -8),
  ('wdStyleHeading8', -9),
  ('wdStyleHeading9', -10),
  ('wdStyleCaption', -35),
  ('wdStyleTitle', -63),
  ('wdStyleSubtitle', -75),
];

void main() {
  for (final (constant, number) in _builtins) {
    test('$constant selects its documented built-in without resolving it', () {
      for (final expression in [
        constant,
        constant.toUpperCase(),
        '$number',
        '$number.0',
      ]) {
        for (final target in [_paragraph, _range]) {
          final macro = _compile('$target.Style = $expression');
          expect(macro.steps.single.tool, 'docx.paragraphStyle');
          expect(macro.steps.single.arguments, {
            'paragraph': 0,
            'builtin': number,
          });
          expect(OfficeMacro.parse(macro.encode()).toJson(), macro.toJson());
        }
      }
    });
  }

  for (final name in [
    'Report Body',
    'heading 1',
    'عنوان التقرير',
    'Résumé & notes <final>',
    'Report 😀',
    '-2',
    '  Authored name  ',
  ]) {
    test('style name preserves the authored String $name', () {
      final macro = _compile('$_range.Style = "$name"');
      expect(macro.steps.single.arguments, {'paragraph': 0, 'name': name});
    });
  }

  test('String expressions and numeric Variant values remain separate', () {
    final macro = _compile('''
Dim chosenStyle As Variant
Dim names(1 To 2) As String
names(1) = "Report"
names(2) = " Body"
chosenStyle = names(1) & names(2)
$_paragraph.Style = chosenStyle
chosenStyle = wdStyleTitle
$_range.Style = chosenStyle
''');
    expect(macro.steps.map((step) => step.arguments), [
      {'paragraph': 0, 'name': 'Report Body'},
      {'paragraph': 0, 'builtin': -63},
    ]);
  });

  test(
    'typed aliases and named ByVal helpers retain their selected target',
    () {
      final macro = _source('''
Option Explicit
Sub Configure(ByVal para As Paragraph, ByVal target As Range, Optional ByVal name As String = "Report Body")
  para.Style = name
  target.Style = wdStyleSubtitle
  Set para = ActiveDocument.Paragraphs(3)
  Set target = ActiveDocument.Paragraphs(4).Range
  para.Style = wdStyleHeading2
  target.Style = wdStyleCaption
End Sub
Sub Main()
  Dim p As Paragraph
  Dim r As Range
  Set p = ThisDocument.Paragraphs.Item(1)
  Set r = Application.ActiveDocument.Paragraphs.Item(2).Range
  Configure target:=r, para:=p
  p.Style = wdStyleNormal
  r.Style = "Body final"
End Sub
''');
      expect(macro.steps.map((step) => step.arguments), [
        {'paragraph': 0, 'name': 'Report Body'},
        {'paragraph': 1, 'builtin': -75},
        {'paragraph': 2, 'builtin': -3},
        {'paragraph': 3, 'builtin': -35},
        {'paragraph': 0, 'builtin': -1},
        {'paragraph': 1, 'name': 'Body final'},
      ]);
    },
  );

  test('nested With and repeated style assignments retain operation order', () {
    final macro = _compile('''
With $_paragraph
  .Style = wdStyleHeading1
  With .Range
    .Font.Bold = True
    .Style = "Report Body"
    .ParagraphFormat.SpaceAfter = 6
  End With
  .Style = wdStyleNormal
End With
''');
    expect(macro.steps.map((step) => step.tool), [
      'docx.paragraphStyle',
      'docx.runFormat',
      'docx.paragraphStyle',
      'docx.paragraphFormat',
      'docx.paragraphStyle',
    ]);
    expect(macro.steps.map((step) => step.arguments), [
      {'paragraph': 0, 'builtin': -2},
      {'paragraph': 0, 'bold': true},
      {'paragraph': 0, 'name': 'Report Body'},
      {'paragraph': 0, 'after': 6},
      {'paragraph': 0, 'builtin': -1},
    ]);
  });

  for (final (collection, index, story) in [
    ('Headers', 'wdHeaderFooterPrimary', 'header'),
    ('Headers', 'wdHeaderFooterFirstPage', 'firstHeader'),
    ('Headers', 'wdHeaderFooterEvenPages', 'evenHeader'),
    ('Footers', 'wdHeaderFooterPrimary', 'footer'),
    ('Footers', 'wdHeaderFooterFirstPage', 'firstFooter'),
    ('Footers', 'wdHeaderFooterEvenPages', 'evenFooter'),
  ]) {
    test('$story style preserves the complete section/paragraph selector', () {
      final macro = _compile('''
With ThisDocument.Sections.Item(2).$collection.Item($index).Range.Paragraphs.Item(3)
  .Style = "Report Body"
  .Range.Style = wdStyleCaption
End With
''');
      expect(macro.steps.map((step) => step.arguments), [
        {'paragraph': 2, 'section': 1, 'story': story, 'name': 'Report Body'},
        {'paragraph': 2, 'section': 1, 'story': story, 'builtin': -35},
      ]);
    });
  }

  test('Range.Paragraphs(1) retains the original paragraph identity', () {
    final macro = _compile('''
ActiveDocument.Paragraphs(4).Range.Paragraphs.Item(1).Style = wdStyleHeading3
''');
    expect(macro.steps.single.arguments, {'paragraph': 3, 'builtin': -4});
    _reject('$_range.Paragraphs(2).Style = wdStyleNormal', 'vba_unsupported');
  });

  for (final expression in [
    '0',
    '1',
    '2',
    '-11',
    '-66',
    '-181',
    '-2147483648',
  ]) {
    test(
      'unsupported numeric style value $expression is not a collection index',
      () {
        _reject('$_paragraph.Style = $expression', 'vba_unsupported');
      },
    );
  }

  for (final expression in [
    'True',
    'False',
    'Null',
    'Empty',
    '-1.5',
    '""',
    '"Name\tSuffix"',
    '"Name\u0001Suffix"',
    '"Name\u000BSuffix"',
    '"Name\uFFFESuffix"',
    '"Name\uFFFFSuffix"',
  ]) {
    test('invalid style expression ${expression.codeUnits} is refused', () {
      _reject('$_range.Style = $expression', 'vba_type_error');
    });
  }

  test('an isolated UTF-16 surrogate cannot reach a native style name', () {
    final surrogate = String.fromCharCode(0xd800);
    _reject('$_range.Style = "Bad $surrogate"', 'vba_type_error');
  });

  for (final expression in ['True', 'Null', 'Empty']) {
    test(
      'a Variant still requires an actual name or numeric constant: $expression',
      () {
        _reject('''
Dim name As Variant
name = $expression
$_paragraph.Style = name
''', 'vba_type_error');
      },
    );
  }

  for (final expression in [
    'True',
    _paragraph,
    _range,
    '$_range.Font',
    '$_paragraph.Format',
    'ThisDocument.Sections(1).PageSetup.TextColumns',
  ]) {
    test('invalid style type is checked in dead code: $expression', () {
      _reject('''
If False Then
  $_paragraph.Style = $expression
End If
''', 'vba_type_error');
    });
    test('invalid style type is checked in an unused helper: $expression', () {
      expect(
        () => _source('''
Sub Unused()
  $_range.Style = $expression
End Sub
Sub Main()
End Sub
'''),
        throwsA(_error('vba_type_error')),
      );
    });
  }

  test('whole arrays do not become style values in an unused helper', () {
    expect(
      () => _source('''
Sub Unused()
  Dim names(1 To 2) As String
  $_paragraph.Style = names
End Sub
Sub Main()
End Sub
'''),
      throwsA(_error('vba_type_error')),
    );
  });

  for (final target in [_paragraph, _range]) {
    test('$target.Style stays write-only even in an unused helper', () {
      expect(
        () => _source('''
Sub Unused()
  Dim name As Variant
  name = $target.Style
End Sub
Sub Main()
End Sub
'''),
        throwsA(_error('vba_unsupported')),
      );
    });
    test('$target.Style cannot interrupt a custom line-spacing pair', () {
      _reject('''
$_paragraph.Format.LineSpacingRule = wdLineSpaceExactly
$target.Style = wdStyleNormal
$_paragraph.Format.LineSpacing = 12
''', 'vba_unsupported');
    });
  }

  for (final target in [
    'ThisDocument',
    'ThisDocument.Paragraphs',
    '$_paragraph.Format',
    '$_range.Font',
    'ThisDocument.Sections(1).Headers(1).Range',
  ]) {
    test('$target is not a supported style assignment target', () {
      _reject('$target.Style = wdStyleNormal', 'vba_unsupported');
    });
  }

  test('a typed Range alias cannot turn a whole story into a paragraph', () {
    _reject('''
Dim story As Range
Set story = ThisDocument.Sections(1).Headers(1).Range
story.Style = wdStyleNormal
''', 'vba_unsupported');
  });

  test('style property assignment is not an object Set operation', () {
    _reject('Set $_paragraph.Style = wdStyleNormal', 'vba_unsupported');
  });

  test('an unbound Paragraph or Range cannot be styled', () {
    for (final type in ['Paragraph', 'Range']) {
      _reject(
        'Dim target As $type\ntarget.Style = wdStyleNormal',
        'vba_unsupported',
      );
    }
  });

  test('style selectors retain the shared operation budget', () {
    _reject('''
Dim i As Long
For i = 1 To 10001
  $_paragraph.Style = wdStyleNormal
Next i
''', 'vba_limit_exceeded');
  });

  test('Word style constants remain unavailable to other Office dialects', () {
    for (final (language, format) in [
      ('vba-excel', OfficeMacroFormat.xlsx),
      ('vba-powerpoint', OfficeMacroFormat.pptx),
    ]) {
      expect(
        () => OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: language,
            format: format,
            source:
                'Sub Main()\nDim name As Long\nname = wdStyleNormal\nEnd Sub',
          ),
        ),
        throwsA(isA<OfficeVbaCompileException>()),
      );
    }
  });

  test('the complete BAS example retains its five intended operations', () {
    final macro = _source(
      File('example/macros/word_styles.bas').readAsStringSync(),
    );
    expect(macro.steps.map((step) => step.tool), [
      'docx.runFormat',
      'docx.paragraphStyle',
      'docx.paragraphStyle',
      'docx.paragraphStyle',
      'docx.runFormat',
    ]);
    expect(macro.steps.map((step) => step.arguments), [
      {'paragraph': 0, 'bold': true},
      {'paragraph': 0, 'builtin': -2},
      {'paragraph': 1, 'name': 'Report Body'},
      {'paragraph': 2, 'builtin': -35},
      {'paragraph': 2, 'italic': true},
    ]);
  });
}
