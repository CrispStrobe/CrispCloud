import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _item(String text, {int level = 0, String? label, int id = 1}) =>
    WmlParagraph(
      properties: WmlParagraphProps(numId: id, ilvl: level, listLabel: label),
      inlines: [WmlRun(text: text)],
    );

XmlElement _body(List<WmlBlock> blocks) {
  final package = OpcPackage.openBytes(
    OdtDocumentWriter.writeBytes(
      WmlDocument(sections: [WmlSection(blocks: blocks)]),
    ),
  );
  return XmlDocument.parse(
    package.getPart('/content.xml')!.readText(),
  ).root!.firstChild('body')!.firstChild('text')!;
}

OpcPackage _export(WmlDocument document) =>
    OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));

XmlElement _xml(OpcPackage package, [String part = 'content.xml']) =>
    XmlDocument.parse(package.getPart('/$part')!.readText()).root!;

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

List<String?> _starts(XmlElement root) => _elements(
  root,
  'list-item',
).map((item) => item.getAttribute('start-value')).toList();

OpcPackage _nativeNumbering(
  String definitions, {
  bool customRelationship = false,
}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  const custom = '/word/custom/list-definitions.xml';
  package.createPart(
    customRelationship ? custom : '/word/numbering.xml',
    OfficeContentTypes.wordNumbering,
    utf8.encode(
      '<w:numbering xmlns:w="${OfficeNamespaces.w}">$definitions</w:numbering>',
    ),
  );
  if (customRelationship) {
    package
        .relationshipsFor('/word/document.xml')
        .add(
          type: RelationshipTypes.numbering,
          target: 'custom/list-definitions.xml',
        );
  }
  return package;
}

String _text(XmlNode node) => switch (node) {
  XmlText() => node.text,
  XmlElement() => node.children.map(_text).join(),
  _ => '',
};

List<(String, int)> _itemDepths(XmlElement body) {
  final result = <(String, int)>[];
  void visit(XmlElement element, int depth) {
    final next = depth + (element.localName == 'list' ? 1 : 0);
    if (element.localName == 'list-item') {
      final paragraph = element.firstChild('p') ?? element.firstChild('h');
      if (paragraph != null) result.add((_text(paragraph), depth));
    }
    for (final child in element.childElements) {
      visit(child, next);
    }
  }

  visit(body, 0);
  return result;
}

