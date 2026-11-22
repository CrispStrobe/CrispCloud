import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:cell-border-test';

String _tableXml({
  String properties = '',
  String cellProperties = '',
  String inside = '',
  String outsideProperties = '',
}) =>
    '<w:tbl><w:tblPr>$properties</w:tblPr>'
    '<w:tblGrid><w:gridCol w:w="2400"/></w:tblGrid><w:tr><w:tc>'
    '<w:tcPr>$cellProperties</w:tcPr>$outsideProperties'
    '<w:p><w:r><w:t>Cell</w:t></w:r></w:p>$inside'
    '</w:tc></w:tr></w:tbl>';

OpcPackage _package({
  String properties = '',
  String borders = '',
  String styles = '',
  String extraCellProperties = '',
  String outsideProperties = '',
  String inside = '',
}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:n="$_w" xmlns:x="$_x"><w:body>'
        '${_tableXml(properties: properties, cellProperties: '<w:tcBorders>$borders</w:tcBorders>$extraCellProperties', outsideProperties: outsideProperties, inside: inside)}'
        '</w:body></w:document>',
      );
  if (styles.isNotEmpty) {
    (package.getPart('/word/styles.xml') ??
            package.createPart(
              '/word/styles.xml',
              OfficeContentTypes.wordStyles,
            ))
        .writeText('<w:styles xmlns:w="$_w" xmlns:x="$_x">$styles</w:styles>');
    if (package
            .relationshipsFor('/word/document.xml')
            .firstByType(RelationshipTypes.styles) ==
        null) {
      package
          .relationshipsFor('/word/document.xml')
          .add(type: RelationshipTypes.styles, target: 'styles.xml');
    }
  }
  return package;
}

WmlTable _table(WmlDocument document) =>
    document.sections.single.blocks.whereType<WmlTable>().single;

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

String _style(
  String id, {
  String properties = '',
  String? parent,
  bool isDefault = false,
}) =>
    '<w:style w:type="table" w:styleId="$id" ${isDefault ? 'w:default="1"' : ''}>'
    '${parent == null ? '' : '<w:basedOn w:val="$parent"/>'}'
    '<w:tblPr>$properties</w:tblPr></w:style>';

Map<String, String?> _serializedBorders(WmlDocument document) {
  final root = XmlDocument.parse(
    WordSerializer().write(document).getPart('/word/document.xml')!.readText(),
  ).root!;
  final borders = root
      .firstChild('body')!
      .firstChild('tbl')!
      .firstChild('tr')!
      .firstChild('tc')!
      .firstChild('tcPr')!
      .firstChild('tcBorders')!;
  return {
    for (final edge in borders.childElements)
      edge.localName: edge.getAttribute('val', namespaceUri: _w),
  };
}

void _expectLeading(WmlDocument document, bool rtl) {
  final table = _table(document);
  final cell = table.rows.single.cells.single;
  expect(table.properties.rightToLeft, rtl);
  expect(cell.borderLeft, !rtl);
  expect(cell.borderRight, rtl);
  final frame = WordLayoutEngine(font: null)
      .layout(document)
      .pages
      .expand((page) => page.frames)
      .singleWhere((frame) => identical(frame.table, table));
  expect(frame.strokeLeft, !rtl);
  expect(frame.strokeRight, rtl);
}

