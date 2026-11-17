import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _tableNamespace = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _textNamespace = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _styleNamespace = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';

WmlTableCell _cell(
  String text, {
  int columns = 1,
  WmlVMerge merge = WmlVMerge.none,
  String? fill,
}) => WmlTableCell(
  gridSpan: columns,
  vMerge: merge,
  fillColor: fill,
  blocks: [
    WmlParagraph(inlines: [WmlRun(text: text)]),
  ],
);

WmlTable _table(List<List<WmlTableCell>> rows, {List<double>? grid}) =>
    WmlTable(
      grid: grid ?? [],
      rows: [for (final cells in rows) WmlTableRow(cells: cells)],
    );

({OpcPackage package, XmlElement content, XmlElement table}) _export(
  WmlTable table,
) {
  final document = WmlDocument(
    sections: [
      WmlSection(blocks: [table]),
    ],
  );
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  final content = XmlDocument.parse(
    package.getPart('/content.xml')!.readText(),
  );
  return (
    package: package,
    content: content.root!,
    table: content.root!
        .firstChild('body')!
        .firstChild('text')!
        .childrenNamed('table', namespaceUri: _tableNamespace)
        .single,
  );
}

List<XmlElement> _rows(XmlElement table) =>
    table.childrenNamed('table-row', namespaceUri: _tableNamespace);

List<XmlElement> _physicalCells(XmlElement row) => row.childElements
    .where((node) => node.namespaceUri == _tableNamespace)
    .toList();

// Interpret only the ODF repetition attribute; expected ownership and span
// extents below are authored independently of the export algorithm.
List<XmlElement> _slots(XmlElement row) {
  final result = <XmlElement>[];
  for (final cell in _physicalCells(row)) {
    final count = int.parse(
      cell.getAttribute('number-columns-repeated') ?? '1',
    );
    if (count < 1 || count > 16) {
      throw StateError('Unexpected expansion in small test fixture: $count');
    }
    result.addAll(List<XmlElement>.filled(count, cell));
  }
  return result;
}

List<List<String>> _visibleGrid(XmlElement table) => [
  for (final row in _rows(table))
    [
      for (final cell in _slots(row))
        if (cell.localName == 'covered-table-cell')
          '#'
        else
          cell
              .childrenNamed('p', namespaceUri: _textNamespace)
              .map((p) => p.text)
              .join('|'),
    ],
];

