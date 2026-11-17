import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _tableNs = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

WmlParagraph _paragraph(String text, [List<WmlTabStop> tabs = const []]) =>
    WmlParagraph(
      properties: WmlParagraphProps(tabs: tabs),
      inlines: [WmlRun(text: text)],
    );

XmlElement _export(List<WmlBlock> blocks) {
  // The first paragraph owns the section master. Subsequent paragraphs must
  // independently retain their ordinary paragraph properties.
  final document = WmlDocument(
    sections: [
      WmlSection(blocks: [_paragraph('Section start'), ...blocks]),
    ],
  );
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  return XmlDocument.parse(package.getPart('/content.xml')!.readText()).root!;
}

XmlElement _body(XmlElement content) => content
    .firstChild('body', namespaceUri: _officeNs)!
    .firstChild('text', namespaceUri: _officeNs)!;

XmlElement? _properties(
  XmlElement content,
  XmlElement element,
  String elementNs,
  String propertyName,
) {
  final name = element.getAttribute('style-name', namespaceUri: elementNs);
  if (name == null) return null;
  return content
      .firstChild('automatic-styles', namespaceUri: _officeNs)!
      .childrenNamed('style', namespaceUri: _styleNs)
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == name,
      )
      .firstChild(propertyName, namespaceUri: _styleNs);
}

List<XmlElement> _tabs(XmlElement content, XmlElement paragraph) =>
    _properties(content, paragraph, _textNs, 'paragraph-properties')!
        .firstChild('tab-stops', namespaceUri: _styleNs)
        ?.childrenNamed('tab-stop', namespaceUri: _styleNs)
        .toList() ??
    const [];

List<XmlElement> _paragraphs(XmlElement content) =>
    _body(content).childrenNamed('p', namespaceUri: _textNs).skip(1).toList();

WmlTableCell _cell(String text, {String? fill, bool border = false}) =>
    WmlTableCell(
      fillColor: fill,
      borderRight: border,
      blocks: [_paragraph(text)],
    );

List<XmlElement> _rows(XmlElement content) => _body(content)
    .childrenNamed('table', namespaceUri: _tableNs)
    .single
    .childrenNamed('table-row', namespaceUri: _tableNs)
    .toList();

