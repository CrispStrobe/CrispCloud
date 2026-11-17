import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _metaNs = 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0';
const _dcNs = 'http://purl.org/dc/elements/1.1/';
const _linkNs = 'http://www.w3.org/1999/xlink';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

WmlParagraph _anchor(String text, List<int> ids) => WmlParagraph(
  inlines: [WmlRun(text: text, commentIds: ids)],
);

WmlComment _comment(int id, String text) => WmlComment(id: id, text: text);

WmlDocument _document(List<WmlBlock> blocks, List<WmlComment> comments) =>
    WmlDocument(
      sections: [WmlSection(blocks: blocks)],
      comments: comments,
    );

OpcPackage _export(WmlDocument document, {String? fixture}) {
  final bytes = OdtDocumentWriter.writeBytes(document);
  if (const bool.fromEnvironment('dart.library.io')) {
    final output = Platform.environment['QUDS_ODF_FIXTURE_OUTPUT'];
    if (fixture != null && output != null && output.isNotEmpty) {
      Directory(output).createSync(recursive: true);
      File('$output/$fixture').writeAsBytesSync(bytes);
    }
  }
  return OpcPackage.openBytes(bytes);
}

XmlElement _xml(OpcPackage package, [String part = 'content.xml']) =>
    XmlDocument.parse(package.getPart('/$part')!.readText()).root!;

Iterable<XmlElement> _elements(XmlElement node, String name) sync* {
  if (node.localName == name) yield node;
  for (final child in node.childElements) {
    yield* _elements(child, name);
  }
}

Iterable<XmlElement> _annotations(XmlElement node) =>
    _elements(node, 'annotation').where((e) => e.namespaceUri == _officeNs);

String _text(XmlNode node) {
  if (node is XmlText) return node.text;
  if (node is! XmlElement) return '';
  if (node.namespaceUri == _textNs) {
    switch (node.localName) {
      case 's':
        return ' ' * int.parse(node.getAttribute('c') ?? '1');
      case 'tab':
        return '\t';
      case 'line-break':
        return '\n';
    }
  }
  return node.children.map(_text).join();
}

XmlElement _style(XmlElement root, XmlElement owner) {
  final name = owner.getAttribute('style-name', namespaceUri: _textNs);
  return root
      .firstChild('automatic-styles')!
      .childrenNamed('style')
      .singleWhere(
        (s) => s.getAttribute('name', namespaceUri: _styleNs) == name,
      );
}

WmlTable _coveredTable(List<int> hiddenIds) => WmlTable(
  grid: [120],
  rows: [
    WmlTableRow(
      cells: [
        WmlTableCell(vMerge: WmlVMerge.restart, blocks: [_anchor('Top', [])]),
      ],
    ),
    WmlTableRow(
      cells: [
        WmlTableCell(
          vMerge: WmlVMerge.cont,
          blocks: [_anchor('Hidden', hiddenIds)],
        ),
      ],
    ),
  ],
);

