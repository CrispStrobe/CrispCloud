import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _ns =
    'xmlns:office="$_office" xmlns:text="$_text" xmlns:table="$_table" '
    'xmlns:style="$_style" xmlns:fo="$_fo"';

// Independent packages exercise real style inheritance, not writer output.
Uint8List _input({
  String defaults = '',
  String parent = '',
  String child = '',
  String? second,
  bool merged = false,
  String covered = '',
  String rowAttributes = '',
  String columnAttributes = '',
}) {
  String cellStyle(String name, String properties, {String? parentName}) =>
      '<style:style style:name="$name" style:family="table-cell" '
      '${parentName == null ? '' : 'style:parent-style-name="$parentName"'}>'
      '<style:table-cell-properties $properties/></style:style>';
  final zip = ZipWriter();
  zip.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  zip.addFile(
    'styles.xml',
    utf8.encode(
      '<office:document-styles $_ns><office:styles>'
      '<style:default-style style:family="table-cell">'
      '<style:table-cell-properties $defaults/></style:default-style>'
      '${cellStyle('Parent', parent)}'
      '${cellStyle('Unused', 'fo:padding="invalid"')}'
      '</office:styles></office:document-styles>',
    ),
  );
  zip.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content $_ns><office:automatic-styles>'
      '${cellStyle('Child', child, parentName: 'Parent')}'
      '${cellStyle('Second', second ?? child, parentName: 'Parent')}'
      '${cellStyle('Covered', covered)}'
      '<style:style style:name="Column" style:family="table-column">'
      '<style:table-column-properties style:column-width="240pt"/>'
      '</style:style></office:automatic-styles><office:body><office:text>'
      '<table:table><table:table-column table:style-name="Column" '
      'table:number-columns-repeated="2" $columnAttributes/>'
      '<table:table-row $rowAttributes>'
      '<table:table-cell table:style-name="Child" '
      '${merged ? 'table:number-columns-spanned="2"' : ''}>'
      '<text:p>First cell</text:p></table:table-cell>'
      '${merged ? '<table:covered-table-cell table:style-name="Covered"/>' : '<table:table-cell table:style-name="Second"><text:p>Second cell</text:p></table:table-cell>'}'
      '</table:table-row></table:table>'
      '</office:text></office:body></office:document-content>',
    ),
  );
  return zip.close();
}

Iterable<WmlTable> _tables(Iterable<WmlBlock> blocks) sync* {
  for (final block in blocks) {
    if (block is WmlTable) {
      yield block;
      for (final row in block.rows) {
        for (final cell in row.cells) {
          yield* _tables(cell.blocks);
        }
      }
    }
  }
}

WmlParagraph _cited(String id) {
  final p = WmlParagraph(inlines: [WmlRun(text: 'Before ')]);
  WordZotero.insertCitation(
    p,
    ZoteroCitation.fromJson({
      'citationID': id,
      'citationItems': [
        {
          'id': 'http://zotero.org/users/42/items/ABCD1234',
          'uris': ['http://zotero.org/users/42/items/ABCD1234'],
          'locator': '7–9',
          'prefix': 'see ',
          'future': {'keep': true},
        },
      ],
      'properties': {'plainCitation': '(Source $id)'},
    }),
  );
  return p;
}

