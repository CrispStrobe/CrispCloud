import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _project = <int>[0, 1, 7, 255, 78, 65, 86];

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'TableNavigationIntegration',
    source: source,
  ),
);

OfficeMacro _compile(String body) =>
    _source('Option Explicit\nSub Main()\n$body\nEnd Sub');

WmlParagraph _paragraph(String text) => WmlParagraph(
  properties: WmlParagraphProps(spacingAfter: 3),
  inlines: [
    WmlRun(
      text: text,
      properties: WmlRunProps(
        italic: true,
        color: '123456',
        asciiFont: 'Georgia',
        fontSizeHalfPoints: 26,
      ),
    ),
  ],
);

WmlTable _table(String label, int rows, int columns) => WmlTable(
  grid: [for (var column = 0; column < columns; column++) 80.0 + column * 10],
  properties: WmlTableProps(cellMargin: 5, borderColor: '334455'),
  rows: [
    for (var row = 0; row < rows; row++)
      WmlTableRow(
        cantSplit: true,
        height: 20,
        cells: [
          for (var column = 0; column < columns; column++)
            WmlTableCell(
              width: 80.0 + column * 10,
              fillColor: 'EAF1F8',
              borderTop: true,
              blocks: [_paragraph('$label:${row + 1},${column + 1}')],
            ),
        ],
      ),
  ],
);

WmlDocument _document() => WmlDocument(
  sections: [
    WmlSection(
      blocks: [_paragraph('Introduction'), _table('A', 2, 3)],
      header: [_paragraph('Header stays separate')],
      footer: [_paragraph('Footer stays separate')],
      linkToPrevious: false,
    ),
    WmlSection(
      blocks: [_paragraph('Second section'), _table('B', 2, 2)],
      linkToPrevious: false,
    ),
  ],
);

List<WmlTable> _tables(WmlDocument document) => [
  for (final section in document.sections)
    ...section.blocks.whereType<WmlTable>(),
];

WmlParagraph _cell(WmlDocument document, int table, int row, int column) =>
    _tables(document)[table].rows[row].cells[column].blocks.single
        as WmlParagraph;

Uint8List _input({bool macroEnabled = false, WmlDocument? document}) {
  final package = OpcPackage.openBytes(
    WordSerializer().writeBytes(document ?? _document()),
  );
  package.createPart(
    '/customXml/navigation.xml',
    'application/xml',
    Uint8List.fromList(utf8.encode('<retained token="navigation"/>')),
  );
  if (macroEnabled) {
    const type = 'application/vnd.ms-word.document.macroEnabled.main+xml';
    package.getPart('/word/document.xml')!.contentType = type;
    package.contentTypes.setOverride('/word/document.xml', type);
    package.createPart(
      '/word/vbaProject.bin',
      'application/vnd.ms-office.vbaProject',
      Uint8List.fromList(_project),
    );
    package
        .relationshipsFor('/word/document.xml')
        .add(
          type:
              'http://schemas.microsoft.com/office/2006/relationships/vbaProject',
          target: 'vbaProject.bin',
        );
  }
  // Establish an ordinary native save as the preservation baseline.
  return WordSerializer().writeBytes(
    WordDeserializer().readBytes(package.save()),
  );
}

List<XmlElement> _elements(XmlElement root, String name) => [
  for (final child in root.childElements) ...[
    if (child.namespaceUri == _w && child.localName == name) child,
    ..._elements(child, name),
  ],
];

Object _xml(XmlNode node) => switch (node) {
  XmlElement() => {
    'name': [node.namespaceUri, node.localName],
    'attributes': {
      for (final attribute in node.attributes.where(
        (attribute) =>
            attribute.prefix != 'xmlns' && attribute.qualifiedName != 'xmlns',
      ))
        '${attribute.namespaceUri}:${attribute.localName}': attribute.value,
    },
    'children': [for (final child in node.children) _xml(child)],
  },
  XmlText() => {'text': node.text},
  XmlCdata() => {'cdata': node.text},
  XmlComment() => {'comment': node.text},
};

Object _metadata(String source) {
  final root = XmlDocument.parse(source).root!;
  for (final modified in root.childrenNamed(
    'modified',
    namespaceUri: 'http://purl.org/dc/terms/',
  )) {
    expect(DateTime.tryParse(modified.text), isNotNull);
    modified.children.clear();
    modified.addText('save timestamp');
  }
  return _xml(root);
}

