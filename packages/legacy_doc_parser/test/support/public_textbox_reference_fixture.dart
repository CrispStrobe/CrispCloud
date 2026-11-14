// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

const publicTextboxInvalidCases = [
  'duplicate-story',
  'duplicate-story-unplaced',
  'duplicate-drawing',
  'zero-id',
  'negative-id',
  'wrong-story-kind',
  'zero-length',
  'excessive-length',
  'count-mismatch',
  'gap-index',
  'duplicate-index',
  'negative-index',
  'wrong-first-shape',
  'wrong-first-anchor',
  'wrong-next-shape',
  'cycle',
  'duplicate-anchor',
  'wrong-drawing-id',
  'wrong-drawing-index',
  'wrong-drawing-next',
  'invalid-recovery-length',
  'unproved-recovery',
  'single-wrong-first-shape',
  'single-wrong-first-anchor',
  'single-header-in-main',
  'single-header-in-footnote',
  'single-body-in-header',
  'single-body-in-textbox',
  'chain-body-in-header',
];

const publicTextboxHiddenInvalidCases = [
  'wrong-drawing-id',
  'wrong-drawing-index',
  'wrong-drawing-next',
  'single-wrong-first-shape',
  'single-wrong-first-anchor',
  'single-header-in-main',
  'single-header-in-footnote',
  'single-body-in-header',
  'chain-body-in-header',
];

const publicTextboxValidCases = [
  'single',
  'single-without-client',
  'chain',
  'chain-reversed',
  'chain-null-links',
  'chain-zero-links',
  'recovered-chain',
  'unresolved-chain',
  'two-stories',
  'two-stories-reversed',
  'single-header',
  'single-footer',
  'single-footnoteSeparator',
  'single-footnoteContinuationSeparator',
  'single-footnoteContinuationNotice',
  'single-endnoteSeparator',
  'single-endnoteContinuationSeparator',
  'single-endnoteContinuationNotice',
];

String publicTextboxOutputPart(String mutation) {
  if (mutation == 'single-header') return 'word/header1.xml';
  if (mutation == 'single-footer') return 'word/footer1.xml';
  if (mutation.startsWith('single-footnote')) return 'word/footnotes.xml';
  if (mutation.startsWith('single-endnote')) return 'word/endnotes.xml';
  return 'word/document.xml';
}

