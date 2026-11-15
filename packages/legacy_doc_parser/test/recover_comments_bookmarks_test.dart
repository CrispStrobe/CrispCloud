// SPDX-License-Identifier: MPL-2.0
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';

// With `recover`, comments or bookmarks whose tables contradict the text
// cost only those features (declared), not the whole document.
void main() {
  final longName = 'B' * 41; // Word's limit is 40.

  test('an over-long bookmark name drops only the bookmarks', () {
    final bytes = storyWordFixture(
      main: 'Body text\r',
      tablePairs: {
        21: storyBookmarkNames([longName]),
        22: storyPlc([0, 0xffffffff], [...wordU16(0), ...wordU16(0)]),
        23: storyPlc([4, 0xffffffff]),
      },
    );
    expect(
      () => parseLegacyWordDocument(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('bookmark name length'),
        ),
      ),
    );
    final document = parseLegacyWordDocument(bytes, recover: true);
    expect(document.plainText, contains('Body text'));
    expect(document.bookmarks, isEmpty);
    expect(document.warnings, contains(LegacyWordWarning.bookmarksOmitted));
    final conversion = convertLegacyWordDocument(document);
    expect(
      conversion.limitations,
      contains(LegacyWordConversionLimitation.fieldsLists),
    );
  });

  test('comment references that miss their markers drop only comments', () {
    // The reference points at 'A' (offset 0) instead of the \x05 marker.
    const main = 'A\x05B\r';
    const comment = '\x05Note\r';
    final bytes = storyWordFixture(
      main: main,
      comments: '$comment\r',
      tablePairs: {
        4: storyPlc([0, 0xffffffff], storyCommentRecord()),
        5: storyPlc([0, comment.length, 0xffffffff]),
        36: storyXst('Alice'),
      },
    );
    expect(
      () => parseLegacyWordDocument(bytes),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('comment markers'),
        ),
      ),
    );
    final document = parseLegacyWordDocument(bytes, recover: true);
    expect(document.plainText, contains('A'));
    expect(document.plainText, contains('B'));
    expect(document.commentReferences, isEmpty);
    expect(
      document.stories.where((s) => s.kind == LegacyWordStoryKind.comment),
      isEmpty,
    );
    expect(document.warnings, contains(LegacyWordWarning.commentsOmitted));
    convertLegacyWordDocument(document);
  });
}