void main() {
  test('neighboring paragraph column and keep properties stay independent', () {
    final content = _export([
      WmlParagraph(inlines: [WmlRun(text: 'Ordinary')]),
      WmlParagraph(
        properties: WmlParagraphProps(columnBreakBefore: true),
        inlines: [WmlRun(text: 'Column')],
      ),
      WmlParagraph(
        properties: WmlParagraphProps(keepTogether: true),
        inlines: [WmlRun(text: 'Together')],
      ),
      WmlParagraph(inlines: [WmlRun(text: 'Ordinary again')]),
    ]);
    final paragraphs = _paragraphs(content);
    final properties = [
      for (final p in paragraphs)
        _properties(content, p, _textNs, 'paragraph-properties')!,
    ];
    expect(
      properties.map(
        (p) => p.getAttribute('break-before', namespaceUri: _foNs),
      ),
      [null, 'column', null, null],
    );
    expect(
      properties.map(
        (p) => p.getAttribute('keep-together', namespaceUri: _foNs),
      ),
      [null, null, 'always', null],
    );
  });
  test('keeps custom tab positions independent across paragraphs', () {
    final content = _export([
      for (final position in [72.0, 144.0, 72.0])
        _paragraph('Left\tRight', [WmlTabStop(position: position)]),
      _paragraph('No custom tab'),
    ]);
    final paragraphs = _paragraphs(content);
    expect(paragraphs, hasLength(4));
    expect(
      paragraphs
          .take(3)
          .map(
            (paragraph) => _tabs(
              content,
              paragraph,
            ).single.getAttribute('position', namespaceUri: _styleNs),
          ),
      ['72.00pt', '144.00pt', '72.00pt'],
    );
    expect(_tabs(content, paragraphs.last), isEmpty);
  });

  test('keeps tab alignment and decimal characters paragraph-specific', () {
    final content = _export([
      for (final alignment in WmlTabAlignment.values)
        _paragraph('Item\t1.25', [
          WmlTabStop(position: 144, alignment: alignment),
        ]),
    ]);
    final tabs = [
      for (final paragraph in _paragraphs(content))
        _tabs(content, paragraph).single,
    ];
    const types = {
      WmlTabAlignment.left: 'left',
      WmlTabAlignment.center: 'center',
      WmlTabAlignment.right: 'right',
      WmlTabAlignment.decimal: 'char',
    };
    for (var i = 0; i < tabs.length; i++) {
      final alignment = WmlTabAlignment.values[i];
      expect(
        tabs[i].getAttribute('type', namespaceUri: _styleNs),
        types[alignment],
      );
      expect(
        tabs[i].getAttribute('char', namespaceUri: _styleNs),
        alignment == WmlTabAlignment.decimal ? '.' : null,
      );
    }
  });

  test('preserves distinct tab leaders without leaking them to plain tabs', () {
    final content = _export([
      for (final leader in WmlTabLeader.values)
        _paragraph('Item\tValue', [WmlTabStop(position: 144, leader: leader)]),
    ]);
    final paragraphs = _paragraphs(content);
    const characters = {
      WmlTabLeader.none: null,
      WmlTabLeader.dot: '.',
      WmlTabLeader.hyphen: '-',
      WmlTabLeader.underscore: '_',
    };
    for (var i = 0; i < paragraphs.length; i++) {
      final tab = _tabs(content, paragraphs[i]).single;
      expect(
        tab.getAttribute('leader-text', namespaceUri: _styleNs),
        characters[WmlTabLeader.values[i]],
      );
    }
  });

  test(
    'preserves tab order and source values while omitting invalid lengths',
    () {
      const tabs = [
        WmlTabStop(position: 144, leader: WmlTabLeader.dot),
        WmlTabStop(position: double.nan),
        WmlTabStop(position: double.infinity),
        WmlTabStop(position: double.negativeInfinity),
        WmlTabStop(position: 1e21),
        WmlTabStop(position: -12, alignment: WmlTabAlignment.right),
        WmlTabStop(position: 0),
        WmlTabStop(position: 72),
      ];
      final paragraph = _paragraph('One\tTwo\tThree', tabs);
      final content = _export([paragraph]);
      expect(
        _tabs(
          content,
          _paragraphs(content).single,
        ).map((tab) => tab.getAttribute('position', namespaceUri: _styleNs)),
        ['144.00pt', '-12.00pt', '0.00pt', '72.00pt'],
      );
      expect(paragraph.properties.tabs, same(tabs));
      expect(tabs[1].position.isNaN, isTrue);
      expect(paragraph.text, 'One\tTwo\tThree');
    },
  );

  test('exports row height as a minimum so multiline cells can expand', () {
    final row = WmlTableRow(
      height: 6,
      cells: [
        WmlTableCell(
          blocks: [
            _paragraph('First line'),
            _paragraph('Second line'),
            _paragraph('Third line'),
          ],
        ),
      ],
    );
    final content = _export([
      WmlTable(grid: [120], rows: [row]),
    ]);
    final emitted = _rows(content).single;
    final properties = _properties(
      content,
      emitted,
      _tableNs,
      'table-row-properties',
    )!;
    expect(
      properties.getAttribute('min-row-height', namespaceUri: _styleNs),
      '6.00pt',
    );
    expect(
      properties.getAttribute('row-height', namespaceUri: _styleNs),
      isNull,
    );
    expect(emitted.text, contains('Third line'));
    expect(row.height, 6);
    expect(row.cells.single.blocks, hasLength(3));
  });

  test('omits invalid row minima and retains zero and valid dimensions', () {
    const invalid = [
      -1.0,
      -0.001,
      double.nan,
      double.infinity,
      double.negativeInfinity,
      1e21,
    ];
    final sourceRows = [
      for (var i = 0; i < invalid.length; i++)
        WmlTableRow(height: invalid[i], cells: [_cell('Invalid $i')]),
      WmlTableRow(height: 0, cells: [_cell('Zero')]),
      WmlTableRow(height: -0.0, cells: [_cell('Signed zero')]),
      WmlTableRow(height: 24, cells: [_cell('Valid')]),
    ];
    final content = _export([
      WmlTable(grid: [120], rows: sourceRows),
    ]);
    final rows = _rows(content);
    for (final row in rows.take(invalid.length)) {
      final properties = _properties(
        content,
        row,
        _tableNs,
        'table-row-properties',
      );
      expect(
        properties?.getAttribute('min-row-height', namespaceUri: _styleNs),
        isNull,
      );
      expect(
        properties?.getAttribute('row-height', namespaceUri: _styleNs),
        isNull,
      );
    }
    expect(
      rows
          .skip(invalid.length)
          .map(
            (row) => _properties(
              content,
              row,
              _tableNs,
              'table-row-properties',
            )!.getAttribute('min-row-height', namespaceUri: _styleNs),
          ),
      ['0.00pt', '0.00pt', '24.00pt'],
    );
    expect(sourceRows[2].height!.isNaN, isTrue);
    expect(sourceRows.last.height, 24);
  });

  test('omits invalid column widths without dropping columns or cell text', () {
    const widths = [
      0.0,
      -1.0,
      0.001,
      double.nan,
      double.infinity,
      double.negativeInfinity,
      1e21,
      120.0,
    ];
    final content = _export([
      WmlTable(
        grid: widths,
        rows: [
          WmlTableRow(
            cells: [for (var i = 0; i < widths.length; i++) _cell('Cell $i')],
          ),
        ],
      ),
    ]);
    final table = _body(
      content,
    ).childrenNamed('table', namespaceUri: _tableNs).single;
    final columns = table
        .childrenNamed('table-column', namespaceUri: _tableNs)
        .toList();
    expect(columns, hasLength(widths.length));
    for (final column in columns.take(widths.length - 1)) {
      final properties = _properties(
        content,
        column,
        _tableNs,
        'table-column-properties',
      );
      expect(
        properties?.getAttribute('column-width', namespaceUri: _styleNs),
        isNull,
      );
    }
    expect(
      _properties(
        content,
        columns.last,
        _tableNs,
        'table-column-properties',
      )!.getAttribute('column-width', namespaceUri: _styleNs),
      '120.00pt',
    );
    for (var i = 0; i < widths.length; i++) {
      expect(table.text, contains('Cell $i'));
    }
    expect(widths[3].isNaN, isTrue);
  });

  test(
    'normalizes cell fill colors and keeps independent cell decorations',
    () {
      const colors = ['ABCDEF', 'abcdef', '0044ff'];
      final cells = [
        for (var i = 0; i < colors.length; i++)
          _cell('Cell $i', fill: colors[i], border: true),
      ];
      final content = _export([
        WmlTable(
          grid: [72, 72, 72],
          rows: [WmlTableRow(cells: cells)],
        ),
      ]);
      final emitted = _rows(
        content,
      ).single.childrenNamed('table-cell', namespaceUri: _tableNs).toList();
      for (var i = 0; i < emitted.length; i++) {
        final properties = _properties(
          content,
          emitted[i],
          _tableNs,
          'table-cell-properties',
        )!;
        expect(
          properties.getAttribute('background-color', namespaceUri: _foNs),
          '#${colors[i].toLowerCase()}',
        );
        expect(
          properties.getAttribute('border-right', namespaceUri: _foNs),
          '0.5pt solid #000000',
        );
      }
      expect(cells.map((cell) => cell.fillColor), colors);
    },
  );

  test('omits malformed cell colors while preserving borders and text', () {
    const colors = [
      'FFF',
      '#AABBCC',
      'GG0000',
      'AABBCC\n',
      'ＡＡＢＢＣＣ',
      '000000" fo:border-top="9pt solid #ff0000',
      '000000"/><injected/>',
    ];
    final cells = [
      for (var i = 0; i < colors.length; i++)
        _cell('Cell $i', fill: colors[i], border: true),
    ];
    final content = _export([
      WmlTable(rows: [WmlTableRow(cells: cells)]),
    ]);
    final emitted = _rows(
      content,
    ).single.childrenNamed('table-cell', namespaceUri: _tableNs).toList();
    for (var i = 0; i < emitted.length; i++) {
      final properties = _properties(
        content,
        emitted[i],
        _tableNs,
        'table-cell-properties',
      )!;
      expect(
        properties.getAttribute('background-color', namespaceUri: _foNs),
        isNull,
      );
      expect(
        properties.getAttribute('border-top', namespaceUri: _foNs),
        isNull,
      );
      expect(
        properties.getAttribute('border-right', namespaceUri: _foNs),
        '0.5pt solid #000000',
      );
      expect(emitted[i].text, 'Cell $i');
    }
    expect(cells.map((cell) => cell.fillColor), colors);
  });

  test(
    'invalid fill alone leaves the cell unshaded without changing its story',
    () {
      final cell = _cell('Visible text', fill: 'not a color');
      final content = _export([
        WmlTable(
          rows: [
            WmlTableRow(cells: [cell]),
          ],
        ),
      ]);
      final emitted = _rows(
        content,
      ).single.childrenNamed('table-cell', namespaceUri: _tableNs).single;
      final properties = _properties(
        content,
        emitted,
        _tableNs,
        'table-cell-properties',
      );
      expect(
        properties?.getAttribute('background-color', namespaceUri: _foNs),
        isNull,
      );
      expect(emitted.text, 'Visible text');
      expect(cell.fillColor, 'not a color');
    },
  );
}
