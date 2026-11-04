import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('comments attach to a range and survive a docx round-trip', () {
    final WmlParagraph para = WmlParagraph(
      inlines: <WmlInline>[WmlRun(text: 'Hello office world')],
    );
    WordComment.applyRange(para, 6, 12, 0);
    final WmlDocument doc = WmlDocument(
      comments: <WmlComment>[
        WmlComment(
          id: 0,
          author: 'Reviewer',
          initials: 'RV',
          text: 'Check this',
        ),
      ],
      sections: <WmlSection>[
        WmlSection(blocks: <WmlBlock>[para]),
      ],
    );
    expect(WordComment.idsAt(para, 7), contains(0));
    expect(WordComment.idsAt(para, 0), isEmpty);
    expect(WordComment.rangeOf(doc, 0)?.start, 6);
    expect(WordComment.rangeOf(doc, 0)?.end, 12);

    final WmlDocument copy = WordDeserializer().readBytes(
      WordSerializer().writeBytes(doc),
    );
    expect(copy.comments, hasLength(1));
    expect(copy.comments.single.text, 'Check this');
    expect(copy.comments.single.author, 'Reviewer');
    expect(WordComment.idsAt(copy.paragraphs.first, 7), contains(0));
    expect(WordComment.rangeOf(copy, 0)?.start, 6);
  });

  test('a comment can cover a multi-paragraph range', () {
    final WmlParagraph first = WmlParagraph(
      inlines: <WmlInline>[WmlRun(text: 'First line')],
    );
    final WmlParagraph second = WmlParagraph(
      inlines: <WmlInline>[WmlRun(text: 'Second line')],
    );
    final WmlDocument doc = WmlDocument(
      comments: <WmlComment>[
        WmlComment(id: 3, author: 'Editor', initials: 'ED', text: 'Both lines'),
      ],
      sections: <WmlSection>[
        WmlSection(blocks: <WmlBlock>[first, second]),
      ],
    );
    WordComment.applyDocumentRange(
      doc,
      startPara: 0,
      startIdx: 6,
      endPara: 1,
      endIdx: 6,
      id: 3,
    );
    expect(WordComment.idsAt(first, 7), contains(3));
    expect(WordComment.idsAt(first, 0), isEmpty);
    expect(WordComment.idsAt(second, 0), contains(3));
    expect(WordComment.idsAt(second, 8), isEmpty);
  });

  test('rich comment threads round-trip with replies and resolve state', () {
    final WmlParagraph para = WmlParagraph(
      inlines: <WmlInline>[WmlRun(text: 'Review this paragraph')],
    );
    WordComment.applyRange(para, 0, para.text.length, 0);
    final WmlDocument doc = WmlDocument(
      comments: <WmlComment>[
        WmlComment(
          id: 0,
          author: 'Lead',
          initials: 'LD',
          dateIso: '2026-09-06T09:00:00Z',
          resolved: true,
          paragraphs: <WmlParagraph>[
            WmlParagraph(
              inlines: <WmlInline>[
                WmlRun(
                  text: 'Please ',
                  properties: WmlRunProps(fontSizeHalfPoints: 20),
                ),
                WmlRun(
                  text: 'tighten',
                  properties: WmlRunProps(
                    bold: true,
                    italic: true,
                    underline: WmlUnderline.single,
                    color: 'C00000',
                    fontSizeHalfPoints: 20,
                  ),
                ),
                WmlRun(
                  text: ' this sentence.',
                  properties: WmlRunProps(fontSizeHalfPoints: 20),
                ),
              ],
            ),
          ],
          visuals: <WmlVisual>[
            WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                title: 'Markup',
                imageBytes: PngBytes.studioCard(),
                width: 120,
                height: 60,
              ),
            ),
          ],
        ),
        WmlComment(
          id: 1,
          author: 'Reviewer',
          initials: 'RV',
          parentId: 0,
          text: 'Done in the next pass.',
        ),
      ],
      sections: <WmlSection>[
        WmlSection(blocks: <WmlBlock>[para]),
      ],
    );

    expect(WordComment.roots(doc), hasLength(1));
    expect(WordComment.repliesOf(doc, 0), hasLength(1));
    expect(WordComment.threadRootId(doc, 1), 0);

    final WmlDocument copy = WordDeserializer().readBytes(
      WordSerializer().writeBytes(doc),
    );
    expect(copy.comments, hasLength(2));
    final WmlComment root = WordComment.byId(copy, 0)!;
    expect(root.resolved, isTrue);
    expect(root.text, contains('tighten'));
    final List<WmlRun> runs = <WmlRun>[
      for (final WmlParagraph paragraph in root.paragraphs)
        ...paragraph.inlines.whereType<WmlRun>(),
    ];
    expect(
      runs.any((WmlRun run) => run.properties.bold && run.text == 'tighten'),
      isTrue,
    );
    expect(root.visuals, isNotEmpty);
    expect(root.visuals.first.visual.isPicture, isTrue);
    expect(root.visuals.first.visual.imageBytes, isNotNull);
    expect(WordComment.byId(copy, 1)?.parentId, 0);
    expect(WordComment.byId(copy, 1)?.text, 'Done in the next pass.');

    WordComment.removeId(copy, 0);
    expect(copy.comments, isEmpty);
    expect(WordComment.idsAt(copy.paragraphs.first, 1), isEmpty);
  });
}
