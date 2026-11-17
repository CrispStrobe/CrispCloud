import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

String _odfText(XmlNode node) {
  if (node is XmlText) return node.text;
  if (node is! XmlElement) return '';
  if (node.namespaceUri == 'urn:oasis:names:tc:opendocument:xmlns:text:1.0') {
    switch (node.localName) {
      case 's':
        return ' ' * int.parse(node.getAttribute('c') ?? '1');
      case 'tab':
        return '\t';
      case 'line-break':
        return '\n';
    }
  }
  return node.children.map(_odfText).join();
}

XmlElement _odtBody(OpcPackage package) => XmlDocument.parse(
  package.getPart('/content.xml')!.readText(),
).root!.firstChild('body')!.firstChild('text')!;

void main() {
  tocTests();
  fieldTests();
  paragraphBreakTests();
  columnTests();
  tabStopTests();
  paragraphShadingTests();
  pageFieldTests();
  linkTests();
  nestedListTests();
  sectionTests();
  commentTests();
  footnoteTests();
  test('writes modeled Word text, runs, tables and pictures as ODT', () {
    final document = WmlDocument(
      properties: OfficeDocumentProperties(
        title: 'Writer smoke',
        subject: 'Metadata',
        creator: 'Author',
      ),
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              properties: WmlParagraphProps(headingLevel: 1),
              inlines: [WmlRun(text: 'Quarterly review')],
            ),
            WmlParagraph(
              properties: WmlParagraphProps(numId: 1),
              inlines: [WmlRun(text: 'First bullet')],
            ),
            WmlParagraph(
              properties: WmlParagraphProps(numId: 1),
              inlines: [WmlRun(text: 'Second bullet')],
            ),
            WmlParagraph(
              properties: WmlParagraphProps(numId: 2, listLabel: '1. '),
              inlines: [WmlRun(text: 'First numbered')],
            ),
            WmlParagraph(
              properties: WmlParagraphProps(
                justification: WmlJustification.center,
              ),
              inlines: [
                WmlRun(text: 'Plain '),
                WmlRun(
                  text: 'bold',
                  properties: WmlRunProps(
                    bold: true,
                    color: 'FF0000',
                    fontSizeHalfPoints: 28,
                  ),
                ),
                WmlRun(text: ' tail'),
              ],
            ),
            WmlTable(
              grid: [120, 180],
              rows: [
                WmlTableRow(
                  height: 24,
                  cells: [
                    WmlTableCell(
                      borderTop: true,
                      borderLeft: true,
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
              ],
            ),
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                title: 'Logo',
                imageBytes: _png,
                width: 72,
                height: 72,
              ),
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    final styles = package.getPart('/styles.xml')!.readText();
    final meta = package.getPart('/meta.xml')!.readText();
    expect(meta, contains('<dc:title>Writer smoke</dc:title>'));
    expect(meta, contains('<dc:subject>Metadata</dc:subject>'));
    expect(meta, contains('<dc:creator>Author</dc:creator>'));
    expect(content, contains('<text:h'));
    expect(content, contains('Quarterly review'));
    expect(
      OfficeTextExtractor.extract(
        OdtDocumentWriter.writeBytes(document),
        name: 'smoke.odt',
      ).paragraphs,
      contains('Plain bold tail'),
    );
    expect(_odfText(_odtBody(package)), contains('Quarterly review'));
    expect(_odfText(_odtBody(package)), contains('Plain bold tail'));
    expect(content, contains('bold'));
    expect(content, contains('fo:font-weight="bold"'));
    expect(content, contains('<text:list'));
    expect(content, contains('First bullet'));
    expect(content, contains('Second bullet'));
    expect(content, contains('First numbered'));
    expect(content, contains('text:style-name="L2"'));
    expect(content, contains('<table:table'));
    expect(content, contains('fo:border-top="0.5pt solid #000000"'));
    expect(content, contains('style:min-row-height="24.00pt"'));
    expect(content, contains('Pictures/image1.png'));
    expect(styles, contains('fo:page-width'));
    expect(styles, contains('style:num-format="1"'));
    expect(styles, contains('style:num-suffix="."'));
    expect(styles, isNot(contains('loext:num-list-format')));
    expect(package.getPart('/Pictures/image1.png'), isNotNull);
  });

  test(
    'table lists retain paragraph layout and use standard number styles',
    () {
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlTable(
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(
                        blocks: [
                          WmlParagraph(
                            properties: WmlParagraphProps(
                              numId: 7,
                              listLabel: '1. ',
                              rightToLeft: true,
                              justification: WmlJustification.right,
                              lineSpacingRule: WmlLineSpacingRule.exact,
                              lineSpacing: 18,
                            ),
                            inlines: [
                              WmlRun(
                                text: 'Numbered cell',
                                properties: WmlRunProps(bold: true),
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
      final package = OpcPackage.openBytes(
        OdtDocumentWriter.writeBytes(document),
      );
      final body = _odtBody(package);
      final cell = body
          .firstChild('table')!
          .firstChild('table-row')!
          .firstChild('table-cell')!;
      final list = cell.firstChild('list')!;
      expect(list.getAttribute('style-name'), 'L2');
      final paragraph = list.firstChild('list-item')!.firstChild('p')!;
      expect(_odfText(paragraph), 'Numbered cell');
      final content = XmlDocument.parse(
        package.getPart('/content.xml')!.readText(),
      ).root!;
      final style = content
          .firstChild('automatic-styles')!
          .childrenNamed('style')
          .singleWhere(
            (style) =>
                style.getAttribute('name') ==
                paragraph.getAttribute('style-name'),
          );
      final properties = style.firstChild('paragraph-properties')!;
      expect(properties.getAttribute('line-height'), '18.00pt');
      expect(properties.getAttribute('writing-mode'), 'rl-tb');
      expect(properties.getAttribute('text-align'), 'right');
    },
  );

  test('empty documents keep the list catalog within ODF core attributes', () {
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(WmlDocument()),
    );
    final styles = package.getPart('/styles.xml')!.readText();
    expect(styles, isNot(contains('loext:')));
    final root = XmlDocument.parse(styles).root!;
    final numbered = root
        .firstChild('styles')!
        .childrenNamed('list-style')
        .singleWhere((style) => style.getAttribute('name') == 'L2');
    expect(numbered.childrenNamed('list-level-style-number'), hasLength(9));
  });

  test('exports Zotero cached results without hidden field instructions', () {
    final source = OpcPackage.create(OpcPackageKind.word);
    source
        .getPart('/word/document.xml')!
        .writeText(
          File('test/fixtures/zotero/word_document.xml').readAsStringSync(),
        );
    final document = WordDeserializer().read(source);
    final fields = WordZotero.fields(document);
    expect(fields, hasLength(4));
    final before = fields
        .map((field) => (field.instruction, field.cachedText))
        .toList();
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    final paragraphs = _odtBody(package).childrenNamed('p');
    expect(paragraphs.map(_odfText), [
      'A study (Lovelace, 1843) confirmed.',
      '(Hopper, 1952)',
      'Hopper. Compilers.',
      'Lovelace. A & B.',
      'Keep malformed cache',
      'Keep other manager',
    ]);
    for (final instruction in [
      'ADDIN',
      'ZOTERO_ITEM',
      'CSL_CITATION',
      'ZOTERO_BIBL',
      'CSL_BIBLIOGRAPHY',
      'citationID',
      'broken JSON',
      'ANOTHER_MANAGER',
    ]) {
      expect(content, isNot(contains(instruction)));
    }
    expect(content, contains('fo:font-weight="bold"'));
    expect(content, contains('fo:font-style="italic"'));
    expect(
      WordZotero.fields(
        document,
      ).map((field) => (field.instruction, field.cachedText)).toList(),
      before,
    );
  });

  test('preserves whitespace in body runs and basic headers and footers', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              inlines: [
                WmlRun(text: '  A & <B>\tC\r\nD\nE\rF '),
                WmlRun(text: ' tail  ', properties: WmlRunProps(bold: true)),
              ],
            ),
          ],
          header: [
            WmlParagraph(inlines: [WmlRun(text: ' Head\tA  B ')]),
          ],
          footer: [
            WmlParagraph(inlines: [WmlRun(text: 'Foot\nLine 2 ')]),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    final paragraph = _odtBody(package).childrenNamed('p').single;
    expect(_odfText(paragraph), '  A & <B>\tC\nD\nE\nF  tail  ');
    expect(content, contains('<text:s text:c="2"/>'));
    expect(content, contains('<text:tab/>'));
    expect('<text:line-break/>'.allMatches(content), hasLength(3));
    expect(content, contains('A'));
    expect(content, contains('&amp;'));
    expect(content, contains('&lt;B&gt;'));
    final master = XmlDocument.parse(
      package.getPart('/styles.xml')!.readText(),
    ).root!.firstChild('master-styles')!.firstChild('master-page')!;
    expect(_odfText(master.firstChild('header')!), ' Head\tA  B ');
    expect(_odfText(master.firstChild('footer')!), 'Foot\nLine 2 ');
  });
}

void footnoteTests() {
  test('writes footnote references and bodies', () {
    final document = WmlDocument(
      footnotes: [
        WmlNote(
          id: 1,
          endnote: false,
          paragraphs: [
            WmlParagraph(inlines: [WmlRun(text: 'Footnote text')]),
          ],
        ),
      ],
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              inlines: [
                WmlRun(text: 'Body'),
                WmlRun(noteRefId: 1),
              ],
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    expect(content, contains('<text:note'));
    expect(content, contains('text:note-class="footnote"'));
    expect(
      content,
      contains('<text:note-citation text:label="1">1</text:note-citation>'),
    );
    expect(content, contains('Footnote text'));
  });
}

void commentTests() {
  test('writes ODT comments', () {
    final document = WmlDocument(
      comments: [
        WmlComment(
          id: 1,
          author: 'Reviewer',
          dateIso: '2026-11-17T00:00:00Z',
          paragraphs: [
            WmlParagraph(inlines: [WmlRun(text: 'Comment text')]),
          ],
        ),
      ],
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              inlines: [
                WmlRun(text: 'Annotated', commentIds: [1]),
              ],
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    expect(content, contains('<office:annotation'));
    expect(content, contains('<dc:creator>Reviewer</dc:creator>'));
    expect(content, contains('Comment text'));
  });
}

void sectionTests() {
  test('writes section page layouts and breaks', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'First section')]),
          ],
        ),
        WmlSection(
          pageSize: WmlPageSize.letter(),
          margins: WmlPageMargins.narrow,
          header: [
            WmlParagraph(inlines: [WmlRun(text: 'Second header')]),
          ],
          footer: [
            WmlParagraph(inlines: [WmlRun(text: 'Second footer')]),
          ],
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'Second section')]),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    final styles = package.getPart('/styles.xml')!.readText();
    expect(content, contains('text:style-name="SB1"'));
    expect(content, contains('Second section'));
    expect(styles, contains('style:name="pm1"'));
    expect(styles, contains('fo:page-width="612.00pt"'));
    expect(styles, contains('style:page-layout-name="pm1"'));
    expect(styles, contains('Second header'));
    expect(styles, contains('Second footer'));
  });
}