void main() {
  for (final aliases in [
    ['left', 'right'],
    ['start', 'end'],
  ]) {
    for (final rtl in [false, true]) {
      test(
        '${aliases.join('/')} maps physical sides and serializes correctly for RTL=$rtl',
        () {
          var document = WordDeserializer().read(
            _package(
              properties: '<w:bidiVisual w:val="${rtl ? 'on' : 'off'}"/>',
              borders:
                  '<n:${aliases[0]} n:val="single" n:sz="4" n:color="000000"/>'
                  '<w:${aliases[1]} w:val="nil"/><w:top w:val="none"/>',
            ),
          );
          for (var cycle = 0; cycle < 3; cycle++) {
            _expectLeading(document, rtl);
            final cell = _table(document).rows.single.cells.single;
            expect(cell.borderTop, isFalse);
            expect(cell.borderBottom, isNull);
            expect(_serializedBorders(document), {
              'top': 'nil',
              'left': 'single',
              'right': 'nil',
            });
            document = _reopen(document);
          }
        },
      );
    }
  }

  for (final reverse in [false, true]) {
    for (final rtl in [false, true]) {
      test(
        'modern aliases take precedence regardless of order reverse=$reverse RTL=$rtl',
        () {
          final declarations = [
            '<w:left w:val="single" w:sz="8" w:color="FF0000"/>',
            '<w:start w:val="none"/>',
            '<w:right w:val="nil"/>',
            '<w:end w:val="single" w:sz="4" w:color="000000"/>',
          ];
          final document = WordDeserializer().read(
            _package(
              properties: '<w:bidiVisual w:val="${rtl ? 'on' : 'off'}"/>',
              borders: (reverse ? declarations.reversed : declarations).join(),
            ),
          );
          final cell = _table(document).rows.single.cells.single;
          expect(cell.borderLeft, rtl);
          expect(cell.borderRight, !rtl);
          expect(_serializedBorders(document), {
            'left': 'nil',
            'right': 'single',
          });
        },
      );
    }
  }

  final directions = <String, ({String properties, String styles, bool rtl})>{
    'named inherited RTL': (
      properties: '<w:tblStyle w:val="Child"/>',
      styles:
          _style('Parent', properties: '<w:bidiVisual w:val="on"/>') +
          _style('Child', parent: 'Parent'),
      rtl: true,
    ),
    'named child overrides RTL': (
      properties: '<w:tblStyle w:val="Child"/>',
      styles:
          _style('Parent', properties: '<w:bidiVisual w:val="on"/>') +
          _style(
            'Child',
            parent: 'Parent',
            properties: '<w:bidiVisual w:val="off"/>',
          ),
      rtl: false,
    ),
    'direct LTR overrides style': (
      properties: '<w:tblStyle w:val="Child"/><w:bidiVisual w:val="off"/>',
      styles: _style('Child', properties: '<w:bidiVisual w:val="on"/>'),
      rtl: false,
    ),
    'unique default RTL': (
      properties: '',
      styles: _style(
        'Default',
        isDefault: true,
        properties: '<w:bidiVisual w:val="on"/>',
      ),
      rtl: true,
    ),
    'direct LTR overrides default': (
      properties: '<w:bidiVisual w:val="off"/>',
      styles: _style(
        'Default',
        isDefault: true,
        properties: '<w:bidiVisual w:val="on"/>',
      ),
      rtl: false,
    ),
    'foreign table-style selector is inert': (
      properties: '<x:tblStyle w:val="Child"/>',
      styles: _style('Child', properties: '<w:bidiVisual w:val="on"/>'),
      rtl: false,
    ),
    'foreign direct direction is inert': (
      properties: '<x:bidiVisual w:val="on"/>',
      styles: '',
      rtl: false,
    ),
    'nested direct direction is inert': (
      properties: '<x:extension><w:bidiVisual w:val="on"/></x:extension>',
      styles: '',
      rtl: false,
    ),
    'foreign inherited direction is inert': (
      properties: '<w:tblStyle w:val="Child"/>',
      styles: _style('Child', properties: '<x:bidiVisual w:val="on"/>'),
      rtl: false,
    ),
    'nested inherited direction is inert': (
      properties: '<w:tblStyle w:val="Child"/>',
      styles: _style(
        'Child',
        properties: '<x:extension><w:bidiVisual w:val="on"/></x:extension>',
      ),
      rtl: false,
    ),
  };
  for (final entry in directions.entries) {
    test('border mapping follows ${entry.key}', () {
      var document = WordDeserializer().read(
        _package(
          properties: entry.value.properties,
          styles: entry.value.styles,
          borders: '<w:start w:val="single"/><w:end w:val="none"/>',
        ),
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        _expectLeading(document, entry.value.rtl);
        document = _reopen(document);
      }
    });
  }

  for (final container in ['foreign', 'nested']) {
    test(
      '$container table properties cannot select RTL or replace the direct source',
      () {
        final package = _package(
          borders: '<w:start w:val="single"/><w:end w:val="none"/>',
          styles: _style('Child', properties: '<w:bidiVisual w:val="on"/>'),
        );
        final part = package.getPart('/word/document.xml')!;
        final decoy = container == 'foreign'
            ? '<x:tblPr><w:tblStyle w:val="Child"/><w:bidiVisual/></x:tblPr>'
            : '<x:extension><w:tblPr><w:tblStyle w:val="Child"/><w:bidiVisual/></w:tblPr></x:extension>';
        part.writeText(
          part.readText().replaceFirst('</w:tblPr>', '</w:tblPr>$decoy'),
        );
        var document = WordDeserializer().read(package);
        for (var cycle = 0; cycle < 2; cycle++) {
          _expectLeading(document, false);
          final table = _table(document);
          expect(table.properties.styleId, isNull);
          expect(
            table.properties.sourcePropertiesXml,
            isNot(contains('Child')),
          );
          document = _reopen(document);
        }
      },
    );
  }

  test('nested table resolves its own direction independently of outer RTL', () {
    final document = WordDeserializer().read(
      _package(
        properties: '<w:bidiVisual/>',
        borders: '<w:start w:val="single"/><w:end w:val="none"/>',
        inside: _tableXml(
          cellProperties:
              '<w:tcBorders><w:start w:val="single"/><w:end w:val="none"/></w:tcBorders>',
        ),
      ),
    );
    _expectLeading(document, true);
    final inner = _table(
      document,
    ).rows.single.cells.single.blocks.whereType<WmlTable>().single;
    expect(inner.properties.rightToLeft, isFalse);
    expect(inner.rows.single.cells.single.borderLeft, isTrue);
    expect(inner.rows.single.cells.single.borderRight, isFalse);
  });

  test(
    'foreign and nested border lookalikes cannot override direct native edges',
    () {
      final document = WordDeserializer().read(
        _package(
          borders:
              '<w:left w:val="nil"/><x:start w:val="single"/>'
              '<x:extension><w:start w:val="single"/></x:extension>',
          extraCellProperties:
              '<x:tcBorders><w:start w:val="single"/></x:tcBorders>'
              '<x:extension><w:tcBorders><w:start w:val="single"/></w:tcBorders></x:extension>',
          outsideProperties:
              '<w:tcBorders><w:start w:val="single"/></w:tcBorders>'
              '<x:tcPr><w:tcBorders><w:start w:val="single"/></w:tcBorders></x:tcPr>',
        ),
      );
      final cell = _table(document).rows.single.cells.single;
      expect(cell.borderLeft, isFalse);
      expect(cell.borderRight, isNull);
    },
  );

  test(
    'duplicate native declarations refuse and reused reader clears staged edges',
    () {
      final reader = WordDeserializer();
      expect(
        () => reader.read(
          _package(borders: '<w:start w:val="single"/><w:start w:val="none"/>'),
        ),
        throwsFormatException,
      );
      final document = reader.read(_package(borders: '<w:end w:val="none"/>'));
      final cell = _table(document).rows.single.cells.single;
      expect(cell.borderLeft, isNull);
      expect(cell.borderRight, isFalse);
      expect(
        () => reader.read(
          _package(borders: '<w:start><w:end w:val="single"/></w:start>'),
        ),
        throwsFormatException,
      );
      expect(
        () => reader.read(_package(extraCellProperties: '<w:tcBorders/>')),
        throwsFormatException,
      );
    },
  );

  test(
    'authored physical sides invert to transitional names in RTL serialization',
    () {
      var document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlTable(
                grid: [120],
                properties: WmlTableProps(rightToLeft: true, borders: false),
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(
                        borderLeft: true,
                        borderRight: false,
                        blocks: [WmlParagraph()],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(_serializedBorders(document), {
          'left': 'nil',
          'right': 'single',
        });
        final cell = _table(document).rows.single.cells.single;
        expect(cell.borderLeft, isTrue);
        expect(cell.borderRight, isFalse);
        document = _reopen(document);
      }
    },
  );

  test(
    'editable ODT refuses RTL table order without modifying active references',
    () {
      final document = WordDeserializer().readBytes(
        File(
          'test/fixtures/zotero/converter/docx-cycle-1/cell.docx',
        ).readAsBytesSync(),
      );
      final table = _table(document);
      table.properties.rightToLeft = true;
      final text = document.paragraphs
          .map((paragraph) => paragraph.text)
          .toList();
      final fields = WordZotero.fields(
        document,
      ).map((field) => field.instruction).toList();
      expect(
        () => OdtDocumentWriter.writeEditableZoteroBytes(document),
        throwsUnsupportedError,
      );
      expect(table.properties.rightToLeft, isTrue);
      expect(document.paragraphs.map((paragraph) => paragraph.text), text);
      expect(
        WordZotero.fields(document).map((field) => field.instruction),
        fields,
      );
      expect(
        WordZotero.fields(document).every((field) => field.canEdit),
        isTrue,
      );
      expect(OdtDocumentWriter.writeBytes(document), isNotEmpty);
    },
  );
}