LegacyWordDocument publicTextboxReferenceDocument(
  String mutation, {
  bool hidden = false,
}) {
  final ownerKind = switch (mutation) {
    'single-header' ||
    'single-body-in-header' ||
    'chain-body-in-header' => LegacyWordStoryKind.header,
    'single-footer' => LegacyWordStoryKind.footer,
    'single-header-in-footnote' => LegacyWordStoryKind.footnote,
    'single-footnoteSeparator' => LegacyWordStoryKind.footnoteSeparator,
    'single-footnoteContinuationSeparator' =>
      LegacyWordStoryKind.footnoteContinuationSeparator,
    'single-footnoteContinuationNotice' =>
      LegacyWordStoryKind.footnoteContinuationNotice,
    'single-endnoteSeparator' => LegacyWordStoryKind.endnoteSeparator,
    'single-endnoteContinuationSeparator' =>
      LegacyWordStoryKind.endnoteContinuationSeparator,
    'single-endnoteContinuationNotice' =>
      LegacyWordStoryKind.endnoteContinuationNotice,
    _ => null,
  };
  final inHeaderFooter =
      mutation.startsWith('single-header') ||
      mutation == 'single-footer' ||
      mutation.startsWith('single-footnote') ||
      mutation.startsWith('single-endnote');
  final firstCp = mutation == 'single-body-in-textbox'
      ? 101
      : ownerKind != null && mutation != 'chain-body-in-header'
      ? 201
      : 1;
  final secondCp = mutation == 'chain-body-in-header' ? 201 : 3;
  final noteOwner =
      mutation.startsWith('single-footnote') ||
      mutation.startsWith('single-endnote');
  final endnote = mutation.startsWith('single-endnote');
  final twoReferences =
      mutation.startsWith('duplicate-') &&
          mutation != 'duplicate-index' &&
          mutation != 'duplicate-anchor' ||
      mutation.startsWith('two-stories');
  final sameStory = mutation.startsWith('duplicate-story');
  final sameDrawing = mutation == 'duplicate-drawing';
  final single =
      mutation.startsWith('single') ||
      twoReferences ||
      const [
        'zero-id',
        'negative-id',
        'wrong-story-kind',
        'zero-length',
        'excessive-length',
      ].contains(mutation);
  var chainLength = single ? 1 : 2;
  if (mutation == 'zero-length') chainLength = 0;
  if (mutation == 'excessive-length') chainLength = 4097;
  if (mutation == 'count-mismatch') chainLength = 3;
  final firstId = mutation == 'zero-id'
      ? 0
      : mutation == 'negative-id'
      ? -1
      : 1;
  final firstIndex = mutation == 'negative-index' ? -1 : 0;
  final secondIndex = mutation == 'gap-index'
      ? 2
      : mutation == 'duplicate-index'
      ? 0
      : 1;
  final int? firstNext = switch (mutation) {
    'chain-null-links' || 'unproved-recovery' => null,
    'chain-zero-links' => 0,
    'wrong-next-shape' => 99,
    _ => single ? null : 43,
  };
  final int? secondNext = mutation == 'cycle'
      ? 42
      : mutation == 'chain-zero-links'
      ? 0
      : null;
  final anchors = <LegacyWordTextboxAnchor>[
    LegacyWordTextboxAnchor(
      shapeId: 42,
      anchorCp: firstCp,
      chainIndex: firstIndex,
      nextShapeId: firstNext,
    ),
    if (!single)
      LegacyWordTextboxAnchor(
        shapeId: mutation == 'duplicate-anchor' ? 42 : 43,
        anchorCp: mutation == 'duplicate-anchor' ? firstCp : secondCp,
        chainIndex: secondIndex,
        nextShapeId: secondNext,
      ),
  ];
  final first = LegacyWordTextboxReference(
    id: firstId,
    storyId: 'box-1',
    inHeaderFooter: inHeaderFooter,
    shapeId: mutation == 'single-wrong-first-shape'
        ? 99
        : mutation == 'wrong-first-shape'
        ? 43
        : 42,
    anchorCp: mutation == 'duplicate-story-unplaced'
        ? 50
        : mutation == 'wrong-first-anchor' ||
              mutation == 'single-wrong-first-anchor'
        ? 2
        : mutation == 'wrong-first-shape'
        ? 3
        : firstCp,
    chainLength: chainLength,
    declaredChainLength: mutation == 'invalid-recovery-length'
        ? 2
        : const ['recovered-chain', 'unproved-recovery'].contains(mutation)
        ? 1
        : null,
    anchors: mutation == 'unresolved-chain' || single
        ? const []
        : mutation == 'chain-reversed'
        ? anchors.reversed.toList()
        : anchors,
  );
  final second = LegacyWordTextboxReference(
    id: 2,
    storyId: sameStory ? 'box-1' : 'box-2',
    inHeaderFooter: false,
    shapeId: sameDrawing ? 42 : 43,
    anchorCp: sameDrawing ? 1 : 3,
  );
  LegacyWordParagraph paragraph(int cp, String text) => LegacyWordParagraph(
    startCp: cp,
    endCp: cp + text.length + 1,
    runs: [LegacyWordRun(startCp: cp, endCp: cp + text.length, text: text)],
  );
  LegacyWordParagraph hiddenParagraph(int cp) => LegacyWordParagraph(
    startCp: cp,
    endCp: cp + 10,
    runs: [LegacyWordRun(startCp: cp + 7, endCp: cp + 8, text: '1')],
  );
  LegacyWordField field(int cp, String storyId) => LegacyWordField(
    id: cp,
    storyId: storyId,
    startCp: cp,
    separatorCp: cp + 6,
    endCp: cp + 9,
    instruction: ' PAGE',
    storedResult: '1',
    type: 'PAGE',
  );
  LegacyWordDrawing drawing(int shapeId, int cp, int index, int storyId) =>
      LegacyWordDrawing(
        shapeId: shapeId,
        anchorCp: cp,
        headerStory: inHeaderFooter,
        leftTwips: index * 1440,
        topTwips: 0,
        rightTwips: (index + 1) * 1440,
        bottomTwips: 720,
        horizontalOrigin: 0,
        verticalOrigin: 0,
        wrapMode: 3,
        wrapSide: 0,
        behindText: false,
        anchorLocked: false,
        textboxId:
            mutation == 'single-without-client' ||
                sameDrawing ||
                mutation == 'unresolved-chain'
            ? null
            : ((mutation == 'wrong-drawing-id' && index == 1 ? 9 : storyId) <<
                      16) |
                  (mutation == 'wrong-drawing-index' && index == 1 ? 2 : index),
        nextTextboxShapeId: mutation == 'wrong-drawing-next' && index == 1
            ? 42
            : single || mutation == 'unresolved-chain'
            ? null
            : index == 0
            ? firstNext
            : secondNext,
        source: const LegacyWordSourceReference(
          streamPath: '0Table',
          offset: 0,
          length: 26,
          structure: 'FSPA',
        ),
      );
  return LegacyWordDocument(
    blocks: [hidden ? hiddenParagraph(0) : paragraph(0, 'ABCD')],
    sections: const [],
    plainText: 'ABCD',
    safeHtml: '',
    stories: [
      LegacyWordStory(
        id: 'box-1',
        kind: mutation == 'wrong-story-kind' || inHeaderFooter
            ? LegacyWordStoryKind.headerTextbox
            : LegacyWordStoryKind.textbox,
        startCp: 100,
        endCp: 104,
        blocks: [paragraph(100, 'One')],
        plainText: 'One',
        safeHtml: '',
      ),
      if (twoReferences && !sameStory)
        LegacyWordStory(
          id: 'box-2',
          kind: LegacyWordStoryKind.textbox,
          startCp: 200,
          endCp: 204,
          blocks: [paragraph(200, 'Two')],
          plainText: 'Two',
          safeHtml: '',
        ),
      if (ownerKind != null)
        LegacyWordStory(
          id: 'owner',
          kind: ownerKind,
          startCp: 200,
          endCp: hidden ? 210 : 205,
          blocks: [hidden ? hiddenParagraph(200) : paragraph(200, 'HOST')],
          plainText: hidden ? '1' : 'HOST',
          safeHtml: '',
          headerFooterType:
              ownerKind == LegacyWordStoryKind.header ||
                  ownerKind == LegacyWordStoryKind.footer
              ? LegacyWordHeaderFooterType.normal
              : null,
        ),
      if (noteOwner)
        LegacyWordStory(
          id: 'note',
          kind: endnote
              ? LegacyWordStoryKind.endnote
              : LegacyWordStoryKind.footnote,
          startCp: 300,
          endCp: 305,
          blocks: [paragraph(300, 'Note')],
          plainText: 'Note',
          safeHtml: '',
        ),
    ],
    fields: [
      if (hidden) field(0, 'main'),
      if (hidden && ownerKind != null) field(200, 'owner'),
    ],
    noteReferences: [
      if (noteOwner)
        LegacyWordNoteReference(
          id: 1,
          anchorCp: hidden ? 7 : 0,
          storyId: 'note',
          endnote: endnote,
        ),
    ],
    textboxReferences: [
      if (mutation == 'two-stories-reversed') second,
      first,
      if (twoReferences && mutation != 'two-stories-reversed') second,
    ],
    media: LegacyWordMediaCatalog.from(
      drawings: [
        drawing(42, firstCp, 0, 1),
        if ((!single || twoReferences) &&
            !sameDrawing &&
            mutation != 'unresolved-chain')
          drawing(43, secondCp, twoReferences ? 0 : 1, twoReferences ? 2 : 1),
      ],
    ),
  );
}
