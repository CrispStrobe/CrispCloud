// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

const publicBookmarkInvalidCases = [
  'empty-name',
  'long-name',
  'invalid-unicode-name',
  'control-name',
  'negative-start',
  'reversed-range',
  'end-overrun',
  'cross-story',
  'gap-point',
  'missing-first-column',
  'missing-last-column',
  'negative-first-column',
  'negative-last-column',
  'reversed-columns',
  'column-overflow',
  'duplicate-name',
  'duplicate-name-hidden-last',
];

const publicBookmarkValidCases = [
  'valid',
  'maximum-name',
  'international-name',
  'point-start',
  'point-end',
  'full-range',
  'first-column',
  'last-column',
  'auxiliary',
  'adjacent-header-point',
  'adjacent-header-range',
  'adjacent-footnote-point',
  'adjacent-footnote-range',
  'adjacent-comment-point',
  'adjacent-comment-range',
  'auxiliary-end',
  'adjacent-footnote-end',
  'shared-auxiliary-point',
];

String publicBookmarkOutputPart(String mutation) {
  if (mutation == 'auxiliary' || mutation == 'auxiliary-end') {
    return 'word/header1.xml';
  }
  if (mutation == 'shared-auxiliary-point') return 'word/footer1.xml';
  if (mutation.startsWith('adjacent-') && !mutation.endsWith('-point')) {
    if (mutation.contains('-header-')) return 'word/header1.xml';
    if (mutation.contains('-footnote-')) return 'word/footnotes.xml';
    return 'word/comments.xml';
  }
  return 'word/document.xml';
}

LegacyWordDocument publicBookmarkDocument(
  String mutation, {
  bool hidden = false,
}) {
  if (mutation.startsWith('adjacent-')) {
    final kind = mutation.contains('-header-')
        ? LegacyWordStoryKind.header
        : mutation.contains('-footnote-')
        ? LegacyWordStoryKind.footnote
        : LegacyWordStoryKind.comment;
    return LegacyWordDocument(
      blocks: const [
        LegacyWordParagraph(
          startCp: 0,
          endCp: 2,
          runs: [LegacyWordRun(startCp: 0, endCp: 1, text: 'A')],
        ),
      ],
      sections: const [],
      plainText: 'A',
      safeHtml: '',
      stories: [
        LegacyWordStory(
          id: 'adjacent',
          kind: kind,
          startCp: 2,
          endCp: 4,
          blocks: const [
            LegacyWordParagraph(
              startCp: 2,
              endCp: 4,
              runs: [LegacyWordRun(startCp: 2, endCp: 3, text: 'N')],
            ),
          ],
          plainText: 'N',
          safeHtml: '',
          headerFooterType: kind == LegacyWordStoryKind.header
              ? LegacyWordHeaderFooterType.normal
              : null,
        ),
      ],
      noteReferences: [
        if (kind == LegacyWordStoryKind.footnote)
          const LegacyWordNoteReference(
            id: 1,
            anchorCp: 0,
            storyId: 'adjacent',
            endnote: false,
          ),
      ],
      commentReferences: [
        if (kind == LegacyWordStoryKind.comment)
          const LegacyWordCommentReference(
            id: 1,
            anchorCp: 0,
            storyId: 'adjacent',
          ),
      ],
      bookmarks: [
        LegacyWordBookmark(
          name: 'Boundary',
          startCp: mutation.endsWith('-end') ? 4 : 2,
          endCp: mutation.endsWith('-end')
              ? 4
              : mutation.endsWith('-point')
              ? 2
              : 3,
        ),
      ],
    );
  }
  var start = hidden ? 2 : 7, end = hidden ? 3 : 8;
  var name = 'mark';
  int? first, last;
  switch (mutation) {
    case 'empty-name':
      name = '';
    case 'long-name':
      name = 'A' * 41;
    case 'invalid-unicode-name':
      name = 'A\uD800';
    case 'control-name':
      name = 'A\u0000';
    case 'negative-start':
      start = -1;
    case 'reversed-range':
      end = start - 1;
    case 'end-overrun':
      end = 1000;
    case 'cross-story':
      end = 102;
    case 'gap-point':
      start = end = 50;
    case 'missing-first-column':
      last = 0;
    case 'missing-last-column':
      first = 0;
    case 'negative-first-column':
      first = -1;
      last = 0;
    case 'negative-last-column':
      first = 0;
      last = -1;
    case 'reversed-columns':
      first = 2;
      last = 1;
    case 'column-overflow':
      first = 0;
      last = 63;
    case 'maximum-name':
      name = 'A' * 40;
    case 'international-name':
      name = '版本_Δοκιμή_ёж';
    case 'point-start':
      start = end = 0;
    case 'point-end':
      start = end = 10;
    case 'full-range':
      start = 0;
      end = 10;
    case 'first-column':
      first = last = 0;
    case 'last-column':
      first = last = 62;
    case 'auxiliary':
      start = 100;
      end = 104;
    case 'auxiliary-end' || 'shared-auxiliary-point':
      start = end = 104;
  }
  final bookmark = LegacyWordBookmark(
    name: name,
    startCp: start,
    endCp: end,
    firstCell: first,
    lastCell: last,
  );
  const duplicate = LegacyWordBookmark(name: 'mark', startCp: 7, endCp: 8);
  return LegacyWordDocument(
    blocks: const [
      LegacyWordParagraph(
        startCp: 0,
        endCp: 10,
        runs: [LegacyWordRun(startCp: 7, endCp: 8, text: '1')],
      ),
    ],
    sections: const [],
    plainText: '1',
    safeHtml: '',
    fields: const [
      LegacyWordField(
        id: 1,
        storyId: 'main',
        startCp: 0,
        separatorCp: 6,
        endCp: 9,
        instruction: ' PAGE',
        storedResult: '1',
        type: 'PAGE',
      ),
    ],
    stories: [
      const LegacyWordStory(
        id: 'header',
        kind: LegacyWordStoryKind.header,
        startCp: 100,
        endCp: 104,
        blocks: [
          LegacyWordParagraph(
            startCp: 100,
            endCp: 104,
            runs: [LegacyWordRun(startCp: 100, endCp: 103, text: 'Hdr')],
          ),
        ],
        plainText: 'Hdr',
        safeHtml: '',
        headerFooterType: LegacyWordHeaderFooterType.normal,
      ),
      if (mutation == 'shared-auxiliary-point')
        const LegacyWordStory(
          id: 'footer',
          kind: LegacyWordStoryKind.footer,
          startCp: 104,
          endCp: 108,
          blocks: [
            LegacyWordParagraph(
              startCp: 104,
              endCp: 108,
              runs: [LegacyWordRun(startCp: 104, endCp: 107, text: 'Ftr')],
            ),
          ],
          plainText: 'Ftr',
          safeHtml: '',
          headerFooterType: LegacyWordHeaderFooterType.normal,
        ),
    ],
    bookmarks: [
      if (mutation == 'duplicate-name-hidden-last') duplicate,
      bookmark,
      if (mutation == 'duplicate-name') duplicate,
    ],
  );
}