void nestedListTests() {
  test('writes nested ODT list levels', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              properties: WmlParagraphProps(numId: 1, ilvl: 0),
              inlines: [WmlRun(text: 'Parent')],
            ),
            WmlParagraph(
              properties: WmlParagraphProps(numId: 1, ilvl: 1),
              inlines: [WmlRun(text: 'Child one')],
            ),
            WmlParagraph(
              properties: WmlParagraphProps(numId: 1, ilvl: 1),
              inlines: [WmlRun(text: 'Child two')],
            ),
            WmlParagraph(
              properties: WmlParagraphProps(numId: 1, ilvl: 0),
              inlines: [WmlRun(text: 'Sibling')],
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    expect(RegExp(r'<text:list ').allMatches(content).length, 2);
    expect(content, contains('Parent'));
    expect(content, contains('Child one'));
    expect(content, contains('Child two'));
    expect(content, contains('Sibling'));
  });
}

void linkTests() {
  test('writes ODT bookmarks and hyperlinks', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              inlines: [
                WmlBookmarkBoundary(id: '1', isStart: true, name: 'Target'),
                WmlRun(text: 'Jump'),
                WmlBookmarkBoundary(id: '1', isStart: false, name: 'Target'),
                WmlRun(
                  text: 'internal',
                  hyperlink: const WmlHyperlink(anchor: 'Target'),
                ),
                WmlRun(
                  text: 'external',
                  hyperlink: const WmlHyperlink(url: 'https://example.com'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    expect(content, contains('<text:bookmark-start'));
    expect(content, contains('text:name="Target"'));
    expect(content, contains('xlink:href="#Target"'));
    expect(content, contains('xlink:href="https://example.com"'));
  });
}

void pageFieldTests() {
  test('writes header page-number fields', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          header: [
            WmlParagraph(
              properties: WmlParagraphProps(pageNumberField: true),
              inlines: [WmlRun(text: '1')],
            ),
          ],
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'Body')]),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final styles = package.getPart('/styles.xml')!.readText();
    expect(styles, contains('<text:page-number/>'));
  });
}

