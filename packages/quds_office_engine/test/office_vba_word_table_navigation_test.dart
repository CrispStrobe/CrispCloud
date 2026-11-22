import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'TableNavigation',
    source: source,
  ),
);

OfficeMacro _body(String source) => _source('Sub Main()\n$source\nEnd Sub');

Matcher _error([String? code]) {
  final result = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'TableNavigation')
      .having((error) => error.entryPoint, 'entry', 'Main')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? result
      : result.having((error) => error.code, 'code', code);
}

Map<String, Object?> _cell(int table, int row, int column, String text) => {
  'table': table,
  'row': row,
  'column': column,
  'text': text,
};

Map<String, Object?> _format(Map<String, Object?> fields) => {
  'paragraph': 0,
  'story': 'tableCell',
  'table': 1,
  'row': 2,
  'column': 3,
  ...fields,
};

const _table = 'ActiveDocument.Tables(2)';
const _row = '$_table.Rows(3).Cells(4)';
const _column = '$_table.Columns(4).Cells(3)';

void main() {
  group('row and column cell identity', () {
    for (final document in [
      'ThisDocument',
      'ActiveDocument',
      'Application.ActiveDocument',
    ]) {
      for (final item in ['', '.Item']) {
        for (final axis in ['Rows', 'Columns']) {
          test('$document / $axis$item translates both coordinates', () {
            final first = axis == 'Rows' ? 3 : 4;
            final second = axis == 'Rows' ? 4 : 3;
            final plan = _body(
              '$document.Tables$item(2).$axis$item($first)'
              '.Cells$item($second).Range.Text = "Ready"',
            );
            expect(plan.steps.single.tool, 'docx.tableCellRangeText');
            expect(plan.steps.single.arguments, _cell(1, 2, 3, 'Ready'));
            expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
          });
        }
      }
    }

    for (final selector in [
      'ActiveDocument.Tables(Index:=2).Rows(Index:=3).Cells(Index:=4)',
      'ActiveDocument.Tables.Item(Index:=2).Rows.Item(Index:=3)'
          '.Cells.Item(Index:=4)',
      'ActiveDocument.Tables(Index:=2).Columns(Index:=4).Cells(Index:=3)',
      'ActiveDocument.Tables.Item(Index:=2).Columns.Item(Index:=4)'
          '.Cells.Item(Index:=3)',
      'ActiveDocument.Tables(2).Cell(Column:=4, Row:=3)',
      'ActiveDocument.Tables(2).Cell(3, Column:=4)',
      'aCtIvEdOcUmEnT.tAbLeS(iNdEx:=2).rOwS(iNdEx:=3)'
          '.cElLs(iNdEx:=4)',
    ]) {
      test('required named selectors: $selector', () {
        final plan = _body('$selector.Range.Text = "Named"');
        expect(plan.steps.single.arguments, _cell(1, 2, 3, 'Named'));
      });
    }

    test('collection aliases preserve both axis and parent binding', () {
      final plan = _body('''
Dim report As Table, rows As Rows, columns As Columns
Dim selectedRow As Row, selectedColumn As Column, selectedCells As Cells
Dim target As Range, retained As Range
Set report = ActiveDocument.Tables(2)
Set rows = report.Rows
Set columns = report.Columns
Set selectedRow = rows.Item(3)
Set selectedColumn = columns.Item(4)
Set selectedCells = selectedRow.Cells
Set target = selectedCells.Item(4).Range
Set retained = target
Set report = ActiveDocument.Tables(1)
Set rows = report.Rows
Set selectedRow = rows.Item(1)
Set selectedCells = selectedColumn.Cells
Set target = selectedCells.Item(2).Range
retained.Text = "Row identity"
target.Text = "Column identity"
selectedRow.Cells(2).Range.Text = "New table"
''');
      expect(plan.steps.map((step) => step.arguments), [
        _cell(1, 2, 3, 'Row identity'),
        _cell(1, 1, 3, 'Column identity'),
        _cell(0, 0, 1, 'New table'),
      ]);
    });

    for (final (type, initial, alternate, initialCell, alternateCell)
        in <(String, String, String, String, String)>[
          (
            'Rows',
            '$_table.Rows',
            'ActiveDocument.Tables(1).Rows',
            'Item(3).Cells(4)',
            'Item(1).Cells(2)',
          ),
          (
            'Row',
            '$_table.Rows(3)',
            'ActiveDocument.Tables(1).Rows(1)',
            'Cells(4)',
            'Cells(2)',
          ),
          (
            'Columns',
            '$_table.Columns',
            'ActiveDocument.Tables(1).Columns',
            'Item(4).Cells(3)',
            'Item(2).Cells(1)',
          ),
          (
            'Column',
            '$_table.Columns(4)',
            'ActiveDocument.Tables(1).Columns(2)',
            'Cells(3)',
            'Cells(1)',
          ),
          (
            'Cells',
            '$_table.Rows(3).Cells',
            'ActiveDocument.Tables(1).Columns(2).Cells',
            'Item(4)',
            'Item(1)',
          ),
        ]) {
      test('$type required named ByVal helper retains caller ownership', () {
        final plan = _source('''
Sub Main()
  Dim selected As $type
  Set selected = $initial
  Apply target:=selected
  selected.$initialCell.Range.Text = "Caller"
End Sub
Sub Apply(ByVal target As $type)
  target.$initialCell.Range.Text = "Initial"
  Set target = $alternate
  target.$alternateCell.Range.Text = "Local"
End Sub
''');
        expect(plan.steps.map((step) => step.arguments), [
          _cell(1, 2, 3, 'Initial'),
          _cell(0, 0, 1, 'Local'),
          _cell(1, 2, 3, 'Caller'),
        ]);
      });
    }

    test('nested With captures a direct cell for all existing operations', () {
      final plan = _body('''
Dim saved As Range
With ActiveDocument.Tables(Index:=2)
  With .Rows
    With .Item(Index:=3)
      With .Cells
        With .Item(Index:=4)
          Set saved = .Range
          .Range.Text = "Ready"
        End With
      End With
    End With
  End With
End With
With saved
  .InsertBefore Text:="Status: "
  .InsertAfter Text:=vbTab & "Reviewed"
  .Font.Bold = True
  .ParagraphFormat.Alignment = wdAlignParagraphRight
  .LanguageID = wdFrench
  .Paragraphs(1).Style = wdStyleNormal
  .Paragraphs(1).Shading.BackgroundPatternColor = RGB(18, 52, 86)
End With
''');
      expect(plan.steps.map((step) => step.tool), [
        'docx.tableCellRangeText',
        'docx.tableCellRangeInsertBefore',
        'docx.tableCellRangeInsertAfter',
        'docx.runFormat',
        'docx.paragraphFormat',
        'docx.runFormat',
        'docx.paragraphStyle',
        'docx.paragraphShading',
      ]);
      expect(plan.steps.map((step) => step.arguments), [
        _cell(1, 2, 3, 'Ready'),
        _cell(1, 2, 3, 'Status: '),
        _cell(1, 2, 3, '\tReviewed'),
        _format({'bold': true}),
        _format({'alignment': 'right'}),
        _format({'language': 'fr-FR'}),
        _format({'builtin': -1}),
        _format({'color': '123456'}),
      ]);
    });

    test('direct-cell aliases remain rooted through cycles', () {
      final plan = _body('''
Dim a As Range, b As Range, c As Range
Set a = $_row.Range
Set b = a
Set c = b
Set a = c
a.Text = "Rooted"
b.InsertAfter " after"
Set c = $_column.Range
c.InsertBefore "before "
''');
      expect(plan.steps.map((step) => step.arguments), [
        _cell(1, 2, 3, 'Rooted'),
        _cell(1, 2, 3, ' after'),
        _cell(1, 2, 3, 'before '),
      ]);
    });

    test(
      'receiver and reversed named arguments evaluate once in source order',
      () {
        final plan = _source('''
Sub Main()
  ActiveDocument.Tables(Index:=Mark(2)).Cell(Column:=Mark(4), Row:=Mark(3)).Range.Text = "Target"
  ActiveDocument.Tables(Index:=Mark(2)).Columns.Item(Index:=Mark(4)).Cells(Index:=Mark(3)).Range.Text = "Column"
End Sub
Function Mark(ByVal value As Long) As Long
  ActiveDocument.Tables(1).Cell(1, 1).Range.InsertAfter CStr(value)
  Mark = value
End Function
''');
        expect(plan.steps.map((step) => step.arguments), [
          _cell(0, 0, 0, '2'),
          _cell(0, 0, 0, '4'),
          _cell(0, 0, 0, '3'),
          _cell(1, 2, 3, 'Target'),
          _cell(0, 0, 0, '2'),
          _cell(0, 0, 0, '4'),
          _cell(0, 0, 0, '3'),
          _cell(1, 2, 3, 'Column'),
        ]);
      },
    );

    test('known dimensions can be addressed with source-only loops', () {
      final plan = _body('''
Dim r As Long, c As Long, selected As Row
For r = 1 To 2
  Set selected = ActiveDocument.Tables(1).Rows(r)
  For c = 1 To 2
    selected.Cells(c).Range.Text = CStr(r) & ":" & CStr(c)
  Next c
Next r
''');
      expect(plan.steps.map((step) => step.arguments), [
        _cell(0, 0, 0, '1:1'),
        _cell(0, 0, 1, '1:2'),
        _cell(0, 1, 0, '2:1'),
        _cell(0, 1, 1, '2:2'),
      ]);
    });
  });

  group('exact source-known selectors', () {
    for (final selector in [
      'ActiveDocument.Tables(Index:=value).Rows(1).Cells(1)',
      'ActiveDocument.Tables(1).Rows(Index:=value).Cells(1)',
      'ActiveDocument.Tables(1).Columns.Item(Index:=value).Cells(1)',
      'ActiveDocument.Tables(1).Rows(1).Cells.Item(Index:=value)',
      'ActiveDocument.Tables(1).Columns(1).Cells(Index:=value)',
      'ActiveDocument.Tables(1).Cell(Column:=value, Row:=1)',
    ]) {
      for (final value in [
        '0',
        '-1',
        '1.5',
        '2147483648',
        'True',
        '"1"',
        'Empty',
        'Null',
      ]) {
        test('$selector refuses Variant $value', () {
          expect(
            () => _body('''
Dim value As Variant
value = $value
$selector.Range.Text = "Refused"
'''),
            throwsA(_error('vba_type_error')),
          );
        });
      }
    }

    test('portable Long maximum remains a selector, never a document read', () {
      final plan = _body('''
ActiveDocument.Tables(Index:=2147483647).Rows(Index:=2147483647).Cells(Index:=2147483647).Range.Text = "Large"
''');
      expect(
        plan.steps.single.arguments,
        _cell(2147483646, 2147483646, 2147483646, 'Large'),
      );
    });

    for (final member in [
      'Rows()',
      'Rows(,)',
      'Rows(Index:=)',
      'Rows(1, 2)',
      'Rows(Index:=1, Index:=2)',
      'Rows(Row:=1)',
      'Rows.Item()',
      'Rows.Item(Row:=1)',
      'Columns(Column:=1)',
      'Rows(1).Cells()',
      'Rows(1).Cells(1, 2)',
      'Columns(1).Cells(Column:=1)',
      'Rows(1).Cells.Item(Row:=1)',
      'Cell(Row:=1)',
      'Cell(Column:=1)',
      'Cell(Row:=1, Row:=2)',
      'Cell(1, Row:=2)',
      'Cell(Row:=1, 2)',
      'Cell(, Column:=2)',
      'Cell(Row:=1, Column:=2, Index:=3)',
      'Cell(Row:=1, Col:=2)',
    ]) {
      test('malformed required selector refuses: $member', () {
        expect(
          () => _body('$_table.$member.Range.Text = "x"'),
          throwsA(_error()),
        );
      });
    }

    test('native step and source work limits remain in force', () {
      expect(
        () => _body('''
Dim i As Long, target As Range
Set target = $_row.Range
For i = 1 To 10001
  target.Text = ""
Next i
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  });

  group('object boundaries remain statically checked', () {
    final objects = <String, String>{
      'Rows': '$_table.Rows',
      'Row': '$_table.Rows(3)',
      'Columns': '$_table.Columns',
      'Column': '$_table.Columns(4)',
      'Cells': '$_table.Rows(3).Cells',
    };
    for (final entry in objects.entries) {
      final type = entry.key;
      final selector = entry.value;
      test('$type requires Set and cannot be assigned to Variant', () {
        expect(
          () => _body('Dim chosen As $type\nchosen = $selector'),
          throwsA(_error('vba_type_error')),
        );
        expect(
          () => _body('Dim chosen As Variant\nSet chosen = $selector'),
          throwsA(_error('vba_type_error')),
        );
      });

      test('$type rejects scalar and wrong object even in inactive code', () {
        for (final value in ['Empty', 'value', 'ActiveDocument']) {
          expect(
            () => _body('''
Dim chosen As $type, value As Variant
If False Then
  Set chosen = $value
End If
'''),
            throwsA(_error('vba_type_error')),
          );
        }
      });

      test('$type cannot accept Variant through an unused helper call', () {
        expect(
          () => _source('''
Sub Main()
End Sub
Sub Unused()
  Dim value As Variant
  Apply target:=value
End Sub
Sub Apply(ByVal target As $type)
End Sub
'''),
          throwsA(_error('vba_type_error')),
        );
      });

      test('$type arrays, returns and optional parameters remain refused', () {
        for (final source in [
          'Sub Main()\nDim chosen(0 To 1) As $type\nEnd Sub',
          'Sub Main()\nEnd Sub\nFunction Selected() As $type\nEnd Function',
          'Sub Main()\nEnd Sub\nSub Apply(Optional ByVal target As $type)\nEnd Sub',
        ]) {
          expect(() => _source(source), throwsA(_error('vba_unsupported')));
        }
      });

      for (final language in ['vba-excel', 'vba-powerpoint']) {
        test('$type declaration stays out of $language', () {
          expect(
            () => OfficeMacroLanguages().compile(
              OfficeMacroSource(
                language: language,
                format: language == 'vba-excel'
                    ? OfficeMacroFormat.xlsx
                    : OfficeMacroFormat.pptx,
                moduleName: 'TableNavigation',
                source: 'Sub Main()\nDim chosen As $type\nEnd Sub',
              ),
            ),
            throwsA(_error('vba_unsupported')),
          );
        });
      }
    }

    for (final member in [
      'Rows.Count',
      'Rows.First.Cells(1)',
      'Rows.Last.Cells(1)',
      'Columns.Count',
      'Columns.First.Cells(1)',
      'Columns.Last.Cells(1)',
      'Rows(1).Cells.Count',
      'Columns(1).Cells.Count',
      'Rows(1).Cells.First',
      'Rows(1).Cells.Last',
      'Rows(1).Range',
      'Columns(1).Range',
      'Cells(1)',
      'Range.Cells(1)',
    ]) {
      test('unsupported table member is checked when inactive: $member', () {
        expect(
          () => _body('''
Dim value As Variant
If False Then
  value = $_table.$member
End If
'''),
          throwsA(_error('vba_unsupported')),
        );
      });
    }

    test('row/column selectors cannot broadcast or enumerate', () {
      for (final statement in [
        '$_table.Rows(1).Cells.Font.Bold = True',
        '$_table.Columns(1).Cells.Text = "x"',
        '$_table.Rows(1).Range.Text = "x"',
        'Dim chosen As Cell\nFor Each chosen In $_table.Rows(1).Cells\nNext chosen',
        'Dim rows As Rows\nSet rows = $_table.Rows\nrows(1).Cells(1).Range.Text = "x"',
      ]) {
        expect(() => _body(statement), throwsA(_error()));
      }
    });

    for (final origin in [_row, _column]) {
      test(
        'cell paragraph projection does not acquire suffix behavior: $origin',
        () {
          expect(
            () => _body('''
If False Then
  $origin.Range.Paragraphs(1).Range.InsertAfter "Refused"
End If
'''),
            throwsA(_error('vba_unsupported')),
          );
        },
      );

      test(
        'cell paragraph projection does not acquire list behavior: $origin',
        () {
          expect(
            () => _body('''
If False Then
  $origin.Range.Paragraphs(1).Range.ListFormat.ApplyBulletDefault
End If
'''),
            throwsA(_error('vba_unsupported')),
          );
        },
      );

      test(
        'mixed paragraph origin cannot hide behind cell alias cycles: $origin',
        () {
          expect(
            () => _body('''
Dim a As Range, b As Range
Set a = $origin.Range
Set b = a
Set a = b
If False Then
  Set b = ActiveDocument.Paragraphs(1).Range
End If
a.InsertAfter "Refused"
'''),
            throwsA(_error('vba_unsupported')),
          );
        },
      );
    }
  });
}
