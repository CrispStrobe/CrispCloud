import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _tableNs = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

void main() {
  group('ODT paragraph tab fidelity', () {
    for (final plainFirst in [true, false]) {
      test('custom tabs stay local with plainFirst=$plainFirst', () {
        final custom = WmlParagraphProps(
          tabs: const [WmlTabStop(position: 72)],
        );
        final properties = plainFirst
            ? [WmlParagraphProps(), custom, WmlParagraphProps()]
            : [custom, WmlParagraphProps(), custom];
        final (output, paragraphs) = _paragraphs(properties);
        for (var index = 0; index < properties.length; index++) {
          final stops = output.tabs(paragraphs[index]);
          expect(stops, hasLength(properties[index].tabs.length));
          if (stops.isNotEmpty) {
            expect(_styleAttribute(stops.single, 'position'), '72.00pt');
          }
          expect(_visibleText(paragraphs[index]), 'Column $index\tTail $index');
          expect(_elements(paragraphs[index], 'tab', _textNs), hasLength(1));
        }
      });
    }

    test('different tab positions resolve to their own paragraph styles', () {
      final (output, paragraphs) = _paragraphs([
        for (final position in [36.0, 72.0, 108.0])
          WmlParagraphProps(tabs: [WmlTabStop(position: position)]),
      ]);
      expect(paragraphs.map(_paragraphStyle).toSet(), hasLength(3));
      expect(
        paragraphs.map(
          (paragraph) =>
              _styleAttribute(output.tabs(paragraph).single, 'position'),
        ),
        ['36.00pt', '72.00pt', '108.00pt'],
      );
    });

    test('left center right and decimal tabs stay distinct', () {
      final (output, paragraphs) = _paragraphs([
        for (final alignment in WmlTabAlignment.values)
          WmlParagraphProps(
            tabs: [WmlTabStop(position: 72, alignment: alignment)],
          ),
      ]);
      expect(paragraphs.map(_paragraphStyle).toSet(), hasLength(4));
      const types = ['left', 'center', 'right', 'char'];
      for (var index = 0; index < paragraphs.length; index++) {
        final tab = output.tabs(paragraphs[index]).single;
        expect(_styleAttribute(tab, 'type'), types[index]);
        expect(_styleAttribute(tab, 'char'), index == 3 ? '.' : null);
      }
    });

    test('none dot hyphen and underscore leaders retain their characters', () {
      final (output, paragraphs) = _paragraphs([
        for (final leader in WmlTabLeader.values)
          WmlParagraphProps(tabs: [WmlTabStop(position: 144, leader: leader)]),
      ]);
      expect(paragraphs.map(_paragraphStyle).toSet(), hasLength(4));
      const characters = <String?>[null, '.', '-', '_'];
      const lineStyles = <String?>[null, 'dotted', 'solid', 'solid'];
      for (var index = 0; index < paragraphs.length; index++) {
        final tab = output.tabs(paragraphs[index]).single;
        expect(_styleAttribute(tab, 'leader-text'), characters[index]);
        expect(_styleAttribute(tab, 'leader-style'), lineStyles[index]);
        expect(
          _styleAttribute(tab, 'leader-type'),
          index == 0 ? null : 'single',
        );
      }
    });

    test(
      'equivalent emitted tab stops reuse styles without changing input',
      () {
        final properties = [
          for (final position in [72.001, 72.004, 72.006])
            WmlParagraphProps(
              tabs: [
                WmlTabStop(
                  position: position,
                  alignment: WmlTabAlignment.right,
                  leader: WmlTabLeader.dot,
                ),
              ],
            ),
        ];
        final originalLists = properties.map((props) => props.tabs).toList();
        final (output, paragraphs) = _paragraphs(properties);
        expect(_paragraphStyle(paragraphs[0]), _paragraphStyle(paragraphs[1]));
        expect(
          _paragraphStyle(paragraphs[0]),
          isNot(_paragraphStyle(paragraphs[2])),
        );
        expect(
          paragraphs.map(
            (paragraph) =>
                _styleAttribute(output.tabs(paragraph).single, 'position'),
          ),
          ['72.00pt', '72.00pt', '72.01pt'],
        );
        for (var index = 0; index < properties.length; index++) {
          expect(
            identical(properties[index].tabs, originalLists[index]),
            isTrue,
          );
        }
        expect(properties.map((props) => props.tabs.single.position), [
          72.001,
          72.004,
          72.006,
        ]);
      },
    );

    for (final invalid in [
      double.nan,
      double.infinity,
      -double.infinity,
      1e21,
    ]) {
      test(
        'invalid tab position $invalid is omitted without losing valid tabs',
        () {
          final invalidStop = WmlTabStop(position: invalid);
          final props = WmlParagraphProps(
            tabs: [invalidStop, const WmlTabStop(position: 72)],
          );
          final originalTabs = props.tabs;
          final (output, paragraphs) = _paragraphs([
            WmlParagraphProps(),
            props,
            WmlParagraphProps(tabs: const [WmlTabStop(position: 72)]),
          ]);
          final emitted = output.tabs(paragraphs[1]);
          expect(emitted, hasLength(1));
          expect(_styleAttribute(emitted.single, 'position'), '72.00pt');
          expect(
            _paragraphStyle(paragraphs[1]),
            _paragraphStyle(paragraphs[2]),
          );
          expect(identical(props.tabs, originalTabs), isTrue);
          expect(props.tabs.first, same(invalidStop));
          expect(props.tabs, hasLength(2));
        },
      );
    }

    test(
      'invalid-only tabs do not create an empty override or a distinct style',
      () {
        final (output, paragraphs) = _paragraphs([
          WmlParagraphProps(tabs: const [WmlTabStop(position: double.nan)]),
          WmlParagraphProps(),
        ]);
        for (final paragraph in paragraphs) {
          expect(
            output
                .properties(paragraph, 'paragraph')!
                .firstChild('tab-stops', namespaceUri: _styleNs),
            isNull,
          );
        }
        expect(_paragraphStyle(paragraphs[0]), _paragraphStyle(paragraphs[1]));
      },
    );

    test('negative and zero tab positions preserve the authored order', () {
      final (output, paragraphs) = _paragraphs([
        WmlParagraphProps(
          tabs: const [
            WmlTabStop(position: 72),
            WmlTabStop(position: -12),
            WmlTabStop(position: 0),
          ],
        ),
      ]);
      expect(
        output
            .tabs(paragraphs.single)
            .map((tab) => _styleAttribute(tab, 'position')),
        ['72.00pt', '-12.00pt', '0.00pt'],
      );
    });

    test(
      'section-start tab styles retain decoration and decimal alignment',
      () {
        final output = _OdtExport(
          WmlDocument(
            sections: [
              for (final position in [72.0, 108.0])
                WmlSection(
                  blocks: [
                    WmlParagraph(
                      properties: WmlParagraphProps(
                        shadingFill: 'AABBCC',
                        borderColor: '123456',
                        tabs: [
                          WmlTabStop(
                            position: position,
                            alignment: WmlTabAlignment.decimal,
                          ),
                        ],
                      ),
                      inlines: [WmlRun(text: 'Value\t12.34')],
                    ),
                  ],
                ),
            ],
          ),
        );
        final paragraphs = output.body
            .childrenNamed('p', namespaceUri: _textNs)
            .toList();
        expect(paragraphs, hasLength(2));
        for (var index = 0; index < paragraphs.length; index++) {
          final props = output.properties(paragraphs[index], 'paragraph')!;
          expect(
            props.getAttribute('background-color', namespaceUri: _foNs),
            '#aabbcc',
          );
          expect(
            props.getAttribute('border', namespaceUri: _foNs),
            '0.5pt solid #123456',
          );
          final tab = output.tabs(paragraphs[index]).single;
          expect(
            _styleAttribute(tab, 'position'),
            index == 0 ? '72.00pt' : '108.00pt',
          );
          expect(_styleAttribute(tab, 'type'), 'char');
          expect(_styleAttribute(tab, 'char'), '.');
        }
      },
    );
  });

  group('ODT table row fidelity', () {
    test('row height remains a minimum for multiline cell content', () {
      final row = WmlTableRow(
        height: 12,
        cells: [
          WmlTableCell(
            blocks: [
              for (var index = 0; index < 4; index++)
                WmlParagraph(inlines: [WmlRun(text: 'Line $index')]),
            ],
          ),
        ],
      );
      final output = _table([row]);
      final emitted = output.rows.single;
      final props = output.properties(emitted, 'table-row')!;
      expect(_styleAttribute(props, 'min-row-height'), '12.00pt');
      expect(_styleAttribute(props, 'row-height'), isNull);
      expect(_elements(emitted, 'p', _textNs).map((p) => p.text), [
        'Line 0',
        'Line 1',
        'Line 2',
        'Line 3',
      ]);
      expect(row.height, 12);
      expect(row.cells.single.blocks, hasLength(4));
    });

    test('zero and negative zero are valid minimum heights', () {
      final output = _table([
        WmlTableRow(height: 0, cells: [_cell('zero')]),
        WmlTableRow(height: -0.0, cells: [_cell('negative zero')]),
      ]);
      for (final row in output.rows) {
        final props = output.properties(row, 'table-row')!;
        expect(_styleAttribute(props, 'min-row-height'), '0.00pt');
        expect(_styleAttribute(props, 'row-height'), isNull);
      }
      expect(_tableStyle(output.rows[0]), _tableStyle(output.rows[1]));
    });

    const invalidHeights = [
      -1.0,
      -0.001,
      double.nan,
      double.infinity,
      -double.infinity,
      1e21,
    ];
    for (var index = 0; index < invalidHeights.length; index++) {
      final invalid = invalidHeights[index];
      test(
        'invalid row height $index is omitted and leaves cell content intact',
        () {
          final row = WmlTableRow(height: invalid, cells: [_cell('retained')]);
          final output = _table([row]);
          expect(_tableStyle(output.rows.single), isNull);
          expect(_visibleText(output.rows.single), 'retained');
          if (invalid.isNaN) {
            expect(row.height!.isNaN, isTrue);
          } else {
            expect(row.height, invalid);
          }
        },
      );
    }

    test(
      'equal emitted minima share styles and different heights stay distinct',
      () {
        final output = _table([
          for (final height in [24.001, 24.004, 36.0])
            WmlTableRow(height: height, cells: [_cell('$height')]),
        ]);
        expect(_tableStyle(output.rows[0]), _tableStyle(output.rows[1]));
        expect(_tableStyle(output.rows[0]), isNot(_tableStyle(output.rows[2])));
        expect(
          output.rows.map(
            (row) => _styleAttribute(
              output.properties(row, 'table-row')!,
              'min-row-height',
            ),
          ),
          ['24.00pt', '24.00pt', '36.00pt'],
        );
      },
    );

    test('an unspecified row height leaves natural content sizing', () {
      final output = _table([
        WmlTableRow(cells: [_cell('natural')]),
      ]);
      expect(_tableStyle(output.rows.single), isNull);
      expect(_visibleText(output.rows.single), 'natural');
    });
  });

  group('ODT table cell fidelity', () {
    test(
      'normalized fills share styles while different colors stay distinct',
      () {
        final cells = [
          for (final fill in ['AABBCC', 'aabbcc', '112233'])
            WmlTableCell(
              fillColor: fill,
              borderTop: true,
              blocks: [
                WmlParagraph(inlines: [WmlRun(text: fill)]),
              ],
            ),
        ];
        final output = _table([WmlTableRow(cells: cells)]);
        final emitted = output.cells;
        expect(_tableStyle(emitted[0]), _tableStyle(emitted[1]));
        expect(_tableStyle(emitted[0]), isNot(_tableStyle(emitted[2])));
        expect(
          emitted.map(
            (cell) => output
                .properties(cell, 'table-cell')!
                .getAttribute('background-color', namespaceUri: _foNs),
          ),
          ['#aabbcc', '#aabbcc', '#112233'],
        );
        expect(cells.map((cell) => cell.fillColor), [
          'AABBCC',
          'aabbcc',
          '112233',
        ]);
      },
    );

    test('all four border flags stay independent for equal fills', () {
      final output = _table([
        WmlTableRow(
          cells: [
            for (var flags = 0; flags < 16; flags++)
              WmlTableCell(
                fillColor: 'ABCDEF',
                borderTop: flags & 1 != 0,
                borderBottom: flags & 2 != 0,
                borderLeft: flags & 4 != 0,
                borderRight: flags & 8 != 0,
                blocks: [
                  WmlParagraph(inlines: [WmlRun(text: '$flags')]),
                ],
              ),
          ],
        ),
      ]);
      expect(output.cells.map(_tableStyle).toSet(), hasLength(16));
      const sides = ['top', 'bottom', 'left', 'right'];
      for (var flags = 0; flags < 16; flags++) {
        final props = output.properties(output.cells[flags], 'table-cell')!;
        for (var side = 0; side < sides.length; side++) {
          expect(
            props.getAttribute('border-${sides[side]}', namespaceUri: _foNs),
            flags & (1 << side) != 0 ? '0.5pt solid #000000' : null,
          );
        }
      }
    });

    const invalidFills = [
      '',
      '#112233',
      '12345',
      '1234567',
      'GGHHII',
      '112233"',
      'ABCDEF" bogus="1',
      '&',
      '<bad>',
      '112233\n',
      '\u0000abcde',
      'transparent',
    ];
    for (var index = 0; index < invalidFills.length; index++) {
      test(
        'invalid fill $index cannot break XML or suppress a valid border',
        () {
          final fill = invalidFills[index];
          final withBorder = WmlTableCell(
            fillColor: fill,
            borderBottom: true,
            blocks: [
              WmlParagraph(inlines: [WmlRun(text: 'border retained')]),
            ],
          );
          final withoutBorder = WmlTableCell(
            fillColor: fill,
            blocks: [
              WmlParagraph(inlines: [WmlRun(text: 'plain retained')]),
            ],
          );
          final output = _table([
            WmlTableRow(
              cells: [
                withBorder,
                withoutBorder,
                WmlTableCell(
                  borderBottom: true,
                  blocks: [_paragraph('same border')],
                ),
              ],
            ),
          ]);
          final props = output.properties(output.cells[0], 'table-cell')!;
          expect(
            props.getAttribute('background-color', namespaceUri: _foNs),
            isNull,
          );
          expect(
            props.getAttribute('border-bottom', namespaceUri: _foNs),
            '0.5pt solid #000000',
          );
          expect(_tableStyle(output.cells[1]), isNull);
          expect(_tableStyle(output.cells[0]), _tableStyle(output.cells[2]));
          expect(output.cells.map(_visibleText), [
            'border retained',
            'plain retained',
            'same border',
          ]);
          expect(withBorder.fillColor, fill);
          expect(withoutBorder.fillColor, fill);
          expect(withBorder.borderBottom, isTrue);
        },
      );
    }
  });
}

