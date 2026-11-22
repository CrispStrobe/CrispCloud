import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'CellParagraphs',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

const _cellRange = 'ActiveDocument.Tables(2).Cell(3, 4).Range';
const _paragraph = '$_cellRange.Paragraphs(1)';

Map<String, Object?> _cell(
  Map<String, Object?> fields, {
  int table = 1,
  int row = 2,
  int column = 3,
}) => {
  'paragraph': 0,
  'story': 'tableCell',
  'table': table,
  'row': row,
  'column': column,
  ...fields,
};

Matcher _error(String code) => isA<OfficeVbaCompileException>()
    .having((error) => error.moduleName, 'module', 'CellParagraphs')
    .having((error) => error.entryPoint, 'entry', 'Main')
    .having((error) => error.line, 'line', greaterThan(0))
    .having((error) => error.column, 'column', greaterThan(0))
    .having((error) => error.code, 'code', code);

void main() {
  group('existing cell paragraph selection', () {
    for (final document in [
      'ThisDocument',
      'ActiveDocument',
      'Application.ActiveDocument',
    ]) {
      for (final item in ['', '.Item']) {
        test('$document / Paragraphs$item retains explicit coordinates', () {
          final target =
              '$document.Tables.Item(2).Cell(3, 4).Range'
              '.Paragraphs$item(1)';
          final plan = _compile('''
$target.Style = wdStyleHeading2
$target.Shading.BackgroundPatternColor = RGB(18, 52, 86)
$target.Range.Font.Bold = True
''');
          expect(plan.steps.map((step) => step.tool), [
            'docx.paragraphStyle',
            'docx.paragraphShading',
            'docx.runFormat',
          ]);
          expect(plan.steps.map((step) => step.arguments), [
            _cell({'builtin': -3}),
            _cell({'color': '123456'}),
            _cell({'bold': true}),
          ]);
          expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
        });
      }
    }

    test('nested With retains cell identity through repeated Paragraphs', () {
      final plan = _compile('''
With ActiveDocument.Tables(2).Cell(3, 4)
  With .Range
    .Text = "Ready"
    With .Paragraphs.Item(1)
      .Style = "Report Total"
      With .Range.Paragraphs(1).Range
        .Style = wdStyleNormal
        .Shading.BackgroundPatternColorIndex = wdYellow
        .Font.Italic = True
        .NoProofing = False
      End With
    End With
  End With
End With
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'table': 1, 'row': 2, 'column': 3, 'text': 'Ready'},
        _cell({'name': 'Report Total'}),
        _cell({'builtin': -1}),
        _cell({'color': 'FFFF00'}),
        _cell({'italic': true}),
        _cell({'noProof': false}),
      ]);
    });

    test('Paragraph, Range, Shading and Format aliases survive rebinding', () {
      final plan = _compile('''
Dim selected As Cell, p As Paragraph, saved As Paragraph
Dim target As Range, background As Shading, layout As ParagraphFormat
Set selected = ActiveDocument.Tables(2).Cell(3, 4)
Set p = selected.Range.Paragraphs(1)
Set saved = p
Set target = p.Range
Set background = p.Shading
Set layout = p.Format
Set selected = ActiveDocument.Tables(1).Cell(1, 2)
Set p = selected.Range.Paragraphs(1)
saved.Style = wdStyleCaption
target.Style = "Report Total"
background.BackgroundPatternColorIndex = wdAuto
layout.SpaceAfter = 6
p.Style = wdStyleNormal
''');
      expect(plan.steps.map((step) => step.arguments), [
        _cell({'builtin': -35}),
        _cell({'name': 'Report Total'}),
        _cell({'color': 'auto'}),
        _cell({'after': 6}),
        _cell({'builtin': -1}, table: 0, row: 0, column: 1),
      ]);
    });

    test(
      'named ByVal helpers retain caller selector after local rebinding',
      () {
        final plan = _source('''
Sub Paint(ByVal background As Shading)
  background.BackgroundPatternColorIndex = wdBrightGreen
  Set background = ActiveDocument.Paragraphs(2).Shading
  background.BackgroundPatternColor = wdColorAutomatic
End Sub
Sub FormatParagraph(ByVal p As Paragraph, Optional ByVal label As String = "Report Total")
  p.Style = label
  Paint background:=p.Shading
  Set p = ActiveDocument.Tables(1).Cell(1, 2).Range.Paragraphs(1)
  p.Range.Font.Bold = True
End Sub
Sub SelectParagraph(ByVal target As Range)
  FormatParagraph p:=target.Paragraphs.Item(1)
End Sub
Sub Main()
  Dim p As Paragraph
  Set p = $_paragraph
  SelectParagraph target:=$_cellRange
  p.Style = wdStyleNormal
End Sub
''');
        expect(plan.steps.map((step) => step.arguments), [
          _cell({'name': 'Report Total'}),
          _cell({'color': '00FF00'}),
          {'paragraph': 1, 'color': 'auto'},
          _cell({'bold': true}, table: 0, row: 0, column: 1),
          _cell({'builtin': -1}),
        ]);
      },
    );

    test('one helper formats body, independent footer and cell paragraphs', () {
      final plan = _source('''
Sub FormatParagraph(ByVal p As Paragraph)
  p.Range.Style = wdStyleNormal
  p.Range.Shading.BackgroundPatternColorIndex = wdAuto
End Sub
Sub Main()
  FormatParagraph ActiveDocument.Paragraphs(2)
  FormatParagraph ActiveDocument.Sections(3).Footers(1).Range.Paragraphs(2)
  FormatParagraph $_paragraph
End Sub
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 1, 'builtin': -1},
        {'paragraph': 1, 'color': 'auto'},
        {'paragraph': 1, 'story': 'footer', 'section': 2, 'builtin': -1},
        {'paragraph': 1, 'story': 'footer', 'section': 2, 'color': 'auto'},
        _cell({'builtin': -1}),
        _cell({'color': 'auto'}),
      ]);
    });

    test('native formatting identity matches direct cell formatting', () {
      final plan = _compile('''
$_cellRange.ParagraphFormat.LineSpacingRule = wdLineSpaceExactly
$_paragraph.Format.LineSpacing = 18
$_paragraph.Range.ParagraphFormat.LineSpacingRule = wdLineSpaceAtLeast
$_cellRange.ParagraphFormat.LineSpacing = 12
$_paragraph.TabStops.Add Position:=12, Alignment:=wdAlignTabRight, Leader:=wdTabLeaderDots
$_paragraph.OpenUp
''');
      expect(plan.steps.map((step) => step.arguments), [
        _cell({'rule': 'exact', 'points': 18}),
        _cell({'rule': 'atLeast', 'points': 12}),
        _cell({'position': 12, 'alignment': 'right', 'leader': 'dot'}),
        _cell({'action': 'open'}),
      ]);
    });

    test('supported cell paragraph syntax is checked in inactive code', () {
      expect(
        _compile('''
If False Then
  $_paragraph.Style = wdStyleHeading1
  $_paragraph.Shading.BackgroundPatternColorIndex = wdYellow
  $_paragraph.Range.Font.Bold = True
End If
''').steps,
        isEmpty,
      );
    });
  });

  group('cell paragraph boundaries', () {
    for (final member in [
      'InsertAfter "x"',
      'ListFormat.ApplyBulletDefault',
      'ListFormat.ListLevelNumber = 1',
    ]) {
      for (final (binding, target) in [
        ('', '$_paragraph.Range'),
        ('Dim p As Paragraph\nSet p = $_paragraph\n', 'p.Range'),
        (
          'Dim p As Paragraph, retained As Range\nSet p = $_paragraph\nSet retained = p.Range\n',
          'retained',
        ),
      ]) {
        test('known $target refuses inactive $member', () {
          expect(
            () => _compile('${binding}If False Then\n$target.$member\nEnd If'),
            throwsA(_error('vba_unsupported')),
          );
        });
      }
      test('nested With refuses inactive $member', () {
        expect(
          () => _compile('''
With $_cellRange
  With .Paragraphs.Item(1)
    With .Range
      If False Then
        .$member
      End If
    End With
  End With
End With
'''),
          throwsA(_error('vba_unsupported')),
        );
      });
    }

    test('generic parameter can insert in body before rebinding to a cell', () {
      final plan = _source('''
Sub Prepare(ByVal target As Range)
  target.InsertBefore "Prefix: "
  Set target = $_paragraph.Range
  target.Style = wdStyleNormal
End Sub
Sub Main()
  Prepare ActiveDocument.Paragraphs(2).Range
End Sub
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 1, 'start': 0, 'end': 0, 'text': 'Prefix: '},
        _cell({'builtin': -1}),
      ]);
    });

    test('mixed local origins are checked against their actual selector', () {
      final plan = _compile('''
Dim target As Range
Set target = $_paragraph.Range
target.Style = wdStyleNormal
Set target = ActiveDocument.Paragraphs(2).Range
target.InsertBefore "Prefix: "
''');
      expect(plan.steps.map((step) => step.arguments), [
        _cell({'builtin': -1}),
        {'paragraph': 1, 'start': 0, 'end': 0, 'text': 'Prefix: '},
      ]);
    });

    test(
      'cyclic cell aliases retain static and active list-operation guards',
      () {
        const bindings =
            '''
Dim original As Range, retained As Range
Set original = $_paragraph.Range
Set retained = original
Set original = retained
''';
        expect(
          () => _compile(
            '${bindings}If False Then\noriginal.ListFormat.ApplyBulletDefault\nEnd If',
          ),
          throwsA(_error('vba_unsupported')),
        );
        expect(
          () => _compile('${bindings}original.ListFormat.ApplyBulletDefault'),
          throwsA(_error('vba_unsupported')),
        );
      },
    );

    for (final index in ['0', '-1', '1.5', 'True', '"1"', 'Empty', 'Null']) {
      for (final item in ['', '.Item']) {
        test('Paragraphs$item rejects invalid index $index', () {
          expect(
            () => _compile(
              '$_cellRange.Paragraphs$item($index).Style = wdStyleNormal',
            ),
            throwsA(_error('vba_type_error')),
          );
        });
      }
    }
    for (final suffix in [
      'Paragraphs(2)',
      'Paragraphs.Item(2)',
      'Paragraphs(1).Range.Paragraphs(2)',
      'Paragraphs(2147483648)',
    ]) {
      test('does not select another paragraph through $suffix', () {
        expect(
          () => _compile('$_cellRange.$suffix.Style = wdStyleNormal'),
          throwsA(_error('vba_unsupported')),
        );
      });
    }

    for (final member in [
      'InsertAfter "x"',
      'ListFormat.ApplyBulletDefault',
      'ListFormat.ListLevelNumber = 1',
      'Text = "replacement"',
      'Duplicate.Font.Bold = True',
    ]) {
      test(
        'projected Range refuses $member without losing its cell identity',
        () {
          expect(
            () => _compile('$_paragraph.Range.$member'),
            throwsA(_error('vba_unsupported')),
          );
          expect(
            () => _source('''
Sub TryWrite(ByVal target As Range)
  target.$member
End Sub
Sub Main()
  TryWrite $_paragraph.Range
End Sub
'''),
            throwsA(_error('vba_unsupported')),
          );
        },
      );
    }

    for (final statement in [
      '$_cellRange.Style = wdStyleNormal',
      '$_cellRange.Shading.BackgroundPatternColorIndex = wdYellow',
      'Dim value As Variant\nvalue = $_paragraph.Style',
      'Dim value As Variant\nvalue = $_paragraph.Range.Text',
      'Dim value As Variant\nvalue = $_cellRange.Paragraphs.Count',
      '$_paragraph.Shading.Texture = 0',
      '$_paragraph.Shading.ForegroundPatternColor = wdColorRed',
    ]) {
      test('existing unrelated-member refusal remains: $statement', () {
        expect(() => _compile(statement), throwsA(_error('vba_unsupported')));
      });
    }

    for (final statement in [
      '$_paragraph.Style = True',
      '$_paragraph.Style = ""',
      '$_paragraph.Shading.BackgroundPatternColorIndex = True',
      '$_paragraph.Shading.BackgroundPatternColor = 1.5',
    ]) {
      test('strict style/color types remain: $statement', () {
        expect(() => _compile(statement), throwsA(_error('vba_type_error')));
      });
    }

    for (final statement in [
      '$_paragraph.Style = 1',
      '$_paragraph.Shading.BackgroundPatternColorIndex = wdByAuthor',
      '$_paragraph.Shading.BackgroundPatternColor = -1',
      '$_paragraph.Style = wdStyleNormal',
      '$_paragraph.Shading.BackgroundPatternColorIndex = wdAuto',
    ]) {
      test('pending custom spacing rejects unrelated mutation: $statement', () {
        expect(
          () => _compile('''
$_cellRange.ParagraphFormat.LineSpacingRule = wdLineSpaceExactly
$statement
$_paragraph.Format.LineSpacing = 18
'''),
          throwsA(_error('vba_unsupported')),
        );
      });
    }
  });
}
