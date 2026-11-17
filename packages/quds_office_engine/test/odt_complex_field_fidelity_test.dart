import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

WmlFieldBoundary _boundary(WmlFieldBoundaryKind kind, [String text = '']) =>
    WmlFieldBoundary(kind: kind, text: text);

List<WmlInline> _field(String instruction, List<WmlInline> result) => [
  _boundary(WmlFieldBoundaryKind.begin),
  _boundary(WmlFieldBoundaryKind.instruction, instruction),
  _boundary(WmlFieldBoundaryKind.separate),
  ...result,
  _boundary(WmlFieldBoundaryKind.end),
];

WmlDocument _document(List<WmlInline> inlines) => WmlDocument(
  sections: [
    WmlSection(blocks: [WmlParagraph(inlines: inlines)]),
  ],
);

({XmlElement content, XmlElement styles}) _export(
  String name,
  WmlDocument document,
) {
  final bytes = OdtDocumentWriter.writeBytes(document);
  final directory = Platform.environment['ODT_FIELD_FIXTURE_DIRECTORY'];
  if (directory != null) {
    File('$directory/$name.odt').writeAsBytesSync(bytes);
  }
  final package = OpcPackage.openBytes(bytes);
  return (
    content: XmlDocument.parse(
      package.getPart('/content.xml')!.readText(),
    ).root!,
    styles: XmlDocument.parse(package.getPart('/styles.xml')!.readText()).root!,
  );
}

Iterable<XmlElement> _elements(
  XmlElement root,
  String name, [
  String namespace = _textNs,
]) sync* {
  if (root.namespaceUri == namespace && root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name, namespace);
  }
}

String _visible(XmlNode node) {
  if (node is XmlText) return node.text;
  if (node is! XmlElement) return '';
  if (node.namespaceUri == _officeNs && node.localName == 'annotation') {
    return '';
  }
  if (node.namespaceUri == _textNs) {
    if (node.localName == 's') {
      return ' ' *
          int.parse(node.getAttribute('c', namespaceUri: _textNs) ?? '1');
    }
    if (node.localName == 'tab') return '\t';
    if (node.localName == 'line-break') return '\n';
  }
  return node.children.map(_visible).join();
}

XmlElement _body(XmlElement content) =>
    content.firstChild('body')!.firstChild('text')!;

Iterable<XmlElement> _nativeFields(XmlElement content) => [
  for (final name in ['page-number', 'page-count', 'date', 'time', 'title'])
    ..._elements(content, name),
];