void main() {
  markerTests();
  storyTests();
  group('ODT authored list levels', () {
    for (final (levels, expected) in <(List<int>, List<int>)>[
      ([0, 3, 3, 0], [1, 2, 2, 1]),
      ([2, 2, 2], [1, 1, 1]),
      ([2, 5, 5, 3, 3, 0], [1, 2, 2, 2, 2, 1]),
      ([0, 1, 2, 3, 2, 1, 0], [1, 2, 3, 4, 3, 2, 1]),
      ([8, 8, 0, 8, 8], [1, 1, 1, 2, 2]),
      ([-9, 999, 999, -1], [1, 2, 2, 1]),
    ]) {
      test('normalizes $levels without inventing ancestors', () {
        final items = <WmlParagraph>[
          for (var i = 0; i < levels.length; i++)
            _item('Item $i', level: levels[i]),
        ];
        final body = _body(items);
        expect(_itemDepths(body), [
          for (var i = 0; i < expected.length; i++) ('Item $i', expected[i]),
        ]);
        expect(items.map((item) => item.properties.ilvl), levels);
        expect(items.map((item) => item.text), [
          for (var i = 0; i < levels.length; i++) 'Item $i',
        ]);
      });
    }

    test('mixed bullets and numbers use their own list styles', () {
      final body = _body([
        _item('Numbered parent', label: '1. '),
        _item('Bullet child', level: 2, label: '• '),
        _item('Number child', level: 2, label: '1. '),
        _item('Bullet parent', label: '• '),
      ]);
      final roots = body.childrenNamed('list').toList();
      expect(roots, hasLength(2));
      expect(roots.map((list) => list.getAttribute('style-name')), [
        'L2',
        'L1',
      ]);
      final parent = roots.first.firstChild('list-item')!;
      final children = parent.childrenNamed('list').toList();
      expect(children.map((list) => list.getAttribute('style-name')), [
        'L1',
        'L2',
      ]);
      expect(_itemDepths(body), [
        ('Numbered parent', 1),
        ('Bullet child', 2),
        ('Number child', 2),
        ('Bullet parent', 1),
      ]);
    });

    test('adjacent mixed siblings stay at one output depth', () {
      final body = _body([
        _item('Bullet one', level: 3, label: '• '),
        _item('Number one', level: 3, label: '1. '),
        _item('Number two', level: 3, label: '2. '),
        _item('Bullet two', level: 3, label: '▪ '),
      ]);
      expect(body.childrenNamed('list'), hasLength(3));
      expect(_itemDepths(body), [
        ('Bullet one', 1),
        ('Number one', 1),
        ('Number two', 1),
        ('Bullet two', 1),
      ]);
    });

    test('a changed numbering identity starts a separate list', () {
      final body = _body([
        _item('Parent', id: 7),
        _item('Other', id: 8, level: 3),
        _item('Other sibling', id: 8, level: 3),
      ]);
      expect(body.childrenNamed('list'), hasLength(2));
      expect(_itemDepths(body), [
        ('Parent', 1),
        ('Other', 1),
        ('Other sibling', 1),
      ]);
    });

    test('suppressed numbering interrupts and stays ordinary text', () {
      final suppressed = _item('Ordinary', level: 2)
        ..properties.numberingSuppressed = true;
      final body = _body([
        _item('Before', level: 2),
        suppressed,
        _item('After', level: 2),
      ]);
      expect(body.childElements.map((node) => node.localName), [
        'list',
        'p',
        'list',
      ]);
      expect(_text(body.childrenNamed('p').single), 'Ordinary');
      expect(_itemDepths(body), [('Before', 1), ('After', 1)]);
    });

    test(
      'zero numbering identity is ordinary text without suppression flag',
      () {
        final removed = _item('Removed', id: 0, label: '1.');
        final body = _body([
          _item('Before', label: '1.'),
          removed,
          _item('After', label: '1.'),
        ]);
        expect(body.childElements.map((element) => element.localName), [
          'list',
          'p',
          'list',
        ]);
        expect(_starts(body), ['1', '2']);
        expect(_text(body.childrenNamed('p').single), 'Removed');
        expect(removed.properties.numId, 0);
        expect(removed.properties.numberingSuppressed, isFalse);
      },
    );

    test('paragraph and run formatting remains on a skipped-level child', () {
      final child = _item('Styled', level: 4)
        ..properties.rightToLeft = true
        ..properties.lineSpacingRule = WmlLineSpacingRule.exact
        ..properties.lineSpacing = 18;
      (child.inlines.single as WmlRun).properties.bold = true;
      final body = _body([_item('Parent'), child]);
      final paragraph = body
          .firstChild('list')!
          .firstChild('list-item')!
          .firstChild('list')!
          .firstChild('list-item')!
          .firstChild('p')!;
      expect(paragraph.getAttribute('style-name'), isNotEmpty);
      expect(
        paragraph.firstChild('span')!.getAttribute('style-name'),
        isNotEmpty,
      );
      expect(_text(paragraph), 'Styled');
      expect(child.properties.ilvl, 4);
      expect(child.properties.rightToLeft, isTrue);
      expect((child.inlines.single as WmlRun).properties.bold, isTrue);
    });

    test('deep malformed levels cannot create unbounded recursion', () {
      final items = <WmlParagraph>[
        for (var i = 0; i < 1000; i++) _item('Item $i', level: i),
      ];
      final depths = _itemDepths(_body(items));
      expect(depths, hasLength(items.length));
      expect(
        depths.map((entry) => entry.$2).reduce((a, b) => a > b ? a : b),
        9,
      );
      expect(depths.last, ('Item 999', 9));
    });
  });
}

