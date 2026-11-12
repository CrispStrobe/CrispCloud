// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';

void main() {
  test(
    'stored first/even header content does not activate different-page flags',
    () {
      for (final enabled in [false, true]) {
        final document = parseLegacyWordDocument(
          storyWordFixture(
            main: 'Body\r',
            headers: 'E\r\rD\r\rV\r\rW\r\rF\r\rG\r\r\r',
            tablePairs: {
              11: storyPlc([
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                3,
                6,
                9,
                12,
                15,
                18,
                0xffffffff,
              ]),
              31: [enabled ? 1 : 0, ...List.filled(83, 0)],
            },
            sections: [
              WordFixtureSection(5, wordSprm(0x300a, [enabled ? 1 : 0])),
            ],
          ),
        );
        expect(document.stories, hasLength(6));
        expect(document.evenAndOddHeaders, enabled);
        expect(document.sections.single.titlePage, enabled);
      }
    },
  );
  test('rejects a truncated document-options structure', () {
    expect(
      () => parseLegacyWordDocument(
        storyWordFixture(
          main: 'Body\r',
          tablePairs: {
            31: [1],
          },
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'private field anchors do not expose note or comment content as active references',
    () {
      const main = 'A\x13 REF Name\x14\x02\x05Secret\x15B\r';
      const note = '\x02Note\r', comment = '\x05Comment\r';
      final markers = [
        main.indexOf('\x13'),
        main.indexOf('\x14'),
        main.indexOf('\x15'),
      ];
      final document = parseLegacyWordDocument(
        storyWordFixture(
          main: main,
          footnotes: '$note\r',
          comments: '$comment\r',
          tablePairs: {
            2: storyPlc([main.indexOf('\x02'), 0xffffffff], wordU16(1)),
            3: storyPlc([0, note.length, 0xffffffff]),
            4: storyPlc([
              main.indexOf('\x05'),
              0xffffffff,
            ], storyCommentRecord()),
            5: storyPlc([0, comment.length, 0xffffffff]),
            36: storyXst('Alice'),
            16: storyPlc(
              [...markers, 0xffffffff],
              [0x13, 0, 0x14, 0, 0x15, 0xa0],
            ),
          },
        ),
      );
      expect(document.plainText, 'AB');
      expect(document.noteReferences.single.presentation.hidden, isTrue);
      expect(document.commentReferences.single.presentation.hidden, isTrue);
      expect(document.stories.map((s) => s.plainText), ['Note', 'Comment']);
    },
  );

  test('a deleted footnote marker keeps its revision state', () {
    const note = '\x02Note\r';
    final document = parseLegacyWordDocument(
      storyWordFixture(
        main: 'A\x02B\r',
        footnotes: '$note\r',
        tablePairs: {
          2: storyPlc([1, 0xffffffff], wordU16(1)),
          3: storyPlc([0, note.length, 0xffffffff]),
        },
        characterRuns: [
          const WordFixtureFkpRun(8192, 16386),
          WordFixtureFkpRun(16386, 16388, properties: wordSprm(0x0800, [1])),
          const WordFixtureFkpRun(16388, 28672),
        ],
      ),
    );
    expect(document.noteReferences.single.presentation.deleted, isTrue);
    expect(document.noteReferences.single.presentation.hidden, isFalse);
  });

  test(
    'header fields retain global positions while PLC positions remain story-local',
    () {
      const text = '\x13 PAGE \x147\x15\r';
      final ends = [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        text.length + 1,
        text.length + 1,
        text.length + 1,
        text.length + 1,
        text.length + 1,
      ];
      final document = parseLegacyWordDocument(
        storyWordFixture(
          main: 'Body\r',
          headers: '$text\r\r',
          tablePairs: {
            11: storyPlc([...ends, 0xffffffff]),
            17: storyPlc(
              [0, text.indexOf('\x14'), text.indexOf('\x15'), 0xffffffff],
              [0x13, 33, 0x14, 0, 0x15, 0x80],
            ),
          },
        ),
      );
      expect(document.fields.single.startCp, 5);
      expect(document.fields.single.storyId, 'header-0-normal');
      expect(document.stories.single.plainText, '7');
      expect(document.plainText, 'Body');
    },
  );

  test(
    'formatted footnotes/endnotes follow global CP references and preserve main-only text',
    () {
      const main = 'A\x02B\x02\r',
          footnote = '\x02Foot\r',
          endnote = '\x02End\r';
      final document = parseLegacyWordDocument(
        storyWordFixture(
          main: main,
          footnotes: '$footnote\r',
          endnotes: '$endnote\r',
          tablePairs: {
            2: storyPlc([1, 0xffffffff], wordU16(1)),
            3: storyPlc([0, footnote.length, 0xffffffff]),
            46: storyPlc([3, 0xffffffff], wordU16(1)),
            47: storyPlc([0, endnote.length, 0xffffffff]),
          },
          characterRuns: [
            WordFixtureFkpRun(
              8192,
              8192 + footnote.length * 2,
              properties: wordSprm(0x0835, [1]),
            ),
            const WordFixtureFkpRun(8192 + footnote.length * 2, 28672),
          ],
        ),
      );
      expect(document.plainText, 'AB');
      expect(document.noteReferences.map((ref) => ref.anchorCp), [1, 3]);
      final note = document.stories.singleWhere(
        (s) => s.kind == LegacyWordStoryKind.footnote,
      );
      expect(note.startCp, main.length);
      expect(note.plainText, 'Foot');
      expect(
        (note.blocks.single as LegacyWordParagraph).runs.single.style.bold,
        isTrue,
      );
      expect(
        document.stories
            .singleWhere((s) => s.kind == LegacyWordStoryKind.endnote)
            .plainText,
        'End',
      );
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.notesOmitted)),
      );
    },
  );

  test(
    'header slots skip inheritance, remove guard CR and retain an explicit blank',
    () {
      const header = 'Header\r\r', footer = '\r\r';
      final ends = [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        header.length,
        header.length,
        header.length + footer.length,
        header.length + footer.length,
        header.length + footer.length,
      ];
      final document = parseLegacyWordDocument(
        storyWordFixture(
          main: 'Body\r',
          headers: '$header$footer\r',
          tablePairs: {
            11: storyPlc([...ends, 0xffffffff]),
          },
        ),
      );
      expect(document.stories.length, 2);
      final normal = document.stories.first;
      expect(normal.id, 'header-0-normal');
      expect(normal.plainText, 'Header');
      expect(normal.endCp - normal.startCp, header.length - 1);
      expect(document.stories.last.id, 'footer-0-normal');
      expect(document.stories.last.plainText, '');
      expect(document.stories.last.blocks, hasLength(1));
      expect(document.plainText, 'Body');
    },
  );

  test(
    'comment range, owner and initials map through tag and end-index tables',
    () {
      const comment = '\x05Comment\r';
      final document = parseLegacyWordDocument(
        storyWordFixture(
          main: 'AB\x05C\r',
          comments: '$comment\r',
          tablePairs: {
            4: storyPlc([2, 0xffffffff], storyCommentRecord(tag: 77)),
            5: storyPlc([0, comment.length, 0xffffffff]),
            36: storyXst('Alice'),
            37: [
              ...wordU16(0xffff),
              ...wordU16(1),
              ...wordU16(10),
              ...wordU16(0),
              ...wordU16(0x100),
              ...wordU32(77),
              ...wordU32(0xffffffff),
            ],
            42: storyPlc([0, 0xffffffff], [...wordU16(0), ...wordU16(0)]),
            43: storyPlc([2, 0xffffffff]),
          },
        ),
      );
      final ref = document.commentReferences.single;
      expect(
        (ref.author, ref.initials, ref.rangeStartCp, ref.rangeEndCp),
        ('Alice', 'AB', 0, 2),
      );
      expect(document.stories.single.plainText, 'Comment');
      expect(document.plainText, 'ABC');
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.commentsOmitted)),
      );
    },
  );

  test(
    'textbox text requires a matching referenced FSPA shape and omits final spare slot',
    () {
      const content = 'Text box\r';
      final ftxbxs = [
        ...wordU32(1),
        ...wordU32(0),
        ...wordU16(0),
        ...wordU32(0),
        ...wordU32(42),
        ...wordU32(0),
        ...List.filled(22, 0),
      ];
      final shape = [
        ...wordU32(42),
        ...wordU32(0),
        ...wordU32(0),
        ...wordU32(1440),
        ...wordU32(720),
        ...wordU16(0),
        ...wordU32(0),
      ];
      final document = parseLegacyWordDocument(
        storyWordFixture(
          main: 'A\x08B\r',
          characterRuns: [
            const WordFixtureFkpRun(8192, 16386),
            WordFixtureFkpRun(16386, 16388, properties: wordSprm(0x0855, [1])),
            const WordFixtureFkpRun(16388, 28672),
          ],
          textboxes: '${content}x',
          tablePairs: {
            56: storyPlc([0, content.length, content.length + 1], ftxbxs),
            40: storyPlc([1, 0xffffffff], shape),
          },
        ),
      );
      expect(document.stories.single.plainText, 'Text box');
      expect(document.textboxReferences.single.shapeId, 42);
      expect(document.textboxReferences.single.anchorCp, 1);
      expect(document.media.drawings.single.shapeId, 42);
      expect(document.plainText, 'AB');
    },
  );

  test(
    'nested fields retain syntax, cached results and global hierarchy without evaluation',
    () {
      const main = 'A\x13 REF \x13 PAGE \x142\x15 \x14Value\x15Z\r';
      final document = parseLegacyWordDocument(storyWordFixture(main: main));
      final outer = document.fields.singleWhere((f) => f.parentId == null);
      final inner = document.fields.singleWhere((f) => f.parentId != null);
      expect(outer.type, 'REF');
      expect(outer.instruction, contains('\x13 PAGE \x142\x15'));
      expect(outer.storedResult, 'Value');
      expect(inner.parentId, outer.id);
      expect(inner.type, 'PAGE');
      expect(inner.storedResult, '2');
      expect(document.plainText, 'AValueZ');
      expect(document.safeHtml, isNot(contains('REF')));
    },
  );

  test('private stored field result is retained only in metadata', () {
    const main = 'A\x13 REF HiddenName \x14Secret\x15B\r';
    final markers = [
      main.indexOf('\x13'),
      main.indexOf('\x14'),
      main.indexOf('\x15'),
    ];
    final document = parseLegacyWordDocument(
      storyWordFixture(
        main: main,
        tablePairs: {
          16: storyPlc(
            [...markers, 0xffffffff],
            [0x13, 0, 0x14, 0, 0x15, 0xb0],
          ),
        },
      ),
    );
    expect(document.fields.single.privateResult, isTrue);
    expect(document.fields.single.locked, isTrue);
    expect(document.fields.single.storedResult, 'Secret');
    expect(document.plainText, 'AB');
    expect(document.safeHtml, isNot(contains('Secret')));
    expect(
      (document.blocks.single as LegacyWordParagraph).runs
          .map((r) => r.text)
          .join(),
      'AB',
    );
  });

  test(
    'bookmarks map through explicit end indices and column limit is exclusive',
    () {
      final document = parseLegacyWordDocument(
        storyWordFixture(
          main: 'ABCDE\r',
          tablePairs: {
            21: storyBookmarkNames(['Outer', 'Inner']),
            22: storyPlc(
              [0, 1, 0xffffffff],
              [...wordU16(1), ...wordU16(0), ...wordU16(0), ...wordU16(0x8301)],
            ),
            23: storyPlc([3, 5, 0xffffffff]),
          },
        ),
      );
      expect(document.bookmarks.map((b) => (b.startCp, b.endCp)), [
        (0, 5),
        (1, 3),
      ]);
      expect(
        (document.bookmarks.last.firstCell, document.bookmarks.last.lastCell),
        (1, 2),
      );
    },
  );

  test(
    'rejects missing note references rather than treating auxiliary bytes as body',
    () {
      expect(
        () => parseLegacyWordDocument(
          storyWordFixture(main: 'A\r', footnotes: 'lost\r\r'),
        ),
        throwsFormatException,
      );
    },
  );
  test('rejects wrong field PLC markers and duplicate separators', () {
    const text = '\x13 REF A\x14B\x15\r';
    expect(
      () => parseLegacyWordDocument(
        storyWordFixture(
          main: text,
          tablePairs: {
            16: storyPlc([0, 0xffffffff], [0x15, 0]),
          },
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => parseLegacyWordDocument(
        storyWordFixture(main: '\x13 REF A\x14B\x14C\x15\r'),
      ),
      throwsFormatException,
    );
  });
  test('rejects a bookmark spanning unrelated subdocuments', () {
    const note = '\x02N\r';
    expect(
      () => parseLegacyWordDocument(
        storyWordFixture(
          main: 'A\x02\r',
          footnotes: '$note\r',
          tablePairs: {
            2: storyPlc([1, 0xffffffff], wordU16(1)),
            3: storyPlc([0, note.length, 0xffffffff]),
            21: storyBookmarkNames(['Bad']),
            22: storyPlc([0, 0xffffffff], [...wordU16(0), ...wordU16(0)]),
            23: storyPlc([5, 0xffffffff]),
          },
        ),
      ),
      throwsFormatException,
    );
  });
}
