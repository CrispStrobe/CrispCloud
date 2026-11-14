// SPDX-License-Identifier: MPL-2.0

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

const cachedStructureScopes = [
  'body',
  'table',
  'list',
  'header',
  'footer',
  'footnote',
  'endnote',
  'comment',
  'textbox',
  'header-textbox',
  'coincident',
];
const cachedStructureRevisions = ['ordinary', 'inserted', 'deleted', 'both'];

LegacyWordDocument cachedStructureDocument(
  String scope,
  String revision, {
  bool privateResult = false,
  String? contradictoryRun,
}) {
  final auxiliary = !const [
    'body',
    'table',
    'list',
    'coincident',
  ].contains(scope);
  final headerTextbox = scope == 'header-textbox';
  final textbox = scope == 'textbox' || headerTextbox;
  final base = auxiliary
      ? headerTextbox
            ? 200
            : 100
      : 0;
  final storyId = auxiliary ? 'field-$scope' : 'main';
  final coincident = scope == 'coincident';
  final source =
      'A\x13 QUOTE "stored" \x14${coincident ? '\x02' : ''}Cache\x15Z\r';
  final separator = base + source.indexOf('\x14');
  final cacheStart = separator + 1 + (coincident ? 1 : 0);
  final fieldEnd = base + source.indexOf('\x15') + 1;
  final inserted = revision == 'inserted' || revision == 'both';
  final deleted = revision == 'deleted' || revision == 'both';
  final cache = LegacyWordRun(
    startCp: cacheStart,
    endCp: cacheStart + 5,
    text: 'Cache',
    style: const LegacyWordCharacterStyle(
      bold: true,
      italic: true,
      underline: true,
      underlineStyle: 'double',
      colorHex: '2468AC',
      fontName: 'Verdana',
      fontSizeHalfPoints: 28,
      spacingTwips: 5,
    ),
    inserted: inserted,
    deleted: deleted,
    insertionRevision: inserted
        ? LegacyWordRevisionInfo(
            author: 'Inserter',
            time: DateTime.utc(2001, 2, 3, 4, 5),
            saveId: 0x11111111,
          )
        : null,
    deletionRevision: deleted
        ? LegacyWordRevisionInfo(
            author: 'Deleter',
            time: DateTime.utc(2002, 3, 4, 5, 6),
            saveId: 0x22222222,
          )
        : null,
    formattingSaveId: 0x10203040,
    formattingRevision: const LegacyWordCharacterFormattingRevision(
      previousStyle: LegacyWordCharacterStyle(
        fontSizeHalfPoints: 22,
        colorHex: '993311',
      ),
      revision: LegacyWordRevisionInfo(author: 'Formatter'),
    ),
  );
  final paragraph = LegacyWordParagraph(
    startCp: base,
    endCp: base + source.length,
    runs: [
      LegacyWordRun(startCp: base, endCp: base + 1, text: 'A'),
      if (contradictoryRun == 'instruction')
        LegacyWordRun(startCp: base + 2, endCp: base + 3, text: 'X'),
      if (contradictoryRun == 'cross-instruction')
        LegacyWordRun(
          startCp: base + 1,
          endCp: separator + 1,
          text: 'X' * (separator - base),
        ),
      if (!privateResult) cache,
      if (contradictoryRun == 'private-result' ||
          contradictoryRun == 'hidden-private')
        LegacyWordRun(
          startCp: cacheStart,
          endCp: cacheStart + 5,
          text: 'LEAK!',
          style: LegacyWordCharacterStyle(
            hidden: contradictoryRun == 'hidden-private',
          ),
        ),
      if (contradictoryRun == 'empty-instruction')
        LegacyWordRun(startCp: base + 2, endCp: base + 2, text: ''),
      LegacyWordRun(startCp: fieldEnd, endCp: fieldEnd + 1, text: 'Z'),
    ]..sort((a, b) => a.startCp.compareTo(b.startCp)),
    style: LegacyWordParagraphStyle(
      alignment: LegacyWordAlignment.right,
      leftIndentTwips: 360,
      spaceBeforeTwips: 123,
      lineSpacingValue: -240,
      lineSpacingMultiple: true,
      listId: scope == 'list' ? 1 : null,
    ),
    mark: const LegacyWordParagraphMark(
      style: LegacyWordCharacterStyle(fontSizeHalfPoints: 30),
    ),
    formattingRevision: const LegacyWordParagraphFormattingRevision(
      previousStyle: LegacyWordParagraphStyle(
        spaceBeforeTwips: 12,
        leftIndentTwips: 720,
        lineSpacingValue: 480,
        lineSpacingMultiple: true,
      ),
      revision: LegacyWordRevisionInfo(author: 'ParagraphEditor'),
    ),
  );
  LegacyWordParagraph plain(int cp, String text) => LegacyWordParagraph(
    startCp: cp,
    endCp: cp + text.length + 1,
    runs: [LegacyWordRun(startCp: cp, endCp: cp + text.length, text: text)],
  );
  LegacyWordStory other(
    String id,
    LegacyWordStoryKind kind,
    int cp,
    String text,
  ) => LegacyWordStory(
    id: id,
    kind: kind,
    startCp: cp,
    endCp: cp + text.length + 1,
    blocks: [plain(cp, text)],
    plainText: text,
    safeHtml: '',
  );
  return LegacyWordDocument(
    blocks: auxiliary
        ? [plain(0, 'Body')]
        : scope == 'table'
        ? [
            LegacyWordTable(
              startCp: paragraph.startCp,
              endCp: paragraph.endCp,
              rows: [
                LegacyWordTableRow(
                  cells: [
                    LegacyWordTableCell(
                      paragraphs: [paragraph],
                      widthTwips: 4000,
                    ),
                  ],
                ),
              ],
            ),
          ]
        : [paragraph],
    sections: const [],
    plainText: auxiliary
        ? 'Body'
        : privateResult
        ? 'AZ'
        : 'ACacheZ',
    safeHtml: '',
    stories: [
      if (headerTextbox)
        other('host-header', LegacyWordStoryKind.header, 100, 'Head'),
      if (auxiliary)
        LegacyWordStory(
          id: storyId,
          kind: switch (scope) {
            'header' => LegacyWordStoryKind.header,
            'footer' => LegacyWordStoryKind.footer,
            'footnote' => LegacyWordStoryKind.footnote,
            'endnote' => LegacyWordStoryKind.endnote,
            'comment' => LegacyWordStoryKind.comment,
            'textbox' => LegacyWordStoryKind.textbox,
            'header-textbox' => LegacyWordStoryKind.headerTextbox,
            _ => throw StateError('Unknown cached fixture scope'),
          },
          startCp: base,
          endCp: base + source.length,
          blocks: [paragraph],
          plainText: privateResult ? 'AZ' : 'ACacheZ',
          safeHtml: '',
        ),
      if (coincident) ...[
        other('nested-note', LegacyWordStoryKind.footnote, 500, 'Note'),
        other('nested-comment', LegacyWordStoryKind.comment, 600, 'Comment'),
      ],
    ],
    fields: [
      LegacyWordField(
        id: 7,
        storyId: storyId,
        startCp: base + 1,
        separatorCp: separator,
        endCp: fieldEnd,
        instruction: ' QUOTE "stored" ',
        storedResult: 'Cache',
        type: 'QUOTE',
        locked: true,
        dirty: true,
        privateResult: privateResult,
        beginHidden: true,
        separatorHidden: inserted,
        endHidden: privateResult,
        instructionVisibility: LegacyWordFieldInstructionVisibility([
          (1, 4),
          (7, 10),
        ]),
      ),
    ],
    noteReferences: [
      if (scope == 'footnote' || scope == 'endnote')
        LegacyWordNoteReference(
          id: 11,
          anchorCp: 1,
          storyId: storyId,
          endnote: scope == 'endnote',
        ),
      if (coincident)
        LegacyWordNoteReference(
          id: 11,
          anchorCp: separator + 1,
          storyId: 'nested-note',
          endnote: false,
        ),
    ],
    commentReferences: [
      if (scope == 'comment')
        LegacyWordCommentReference(
          id: 21,
          anchorCp: 1,
          storyId: storyId,
          author: 'Commenter',
        ),
      if (coincident)
        LegacyWordCommentReference(
          id: 21,
          anchorCp: separator + 1,
          rangeStartCp: separator + 1,
          rangeEndCp: cacheStart + 5,
          storyId: 'nested-comment',
          author: 'Commenter',
        ),
    ],
    bookmarks: [
      if (coincident)
        LegacyWordBookmark(
          name: 'Coincident',
          startCp: separator + 1,
          endCp: cacheStart + 5,
        ),
    ],
    numbering: [
      if (scope == 'list')
        const LegacyWordNumberingDefinition(
          id: 1,
          levels: [
            LegacyWordNumberingLevel(level: 0, format: 'decimal', text: '%1.'),
          ],
        ),
    ],
    textboxReferences: [
      if (textbox)
        LegacyWordTextboxReference(
          id: 1,
          storyId: storyId,
          inHeaderFooter: headerTextbox,
          anchorCp: headerTextbox ? 101 : 1,
          shapeId: 1024,
        ),
    ],
    media: LegacyWordMediaCatalog.from(
      drawings: [
        if (textbox)
          LegacyWordDrawing(
            shapeId: 1024,
            anchorCp: headerTextbox ? 101 : 1,
            headerStory: headerTextbox,
            leftTwips: 0,
            topTwips: 0,
            rightTwips: 4000,
            bottomTwips: 2000,
            horizontalOrigin: 0,
            verticalOrigin: 0,
            wrapMode: 0,
            wrapSide: 0,
            behindText: false,
            anchorLocked: false,
            textboxId: 0x10000,
            source: const LegacyWordSourceReference(
              streamPath: '1Table',
              offset: 0,
              length: 26,
              structure: 'FSPA',
            ),
          ),
      ],
    ),
  );
}

LegacyWordDocument cachedFieldDepthDocument(int depth) => LegacyWordDocument(
  blocks: [
    LegacyWordParagraph(
      startCp: 0,
      endCp: 10 * depth + 2,
      runs: [
        LegacyWordRun(startCp: 9 * depth, endCp: 9 * depth + 1, text: 'Z'),
      ],
    ),
  ],
  sections: const [],
  plainText: 'Z',
  safeHtml: '',
  fields: [
    for (var index = 0; index < depth; index++)
      LegacyWordField(
        id: index,
        parentId: index == 0 ? null : index - 1,
        storyId: 'main',
        startCp: 9 * index,
        separatorCp: 9 * index + 8,
        endCp: 10 * depth + 1 - index,
        instruction: ' QUOTE ',
        storedResult: 'Z',
        type: 'QUOTE',
      ),
  ],
);
