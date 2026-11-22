import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'CellPrefix',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

const _cell = 'ActiveDocument.Tables(2).Cell(3, 4).Range';

Map<String, Object?> _prefix(
  String text, {
  int table = 1,
  int row = 2,
  int column = 3,
}) => {'table': table, 'row': row, 'column': column, 'text': text};

Matcher _error(String code) => isA<OfficeVbaCompileException>()
    .having((error) => error.code, 'code', code)
    .having((error) => error.moduleName, 'module', 'CellPrefix')
    .having((error) => error.entryPoint, 'entry', 'Main')
    .having((error) => error.line, 'line', greaterThan(0))
    .having((error) => error.column, 'column', greaterThan(0));

void main() {
  group('Word cell prefixes', () {
    for (final document in [
      'ThisDocument',
      'ActiveDocument',
      'Application.ActiveDocument',
    ]) {
      for (final tables in ['Tables', 'Tables.Item']) {
        for (final projection in [
          '',
          '.Paragraphs(1).Range',
          '.Paragraphs.Item(1).Range.Paragraphs(1).Range',
        ]) {
          test('$document.$tables$projection keeps exact cell coordinates', () {
            final plan = _compile(
              '$document.$tables(2).Cell(3, 4).Range$projection.InsertBefore Text:="Label: "',
            );
            expect(plan.steps.single.tool, 'docx.tableCellRangeInsertBefore');
            expect(plan.steps.single.arguments, _prefix('Label: '));
            expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
          });
        }
      }
    }

    test(
      'positional, named, Call and nested With forms retain their order',
      () {
        final plan = _compile('''
Dim target As Range
Set target = $_cell
target.InsertBefore "a"
target.InsertBefore("b")
Call target.InsertBefore("c")
target.InsertBefore Text:="d"
Call target.InsertBefore(tExT:="e")
With target
  .InsertBefore Text:="f"
  With .Paragraphs.Item(1).Range
    Call .InsertBefore(Text:="g")
    .InsertBefore ""
  End With
End With
''');
        expect(plan.steps.map((step) => step.arguments['text']), [
          'a',
          'b',
          'c',
          'd',
          'e',
          'f',
          'g',
          '',
        ]);
        expect(
          plan.steps.every(
            (step) => step.tool == 'docx.tableCellRangeInsertBefore',
          ),
          isTrue,
        );
      },
    );

    test('aliases and ByVal rebinding preserve direct and projected cells', () {
      final plan = _source('''
Sub Prefix(ByVal target As Range, Optional ByVal label As String = "Ready: ")
  target.InsertBefore Text:=label
  Set target = ActiveDocument.Tables(1).Cell(1, 2).Range
  target.InsertBefore "Local: "
End Sub
Sub Main()
  Dim selected As Cell, original As Range, projected As Range
  Set selected = ActiveDocument.Tables(2).Cell(3, 4)
  Set original = selected.Range
  Set projected = original.Paragraphs(1).Range
  Set selected = ActiveDocument.Tables(3).Cell(2, 1)
  Prefix label:="First: ", target:=original
  Prefix target:=projected
  original.InsertBefore "Caller: "
  selected.Range.InsertBefore "Other: "
End Sub
''');
      expect(plan.steps.map((step) => step.arguments), [
        _prefix('First: '),
        _prefix('Local: ', table: 0, row: 0, column: 1),
        _prefix('Ready: '),
        _prefix('Local: ', table: 0, row: 0, column: 1),
        _prefix('Caller: '),
        _prefix('Other: ', table: 2, row: 1, column: 0),
      ]);
    });

    test(
      'one named helper prefixes body, header, footer and cell selectors',
      () {
        final plan = _source('''
Sub Prefix(ByVal target As Range)
  target.InsertBefore Text:="Review: "
End Sub
Sub Main()
  Prefix ActiveDocument.Paragraphs(2).Range
  Prefix ActiveDocument.Sections(3).Headers(1).Range.Paragraphs(2).Range
  Prefix ActiveDocument.Sections(2).Footers(3).Range.Paragraphs(1).Range
  Prefix $_cell
  Prefix $_cell.Paragraphs(1).Range
End Sub
''');
        expect(plan.steps.map((step) => step.tool), [
          'docx.replaceText',
          'docx.replaceText',
          'docx.replaceText',
          'docx.tableCellRangeInsertBefore',
          'docx.tableCellRangeInsertBefore',
        ]);
        expect(plan.steps.map((step) => step.arguments), [
          {'paragraph': 1, 'start': 0, 'end': 0, 'text': 'Review: '},
          {
            'paragraph': 1,
            'story': 'header',
            'section': 2,
            'start': 0,
            'end': 0,
            'text': 'Review: ',
          },
          {
            'paragraph': 0,
            'story': 'evenFooter',
            'section': 1,
            'start': 0,
            'end': 0,
            'text': 'Review: ',
          },
          _prefix('Review: '),
          _prefix('Review: '),
        ]);
      },
    );

    test(
      'receiver is captured before one evaluation of its named argument',
      () {
        final plan = _source('''
Function ChooseTable() As Long
  ActiveDocument.Paragraphs(1).Range.InsertBefore Text:="receiver"
  ChooseTable = 2
End Function
Function Label() As String
  ActiveDocument.Paragraphs(1).Range.InsertBefore Text:="argument"
  Label = "once"
End Function
Sub Main()
  ActiveDocument.Tables(ChooseTable()).Cell(3, 4).Range.InsertBefore Text:=Label()
End Sub
''');
        expect(plan.steps.map((step) => step.arguments['text']), [
          'receiver',
          'argument',
          'once',
        ]);
        expect(plan.steps.last.arguments, _prefix('once'));
      },
    );

    test('cyclic alias origins still select the actual cell at evaluation', () {
      final plan = _compile('''
Dim a As Range, b As Range
Set a = $_cell.Paragraphs(1).Range
Set b = a
Set a = b
a.InsertBefore Text:="Cycle: "
''');
      expect(plan.steps.single.arguments, _prefix('Cycle: '));
    });

    test(
      'Unicode, tabs, empty strings and explicit Variant strings compile',
      () {
        final plan = _compile('''
Dim text As Variant
text = "Résumé 😀 & <ready>" & vbTab
$_cell.InsertBefore Text:=text
$_cell.InsertBefore Text:=""
''');
        expect(plan.steps.map((step) => step.arguments), [
          _prefix('Résumé 😀 & <ready>\t'),
          _prefix(''),
        ]);
      },
    );

    test('supported inactive prefix paths and unused helpers are checked', () {
      expect(
        _source('''
Sub Main()
  If False Then
    $_cell.InsertBefore Text:="unused"
    $_cell.Paragraphs(1).Range.InsertBefore "unused"
  End If
End Sub
Sub Unused(ByVal target As Range)
  target.InsertBefore Text:="unused"
End Sub
''').steps,
        isEmpty,
      );
    });
  });

  group('cell prefix boundaries', () {
    for (final argument in ['1', 'True', 'Empty', 'Null']) {
      test('does not implicitly coerce $argument to prefix text', () {
        expect(
          () => _compile('$_cell.InsertBefore Text:=$argument'),
          throwsA(_error('vba_type_error')),
        );
      });
    }
    for (final call in [
      'InsertBefore',
      'InsertBefore()',
      'InsertBefore "a", "b"',
      'InsertBefore Text:="a", Text:="b"',
      'InsertBefore , "b"',
    ]) {
      test('requires exactly one nonomitted argument: $call', () {
        expect(
          () => _compile('$_cell.$call'),
          throwsA(_error('vba_type_error')),
        );
      });
    }
    for (final target in [_cell, 'ActiveDocument.Paragraphs(1).Range']) {
      test('unknown named argument is checked in inactive $target', () {
        expect(
          () => _compile(
            'If False Then\n$target.InsertBefore Value:="x"\nEnd If',
          ),
          throwsA(_error('vba_name_error')),
        );
      });
      test('nonstrings are checked in inactive $target', () {
        expect(
          () => _compile(
            'If False Then\n$target.InsertBefore Text:=True\nEnd If',
          ),
          throwsA(_error('vba_type_error')),
        );
      });
    }
    for (final text in [
      '"a" & vbCr',
      '"a" & vbLf',
      'ChrW(7)',
      'ChrW(0)',
      'ChrW(55296)',
    ]) {
      test('refuses structural and invalid text $text', () {
        expect(
          () => _compile('$_cell.InsertBefore Text:=$text'),
          throwsA(_error('vba_type_error')),
        );
      });
    }
    for (final statement in [
      '$_cell.Paragraphs(1).Range.InsertAfter "x"',
      '$_cell.Paragraphs(1).Range.Text = "x"',
      '$_cell.Paragraphs(1).Range.ListFormat.ApplyBulletDefault',
      '$_cell.Paragraphs(2).Range.InsertBefore "x"',
      'Dim value As Variant\nvalue = $_cell.Text',
      'Dim target As Range\ntarget.InsertBefore Text:="x"',
    ]) {
      test('retains unsupported selector boundary: $statement', () {
        expect(() => _compile(statement), throwsA(_error('vba_unsupported')));
      });
    }
    test('whole header ranges remain a distinct unsupported object type', () {
      expect(
        () => _compile(
          'ActiveDocument.Sections(1).Headers(1).Range.InsertBefore Text:="x"',
        ),
        throwsA(_error('vba_type_error')),
      );
    });
    test('insertion cannot interrupt a pending custom line-spacing pair', () {
      for (final text in ['"x"', '""']) {
        expect(
          () => _compile('''
$_cell.ParagraphFormat.LineSpacingRule = wdLineSpaceExactly
$_cell.InsertBefore Text:=$text
$_cell.ParagraphFormat.LineSpacing = 14
'''),
          throwsA(_error('vba_unsupported')),
        );
      }
    });
    test('retains source String and aggregate native output limits', () {
      final plan = _compile('$_cell.InsertBefore Text:=String(32767, "x")');
      expect((plan.steps.single.arguments['text']! as String).length, 32767);
      expect(
        () => _compile('$_cell.InsertBefore Text:=String(32768, "x")'),
        throwsA(_error('vba_limit_exceeded')),
      );
      expect(
        () => _compile('''
Dim i As Long
For i = 1 To 40
  $_cell.InsertBefore Text:=String(32767, "x")
Next i
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  });
}
