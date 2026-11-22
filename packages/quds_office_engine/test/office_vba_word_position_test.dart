import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

const _font = 'ActiveDocument.Paragraphs(1).Range.Font';

OfficeMacro _source(String source) =>
    const OfficeVbaWordMacroLanguage().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordFontPosition',
        source: source,
      ),
    );

OfficeMacro _body(String body) => _source('Sub Main()\n$body\nEnd Sub\n');

void _reject(String body, {String code = 'vba_type_error'}) => expect(
  () => _body(body),
  throwsA(
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'WordFontPosition')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0)),
  ),
);

void main() {
  test('Position uses signed whole points and retains write order', () {
    final plan = _body('''
With $_font
  .Position = 3
  .Position = -2
  .Position = 0
  .Size = 12
End With
''');
    expect(plan.steps.map((step) => step.tool), everyElement('docx.runFormat'));
    expect(plan.steps.map((step) => step.arguments), <Map<String, Object?>>[
      {'paragraph': 0, 'position': 3},
      {'paragraph': 0, 'position': -2},
      {'paragraph': 0, 'position': 0},
      {'paragraph': 0, 'size': 12},
    ]);
  });

  test('aliases, nested With and named ByVal retain the original Font', () {
    final plan = _source('''
Option Explicit
Sub Move(ByVal target As Font, Optional ByVal points As Long = 2)
  target.Position = points
  Set target = ThisDocument.Paragraphs(3).Range.Font
  target.Position = -1
End Sub
Sub Main()
  Dim target As Font
  Set target = Application.ActiveDocument.Paragraphs.Item(2).Range.Font
  Move target:=target, points:=3
  With target
    .pOsItIoN = 0
  End With
  With ActiveDocument
    With .Paragraphs.Item(1)
      With .Range.Font
        .Position = 1
      End With
    End With
  End With
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), <Map<String, Object?>>[
      {'paragraph': 1, 'position': 3},
      {'paragraph': 2, 'position': -1},
      {'paragraph': 1, 'position': 0},
      {'paragraph': 0, 'position': 1},
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
    test('preserves explicit $story section and paragraph identity', () {
      final plan = _body('''
With ThisDocument.Sections.Item(2).$collection.Item($index)
  .Range.Paragraphs.Item(3).Range.Font.Position = -4
End With
''');
      expect(plan.steps.single.arguments, {
        'paragraph': 2,
        'story': story,
        'section': 1,
        'position': -4,
      });
    });
  }

  for (final value in ['-1584', '-1', '0', '1', '1584', '2.0', '6 / 2']) {
    test('accepts exact integral source point value $value', () {
      final plan = _body('$_font.Position = $value');
      expect(plan.steps.single.arguments['position'], isA<int>());
    });
  }

  test('source-known typed arrays, scalar functions and Variants compose', () {
    final plan = _source('''
Function Shift(ByVal n As Long) As Long
  Shift = n - 2
End Function
Sub Main()
  Dim values(1 To 3) As Long, i As Long, result As Variant
  values(1) = -1
  values(2) = 0
  values(3) = 3
  For i = 1 To 3
    result = Shift(values(i))
    ActiveDocument.Paragraphs(i).Range.Font.Position = result
  Next i
End Sub
''');
    expect(plan.steps.map((step) => step.arguments['position']), [-3, -2, 1]);
  });

  for (final value in [
    '-1585',
    '1585',
    '-0.5',
    '0.5',
    '1.25',
    'True',
    'False',
    '"2"',
    'Null',
    'Empty',
  ]) {
    test('refuses $value without returning a partially emitted plan', () {
      _reject('$_font.Bold = True\n$_font.Position = $value');
    });
  }

  for (final body in [
    'ActiveDocument.Paragraphs(1).Position = 1',
    'ActiveDocument.Paragraphs(1).Range.Position = 1',
    'ActiveDocument.Paragraphs(1).Format.Position = 1',
    'Dim value As Variant\nvalue = $_font.Position',
    '$_font.Position(1) = 1',
  ]) {
    test('unsupported receiver/read is checked even in dead code: $body', () {
      _reject('If False Then\n$body\nEnd If', code: 'vba_unsupported');
    });
  }

  test('unbound Font aliases do not gain an implicit selection', () {
    _reject('Dim target As Font\ntarget.Position = 1', code: 'vba_unsupported');
  });

  test('Excel and PowerPoint adapters do not acquire Word Position', () {
    for (final (language, format, receiver) in [
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
      expect(
        () => OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: language,
            format: format,
            source: 'Sub Main()\n$receiver.Position = 1\nEnd Sub',
          ),
        ),
        throwsA(isA<OfficeVbaCompileException>()),
      );
    }
  });
}
