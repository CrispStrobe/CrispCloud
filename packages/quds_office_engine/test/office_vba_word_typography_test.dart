import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String body, {String declarations = ''}) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'Typography',
        source:
            '''
Option Explicit
Sub Main()
$declarations
$body
End Sub
''',
      ),
    );

void _reject(String body, String code, {String declarations = ''}) {
  expect(
    () => _compile(body, declarations: declarations),
    throwsA(
      isA<OfficeVbaCompileException>()
          .having((error) => error.code, 'code', code)
          .having((error) => error.moduleName, 'module', 'Typography')
          .having((error) => error.line, 'line', greaterThan(0))
          .having((error) => error.column, 'column', greaterThan(0)),
    ),
  );
}

void main() {
  for (final selector in <String>[
    'ThisDocument.Paragraphs(2)',
    'ThisDocument.Paragraphs.Item(2)',
    'ActiveDocument.Paragraphs(2)',
    'ActiveDocument.Paragraphs.Item(2)',
    'Application.ActiveDocument.Paragraphs(2)',
    'Application.ActiveDocument.Paragraphs.Item(2)',
  ]) {
    test('$selector uses the explicit session paragraph', () {
      final plan = _compile('$selector.Range.Font.SmallCaps = True');
      expect(plan.steps.single.tool, 'docx.runFormat');
      expect(plan.steps.single.arguments, <String, Object?>{
        'paragraph': 1,
        'smallCaps': true,
      });
    });
  }

  test(
    'application/paragraph collection With bindings retain one-based items',
    () {
      final plan = _compile('''
With Application
  Set doc = .ActiveDocument
End With
With doc.Paragraphs
  Set target = .Item(3).Range
End With
target.Font.Superscript = True
''', declarations: 'Dim doc As Document\nDim target As Range');
      expect(plan.steps.single.arguments, <String, Object?>{
        'paragraph': 2,
        'superscript': true,
      });
    },
  );

  test('typography assignments retain their ordered Boolean intent', () {
    final plan = _compile('''
With ActiveDocument.Paragraphs.Item(1).Range.Font
  .SmallCaps = True
  .SmallCaps = False
  .Superscript = True
  .Superscript = False
  .Subscript = True
  .Subscript = False
End With
''');
    expect(plan.steps.map((step) => step.tool), everyElement('docx.runFormat'));
    expect(plan.steps.map((step) => step.arguments), <Object?>[
      {'paragraph': 0, 'smallCaps': true},
      {'paragraph': 0, 'smallCaps': false},
      {'paragraph': 0, 'superscript': true},
      {'paragraph': 0, 'superscript': false},
      {'paragraph': 0, 'subscript': true},
      {'paragraph': 0, 'subscript': false},
    ]);
  });

  // Independent fixed WdColorIndex expectations from the Microsoft enum and
  // native ST_HighlightColor palette, rather than compiler implementation data.
  for (final (name, index, rgb) in <(String, int, String?)>[
    ('wdNoHighlight', 0, null),
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
    test('$name and numeric $index publish exact highlight $rgb', () {
      final plan = _compile('''
With Application.ActiveDocument.Paragraphs.Item(1).Range
  .HighlightColorIndex = $name
  .HighlightColorIndex = $index
End With
''');
      expect(plan.steps, hasLength(2));
      for (final step in plan.steps) {
        expect(step.tool, 'docx.runFormat');
        expect(step.arguments, {'paragraph': 0, 'highlight': rgb});
      }
    });
  }

  test('wdAuto is the numeric alias of wdNoHighlight for a Range', () {
    final plan = _compile(
      'ActiveDocument.Paragraphs(1).Range.HighlightColorIndex = wdAuto',
    );
    expect(plan.steps.single.arguments, {'paragraph': 0, 'highlight': null});
  });

  for (final (body, code) in <(String, String)>[
    (
      'ActiveDocument.Paragraphs(1).Range.Font.SmallCaps = -1',
      'vba_type_error',
    ),
    (
      'ActiveDocument.Paragraphs(1).Range.Font.Superscript = "True"',
      'vba_type_error',
    ),
    (
      'ActiveDocument.Paragraphs(1).Range.Font.Subscript = 9999998',
      'vba_type_error',
    ),
    (
      'ActiveDocument.Paragraphs(1).Range.HighlightColorIndex = True',
      'vba_type_error',
    ),
    (
      'ActiveDocument.Paragraphs(1).Range.HighlightColorIndex = 1.5',
      'vba_type_error',
    ),
    (
      'ActiveDocument.Paragraphs(1).Range.HighlightColorIndex = wdByAuthor',
      'vba_unsupported',
    ),
    (
      'ActiveDocument.Paragraphs(1).Range.HighlightColorIndex = 17',
      'vba_unsupported',
    ),
    (
      'Application.ActiveDocument.Paragraphs.Item(0).Range.Font.SmallCaps = True',
      'vba_type_error',
    ),
    (
      'Application.ActiveDocument.Paragraphs.Item("1").Range.Font.SmallCaps = True',
      'vba_type_error',
    ),
    (
      'Application.ActiveDocument.Paragraphs.Item(1, 2).Range.Font.SmallCaps = True',
      'vba_type_error',
    ),
    (
      'Application.Paragraphs(1).Range.Font.SmallCaps = True',
      'vba_unsupported',
    ),
    (
      'ActiveDocument.Paragraphs(1).Range.Font.AllCaps = True',
      'vba_unsupported',
    ),
  ]) {
    test(
      'reject unsupported typography or selector: $body',
      () => _reject(body, code),
    );
  }

  for (final body in <String>[
    'value = ActiveDocument.Paragraphs.Count',
    'value = Application.ActiveDocument.Paragraphs.Item(1).Range.Font.SmallCaps',
    'value = ActiveDocument.Paragraphs(1).Range.HighlightColorIndex',
    'value = Application.ActiveDocument.Name',
    'Application.Documents.Open "other.docx"',
  ]) {
    test('unsupported document reads stay rejected in unused code: $body', () {
      _reject(
        'If False Then\n$body\nEnd If',
        'vba_unsupported',
        declarations: 'Dim value As Variant',
      );
    });
  }

  test('new Boolean type checking also applies to unused code', () {
    _reject(
      'If False Then\nActiveDocument.Paragraphs(1).Range.Font.Subscript = 1\nEnd If',
      'vba_type_error',
    );
  });

  for (final name in <String>[
    'Application',
    'ActiveDocument',
    'wdGreen',
    'wdNoHighlight',
  ]) {
    test('session and color names cannot be shadowed: $name', () {
      _reject('', 'vba_name_error', declarations: 'Dim $name As Long');
    });
  }
}
