import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';

WmlRun _ref(int id, {bool endnote = false, String? text}) =>
    WmlRun(text: text ?? '$id', noteRefId: id, noteRefEndnote: endnote);

WmlNote _note(int id, {bool endnote = false, List<WmlBlock>? blocks}) =>
    WmlNote(
      id: id,
      endnote: endnote,
      blocks:
          blocks ??
          [
            WmlParagraph(inlines: [WmlRun(text: 'Note $id')]),
          ],
    );

WmlDocument _document(
  List<WmlRun> refs, {
  List<WmlNote>? footnotes,
  List<WmlNote>? endnotes,
}) => WmlDocument(
  sections: [
    WmlSection(blocks: [WmlParagraph(inlines: refs)]),
  ],
  footnotes: footnotes,
  endnotes: endnotes,
);

OpcPackage _package(WmlDocument document) =>
    OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));

XmlElement _xml(OpcPackage package, [String part = 'content.xml']) =>
    XmlDocument.parse(package.getPart('/$part')!.readText()).root!;

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.namespaceUri == _textNs && root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

List<String> _labels(XmlElement root) =>
    _elements(root, 'note-citation').map((e) => e.text).toList();

String? _attr(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: _textNs);

String _visibleText(XmlNode node) {
  if (node is XmlText) return node.text;
  if (node is! XmlElement) return '';
  if (node.namespaceUri == _textNs) {
    if (node.localName == 's') return ' ' * int.parse(_attr(node, 'c') ?? '1');
    if (node.localName == 'tab') return '\t';
    if (node.localName == 'line-break') return '\n';
  }
  return node.children.map(_visibleText).join();
}