// Ignore only the selected cells' paragraph contents. Cell properties,
// neighbors, section/body/header/footer structure and all package parts stay
// in the independent preservation comparison.
Object _untouched(Uint8List bytes, Set<int> editedCells) {
  final package = OpcPackage.openBytes(bytes);
  final root = XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!;
  final cells = _elements(root, 'tc');
  for (final index in editedCells) {
    cells[index].children.removeWhere(
      (node) =>
          node is XmlElement &&
          node.namespaceUri == _w &&
          node.localName == 'p',
    );
  }
  return {
    'document': _xml(root),
    'parts': {
      for (final part in package.parts)
        if (part.uri != '/word/document.xml')
          part.uri: part.uri == '/docProps/core.xml'
              ? _metadata(package.getPart(part.uri)!.readText())
              : base64Encode(package.getPart(part.uri)!.readBytes()),
    },
  };
}

List<String> _texts(Uint8List bytes) => [
  for (final table in _tables(WordDeserializer().readBytes(bytes)))
    for (final row in table.rows)
      for (final cell in row.cells) (cell.blocks.single as WmlParagraph).text,
];

const _report = '''
Option Explicit
Sub Main()
  Dim allTables As Tables
  Dim selectedTable As Table
  Dim allRows As Rows, selectedRow As Row
  Dim allColumns As Columns, selectedColumn As Column
  Dim selectedCells As Cells, selectedCell As Cell
  Dim saved As Range
  Set allTables = ActiveDocument.Tables
  Set selectedTable = allTables.Item(Index:=1)
  Set allRows = selectedTable.Rows
  Set selectedRow = allRows.Item(Index:=2)
  Set selectedCells = selectedRow.Cells
  Set selectedCell = selectedCells.Item(Index:=3)
  Set saved = selectedCell.Range
  saved.Text = "Row-selected"
  Set allColumns = selectedTable.Columns
  Set selectedColumn = allColumns.Item(Index:=2)
  Set selectedCells = selectedColumn.Cells
  selectedCells.Item(Index:=1).Range.InsertAfter Text:="-Column-selected"
  Call Decorate(target:=selectedTable.Columns(3).Cells(1).Range)
  Set selectedTable = allTables.Item(2)
  allRows.Item(1).Cells(1).Range.InsertBefore "Original-"
  Set allColumns = selectedTable.Columns
  allColumns.Item(2).Cells(1).Range.Text = "Second table"
  saved.InsertAfter "-Saved"
End Sub
Sub Decorate(ByVal target As Range)
  target.Font.Bold = True
  target.ParagraphFormat.Alignment = wdAlignParagraphRight
End Sub
''';

const _expected = <String>[
  'Original-A:1,1',
  'A:1,2-Column-selected',
  'A:1,3',
  'A:2,1',
  'A:2,2',
  'Row-selected-Saved',
  'B:1,1',
  'Second table',
  'B:2,1',
  'B:2,2',
];

void _assertReport(Uint8List bytes) {
  expect(_texts(bytes), _expected);
  final document = WordDeserializer().readBytes(bytes);
  final formatted = _cell(document, 0, 0, 2);
  expect(formatted.properties.justification, WmlJustification.right);
  expect(formatted.properties.spacingAfter, 3);
  expect(
    formatted.inlines.whereType<WmlRun>().every((run) => run.properties.bold),
    isTrue,
  );
  for (final table in _tables(document)) {
    for (final row in table.rows) {
      for (final cell in row.cells) {
        final paragraph = cell.blocks.single as WmlParagraph;
        for (final run in paragraph.inlines.whereType<WmlRun>()) {
          expect(run.properties.italic, isTrue);
          expect(run.properties.color, '123456');
          expect(run.properties.asciiFont, 'Georgia');
          expect(run.properties.fontSizeHalfPoints, 26);
        }
      }
    }
  }
}

