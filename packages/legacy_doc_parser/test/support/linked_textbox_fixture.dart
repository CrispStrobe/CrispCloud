// SPDX-License-Identifier: MPL-2.0
import 'package:legacy_doc_parser/legacy_doc_parser.dart';

/// Authored editable story: increasing only the first frame's height must
/// pull text back from the second frame. Markers are unique, so a renderer
/// cannot pass by duplicating the full story in both frames.
LegacyWordDocument linkedTextboxFixture({int firstHeightTwips = 840}) {
  const markers = [
    'FLOW_ONE',
    'FLOW_TWO',
    'FLOW_THREE',
    'FLOW_FOUR',
    'FLOW_FIVE',
    'FLOW_SIX',
    'FLOW_SEVEN',
    'FLOW_EIGHT',
  ];
  final paragraphs = <LegacyWordParagraph>[];
  var cp = 10;
  for (final marker in markers) {
    paragraphs.add(
      LegacyWordParagraph(
        startCp: cp,
        endCp: cp + marker.length + 1,
        style: const LegacyWordParagraphStyle(
          spaceBeforeTwips: 0,
          spaceAfterTwips: 0,
          lineSpacingValue: -280,
        ),
        runs: [
          LegacyWordRun(
            startCp: cp,
            endCp: cp + marker.length,
            text: marker,
            style: const LegacyWordCharacterStyle(
              fontName: 'Liberation Serif',
              fontSizeHalfPoints: 24,
            ),
          ),
        ],
      ),
    );
    cp += marker.length + 1;
  }
  LegacyWordDrawing drawing(int id, int anchor, int index) => LegacyWordDrawing(
    shapeId: id,
    anchorCp: anchor,
    headerStory: false,
    leftTwips: index == 0 ? 1440 : 7200,
    topTwips: 1440,
    rightTwips: index == 0 ? 4320 : 10080,
    bottomTwips: 1440 + (index == 0 ? firstHeightTwips : 2800),
    horizontalOrigin: 1,
    verticalOrigin: 1,
    wrapMode: 3,
    wrapSide: 0,
    behindText: false,
    anchorLocked: false,
    textboxId: 0x10000 | index,
    nextTextboxShapeId: index == 0 ? 43 : null,
    shape: LegacyWordOfficeArtShape(
      type: 202,
      fill: const LegacyWordOfficeArtFill(enabled: false),
      line: const LegacyWordOfficeArtLine(enabled: true, color: '000000'),
      text: const LegacyWordOfficeArtText(
        insetLeftEmu: 0,
        insetTopEmu: 0,
        insetRightEmu: 0,
        insetBottomEmu: 0,
        fitShapeToText: false,
        anchor: 0,
      ),
    ),
    source: const LegacyWordSourceReference(
      streamPath: '0Table',
      offset: 0,
      length: 26,
      structure: 'Authored FSPA',
    ),
  );
  return LegacyWordDocument(
    blocks: [
      LegacyWordParagraph(
        startCp: 0,
        endCp: 4,
        runs: [LegacyWordRun(startCp: 0, endCp: 3, text: '   ')],
      ),
    ],
    sections: const [],
    plainText: '   ',
    safeHtml: '',
    stories: [
      LegacyWordStory(
        id: 'linked-probe',
        kind: LegacyWordStoryKind.textbox,
        startCp: 10,
        endCp: cp,
        blocks: paragraphs,
        plainText: markers.join('\n'),
        safeHtml: '',
      ),
    ],
    textboxReferences: const [
      LegacyWordTextboxReference(
        id: 1,
        storyId: 'linked-probe',
        inHeaderFooter: false,
        shapeId: 42,
        anchorCp: 1,
        chainLength: 2,
        anchors: [
          LegacyWordTextboxAnchor(
            shapeId: 42,
            anchorCp: 1,
            chainIndex: 0,
            nextShapeId: 43,
          ),
          LegacyWordTextboxAnchor(shapeId: 43, anchorCp: 2, chainIndex: 1),
        ],
      ),
    ],
    media: LegacyWordMediaCatalog.from(
      drawings: [drawing(42, 1, 0), drawing(43, 2, 1)],
    ),
  );
}
