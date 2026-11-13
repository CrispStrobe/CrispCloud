import 'dart:io';
import 'dart:ui';

import 'package:crisp_cloud/l10n/legacy_word_preview_strings.dart';
import 'package:crisp_cloud/l10n/office_preview_strings.dart';
import 'package:crisp_cloud/services/legacy_word_preview.dart';
import 'package:crisp_cloud/services/locale_preference.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../packages/legacy_doc_parser/test/support/story_word_fixture.dart';
import '../packages/legacy_doc_parser/test/support/structured_word_fixture.dart';

LegacyWordStory _story(
  String id,
  LegacyWordStoryKind kind,
  int cp, {
  String text = 'Stored content',
  String html = '<p>Stored content</p>',
  int? section,
  LegacyWordHeaderFooterType? variant,
}) => LegacyWordStory(
  id: id,
  kind: kind,
  startCp: cp,
  endCp: cp + text.length,
  blocks: const [],
  plainText: text,
  safeHtml: html,
  sectionIndex: section,
  headerFooterType: variant,
);

LegacyWordDocument _document({
  String text = 'Body',
  String html = '<p>Body</p>',
  List<LegacyWordStory> stories = const [],
  List<LegacyWordNoteReference> notes = const [],
  List<LegacyWordCommentReference> comments = const [],
  List<LegacyWordTextboxReference> textboxes = const [],
  LegacyWordMediaCatalog media = const LegacyWordMediaCatalog(),
}) => LegacyWordDocument(
  blocks: const [],
  sections: const [],
  plainText: text,
  safeHtml: html,
  stories: stories,
  noteReferences: notes,
  commentReferences: comments,
  textboxReferences: textboxes,
  media: media,
);

LegacyWordDrawing _drawing(
  int id,
  int cp, {
  bool hidden = false,
  bool deleted = false,
}) => LegacyWordDrawing(
  shapeId: id,
  anchorCp: cp,
  headerStory: false,
  leftTwips: 0,
  topTwips: 0,
  rightTwips: 100,
  bottomTwips: 100,
  horizontalOrigin: 0,
  verticalOrigin: 0,
  wrapMode: 0,
  wrapSide: 0,
  behindText: false,
  anchorLocked: false,
  source: const LegacyWordSourceReference(
    streamPath: '1Table',
    offset: 0,
    length: 26,
    structure: 'FSPA',
  ),
  presentation: LegacyWordMediaPresentation(hidden: hidden),
  shapeDeleted: deleted,
);

