// SPDX-License-Identifier: MPL-2.0
import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import 'public_textbox_reference_fixture.dart';

LegacyWordDocument unidentifiedTextboxDocument(
  String mutation, {
  bool hidden = false,
}) {
  final base = publicTextboxReferenceDocument(
    mutation == 'wrong-owner'
        ? 'single-header-in-main'
        : 'single-without-client',
    hidden: hidden,
  );
  final original = base.textboxReferences.single;
  final oldDrawing = base.media.drawings.single;
  final anchor = LegacyWordTextboxAnchor(
    shapeId: oldDrawing.shapeId,
    anchorCp: oldDrawing.anchorCp,
    chainIndex: 0,
    nextShapeId: oldDrawing.shapeId,
  );
  final reference = LegacyWordTextboxReference(
    id: original.id,
    storyId: original.storyId,
    inHeaderFooter: original.inHeaderFooter,
    shapeId: original.shapeId,
    anchorCp: mutation == 'wrong-anchor' ? 2 : original.anchorCp,
    anchors: mutation == 'explicit-anchor' ? [anchor] : const [],
    headerAliases: mutation == 'header-alias' ? [anchor] : const [],
    replicaAnchors: mutation == 'replica' ? [anchor] : const [],
  );
  final drawing = LegacyWordDrawing(
    shapeId: oldDrawing.shapeId,
    anchorCp: oldDrawing.anchorCp,
    headerStory: oldDrawing.headerStory,
    leftTwips: oldDrawing.leftTwips,
    topTwips: oldDrawing.topTwips,
    rightTwips: oldDrawing.rightTwips,
    bottomTwips: oldDrawing.bottomTwips,
    horizontalOrigin: oldDrawing.horizontalOrigin,
    verticalOrigin: oldDrawing.verticalOrigin,
    wrapMode: oldDrawing.wrapMode,
    wrapSide: oldDrawing.wrapSide,
    behindText: oldDrawing.behindText,
    anchorLocked: oldDrawing.anchorLocked,
    source: oldDrawing.source,
    textboxId: switch (mutation) {
      'client-zero' => 0,
      'client-id' => 1 << 16,
      'wrong-client' => 9 << 16,
      _ => null,
    },
    nextTextboxShapeId: mutation == 'nonself' ? 43 : oldDrawing.shapeId,
  );
  return LegacyWordDocument(
    blocks: base.blocks,
    sections: base.sections,
    plainText: base.plainText,
    safeHtml: base.safeHtml,
    stories: base.stories,
    fields: base.fields,
    textboxReferences: [
      reference,
      if (mutation == 'duplicate-owner') reference,
    ],
    media: LegacyWordMediaCatalog.from(drawings: [drawing]),
  );
}