void markerTests() {
  group('ODT list markers and starts', () {
    for (final parentFormat in ['upperRoman', 'bullet']) {
      test('native $parentFormat parents restart decimal child sequences', () {
        final source = _nativeNumbering(
          '<w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0">'
          '<w:numFmt w:val="$parentFormat"/>'
          '<w:lvlText w:val="${parentFormat == 'bullet' ? '•' : '%1.'}"/>'
          '</w:lvl><w:lvl w:ilvl="1"><w:start w:val="1"/>'
          '<w:numFmt w:val="decimal"/><w:lvlText w:val="%2."/>'
          '</w:lvl></w:abstractNum>'
          '<w:num w:numId="7"><w:abstractNumId w:val="7"/></w:num>',
        );
        final first = parentFormat == 'bullet' ? null : 'I.';
        final second = parentFormat == 'bullet' ? null : 'II.';
        final blocks = [
          _item('Parent first', id: 7, label: first),
          _item('Child first', id: 7, level: 1),
          _item('Child next', id: 7, level: 1),
          _item('Parent second', id: 7, label: second),
          _item('Child reset', id: 7, level: 1),
        ];
        final package = _export(
          WmlDocument(
            package: source,
            sections: [WmlSection(blocks: blocks)],
          ),
        );
        expect(_starts(_xml(package)), [null, '1', '2', null, '1']);
        expect(blocks.map((paragraph) => paragraph.properties.listLabel), [
          first,
          null,
          null,
          second,
          null,
        ]);
      });
    }

    test('special native child restart rules retain literal cached labels', () {
      final source = _nativeNumbering(
        '<w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0">'
        '<w:numFmt w:val="bullet"/><w:lvlText w:val="•"/></w:lvl>'
        '<w:lvl w:ilvl="1"><w:start w:val="1"/>'
        '<w:numFmt w:val="decimal"/><w:lvlText w:val="%2."/>'
        '<w:lvlRestart w:val="0"/></w:lvl></w:abstractNum>'
        '<w:num w:numId="7"><w:abstractNumId w:val="7"/></w:num>',
      );
      final package = _export(
        WmlDocument(
          package: source,
          sections: [
            WmlSection(
              blocks: [
                _item('Parent first', id: 7),
                _item('Child first', id: 7, level: 1, label: '3.'),
                _item('Parent next', id: 7),
                _item('Child continued', id: 7, level: 1, label: '4.'),
              ],
            ),
          ],
        ),
      );
      expect(_starts(_xml(package)), [null, null, null, null]);
      final markers = _elements(
        _xml(package),
        'list-level-style-number',
      ).where((style) => style.getAttribute('level') == '1');
      expect(markers.map((style) => style.getAttribute('num-prefix')), [
        '3.',
        '4.',
      ]);
      expect(markers.map((style) => style.getAttribute('num-format')), [
        '',
        '',
      ]);
    });

    for (final (native, expected) in [('\uf0b7', '•'), ('o', '◦'), ('', '•')]) {
      test(
        'uncached native bullet "$native" uses model fallback "$expected"',
        () {
          final source = _nativeNumbering(
            '<w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0">'
            '<w:numFmt w:val="bullet"/><w:lvlText w:val="$native"/>'
            '</w:lvl></w:abstractNum>'
            '<w:num w:numId="7"><w:abstractNumId w:val="7"/></w:num>',
          );
          final package = _export(
            WmlDocument(
              package: source,
              sections: [
                WmlSection(blocks: [_item('Bullet', id: 7, level: 3)]),
              ],
            ),
          );
          final content = _xml(package);
          final name = _elements(
            content,
            'list',
          ).single.getAttribute('style-name');
          final style = <XmlElement>[
            ..._elements(content, 'list-style'),
            ..._elements(_xml(package, 'styles.xml'), 'list-style'),
          ].singleWhere((element) => element.getAttribute('name') == name);
          expect(
            style
                .firstChild('list-level-style-bullet')!
                .getAttribute('bullet-char'),
            expected,
          );
          expect(_starts(content), [null]);
        },
      );
    }

    test('an explicit cached bullet is retained over native fallback', () {
      final source = _nativeNumbering(
        '<w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0">'
        '<w:numFmt w:val="bullet"/><w:lvlText w:val="\uf0b7"/>'
        '</w:lvl></w:abstractNum>'
        '<w:num w:numId="7"><w:abstractNumId w:val="7"/></w:num>',
      );
      final package = _export(
        WmlDocument(
          package: source,
          sections: [
            WmlSection(blocks: [_item('Bullet', id: 7, label: 'o')]),
          ],
        ),
      );
      expect(
        _elements(
          _xml(package),
          'list-level-style-bullet',
        ).first.getAttribute('bullet-char'),
        'o',
      );
    });

    test(
      'a missing native level keeps its level-zero-derived cached label',
      () {
        final source = _nativeNumbering(
          '<w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0">'
          '<w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/>'
          '</w:lvl></w:abstractNum>'
          '<w:num w:numId="7"><w:abstractNumId w:val="7"/></w:num>',
        );
        final package = _export(
          WmlDocument(
            package: source,
            sections: [
              WmlSection(
                blocks: [
                  _item('First', id: 7, level: 3, label: '4.'),
                  _item('Next', id: 7, level: 3, label: '4.'),
                ],
              ),
            ],
          ),
        );
        // The inherited %1 token refers to the parent level, not these items'
        // %4 counter. Inventing an independent 4,5 sequence would alter it.
        expect(_starts(_xml(package)), [null, null]);
        expect(
          _elements(
            _xml(package),
            'list-level-style-number',
          ).first.getAttribute('num-prefix'),
          '4.',
        );
      },
    );

    test(
      'decimal lists continue across paragraphs and honor pending restarts',
      () {
        final first = _item('First', label: '1. ');
        final second = _item('Second', label: '1. ');
        final restart = _item('Restart', label: '1. ')
          ..properties.listRestart = 7;
        final last = _item('Last', label: '1. ');
        final paragraphs = [first, second, restart, last];
        final before = paragraphs
            .map((p) => (p.properties.listLabel, p.properties.listRestart))
            .toList();
        final body = _body([
          first,
          WmlParagraph(inlines: [WmlRun(text: 'Interruption')]),
          second,
          restart,
          last,
        ]);
        expect(_starts(body), ['1', '2', '7', '8']);
        expect(
          paragraphs.map(
            (p) => (p.properties.listLabel, p.properties.listRestart),
          ),
          before,
        );
      },
    );

    test('cached first decimal label seeds only its authored level', () {
      final body = _body([
        _item('Parent', label: '3.'),
        _item('Child first', level: 4, label: '(8)'),
        _item('Child second', level: 4, label: '(8)'),
        _item('Next parent', label: '3.'),
        _item('Next child', level: 4, label: '(8)'),
      ]);
      expect(_starts(body), ['3', '8', '9', '4', '8']);
    });

    test('distinct list identities retain independent counters', () {
      expect(
        _starts(
          _body([
            _item('A', id: 7, label: '2.'),
            _item('B', id: 9, label: '6.'),
            _item('C', id: 7, label: '2.'),
            _item('D', id: 9, label: '6.'),
          ]),
        ),
        ['2', '6', '3', '7'],
      );
    });

    test('reusing a paragraph object still counts each visible occurrence', () {
      final item = _item('Repeated', label: '1.');
      expect(_starts(_body([item, item])), ['1', '2']);
      expect(item.properties.listLabel, '1.');
    });

    test('large decimal starts increment exactly on VM and JavaScript', () {
      expect(
        _starts(
          _body([
            _item('First', label: '9007199254740993.'),
            _item('Next', label: '9007199254740993.'),
          ]),
        ),
        ['9007199254740993', '9007199254740994'],
      );
    });

    test(
      'nonpositive restarts stay literal instead of invalid ODF attributes',
      () {
        final zero = _item('Zero', label: '1.')..properties.listRestart = 0;
        final negative = _item('Negative', label: '1.')
          ..properties.listRestart = -1;
        final package = _export(
          WmlDocument(
            sections: [
              WmlSection(
                blocks: [
                  zero,
                  _item('One', label: '1.'),
                  negative,
                  _item('Zero again', label: '1.'),
                  _item('One again', label: '1.'),
                ],
              ),
            ],
          ),
        );
        expect(_starts(_xml(package)), [null, '1', null, null, '1']);
        final markers = _elements(_xml(package), 'list-level-style-number')
            .where((style) => style.getAttribute('level') == '1')
            .map((style) => style.getAttribute('num-prefix'));
        expect(markers, containsAll(['0.', '-1.']));
      },
    );

    test(
      'native decimal starts and overrides survive without cached labels',
      () {
        final source = _nativeNumbering(
          '<w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0">'
          '<w:start w:val="3"/><w:numFmt w:val="decimal"/>'
          '<w:lvlText w:val="%1)"/></w:lvl></w:abstractNum>'
          '<w:num w:numId="7"><w:abstractNumId w:val="7"/>'
          '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="5"/>'
          '</w:lvlOverride></w:num>',
          customRelationship: true,
        );
        final before = source.save();
        final package = _export(
          WmlDocument(
            package: source,
            sections: [
              WmlSection(blocks: [_item('First', id: 7), _item('Next', id: 7)]),
            ],
          ),
        );
        expect(_starts(_xml(package)), ['5', '6']);
        final level = _elements(_xml(package), 'list-level-style-number').first;
        expect(level.getAttribute('num-format'), '1');
        expect(level.getAttribute('num-suffix'), ')');
        expect(source.save(), before);
      },
    );

    test(
      'native per-instance level and pending restart override base start',
      () {
        final source = _nativeNumbering(
          '<w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0">'
          '<w:start w:val="3"/><w:numFmt w:val="bullet"/>'
          '<w:lvlText w:val="•"/></w:lvl></w:abstractNum>'
          '<w:num w:numId="7"><w:abstractNumId w:val="7"/>'
          '<w:lvlOverride w:ilvl="0"><w:lvl w:ilvl="0">'
          '<w:start w:val="4"/><w:numFmt w:val="decimal"/>'
          '<w:lvlText w:val="Chapter %1."/></w:lvl>'
          '</w:lvlOverride></w:num>',
        );
        final package = _export(
          WmlDocument(
            package: source,
            sections: [
              WmlSection(
                blocks: [
                  _item('First', id: 7),
                  _item('Restart', id: 7)..properties.listRestart = 9,
                  _item('Next', id: 7),
                ],
              ),
            ],
          ),
        );
        expect(_starts(_xml(package)), ['4', '9', '10']);
        expect(
          _elements(
            _xml(package),
            'list-level-style-number',
          ).first.getAttribute('num-prefix'),
          'Chapter ',
        );
      },
    );

    test('ambiguous native definitions fall back to cached visible labels', () {
      final source = _nativeNumbering(
        '<w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0">'
        '<w:start w:val="99"/><w:numFmt w:val="decimal"/>'
        '<w:lvlText w:val="%1."/></w:lvl></w:abstractNum>'
        '<w:abstractNum w:abstractNumId="7"/>'
        '<w:num w:numId="7"><w:abstractNumId w:val="7"/></w:num>',
      );
      final package = _export(
        WmlDocument(
          package: source,
          sections: [
            WmlSection(blocks: [_item('Cached', id: 7, label: '8.')]),
          ],
        ),
      );
      expect(_starts(_xml(package)), ['8']);
    });

    test('complex cached markers remain literal and XML-safe', () {
      final labels = ['IV.', 'a)', '1.2.', '01.', 'Label & <x> "q"'];
      final package = _export(
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                for (var i = 0; i < labels.length; i++)
                  _item('Item $i', label: labels[i]),
              ],
            ),
          ],
        ),
      );
      final markers = _elements(
        _xml(package),
        'list-level-style-number',
      ).where((style) => style.getAttribute('level') == '1').toList();
      expect(markers.map((style) => style.getAttribute('num-prefix')), labels);
      expect(
        markers.every((style) => style.getAttribute('num-format') == ''),
        isTrue,
      );
      expect(_starts(_xml(package)), List<String?>.filled(labels.length, null));
    });

    test(
      'native unsupported format does not reinterpret its cached decimal',
      () {
        final source = _nativeNumbering(
          '<w:abstractNum w:abstractNumId="7"><w:lvl w:ilvl="0">'
          '<w:numFmt w:val="decimalZero"/><w:lvlText w:val="%1."/>'
          '</w:lvl></w:abstractNum>'
          '<w:num w:numId="7"><w:abstractNumId w:val="7"/></w:num>',
        );
        final package = _export(
          WmlDocument(
            package: source,
            sections: [
              WmlSection(blocks: [_item('Cached', id: 7, label: '08.')]),
            ],
          ),
        );
        final marker = _elements(
          _xml(package),
          'list-level-style-number',
        ).first;
        expect(marker.getAttribute('num-format'), '');
        expect(marker.getAttribute('num-prefix'), '08.');
        expect(_starts(_xml(package)), [null]);
      },
    );

    test(
      'authored bullet glyphs stay distinct instead of all becoming solid',
      () {
        final package = _export(
          WmlDocument(
            sections: [
              WmlSection(
                blocks: [
                  _item('Hollow', label: '◦'),
                  _item('Square', label: '▪'),
                  _item('Letter bullet', label: 'o'),
                ],
              ),
            ],
          ),
        );
        expect(
          _elements(_xml(package), 'list-level-style-bullet')
              .where((style) => style.getAttribute('level') == '1')
              .map((style) => style.getAttribute('bullet-char')),
          ['◦', '▪', 'o'],
        );
      },
    );
  });
}