void main() {
  for (final deleted in [false, true]) {
    test(
      'hidden or deleted textbox shape without encoded ID remains invisible: $deleted',
      () {
        final preview = projectLegacyWordPreview(
          _document(
            stories: [
              _story(
                'box',
                LegacyWordStoryKind.textbox,
                50,
                text: 'PRIVATE BOX',
              ),
            ],
            textboxes: const [
              LegacyWordTextboxReference(
                id: 1,
                storyId: 'box',
                inHeaderFooter: false,
                shapeId: 42,
                anchorCp: 2,
              ),
            ],
            media: LegacyWordMediaCatalog.from(
              drawings: [
                _drawing(42, 2, hidden: !deleted, deleted: deleted),
                _drawing(43, 3),
              ],
            ),
          ),
        );
        expect(preview.stories, isEmpty);
        expect(preview.plainText, 'Body');
      },
    );
  }

  test('keeps CP order, shared occurrences, identities and page variants', () {
    final document = _document(
      stories: [
        _story('textbox-2', LegacyWordStoryKind.textbox, 50),
        _story(
          'header-1',
          LegacyWordStoryKind.header,
          20,
          section: 0,
          variant: LegacyWordHeaderFooterType.normal,
        ),
        _story(
          'header-2',
          LegacyWordStoryKind.header,
          20,
          section: 1,
          variant: LegacyWordHeaderFooterType.first,
        ),
        _story('note-1', LegacyWordStoryKind.footnote, 10),
      ],
    );
    final preview = projectLegacyWordPreview(document);
    expect(preview.stories.map((item) => item.id), [
      'note-1',
      'header-1',
      'header-2',
      'textbox-2',
    ]);
    expect(preview.stories.map((item) => item.startCp), [10, 20, 20, 50]);
    expect(preview.stories.map((item) => item.number), [1, 1, 2, 1]);
    expect(preview.plainText, startsWith('Body\n\nFootnote 1'));
    expect(preview.plainText, contains('Header 2 · Section 2 · First page'));
    expect(
      preview.safeHtml,
      contains('<h2>Header 1 · Section 1 · Default pages</h2>'),
    );
    expect(document.stories.first.id, 'textbox-2');
  });

  test(
    'no auxiliary content leaves main-only previews byte-for-byte unchanged',
    () {
      final document = _document();
      final preview = projectLegacyWordPreview(document);
      expect(preview.plainText, document.plainText);
      expect(preview.safeHtml, document.safeHtml);
      expect(preview.stories, isEmpty);
    },
  );

  test(
    'all story roles and generated headings localize without changing content',
    () {
      final document = _document(
        stories: [
          for (final kind in LegacyWordStoryKind.values)
            _story(
              kind.name,
              kind,
              10 + kind.index * 100,
              text: 'Text box 1 <script> & unchanged',
              html: '<p>Text box 1 &lt;script&gt; &amp; unchanged</p>',
              section: 0,
              variant: LegacyWordHeaderFooterType.even,
            ),
        ],
      );
      final preview = projectLegacyWordPreview(document);
      final english = LegacyWordPreviewStrings(const Locale('en'));
      for (final language in LocalePreference.supported) {
        final strings = LegacyWordPreviewStrings(Locale(language));
        final text = strings.text(preview);
        final html = strings.html(preview)!;
        expect(
          'Text box 1 <script> & unchanged'.allMatches(text),
          hasLength(LegacyWordStoryKind.values.length),
        );
        expect(html, isNot(contains('<script>')));
        expect(
          'Text box 1 &lt;script&gt; &amp; unchanged'.allMatches(html),
          hasLength(LegacyWordStoryKind.values.length),
        );
        for (final story in preview.stories) {
          expect(text, contains(strings.heading(story)));
          if (language != 'en') {
            expect(
              strings.heading(story),
              isNot(english.heading(story)),
              reason: '$language ${story.kind.name}',
            );
          }
        }
        expect(strings.searchLimit, isNotEmpty);
        expect(strings.searchedPreview, isNotEmpty);
        expect(strings.textLimit, isNotEmpty);
      }
    },
  );

  test(
    'hidden-only references stay hidden; one visible reference keeps a story',
    () {
      const hidden = LegacyWordMediaPresentation(hidden: true);
      final preview = projectLegacyWordPreview(
        _document(
          stories: [
            _story(
              'hidden-note',
              LegacyWordStoryKind.footnote,
              10,
              text: 'SECRET',
            ),
            _story(
              'hidden-comment',
              LegacyWordStoryKind.comment,
              30,
              text: 'PRIVATE',
            ),
            _story(
              'shared-note',
              LegacyWordStoryKind.footnote,
              50,
              text: 'Visible',
            ),
          ],
          notes: const [
            LegacyWordNoteReference(
              id: 1,
              anchorCp: 1,
              storyId: 'hidden-note',
              endnote: false,
              presentation: hidden,
            ),
            LegacyWordNoteReference(
              id: 2,
              anchorCp: 2,
              storyId: 'shared-note',
              endnote: false,
              presentation: hidden,
            ),
            LegacyWordNoteReference(
              id: 3,
              anchorCp: 3,
              storyId: 'shared-note',
              endnote: false,
            ),
          ],
          comments: const [
            LegacyWordCommentReference(
              id: 1,
              anchorCp: 2,
              storyId: 'hidden-comment',
              presentation: hidden,
            ),
          ],
        ),
      );
      expect(preview.stories.map((item) => item.id), ['shared-note']);
      expect(preview.plainText, contains('Visible'));
      expect(preview.plainText, isNot(contains('SECRET')));
      expect(preview.plainText, isNot(contains('PRIVATE')));
    },
  );

  test(
    'bounded projection rejects excess text and stories instead of truncating',
    () {
      final story = _story('note', LegacyWordStoryKind.footnote, 1);
      expect(
        () => projectLegacyWordPreview(
          _document(text: 'x' * (8 * 1024 * 1024), stories: [story]),
        ),
        throwsFormatException,
      );
      expect(
        () => projectLegacyWordPreview(
          _document(stories: List.filled(20001, story)),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'hidden comment parents suppress replies transitively in any source order',
    () {
      final preview = projectLegacyWordPreview(
        _document(
          stories: [
            _story(
              'parent',
              LegacyWordStoryKind.comment,
              10,
              text: 'PRIVATE PARENT',
            ),
            _story(
              'reply',
              LegacyWordStoryKind.comment,
              30,
              text: 'PRIVATE REPLY',
            ),
            _story(
              'nested',
              LegacyWordStoryKind.comment,
              50,
              text: 'PRIVATE NESTED',
            ),
            _story(
              'independent',
              LegacyWordStoryKind.comment,
              70,
              text: 'Public comment',
            ),
          ],
          comments: const [
            LegacyWordCommentReference(
              id: 3,
              anchorCp: 3,
              storyId: 'nested',
              parentId: 2,
            ),
            LegacyWordCommentReference(
              id: 2,
              anchorCp: 2,
              storyId: 'reply',
              parentId: 1,
            ),
            LegacyWordCommentReference(
              id: 1,
              anchorCp: 1,
              storyId: 'parent',
              presentation: LegacyWordMediaPresentation(hidden: true),
            ),
            LegacyWordCommentReference(
              id: 4,
              anchorCp: 4,
              storyId: 'independent',
            ),
          ],
        ),
      );
      expect(preview.stories.map((item) => item.id), ['independent']);
      expect(preview.plainText, contains('Public comment'));
      expect(preview.plainText, isNot(contains('PRIVATE')));
    },
  );

  test(
    'large markup falls back to complete extracted text without composing it',
    () {
      final preview = projectLegacyWordPreview(
        _document(
          html: 'x' * (4 * 1024 * 1024),
          stories: [
            _story(
              'last-note',
              LegacyWordStoryKind.endnote,
              10,
              text: 'Last note',
            ),
          ],
        ),
      );
      expect(preview.safeHtml, isNull);
      expect(preview.htmlHeadings, isEmpty);
      expect(preview.plainText, endsWith('Last note'));
      expect(preview.stories.single.id, 'last-note');
    },
  );

  test(
    'DOC and DOT include real parsed headers, footers, notes and comments',
    () async {
      const main = 'Body\x02 and\x02 comment\x05\r';
      const footnote = '\x02Foot content\r', endnote = '\x02End content\r';
      const comment = '\x05Comment content\r';
      const header = 'Header content\r\r', footer = 'Footer content\r\r';
      final bytes = storyWordFixture(
        main: main,
        footnotes: '$footnote\r',
        headers: '$header$footer\r',
        comments: '$comment\r',
        endnotes: '$endnote\r',
        tablePairs: {
          2: storyPlc([main.indexOf('\x02'), 0xffffffff], wordU16(1)),
          3: storyPlc([0, footnote.length, 0xffffffff]),
          4: storyPlc([main.indexOf('\x05'), 0xffffffff], storyCommentRecord()),
          5: storyPlc([0, comment.length, 0xffffffff]),
          11: storyPlc([
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
            0xffffffff,
          ]),
          36: storyXst('Author'),
          46: storyPlc([main.lastIndexOf('\x02'), 0xffffffff], wordU16(1)),
          47: storyPlc([0, endnote.length, 0xffffffff]),
        },
      );
      final source = List<int>.from(bytes);
      for (final suffix in ['doc', 'DOT']) {
        final preview = await parseOfficeDocument(bytes, 'stories.$suffix');
        expect(preview.fallback, isNull);
        expect(preview.notice, OfficePreviewNotice.legacyWordStories);
        expect(preview.legacyWordPreview!.stories, hasLength(5));
        for (final content in [
          'Header content',
          'Footer content',
          'Foot content',
          'End content',
          'Comment content',
        ]) {
          expect(preview.plainText, contains(content));
          expect(preview.safeHtml, contains(content));
        }
        final strings = OfficePreviewStrings(const Locale('de'));
        expect(strings.text(preview), contains('Fußnote 1'));
        expect(strings.safeHtml(preview), contains('<h2>Fußnote 1</h2>'));
        expect(strings.note(preview), contains('Seitenpositionen'));
      }
      expect(bytes, orderedEquals(source));
    },
  );

  test(
    'private-field note and comment bodies do not leak through the adapter',
    () async {
      const main = 'A\x13 REF Name\x14\x02\x05Secret\x15B\r';
      const note = '\x02Hidden note\r', comment = '\x05Hidden comment\r';
      final preview = await parseOfficeDocument(
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
            36: storyXst('Author'),
            16: storyPlc(
              [
                main.indexOf('\x13'),
                main.indexOf('\x14'),
                main.indexOf('\x15'),
                0xffffffff,
              ],
              [0x13, 0, 0x14, 0, 0x15, 0xa0],
            ),
          },
        ),
        'private.doc',
      );
      expect(preview.fallback, isNull);
      expect(preview.plainText, 'AB');
      expect(preview.safeHtml, isNot(contains('Hidden')));
      expect(preview.legacyWordPreview!.stories, isEmpty);
    },
  );

  for (final fixture in [
    'linked-textboxes-extended.doc',
    'word14-margin-origin.doc',
  ]) {
    test(
      'native fixture $fixture retains every recovered textbox in DOC/DOT preview',
      () async {
        final bytes = File(
          'packages/legacy_doc_parser/test/fixtures/word_native/$fixture',
        ).readAsBytesSync();
        final document = parseLegacyWordDocument(bytes);
        final stories = document.stories
            .where((story) => story.kind == LegacyWordStoryKind.textbox)
            .toList();
        expect(stories, isNotEmpty);
        for (final name in [fixture, 'template.dot']) {
          final preview = await parseOfficeDocument(bytes, name);
          expect(preview.fallback, isNull);
          expect(preview.notice, OfficePreviewNotice.legacyWordStories);
          for (final story in stories) {
            expect(preview.plainText, contains(story.plainText));
            expect(preview.safeHtml, contains(story.safeHtml));
            expect(
              preview.legacyWordPreview!.stories.map((item) => item.id),
              contains(story.id),
            );
          }
          expect(
            preview.plainText.length,
            greaterThan(document.plainText.length),
          );
        }
      },
    );
  }
}
