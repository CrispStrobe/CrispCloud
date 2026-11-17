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
  commentTests();
  footnoteTests();
  test('writes modeled Word text, runs, tables and pictures as ODT', () {
    final document = WmlDocument(
      properties: OfficeDocumentProperties(title: 'Writer smoke'),
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
                  cells: [
                    WmlTableCell(
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
    expect(content, contains('Pictures/image1.png'));
    expect(styles, contains('fo:page-width'));
    expect(package.getPart('/Pictures/image1.png'), isNotNull);
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
    expect(content, contains('<text:note-citation>1</text:note-citation>'));
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