void main() {
  test(
    'infers missing column declarations and uses a relative table width',
    () {
      final output = _export(
        _table([
          [_cell('A', columns: 2), _cell('B')],
          [_cell('C'), _cell('D'), _cell('E')],
        ]),
      );
      final columns = output.table.childrenNamed('table-column');
      expect(columns, hasLength(1));
      expect(columns.single.getAttribute('number-columns-repeated'), '3');
      final style = output.content
          .firstChild('automatic-styles')!
          .childrenNamed('style')
          .singleWhere(
            (s) =>
                s.getAttribute('name') ==
                output.table.getAttribute('style-name'),
          );
      final properties = style.firstChild('table-properties')!;
      expect(properties.getAttribute('rel-width'), '100%');
      expect(properties.getAttribute('width'), isNull);
    },
  );

  test('extends a partial authored grid without discarding known widths', () {
    final output = _export(
      _table(
        [
          [_cell('Wide', columns: 3)],
        ],
        grid: [72],
      ),
    );
    final columns = output.table.childrenNamed('table-column');
    expect(columns, hasLength(2));
    expect(columns.first.getAttribute('style-name'), isNotNull);
    expect(columns.last.getAttribute('number-columns-repeated'), '2');
    expect(
      output.package.getPart('/content.xml')!.readText(),
      contains('style:column-width="72.00pt"'),
    );
  });

  test('exports a three-row vertical merge with covered positions', () {
    final table = _table(
      [
        [_cell('Anchor', merge: WmlVMerge.restart), _cell('A')],
        [_cell('', merge: WmlVMerge.cont), _cell('B')],
        [_cell('', merge: WmlVMerge.cont), _cell('C')],
      ],
      grid: [72, 96],
    );
    final output = _export(table);
    expect(_visibleGrid(output.table), [
      ['Anchor', 'A'],
      ['#', 'B'],
      ['#', 'C'],
    ]);
    final anchor = _slots(_rows(output.table).first).first;
    expect(anchor.getAttribute('number-rows-spanned'), '3');
    expect(anchor.getAttribute('number-columns-spanned'), isNull);
    expect(output.table.childrenNamed('table-column'), hasLength(2));
  });

  test('exports mixed rectangular and adjacent independent merges', () {
    final table = _table(
      [
        [
          _cell('Wide', columns: 2, merge: WmlVMerge.restart),
          _cell('Narrow', merge: WmlVMerge.restart),
          _cell('A'),
        ],
        [
          _cell('', columns: 2, merge: WmlVMerge.cont),
          _cell('', merge: WmlVMerge.cont),
          _cell('B'),
        ],
        [
          _cell('', columns: 2, merge: WmlVMerge.cont),
          _cell('Lower', columns: 2),
        ],
      ],
      grid: [36, 36, 72, 72],
    );
    final output = _export(table).table;
    expect(_visibleGrid(output), [
      ['Wide', '#', 'Narrow', 'A'],
      ['#', '#', '#', 'B'],
      ['#', '#', 'Lower', '#'],
    ]);
    final anchors = _slots(_rows(output).first);
    expect(anchors[0].getAttribute('number-columns-spanned'), '2');
    expect(anchors[0].getAttribute('number-rows-spanned'), '3');
    expect(anchors[2].getAttribute('number-rows-spanned'), '2');
    expect(
      _slots(_rows(output).last)[2].getAttribute('number-rows-spanned'),
      isNull,
    );
  });

  test('new restart and ordinary cells terminate previous merge ownership', () {
    final output = _export(
      _table([
        [_cell('First', merge: WmlVMerge.restart)],
        [_cell('', merge: WmlVMerge.cont)],
        [_cell('Second', merge: WmlVMerge.restart)],
        [_cell('', merge: WmlVMerge.cont)],
        [_cell('Ordinary')],
        [_cell('Orphan', merge: WmlVMerge.cont)],
      ]),
    ).table;
    expect(_visibleGrid(output), [
      ['First'],
      ['#'],
      ['Second'],
      ['#'],
      ['Ordinary'],
      ['Orphan'],
    ]);
    expect(
      _slots(_rows(output)[0]).first.getAttribute('number-rows-spanned'),
      '2',
    );
    expect(
      _slots(_rows(output)[2]).first.getAttribute('number-rows-spanned'),
      '2',
    );
  });

  test('orphan continuations stay visible and cannot establish an anchor', () {
    final output = _export(
      _table([
        [_cell('First orphan', merge: WmlVMerge.cont)],
        [_cell('Second orphan', merge: WmlVMerge.cont)],
      ]),
    ).table;
    expect(_visibleGrid(output), [
      ['First orphan'],
      ['Second orphan'],
    ]);
    expect(_physicalCells(_rows(output).first).single.localName, 'table-cell');
  });

  test('column-span mismatches retain both stories in ordinary cells', () {
    final output = _export(
      _table([
        [_cell('Wide', columns: 2, merge: WmlVMerge.restart)],
        [_cell('Left', merge: WmlVMerge.cont), _cell('Right')],
        [_cell('Later', columns: 2, merge: WmlVMerge.cont)],
      ]),
    ).table;
    expect(_visibleGrid(output), [
      ['Wide', '#'],
      ['Left', 'Right'],
      ['Later', '#'],
    ]);
    expect(
      _slots(_rows(output).first).first.getAttribute('number-rows-spanned'),
      isNull,
    );
  });

  test(
    'continuations inside a preceding wide cell do not hide shifted text',
    () {
      final output = _export(
        _table([
          [_cell('Anchor', columns: 2, merge: WmlVMerge.restart), _cell('A')],
          [_cell('B'), _cell('Shifted', columns: 2, merge: WmlVMerge.cont)],
        ]),
      ).table;
      expect(_visibleGrid(output), [
        ['Anchor', '#', 'A'],
        ['B', 'Shifted', '#'],
      ]);
      expect(
        _slots(_rows(output).first).first.getAttribute('number-rows-spanned'),
        isNull,
      );
    },
  );

  test(
    'a missing row cell interrupts its chain without damaging its neighbor',
    () {
      final output = _export(
        _table([
          [
            _cell('Left', merge: WmlVMerge.restart),
            _cell('Right', merge: WmlVMerge.restart),
          ],
          [_cell('', merge: WmlVMerge.cont)],
          [
            _cell('', merge: WmlVMerge.cont),
            _cell('Visible', merge: WmlVMerge.cont),
          ],
        ]),
      ).table;
      expect(_visibleGrid(output), [
        ['Left', 'Right'],
        ['#', ''],
        ['#', 'Visible'],
      ]);
      final first = _slots(_rows(output).first);
      expect(first[0].getAttribute('number-rows-spanned'), '3');
      expect(first[1].getAttribute('number-rows-spanned'), isNull);
    },
  );

  for (final span in [0, -2]) {
    test(
      'invalid span $span breaks merge inference and preserves all text',
      () {
        final output = _export(
          _table([
            [_cell('Anchor', merge: WmlVMerge.restart), _cell('A')],
            [
              _cell('Visible', merge: WmlVMerge.cont),
              _cell('Invalid', columns: span),
            ],
            [_cell('Still visible', merge: WmlVMerge.cont), _cell('B')],
          ]),
        ).table;
        expect(_visibleGrid(output), [
          ['Anchor', 'A'],
          ['Visible', 'Invalid'],
          ['Still visible', 'B'],
        ]);
        expect(
          _slots(_rows(output).first).first.getAttribute('number-rows-spanned'),
          isNull,
        );
      },
    );
  }

  test(
    'row omissions retain offsets and do not create phantom continuations',
    () {
      final table = _table(
        [
          [_cell('Anchor', columns: 2, merge: WmlVMerge.restart)],
          [_cell('', columns: 2, merge: WmlVMerge.cont)],
          [_cell('Shifted', columns: 2, merge: WmlVMerge.cont)],
        ],
        grid: [36, 36, 36, 36, 36],
      );
      table.rows[0]
        ..gridBefore = 1
        ..gridAfter = 2;
      table.rows[1]
        ..gridBefore = 1
        ..gridAfter = 2;
      table.rows[2]
        ..gridBefore = 2
        ..gridAfter = 1;
      final output = _export(table).table;
      expect(_visibleGrid(output), [
        ['', 'Anchor', '#', '', ''],
        ['', '#', '#', '', ''],
        ['', '', 'Shifted', '#', ''],
      ]);
      expect(
        _slots(_rows(output).first)[1].getAttribute('number-rows-spanned'),
        '2',
      );
    },
  );

  for (final before in [true, false]) {
    test(
      'negative ${before ? 'leading' : 'trailing'} omission prevents inference',
      () {
        final table = _table([
          [_cell('Anchor', merge: WmlVMerge.restart)],
          [_cell('Visible', merge: WmlVMerge.cont)],
        ]);
        if (before) {
          table.rows[1].gridBefore = -1;
        } else {
          table.rows[1].gridAfter = -1;
        }
        expect(_visibleGrid(_export(table).table), [
          ['Anchor'],
          ['Visible'],
        ]);
      },
    );
  }

  test(
    'preserves anchor formatting and hidden continuation stories without mutation',
    () {
      final anchor = _cell('Anchor', merge: WmlVMerge.restart, fill: 'ABCDEF');
      final run =
          (anchor.blocks.single as WmlParagraph).inlines.single as WmlRun;
      run.properties = WmlRunProps(bold: true, color: '123456');
      final continuation = _cell(
        'Hidden',
        merge: WmlVMerge.cont,
        fill: 'FEDCBA',
      );
      final table = _table([
        [anchor],
        [continuation],
      ]);
      final originalRows = List<WmlTableRow>.of(table.rows);
      final originalAnchorBlocks = List<WmlBlock>.of(anchor.blocks);
      final originalContinuationBlocks = List<WmlBlock>.of(continuation.blocks);
      final first = _export(table);
      final second = _export(table);
      expect(
        first.package.getPart('/content.xml')!.readText(),
        second.package.getPart('/content.xml')!.readText(),
      );
      expect(_visibleGrid(first.table), [
        ['Anchor'],
        ['#'],
      ]);
      final covered = _physicalCells(_rows(first.table)[1]).single;
      expect(covered.text, 'Hidden');
      expect(covered.getAttribute('style-name'), isNotNull);
      expect(covered.getAttribute('number-columns-spanned'), isNull);
      expect(covered.getAttribute('number-rows-spanned'), isNull);
      final styles = first.content.firstChild('automatic-styles')!;
      final anchorXml = _slots(_rows(first.table).first).first;
      final style = styles
          .childrenNamed('style', namespaceUri: _styleNamespace)
          .singleWhere(
            (s) =>
                s.getAttribute('name') == anchorXml.getAttribute('style-name'),
          );
      expect(
        style
            .firstChild('table-cell-properties')!
            .getAttribute('background-color'),
        '#abcdef',
      );
      final xml = first.package.getPart('/content.xml')!.readText();
      expect(xml, contains('fo:font-weight="bold"'));
      expect(xml, contains('fo:color="#123456"'));
      expect(table.rows, orderedEquals(originalRows));
      expect(table.rows[0].cells.single, same(anchor));
      expect(table.rows[1].cells.single, same(continuation));
      expect(anchor.blocks, orderedEquals(originalAnchorBlocks));
      expect(continuation.blocks, orderedEquals(originalContinuationBlocks));
      expect(
        (anchor.gridSpan, anchor.vMerge, anchor.fillColor),
        (1, WmlVMerge.restart, 'ABCDEF'),
      );
      expect(
        (continuation.gridSpan, continuation.vMerge, continuation.fillColor),
        (1, WmlVMerge.cont, 'FEDCBA'),
      );
      expect((anchor.blocks.single as WmlParagraph).inlines.single, same(run));
    },
  );

  test('nested table chains remain separate from their enclosing merge', () {
    final inner = _table([
      [_cell('Inner', columns: 2, merge: WmlVMerge.restart)],
      [_cell('', columns: 2, merge: WmlVMerge.cont)],
    ]);
    final anchor = _cell('Outer', merge: WmlVMerge.restart)..blocks.add(inner);
    final outer = _table([
      [anchor],
      [_cell('', merge: WmlVMerge.cont)],
    ]);
    final output = _export(outer).table;
    final outerAnchor = _slots(_rows(output).first).first;
    final nested = outerAnchor
        .childrenNamed('table', namespaceUri: _tableNamespace)
        .single;
    expect(_visibleGrid(output), [
      ['Outer'],
      ['#'],
    ]);
    expect(_visibleGrid(nested), [
      ['Inner', '#'],
      ['#', '#'],
    ]);
    expect(outerAnchor.getAttribute('number-rows-spanned'), '2');
    expect(
      _slots(_rows(nested).first).first.getAttribute('number-rows-spanned'),
      '2',
    );
    expect(nested.getAttribute('name'), isNot(output.getAttribute('name')));
  });

  test('native DOCX rectangular merge retains its geometry in ODT', () {
    final source = OpcPackage.create(OpcPackageKind.word);
    source.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
<w:tbl><w:tblGrid><w:gridCol w:w="720"/><w:gridCol w:w="720"/><w:gridCol w:w="720"/></w:tblGrid>
<w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/><w:vMerge w:val="restart"/></w:tcPr><w:p><w:r><w:t>Native</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc></w:tr>
<w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/><w:vMerge/></w:tcPr><w:p/></w:tc><w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr>
</w:tbl><w:sectPr/></w:body></w:document>''');
    final document = WordDeserializer().read(source);
    final table = document.sections.single.blocks.single as WmlTable;
    expect(WordTable.supportsGridAddressing(table), isTrue);
    final output = _export(table).table;
    expect(_visibleGrid(output), [
      ['Native', '#', 'A'],
      ['#', '#', 'B'],
    ]);
    final anchor = _slots(_rows(output).first).first;
    expect(anchor.getAttribute('number-rows-spanned'), '2');
    expect(anchor.getAttribute('number-columns-spanned'), '2');
  });

  test(
    'huge spans and omissions stay compact and do not allocate grid slots',
    () {
      const count = 1000000000;
      final table = _table([
        [_cell('Wide', columns: count, merge: WmlVMerge.restart)],
        [_cell('Hidden', columns: count, merge: WmlVMerge.cont)],
      ]);
      for (final row in table.rows) {
        row
          ..gridBefore = count
          ..gridAfter = count;
      }
      final output = _export(table);
      expect(
        output.package.getPart('/content.xml')!.readText().length,
        lessThan(5000),
      );
      final first = _physicalCells(_rows(output.table).first);
      final second = _physicalCells(_rows(output.table).last);
      expect(first, hasLength(4));
      expect(second, hasLength(4));
      expect(first[0].getAttribute('number-columns-repeated'), '$count');
      expect(first[1].getAttribute('number-columns-spanned'), '$count');
      expect(first[1].getAttribute('number-rows-spanned'), '2');
      expect(first[2].getAttribute('number-columns-repeated'), '${count - 1}');
      expect(second[1].localName, 'covered-table-cell');
      expect(second[1].text, 'Hidden');
    },
  );

  test(
    'logical offsets remain distinct beyond the web exact integer range',
    () {
      final huge = int.parse('9007199254740991');
      final table = _table([
        [
          _cell('Wide', columns: huge),
          _cell('Before'),
          _cell('Anchor', merge: WmlVMerge.restart),
        ],
        [
          _cell('Wide', columns: huge),
          _cell('Shift'),
          _cell('Gap'),
          _cell('Visible', merge: WmlVMerge.cont),
        ],
      ]);
      final output = _export(table).table;
      final first = _physicalCells(_rows(output).first);
      final last = _physicalCells(_rows(output).last);
      expect(first.last.getAttribute('number-rows-spanned'), isNull);
      expect(last.last.localName, 'table-cell');
      expect(last.last.text, 'Visible');
    },
  );

  test('empty rows interrupt active merge chains', () {
    final output = _export(
      _table([
        [_cell('Anchor', merge: WmlVMerge.restart)],
        [],
        [_cell('Visible', merge: WmlVMerge.cont)],
      ]),
    ).table;
    expect(_visibleGrid(output), [
      ['Anchor'],
      [''],
      ['Visible'],
    ]);
    expect(
      _slots(_rows(output).first).first.getAttribute('number-rows-spanned'),
      isNull,
    );
  });

  test('an empty table has declared columns and a nonempty blank row', () {
    final source = _table([]);
    final output = _export(source).table;
    expect(output.childrenNamed('table-column'), hasLength(1));
    expect(_visibleGrid(output), [
      [''],
    ]);
    expect(source.rows, isEmpty);
    expect(source.grid, isEmpty);
  });

  test('an empty table retains the full authored grid width', () {
    final source = _table([], grid: [30, 60, 90]);
    final output = _export(source).table;
    expect(output.childrenNamed('table-column'), hasLength(3));
    expect(_visibleGrid(output), [
      ['', '', ''],
    ]);
    final placeholder = _physicalCells(_rows(output).single).single;
    expect(placeholder.localName, 'table-cell');
    expect(placeholder.getAttribute('number-columns-repeated'), '3');
    expect(placeholder.childrenNamed('p'), hasLength(1));
    expect(source.rows, isEmpty);
  });

  test(
    'all empty rows retain their number and receive ordinary blank cells',
    () {
      final source = _table([[], [], []]);
      final output = _export(source).table;
      expect(_visibleGrid(output), [
        [''],
        [''],
        [''],
      ]);
      expect(source.rows, hasLength(3));
      expect(source.rows.every((row) => row.cells.isEmpty), isTrue);
    },
  );

  test('ragged rows are padded compactly to the authored grid width', () {
    final source = _table(
      [
        [_cell('A')],
        [],
        [_cell('B'), _cell('C')],
      ],
      grid: [40, 40, 40, 40],
    );
    final output = _export(source).table;
    expect(_visibleGrid(output), [
      ['A', '', '', ''],
      ['', '', '', ''],
      ['B', 'C', '', ''],
    ]);
    expect(
      _physicalCells(
        _rows(output).first,
      ).last.getAttribute('number-columns-repeated'),
      '3',
    );
    expect(source.rows.map((row) => row.cells.length), [1, 0, 2]);
  });

  test(
    'ragged rows are padded to the widest inferred row without moving text',
    () {
      final source = _table([
        [_cell('Wide', columns: 3)],
        [_cell('Narrow')],
        [_cell('Omitted')],
      ]);
      source.rows.last
        ..gridBefore = 1
        ..gridAfter = 1;
      final output = _export(source).table;
      expect(_visibleGrid(output), [
        ['Wide', '#', '#'],
        ['Narrow', '', ''],
        ['', 'Omitted', ''],
      ]);
      expect(
        _physicalCells(
          _rows(output)[1],
        ).last.getAttribute('number-columns-repeated'),
        '2',
      );
    },
  );

  test(
    'empty-row padding retains exact BigInt widths without grid allocation',
    () {
      final huge = int.parse('9007199254740991');
      final source = _table([
        [
          _cell('First', columns: huge),
          _cell('Second', columns: huge),
          _cell('Last'),
        ],
        [],
      ]);
      final output = _export(source);
      expect(
        output.package.getPart('/content.xml')!.readText().length,
        lessThan(6000),
      );
      const expected = '18014398509481983';
      expect(
        output.table
            .childrenNamed('table-column')
            .single
            .getAttribute('number-columns-repeated'),
        expected,
      );
      final placeholder = _physicalCells(_rows(output.table).last).single;
      expect(placeholder.localName, 'table-cell');
      expect(placeholder.getAttribute('number-columns-repeated'), expected);
      expect(placeholder.childrenNamed('p'), hasLength(1));
      expect(source.rows.last.cells, isEmpty);
    },
  );
}
