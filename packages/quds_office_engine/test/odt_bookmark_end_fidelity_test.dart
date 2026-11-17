import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

WmlBookmarkBoundary _start(String id, String name) =>
    WmlBookmarkBoundary(id: id, isStart: true, name: name);
WmlBookmarkBoundary _end(String id) =>
    WmlBookmarkBoundary(id: id, isStart: false);
WmlParagraph _range(String name) => WmlParagraph(
  inlines: [
    _start('7', name),
    WmlRun(text: name),
    _end('7'),
  ],
);

({XmlElement content, XmlElement styles}) _export(WmlDocument document) {
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  XmlElement part(String name) =>
      XmlDocument.parse(package.getPart('/$name.xml')!.readText()).root!;
  return (content: part('content'), styles: part('styles'));
}

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

List<String?> _ends(XmlElement root) => _elements(root, 'bookmark-end')
    .map((element) => element.getAttribute('name', namespaceUri: _textNs))
    .toList();

void main() {
  test('native id-only bookmark ends resolve their authored start names', () {
    final package = OpcPackage.create(OpcPackageKind.word);
    package
        .getPart('/word/document.xml')!
        .writeText(
          '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>'
          '<w:bookmarkStart w:id="007" w:name="Native"/>'
          '<w:r><w:t>Selected text</w:t></w:r><w:bookmarkEnd w:id="7"/>'
          '</w:p><w:sectPr/></w:body></w:document>',
        );
    final document = WordDeserializer().read(package);
    final markers = document.paragraphs.single.inlines
        .whereType<WmlBookmarkBoundary>()
        .toList();
    expect(markers.last.name, isNull);
    final result = _export(document);
    expect(_ends(result.content), ['Native']);
    expect(
      _elements(
        result.content,
        'bookmark-start',
      ).single.getAttribute('name', namespaceUri: _textNs),
      'Native',
    );
    expect(markers.last.name, isNull);
    expect(markers.first.id, '007');
    expect(markers.last.id, '7');
  });

  test(
    'body and table share a range while auxiliary stories reuse ids independently',
    () {
      final bodyEnd = _end('7');
      final document = WmlDocument(
        sections: [
          WmlSection(
            header: [_range('Header')],
            footer: [_range('Footer')],
            blocks: [
              WmlParagraph(
                inlines: [
                  _start('7', 'Body'),
                  WmlRun(text: 'Body start', commentIds: [4]),
                  WmlRun(text: '5', noteRefId: 5),
                ],
              ),
              WmlFrame(blocks: [_range('Frame')]),
              WmlTable(
                grid: [120],
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(
                        blocks: [
                          WmlParagraph(
                            inlines: [
                              WmlRun(text: 'Body table end'),
                              bodyEnd,
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
        footnotes: [
          WmlNote(id: 5, endnote: false, paragraphs: [_range('Note')]),
        ],
        comments: [
          WmlComment(id: 4, paragraphs: [_range('Comment')]),
        ],
      );
      final result = _export(document);
      expect(_ends(result.content), ['Comment', 'Note', 'Frame', 'Body']);
      expect(_ends(result.styles), ['Header', 'Footer']);
      expect(_ends(_elements(result.content, 'note-body').single), ['Note']);
      expect(_ends(_elements(result.content, 'text-box').single), ['Frame']);
      expect(bodyEnd.name, isNull);
    },
  );

  test('malformed or cross-story ranges cannot borrow an unrelated start', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          header: [
            WmlParagraph(
              inlines: [
                _end('1'),
                WmlRun(text: 'Header orphan'),
              ],
            ),
          ],
          footer: [
            WmlParagraph(
              inlines: [
                _end('2'),
                WmlRun(text: 'Footer orphan'),
              ],
            ),
          ],
          blocks: [
            WmlParagraph(
              inlines: [
                _start('1', 'Complete'),
                WmlRun(text: 'Retained complete'),
                _end('1'),
                _start('2', 'Body orphan'),
                WmlRun(text: 'Retained orphan'),
                _start('3', 'Ambiguous one'),
                _start('3', 'Ambiguous two'),
                WmlRun(text: 'Retained ambiguous'),
                _end('3'),
              ],
            ),
          ],
        ),
      ],
    );
    final result = _export(document);
    expect(_ends(result.content), ['Complete']);
    expect(_ends(result.styles), isEmpty);
    expect(
      result.content.text,
      contains('Retained completeRetained orphanRetained ambiguous'),
    );
    expect(result.styles.text, contains('Header orphan'));
    expect(result.styles.text, contains('Footer orphan'));
  });

  test('an omitted TOC title cannot create a visible orphan end', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            _range('Visible'),
            WmlToc(
              title: '',
              titleParagraph: WmlParagraph(
                inlines: [
                  _start('9', 'Unexported'),
                  WmlRun(text: 'TOC title'),
                ],
              ),
            ),
            WmlParagraph(
              inlines: [
                _end('9'),
                WmlRun(text: 'After TOC'),
              ],
            ),
          ],
        ),
      ],
    );
    final result = _export(document);
    expect(_ends(result.content), ['Visible']);
    expect(
      _elements(
        result.content,
        'bookmark-start',
      ).map((e) => e.getAttribute('name', namespaceUri: _textNs)),
      ['Visible'],
    );
    expect(result.content.text, isNot(contains('TOC title')));
    expect(result.content.text, contains('After TOC'));
  });
  test(
    'an exported TOC title keeps its bookmark range into following text',
    () {
      final content = _export(
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlToc(
                  title: 'Contents',
                  titleParagraph: WmlParagraph(
                    inlines: [
                      _start('9', 'ContentsRange'),
                      WmlRun(text: 'TOC title'),
                    ],
                  ),
                ),
                WmlParagraph(
                  inlines: [
                    _end('9'),
                    WmlRun(text: 'After contents'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ).content;
      expect(_ends(content), ['ContentsRange']);
      expect(
        _elements(
          content,
          'bookmark-start',
        ).map((e) => e.getAttribute('name', namespaceUri: _textNs)),
        ['ContentsRange'],
      );
      expect(content.text, contains('TOC title'));
      expect(content.text, contains('After contents'));
    },
  );

  test(
    'malformed bookmark IDs keep visible text without invented range ends',
    () {
      final content = _export(
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlParagraph(
                  inlines: [
                    _start('invalid', 'Invalid'),
                    WmlRun(text: 'Visible'),
                    _end('invalid'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ).content;
      expect(content.text, contains('Visible'));
      expect(_ends(content), isEmpty);
    },
  );
}
