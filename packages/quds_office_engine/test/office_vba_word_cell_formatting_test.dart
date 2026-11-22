import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordCellFormatting',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Matcher _error([String? code]) {
  final result = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'WordCellFormatting')
      .having((error) => error.entryPoint, 'entry', 'Main')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? result
      : result.having((error) => error.code, 'code', code);
}

const _range = 'ActiveDocument.Tables(2).Cell(3, 4).Range';

Map<String, Object?> _cell(
  int table,
  int row,
  int column,
  Map<String, Object?> fields,
) => {
  'paragraph': 0,
  'story': 'tableCell',
  'table': table,
  'row': row,
  'column': column,
  ...fields,
};

void main() {
  group('explicit table cell formatting selectors', () {
    for (final document in [
      'ThisDocument',
      'ActiveDocument',
      'Application.ActiveDocument',
    ]) {
      for (final item in ['', '.Item']) {
        test('$document.Tables$item retains all three coordinates', () {
          final plan = _compile('''
$document.Tables$item(2).Cell(3, 4).Range.Font.Bold = True
$document.Tables$item(2).Cell(3, 4).Range.ParagraphFormat.Alignment = wdAlignParagraphRight
''');
          expect(plan.steps.map((step) => step.tool), [
            'docx.runFormat',
            'docx.paragraphFormat',
          ]);
          expect(plan.steps.map((step) => step.arguments), [
            _cell(1, 2, 3, {'bold': true}),
            _cell(1, 2, 3, {'alignment': 'right'}),
          ]);
          expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
        });
      }
    }

    test('text and formatting retain ordered separate native operations', () {
      final plan = _compile('''
With $_range
  .Text = "Prepared"
  With .Font
    .Bold = True
    .ColorIndex = wdDarkBlue
  End With
  With .ParagraphFormat
    .Alignment = wdAlignParagraphCenter
    .SpaceAfter = 6
  End With
  .Text = "Published"
End With
''');
      expect(plan.steps.map((step) => step.tool), [
        'docx.tableCellRangeText',
        'docx.runFormat',
        'docx.runFormat',
        'docx.paragraphFormat',
        'docx.paragraphFormat',
        'docx.tableCellRangeText',
      ]);
      expect(plan.steps.map((step) => step.arguments), [
        {'table': 1, 'row': 2, 'column': 3, 'text': 'Prepared'},
        _cell(1, 2, 3, {'bold': true}),
        _cell(1, 2, 3, {'color': '000080'}),
        _cell(1, 2, 3, {'alignment': 'center'}),
        _cell(1, 2, 3, {'after': 6}),
        {'table': 1, 'row': 2, 'column': 3, 'text': 'Published'},
      ]);
    });

    test('typed Font and ParagraphFormat aliases survive parent rebinding', () {
      final plan = _compile('''
Dim selectedTable As Table, selectedCell As Cell
Dim selectedRange As Range, copiedRange As Range
Dim face As Font, layout As ParagraphFormat
Set selectedTable = ThisDocument.Tables(2)
Set selectedCell = selectedTable.Cell(3, 4)
Set selectedRange = selectedCell.Range
Set copiedRange = selectedRange
Set face = selectedRange.Font
Set layout = selectedRange.ParagraphFormat
Set selectedTable = ThisDocument.Tables(1)
Set selectedCell = selectedTable.Cell(1, 2)
Set selectedRange = selectedCell.Range
face.Color = RGB(18, 52, 86)
layout.Alignment = wdAlignParagraphRight
copiedRange.Font.Italic = True
selectedRange.Font.Bold = False
''');
      expect(plan.steps.map((step) => step.arguments), [
        _cell(1, 2, 3, {'color': '123456'}),
        _cell(1, 2, 3, {'alignment': 'right'}),
        _cell(1, 2, 3, {'italic': true}),
        _cell(0, 0, 1, {'bold': false}),
      ]);
    });

    test(
      'named ByVal helpers retain the supplied selector and caller alias',
      () {
        final plan = _source('''
Option Explicit
Sub Paint(ByVal face As Font, Optional ByVal color As Long = wdAuto)
  face.ColorIndex = color
  Set face = ThisDocument.Tables(1).Cell(1, 1).Range.Font
  face.Bold = True
End Sub
Sub Align(ByVal layout As ParagraphFormat)
  layout.Alignment = wdAlignParagraphCenter
  Set layout = ThisDocument.Paragraphs(1).Format
  layout.SpaceAfter = 9
End Sub
Sub FormatRange(ByVal target As Range)
  Paint face:=target.Font, color:=wdRed
  Align layout:=target.ParagraphFormat
  Set target = ActiveDocument.Tables(1).Cell(1, 2).Range
  target.Font.Italic = True
End Sub
Sub Main()
  Dim target As Range, face As Font, layout As ParagraphFormat
  Set target = $_range
  Set face = target.Font
  Set layout = target.ParagraphFormat
  FormatRange target:=target
  Paint face:=face
  layout.SpaceAfter = 3
End Sub
''');
        expect(plan.steps.map((step) => step.arguments), [
          _cell(1, 2, 3, {'color': 'FF0000'}),
          _cell(0, 0, 0, {'bold': true}),
          _cell(1, 2, 3, {'alignment': 'center'}),
          {'paragraph': 0, 'after': 9},
          _cell(0, 0, 1, {'italic': true}),
          _cell(1, 2, 3, {'color': 'auto'}),
          _cell(0, 0, 0, {'bold': true}),
          _cell(1, 2, 3, {'after': 3}),
        ]);
      },
    );

    test('nested With and computed loop coordinates remain source-only', () {
      final plan = _compile('''
Dim rowIndex As Long, columnIndex As Long
With Application
  With .ActiveDocument.Tables.Item(2)
    For rowIndex = 1 To 2
      For columnIndex = 1 To 2
        With .Cell(rowIndex, columnIndex).Range
          .Font.Bold = rowIndex = 1
          .ParagraphFormat.SpaceAfter = columnIndex * 3
        End With
      Next columnIndex
    Next rowIndex
  End With
End With
''');
      expect(plan.steps.map((step) => step.arguments), [
        _cell(1, 0, 0, {'bold': true}),
        _cell(1, 0, 0, {'after': 3}),
        _cell(1, 0, 1, {'bold': true}),
        _cell(1, 0, 1, {'after': 6}),
        _cell(1, 1, 0, {'bold': false}),
        _cell(1, 1, 0, {'after': 3}),
        _cell(1, 1, 1, {'bold': false}),
        _cell(1, 1, 1, {'after': 6}),
      ]);
    });

    test('the same generic formatting helper accepts body and cell ranges', () {
      final plan = _source('''
Sub Format(ByVal target As Range)
  target.Font.Bold = True
  target.ParagraphFormat.SpaceAfter = 6
End Sub
Sub Main()
  Format ThisDocument.Paragraphs(2).Range
  Format $_range
  Format ThisDocument.Sections(1).Headers(1).Range.Paragraphs(1).Range
End Sub
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 1, 'bold': true},
        {'paragraph': 1, 'after': 6},
        _cell(1, 2, 3, {'bold': true}),
        _cell(1, 2, 3, {'after': 6}),
        {'paragraph': 0, 'story': 'header', 'section': 0, 'bold': true},
        {'paragraph': 0, 'story': 'header', 'section': 0, 'after': 6},
      ]);
    });
  });

  group('existing formatting contracts on a cell', () {
    for (final (source, fields) in <(String, Map<String, Object?>)>[
      ('Name = "Arial"', {'font': 'Arial'}),
      ('NameBi = "Amiri"', {'csFont': 'Amiri'}),
      ('Size = 11.5', {'size': 11.5}),
      ('Bold = False', {'bold': false}),
      ('Italic = True', {'italic': true}),
      ('Underline = wdUnderlineDouble', {'underline': 'double'}),
      ('StrikeThrough = True', {'strike': true}),
      ('SmallCaps = True', {'smallCaps': true}),
      ('AllCaps = False', {'allCaps': false}),
      ('Superscript = True', {'superscript': true}),
      ('Subscript = False', {'subscript': false}),
      ('Position = -2', {'position': -2}),
      ('Kerning = 8.5', {'kerning': 8.5}),
      ('Color = wdColorAutomatic', {'color': 'auto'}),
      ('ColorIndex = wdDarkRed', {'color': '800000'}),
    ]) {
      test('Font.$source keeps the bounded native value', () {
        final step = _compile('$_range.Font.$source').steps.single;
        expect(step.tool, 'docx.runFormat');
        expect(step.arguments, _cell(1, 2, 3, fields));
      });
    }

    for (final (source, fields) in <(String, Map<String, Object?>)>[
      ('Alignment = wdAlignParagraphJustify', {'alignment': 'justify'}),
      ('SpaceBefore = 0', {'before': 0}),
      ('SpaceAfter = 6.25', {'after': 6.25}),
      ('LeftIndent = -12.5', {'left': -12.5}),
      ('RightIndent = InchesToPoints(0.25)', {'right': 18}),
      ('FirstLineIndent = -9', {'firstLine': 0, 'hanging': 9}),
      ('KeepTogether = False', {'keepTogether': false}),
      ('PageBreakBefore = True', {'pageBreakBefore': true}),
      ('Hyphenation = False', {'suppressAutoHyphens': true}),
      ('ReadingOrder = wdReadingOrderRtl', {'rtl': true}),
      (
        'LineSpacingRule = wdLineSpaceDouble',
        {'lineSpacing': 2.0, 'lineSpacingRule': 'auto'},
      ),
    ]) {
      test('ParagraphFormat.$source retains cell identity', () {
        final step = _compile('$_range.ParagraphFormat.$source').steps.single;
        expect(step.tool, 'docx.paragraphFormat');
        expect(step.arguments, _cell(1, 2, 3, fields));
      });
    }

    test('paragraph spacing methods and tab objects retain the cell', () {
      final plan = _compile('''
Dim layout As ParagraphFormat, stops As TabStops
Set layout = $_range.ParagraphFormat
layout.Space1
layout.Space15
Call layout.Space2()
layout.OpenUp
layout.CloseUp
layout.OpenOrCloseUp
Set stops = layout.TabStops
Set layout = ThisDocument.Paragraphs(1).Format
stops.ClearAll
stops.Add Leader:=wdTabLeaderDots, Position:=72, Alignment:=wdAlignTabRight
''');
      expect(plan.steps.map((step) => step.tool), [
        'docx.paragraphFormat',
        'docx.paragraphFormat',
        'docx.paragraphFormat',
        'docx.paragraphSpaceBefore',
        'docx.paragraphSpaceBefore',
        'docx.paragraphSpaceBefore',
        'docx.clearTabStops',
        'docx.tabStop',
      ]);
      expect(plan.steps.map((step) => step.arguments), [
        _cell(1, 2, 3, {'lineSpacing': 1.0, 'lineSpacingRule': 'auto'}),
        _cell(1, 2, 3, {'lineSpacing': 1.5, 'lineSpacingRule': 'auto'}),
        _cell(1, 2, 3, {'lineSpacing': 2.0, 'lineSpacingRule': 'auto'}),
        _cell(1, 2, 3, {'action': 'open'}),
        _cell(1, 2, 3, {'action': 'close'}),
        _cell(1, 2, 3, {'action': 'toggle'}),
        _cell(1, 2, 3, {}),
        _cell(1, 2, 3, {'position': 72, 'alignment': 'right', 'leader': 'dot'}),
      ]);
    });

    test(
      'a spacing pair recognizes independently derived equivalent cells',
      () {
        final plan = _source('''
Sub Finish(ByVal layout As ParagraphFormat)
  layout.LineSpacing = 18.25
End Sub
Sub Main()
  Dim target As Range
  Set target = ThisDocument.Tables.Item(2).Cell(3, 4).Range
  target.ParagraphFormat.LineSpacingRule = wdLineSpaceExactly
  Finish ActiveDocument.Tables(2).Cell(3, 4).Range.ParagraphFormat
End Sub
''');
        expect(plan.steps.single.tool, 'docx.lineSpacing');
        expect(
          plan.steps.single.arguments,
          _cell(1, 2, 3, {'rule': 'exact', 'points': 18.25}),
        );
      },
    );

    for (final target in [
      'ActiveDocument.Tables(1).Cell(3, 4).Range.ParagraphFormat',
      'ActiveDocument.Tables(2).Cell(2, 4).Range.ParagraphFormat',
      'ActiveDocument.Tables(2).Cell(3, 3).Range.ParagraphFormat',
      'ActiveDocument.Paragraphs(1).Format',
      'ActiveDocument.Sections(1).Headers(1).Range.Paragraphs(1).Format',
    ]) {
      test('custom spacing cannot cross from a cell to $target', () {
        expect(
          () => _compile('''
$_range.ParagraphFormat.LineSpacingRule = wdLineSpaceExactly
$target.LineSpacing = 18
'''),
          throwsA(_error('vba_unsupported')),
        );
      });
    }

    test(
      'body paragraph zero and cell paragraph zero are distinct targets',
      () {
        expect(
          () => _compile('''
ActiveDocument.Paragraphs(1).Format.LineSpacingRule = wdLineSpaceExactly
ActiveDocument.Tables(1).Cell(1, 1).Range.ParagraphFormat.LineSpacing = 18
'''),
          throwsA(_error('vba_unsupported')),
        );
      },
    );
  });

  group('formatting boundaries', () {
    for (final statement in [
      '$_range.Font.Size = 11.25',
      '$_range.Font.Position = 0.5',
      '$_range.Font.Kerning = -1',
      '$_range.Font.Bold = 1',
      '$_range.ParagraphFormat.LeftIndent = 0.001',
      '$_range.ParagraphFormat.Alignment = True',
      '$_range.ParagraphFormat.PageBreakBefore = 1',
      '$_range.ParagraphFormat.SpaceBefore = -1',
    ]) {
      test('reuses strict type and precision rules: $statement', () {
        expect(
          () => _compile('$_range.Font.Bold = True\n$statement'),
          throwsA(_error('vba_type_error')),
        );
      });
    }

    for (final statement in [
      '$_range.Font = $_range.Font',
      '$_range.ParagraphFormat = $_range.ParagraphFormat',
      '$_range.Font.ColorIndex = wdByAuthor',
      '$_range.ParagraphFormat.Alignment = 4',
      '$_range.Font.Bold()',
      '$_range.ParagraphFormat.LineSpacing = 12',
    ]) {
      test('unsupported write retains a source diagnostic: $statement', () {
        expect(() => _compile(statement), throwsA(_error()));
      });
    }

    for (final statement in [
      '$_range.Shading.BackgroundPatternColor = wdColorRed',
      '$_range.Style = wdStyleNormal',
      '$_range.ListFormat.ApplyBulletDefault',
      'Dim value As Variant\nvalue = $_range.Font.Bold',
      'Dim value As Variant\nvalue = $_range.ParagraphFormat.Alignment',
      'Dim face As Font\nSet face = $_range.Font.Duplicate',
      'Dim layout As ParagraphFormat\nSet layout = $_range.ParagraphFormat.Duplicate',
    ]) {
      test(
        'cell range does not gain unrelated members in dead code: $statement',
        () {
          expect(
            () => _compile('If False Then\n$statement\nEnd If'),
            throwsA(_error('vba_unsupported')),
          );
        },
      );
    }

    for (final statement in [
      'selected.InsertAfter "x"',
      'selected.Style = wdStyleNormal',
      'selected.Shading.BackgroundPatternColor = wdColorRed',
      'selected.ListFormat.ApplyBulletDefault',
    ]) {
      test('a generic Range helper cannot escape its cell: $statement', () {
        expect(
          () => _source('''
Sub Main()
  TryWrite $_range
End Sub
Sub TryWrite(ByVal selected As Range)
  $statement
End Sub
'''),
          throwsA(_error('vba_unsupported')),
        );
      });
    }

    for (final value in ['0', '-1', '1.5', '2147483648', 'True', '"1"']) {
      test('formatting retains strict cell coordinates: $value', () {
        expect(
          () => _compile(
            'ActiveDocument.Tables(1).Cell($value, 1).Range.Font.Bold = True',
          ),
          throwsA(_error('vba_type_error')),
        );
      });
    }

    test('empty unused formatting paths do not emit operations', () {
      final plan = _source('''
Sub Unused()
  $_range.Font.Bold = True
  $_range.ParagraphFormat.Alignment = wdAlignParagraphCenter
End Sub
Sub Main()
  If False Then
    $_range.Font.Italic = True
  End If
End Sub
''');
      expect(plan.steps, isEmpty);
    });
  });
}