void main() {
  test(
    'row and column navigation lower to independently expected coordinates',
    () {
      final plan = _source(_report);
      expect(plan.steps.map((step) => step.toJson()), [
        {
          'tool': 'docx.tableCellRangeText',
          'arguments': {
            'table': 0,
            'row': 1,
            'column': 2,
            'text': 'Row-selected',
          },
        },
        {
          'tool': 'docx.tableCellRangeInsertAfter',
          'arguments': {
            'table': 0,
            'row': 0,
            'column': 1,
            'text': '-Column-selected',
          },
        },
        {
          'tool': 'docx.runFormat',
          'arguments': {
            'paragraph': 0,
            'story': 'tableCell',
            'table': 0,
            'row': 0,
            'column': 2,
            'bold': true,
          },
        },
        {
          'tool': 'docx.paragraphFormat',
          'arguments': {
            'paragraph': 0,
            'story': 'tableCell',
            'table': 0,
            'row': 0,
            'column': 2,
            'alignment': 'right',
          },
        },
        {
          'tool': 'docx.tableCellRangeInsertBefore',
          'arguments': {'table': 0, 'row': 0, 'column': 0, 'text': 'Original-'},
        },
        {
          'tool': 'docx.tableCellRangeText',
          'arguments': {
            'table': 1,
            'row': 0,
            'column': 1,
            'text': 'Second table',
          },
        },
        {
          'tool': 'docx.tableCellRangeInsertAfter',
          'arguments': {'table': 0, 'row': 1, 'column': 2, 'text': '-Saved'},
        },
      ]);
      expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
    },
  );

  for (final macroEnabled in [false, true]) {
    test(
      '${macroEnabled ? 'DOCM' : 'DOCX'} navigation previews, saves, reopens and records exactly',
      () async {
        final input = _input(macroEnabled: macroEnabled);
        const edited = {0, 1, 2, 5, 7};
        final preserved = _untouched(input, edited);
        final plan = _source(_report);
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        final preview = await session.validate(plan);
        expect(preview.validatedOnly, isTrue);
        expect(preview.completedSteps, 7);
        expect(session.bytes, input);
        expect(session.revision, 0);
        await session.run(OfficeMacro.parse(plan.encode()));
        expect(session.revision, 1);
        var saved = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          _assertReport(saved);
          expect(_untouched(saved, edited), preserved);
          if (macroEnabled) {
            expect(
              OpcPackage.openBytes(
                saved,
              ).getPart('/word/vbaProject.bin')!.readBytes(),
              _project,
            );
          }
          saved = WordSerializer().writeBytes(
            WordDeserializer().readBytes(saved),
          );
        }
        final recorder = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        )..startRecording('Navigation report');
        for (final step in plan.steps) {
          await recorder.callTool(step.tool, step.arguments);
        }
        final recording = recorder.stopRecording();
        expect(
          recording.steps.map((step) => step.toJson()),
          plan.steps.map((step) => step.toJson()),
        );
        final replay = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        await replay.run(OfficeMacro.parse(recording.encode()));
        _assertReport(replay.bytes);
        expect(_untouched(replay.bytes, edited), preserved);
      },
    );
  }

  test(
    'nested With and a rooted Range alias cycle retain the selected cell',
    () async {
      final plan = _compile('''
Dim first As Range, second As Range
With ActiveDocument.Tables(Index:=1)
  With .Columns
    With .Item(Index:=3)
      With .Cells
        With .Item(Index:=2)
          Set first = .Range
        End With
      End With
    End With
  End With
End With
Set second = first
Set first = second
second.InsertAfter "-cycle"
''');
      final input = _input();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(plan);
      final expected = _texts(input)..[5] = 'A:2,3-cycle';
      expect(_texts(session.bytes), expected);
      expect(_untouched(session.bytes, {5}), _untouched(input, {5}));
    },
  );

  test(
    'ByVal row, column and cell collection rebinding leaves caller identities intact',
    () async {
      final plan = _source('''
Option Explicit
Sub Main()
  Dim rowSelection As Row, columnSelection As Column, cellSelection As Cells
  Set rowSelection = ActiveDocument.Tables(1).Rows(2)
  Set columnSelection = ActiveDocument.Tables(1).Columns(3)
  Set cellSelection = columnSelection.Cells
  Call Rebind(selectedRow:=rowSelection, selectedColumn:=columnSelection, selectedCells:=cellSelection)
  rowSelection.Cells(1).Range.Text = "Caller row"
  columnSelection.Cells(1).Range.Text = "Caller column"
  cellSelection.Item(2).Range.InsertAfter "-Caller cells"
End Sub
Sub Rebind(ByVal selectedRow As Row, ByVal selectedColumn As Column, ByVal selectedCells As Cells)
  Set selectedRow = ActiveDocument.Tables(2).Rows(1)
  Set selectedColumn = ActiveDocument.Tables(2).Columns(2)
  Set selectedCells = selectedRow.Cells
  selectedRow.Cells(1).Range.Text = "Helper row"
  selectedColumn.Cells(2).Range.Text = "Helper column"
  selectedCells.Item(2).Range.Text = "Helper cells"
End Sub
''');
      final input = _input();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(plan);
      expect(_texts(session.bytes), [
        'A:1,1',
        'A:1,2',
        'Caller column',
        'Caller row',
        'A:2,2',
        'A:2,3-Caller cells',
        'Helper row',
        'Helper cells',
        'B:2,1',
        'Helper column',
      ]);
      expect(
        _untouched(session.bytes, {2, 3, 5, 6, 7, 9}),
        _untouched(input, {2, 3, 5, 6, 7, 9}),
      );
    },
  );

  test(
    'a shared Range helper keeps body, header and selected cell stories separate',
    () async {
      final plan = _source('''
Sub Main()
  FormatRange ActiveDocument.Paragraphs(1).Range
  FormatRange ActiveDocument.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range
  FormatRange ActiveDocument.Tables(1).Rows(2).Cells(2).Range
End Sub
Sub FormatRange(ByVal target As Range)
  target.Font.Bold = True
End Sub
''');
      expect(plan.steps.map((step) => step.arguments['story']), [
        null,
        'header',
        'tableCell',
      ]);
      final input = _input();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      await session.run(plan);
      final output = WordDeserializer().readBytes(session.bytes);
      for (final paragraph in [
        output.sections.first.blocks.first as WmlParagraph,
        output.sections.first.header.single,
        _cell(output, 0, 1, 1),
      ]) {
        expect(
          paragraph.inlines.whereType<WmlRun>().single.properties.bold,
          isTrue,
        );
      }
      expect(
        _cell(
          output,
          0,
          0,
          0,
        ).inlines.whereType<WmlRun>().single.properties.bold,
        isFalse,
      );
      expect(
        output.sections.first.footer.single.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .bold,
        isFalse,
      );
      expect(_texts(session.bytes), _texts(input));
    },
  );

  for (final selector in [
    'ActiveDocument.Tables(1).Rows(3).Cells(1)',
    'ActiveDocument.Tables(1).Columns(4).Cells(1)',
    'ActiveDocument.Tables(2).Rows(1).Cells(3)',
    'ActiveDocument.Tables(2).Columns(1).Cells(3)',
  ]) {
    test(
      'late missing selector $selector rolls back preview, execution and recording',
      () async {
        final input = _input();
        final plan = _compile('''
ActiveDocument.Tables(1).Columns(2).Cells(1).Range.InsertAfter "-Discard"
$selector.Range.Text = "Missing"
''');
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        )..startRecording('Refused navigation');
        for (final action in [session.validate, session.run]) {
          await expectLater(
            action(plan),
            throwsA(
              isA<OfficeMacroException>()
                  .having((error) => error.stepIndex, 'failing step', 1)
                  .having(
                    (error) => error.tool,
                    'failing tool',
                    'docx.tableCellRangeText',
                  ),
            ),
          );
          expect(session.bytes, input);
          expect(session.revision, 0);
        }
        expect(session.stopRecording().steps, isEmpty);
      },
    );
  }

  for (final shape in ['merged', 'nested']) {
    test(
      '$shape tables remain guarded through row and column aliases',
      () async {
        final document = _document();
        final table = _tables(document).first;
        if (shape == 'merged') {
          WordTable.merge(table, 0, 0, 0, 1);
          expect(table.rows.first.cells.length, 2);
        } else {
          table.rows.first.cells.first.blocks.add(_table('nested', 1, 1));
        }
        final input = _input(document: document);
        final plan = _compile('''
Dim selectedRows As Rows, selectedColumns As Columns
Set selectedRows = ActiveDocument.Tables(1).Rows
Set selectedColumns = ActiveDocument.Tables(1).Columns
selectedRows.Item(1).Cells(1).Range.Text = "Refused"
selectedColumns.Item(1).Cells(1).Range.InsertAfter "Refused"
''');
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        )..startRecording('Guarded navigation');
        await expectLater(
          session.run(plan),
          throwsA(isA<OfficeMacroException>()),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
        expect(session.stopRecording().steps, isEmpty);
      },
    );
  }

  for (final selector in [
    'ActiveDocument.Paragraphs(1).Range',
    'ActiveDocument.Sections(1).Headers(wdHeaderFooterPrimary).Range.Paragraphs(1).Range',
  ]) {
    test('cell-only helper refuses a later non-cell selector $selector', () {
      expect(
        () => _source('''
Sub Main()
  AppendToCell ActiveDocument.Tables(1).Rows(1).Cells(1).Range
  AppendToCell $selector
End Sub
Sub AppendToCell(ByVal target As Range)
  target.InsertAfter "-cell"
End Sub
'''),
        throwsA(isA<OfficeVbaCompileException>()),
      );
    });
  }

  test(
    'a mixed local origin cannot acquire cell-only insertion through a navigation alias',
    () {
      expect(
        () => _compile('''
Dim selected As Range, copied As Range
Set selected = ActiveDocument.Tables(1).Columns(1).Cells(1).Range
Set copied = selected
Set selected = copied
If False Then
  Set selected = ActiveDocument.Paragraphs(1).Range
End If
copied.InsertAfter "-refused"
'''),
        throwsA(isA<OfficeVbaCompileException>()),
      );
    },
  );

  test(
    'typed navigation does not grant an unapproved formatting capability',
    () async {
      final input = _input();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: OfficeMacroPolicy(allowedTools: {'docx.tableCellRangeText'}),
      )..startRecording('Denied formatting');
      final plan = _compile('''
ActiveDocument.Tables(1).Rows(1).Cells(1).Range.Text = "Discard"
ActiveDocument.Tables(1).Columns(1).Cells(2).Range.Font.Bold = True
''');
      await expectLater(
        session.run(plan),
        throwsA(isA<OfficeMacroException>()),
      );
      expect(session.bytes, input);
      expect(session.revision, 0);
      expect(session.stopRecording().steps, isEmpty);
    },
  );
}
