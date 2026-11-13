// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import 'metafile_fixture.dart';
import 'structured_word_fixture.dart';

const publicMetafilePlacements = ['inline', 'floating', 'textbox-fill'];
const publicMetafileMutations = ['valid', 'escape', 'truncated', 'bad-size'];

Uint8List publicMetafileBytes(LegacyWordImageFormat format, String mutation) {
  final emf = format == LegacyWordImageFormat.emf;
  final bytes = emf
      ? emfFixture(
          records: [
            if (mutation == 'escape')
              emfRecord(105, [...wordU32(1), ...wordU32(0)]),
          ],
        )
      : wmfFixture(
          placeable: true,
          records: [
            if (mutation == 'escape')
              wmfRecord(0x626, [...wordU16(9), ...wordU16(0)]),
          ],
        );
  if (mutation == 'truncated') return Uint8List.sublistView(bytes, 0, 12);
  if (mutation == 'bad-size') {
    ByteData.sublistView(bytes).setUint32(emf ? 48 : 28, 1, Endian.little);
  }
  return bytes;
}

/// The metadata is intentionally independent of the raw bytes. Callers can
/// construct these public models without running the binary parser first.
LegacyWordDocument publicMetafileDocument(
  LegacyWordImageFormat format,
  String mutation,
  String placement, {
  bool metadataAllowsEmbedding = true,
  int references = 1,
  Uint8List? rawBytes,
}) {
  const source = LegacyWordSourceReference(
    streamPath: 'Data',
    offset: 0,
    length: 1,
    structure: 'PublicModelFixture',
  );
  final asset = LegacyWordImageAsset(
    id: 'image',
    format: format,
    bytes: rawBytes ?? publicMetafileBytes(format, mutation),
    source: source,
    officeArtArtifactId: 'artifact',
    metafile: LegacyWordMetafileInfo(
      bounds: const LegacyWordVectorBounds(0, 0, 200, 100),
      recordCount: 2,
      nativeEmbeddingAllowed: metadataAllowsEmbedding,
    ),
  );
  final textbox = placement == 'textbox-fill';
  return LegacyWordDocument(
    blocks: const [
      LegacyWordParagraph(
        startCp: 0,
        endCp: 4,
        runs: [
          LegacyWordRun(startCp: 0, endCp: 1, text: 'A'),
          LegacyWordRun(startCp: 2, endCp: 3, text: 'B'),
        ],
      ),
    ],
    sections: const [],
    plainText: 'AB',
    safeHtml: '',
    stories: [
      if (textbox)
        const LegacyWordStory(
          id: 'box',
          kind: LegacyWordStoryKind.textbox,
          startCp: 10,
          endCp: 14,
          blocks: [
            LegacyWordParagraph(
              startCp: 10,
              endCp: 14,
              runs: [LegacyWordRun(startCp: 10, endCp: 13, text: 'Box')],
            ),
          ],
          plainText: 'Box',
          safeHtml: '',
        ),
    ],
    textboxReferences: [
      if (textbox)
        const LegacyWordTextboxReference(
          id: 1,
          storyId: 'box',
          inHeaderFooter: false,
          shapeId: 42,
          anchorCp: 1,
        ),
    ],
    media: LegacyWordMediaCatalog.from(
      assets: [asset],
      pictures: [
        if (placement == 'inline')
          for (var i = 0; i < references; i++)
            LegacyWordPicture(
              id: 'picture-$i',
              cp: 1,
              source: source,
              officeArtArtifactId: 'artifact',
              imageId: 'image',
            ),
      ],
      drawings: [
        if (placement != 'inline')
          LegacyWordDrawing(
            shapeId: 42,
            anchorCp: 1,
            headerStory: false,
            leftTwips: 0,
            topTwips: 0,
            rightTwips: 1440,
            bottomTwips: 720,
            horizontalOrigin: 1,
            verticalOrigin: 1,
            wrapMode: 3,
            wrapSide: 2,
            behindText: false,
            anchorLocked: false,
            source: source,
            officeArtArtifactId: 'artifact',
            imageId: textbox ? null : 'image',
            textboxId: textbox ? 0x10000 : null,
            shape: textbox
                ? LegacyWordOfficeArtShape(
                    type: 202,
                    fill: const LegacyWordOfficeArtFill(
                      type: 2,
                      imageId: 'image',
                    ),
                  )
                : null,
          ),
      ],
    ),
  );
}