void storyTests() {
  group('ODT list story counters', () {
    test('body numbering continues across sections', () {
      final package = _export(
        WmlDocument(
          sections: [
            WmlSection(blocks: [_item('First section', label: '1.')]),
            WmlSection(blocks: [_item('Second section', label: '1.')]),
          ],
        ),
      );
      expect(_starts(_xml(package)), ['1', '2']);
    });

    test('visible table cells continue body counters', () {
      final body = _body([
        _item('Body first', label: '1.'),
        WmlTable(
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [_item('Cell', label: '1.')]),
              ],
            ),
          ],
        ),
        _item('Body last', label: '1.'),
      ]);
      expect(_starts(body), ['1', '2', '3']);
    });

    test('covered cell lists cannot consume visible body numbers', () {
      final body = _body([
        _item('Body first', label: '1.'),
        WmlTable(
          rows: [
            WmlTableRow(cells: [WmlTableCell(vMerge: WmlVMerge.restart)]),
            WmlTableRow(
              cells: [
                WmlTableCell(
                  vMerge: WmlVMerge.cont,
                  blocks: [_item('Hidden', label: '99.')],
                ),
              ],
            ),
          ],
        ),
        _item('Body last', label: '1.'),
      ]);
      expect(_starts(body), ['1', '99', '2']);
      expect(
        _elements(body, 'covered-table-cell').single.firstChild('list'),
        isNotNull,
      );
    });

    test('orphan continuation cells remain in visible numbering order', () {
      final body = _body([
        _item('Body first', label: '1.'),
        WmlTable(
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(
                  vMerge: WmlVMerge.cont,
                  blocks: [_item('Orphan', label: '1.')],
                ),
              ],
            ),
          ],
        ),
        _item('Body last', label: '1.'),
      ]);
      expect(_starts(body), ['1', '2', '3']);
    });

    test('separate notes start fresh and never consume body ordinals', () {
      final first = _item('First', label: '1.');
      first.inlines.add(WmlRun(noteRefId: 4));
      final second = _item('Second', label: '1.');
      second.inlines.add(WmlRun(noteRefId: 5));
      final package = _export(
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                first,
                WmlParagraph(inlines: [WmlRun(text: 'Between')]),
                second,
                _item('Third', label: '1.'),
              ],
            ),
          ],
          footnotes: [
            WmlNote(
              id: 4,
              endnote: false,
              blocks: [
                _item('Note first', label: '1.'),
                _item('Note next', label: '1.'),
              ],
            ),
            WmlNote(
              id: 5,
              endnote: false,
              blocks: [_item('Other note', label: '1.')],
            ),
          ],
        ),
      );
      expect(_starts(_xml(package)), ['1', '1', '2', '2', '1', '3']);
    });

    test('separate comments do not share counters with body or each other', () {
      final first = _item('First', label: '1.');
      (first.inlines.single as WmlRun).commentIds.add(4);
      final second = _item('Second', label: '1.');
      (second.inlines.single as WmlRun).commentIds.add(5);
      final package = _export(
        WmlDocument(
          sections: [
            WmlSection(blocks: [first, second]),
          ],
          comments: [
            WmlComment(id: 4, paragraphs: [_item('Comment A', label: '1.')]),
            WmlComment(id: 5, paragraphs: [_item('Comment B', label: '1.')]),
          ],
        ),
      );
      expect(_starts(_xml(package)), ['1', '1', '2', '1']);
    });

    test('frame lists form independent stories and preserve nesting', () {
      final body = _body([
        _item('Body first', label: '1.'),
        WmlFrame(
          blocks: [
            _item('Frame first', label: '1.'),
            _item('Frame child', level: 4, label: '•'),
            _item('Frame next', label: '1.'),
          ],
        ),
        WmlFrame(blocks: [_item('Other frame', label: '1.')]),
        _item('Body last', label: '1.'),
      ]);
      expect(_starts(body), ['1', '1', null, '2', '1', '2']);
      expect(_itemDepths(_elements(body, 'text-box').first), [
        ('Frame first', 1),
        ('Frame child', 2),
        ('Frame next', 1),
      ]);
    });
  });
}
