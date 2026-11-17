import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

({XmlElement content, XmlElement styles}) _export(WmlDocument document) {
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  XmlElement part(String name) =>
      XmlDocument.parse(package.getPart('/$name.xml')!.readText()).root!;
  return (content: part('content'), styles: part('styles'));
}

Iterable<XmlElement> _elements(
  XmlElement root,
  String name, [
  String namespace = _textNs,
]) sync* {
  if (root.localName == name && root.namespaceUri == namespace) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name, namespace);
  }
}

XmlElement _body(XmlElement root) => root
    .firstChild('body', namespaceUri: _officeNs)!
    .firstChild('text', namespaceUri: _officeNs)!;

String _visible(XmlNode node) {
  if (node is XmlText) return node.text;
  if (node is! XmlElement) return '';
  if (node.namespaceUri == _officeNs && node.localName == 'annotation') {
    return '';
  }
  if (node.namespaceUri == _textNs) {
    if (node.localName == 'page-number') return '{PAGE}';
    if (node.localName == 's') {
      return ' ' *
          int.parse(node.getAttribute('c', namespaceUri: _textNs) ?? '1');
    }
    if (node.localName == 'tab') return '\t';
    if (node.localName == 'line-break') return '\n';
  }
  return node.children.map(_visible).join();
}

XmlElement _style(XmlElement root, XmlElement owner) {
  final name = owner.getAttribute('style-name', namespaceUri: _textNs);
  return root
      .firstChild('automatic-styles', namespaceUri: _officeNs)!
      .childrenNamed('style', namespaceUri: _styleNs)
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == name,
      );
}

WmlParagraph _page(String cache, {WmlRunProps? runProperties}) => WmlParagraph(
  properties: WmlParagraphProps(pageNumberField: true),
  inlines: [WmlRun(text: cache, properties: runProperties)],
);

WmlParagraph _plain(String text) => WmlParagraph(inlines: [WmlRun(text: text)]);

