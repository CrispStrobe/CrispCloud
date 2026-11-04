import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  WmlParagraph heading(String text, int level) {
    final WmlParagraph paragraph = WmlParagraph(
      inlines: <WmlInline>[WmlRun(text: text)],
    );
    WordToc.applyHeading(paragraph, level);
    return paragraph;
  }

  test('applyHeading sets outline level and run look', () {
    final WmlParagraph para = heading('Intro', 1);
    expect(para.properties.headingLevel, 1);
    expect(para.properties.styleId, 'Heading1');
    expect(para.inlines.whereType<WmlRun>().first.properties.bold, isTrue);
    expect(
      para.inlines.whereType<WmlRun>().first.properties.fontSizeHalfPoints,
      32,
    );
    WordToc.applyHeading(para, 0);
    expect(para.properties.headingLevel, isNull);
    expect(para.properties.styleId, 'Normal');
  });

  test('TOC collects headings and page numbers across breaks', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlToc(title: 'Contents', minLevel: 1, maxLevel: 2),
            heading('One', 1),
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Body')]),
            WmlParagraph(
              properties: WmlParagraphProps(pageBreakBefore: true),
              inlines: <WmlInline>[WmlRun(text: 'After break')],
            ),
            heading('Two', 2),
            heading('Deep', 3),
          ],
        ),
      ],
    );
    WordToc.refreshAll(doc);
    final WmlToc toc = WordToc.tocs(doc).single;
    expect(toc.itemParagraphs, hasLength(2));
    expect(doc.paragraphs.first, same(toc.titleParagraph));
    expect(
      WordToc.headings(doc).map((WmlHeadingRef h) => h.text).toList(),
      <String>['One', 'Two', 'Deep'],
    );
    expect(toc.entries.map((WmlTocEntry e) => e.text).toList(), <String>[
      'One',
      'Two',
    ]);
    var laid = WordLayoutEngine(font: null).layout(doc);
    expect(WordToc.syncPageNumbers(doc, laid), isTrue);
    expect(toc.entries[0].pageNumber, 1);
    expect(toc.entries[1].pageNumber, 2);
    laid = WordLayoutEngine(font: null).layout(doc);
    expect(
      laid.pages.first.frames.any(
        (LaidOutBox box) => box.kind == LaidOutBoxKind.tocEntry,
      ),
      isTrue,
    );
    expect(
      laid.pages.first.lines.any(
        (LaidOutLine line) => line.tocTargetParagraph != null,
      ),
      isTrue,
    );
  });

  test('TOC and headings survive Word serialize round-trip', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlToc(
              title: 'Contents',
              entries: <WmlTocEntry>[
                WmlTocEntry(
                  text: 'Alpha',
                  level: 1,
                  headingParagraphIndex: 0,
                  pageNumber: 1,
                ),
              ],
            ),
            heading('Alpha', 1),
            heading('Beta', 2),
          ],
        ),
      ],
    );
    final WmlDocument copy = WordDeserializer().readBytes(
      WordSerializer().writeBytes(doc),
    );
    expect(WordToc.headings(copy).map((WmlHeadingRef h) => h.text), <String>[
      'Alpha',
      'Beta',
    ]);
    expect(WordToc.tocs(copy), isNotEmpty);
    final WmlToc toc = WordToc.tocs(copy).single;
    expect(toc.title, 'Contents');
    expect(toc.titleParagraph.text, 'Contents');
    expect(toc.itemParagraphs, isNotEmpty);
    expect(
      toc.entries.any((WmlTocEntry e) => e.text.contains('Alpha')),
      isTrue,
    );
  });

  test('page-number sync keeps customized TOC paragraphs', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlToc(title: 'Contents', minLevel: 1, maxLevel: 2),
            heading('One', 1),
            heading('Two', 2),
          ],
        ),
      ],
    );
    WordToc.refreshAll(doc);
    final WmlToc toc = WordToc.tocs(doc).single;
    final WmlParagraph item = toc.itemParagraphs.first;
    item.inlines.whereType<WmlRun>().first
      ..text = 'Custom one'
      ..properties.color = 'C00000';
    toc.titleParagraph.inlines.whereType<WmlRun>().first.properties.color =
        'FF00FF';
    final laid = WordLayoutEngine(font: null).layout(doc);
    WordToc.syncPageNumbers(doc, laid);
    expect(identical(toc.itemParagraphs.first, item), isTrue);
    expect(item.text, 'Custom one');
    expect(item.inlines.whereType<WmlRun>().first.properties.color, 'C00000');
    expect(
      toc.titleParagraph.inlines.whereType<WmlRun>().first.properties.color,
      'FF00FF',
    );
    WordToc.refresh(toc, doc);
    expect(toc.itemParagraphs.first.text, 'One');
    expect(
      toc.titleParagraph.inlines.whereType<WmlRun>().first.properties.color,
      'FF00FF',
    );
  });

  test('hyperlinks and heading bookmarks round-trip', () {
    final WmlParagraph heading = WmlParagraph(
      inlines: <WmlInline>[WmlRun(text: 'Target')],
    );
    WordToc.applyHeading(heading, 1);
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            heading,
            WmlParagraph(
              inlines: <WmlInline>[
                WordLink.linkedRun(
                  'Go',
                  WmlHyperlink(anchor: heading.properties.bookmarkName),
                ),
                WordLink.linkedRun(
                  'Web',
                  const WmlHyperlink(url: 'https://example.com'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final WmlDocument copy = WordDeserializer().readBytes(
      WordSerializer().writeBytes(doc),
    );
    expect(copy.paragraphs.first.properties.bookmarkName, isNotNull);
    expect(
      copy.paragraphs.last.inlines.whereType<WmlRun>().first.hyperlink?.anchor,
      copy.paragraphs.first.properties.bookmarkName,
    );
    expect(
      copy.paragraphs.last.inlines.whereType<WmlRun>().last.hyperlink?.url,
      'https://example.com',
    );
    expect(
      WordLink.paragraphIndexForAnchor(
        copy,
        copy.paragraphs.first.properties.bookmarkName!,
      ),
      0,
    );
  });

  test('rebindHeadings repairs absorbed TOC paragraph indexes', () {
    final WmlDocument doc = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlToc(title: 'Contents', minLevel: 1, maxLevel: 2),
            heading('One', 1),
            WmlParagraph(
              properties: WmlParagraphProps(pageBreakBefore: true),
              inlines: <WmlInline>[WmlRun(text: 'Gap')],
            ),
            heading('Two', 2),
          ],
        ),
      ],
    );
    WordToc.refreshAll(doc);
    final WmlToc toc = WordToc.tocs(doc).single;
    toc.entries[0].headingParagraphIndex = 0;
    toc.entries[1].headingParagraphIndex = 1;
    WordToc.rebindHeadings(doc);
    expect(toc.entries[0].headingParagraphIndex, greaterThan(0));
    expect(
      toc.entries[1].headingParagraphIndex,
      greaterThan(toc.entries[0].headingParagraphIndex),
    );
    final laid = WordLayoutEngine(font: null).layout(doc);
    expect(WordToc.syncPageNumbers(doc, laid), isTrue);
    expect(toc.entries[0].pageNumber, 1);
    expect(toc.entries[1].pageNumber, 2);
  });

  test('TOC page numbers sit on the right margin, not the title', () {
    expect(
      WordToc.pageNumberX(
        pageWidth: 595.28,
        marginRight: 54,
        numberWidth: 12,
      ),
      closeTo(529.28, 0.01),
    );
    expect(
      WordToc.leaderEndX(
        pageWidth: 595.28,
        marginRight: 54,
        numberWidth: 12,
      ),
      closeTo(525.28, 0.01),
    );
    expect(
      WordToc.pageNumberX(
        pageWidth: 595.28,
        marginRight: 54,
        numberWidth: 12,
      ),
      greaterThan(200),
    );
  });

  test('Docx builder heading writes outline level', () {
    final WmlDocument doc = WordDeserializer().readBytes(
      (DocxDocumentBuilder()..heading('Title', level: 2)).build(),
    );
    expect(doc.paragraphs.first.properties.headingLevel, 2);
    expect(doc.paragraphs.first.properties.styleId, 'Heading2');
  });
}