String? _styleAttribute(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: _styleNs);

String? _paragraphStyle(XmlElement element) =>
    element.getAttribute('style-name', namespaceUri: _textNs);

String? _tableStyle(XmlElement element) =>
    element.getAttribute('style-name', namespaceUri: _tableNs);

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlTableCell _cell(String text) => WmlTableCell(blocks: [_paragraph(text)]);

(_OdtExport, List<XmlElement>) _paragraphs(List<WmlParagraphProps> properties) {
  final output = _OdtExport(
    WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            _paragraph('Section lead'),
            for (var index = 0; index < properties.length; index++)
              WmlParagraph(
                properties: properties[index],
                inlines: [WmlRun(text: 'Column $index\tTail $index')],
              ),
          ],
        ),
      ],
    ),
  );
  return (
    output,
    output.body.childrenNamed('p', namespaceUri: _textNs).skip(1).toList(),
  );
}

_OdtExport _table(List<WmlTableRow> rows) => _OdtExport(
  WmlDocument(
    sections: [
      WmlSection(blocks: [WmlTable(rows: rows)]),
    ],
  ),
);

Iterable<XmlElement> _elements(
  XmlElement root,
  String name,
  String namespace,
) sync* {
  for (final child in root.children.whereType<XmlElement>()) {
    if (child.localName == name && child.namespaceUri == namespace) yield child;
    yield* _elements(child, name, namespace);
  }
}