void main() {
  test('a hidden covered anchor does not consume a visible comment', () {
    final root = _xml(
      _export(
        _document(
          [
            _coveredTable([1]),
            _anchor('Visible', [1]),
          ],
          [_comment(1, 'Visible review')],
        ),
        fixture: 'word-comments-covered.odt',
      ),
    );
    expect(_annotations(_elements(root, 'covered-table-cell').single), isEmpty);
    final annotation = _annotations(root).single;
    expect(annotation.parent!.text, startsWith('Visible'));
    expect(annotation.text, contains('Visible review'));
  });

  test('comments anchored only in covered stories stay hidden', () {
    final root = _xml(
      _export(
        _document(
          [
            _coveredTable([1]),
          ],
          [_comment(1, 'Hidden review')],
        ),
      ),
    );
    expect(_annotations(root), isEmpty);
    expect(_elements(root, 'covered-table-cell').single.text, 'Hidden');
  });

  test('an orphan continuation remains a visible comment anchor', () {
    final root = _xml(
      _export(
        _document(
          [
            WmlTable(
              rows: [
                WmlTableRow(
                  cells: [
                    WmlTableCell(
                      vMerge: WmlVMerge.cont,
                      blocks: [
                        _anchor('Orphan', [1]),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
          [_comment(1, 'Orphan review')],
        ),
      ),
    );
    expect(_annotations(root).single.parent!.text, startsWith('Orphan'));
  });

  for (final duplicates in [2, 3]) {
    test(
      'rejects $duplicates ambiguous definitions without changing anchor',
      () {
        final document = _document([
          _anchor('Ambiguous anchor', [7]),
        ], List.generate(duplicates, (index) => _comment(7, 'Wrong $index')));
        final root = _xml(_export(document));
        expect(_annotations(root), isEmpty);
        expect(root.text, contains('Ambiguous anchor'));
        expect(document.comments, hasLength(duplicates));
      },
    );
  }

  test('missing definitions leave the visible run intact', () {
    final root = _xml(
      _export(
        _document([
          _anchor('Missing anchor', [99]),
        ], []),
      ),
    );
    expect(_annotations(root), isEmpty);
    expect(root.text, contains('Missing anchor'));
  });

  test('repeated IDs emit one body without mutating the source', () {
    final document = _document(
      [
        _anchor('First', [1, 1]),
        _anchor('Second', [1]),
      ],
      [_comment(1, 'One review')],
    );
    final first = _export(document);
    expect(_annotations(_xml(first)), hasLength(1));
    expect(
      document.paragraphs.first.inlines.whereType<WmlRun>().single.commentIds,
      [1, 1],
    );
    expect(document.comments.single.text, 'One review');
    expect(
      _export(document).getPart('/content.xml')!.readText(),
      first.getPart('/content.xml')!.readText(),
    );
  });

  test(
    'shared IDs are deduplicated while unique master-story comments remain',
    () {
      final document = WmlDocument(
        comments: [
          _comment(1, 'Shared review'),
          _comment(2, 'Header review'),
          _comment(3, 'Footer review'),
        ],
        sections: [
          WmlSection(
            blocks: [
              _anchor('Body', [1]),
            ],
            header: [
              _anchor('Header', [1, 2]),
            ],
            footer: [
              _anchor('Footer', [1, 2, 3]),
            ],
          ),
        ],
      );
      final package = _export(document, fixture: 'word-comments-stories.odt');
      final body = _xml(package);
      final styles = _xml(package, 'styles.xml');
      expect(_annotations(body), hasLength(1));
      expect(_annotations(styles), hasLength(2));
      expect(_annotations(styles).map((a) => a.text), [
        contains('Header review'),
        contains('Footer review'),
      ]);
    },
  );

  test('recursive comment references do not nest or consume later anchors', () {
    final document = _document(
      [
        _anchor('First', [1]),
        _anchor('Second', [2]),
      ],
      [
        WmlComment(
          id: 1,
          paragraphs: [
            _anchor('First review', [1, 2]),
          ],
        ),
        WmlComment(
          id: 2,
          paragraphs: [
            _anchor('Second review', [1, 2]),
          ],
        ),
      ],
    );
    final root = _xml(
      _export(document, fixture: 'word-comments-recursive.odt'),
    );
    final annotations = _annotations(root).toList();
    expect(annotations, hasLength(2));
    for (final annotation in annotations) {
      expect(_annotations(annotation).skip(1), isEmpty);
    }
    expect(annotations[0].parent!.text, startsWith('First'));
    expect(annotations[1].parent!.text, startsWith('Second'));
  });

  test('note references in comments retain marks without consuming bodies', () {
    final document = WmlDocument(
      comments: [
        WmlComment(
          id: 1,
          paragraphs: [
            WmlParagraph(
              inlines: [
                WmlRun(text: 'Review '),
                WmlRun(noteRefId: 8),
              ],
            ),
          ],
        ),
      ],
      footnotes: [
        WmlNote(
          id: 8,
          endnote: false,
          paragraphs: [
            _anchor('Footnote body', [2]),
          ],
        ),
      ],
      sections: [
        WmlSection(
          blocks: [
            _anchor('Anchor', [1]),
            WmlParagraph(inlines: [WmlRun(noteRefId: 8)]),
          ],
        ),
      ],
    );
    document.comments.add(_comment(2, 'Review of footnote'));
    final root = _xml(_export(document, fixture: 'word-comments-notes.odt'));
    final first = _annotations(root).first;
    expect(_elements(first, 'note'), isEmpty);
    expect(_text(first), contains('Review 1'));
    final note = _elements(root, 'note').single;
    expect(note.text, contains('Footnote body'));
    expect(_annotations(note).single.text, contains('Review of footnote'));
  });

  test('visible frame comments retain their bodies', () {
    final root = _xml(
      _export(
        _document(
          [
            WmlFrame(
              blocks: [
                _anchor('Frame anchor', [1]),
              ],
            ),
          ],
          [_comment(1, 'Frame review')],
        ),
      ),
    );
    expect(
      _annotations(_elements(root, 'text-box').single).single.text,
      contains('Frame review'),
    );
  });

  for (final auxiliary in ['note', 'frame']) {
    test(
      'main body anchor takes precedence over an earlier $auxiliary anchor',
      () {
        final document = _document(
          [
            if (auxiliary == 'frame')
              WmlFrame(
                blocks: [
                  _anchor('Frame anchor', [1]),
                ],
              )
            else
              WmlParagraph(inlines: [WmlRun(noteRefId: 8)]),
            _anchor('Main body anchor', [1]),
          ],
          [_comment(1, 'Main body review')],
        );
        document.footnotes.add(
          WmlNote(
            id: 8,
            endnote: false,
            paragraphs: [
              _anchor('Note anchor', [1]),
            ],
          ),
        );
        final root = _xml(
          _export(document, fixture: 'word-comments-$auxiliary-priority.odt'),
        );
        expect(
          _annotations(root).single.parent!.text,
          startsWith('Main body anchor'),
        );
      },
    );
  }

  test('empty comment bodies have a valid empty paragraph', () {
    final root = _xml(
      _export(
        _document(
          [
            _anchor('Anchor', [1]),
          ],
          [WmlComment(id: 1, paragraphs: [])],
        ),
        fixture: 'word-comments-empty.odt',
      ),
    );
    final annotation = _annotations(root).single;
    expect(annotation.childrenNamed('p'), hasLength(1));
    expect(annotation.childrenNamed('p').single.text, isEmpty);
  });

  test(
    'comment headings use legal paragraph children and retain heading style',
    () {
      final root = _xml(
        _export(
          _document(
            [
              _anchor('Anchor', [1]),
            ],
            [
              WmlComment(
                id: 1,
                paragraphs: [
                  WmlParagraph(
                    properties: WmlParagraphProps(headingLevel: 2),
                    inlines: [WmlRun(text: 'Review heading')],
                  ),
                ],
              ),
            ],
          ),
          fixture: 'word-comments-heading.odt',
        ),
      );
      final annotation = _annotations(root).single;
      expect(_elements(annotation, 'h'), isEmpty);
      final paragraph = annotation.childrenNamed('p').single;
      expect(
        paragraph.getAttribute('outline-level', namespaceUri: _textNs),
        isNull,
      );
      expect(
        _style(root, paragraph).getAttribute('parent-style-name'),
        'Heading_20_2',
      );
    },
  );

  for (final date in [
    '2026-11-17T15:30:42Z',
    '2024-02-29T15:30:42.125+01:00',
    '2026-11-17T15:30:42',
    ' 2026-11-17T15:30:42Z ',
    '2026-11-17T24:00:00Z',
    '12026-11-17T15:30:42-14:00',
    '-0004-02-29T00:00:00Z',
  ]) {
    test('retains valid annotation date $date', () {
      final comment = _comment(1, 'Review')..dateIso = date;
      final annotation = _annotations(
        _xml(
          _export(
            _document(
              [
                _anchor('Anchor', [1]),
              ],
              [comment],
            ),
          ),
        ),
      ).single;
      expect(annotation.firstChild('date')!.namespaceUri, _dcNs);
      expect(annotation.firstChild('date')!.text, date);
      expect(annotation.firstChild('date-string'), isNull);
    });
  }

  for (final date in [
    '2026-02-29T12:00:00Z',
    '2026-11-17',
    'Yesterday & tomorrow',
    '2026-11-17T24:00:01Z',
    '2026-11-17T00:00:00+14:01',
    '0000-01-01T00:00:00Z',
    '012026-11-17T00:00:00Z',
    '\u00a02026-11-17T00:00:00Z',
    '2026-11-17T00:00:00Z\u2028',
  ]) {
    final displayDate = date
        .replaceAll('\u00a0', '<NBSP>')
        .replaceAll('\u2028', '<LINE SEPARATOR>');
    test('retains non-date metadata as date-string: $displayDate', () {
      final comment = _comment(1, 'Review')..dateIso = date;
      final annotation = _annotations(
        _xml(
          _export(
            _document(
              [
                _anchor('Anchor', [1]),
              ],
              [comment],
            ),
            fixture: date == 'Yesterday & tomorrow'
                ? 'word-comments-date-string.odt'
                : null,
          ),
        ),
      ).single;
      expect(annotation.firstChild('date'), isNull);
      expect(annotation.firstChild('date-string')!.namespaceUri, _metaNs);
      expect(annotation.firstChild('date-string')!.text, date);
      expect(comment.dateIso, date);
    });
  }

  test('long malformed date metadata retains exact internal whitespace', () {
    final date = 'X${' ' * 65536}X';
    final comment = _comment(1, 'Review')..dateIso = date;
    final annotation = _annotations(
      _xml(
        _export(
          _document(
            [
              _anchor('Anchor', [1]),
            ],
            [comment],
          ),
        ),
      ),
    ).single;
    expect(annotation.firstChild('date'), isNull);
    expect(annotation.firstChild('date-string')!.text, date);
    expect(comment.dateIso, date);
  });

  test('rich comment text, links, fields, initials and pictures survive', () {
    WmlVisual picture(String title) => WmlVisual(
      visual: OfficeVisual(
        kind: OfficeVisualKind.picture,
        title: title,
        imageBytes: _png,
        width: 12,
        height: 12,
      ),
    );
    final comment = WmlComment(
      id: 1,
      author: 'Reviewer <A&B>',
      initials: 'A&B',
      dateIso: '2026-11-17T15:30:42Z',
      paragraphs: [
        WmlParagraph(
          inlines: [
            WmlRun(
              text: ' Leading  text ',
              properties: WmlRunProps(bold: true, color: '1234AB'),
            ),
            WmlBreak(WmlBreakType.textWrapping),
            WmlRun(
              text: 'Link\t',
              hyperlink: WmlHyperlink(url: 'https://example.test/?a=1&b=2'),
            ),
            WmlFieldBoundary(
              kind: WmlFieldBoundaryKind.instruction,
              text: 'HIDDEN INSTRUCTION',
            ),
            WmlRun(text: 'Cached result '),
            WmlRun(inlineVisual: picture('Inline picture')),
          ],
        ),
        WmlParagraph(
          properties: WmlParagraphProps(numId: 4),
          inlines: [WmlRun(text: 'List item')],
        ),
      ],
      visuals: [picture('Comment picture')],
    );
    final document = _document(
      [
        _anchor('Body anchor', [1]),
      ],
      [comment],
    );
    final package = _export(document, fixture: 'word-comments-rich.odt');
    final root = _xml(package);
    final annotation = _annotations(root).single;
    expect(annotation.firstChild('creator')!.text, 'Reviewer <A&B>');
    expect(annotation.firstChild('creator-initials'), isNotNull);
    expect(annotation.firstChild('creator-initials')!.text, 'A&B');
    expect(annotation.firstChild('creator-initials')!.namespaceUri, _metaNs);
    expect(
      _text(annotation),
      contains(' Leading  text \nLink\tCached result '),
    );
    expect(annotation.text, isNot(contains('HIDDEN INSTRUCTION')));
    expect(_elements(annotation, 'list'), hasLength(1));
    final spans = _elements(annotation, 'span').toList();
    final props = _style(root, spans.first).firstChild('text-properties')!;
    expect(props.getAttribute('font-weight', namespaceUri: _foNs), 'bold');
    expect(props.getAttribute('color', namespaceUri: _foNs), '#1234ab');
    final link = _elements(annotation, 'a').single;
    expect(link.childrenNamed('span'), isEmpty);
    expect(_style(root, link).getAttribute('family'), 'text');
    expect(
      link.getAttribute('href', namespaceUri: _linkNs),
      'https://example.test/?a=1&b=2',
    );
    expect(link.getAttribute('type', namespaceUri: _linkNs), 'simple');
    final images = _elements(annotation, 'image').toList();
    expect(images, hasLength(2));
    for (final image in images) {
      final path = image.getAttribute('href', namespaceUri: _linkNs)!;
      expect(package.getPart('/$path')!.readBytes(), _png);
      expect(image.getAttribute('type', namespaceUri: _linkNs), 'simple');
      expect(image.parent!.parent!.localName, 'p');
    }
    expect(
      OfficeTextExtractor.extract(
        OdtDocumentWriter.writeBytes(document),
        name: 'comments.odt',
      ).paragraphs,
      ['Body anchor'],
    );
    expect(comment.paragraphs, hasLength(2));
    expect(comment.visuals, hasLength(1));
  });

  test('detached visual fallbacks are legal comment paragraphs', () {
    final comment = WmlComment(
      id: 1,
      paragraphs: [],
      visuals: [
        WmlVisual(
          visual: OfficeVisual(
            kind: OfficeVisualKind.chartColumn,
            title: ' Chart\tlabel ',
          ),
        ),
      ],
    );
    final annotation = _annotations(
      _xml(
        _export(
          _document(
            [
              _anchor('Anchor', [1]),
            ],
            [comment],
          ),
        ),
      ),
    ).single;
    expect(annotation.childrenNamed('p'), hasLength(1));
    expect(_text(annotation.childrenNamed('p').single), ' Chart\tlabel ');
  });

  test('empty optional metadata is omitted', () {
    final comment = WmlComment(id: 1, author: '', initials: '', text: 'Review');
    final annotation = _annotations(
      _xml(
        _export(
          _document(
            [
              _anchor('Anchor', [1]),
            ],
            [comment],
          ),
        ),
      ),
    ).single;
    expect(annotation.firstChild('creator'), isNull);
    expect(annotation.firstChild('creator-initials'), isNull);
    expect(annotation.firstChild('date'), isNull);
    expect(annotation.firstChild('date-string'), isNull);
  });
}