void main() {
  test(
    'reused empty runs keep native field content local to its occurrence',
    () {
      for (final sectionLeading in [false, true]) {
        for (final aliased in [false, true]) {
          final empty = WmlRun();
          final cache = aliased ? empty : WmlRun();
          final paragraph = WmlParagraph(
            inlines: [
              empty,
              WmlBreak(WmlBreakType.column),
              ..._field(' PAGE ', [cache]),
            ],
          );
          final original = List<WmlInline>.of(paragraph.inlines);
          final result = _export(
            'aliased-empty-cache-$aliased-section-leading-$sectionLeading',
            WmlDocument(
              sections: [
                WmlSection(
                  columnCount: 2,
                  blocks: [
                    if (!sectionLeading)
                      WmlParagraph(inlines: [WmlRun(text: 'Prelude')]),
                    paragraph,
                  ],
                ),
              ],
            ),
          );
          final paragraphs = _elements(_body(result.content), 'p')
              .skip(sectionLeading ? 0 : 1)
              .toList();
          // A section boundary retains its empty leading source fragment;
          // a later paragraph does not acquire one because a run is aliased.
          expect(paragraphs, hasLength(sectionLeading ? 2 : 1));
          if (sectionLeading) {
            expect(_nativeFields(paragraphs.first), isEmpty);
          }
          final fieldParagraph = paragraphs.last;
          expect(_elements(fieldParagraph, 'page-number'), hasLength(1));
          final styleName = fieldParagraph.getAttribute(
            'style-name',
            namespaceUri: _textNs,
          );
          final style = _elements(result.content, 'style', _styleNs).singleWhere(
            (style) =>
                style.getAttribute('name', namespaceUri: _styleNs) == styleName,
          );
          expect(
            _elements(style, 'paragraph-properties', _styleNs)
                .single
                .getAttribute('break-before', namespaceUri: _foNs),
            'column',
          );
          expect(paragraph.inlines, orderedEquals(original));
          expect(identical(paragraph.inlines.first, empty), isTrue);
          expect(identical(paragraph.inlines[5], cache), isTrue);
          expect(identical(empty, cache), aliased);
        }
      }
    },
  );

  for (final instruction in ['PAGE', 'NUMPAGES']) {
    for (final (label, text) in [
      ('spaces', ' 7  8 '),
      ('tab', '7\t8'),
      ('line break', '7\n8'),
    ]) {
      test('$instruction cache retains significant $label through fallback', () {
        final run = WmlRun(
          text: text,
          properties: WmlRunProps(bold: true),
          hyperlink: const WmlHyperlink(url: 'https://example.com/pages'),
        );
        final result = _export(
          'whitespace-${instruction.toLowerCase()}-${label.replaceAll(' ', '-')}',
          _document([
            ..._field(' $instruction ', [run]),
            WmlRun(text: ' after'),
          ]),
        );
        expect(_nativeFields(result.content), isEmpty);
        expect(_visible(_body(result.content)), '$text after');
        final link = _elements(result.content, 'a').single;
        expect(_visible(link), text);
        expect(
          link.getAttribute(
            'href',
            namespaceUri: 'http://www.w3.org/1999/xlink',
          ),
          'https://example.com/pages',
        );
        expect(run.text, text);
        expect(run.properties.bold, isTrue);
      });
    }
  }

  for (final entry in {
    'PAGE': 'page-number',
    'NUMPAGES': 'page-count',
  }.entries) {
    test(
      'uncached ${entry.key} has no invented display before a column boundary',
      () {
        final document = _document([
          ..._field(' ${entry.key} ', []),
          WmlBreak(WmlBreakType.column),
        ]);
        final original = List<WmlInline>.of(document.paragraphs.single.inlines);
        final result = _export(
          'uncached-${entry.key.toLowerCase()}-column',
          document,
        );
        final paragraphs = _body(result.content).childElements.toList();
        expect(paragraphs, hasLength(1));
        expect(_elements(paragraphs.first, entry.value), isEmpty);
        expect(_nativeFields(paragraphs.last), isEmpty);
        final styleName = paragraphs.last.getAttribute(
          'style-name',
          namespaceUri: _textNs,
        );
        final style = _elements(result.content, 'style', _styleNs).singleWhere(
          (style) =>
              style.getAttribute('name', namespaceUri: _styleNs) == styleName,
        );
        final properties = _elements(
          style,
          'paragraph-properties',
          _styleNs,
        ).single;
        expect(
          properties.getAttribute('break-before', namespaceUri: _foNs),
          'column',
        );
        expect(document.paragraphs.single.inlines, orderedEquals(original));
        expect(document.paragraphs.single.inlines.whereType<WmlRun>(), isEmpty);
      },
    );
  }

  for (final entry in {
    'PAGE': 'page-number',
    'NUMPAGES': 'page-count',
  }.entries) {
    test(
      'empty native ${entry.key} cache keeps a following column break after the field',
      () {
        final result = _export(
          'empty-native-${entry.key.toLowerCase()}-before-column',
          _document([
            ..._field(' ${entry.key} ', [WmlRun(text: '')]),
            WmlBreak(WmlBreakType.column),
          ]),
        );
        final paragraphs = _body(result.content).childElements.toList();
        expect(paragraphs, hasLength(2));
        expect(_elements(paragraphs.first, entry.value), hasLength(1));
        expect(_nativeFields(paragraphs.last), isEmpty);
        final styleName = paragraphs.last.getAttribute(
          'style-name',
          namespaceUri: _textNs,
        );
        final style = _elements(result.content, 'style', _styleNs).singleWhere(
          (style) =>
              style.getAttribute('name', namespaceUri: _styleNs) == styleName,
        );
        final properties = _elements(
          style,
          'paragraph-properties',
          _styleNs,
        ).single;
        expect(
          properties.getAttribute('break-before', namespaceUri: _foNs),
          'column',
        );
      },
    );
  }

  test('plain NUMPAGES imported from actual DOCX remains a native field', () {
    final package = OpcPackage.create(OpcPackageKind.word);
    package
        .getPart('/word/document.xml')!
        .writeText(
          '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>'
          '<w:r><w:t xml:space="preserve">Before </w:t></w:r>'
          '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
          '<w:r><w:instrText xml:space="preserve"> NUMPAGES </w:instrText></w:r>'
          '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
          '<w:r><w:t>121</w:t></w:r>'
          '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
          '<w:r><w:t xml:space="preserve"> After</w:t></w:r>'
          '</w:p><w:sectPr/></w:body></w:document>',
        );
    final document = WordDeserializer().read(package);
    final cache = document.paragraphs.single.inlines
        .whereType<WmlRun>()
        .singleWhere((run) => run.text == '121');
    expect(cache.properties.sourcePropertiesXml, '');
    final result = _export('imported-numpages', document);
    expect(_elements(result.content, 'page-count'), hasLength(1));
    expect(_elements(result.content, 'page-count').single.text, '121');
    expect(_visible(_body(result.content)), 'Before 121 After');
    expect(cache.text, '121');
  });

  for (final entry in {
    'PAGE': ('page-number', '37'),
    'DATE': ('date', '17.11.2026'),
    'TIME': ('time', '12:34:56'),
    'TITLE': ('title', 'Authored title'),
  }.entries) {
    test(
      '${entry.key} preserves its display and styling without changing the model cache',
      () {
        final run = WmlRun(
          text: entry.value.$2,
          properties: WmlRunProps(bold: true, color: '123456'),
        );
        final document = _document([
          WmlRun(text: 'Before '),
          ..._field(' ${entry.key} ', [run]),
          WmlRun(text: ' After'),
        ]);
        final result = _export(entry.key.toLowerCase(), document);
        final fields = _elements(result.content, entry.value.$1);
        if (entry.key == 'PAGE') {
          expect(fields.single.text, entry.value.$2);
          expect(fields.single.childElements, isEmpty);
        } else {
          expect(_nativeFields(result.content), isEmpty);
        }
        expect(
          _visible(_body(result.content)),
          'Before ${entry.value.$2} After',
        );
        final span = _elements(
          result.content,
          'span',
        ).singleWhere((span) => span.text == entry.value.$2);
        final styleName = span.getAttribute(
          'style-name',
          namespaceUri: _textNs,
        );
        final style = _elements(result.content, 'style', _styleNs).singleWhere(
          (style) =>
              style.getAttribute('name', namespaceUri: _styleNs) == styleName,
        );
        final props = _elements(style, 'text-properties', _styleNs).single;
        expect(props.getAttribute('font-weight', namespaceUri: _foNs), 'bold');
        expect(props.getAttribute('color', namespaceUri: _foNs), '#123456');
        expect(run.text, entry.value.$2);
      },
    );
  }

  test('plain NUMPAGES emits one native field with one cached display', () {
    final result = _export(
      'numpages',
      _document([
        WmlRun(text: 'Before '),
        ..._field(' NUMPAGES ', [WmlRun(text: '121')]),
        WmlRun(text: ' After'),
      ]),
    );
    final field = _elements(result.content, 'page-count').single;
    expect(field.text, '121');
    expect(field.childElements, isEmpty);
    expect(
      _elements(
        result.content,
        'span',
      ).where((span) => span.childElements.contains(field)),
      hasLength(1),
    );
    expect(_visible(_body(result.content)), 'Before 121 After');
  });

  test('styled NUMPAGES keeps its single cache and native field style', () {
    final result = _export(
      'numpages-styled',
      _document(
        _field(' NUMPAGES ', [
          WmlRun(
            text: '121',
            properties: WmlRunProps(bold: true, color: '123456'),
          ),
        ]),
      ),
    );
    expect(_elements(result.content, 'page-count').single.text, '121');
    expect(_visible(_body(result.content)), '121');
    final span = _elements(result.content, 'span').single;
    final styleName = span.getAttribute('style-name', namespaceUri: _textNs);
    final style = _elements(result.content, 'style', _styleNs).singleWhere(
      (style) =>
          style.getAttribute('name', namespaceUri: _styleNs) == styleName,
    );
    final props = _elements(style, 'text-properties', _styleNs).single;
    expect(props.getAttribute('font-weight', namespaceUri: _foNs), 'bold');
    expect(props.getAttribute('color', namespaceUri: _foNs), '#123456');
  });

  test(
    'hyperlinked NUMPAGES preserves its source link around its native field',
    () {
      final run = WmlRun(
        text: '121',
        hyperlink: const WmlHyperlink(url: 'https://example.com/pages'),
      );
      final result = _export(
        'numpages-link',
        _document(_field(' NUMPAGES ', [run])),
      );
      expect(_elements(result.content, 'page-count').single.text, '121');
      expect(_visible(_body(result.content)), '121');
      expect(
        _elements(result.content, 'a').single.getAttribute(
          'href',
          namespaceUri: 'http://www.w3.org/1999/xlink',
        ),
        'https://example.com/pages',
      );
    },
  );

  test('split instruction fragments are joined before recognizing PAGE', () {
    final result = _export(
      'split-instruction',
      _document([
        _boundary(WmlFieldBoundaryKind.begin),
        _boundary(WmlFieldBoundaryKind.instruction, ' PA'),
        _boundary(WmlFieldBoundaryKind.instruction, 'GE '),
        _boundary(WmlFieldBoundaryKind.separate),
        WmlRun(text: '9'),
        _boundary(WmlFieldBoundaryKind.end),
        WmlRun(text: ' after'),
      ]),
    );
    expect(_elements(result.content, 'page-number').single.text, '9');
    expect(_visible(_body(result.content)), '9 after');
  });

  test('native cache keeps its source bookmark and comment ownership', () {
    final run = WmlRun(text: '9', commentIds: [7]);
    final document = _document([
      WmlBookmarkBoundary(id: '2', isStart: true, name: 'FieldMark'),
      ..._field(' PAGE ', [run]),
      WmlBookmarkBoundary(id: '2', isStart: false, name: 'FieldMark'),
      WmlRun(text: ' after'),
    ]);
    document.comments.add(
      WmlComment(
        id: 7,
        paragraphs: [
          WmlParagraph(inlines: [WmlRun(text: 'Field comment')]),
        ],
      ),
    );
    final result = _export('bookmark-comment', document);
    expect(_elements(result.content, 'page-number').single.text, '9');
    expect(_elements(result.content, 'annotation', _officeNs), hasLength(1));
    expect(_elements(result.content, 'bookmark-start'), hasLength(1));
    expect(_elements(result.content, 'bookmark-end'), hasLength(1));
    expect(_visible(_body(result.content)), '9 after');
    expect(run.commentIds, [7]);
  });

  for (final instruction in ['PAGE', 'IF condition']) {
    test(
      'nested $instruction retains all cached text without suppression leak',
      () {
        final result = _export(
          'nested-${instruction.split(' ').first}',
          _document([
            ..._field(instruction, [
              WmlRun(text: 'outer '),
              ..._field(' NUMPAGES ', [WmlRun(text: 'inner')]),
              WmlRun(text: ' tail'),
            ]),
            WmlRun(text: ' after'),
          ]),
        );
        expect(_nativeFields(result.content), isEmpty);
        expect(_visible(_body(result.content)), 'outer inner tail after');
      },
    );
  }

  test('unclosed field cannot suppress a later paragraph or header story', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              inlines: [
                _boundary(WmlFieldBoundaryKind.begin),
                _boundary(WmlFieldBoundaryKind.instruction, ' PAGE '),
                _boundary(WmlFieldBoundaryKind.separate),
                WmlRun(text: '11'),
              ],
            ),
            WmlParagraph(inlines: [WmlRun(text: 'AfterBody')]),
          ],
          header: [
            WmlParagraph(inlines: [WmlRun(text: 'HeaderText')]),
          ],
        ),
      ],
    );
    final result = _export('unclosed-story', document);
    expect(_nativeFields(result.content), isEmpty);
    expect(_visible(_body(result.content)), '11AfterBody');
    expect(
      _elements(result.styles, 'header', _styleNs).single.text,
      'HeaderText',
    );
  });

  test('stray instruction cannot suppress ordinary text', () {
    final result = _export(
      'stray-instruction',
      _document([
        _boundary(WmlFieldBoundaryKind.instruction, ' PAGE '),
        WmlRun(text: 'Ordinary text'),
      ]),
    );
    expect(_nativeFields(result.content), isEmpty);
    expect(_visible(_body(result.content)), 'Ordinary text');
  });

  test(
    'authored cache whitespace falls back without unsupported field children',
    () {
      const cache = '  Title\t detail\n ';
      final result = _export(
        'cache-whitespace',
        _document([
          ..._field(' TITLE ', [WmlRun(text: cache)]),
          WmlRun(text: 'after'),
        ]),
      );
      expect(_nativeFields(result.content), isEmpty);
      expect(_visible(_body(result.content)), '${cache}after');
    },
  );

  test('heterogeneous cached runs retain their text and separate styles', () {
    final result = _export(
      'heterogeneous-cache',
      _document(
        _field(' TITLE ', [
          WmlRun(text: 'First', properties: WmlRunProps(bold: true)),
          WmlRun(text: 'Second', properties: WmlRunProps(italic: true)),
        ]),
      ),
    );
    expect(_nativeFields(result.content), isEmpty);
    expect(_visible(_body(result.content)), 'FirstSecond');
    expect(_elements(result.content, 'span'), hasLength(2));
  });

  test('inline column boundary inside a cached field remains source owned', () {
    final result = _export(
      'column-cache',
      _document(
        _field(' PAGE ', [
          WmlRun(text: '9'),
          WmlBreak(WmlBreakType.column),
          WmlRun(text: 'after-column'),
        ]),
      ),
    );
    expect(_nativeFields(result.content), isEmpty);
    expect(_visible(_body(result.content)), '9after-column');
  });

  test(
    'note reference in a cached field retains its separately owned story',
    () {
      final document = _document(
        _field(' PAGE ', [WmlRun(text: '9'), WmlRun(text: '1', noteRefId: 1)]),
      );
      document.footnotes.add(
        WmlNote(
          id: 1,
          endnote: false,
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'NoteBody')]),
          ],
        ),
      );
      final result = _export('note-cache', document);
      expect(_nativeFields(result.content), isEmpty);
      expect(_elements(result.content, 'note'), hasLength(1));
      expect(
        _elements(result.content, 'note-body').single.text,
        contains('NoteBody'),
      );
      expect(_visible(_body(result.content)), startsWith('91'));
    },
  );

  test('locked source field retains its cached result', () {
    final result = _export(
      'locked-cache',
      _document([
        WmlFieldBoundary(
          kind: WmlFieldBoundaryKind.begin,
          sourceXml: '<w:fldChar w:fldCharType="begin" w:fldLock="true"/>',
        ),
        _boundary(WmlFieldBoundaryKind.instruction, ' PAGE '),
        _boundary(WmlFieldBoundaryKind.separate),
        WmlRun(text: 'Locked 9'),
        _boundary(WmlFieldBoundaryKind.end),
      ]),
    );
    expect(_nativeFields(result.content), isEmpty);
    expect(_visible(_body(result.content)), 'Locked 9');
  });

  test(
    'unknown field retains exact cached text and following ordinary content',
    () {
      final result = _export(
        'unknown-cache',
        _document([
          ..._field(' CITATION source ', [
            WmlRun(text: '  Authored citation  '),
          ]),
          WmlRun(text: 'after'),
        ]),
      );
      expect(_nativeFields(result.content), isEmpty);
      expect(_visible(_body(result.content)), '  Authored citation  after');
    },
  );
}