WmlDocument _document(double margin) => WmlDocument(
  zoteroDocumentData: jsonEncode({
    'dataVersion': 4,
    'style': {'styleID': 'http://www.zotero.org/styles/apa'},
    'prefs': {'fieldType': 'Field', 'noteType': 0},
  }),
  sections: [
    WmlSection(
      blocks: [
        WmlTable(
          grid: [240, 120],
          properties: WmlTableProps(borders: false, cellMargin: margin),
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(
                  width: 360,
                  gridSpan: 2,
                  vMerge: WmlVMerge.restart,
                  blocks: [_cited('merged')],
                ),
              ],
            ),
            WmlTableRow(
              cells: [
                WmlTableCell(
                  width: 360,
                  gridSpan: 2,
                  vMerge: WmlVMerge.cont,
                  blocks: [WmlParagraph()],
                ),
              ],
            ),
            WmlTableRow(
              cells: [
                WmlTableCell(
                  width: 240,
                  blocks: [
                    WmlTable(
                      grid: [96],
                      properties: WmlTableProps(borders: false, cellMargin: 3),
                      rows: [
                        WmlTableRow(
                          cells: [
                            WmlTableCell(width: 96, blocks: [_cited('nested')]),
                          ],
                        ),
                      ],
                    ),
                    WmlParagraph(),
                  ],
                ),
                WmlTableCell(width: 120, blocks: [WmlParagraph()]),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  final cases =
      <
        ({
          String name,
          String defaults,
          String parent,
          String child,
          double expected,
        })
      >[
        (
          name: 'absent padding stays zero',
          defaults: '',
          parent: '',
          child: '',
          expected: 0,
        ),
        (
          name: 'family default is inherited',
          defaults: 'fo:padding="3pt"',
          parent: '',
          child: '',
          expected: 3,
        ),
        (
          name: 'parent shorthand is inherited',
          defaults: '',
          parent: 'fo:padding="6pt"',
          child: '',
          expected: 6,
        ),
        (
          name: 'child shorthand resets parent sides',
          defaults: '',
          parent: 'fo:padding-left="9pt"',
          child: 'fo:padding="4pt"',
          expected: 4,
        ),
        (
          name: 'explicit zero resets positive parent',
          defaults: '',
          parent: 'fo:padding="6pt"',
          child: 'fo:padding="0pt"',
          expected: 0,
        ),
        (
          name: 'sides override same-layer shorthand',
          defaults: '',
          parent: '',
          child:
              'fo:padding-top="3pt" fo:padding-right="3pt" fo:padding-bottom="3pt" fo:padding-left="3pt" fo:padding="9pt"',
          expected: 3,
        ),
        (
          name: 'mixed units resolve to equal sides',
          defaults: '',
          parent: '',
          child:
              'fo:padding-top="1in" fo:padding-right="72pt" fo:padding-bottom="2.54cm" fo:padding-left="25.4mm"',
          expected: 72,
        ),
      ];
  for (final c in cases) {
    test(c.name, () async {
      final document = await OdtDocumentReader.readBytes(
        _input(defaults: c.defaults, parent: c.parent, child: c.child),
      );
      final table = _tables(document.sections.single.blocks).single;
      expect(table.properties.cellMargin, closeTo(c.expected, 0.000001));
      expect(
        table.rows.single.cells.map(
          (cell) => cell.blocks.whereType<WmlParagraph>().single.text,
        ),
        ['First cell', 'Second cell'],
      );
    });
  }

  test('merged cells admit absent or matching covered padding', () async {
    for (final covered in [
      '',
      'fo:padding="6pt"',
      'fo:padding="6pt" fo:border="none"',
    ]) {
      final document = await OdtDocumentReader.readBytes(
        _input(child: 'fo:padding="6pt"', merged: true, covered: covered),
      );
      final table = _tables(document.sections.single.blocks).single;
      expect(table.properties.cellMargin, 6);
      expect(table.rows.single.cells.single.gridSpan, 2);
      expect(table.rows.single.cells.single.width, 480);
    }
  });

  test('LibreOffice inert border declarations retain uniform padding', () async {
    final document = await OdtDocumentReader.readBytes(
      _input(
        defaults: 'fo:border="none"',
        child:
            'fo:padding="6pt" fo:border-top="none" fo:border-right="none" fo:border-bottom="none" fo:border-left="none"',
      ),
    );
    final table = _tables(document.sections.single.blocks).single;
    expect(table.properties.borders, isFalse);
    expect(table.properties.cellMargin, 6);
  });

  final refusals = <String, Uint8List Function()>{
    'visible side beside inert border': () => _input(
      child:
          'fo:padding="6pt" fo:border="none" fo:border-left="1pt solid #000000"',
    ),
    'asymmetric effective sides': () =>
        _input(parent: 'fo:padding="3pt"', child: 'fo:padding-left="6pt"'),
    'different visible cells': () =>
        _input(child: 'fo:padding="3pt"', second: 'fo:padding="6pt"'),
    'authored versus absent padding': () =>
        _input(child: 'fo:padding="3pt"', second: ''),
    'mismatching covered override': () => _input(
      child: 'fo:padding="6pt"',
      merged: true,
      covered: 'fo:padding="3pt"',
    ),
    'mismatching covered default': () => _input(
      defaults: 'fo:padding="3pt"',
      child: 'fo:padding="6pt"',
      merged: true,
    ),
    'padding consumes the cell': () => _input(child: 'fo:padding="120pt"'),
    'padding exceeds Word storage': () => _input(child: 'fo:padding="2000pt"'),
    'unmodeled row default': () =>
        _input(rowAttributes: 'table:default-cell-style-name="Child"'),
    'unmodeled column default': () =>
        _input(columnAttributes: 'table:default-cell-style-name="Child"'),
    for (final invalid in [
      '-1pt',
      '5%',
      'auto',
      'inherit',
      '2pt 4pt',
      'NaNpt',
      'Infinitypt',
      '5000pt',
    ])
      'invalid length $invalid': () => _input(child: 'fo:padding="$invalid"'),
  };
  for (final entry in refusals.entries) {
    test('refuses ${entry.key} without changing input', () async {
      final bytes = entry.value();
      final before = Uint8List.fromList(bytes);
      await expectLater(
        OdtDocumentReader.readBytes(bytes),
        throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())),
      );
      expect(bytes, before);
    });
  }

  for (final margin in [0.0, 6.0, 12.0]) {
    test(
      'editable fields and independent nested padding survive $margin pt cycles',
      () async {
        final original = _document(margin);
        final expected = WordZotero.fields(
          original,
        ).map((field) => field.citation!.toJson()).toList();
        var document = original;
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
          final content = OpcPackage.openBytes(
            bytes,
          ).getPart('/content.xml')!.readText();
          expect(content, contains('fo:padding='));
          document = await OdtDocumentReader.readBytes(bytes);
          final tables = _tables(document.sections.single.blocks).toList();
          expect(tables.map((table) => table.properties.cellMargin), [
            margin,
            3,
          ]);
          expect(tables.first.rows.first.cells.single.gridSpan, 2);
          expect(tables.first.rows[1].cells.single.vMerge, WmlVMerge.cont);
          final fields = WordZotero.fields(document);
          expect(fields.map((field) => field.citation!.toJson()), expected);
          expect(fields.every((field) => field.canEdit), isTrue);
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expect(
            _tables(
              document.sections.single.blocks,
            ).map((table) => table.properties.cellMargin),
            [margin, 3],
          );
        }
        expect(
          _tables(
            original.sections.single.blocks,
          ).map((table) => table.properties.cellMargin),
          [margin, 3],
        );
        expect(
          WordZotero.fields(original).map((field) => field.citation!.toJson()),
          expected,
        );
      },
    );
  }

  test(
    'export validates merged width rather than each constituent column',
    () async {
      final document = _document(40);
      document.sections.single.blocks
        ..clear()
        ..add(
          WmlTable(
            grid: [60, 60],
            properties: WmlTableProps(borders: false, cellMargin: 40),
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    width: 120,
                    gridSpan: 2,
                    blocks: [_cited('span')],
                  ),
                ],
              ),
            ],
          ),
        );
      final reopened = await OdtDocumentReader.readBytes(
        OdtDocumentWriter.writeEditableZoteroBytes(document),
      );
      final table = reopened.sections.single.blocks
          .whereType<WmlTable>()
          .single;
      expect(table.properties.cellMargin, 40);
      expect(table.rows.single.cells.single.gridSpan, 2);
      expect(WordZotero.fields(reopened).single.canEdit, isTrue);
    },
  );

  test('export refuses a positive column that rounds to zero', () {
    final document = _document(0);
    final table = document.sections.single.blocks.whereType<WmlTable>().single;
    table.grid[1] = 0.004;
    expect(
      () => OdtDocumentWriter.writeEditableZoteroBytes(document),
      throwsArgumentError,
    );
    expect(table.grid[1], 0.004);
  });

  test('export refuses exhausted decimal width after a larger column', () {
    final document = _document(0.01);
    final table = document.sections.single.blocks.whereType<WmlTable>().single;
    table.grid[1] = 0.02;
    expect(
      () => OdtDocumentWriter.writeEditableZoteroBytes(document),
      throwsArgumentError,
    );
    expect(table.grid, [240, 0.02]);
    expect(table.properties.cellMargin, 0.01);
  });

  for (final margin in [
    -1.0,
    double.nan,
    double.infinity,
    2000.0,
    60.0,
    61.0,
    59.999,
  ]) {
    test('explicit exporter refuses invalid native margin $margin', () {
      final document = _document(margin);
      final expected = WordZotero.fields(
        document,
      ).map((field) => field.instruction).toList();
      expect(
        () => OdtDocumentWriter.writeEditableZoteroBytes(document),
        throwsArgumentError,
      );
      expect(
        WordZotero.fields(document).map((field) => field.instruction),
        expected,
      );
    });
  }
}
