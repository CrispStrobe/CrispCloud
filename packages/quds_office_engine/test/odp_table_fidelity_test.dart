import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _tableNs = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

XmlElement _export(
  List<PmlShape> shapes, {
  String? fixture,
  String notes = '',
}) {
  final bytes = OdpPresentationWriter.writeBytes(
    PmlPresentation(
      slides: [PmlSlide(id: 1, shapes: shapes, notes: notes)],
    ),
  );
  final output = Platform.environment['QUDS_ODF_FIXTURE_OUTPUT'];
  if (fixture != null && output != null && output.isNotEmpty) {
    Directory(output).createSync(recursive: true);
    File('$output/$fixture').writeAsBytesSync(bytes);
  }
  return XmlDocument.parse(
    OpcPackage.openBytes(bytes).getPart('/content.xml')!.readText(),
  ).root!;
}

PmlShape _shape(PmlTable table, {int width = 360, int height = 120}) =>
    PmlShape(
      id: 2,
      name: 'Table',
      transform: PmlTransform(cx: width * 12700, cy: height * 12700),
      table: table,
    );

XmlElement _properties(
  XmlElement root,
  XmlElement owner,
  String family, {
  String ownerNamespace = _tableNs,
}) {
  final name = owner.getAttribute('style-name', namespaceUri: ownerNamespace);
  expect(
    name,
    isNotNull,
    reason: '${owner.qualifiedName} needs a $family style',
  );
  final style = _elements(root, 'style').singleWhere(
    (element) =>
        element.getAttribute('name', namespaceUri: _styleNs) == name &&
        element.getAttribute('family', namespaceUri: _styleNs) == family,
  );
  return style.firstChild('$family-properties', namespaceUri: _styleNs)!;
}

int _cellCount(XmlElement row) => row
    .childrenNamed('table-cell', namespaceUri: _tableNs)
    .fold(
      0,
      (sum, cell) =>
          sum + int.parse(cell.getAttribute('number-columns-repeated') ?? '1'),
    );

