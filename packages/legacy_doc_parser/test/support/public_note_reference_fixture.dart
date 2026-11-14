// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

const publicNoteInvalidCases = [
  'shared-story',
  'shared-story-hidden-first',
  'shared-story-hidden-second',
  'duplicate-id-hidden-first',
  'duplicate-id-hidden-second',
  'hidden-negative-anchor',
  'hidden-end-anchor',
  'hidden-gap-anchor',
];

LegacyWordDocument publicNoteReferenceDocument(String mutation, bool endnote) {
  const visible = LegacyWordMediaPresentation();
  const hidden = LegacyWordMediaPresentation(hidden: true);
  final firstHidden = mutation.endsWith('hidden-first');
  final secondHidden = mutation.endsWith('hidden-second');
  final sharedStory = mutation.startsWith('shared-story');
  final duplicateId = mutation.startsWith('duplicate-id');
  final oneHidden = mutation.startsWith('hidden-');
  final first = LegacyWordNoteReference(
    id: 1,
    anchorCp: switch (mutation) {
      'hidden-negative-anchor' => -1,
      'hidden-end-anchor' => 9,
      'hidden-gap-anchor' => 50,
      _ => 1,
    },
    storyId: 'note-1',
    endnote: endnote,
    presentation: firstHidden || oneHidden ? hidden : visible,
  );
  final second = LegacyWordNoteReference(
    id: duplicateId ? 1 : 2,
    anchorCp: 4,
    storyId: sharedStory ? 'note-1' : 'note-2',
    endnote: endnote,
    presentation: secondHidden || mutation == 'one-hidden' ? hidden : visible,
  );
  LegacyWordParagraph paragraph(int cp, String text) => LegacyWordParagraph(
    startCp: cp,
    endCp: cp + text.length + 1,
    runs: [LegacyWordRun(startCp: cp, endCp: cp + text.length, text: text)],
  );
  return LegacyWordDocument(
    blocks: [paragraph(0, 'BodyText')],
    sections: const [],
    plainText: 'BodyText',
    safeHtml: '',
    stories: [
      for (var index = 1; index <= 2; index++)
        LegacyWordStory(
          id: 'note-$index',
          kind: endnote
              ? LegacyWordStoryKind.endnote
              : LegacyWordStoryKind.footnote,
          startCp: index * 100,
          endCp: index * 100 + 6,
          blocks: [paragraph(index * 100, 'Note$index')],
          plainText: 'Note$index',
          safeHtml: '',
        ),
    ],
    noteReferences: [
      if (mutation == 'reverse') ...[
        second,
        first,
      ] else ...[
        first,
        if (!oneHidden) second,
      ],
    ],
  );
}
