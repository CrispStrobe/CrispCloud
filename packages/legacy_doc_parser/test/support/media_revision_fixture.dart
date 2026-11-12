// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'media_word_fixture.dart';
import 'officeart_shape_fixture.dart';
import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';

// Independently authored MS-DOC 2.6.1 character records. Dates deliberately
// differ, and no time zone is invented for these wall-clock DTTM values.
const mediaInsertionDttm =
    45 | (8 << 6) | (12 << 11) | (11 << 16) | (126 << 20);
const mediaDeletionDttm = 15 | (9 << 6) | (13 << 11) | (11 << 16) | (126 << 20);

List<int> mediaReviewAuthors() => [
  ...wordU16(0xffff),
  ...wordU16(3),
  ...wordU16(0),
  for (final name in ['Unknown', 'Alice', 'Bob']) ...[
    ...wordU16(name.length),
    for (final unit in name.codeUnits) ...wordU16(unit),
  ],
];

List<int> mediaReviewProperties({
  bool inserted = true,
  bool deleted = true,
  bool hidden = false,
  bool insertionMetadata = true,
  int insertionAuthor = 1,
  int insertionDate = mediaInsertionDttm,
}) => [
  ...wordSprm(0x0801, [inserted ? 1 : 0]),
  ...wordSprm(0x0800, [deleted ? 1 : 0]),
  ...wordSprm(0x083c, [hidden ? 1 : 0]),
  if (insertionMetadata) ...[
    ...wordSprm(0x4804, wordU16(insertionAuthor)),
    ...wordSprm(0x6805, wordU32(insertionDate)),
    ...wordSprm(0x6816, wordU32(0x10203040)),
    ...wordSprm(0x4807, wordU16(7)),
  ],
  ...wordSprm(0x4863, wordU16(2)),
  ...wordSprm(0x6864, wordU32(mediaDeletionDttm)),
  ...wordSprm(0x6817, wordU32(0x50607080)),
  ...wordSprm(0x4867, wordU16(9)),
];

const mediaReviewKinds = [
  'inline-picture',
  'floating-picture',
  'embedded-object',
  'editable-shape',
  'footnote-picture',
  'footnote-anchor',
  'endnote-anchor',
  'comment-anchor',
];

Uint8List mediaReviewFixture(
  String kind, {
  bool inserted = true,
  bool deleted = true,
  List<int>? properties,
}) {
  final props =
      properties ?? mediaReviewProperties(inserted: inserted, deleted: deleted);
  final authors = {51: mediaReviewAuthors()};
  switch (kind) {
    case 'inline-picture':
      return inlinePictureWordFixture(
        characterProperties: props,
        extraTablePairs: authors,
      );
    case 'floating-picture':
      return floatingPictureWordFixture(
        characterProperties: props,
        extraTablePairs: authors,
      );
    case 'embedded-object':
      return oleWordFixture(
        characterProperties: props,
        extraTablePairs: authors,
      );
    case 'editable-shape':
      return officeArtShapeWordFixture(
        characterProperties: props,
        extraTablePairs: authors,
      );
    case 'footnote-picture':
      const note = '\x02P\x01Q\r';
      return StructuredWordFixture(
        pieces: const [
          WordFixturePiece('A\x02B\r', offset: 16384, compressed: false),
          WordFixturePiece('$note\r', offset: 8192, compressed: false),
        ],
        mainCharacterCount: 4,
        storyCounts: {4: note.length + 1},
        characterRuns: [
          const WordFixtureFkpRun(8192, 8196),
          WordFixtureFkpRun(
            8196,
            8198,
            properties: [
              ...wordSprm(0x0855, [1]),
              ...wordSprm(0x6a03, wordU32(16)),
              ...props,
            ],
          ),
          const WordFixtureFkpRun(8198, 28672),
        ],
        paragraphRuns: const [WordFixtureFkpRun(8192, 28672)],
        extraTablePairs: {
          ...authors,
          2: storyPlc([1, 0xffffffff], wordU16(1)),
          3: storyPlc([0, note.length, 0xffffffff]),
        },
        extraStreams: {
          'Data': Uint8List.fromList([
            ...List.filled(16, 0),
            ...inlinePictureData(),
          ]),
        },
      ).build();
    case 'footnote-anchor':
    case 'endnote-anchor':
    case 'comment-anchor':
      final comment = kind == 'comment-anchor';
      final endnote = kind == 'endnote-anchor';
      final marker = comment ? '\x05' : '\x02';
      final note = '${marker}Original story\r';
      return storyWordFixture(
        main: 'A${marker}B\r',
        footnotes: !comment && !endnote ? '$note\r' : '',
        endnotes: endnote ? '$note\r' : '',
        comments: comment ? '$note\r' : '',
        tablePairs: {
          ...authors,
          if (comment) ...{
            4: storyPlc([1, 0xffffffff], storyCommentRecord()),
            5: storyPlc([0, note.length, 0xffffffff]),
            36: storyXst('Comment Author'),
          } else ...{
            endnote ? 46 : 2: storyPlc([1, 0xffffffff], wordU16(1)),
            endnote ? 47 : 3: storyPlc([0, note.length, 0xffffffff]),
          },
        },
        characterRuns: [
          const WordFixtureFkpRun(8192, 16386),
          WordFixtureFkpRun(16386, 16388, properties: props),
          const WordFixtureFkpRun(16388, 28672),
        ],
      );
    default:
      throw ArgumentError.value(kind, 'kind');
  }
}
