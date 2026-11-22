import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/zotero_converter_fixtures.dart';

const _ns =
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"';

Uint8List _input({
  String defaults = '',
  String parent = '',
  String child = '',
  String? second,
  String? borderModel = 'collapsing',
  bool merged = false,
  String covered = '',
}) {
  String style(String name, String properties, {String? parentName}) =>
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
      '<style:default-style style:family="table">'
      '<style:table-properties '
      '${borderModel == null ? '' : 'table:border-model="$borderModel"'}/>'
      '</style:default-style>${style('Parent', parent)}'
      '${style('Unused', 'fo:border="malformed"')}'
      '</office:styles></office:document-styles>',
    ),
  );
  zip.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content $_ns><office:automatic-styles>'
      '${style('Child', child, parentName: 'Parent')}'
      '${style('Second', second ?? child, parentName: 'Parent')}'
      '${style('Covered', covered)}'
      '<style:style style:name="Column" style:family="table-column">'
      '<style:table-column-properties style:column-width="120pt"/>'
      '</style:style></office:automatic-styles><office:body><office:text>'
      '<table:table><table:table-column table:style-name="Column" '
      'table:number-columns-repeated="2"/><table:table-row>'
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

List<bool> _sides(WmlTable table, WmlTableCell cell) => [
  cell.borderTop ?? table.properties.borders,
  cell.borderRight ?? table.properties.borders,
  cell.borderBottom ?? table.properties.borders,
  cell.borderLeft ?? table.properties.borders,
];

List<WmlTable> _tables(WmlDocument document) {
  final result = <WmlTable>[];
  void walk(Iterable<WmlBlock> blocks) {
    for (final block in blocks) {
      if (block is! WmlTable) continue;
      result.add(block);
      for (final row in block.rows) {
        for (final cell in row.cells) {
          walk(cell.blocks);
        }
      }
    }
  }

  for (final section in document.sections) {
    walk(section.blocks);
  }
  return result;
}

List<Object?> _geometry(WmlDocument document) => [
  for (final table in _tables(document))
    {
      'width': table.properties.borderWidth,
      'color': table.properties.borderColor ?? '000000',
      'margin': table.properties.cellMargin,
      'grid': table.grid,
      'cells': [
        for (final row in table.rows)
          for (final cell in row.cells)
            {
              'span': cell.gridSpan,
              'merge': cell.vMerge.name,
              'sides': _sides(table, cell),
            },
      ],
    },
];

WmlParagraph _cited(String id) {
  final paragraph = WmlParagraph(inlines: [WmlRun(text: 'Source ')]);
  WordZotero.insertCitation(
    paragraph,
    ZoteroCitation.fromJson({
      'citationID': id,
      'citationItems': [
        {
          'id': 'http://zotero.org/users/42/items/ABCD1234',
          'uris': ['http://zotero.org/users/42/items/ABCD1234'],
          'locator': '12–14',
          'prefix': 'see ',
          'future': {'keep': true},
        },
      ],
      'properties': {'plainCitation': '($id)'},
    }),
  );
  return paragraph;
}