void paragraphShadingTests() {
  test('writes paragraph shading and borders', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              properties: WmlParagraphProps(
                shadingFill: 'FFFF00',
                borderColor: 'FF0000',
              ),
              inlines: [WmlRun(text: 'Shaded')],
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    expect(content, contains('fo:background-color="#ffff00"'));
    expect(content, contains('fo:border="0.5pt solid #ff0000"'));
  });
}

void tabStopTests() {
  test('writes custom paragraph tab stops', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              properties: WmlParagraphProps(
                tabs: const [
                  WmlTabStop(position: 72, alignment: WmlTabAlignment.center),
                  WmlTabStop(
                    position: 144,
                    alignment: WmlTabAlignment.right,
                    leader: WmlTabLeader.dot,
                  ),
                ],
              ),
              inlines: [WmlRun(text: 'One\tTwo\tThree')],
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    expect(content, contains('<style:tab-stops>'));
    expect(content, contains('style:position="72.00pt"'));
    expect(content, contains('style:type="center"'));
    expect(content, contains('style:type="right"'));
    expect(content, contains('style:leader-style="dotted"'));
  });
}

void columnTests() {
  test('writes multi-column ODT sections', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          columnCount: 2,
          columnSpace: 18,
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'Columns')]),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    const officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
    const styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
    const textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
    const foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
    final content = XmlDocument.parse(
      package.getPart('/content.xml')!.readText(),
    ).root!;
    final section = content
        .firstChild('body', namespaceUri: officeNs)!
        .firstChild('text', namespaceUri: officeNs)!
        .childrenNamed('section', namespaceUri: textNs)
        .single;
    expect(section.getAttribute('name', namespaceUri: textNs), 'Section0');
    expect(_odfText(section), 'Columns');
    final styleName = section.getAttribute('style-name', namespaceUri: textNs);
    final properties = content
        .firstChild('automatic-styles', namespaceUri: officeNs)!
        .childrenNamed('style', namespaceUri: styleNs)
        .singleWhere(
          (style) =>
              style.getAttribute('name', namespaceUri: styleNs) == styleName &&
              style.getAttribute('family', namespaceUri: styleNs) == 'section',
        )
        .firstChild('section-properties', namespaceUri: styleNs)!;
    // ODF 1.3, sections 17.11–17.12: the child columns element owns these
    // attributes; placing them on section-properties is not an ODF column style.
    final columns = properties.firstChild('columns', namespaceUri: styleNs);
    expect(columns, isNotNull);
    expect(columns!.getAttribute('column-count', namespaceUri: foNs), '2');
    expect(columns.getAttribute('column-gap', namespaceUri: foNs), '18.00pt');
    expect(properties.getAttribute('column-count', namespaceUri: foNs), isNull);
    expect(properties.getAttribute('column-gap', namespaceUri: foNs), isNull);
  });
}

