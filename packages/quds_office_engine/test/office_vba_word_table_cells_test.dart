import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordTableCells',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Matcher _error([String? code]) {
  final result = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'WordTableCells')
      .having((error) => error.entryPoint, 'entry', 'Main')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? result
      : result.having((error) => error.code, 'code', code);
}

const _target = 'ActiveDocument.Tables(2).Cell(3, 4).Range';

Map<String, Object?> _cell(int table, int row, int column, String text) => {
  'table': table,
  'row': row,
  'column': column,
  'text': text,
};

void main() {
  group('explicit table-cell text selectors', () {
    for (final document in <String>[
      'ThisDocument',
      'ActiveDocument',
      'Application.ActiveDocument',
    ]) {
      for (final item in <String>['', '.Item']) {
        test('$document.Tables$item selects one-based table/row/column', () {
          final plan = _compile(
            '$document.Tables$item(2).Cell(3, 4).Range.Text = "Prepared"',
          );
          expect(plan.steps.single.tool, 'docx.tableCellRangeText');
          expect(plan.steps.single.arguments, _cell(1, 2, 3, 'Prepared'));
          expect(
            OfficeMacro.parse(jsonEncode(plan.toJson())).toJson(),
            plan.toJson(),
          );
        });
      }
    }

    test(
      'typed aliases keep their cell when preceding selectors are rebound',
      () {
        final plan = _compile('''
Dim doc As Document
Dim allTables As Tables
Dim selectedTable As Table
Dim selectedCell As Cell
Dim target As Range
Dim copy As Range
Set doc = ThisDocument
Set allTables = doc.Tables
Set selectedTable = allTables.Item(2)
Set selectedCell = selectedTable.Cell(3, 4)
Set target = selectedCell.Range
Set copy = target
Set selectedTable = doc.Tables(1)
Set selectedCell = selectedTable.Cell(1, 2)
Set target = selectedCell.Range
copy.Text = "Original"
target.Text = "Rebound"
''');
        expect(plan.steps.map((step) => step.arguments), [
          _cell(1, 2, 3, 'Original'),
          _cell(0, 0, 1, 'Rebound'),
        ]);
      },
    );

    test('nested With includes Tables, Table, Cell and cell Range', () {
      final plan = _compile('''
Dim saved As Range
With Application
  With .ActiveDocument
    With .Tables
      With .Item(2)
        With .Cell(3, 4)
          Set saved = .Range
          With .Range
            .Text = "Nested"
          End With
        End With
      End With
    End With
  End With
End With
saved.Text = "Saved"
''');
      expect(plan.steps.map((step) => step.arguments), [
        _cell(1, 2, 3, 'Nested'),
        _cell(1, 2, 3, 'Saved'),
      ]);
    });

    test('case-insensitive members and local computed selectors', () {
      final plan = _compile('''
Dim rowIndex As Long
Dim columnIndex As Variant
rowIndex = 2
columnIndex = 3
WiTh aCtIvEdOcUmEnT.tAbLeS.ItEm(1 + 1).cElL(rowIndex + 1, CLng(columnIndex) + 1).RaNgE
  .tExT = Replace("a_b", "_", " ") & ChrW(9) & "😀"
EnD wItH
''');
      expect(plan.steps.single.arguments, _cell(1, 2, 3, 'a b\t😀'));
    });

    test(
      'required ByVal objects and named helper arguments keep bindings local',
      () {
        final plan = _source('''
Option Explicit
Sub Main()
Dim allTables As Tables
Dim selectedTable As Table
Dim chosen As Cell
Dim target As Range
Set allTables = ThisDocument.Tables
Set selectedTable = allTables.Item(2)
Set chosen = selectedTable.Cell(3, 4)
Set target = chosen.Range
Call FillTable(selected:=selectedTable, label:="Table")
Call FillCell(chosen, "Cell")
Call FillRange(target, "Range")
Call FillCollection(allTables)
target.Text = "Caller"
End Sub
Sub FillTable(ByVal selected As Table, ByVal label As String)
selected.Cell(3, 4).Range.Text = label
Set selected = ThisDocument.Tables(1)
selected.Cell(1, 1).Range.Text = "Local table"
End Sub
Sub FillCell(ByVal selected As Cell, ByVal label As String)
selected.Range.Text = label
Set selected = ThisDocument.Tables(1).Cell(1, 2)
selected.Range.Text = "Local cell"
End Sub
Sub FillRange(ByVal selected As Range, ByVal label As String)
With selected
  .Text = label
End With
Set selected = ThisDocument.Tables(1).Cell(1, 3).Range
selected.Text = "Local range"
End Sub
Sub FillCollection(ByVal selected As Tables)
selected.Item(1).Cell(1, 4).Range.Text = "Collection"
End Sub
''');
        expect(plan.steps.map((step) => step.arguments), [
          _cell(1, 2, 3, 'Table'),
          _cell(0, 0, 0, 'Local table'),
          _cell(1, 2, 3, 'Cell'),
          _cell(0, 0, 1, 'Local cell'),
          _cell(1, 2, 3, 'Range'),
          _cell(0, 0, 2, 'Local range'),
          _cell(0, 0, 3, 'Collection'),
          _cell(1, 2, 3, 'Caller'),
        ]);
      },
    );

    test('bounded nested loops populate known table coordinates', () {
      final plan = _compile('''
Dim rowIndex As Long
Dim columnIndex As Long
For rowIndex = 1 To 2
  For columnIndex = 1 To 2
    ActiveDocument.Tables(1).Cell(rowIndex, columnIndex).Range.Text = CStr(rowIndex) & ":" & CStr(columnIndex)
  Next columnIndex
Next rowIndex
''');
      expect(plan.steps.map((step) => step.arguments), [
        _cell(0, 0, 0, '1:1'),
        _cell(0, 0, 1, '1:2'),
        _cell(0, 1, 0, '2:1'),
        _cell(0, 1, 1, '2:2'),
      ]);
    });

    test(
      'empty String clears a cell and scalar Variant String is explicit',
      () {
        final plan = _compile('''
Dim label As Variant
label = "Résumé"
$_target.Text = label
$_target.Text = ""
''');
        expect(plan.steps.map((step) => step.arguments), [
          _cell(1, 2, 3, 'Résumé'),
          _cell(1, 2, 3, ''),
        ]);
      },
    );

    test('largest portable Long selectors compile without a document', () {
      final plan = _compile('''
ActiveDocument.Tables(2147483647).Cell(2147483647, 2147483647).Range.Text = "Boundary"
''');
      expect(
        plan.steps.single.arguments,
        _cell(2147483646, 2147483646, 2147483646, 'Boundary'),
      );
    });
  });

  group('strict selector and text values', () {
    for (final value in <String>[
      '0',
      '-1',
      '1.5',
      '2147483648',
      'True',
      '"1"',
      'Empty',
      'Null',
    ]) {
      for (final selector in <String>[
        'ActiveDocument.Tables(value).Cell(1, 1)',
        'ActiveDocument.Tables(1).Cell(value, 1)',
        'ActiveDocument.Tables(1).Cell(1, value)',
      ]) {
        test('$selector refuses Variant $value', () {
          expect(
            () => _compile('''
Dim value As Variant
value = $value
$selector.Range.Text = "x"
'''),
            throwsA(_error('vba_type_error')),
          );
        });
      }
    }

    for (final value in <String>['1', 'True', 'Empty', 'Null']) {
      test('Text does not implicitly coerce Variant $value', () {
        expect(
          () => _compile('''
Dim value As Variant
value = $value
$_target.Text = value
'''),
          throwsA(_error('vba_type_error')),
        );
      });
    }

    for (final value in <String>[
      'ChrW(0)',
      'ChrW(7)',
      'ChrW(10)',
      'ChrW(13)',
      'ChrW(11)',
      'ChrW(65534)',
      'ChrW(65535)',
      'ChrW(55296)',
      'ChrW(56320)',
    ]) {
      test('Text refuses unsafe native text $value', () {
        expect(
          () => _compile('$_target.Text = $value'),
          throwsA(_error('vba_type_error')),
        );
      });
    }

    for (final statement in <String>[
      'ActiveDocument.Tables().Cell(1,1).Range.Text = "x"',
      'ActiveDocument.Tables(1,2).Cell(1,1).Range.Text = "x"',
      'ActiveDocument.Tables.Item().Cell(1,1).Range.Text = "x"',
      'ActiveDocument.Tables(1).Cell().Range.Text = "x"',
      'ActiveDocument.Tables(1).Cell(1).Range.Text = "x"',
      'ActiveDocument.Tables(1).Cell(1,2,3).Range.Text = "x"',
    ]) {
      test('invalid arity: $statement', () {
        expect(() => _compile(statement), throwsA(_error('vba_type_error')));
      });
    }

    for (final statement in <String>[
      'ActiveDocument.Tables(1).Cell(1,1).Range(1).Text = "x"',
      '$_target.Text(1) = "x"',
      'ActiveDocument.Tables(Index:=1).Cell(1,1).Range.Text = "x"',
      'ActiveDocument.Tables.Item(Index:=1).Cell(1,1).Range.Text = "x"',
      'ActiveDocument.Tables(1).Cell(Row:=1, Column:=1).Range.Text = "x"',
      'ActiveDocument.Tables(1).Cell(,1).Range.Text = "x"',
      'ActiveDocument.Tables(1).Cell(1,).Range.Text = "x"',
    ]) {
      test('unsupported member argument form: $statement', () {
        expect(() => _compile(statement), throwsA(_error('vba_unsupported')));
      });
    }
  });

  group('object and document boundaries', () {
    for (final type in <String>['Tables', 'Table', 'Cell']) {
      test('$type rejects scalar Set even in an unused branch', () {
        expect(
          () => _compile('''
Dim selected As $type
If False Then
  Set selected = Empty
End If
'''),
          throwsA(_error('vba_type_error')),
        );
      });
      test('$type requires Set', () {
        final value = switch (type) {
          'Tables' => 'ActiveDocument.Tables',
          'Table' => 'ActiveDocument.Tables(1)',
          _ => 'ActiveDocument.Tables(1).Cell(1,1)',
        };
        expect(
          () => _compile('Dim selected As $type\nselected = $value'),
          throwsA(_error('vba_type_error')),
        );
      });
      test('$type arrays and returns remain unsupported', () {
        expect(
          () => _compile('Dim selected(0 To 1) As $type'),
          throwsA(_error('vba_unsupported')),
        );
        expect(
          () => _source('''
Sub Main()
End Sub
Function GetObject() As $type
End Function
'''),
          throwsA(_error('vba_unsupported')),
        );
      });
      for (final language in <String>['vba-excel', 'vba-powerpoint']) {
        test('$type declaration does not leak into $language', () {
          expect(
            () => OfficeMacroLanguages().compile(
              OfficeMacroSource(
                language: language,
                format: language == 'vba-excel'
                    ? OfficeMacroFormat.xlsx
                    : OfficeMacroFormat.pptx,
                moduleName: 'WordTableCells',
                source: 'Sub Main()\nDim selected As $type\nEnd Sub',
              ),
            ),
            throwsA(_error('vba_unsupported')),
          );
        });
      }
    }

    for (final statement in <String>[
      'value = ActiveDocument.Tables.Count',
      'value = ActiveDocument.Tables(1).Rows.Count',
      'value = ActiveDocument.Tables(1).Columns.Count',
      'value = ActiveDocument.Tables(1).Cell(1,1).Range.Text',
      'value = ActiveDocument.Tables(1).Cell(1,1).RowIndex',
      '$_target.Shading.BackgroundPatternColor = wdColorRed',
      '$_target.Style = wdStyleNormal',
      '$_target.Paragraphs(1).Range.InsertAfter "x"',
      '$_target.Value = "x"',
      'ActiveDocument.Sections(1).Headers(1).Range.Tables(1).Cell(1,1).Range.Text = "x"',
      'ActiveDocument.Paragraphs(1).Range.Text = "x"',
    ]) {
      test('unsupported member is checked even when unused: $statement', () {
        expect(
          () => _compile('''
Dim value As Variant
If False Then
$statement
End If
'''),
          throwsA(_error('vba_unsupported')),
        );
      });
    }

    test('unused helper still checks the table object shape', () {
      expect(
        () => _source('''
Sub Main()
End Sub
Sub Unused(ByVal selected As Table)
Dim count As Long
count = selected.Rows.Count
End Sub
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('Tables does not enumerate or admit objects as Variant scalars', () {
      expect(
        () => _compile('''
Dim selected As Table
For Each selected In ActiveDocument.Tables
Next selected
'''),
        throwsA(_error('vba_unsupported')),
      );
      expect(
        () => _compile('''
Dim selected As Variant
Set selected = ActiveDocument.Tables(1)
'''),
        throwsA(_error('vba_type_error')),
      );
    });

    for (final source in <String>[
      'ActiveDocument.Paragraphs(1).Range',
      'ActiveDocument.Sections(1).Headers(1).Range',
    ]) {
      test(
        'a generic Range helper refuses actual non-cell selector $source',
        () {
          expect(
            () => _source('''
Sub Main()
Call Fill($source)
End Sub
Sub Fill(ByVal selected As Range)
selected.Text = "x"
End Sub
'''),
            throwsA(_error('vba_unsupported')),
          );
        },
      );
    }

    test(
      'paragraph-only aliases cannot gain Text even through unused paths',
      () {
        expect(
          () => _compile('''
Dim original As Range
Dim copy As Range
Set original = ActiveDocument.Paragraphs(1).Range
Set copy = original
If False Then
  With copy
    .Text = "x"
  End With
End If
'''),
          throwsA(_error('vba_unsupported')),
        );
      },
    );

    test('mixed cell/paragraph aliases do not promote paragraph marks', () {
      expect(
        () => _compile('''
Dim target As Range
Set target = ActiveDocument.Tables(1).Cell(1,1).Range
If False Then
  Set target = ActiveDocument.Paragraphs(1).Range
End If
target.Text = "x"
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    for (final statement in <String>[
      'selected.ListFormat.ApplyBulletDefault',
      'selected.InsertAfter "x"',
      'selected.Paragraphs(1).Range.InsertAfter "x"',
    ]) {
      test('a generic Range cannot escape its cell target: $statement', () {
        expect(
          () => _compile('''
Dim selected As Range
Set selected = $_target
$statement
'''),
          throwsA(_error('vba_unsupported')),
        );
      });
    }

    test('unbound Table and Cell variables cannot fabricate selectors', () {
      expect(
        () => _compile('''
Dim selected As Table
selected.Cell(1,1).Range.Text = "x"
'''),
        throwsA(_error('vba_unsupported')),
      );
      expect(
        () => _compile('''
Dim selected As Cell
selected.Range.Text = "x"
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('object aliases cannot bind another Word object type', () {
      expect(
        () => _compile('''
Dim selected As Table
Set selected = ActiveDocument.Paragraphs(1)
'''),
        throwsA(_error('vba_type_error')),
      );
      expect(
        () => _compile('''
Dim selected As Cell
Set selected = ActiveDocument.Tables(1)
'''),
        throwsA(_error('vba_type_error')),
      );
    });
  });

  group('dialect-scoped Word names', () {
    for (final language in <String>['vba-excel', 'vba-powerpoint']) {
      test('Tables/Table/Cell remain ordinary identifiers in $language', () {
        final plan = OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: language,
            format: language == 'vba-excel'
                ? OfficeMacroFormat.xlsx
                : OfficeMacroFormat.pptx,
            source: '''
Sub Main()
Dim Tables As Long, Table As Long, Cell As Long
Tables = 1
Table = 2
Cell = Tables + Table
End Sub
''',
          ),
        );
        expect(plan.steps, isEmpty);
      });
    }
  });

  group('shared native emission boundaries', () {
    test('cell text writes do not complete pending paragraph line spacing', () {
      expect(
        () => _compile('''
ActiveDocument.Paragraphs(1).Range.ParagraphFormat.LineSpacingRule = wdLineSpaceExactly
$_target.Text = "x"
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('repeated text publication charges shared work', () {
      expect(
        () => _compile('''
Dim index As Long
Dim label As String
label = String(30000, "x")
For index = 1 To 10
  $_target.Text = label
Next index
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });

    test('the native cell write operation limit applies through aliases', () {
      expect(
        () => _compile('''
Dim selected As Range
Dim index As Long
Set selected = $_target
For index = 1 To 10001
  selected.Text = ""
Next index
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  });
}