WmlDocument _document({bool inherit = true}) => WmlDocument(
  zoteroDocumentData: jsonEncode({
    'dataVersion': 4,
    'style': {'styleID': 'http://www.zotero.org/styles/apa'},
    'prefs': {'fieldType': 'Field', 'noteType': 0},
  }),
  sections: [
    WmlSection(
      blocks: [
        WmlTable(
          grid: [120, 120],
          properties: WmlTableProps(
            borders: inherit,
            borderColor: '123456',
            borderWidth: 1.25,
            cellMargin: 4,
          ),
          rows: [
            for (final continuation in [false, true])
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    width: 240,
                    gridSpan: 2,
                    vMerge: continuation ? WmlVMerge.cont : WmlVMerge.restart,
                    borderTop: false,
                    borderRight: true,
                    borderBottom: true,
                    borderLeft: false,
                    blocks: [continuation ? WmlParagraph() : _cited('merged')],
                  ),
                ],
              ),
            WmlTableRow(
              cells: [
                WmlTableCell(
                  width: 120,
                  blocks: [
                    WmlTable(
                      grid: [80],
                      properties: WmlTableProps(
                        borderColor: 'A0B1C2',
                        borderWidth: 0.375,
                        cellMargin: 3,
                      ),
                      rows: [
                        WmlTableRow(
                          cells: [
                            WmlTableCell(
                              width: 80,
                              borderRight: false,
                              blocks: [_cited('nested')],
                            ),
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

WmlDocument _docx(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

void main() {
  test(
    'resolves inherited border shorthands and explicit side overrides',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _input(
          defaults: 'fo:border="2pt solid #A0B0C0" fo:padding="4pt"',
          parent: 'fo:border="1.25pt solid #123456" fo:border-left="none"',
          child: 'fo:border-top="none"',
          second: 'fo:border="none" fo:border-right="1.25pt solid #123456"',
        ),
      );
      final table = _tables(document).single;
      expect(table.properties.borderColor, '123456');
      expect(table.properties.borderWidth, 1.25);
      expect(table.properties.cellMargin, 4);
      expect(_sides(table, table.rows.single.cells.first), [
        false,
        true,
        true,
        false,
      ]);
      expect(_sides(table, table.rows.single.cells.last), [
        false,
        true,
        false,
        false,
      ]);
      expect(_geometry(_docx(document)), _geometry(document));
    },
  );

  test(
    'child shorthand resets earlier sides regardless of XML attribute order',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _input(
          parent: 'fo:border-top="1pt solid #123456"',
          child: 'fo:border-left="0.5pt solid #123456" fo:border="none"',
        ),
      );
      final table = _tables(document).single;
      expect(table.properties.borderWidth, 0.5);
      expect(_sides(table, table.rows.single.cells.first), [
        false,
        false,
        false,
        true,
      ]);
    },
  );

  test(
    'borderless tables retain sparse disabled sides in either style-cache order',
    () async {
      for (final model in [null, 'separating', 'collapsing']) {
        for (final explicit in ['fo:border="none"', 'fo:border-top="none"']) {
          for (final explicitFirst in [false, true]) {
            var document = await OdtDocumentReader.readBytes(
              _input(
                borderModel: model,
                child: explicitFirst ? explicit : '',
                second: explicitFirst ? '' : explicit,
              ),
            );
            for (var cycle = 0; cycle < 2; cycle++) {
              final table = _tables(document).single;
              final absent = table.rows.single.cells[explicitFirst ? 1 : 0];
              final disabled = table.rows.single.cells[explicitFirst ? 0 : 1];
              expect(table.properties.borders, isFalse);
              expect(absent.borderTop, isNull);
              expect(absent.borderRight, isNull);
              expect(disabled.borderTop, isFalse);
              expect(
                disabled.borderRight,
                explicit.contains('border-top') ? isNull : isFalse,
              );
              document = await OdtDocumentReader.readBytes(
                OdtDocumentWriter.writeEditableZoteroBytes(document),
              );
            }
          }
        }
      }
    },
  );

  test(
    'matching or absent covered borders preserve the merged owner',
    () async {
      for (final covered in ['', 'fo:border="1pt solid #123456"']) {
        final document = await OdtDocumentReader.readBytes(
          _input(
            child: 'fo:border="1pt solid #123456"',
            merged: true,
            covered: covered,
          ),
        );
        final table = _tables(document).single;
        expect(table.rows.single.cells.single.gridSpan, 2);
        expect(_sides(table, table.rows.single.cells.single), [
          true,
          true,
          true,
          true,
        ]);
      }
    },
  );

  for (final inherit in [false, true]) {
    test(
      'merged nested citations retain strokes, masks and margins through exchange inherit=$inherit',
      () async {
        final original = _document(inherit: inherit);
        final expectedGeometry = _geometry(original);
        final expectedFields = WordZotero.fields(
          original,
        ).map((field) => field.citation!.toJson()).toList();
        final preferences = WordZoteroDocumentData.read(original);
        var document = original;
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
          final xml = OpcPackage.openBytes(
            bytes,
          ).getPart('/content.xml')!.readText();
          expect(xml, contains('table:border-model="collapsing"'));
          expect(xml, contains('1.250pt solid #123456'));
          expect(xml, contains('0.375pt solid #A0B1C2'));
          expect(xml, contains('fo:border-top="none"'));
          document = await OdtDocumentReader.readBytes(bytes);
          expect(_geometry(document), expectedGeometry);
          expect(
            WordZotero.fields(
              document,
            ).map((field) => field.citation!.toJson()),
            expectedFields,
          );
          expect(
            WordZotero.fields(document).every((field) => field.canEdit),
            isTrue,
          );
          expect(WordZoteroDocumentData.read(document), preferences);
          expect(WordFieldSpans.unbalanced(document), isEmpty);
          document = _docx(document);
          expect(_geometry(document), expectedGeometry);
        }
        expect(_geometry(original), expectedGeometry);
        expect(
          WordZotero.fields(original).map((field) => field.citation!.toJson()),
          expectedFields,
        );
      },
    );
  }

  test(
    'native layout retains independent nested stroke colors and side masks',
    () async {
      final original = _document();
      final document = await OdtDocumentReader.readBytes(
        OdtDocumentWriter.writeEditableZoteroBytes(original),
      );
      final tables = _tables(document);
      final frames = WordLayoutEngine(font: null)
          .layout(document)
          .pages
          .expand((page) => page.frames)
          .where((frame) => frame.table != null && frame.height > 0)
          .toList();
      final outer = frames.firstWhere(
        (frame) => identical(frame.table, tables.first) && frame.tableRow == 0,
      );
      expect(outer.strokeColor, '123456');
      expect(outer.strokeWidth, 1.25);
      expect(
        [
          outer.strokeTop,
          outer.strokeRight,
          outer.strokeBottom,
          outer.strokeLeft,
        ],
        [false, true, true, false],
      );
      final inner = frames.singleWhere(
        (frame) => identical(frame.table, tables.last),
      );
      expect(inner.strokeColor, 'A0B1C2');
      expect(inner.strokeWidth, 0.375);
      expect(
        [
          inner.strokeTop,
          inner.strokeRight,
          inner.strokeBottom,
          inner.strokeLeft,
        ],
        [true, false, true, true],
      );
    },
  );

  for (final cycle in [1, 2]) {
    test(
      'retained Writer DOCX cell cycle $cycle reopens as editable ODT and refreshes',
      () async {
        final bytes = File(
          '$zoteroConverterFixtureRoot/docx-cycle-$cycle/cell.docx',
        ).readAsBytesSync();
        final original = Uint8List.fromList(bytes);
        var document = WordDeserializer().readBytes(bytes);
        final geometry = _geometry(document);
        final sourceTable = _tables(document).single;
        for (final cell in sourceTable.rows.single.cells) {
          // The retained raw DOCX declares top/start/bottom/end as single.
          // Assert this independently of the native snapshot to catch alias loss.
          expect(_sides(sourceTable, cell), [true, true, true, true]);
        }
        expectConverterSnapshot(document, 'cell');
        document = await OdtDocumentReader.readBytes(
          OdtDocumentWriter.writeEditableZoteroBytes(document),
        );
        expectConverterSnapshot(document, 'cell');
        expect(_geometry(document), geometry);
        const id = 'border-refresh';
        final session = WordZoteroCitingSession(
          document: document,
          documentId: id,
          insertionParagraph: document.paragraphs.first,
        );
        Object? call(String command, [List<Object?> args = const []]) =>
            session.handle(command, [id, ...args]);
        final fields = (call('Document.getFields', ['Http']) as List<Object?>)
            .cast<Map<String, Object>>();
        final originalFields = WordZotero.fields(document);
        for (var i = 0; i < fields.length; i++) {
          final citation = originalFields[i].citation!.withItems(
            originalFields[i].citation!.items,
            plainCitation: '(Updated ${i + 1})',
            noteIndex: 0,
          );
          call('Field.setCode', [
            fields[i]['id'],
            'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
          ]);
          call('Field.setText', [
            fields[i]['id'],
            '<i>(Updated ${i + 1})</i>',
            true,
          ]);
        }
        expectConverterSnapshot(document, 'cell');
        call('Document.complete');
        session.apply();
        for (var save = 0; save < 2; save++) {
          expect(_geometry(document), geometry);
          final actual = WordZotero.fields(document);
          expect(actual.map((field) => field.cachedText), [
            '(Updated 1)',
            '(Updated 2)',
          ]);
          expect(actual.map((field) => field.citation!.citationId), [
            'FIRST1',
            'SECOND2',
          ]);
          expect(
            actual.every(
              (field) =>
                  field.canEdit &&
                  converterStory(document, 'cell').contains(field.paragraph),
            ),
            isTrue,
          );
          document = await OdtDocumentReader.readBytes(
            OdtDocumentWriter.writeEditableZoteroBytes(_docx(document)),
          );
        }
        expect(_geometry(document), geometry);
        expect(bytes, original);
      },
    );
  }

  final refused = <String, Uint8List Function()>{
    'separating visible model': () => _input(
      borderModel: 'separating',
      child: 'fo:border="1pt solid #123456"',
    ),
    'unspecified visible model': () =>
        _input(borderModel: null, child: 'fo:border="1pt solid #123456"'),
    'mixed visible widths': () => _input(
      child: 'fo:border="1pt solid #123456"',
      second: 'fo:border="2pt solid #123456"',
    ),
    'mixed visible colors': () => _input(
      child: 'fo:border="1pt solid #123456"',
      second: 'fo:border="1pt solid #AABBCC"',
    ),
    'different covered stroke': () => _input(
      child: 'fo:border="1pt solid #123456"',
      merged: true,
      covered: 'fo:border="2pt solid #123456"',
    ),
    'covered edge erases visible owner': () => _input(
      child: 'fo:border="1pt solid #123456"',
      merged: true,
      covered: 'fo:border-left="none"',
    ),
    for (final border in [
      '1pt dashed #123456',
      '1pt double #123456',
      '0pt solid #123456',
      '0.1pt solid #123456',
      '0.3pt solid #123456',
      '13pt solid #123456',
      '1pt solid red',
      '1pt solid #12345678',
      'NaNpt solid #123456',
    ])
      'unsupported $border': () => _input(child: 'fo:border="$border"'),
  };
  for (final entry in refused.entries) {
    test('refuses ${entry.key} without changing input', () async {
      final bytes = entry.value();
      final original = Uint8List.fromList(bytes);
      await expectLater(
        OdtDocumentReader.readBytes(bytes),
        throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
      );
      expect(bytes, original);
    });
  }

  test(
    'export refuses covered border conflicts without changing active fields',
    () {
      final document = _document();
      final table = _tables(document).first;
      table.rows[1].cells.single.borderLeft = true;
      final before = WordZotero.fields(
        document,
      ).map((field) => field.instruction).toList();
      expect(
        () => OdtDocumentWriter.writeEditableZoteroBytes(document),
        throwsUnsupportedError,
      );
      expect(
        WordZotero.fields(document).map((field) => field.instruction),
        before,
      );
      expect(table.rows[1].cells.single.borderLeft, isTrue);
    },
  );

  for (final invalid in [0.0, 0.3, 13.0, double.infinity, double.nan]) {
    test('export refuses nonportable border width $invalid', () {
      final document = _document();
      _tables(document).first.properties.borderWidth = invalid;
      expect(
        () => OdtDocumentWriter.writeEditableZoteroBytes(document),
        throwsUnsupportedError,
      );
      expect(WordZotero.fields(document), hasLength(2));
    });
  }
}