void main() {
  test('uses independent native footnote and endnote numbering', () {
    final document = _document(
      [_ref(42), _ref(42, endnote: true), _ref(8)],
      footnotes: [_note(8), _note(42)],
      endnotes: [_note(42, endnote: true)],
    );
    final root = _xml(_package(document));
    expect(_labels(root), ['1', 'i', '2']);
    final notes = _elements(root, 'note').toList();
    expect(notes.map((n) => _attr(n, 'note-class')), [
      'footnote',
      'endnote',
      'footnote',
    ]);
    expect(notes.map((n) => _attr(n, 'id')).toSet(), hasLength(3));
    expect(document.paragraphs.single.text, '42428');
  });

  test('numbers empty authored reference markers in their body sequence', () {
    final document = _document(
      [_ref(9, text: ''), _ref(7, endnote: true, text: ''), _ref(2)],
      footnotes: [_note(9), _note(2)],
      endnotes: [_note(7, endnote: true)],
    );
    expect(_labels(_xml(_package(document))), ['1', 'i', '2']);
    expect(
      document.paragraphs.single.inlines.whereType<WmlRun>().first.text,
      '',
    );
    // Existing callers retain the original empty-text interpretation.
    expect(WordNoteNumbering(document).labelFor(document.footnotes.first), '');
  });

  test(
    'freezes resolved labels so consumers cannot silently renumber them',
    () {
      final document = _document([_ref(3)], footnotes: [_note(3)]);
      document.sections.single.sourceProperties = WmlSectionSource(
        xml:
            '<w:sectPr xmlns:w="${OfficeNamespaces.w}">'
            '<w:footnotePr><w:numStart w:val="108"/></w:footnotePr></w:sectPr>',
        values: const {},
      );
      final citation = _elements(
        _xml(_package(document)),
        'note-citation',
      ).single;
      expect(citation.text, '108');
      expect(_attr(citation, 'label'), '108');
      expect(document.sections.single.sourceProperties!.xml, contains('108'));
    },
  );

  test(
    'preserves authored citation labels and excludes them from numbering',
    () {
      final document = _document(
        [_ref(5, text: '†'), _ref(8)],
        footnotes: [_note(5), _note(8)],
      );
      final citations = _elements(
        _xml(_package(document)),
        'note-citation',
      ).toList();
      expect(citations.map((e) => e.text), ['†', '1']);
      expect(citations.map((e) => _attr(e, 'label')), ['†', '1']);
    },
  );

  test('emits one body and a resolvable field for repeated references', () {
    final root = _xml(
      _package(
        _document([_ref(17), _ref(17), _ref(17)], footnotes: [_note(17)]),
      ),
    );
    final note = _elements(root, 'note').single;
    final refs = _elements(root, 'note-ref').toList();
    expect(refs, hasLength(2));
    expect(
      refs.map((r) => _attr(r, 'ref-name')),
      everyElement(_attr(note, 'id')),
    );
    expect(refs.map((r) => _attr(r, 'reference-format')), everyElement('text'));
    expect(refs.map((r) => r.text), everyElement('1'));
  });

  test('missing note definitions retain visible reference text', () {
    final root = _xml(_package(_document([_ref(99, text: 'MISSING †')])));
    expect(_elements(root, 'note'), isEmpty);
    expect(root.text, contains('MISSING †'));
  });

  test(
    'a differently authored repeat mark retains its visible cached text',
    () {
      final root = _xml(
        _package(
          _document(
            [_ref(1, text: '†'), _ref(1, text: '‡')],
            footnotes: [_note(1)],
          ),
        ),
      );
      expect(_elements(root, 'note'), hasLength(1));
      expect(_elements(root, 'note-ref'), isEmpty);
      expect(root.text, contains('‡'));
    },
  );

  test('ambiguous duplicate definitions retain visible reference text', () {
    final root = _xml(
      _package(
        _document(
          [_ref(1, text: 'AMBIGUOUS')],
          footnotes: [_note(1), _note(1)],
        ),
      ),
    );
    expect(_elements(root, 'note'), isEmpty);
    expect(root.text, contains('AMBIGUOUS'));
  });

  test('self references cannot recursively expand note bodies', () {
    final note = _note(
      4,
      blocks: [
        WmlParagraph(
          inlines: [
            WmlRun(text: 'Self '),
            _ref(4),
          ],
        ),
      ],
    );
    final root = _xml(_package(_document([_ref(4)], footnotes: [note])));
    final body = _elements(root, 'note-body').single;
    expect(_elements(root, 'note'), hasLength(1));
    expect(_elements(body, 'note'), isEmpty);
    expect(_visibleText(body), ' Self 1');
  });

  test('mutually referenced notes stay flat and terminate', () {
    final first = _note(
      4,
      blocks: [
        WmlParagraph(
          inlines: [
            WmlRun(text: 'A '),
            _ref(9),
          ],
        ),
      ],
    );
    final second = _note(
      9,
      blocks: [
        WmlParagraph(
          inlines: [
            WmlRun(text: 'B '),
            _ref(4),
          ],
        ),
      ],
    );
    final root = _xml(
      _package(_document([_ref(4), _ref(9)], footnotes: [first, second])),
    );
    expect(_elements(root, 'note'), hasLength(2));
    for (final body in _elements(root, 'note-body')) {
      expect(_elements(body, 'note'), isEmpty);
    }
    expect(_visibleText(root), contains('A 2'));
    expect(_visibleText(root), contains('B 1'));
  });

  test('comment references cannot consume the visible body note', () {
    final document = _document(
      [
        WmlRun(text: 'Before', commentIds: [1]),
        _ref(7),
        WmlRun(text: 'After', commentIds: [2]),
      ],
      footnotes: [_note(7)],
    );
    document.comments.addAll([
      for (final id in [1, 2])
        WmlComment(
          id: id,
          paragraphs: [
            WmlParagraph(inlines: [_ref(7)]),
          ],
        ),
    ]);
    final root = _xml(_package(document));
    final annotations = root
        .firstChild('body')!
        .firstChild('text')!
        .firstChild('p')!
        .childrenNamed(
          'annotation',
          namespaceUri: 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
        )
        .toList();
    expect(annotations, hasLength(2));
    for (final annotation in annotations) {
      expect(_elements(annotation, 'note'), isEmpty);
      expect(_elements(annotation, 'note-ref'), isEmpty);
      expect(_visibleText(annotation.firstChild('p')!), '1');
    }
    expect(_elements(root, 'note'), hasLength(1));
    expect(_elements(root, 'note-ref'), isEmpty);
    expect(_elements(root, 'note-body').single.text, contains('Note 7'));
  });

  test(
    'header and footer references preserve text without duplicate note bodies',
    () {
      final document = _document([_ref(7)], footnotes: [_note(7)]);
      document.sections.single.header.add(WmlParagraph(inlines: [_ref(7)]));
      document.sections.single.footer.add(
        WmlParagraph(inlines: [_ref(7, text: '†')]),
      );
      final package = _package(document);
      final styles = _xml(package, 'styles.xml');
      expect(_elements(styles, 'note'), isEmpty);
      expect(_elements(styles, 'note-ref'), isEmpty);
      expect(_elements(_xml(package), 'note'), hasLength(1));
      expect(styles.firstChild('master-styles')!.text, contains('1†'));
    },
  );

  test('empty note bodies get a consumer-compatible blank paragraph', () {
    final root = _xml(
      _package(_document([_ref(1)], footnotes: [_note(1, blocks: [])])),
    );
    expect(_elements(_elements(root, 'note-body').single, 'p'), hasLength(1));
  });

  test(
    'rich note paragraphs retain spacing, breaks, colors and hyperlinks',
    () {
      final note = _note(
        1,
        blocks: [
          WmlParagraph(
            properties: WmlParagraphProps(
              lineSpacing: 18,
              lineSpacingRule: WmlLineSpacingRule.exact,
            ),
            inlines: [
              WmlRun(
                text: 'Styled',
                properties: WmlRunProps(bold: true, color: 'CC0000'),
              ),
              WmlBreak(WmlBreakType.textWrapping),
              WmlRun(
                text: ' cached result',
                hyperlink: WmlHyperlink(url: 'https://example.test/note'),
              ),
            ],
          ),
        ],
      );
      final package = _package(_document([_ref(1)], footnotes: [note]));
      final root = _xml(package);
      final body = _elements(root, 'note-body').single;
      expect(_elements(body, 'line-break'), hasLength(1));
      expect(body.text, contains('Styled'));
      expect(body.text, contains('cached result'));
      expect(
        _elements(body, 'a').single.getAttribute(
          'type',
          namespaceUri: 'http://www.w3.org/1999/xlink',
        ),
        'simple',
      );
      expect(
        package.getPart('/content.xml')!.readText(),
        contains('fo:line-height="18.00pt"'),
      );
      expect(
        package.getPart('/content.xml')!.readText(),
        contains('fo:color="#cc0000"'),
      );
    },
  );

  test(
    'reference run styling surrounds the note and repeated reference field',
    () {
      final first = _ref(3)
        ..properties = WmlRunProps(
          vertAlign: WmlVertAlign.superscript,
          color: '008000',
        );
      final second = _ref(3)..properties = first.properties.copy();
      final root = _xml(
        _package(_document([first, second], footnotes: [_note(3)])),
      );
      final wrappers = _elements(root, 'span')
          .where(
            (span) => span.childElements.any(
              (e) => e.localName == 'note' || e.localName == 'note-ref',
            ),
          )
          .toList();
      expect(wrappers, hasLength(2));
      final names = wrappers.map((e) => _attr(e, 'style-name')).toSet();
      expect(names, hasLength(1));
      final style = root
          .firstChild('automatic-styles')!
          .childrenNamed('style', namespaceUri: _styleNs)
          .singleWhere(
            (e) =>
                e.getAttribute('name', namespaceUri: _styleNs) == names.single,
          );
      expect(
        style
            .firstChild('text-properties')!
            .getAttribute('text-position', namespaceUri: _styleNs),
        'super 58%',
      );
    },
  );

  test(
    'custom-mark references remain unnumbered while their bodies survive',
    () {
      final custom = _ref(1)..noteRefCustomMark = true;
      final document = _document(
        [custom, _ref(2)],
        footnotes: [_note(1), _note(2)],
      );
      final citations = _elements(
        _xml(_package(document)),
        'note-citation',
      ).toList();
      expect(citations.map((e) => e.text), ['', '1']);
      expect(citations.map((e) => _attr(e, 'label')), ['\u2060', '1']);
      expect(_xml(_package(document)).text, isNot(contains('\u2060')));
    },
  );

  test('covered cell references cannot consume the only visible note body', () {
    final document = _document([_ref(3)], footnotes: [_note(3)]);
    document.sections.single.blocks.insert(
      0,
      WmlTable(
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(
                vMerge: WmlVMerge.restart,
                blocks: [
                  WmlParagraph(inlines: [WmlRun(text: 'Anchor')]),
                ],
              ),
            ],
          ),
          WmlTableRow(
            cells: [
              WmlTableCell(
                vMerge: WmlVMerge.cont,
                blocks: [
                  WmlParagraph(inlines: [_ref(3)]),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    final root = _xml(_package(document));
    final table = root
        .firstChild('body')!
        .firstChild('text')!
        .firstChild('table')!;
    expect(_elements(table, 'note'), isEmpty);
    expect(_elements(root, 'note'), hasLength(1));
    expect(_elements(root, 'note-ref'), isEmpty);
  });

  for (final endnote in [false, true]) {
    final kind = endnote ? 'endnote' : 'footnote';
    test('$kind references in comments cannot consume visible note bodies', () {
      final note = _note(7, endnote: endnote);
      final document = _document(
        [_ref(7, endnote: endnote), _ref(7, endnote: endnote)],
        footnotes: endnote ? null : [note],
        endnotes: endnote ? [note] : null,
      );
      document.comments.add(
        WmlComment(
          id: 1,
          author: 'Reviewer',
          paragraphs: [
            WmlParagraph(
              inlines: [
                WmlRun(text: 'Comment '),
                _ref(7, endnote: endnote),
              ],
            ),
          ],
        ),
      );
      document.sections.single.blocks.insert(
        0,
        WmlParagraph(
          inlines: [
            WmlRun(text: 'Annotated', commentIds: [1]),
          ],
        ),
      );

      final package = _package(document);
      final root = _xml(package);
      final paragraphs = root
          .firstChild('body')!
          .firstChild('text')!
          .childrenNamed('p', namespaceUri: _textNs);
      final annotation = paragraphs.first.firstChild(
        'annotation',
        namespaceUri: _officeNs,
      )!;
      final label = endnote ? 'i' : '1';
      expect(_elements(annotation, 'note'), isEmpty);
      expect(_elements(annotation, 'note-ref'), isEmpty);
      expect(_elements(annotation, 'note-body'), isEmpty);
      expect(
        _visibleText(annotation.firstChild('p', namespaceUri: _textNs)!),
        'Comment $label',
      );

      final visibleNote = _elements(paragraphs.last, 'note').single;
      final repeated = _elements(paragraphs.last, 'note-ref').single;
      expect(_attr(visibleNote, 'note-class'), kind);
      expect(
        _elements(visibleNote, 'note-body').single.text,
        contains('Note 7'),
      );
      expect(_labels(root), [label]);
      expect(_elements(root, 'note'), hasLength(1));
      expect(_elements(root, 'note-ref'), hasLength(1));
      expect(_attr(repeated, 'ref-name'), _attr(visibleNote, 'id'));
      expect(repeated.text, label);
      expect(package.getPart('/content.xml')!.readText(), contains('Comment'));
      expect(document.comments.single.text, 'Comment 7');
      expect(note.id, 7);
      expect(note.text, 'Note 7');
    });
  }

  test(
    'repeated exports preserve source IDs, reference strings and native settings',
    () {
      final document = _document([_ref(42), _ref(42)], footnotes: [_note(42)]);
      final before = document.paragraphs.map((p) => p.text).toList();
      final first = _package(document), second = _package(document);
      for (final part in [
        'content.xml',
        'styles.xml',
        'META-INF/manifest.xml',
      ]) {
        expect(
          second.getPart('/$part')!.readText(),
          first.getPart('/$part')!.readText(),
        );
      }
      expect(document.paragraphs.map((p) => p.text), before);
      expect(document.footnotes.single.id, 42);
      expect(document.footnotes.single.text, 'Note 42');
    },
  );

  for (final orphan in [false, true]) {
    test(
      'visible note numbering respects ${orphan ? 'orphan' : 'covered'} continuation cells',
      () {
        final document = _document([_ref(8)], footnotes: [_note(4), _note(8)]);
        document.sections.single.blocks.insert(
          0,
          WmlTable(
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    vMerge: orphan ? WmlVMerge.none : WmlVMerge.restart,
                    blocks: [
                      WmlParagraph(inlines: [WmlRun(text: 'Anchor')]),
                    ],
                  ),
                ],
              ),
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    vMerge: WmlVMerge.cont,
                    blocks: [
                      WmlParagraph(inlines: [_ref(4)]),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
        final root = _xml(_package(document));
        expect(_labels(root), orphan ? ['1', '2'] : ['1']);
        // The export-specific visibility hook does not change native callers.
        expect(
          WordNoteNumbering(document).labelFor(document.footnotes.last),
          '2',
        );
      },
    );
  }

  test(
    'note tables preserve visible nested cell paragraphs without hidden stories',
    () {
      final note = _note(
        1,
        blocks: [
          WmlTable(
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    vMerge: WmlVMerge.restart,
                    blocks: [
                      WmlParagraph(inlines: [WmlRun(text: 'A')]),
                    ],
                  ),
                  WmlTableCell(
                    blocks: [
                      WmlParagraph(inlines: [WmlRun(text: 'B')]),
                    ],
                  ),
                ],
              ),
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    vMerge: WmlVMerge.cont,
                    blocks: [
                      WmlParagraph(inlines: [WmlRun(text: 'HIDDEN')]),
                    ],
                  ),
                  WmlTableCell(
                    blocks: [
                      WmlTable(
                        rows: [
                          WmlTableRow(
                            cells: [
                              WmlTableCell(
                                blocks: [
                                  WmlParagraph(inlines: [WmlRun(text: 'C')]),
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
          ),
        ],
      );
      final package = _package(_document([_ref(1)], footnotes: [note]));
      final body = _elements(_xml(package), 'note-body').single;
      expect(_elements(body, 'p').map(_visibleText), [' A', 'B', 'C']);
      expect(
        package.getPart('/content.xml')!.readText(),
        isNot(contains('<table:table')),
      );
      expect(body.text, isNot(contains('HIDDEN')));
      expect(note.blocks.single, isA<WmlTable>());
    },
  );

  for (final addSpace in [false, true]) {
    test('honors authored automatic note reference spacing $addSpace', () {
      final note = WmlNote(
        id: 1,
        endnote: false,
        addReferenceSpace: addSpace,
        paragraphs: [
          WmlParagraph(inlines: [WmlRun(text: 'Body')]),
        ],
      );
      final root = _xml(_package(_document([_ref(1)], footnotes: [note])));
      expect(
        _visibleText(_elements(root, 'note-body').single),
        addSpace ? ' Body' : 'Body',
      );
      expect(note.text, 'Body');
    });
  }

  test('does not duplicate an existing note-body separator', () {
    final note = _note(
      1,
      blocks: [
        WmlParagraph(inlines: [WmlRun(text: ' Body')]),
      ],
    );
    final root = _xml(_package(_document([_ref(1)], footnotes: [note])));
    expect(_visibleText(_elements(root, 'note-body').single), ' Body');
  });
}