String _visibleText(XmlNode node) {
  if (node is XmlText) return node.text;
  if (node is! XmlElement) return '';
  if (node.namespaceUri == _textNs) {
    if (node.localName == 'tab') return '\t';
    if (node.localName == 'line-break') return '\n';
    if (node.localName == 's') {
      return ' ' *
          int.parse(node.getAttribute('c', namespaceUri: _textNs) ?? '1');
    }
  }
  return node.children.map(_visibleText).join();
}

class _OdtExport {
  _OdtExport(WmlDocument document) {
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    content = XmlDocument.parse(
      package.getPart('/content.xml')!.readText(),
    ).root!;
    styles = XmlDocument.parse(
      package.getPart('/styles.xml')!.readText(),
    ).root!;
  }

  late final XmlElement content;
  late final XmlElement styles;

  XmlElement get body => content
      .firstChild('body', namespaceUri: _officeNs)!
      .firstChild('text', namespaceUri: _officeNs)!;

  List<XmlElement> get rows => _elements(body, 'table-row', _tableNs).toList();

  List<XmlElement> get cells =>
      _elements(body, 'table-cell', _tableNs).toList();

  XmlElement? properties(XmlElement element, String family) {
    final name = family == 'paragraph'
        ? _paragraphStyle(element)
        : _tableStyle(element);
    if (name == null) return null;
    final style =
        [
          ..._elements(content, 'style', _styleNs),
          ..._elements(styles, 'style', _styleNs),
        ].firstWhere(
          (style) =>
              _styleAttribute(style, 'name') == name &&
              _styleAttribute(style, 'family') == family,
        );
    return style.firstChild('$family-properties', namespaceUri: _styleNs);
  }

  List<XmlElement> tabs(XmlElement paragraph) =>
      properties(paragraph, 'paragraph')!
          .firstChild('tab-stops', namespaceUri: _styleNs)
          ?.childrenNamed('tab-stop', namespaceUri: _styleNs)
          .toList() ??
      <XmlElement>[];
}