void paragraphBreakTests() {
  test('writes column breaks and keep-together', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              properties: WmlParagraphProps(
                columnBreakBefore: true,
                keepTogether: true,
              ),
              inlines: [WmlRun(text: 'Keep')],
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    expect(content, contains('fo:break-before="column"'));
    expect(content, contains('fo:keep-together="always"'));
  });
}

void fieldTests() {
<<<<<<< HEAD
  test('writes PAGE and NUMPAGES fields without cached results', () {
=======
  test('writes PAGE and NUMPAGES with one cached display per native field', () {
>>>>>>> f22a0312 (Sync latest ODT writer with AOT-free Quds main)
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(
              inlines: [
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
                WmlFieldBoundary(
                  kind: WmlFieldBoundaryKind.instruction,
                  text: ' PAGE \\* MERGEFORMAT ',
                ),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
                WmlRun(text: '99'),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
                WmlFieldBoundary(
                  kind: WmlFieldBoundaryKind.instruction,
                  text: ' NUMPAGES ',
                ),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
                WmlRun(text: '99'),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
              ],
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
<<<<<<< HEAD
    final content = package.getPart('/content.xml')!.readText();
    expect(RegExp(r'<text:page-number/>').allMatches(content).length, 1);
    expect(RegExp(r'<text:page-count/>').allMatches(content).length, 1);
    expect(content, isNot(contains('>99<')));
=======
    final paragraph = _odtBody(package).firstChild('p')!;
    final fields = paragraph.childElements
        .expand((span) => span.childElements)
        .toList();
    expect(fields.map((field) => field.localName), [
      'page-number',
      'page-count',
    ]);
    expect(fields.map((field) => field.text), ['99', '99']);
    expect(paragraph.text, '9999');
>>>>>>> f22a0312 (Sync latest ODT writer with AOT-free Quds main)
  });
}

void tocTests() {
  test('writes cached table-of-contents entries', () {
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlToc(
              title: 'Contents',
              minLevel: 1,
              maxLevel: 3,
              entries: [
                WmlTocEntry(
                  text: 'Introduction',
                  level: 1,
                  headingParagraphIndex: 0,
                  pageNumber: 2,
                ),
                WmlTocEntry(
                  text: 'Details',
                  level: 2,
                  headingParagraphIndex: 1,
                  pageNumber: 4,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = package.getPart('/content.xml')!.readText();
    expect(content, contains('Contents'));
    expect(content, contains('Introduction'));
    expect(content, contains('Details'));
    expect(content, contains('<text:tab/>2'));
    expect(content, contains('<text:tab/>4'));
  });
}
