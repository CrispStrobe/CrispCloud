import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument tableDoc() {
  return WmlDocument(
    sections: <WmlSection>[
      WmlSection(
        blocks: <WmlBlock>[
          WmlTable(
            grid: <double>[120, 120],
            rows: <WmlTableRow>[
              WmlTableRow(
                cells: <WmlTableCell>[
                  WmlTableCell(
                    blocks: <WmlBlock>[
                      WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'A1')]),
                    ],
                  ),
                  WmlTableCell(
                    blocks: <WmlBlock>[
                      WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'B1')]),
                    ],
                  ),
                ],
              ),
              WmlTableRow(
                cells: <WmlTableCell>[
                  WmlTableCell(
                    blocks: <WmlBlock>[
                      WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'A2')]),
                    ],
                  ),
                  WmlTableCell(
                    blocks: <WmlBlock>[
                      WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'B2')]),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  test('locationOfIndex finds the caret cell', () {
    final WmlDocument doc = tableDoc();
    final List<WmlParagraph> paras = doc.paragraphs.toList();
    expect(paras.length, 4);
    final ({WmlTable table, int row, int col})? loc = WordTable.locationOfIndex(
      doc,
      3,
    );
    expect(loc, isNotNull);
    expect(loc!.row, 1);
    expect(loc.col, 1);
    expect(paras[3].text, 'B2');
  });

  test('insertRow adds an empty row and keeps column count', () {
    final WmlDocument doc = tableDoc();
    final WmlTable table = doc.sections.first.blocks.first as WmlTable;
    WordTable.insertRow(table, 1);
    expect(table.rows.length, 3);
    expect(table.rows[1].cells.length, 2);
    expect((table.rows[1].cells.first.blocks.first as WmlParagraph).text, '');
    expect((table.rows[2].cells.first.blocks.first as WmlParagraph).text, 'A2');
  });

  test('insertColumn copies the previous column formatting', () {
    final WmlDocument doc = tableDoc();
    final WmlTable table = doc.sections.first.blocks.first as WmlTable;
    table.rows.first.cells.first.fillColor = '1F4E79';
    table.rows.first.cells.first.blocks
            .whereType<WmlParagraph>()
            .first
            .inlines
            .whereType<WmlRun>()
            .first
            .properties
            .bold =
        true;
    WordTable.insertColumn(table, 1);
    expect(table.rows.first.cells[1].fillColor, '1F4E79');
    expect(
      table.rows.first.cells[1].blocks
          .whereType<WmlParagraph>()
          .first
          .inlines
          .whereType<WmlRun>()
          .first
          .properties
          .bold,
      isTrue,
    );
    expect((table.rows.first.cells[1].blocks.first as WmlParagraph).text, '');
    expect((table.rows.first.cells[2].blocks.first as WmlParagraph).text, 'B1');
  });

  test('autoFit window keeps the table inside the page width', () {
    final WmlDocument doc = tableDoc();
    final WmlTable table = doc.sections.first.blocks.first as WmlTable;
    table.grid
      ..clear()
      ..addAll(<double>[200, 200, 200]);
    WordTable.insertColumn(table, 1);
    WordTable.constrainToWidth(table, 400);
    expect(WordTable.gridWidth(table), closeTo(400, 1));
  });

  test('insertColumn inserts at the boundary and grows the grid', () {
    final WmlDocument doc = tableDoc();
    final WmlTable table = doc.sections.first.blocks.first as WmlTable;
    WordTable.insertColumn(table, 1);
    expect(WordTable.columnCount(table), 3);
    expect(table.grid.length, 3);
    expect(table.rows.first.cells.length, 3);
    expect((table.rows.first.cells[2].blocks.first as WmlParagraph).text, 'B1');
  });

  test('deleteRow and deleteColumn refuse to remove the last axis', () {
    final WmlDocument doc = tableDoc();
    final WmlTable table = doc.sections.first.blocks.first as WmlTable;
    WordTable.deleteRow(table, 0);
    expect(table.rows.length, 1);
    WordTable.deleteRow(table, 0);
    expect(table.rows.length, 1);
    WordTable.deleteColumn(table, 0);
    expect(WordTable.columnCount(table), 1);
    WordTable.deleteColumn(table, 0);
    expect(WordTable.columnCount(table), 1);
  });

  test('clone keeps heading and table fill independent', () {
    final WmlParagraph heading = WmlParagraph(
      properties: WmlParagraphProps(headingLevel: 2, styleId: 'Heading2'),
      inlines: <WmlInline>[
        WmlRun(
          text: 'Tool map',
          properties: WmlRunProps(bold: true, color: '2B579A'),
        ),
      ],
    );
    final WmlTable table = WmlTable(
      grid: <double>[80],
      rows: <WmlTableRow>[
        WmlTableRow(
          cells: <WmlTableCell>[
            WmlTableCell(
              fillColor: '1F4E79',
              blocks: <WmlBlock>[
                WmlParagraph(
                  inlines: <WmlInline>[
                    WmlRun(
                      text: 'Surface',
                      properties: WmlRunProps(color: 'FFFFFF'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final WmlParagraph headingCopy = WmlClone.paragraph(heading);
    final WmlTable tableCopy = WmlClone.table(table);
    heading.properties.headingLevel = 1;
    table.rows.first.cells.first.fillColor = 'FF0000';
    expect(headingCopy.properties.headingLevel, 2);
    expect(headingCopy.properties.styleId, 'Heading2');
    expect(tableCopy.rows.first.cells.first.fillColor, '1F4E79');
    expect(
      (tableCopy.rows.first.cells.first.blocks.first as WmlParagraph).text,
      'Surface',
    );
  });

  test('canMerge is false for a single already-merged cell', () {
    final WmlDocument doc = tableDoc();
    final WmlTable table = doc.sections.first.blocks.first as WmlTable;
    WordTable.merge(table, 0, 0, 0, 1);
    expect(WordTable.canMerge(table, 0, 0, 0, 1), isFalse);
    expect(WordTable.canUnmerge(table, 0, 0), isTrue);
  });

  test('merge joins consecutive cells and unmerge splits them', () {
    final WmlDocument doc = tableDoc();
    final WmlTable table = doc.sections.first.blocks.first as WmlTable;
    expect(WordTable.canMerge(table, 0, 0, 0, 1), isTrue);
    WordTable.merge(table, 0, 0, 0, 1);
    expect(table.rows.first.cells.length, 1);
    expect(table.rows.first.cells.first.gridSpan, 2);
    expect(
      (table.rows.first.cells.first.blocks.first as WmlParagraph).text,
      'A1',
    );
    expect((table.rows.first.cells.first.blocks[1] as WmlParagraph).text, 'B1');
    expect(WordTable.canUnmerge(table, 0, 0), isTrue);
    WordTable.unmerge(table, 0, 0);
    expect(table.rows.first.cells.length, 2);
    expect(table.rows.first.cells.first.gridSpan, 1);
    expect(table.rows.first.cells[1].gridSpan, 1);
  });

  test('merge can span a rectangle vertically', () {
    final WmlDocument doc = tableDoc();
    final WmlTable table = doc.sections.first.blocks.first as WmlTable;
    WordTable.merge(table, 0, 0, 1, 0);
    expect(table.rows.first.cells.first.vMerge, WmlVMerge.restart);
    expect(table.rows[1].cells.first.vMerge, WmlVMerge.cont);
    WordTable.unmerge(table, 1, 0);
    expect(table.rows.first.cells.first.vMerge, WmlVMerge.none);
    expect(table.rows[1].cells.first.vMerge, WmlVMerge.none);
  });

  test('snapshot restore reverts an insert', () {
    final WmlDocument doc = tableDoc();
    final WmlTable table = doc.sections.first.blocks.first as WmlTable;
    final WmlTable snap = WordTable.snapshot(table);
    WordTable.insertRow(table, 0);
    expect(table.rows.length, 3);
    WordTable.restore(table, snap);
    expect(table.rows.length, 2);
    expect(
      (table.rows.first.cells.first.blocks.first as WmlParagraph).text,
      'A1',
    );
  });
}