void main() {
  test('table cell text colors survive independently of fill colors', () {
    final root = _export([
      _shape(
        PmlTable(
          rows: [
            [
              PmlTableCell(
                text: 'White',
                fillColor: '2B579A',
                textColor: 'FFFFFF',
              ),
              PmlTableCell(
                text: 'Red',
                fillColor: 'FFFFFF',
                textColor: 'AA0011',
              ),
              PmlTableCell(text: 'Default'),
            ],
          ],
        ),
      ),
    ], fixture: 'slide-table-colors.odp');
    final cells = _elements(root, 'table-cell').toList();
    expect(
      _properties(
        root,
        cells.first,
        'table-cell',
      ).getAttribute('background-color', namespaceUri: _foNs),
      '#2b579a',
    );
    final colors = cells.map((cell) {
      final span = _elements(cell, 'span').single;
      return _properties(
        root,
        span,
        'text',
        ownerNamespace: _textNs,
      ).getAttribute('color', namespaceUri: _foNs);
    }).toList();
    expect(colors, ['#ffffff', '#aa0011', '#1a1a1a']);
    expect(
      _properties(
        root,
        cells.last,
        'table-cell',
      ).getAttribute('background-color', namespaceUri: _foNs),
      '#ffffff',
    );
  });

  test('equal text colors reuse styles without bleeding into other cells', () {
    final root = _export([
      _shape(
        PmlTable(
          rows: [
            [
              PmlTableCell(text: 'A', textColor: 'AABBCC'),
              PmlTableCell(text: 'B', textColor: 'aabbcc'),
            ],
            [
              PmlTableCell(text: 'C', textColor: '112233'),
              PmlTableCell(text: 'D'),
            ],
          ],
        ),
      ),
    ]);
    final spans = _elements(root, 'span').toList();
    final names = spans
        .map((span) => span.getAttribute('style-name', namespaceUri: _textNs))
        .toList();
    expect(names[0], names[1]);
    expect(names[2], isNot(names[0]));
    expect(names[3], isNot(names[0]));
  });

  test(
    'right-to-left tables export physical positions and paragraph direction',
    () {
      final table = PmlTable(
        rightToLeft: true,
        rows: [
          [PmlTableCell(text: 'الأول'), PmlTableCell(text: 'الثاني')],
        ],
      );
      final root = _export([_shape(table)], fixture: 'slide-table-rtl.odp');
      final exported = _elements(root, 'table').single;
      expect(
        _properties(
          root,
          exported,
          'table',
        ).getAttribute('writing-mode', namespaceUri: _styleNs),
        'lr-tb',
      );
      final paragraphs = _elements(exported, 'p').toList();
      expect(paragraphs.map((paragraph) => paragraph.text), [
        'الثاني',
        'الأول',
      ]);
      for (final paragraph in paragraphs) {
        final properties = _properties(
          root,
          paragraph,
          'paragraph',
          ownerNamespace: _textNs,
        );
        expect(
          properties.getAttribute('writing-mode', namespaceUri: _styleNs),
          'rl-tb',
        );
        expect(
          properties.getAttribute(
            'writing-mode-automatic',
            namespaceUri: _styleNs,
          ),
          'false',
        );
      }
      expect(table.rows.single.map((cell) => cell.text), ['الأول', 'الثاني']);
    },
  );

  test('physical table layout and paragraph direction remain independent', () {
    final root = _export([
      for (final rtl in [false, true])
        _shape(
          PmlTable(
            rightToLeft: rtl,
            rows: [
              [PmlTableCell(text: 'A')],
            ],
          ),
        ),
    ]);
    final tables = _elements(root, 'table').toList();
    expect(
      _properties(
        root,
        tables[0],
        'table',
      ).getAttribute('writing-mode', namespaceUri: _styleNs),
      'lr-tb',
    );
    final paragraph = _elements(tables[0], 'p').single;
    final rtlParagraph = _elements(tables[1], 'p').single;
    expect(
      paragraph.getAttribute('style-name'),
      isNot(rtlParagraph.getAttribute('style-name')),
    );
    expect(
      _properties(
        root,
        paragraph,
        'paragraph',
        ownerNamespace: _textNs,
      ).getAttribute('writing-mode', namespaceUri: _styleNs),
      'lr-tb',
    );
  });

  test('header intent keeps every presentation row directly visible', () {
    final root = _export([
      _shape(
        PmlTable(
          rows: [
            [PmlTableCell(text: 'Heading')],
            [PmlTableCell(text: 'Body')],
          ],
        ),
      ),
    ]);
    final table = _elements(root, 'table').single;
    expect(
      table.getAttribute('use-first-row-styles', namespaceUri: _tableNs),
      'true',
    );
    expect(_elements(table, 'table-header-rows'), isEmpty);
    expect(
      table
          .childrenNamed('table-row', namespaceUri: _tableNs)
          .map((row) => row.text),
      ['Heading', 'Body'],
    );
  });

  test('table without header exports all rows as body rows', () {
    final root = _export([
      _shape(
        PmlTable(
          headerRow: false,
          rows: [
            [PmlTableCell(text: 'A')],
            [PmlTableCell(text: 'B')],
          ],
        ),
      ),
    ]);
    final table = _elements(root, 'table').single;
    expect(
      table.getAttribute('use-first-row-styles', namespaceUri: _tableNs),
      'false',
    );
    expect(_elements(table, 'table-header-rows'), isEmpty);
    expect(
      table.childrenNamed('table-row', namespaceUri: _tableNs),
      hasLength(2),
    );
  });

  test('table geometry follows equal-sized modeled rows and columns', () {
    final root = _export([
      _shape(PmlTable.grid(rows: 3, cols: 2), width: 360, height: 120),
    ], fixture: 'slide-table-geometry.odp');
    final table = _elements(root, 'table').single;
    expect(
      _properties(
        root,
        table,
        'table',
      ).getAttribute('width', namespaceUri: _styleNs),
      '360.00pt',
    );
    final columns = table.childrenNamed('table-column', namespaceUri: _tableNs);
    expect(
      columns.fold<int>(
        0,
        (sum, col) =>
            sum + int.parse(col.getAttribute('number-columns-repeated') ?? '1'),
      ),
      2,
    );
    for (final column in columns) {
      expect(
        _properties(
          root,
          column,
          'table-column',
        ).getAttribute('column-width', namespaceUri: _styleNs),
        '180.00pt',
      );
    }
    for (final row in _elements(table, 'table-row')) {
      final properties = _properties(root, row, 'table-row');
      expect(
        properties.getAttribute('row-height', namespaceUri: _styleNs),
        '40.00pt',
      );
      expect(
        properties.getAttribute(
          'use-optimal-row-height',
          namespaceUri: _styleNs,
        ),
        'false',
      );
    }
  });

  test('different table dimensions do not alias size styles', () {
    final root = _export([
      _shape(PmlTable.grid(rows: 2, cols: 2), width: 200, height: 80),
      _shape(PmlTable.grid(rows: 2, cols: 2), width: 400, height: 160),
    ]);
    final tables = _elements(root, 'table').toList();
    expect(
      tables[0].getAttribute('style-name'),
      isNot(tables[1].getAttribute('style-name')),
    );
    final columns = tables
        .map((table) => table.firstChild('table-column')!)
        .toList();
    expect(
      columns[0].getAttribute('style-name'),
      isNot(columns[1].getAttribute('style-name')),
    );
    final rows = tables
        .map((table) => _elements(table, 'table-row').first)
        .toList();
    expect(
      rows[0].getAttribute('style-name'),
      isNot(rows[1].getAttribute('style-name')),
    );
  });

  test('ragged rows export a rectangular grid without mutating the model', () {
    final table = PmlTable(
      headerRow: false,
      rows: [
        [
          PmlTableCell(text: 'A'),
          PmlTableCell(text: 'B'),
          PmlTableCell(text: 'C'),
        ],
        [PmlTableCell(text: 'D')],
        [],
      ],
    );
    final root = _export([_shape(table)]);
    final rows = _elements(root, 'table-row').toList();
    expect(rows.map(_cellCount), [3, 3, 3]);
    expect(table.rows.map((row) => row.length), [3, 1, 0]);
    expect(rows.map((row) => row.text), ['ABC', 'D', '']);
  });

  test(
    'empty tables export a valid minimal grid without adding model cells',
    () {
      final table = PmlTable();
      final root = _export([_shape(table)]);
      expect(_elements(root, 'table-column'), hasLength(1));
      final row = _elements(root, 'table-row').single;
      expect(_cellCount(row), 1);
      expect(_elements(root, 'table-header-rows'), isEmpty);
      expect(table.rows, isEmpty);
    },
  );

  test('trailing empty grid positions are represented compactly', () {
    final table = PmlTable(
      headerRow: false,
      rows: [
        [for (var i = 0; i < 100; i++) PmlTableCell(text: '$i')],
        [],
      ],
    );
    final root = _export([_shape(table)]);
    final row = _elements(root, 'table-row').last;
    expect(row.childrenNamed('table-cell'), hasLength(1));
    expect(_cellCount(row), 100);
    expect(table.rows.last, isEmpty);
  });

  test(
    'table text keeps multiline whitespace and its color on every paragraph',
    () {
      final root = _export([
        _shape(
          PmlTable(
            rows: [
              [PmlTableCell(text: ' A\tB \n\n C ', textColor: '123456')],
            ],
          ),
        ),
      ]);
      final cell = _elements(root, 'table-cell').single;
      expect(_elements(cell, 'p'), hasLength(3));
      expect(_elements(cell, 'tab'), hasLength(1));
      expect(_elements(cell, 's'), hasLength(4));
      for (final span in _elements(cell, 'span')) {
        expect(
          _properties(
            root,
            span,
            'text',
            ownerNamespace: _textNs,
          ).getAttribute('color', namespaceUri: _foNs),
          '#123456',
        );
      }
    },
  );

  for (final tableFirst in [true, false]) {
    test(
      'table insertion order $tableFirst preserves shape and note styles',
      () {
        final table = _shape(
          PmlTable(
            rightToLeft: true,
            rows: [
              [PmlTableCell(text: 'Cell', textColor: 'aabbcc')],
            ],
          ),
        );
        final shape = PmlShape(
          id: 3,
          name: 'Ordinary',
          text: 'Shape',
          textColor: 'AABBCC',
          fontSizePt: 27,
          textAlign: PmlTextAlign.center,
        );
        final root = _export(
          tableFirst ? [table, shape] : [shape, table],
          notes: 'Note',
        );
        final frame = _elements(
          root,
          'frame',
        ).singleWhere((frame) => frame.getAttribute('name') == 'Ordinary');
        final paragraph = _elements(frame, 'p').single;
        final span = _elements(paragraph, 'span').single;
        final text = _properties(root, span, 'text', ownerNamespace: _textNs);
        expect(text.getAttribute('color', namespaceUri: _foNs), '#aabbcc');
        expect(text.getAttribute('font-size', namespaceUri: _foNs), '27.0pt');
        expect(
          _properties(
            root,
            paragraph,
            'paragraph',
            ownerNamespace: _textNs,
          ).getAttribute('text-align', namespaceUri: _foNs),
          'center',
        );
        final note = _elements(_elements(root, 'notes').single, 'span').single;
        final noteText = _properties(
          root,
          note,
          'text',
          ownerNamespace: _textNs,
        );
        expect(noteText.getAttribute('color', namespaceUri: _foNs), isNull);
        expect(noteText.getAttribute('font-size', namespaceUri: _foNs), isNull);
        final cell = _elements(
          _elements(root, 'table-cell').single,
          'span',
        ).single;
        final cellText = _properties(
          root,
          cell,
          'text',
          ownerNamespace: _textNs,
        );
        expect(cellText.getAttribute('color', namespaceUri: _foNs), '#aabbcc');
        expect(cellText.getAttribute('font-size', namespaceUri: _foNs), isNull);
      },
    );
  }

  test('RTL empty header remains rectangular across repeated exports', () {
    final first = <PmlTableCell>[];
    final table = PmlTable(
      rightToLeft: true,
      rows: [
        first,
        [
          PmlTableCell(text: '1'),
          PmlTableCell(text: '2'),
          PmlTableCell(text: '3'),
        ],
      ],
    );
    final shape = _shape(table, width: 100, height: 100);
    for (final root in [
      _export([shape]),
      _export([shape]),
    ]) {
      final table = _elements(root, 'table').single;
      expect(
        table.getAttribute('use-first-row-styles', namespaceUri: _tableNs),
        'true',
      );
      expect(_cellCount(_elements(table, 'table-row').first), 3);
      expect(_elements(root, 'table-row'), hasLength(2));
      expect(_elements(root, 'p').map((paragraph) => paragraph.text), [
        '',
        '3',
        '2',
        '1',
      ]);
    }
    expect(identical(table.rows.first, first), isTrue);
    expect(first, isEmpty);
    expect(table.rows.map((row) => row.length), [0, 3]);
  });

  test('RTL ragged rows place missing logical cells on the physical left', () {
    final table = PmlTable(
      rightToLeft: true,
      rows: [
        [
          PmlTableCell(text: 'First'),
          PmlTableCell(text: 'Second'),
          PmlTableCell(text: 'Third'),
        ],
        [PmlTableCell(text: 'Right')],
      ],
    );
    final root = _export([_shape(table)]);
    final cells = _elements(root, 'table-row').last.childrenNamed('table-cell');
    expect(cells, hasLength(2));
    expect(cells.first.getAttribute('number-columns-repeated'), '2');
    expect(cells.first.text, '');
    expect(cells.last.text, 'Right');
    expect(table.rows.map((row) => row.length), [3, 1]);
  });
}