void main() {
  for (final footer in [false, true]) {
    for (final cache in ['', '27', '1  |  Al Tahreer Neighborhood Profile']) {
      test(
        'PAGE field retains styled ${footer ? 'footer' : 'header'}: $cache',
        () {
          final props = WmlRunProps(
            bold: true,
            color: '123456',
            fontSizeHalfPoints: 30,
          );
          final paragraph = _page(cache, runProperties: props);
          final originalRun = paragraph.inlines.single;
          final result = _export(
            WmlDocument(
              sections: [
                WmlSection(
                  header: footer ? [] : [paragraph],
                  footer: footer ? [paragraph] : [],
                  blocks: [_plain('Body')],
                ),
              ],
            ),
          );
          final story = _elements(
            result.styles,
            footer ? 'footer' : 'header',
            _styleNs,
          ).single;
          expect(_elements(story, 'page-number'), hasLength(1));
          expect(
            _visible(story),
            WordFields.pageResultWithSuffix(cache, '{PAGE}'),
          );
          final span = _elements(
            story,
            'span',
          ).firstWhere((span) => _elements(span, 'page-number').isNotEmpty);
          final properties = _style(
            result.styles,
            span,
          ).firstChild('text-properties', namespaceUri: _styleNs)!;
          expect(
            properties.getAttribute('font-weight', namespaceUri: _foNs),
            'bold',
          );
          expect(
            properties.getAttribute('color', namespaceUri: _foNs),
            '#123456',
          );
          expect(
            properties.getAttribute('font-size', namespaceUri: _foNs),
            '15.0pt',
          );
          expect(paragraph.text, cache);
          expect(identical(paragraph.inlines.single, originalRun), isTrue);
          expect(
            identical((paragraph.inlines.single as WmlRun).properties, props),
            isTrue,
          );
        },
      );
    }
  }

  test('an empty PAGE paragraph without runs still emits one live field', () {
    final paragraph = WmlParagraph(
      properties: WmlParagraphProps(pageNumberField: true),
    );
    final content = _export(
      WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      ),
    ).content;
    expect(_elements(content, 'page-number'), hasLength(1));
    expect(_visible(_body(content)), '{PAGE}');
    expect(paragraph.inlines, isEmpty);
  });

  test(
    'an empty bookmarked PAGE paragraph keeps the field inside its range',
    () {
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps(pageNumberField: true),
        inlines: [
          WmlBookmarkBoundary(id: '2', isStart: true, name: 'EmptyPage'),
          WmlBookmarkBoundary(id: '2', isStart: false, name: 'EmptyPage'),
        ],
      );
      final content = _export(
        WmlDocument(
          sections: [
            WmlSection(blocks: [paragraph]),
          ],
        ),
      ).content;
      expect(
        _body(
          content,
        ).childElements.single.childElements.map((e) => e.localName),
        ['bookmark-start', 'page-number', 'bookmark-end'],
      );
      expect(_visible(_body(content)), '{PAGE}');
      expect(paragraph.inlines.whereType<WmlRun>(), isEmpty);
    },
  );

  test('split cached number and title retain the suffix run formatting', () {
    final first = WmlRun(text: '1', properties: WmlRunProps(bold: true));
    final second = WmlRun(text: '2');
    final suffix = WmlRun(
      text: '  |  Report',
      properties: WmlRunProps(italic: true, color: 'ABCDEF'),
    );
    final paragraph = WmlParagraph(
      properties: WmlParagraphProps(pageNumberField: true),
      inlines: [first, second, suffix],
    );
    final content = _export(
      WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      ),
    ).content;
    expect(_elements(content, 'page-number'), hasLength(1));
    expect(_visible(_body(content)), '{PAGE}  |  Report');
    final suffixSpan = _elements(
      _body(content),
      'span',
    ).singleWhere((span) => _visible(span) == '  |  Report');
    final properties = _style(
      content,
      suffixSpan,
    ).firstChild('text-properties', namespaceUri: _styleNs)!;
    expect(
      properties.getAttribute('font-style', namespaceUri: _foNs),
      'italic',
    );
    expect(properties.getAttribute('color', namespaceUri: _foNs), '#abcdef');
    expect(paragraph.inlines, [first, second, suffix]);
    expect(paragraph.text, '12  |  Report');
  });

  test('PAGE field preserves bookmark and comment ownership', () {
    final run = WmlRun(text: '4', commentIds: [7]);
    final paragraph = WmlParagraph(
      properties: WmlParagraphProps(pageNumberField: true),
      inlines: [
        WmlBookmarkBoundary(id: '2', isStart: true, name: 'PageMark'),
        run,
        WmlBookmarkBoundary(id: '2', isStart: false, name: 'PageMark'),
      ],
    );
    final content = _export(
      WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
        comments: [WmlComment(id: 7, text: 'Page-number comment')],
      ),
    ).content;
    final owner = _body(content).childElements.single;
    expect(owner.childElements.map((element) => element.localName), [
      'bookmark-start',
      'span',
      'annotation',
      'bookmark-end',
    ]);
    expect(_elements(owner, 'page-number'), hasLength(1));
    expect(
      _elements(
        owner,
        'bookmark-start',
      ).single.getAttribute('name', namespaceUri: _textNs),
      'PageMark',
    );
    expect(
      _elements(owner, 'annotation', _officeNs).single.text,
      contains('Page-number comment'),
    );
    expect(run.text, '4');
    expect(run.commentIds, [7]);
  });

  test('an auxiliary PAGE anchor cannot consume a shared body comment', () {
    final header = _page('1');
    (header.inlines.single as WmlRun).commentIds = [7];
    final body = _plain('Body');
    (body.inlines.single as WmlRun).commentIds = [7];
    final result = _export(
      WmlDocument(
        sections: [
          WmlSection(header: [header], blocks: [body]),
        ],
        comments: [WmlComment(id: 7, text: 'Shared comment')],
      ),
    );
    expect(_elements(result.content, 'annotation', _officeNs), hasLength(1));
    expect(_elements(result.styles, 'annotation', _officeNs), isEmpty);
    expect(_elements(result.styles, 'page-number'), hasLength(1));
  });

  for (final endnote in [false, true]) {
    for (final cache in ['', '9']) {
      test(
        'PAGE consumes first ${endnote ? 'endnote' : 'footnote'} spacing: $cache',
        () {
          final note = WmlNote(
            id: 3,
            endnote: endnote,
            blocks: [_page(cache), _plain('Following note paragraph')],
          );
          final content = _export(
            WmlDocument(
              sections: [
                WmlSection(
                  blocks: [
                    WmlParagraph(
                      inlines: [
                        WmlRun(
                          text: '3',
                          noteRefId: 3,
                          noteRefEndnote: endnote,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
              footnotes: endnote ? [] : [note],
              endnotes: endnote ? [note] : [],
            ),
          ).content;
          final paragraphs = _elements(
            content,
            'note-body',
          ).single.childElements.toList();
          expect(paragraphs, hasLength(2));
          expect(_visible(paragraphs[0]), ' {PAGE}');
          expect(_visible(paragraphs[1]), 'Following note paragraph');
          expect(note.paragraphs.first.text, cache);
        },
      );
    }
  }

  test('PAGE note respects intentionally absent reference spacing', () {
    final content = _export(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlParagraph(inlines: [WmlRun(text: '1', noteRefId: 1)]),
            ],
          ),
        ],
        footnotes: [
          WmlNote(
            id: 1,
            endnote: false,
            addReferenceSpace: false,
            blocks: [_page('1'), _plain('Next')],
          ),
        ],
      ),
    ).content;
    final paragraphs = _elements(
      content,
      'note-body',
    ).single.childElements.toList();
    expect(paragraphs.map(_visible), ['{PAGE}', 'Next']);
  });

  for (final instruction in [' NUMPAGES ', ' DATE ', 'UNKNOWN custom']) {
    test(
      'explicit non-PAGE instruction retains cached result: $instruction',
      () {
        final paragraph = WmlParagraph(
          properties: WmlParagraphProps(
            pageNumberField: true,
            fieldInstruction: instruction,
          ),
          inlines: [WmlRun(text: 'Cached result')],
        );
        final content = _export(
          WmlDocument(
            sections: [
              WmlSection(blocks: [paragraph]),
            ],
          ),
        ).content;
        expect(_elements(content, 'page-number'), isEmpty);
        expect(_visible(_body(content)), 'Cached result');
        expect(paragraph.properties.pageNumberField, isTrue);
        expect(paragraph.properties.fieldInstruction, instruction);
      },
    );
  }

  for (final (instruction, cache) in [
    (r' PAGE \* ROMAN ', 'IV'),
    (r' PAGE \# "000" ', '007'),
    (r' PAGE \* MERGEFORMAT extra ', '12'),
    (' PAGE custom ', '12'),
  ]) {
    for (final compatibilityFlag in [false, true]) {
      test('unsupported PAGE instruction preserves cache with flag '
          '$compatibilityFlag: $instruction', () {
        final run = WmlRun(text: cache);
        final paragraph = WmlParagraph(
          properties: WmlParagraphProps(
            pageNumberField: compatibilityFlag,
            fieldInstruction: instruction,
          ),
          inlines: [run],
        );
        final content = _export(
          WmlDocument(
            sections: [
              WmlSection(blocks: [paragraph, _plain('Following text')]),
            ],
          ),
        ).content;
        expect(_elements(content, 'page-number'), isEmpty);
        expect(_visible(_body(content)), '${cache}Following text');
        expect(paragraph.inlines.single, same(run));
        expect(run.text, cache);
        expect(paragraph.properties.fieldInstruction, instruction);
        expect(paragraph.properties.pageNumberField, compatibilityFlag);
      });
    }
  }

  for (final footer in [false, true]) {
    test('unsupported PAGE switch retains styled linked '
        '${footer ? 'footer' : 'header'} cache', () {
      final first = WmlRun(text: 'I', properties: WmlRunProps(bold: true));
      final suffix = WmlRun(
        text: 'V  |  Report',
        properties: WmlRunProps(italic: true),
        hyperlink: WmlHyperlink(url: 'https://example.com/report'),
      );
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps(
          pageNumberField: true,
          fieldInstruction: r' PAGE \* ROMAN ',
        ),
        inlines: [first, suffix],
      );
      final result = _export(
        WmlDocument(
          sections: [
            WmlSection(
              header: footer ? [] : [paragraph],
              footer: footer ? [paragraph] : [],
              blocks: [_plain('Body')],
            ),
          ],
        ),
      );
      final story = _elements(
        result.styles,
        footer ? 'footer' : 'header',
        _styleNs,
      ).single;
      expect(_elements(story, 'page-number'), isEmpty);
      expect(_visible(story), 'IV  |  Report');
      expect(_visible(_elements(story, 'a').single), 'V  |  Report');
      final spans = _elements(story, 'span').toList();
      final firstProperties = _style(
        result.styles,
        spans.first,
      ).firstChild('text-properties', namespaceUri: _styleNs)!;
      final suffixProperties = _style(
        result.styles,
        spans.last,
      ).firstChild('text-properties', namespaceUri: _styleNs)!;
      expect(
        firstProperties.getAttribute('font-weight', namespaceUri: _foNs),
        'bold',
      );
      expect(
        suffixProperties.getAttribute('font-style', namespaceUri: _foNs),
        'italic',
      );
      expect(_visible(_body(result.content)), 'Body');
      expect(paragraph.inlines, [first, suffix]);
      expect(paragraph.text, 'IV  |  Report');
    });
  }

  for (final instruction in [' PAGE ', r' pAgE \* mErGeFoRmAt ', '\tPAGE\n']) {
    test('explicit PAGE instruction works without the compatibility flag: '
        '$instruction', () {
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps(fieldInstruction: instruction),
        inlines: [WmlRun(text: '12')],
      );
      final content = _export(
        WmlDocument(
          sections: [
            WmlSection(blocks: [paragraph]),
          ],
        ),
      ).content;
      expect(_elements(content, 'page-number'), hasLength(1));
      expect(_visible(_body(content)), '{PAGE}');
      expect(paragraph.properties.pageNumberField, isFalse);
    });
  }

  test('mixed native inline fields retain their cached content', () {
    final paragraph = WmlParagraph(
      properties: WmlParagraphProps(pageNumberField: true),
      inlines: [
        WmlRun(text: 'Prefix '),
        WmlRun(text: '9', fieldInstruction: ' PAGE ', fieldLocked: true),
      ],
    );
    final content = _export(
      WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      ),
    ).content;
    expect(_elements(content, 'page-number'), isEmpty);
    expect(_visible(_body(content)), 'Prefix 9');
    expect((paragraph.inlines.last as WmlRun).fieldLocked, isTrue);
  });

  test(
    'leading PAGE list item retains its section boundary and sibling style',
    () {
      final first = _page('1');
      first.properties
        ..numId = 1
        ..listLabel = '1.'
        ..rightToLeft = true
        ..shadingFill = 'ABCDEF';
      final next = _plain('Next item');
      next.properties
        ..numId = 1
        ..listLabel = '2.';
      final content = _export(
        WmlDocument(
          sections: [
            WmlSection(blocks: [_plain('First section')]),
            WmlSection(blocks: [first, next]),
          ],
        ),
      ).content;
      final list = _body(
        content,
      ).childrenNamed('list', namespaceUri: _textNs).single;
      final items = list
          .childrenNamed('list-item', namespaceUri: _textNs)
          .toList();
      expect(items, hasLength(2));
      final firstParagraph = items[0].firstChild('p', namespaceUri: _textNs)!;
      final secondParagraph = items[1].firstChild('p', namespaceUri: _textNs)!;
      expect(_visible(firstParagraph), '{PAGE}');
      expect(_visible(secondParagraph), 'Next item');
      final sectionStyle = _style(content, firstParagraph);
      expect(
        sectionStyle.getAttribute('master-page-name', namespaceUri: _styleNs),
        'mp1',
      );
      final properties = sectionStyle.firstChild(
        'paragraph-properties',
        namespaceUri: _styleNs,
      )!;
      expect(
        properties.getAttribute('break-before', namespaceUri: _foNs),
        'page',
      );
      expect(
        properties.getAttribute('writing-mode', namespaceUri: _styleNs),
        'rl-tb',
      );
      expect(
        properties.getAttribute('background-color', namespaceUri: _foNs),
        '#abcdef',
      );
      expect(
        _style(
          content,
          secondParagraph,
        ).getAttribute('master-page-name', namespaceUri: _styleNs),
        isNull,
      );
      expect(first.text, '1');
      expect(next.text, 'Next item');
    },
  );
}
