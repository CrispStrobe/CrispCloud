import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _namespaces =
    'xmlns:office="$_office" xmlns:text="$_text" xmlns:table="$_table" '
    'xmlns:style="$_style" xmlns:fo="$_fo"';

WmlDocument _document(WmlJustification alignment) {
  final paragraph = WmlParagraph(inlines: [WmlRun(text: 'Source ')]);
  WordZotero.insertCitation(
    paragraph,
    ZoteroCitation.fromJson({
      'citationID': 'table-citation',
      'citationItems': [
        {
          'id': 'http://zotero.org/users/42/items/ABCD1234',
          'uris': ['http://zotero.org/users/42/items/ABCD1234'],
          'locator': '17',
          'label': 'page',
        },
      ],
      'properties': {'plainCitation': '(Author, 17)'},
    }),
  );
  return WmlDocument(
    zoteroDocumentData: jsonEncode({
      'dataVersion': 4,
      'style': {'styleID': 'http://www.zotero.org/styles/apa'},
      'prefs': {'fieldType': 'Field', 'noteType': 0},
    }),
    sections: [
      WmlSection(
        blocks: [
          WmlTable(
            properties: WmlTableProps(
              alignment: alignment,
              borders: false,
              cellMargin: 0,
            ),
            grid: [72, 108],
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(gridSpan: 2, width: 180, blocks: [paragraph]),
                ],
              ),
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    width: 72,
                    blocks: [
                      WmlParagraph(inlines: [WmlRun(text: 'Left')]),
                    ],
                  ),
                  WmlTableCell(
                    width: 108,
                    blocks: [
                      WmlParagraph(inlines: [WmlRun(text: 'Right')]),
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

Iterable<XmlElement> _elements(XmlElement root, String localName) sync* {
  if (root.namespaceUri == _style && root.localName == localName) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, localName);
  }
}

XmlElement _content(Uint8List bytes) => XmlDocument.parse(
  OpcPackage.openBytes(bytes).getPart('/content.xml')!.readText(),
).root!;

Uint8List _independentOdt({
  String borderModel = 'separating',
  String tableProperties = '',
  String rowProperties = '',
  String cellProperties = '',
  String coveredCellProperties = '',
  String defaultCellProperties = '',
  bool relativeColumns = false,
}) {
  final writer = ZipWriter();
  writer.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  writer.addFile(
    'styles.xml',
    utf8.encode(
      '<office:document-styles $_namespaces><office:styles>'
      '<style:default-style style:family="table"><style:table-properties '
      'table:border-model="$borderModel"/></style:default-style>'
      '<style:default-style style:family="table-cell">'
      '<style:table-cell-properties $defaultCellProperties/>'
      '</style:default-style>'
      '</office:styles></office:document-styles>',
    ),
  );
  writer.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content $_namespaces><office:automatic-styles>'
      '<style:style style:name="T" style:family="table">'
      '<style:table-properties style:width="180pt" table:align="center" '
      '$tableProperties/></style:style>'
      '<style:style style:name="R" style:family="table-row">'
      '<style:table-row-properties $rowProperties/></style:style>'
      '<style:style style:name="C1" style:family="table-column">'
      '<style:table-column-properties '
      '${relativeColumns ? 'style:rel-column-width="2*"' : 'style:column-width="72pt"'}/>'
      '</style:style><style:style style:name="C2" style:family="table-column">'
      '<style:table-column-properties '
      '${relativeColumns ? 'style:rel-column-width="3*"' : 'style:column-width="108pt"'}/>'
      '</style:style><style:style style:name="Cell" style:family="table-cell">'
      '<style:table-cell-properties $cellProperties/></style:style>'
      '<style:style style:name="Covered" style:family="table-cell">'
      '<style:table-cell-properties $coveredCellProperties/></style:style>'
      '</office:automatic-styles><office:body><office:text>'
      '<table:table table:style-name="T">'
      '<table:table-column table:style-name="C1"/>'
      '<table:table-column table:style-name="C2"/>'
      '<table:table-row table:style-name="R">'
      '<table:table-cell table:style-name="Cell" table:number-columns-spanned="2">'
      '<text:p>Merged text</text:p></table:table-cell>'
      '<table:covered-table-cell table:style-name="Covered"/>'
      '</table:table-row></table:table>'
      '</office:text></office:body></office:document-content>',
    ),
  );
  return writer.close();
}

void main() {
  for (final alignment in [
    WmlJustification.left,
    WmlJustification.center,
    WmlJustification.right,
  ]) {
    test(
      'editable ODT retains absolute ${alignment.name} table geometry',
      () async {
        final source = _document(alignment);
        final bytes = OdtDocumentWriter.writeEditableZoteroBytes(source);
        final content = _content(bytes);
        final properties = _elements(content, 'table-properties').single;
        expect(
          properties.getAttribute('width', namespaceUri: _style),
          '180.00pt',
        );
        expect(
          properties.getAttribute('rel-width', namespaceUri: _style),
          isNull,
        );
        expect(
          properties.getAttribute('align', namespaceUri: _table),
          alignment.name,
        );
        expect(
          _elements(content, 'table-column-properties').map(
            (column) =>
                column.getAttribute('column-width', namespaceUri: _style),
          ),
          ['72.00pt', '108.00pt'],
        );
        var document = await OdtDocumentReader.readBytes(bytes);
        for (var cycle = 0; cycle < 3; cycle++) {
          final table = document.sections.single.blocks
              .whereType<WmlTable>()
              .single;
          expect(table.grid, [72, 108]);
          expect(table.properties.alignment, alignment);
          expect(table.properties.cellMargin, 0, reason: 'cycle $cycle');
          expect(table.rows.first.cells.single.gridSpan, 2);
          expect(table.rows.first.cells.single.width, 180);
          expect(table.rows.last.cells.map((cell) => cell.width), [72, 108]);
          final citation = WordZotero.fields(document).single;
          expect(citation.citation!.citationId, 'table-citation');
          expect(citation.cachedText, '(Author, 17)');
          expect(citation.canEdit, isTrue);
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
        final originalTable = source.sections.single.blocks.single as WmlTable;
        expect(originalTable.grid, [72, 108]);
        expect(originalTable.properties.alignment, alignment);
      },
    );

    test(
      'ordinary ODT retains its established fill-width behavior for ${alignment.name}',
      () {
        final content = _content(
          OdtDocumentWriter.writeBytes(_document(alignment)),
        );
        final properties = _elements(content, 'table-properties').single;
        expect(
          properties.getAttribute('align', namespaceUri: _table),
          'margins',
        );
        expect(
          properties.getAttribute('rel-width', namespaceUri: _style),
          '100%',
        );
        expect(properties.getAttribute('width', namespaceUri: _style), isNull);
      },
    );
  }

  for (final alignment in [
    WmlJustification.justify,
    WmlJustification.distributed,
  ]) {
    test(
      'editable export refuses unmodeled table alignment ${alignment.name}',
      () {
        final document = _document(alignment);
        final before = WordZotero.fields(document).single.instruction;
        expect(
          () => OdtDocumentWriter.writeEditableZoteroBytes(document),
          throwsUnsupportedError,
        );
        expect(WordZotero.fields(document).single.instruction, before);
      },
    );
  }

  for (final model in ['separating', 'collapsing']) {
    test(
      'inherited $model border model is inert for explicitly borderless input',
      () async {
        final document = await OdtDocumentReader.readBytes(
          _independentOdt(borderModel: model),
        );
        final table = document.sections.single.blocks.single as WmlTable;
        expect(table.properties.borders, isFalse);
        expect(table.properties.cellMargin, 0);
        expect(table.properties.alignment, WmlJustification.center);
        expect(table.grid, [72, 108]);
        expect(table.rows.single.cells.single.width, 180);
        expect(
          table.rows.single.cells.single.blocks
              .whereType<WmlParagraph>()
              .single
              .text,
          'Merged text',
        );
      },
    );
  }

  final activeStyles = <String, Uint8List Function()>{
    'inherited cell border': () =>
        _independentOdt(defaultCellProperties: 'fo:border="1pt solid #000000"'),
    'cell border': () =>
        _independentOdt(cellProperties: 'fo:border="1pt solid #000000"'),
    'covered cell border': () => _independentOdt(
      coveredCellProperties: 'fo:border-left="1pt solid #000000"',
    ),
    'asymmetric cell padding': () =>
        _independentOdt(cellProperties: 'fo:padding-left="2pt"'),
    'covered cell padding': () =>
        _independentOdt(coveredCellProperties: 'fo:padding="2pt"'),
    'table border': () =>
        _independentOdt(tableProperties: 'fo:border="1pt solid #000000"'),
    'row border': () =>
        _independentOdt(rowProperties: 'fo:border="1pt solid #000000"'),
    'unknown border model': () => _independentOdt(borderModel: 'custom'),
    'relative column widths': () => _independentOdt(relativeColumns: true),
  };
  for (final entry in activeStyles.entries) {
    test('border-model compatibility does not flatten ${entry.key}', () async {
      final bytes = entry.value();
      final original = Uint8List.fromList(bytes);
      await expectLater(
        OdtDocumentReader.readBytes(bytes),
        throwsUnsupportedError,
      );
      expect(bytes, original);
    });
  }
}
