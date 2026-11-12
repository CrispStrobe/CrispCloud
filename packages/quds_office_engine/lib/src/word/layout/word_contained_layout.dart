part of 'word_layout.dart';

// Table cells and textboxes share a nonbreaking child layout. Measurement calls
// this same dispatcher with scratch buffers, so rich block height and visible
// placement cannot diverge. An anchored frame has children but consumes no flow
// height; opaque preserved content has no Quds rendering.
({double y, int nextParagraphIndex}) _layoutContainedBlock(
  WordLayoutEngine owner,
  WmlBlock block,
  WmlSection section,
  List<LaidOutPage> pages,
  List<LaidOutLine> lines,
  List<LaidOutBox> frames,
  int pageIndex,
  double y,
  int paragraphIndex, {
  required double originX,
  required double maxWidth,
}) {
  var cursor = y;
  var nextParagraph = paragraphIndex;
  switch (block) {
    case WmlParagraph():
      cursor = owner
          ._layoutParagraph(
            block,
            section,
            pages,
            lines,
            frames,
            pageIndex,
            y,
            paragraphIndex,
            originX: originX,
            maxWidthOverride: maxWidth,
            allowBreak: false,
          )
          .y;
      nextParagraph++;
    case WmlVisual():
      final absolute =
          block.visual.picture.wrap == PictureWrap.behind ||
          block.visual.picture.wrap == PictureWrap.inFront;
      final deferred = owner._deferredContainedVisuals;
      if (absolute && deferred != null) {
        if (owner._containedMeasureDepth == 0) deferred[block] = y;
        break;
      }
      final physical = owner._containedPhysicalSection ?? section;
      final depth = math.max(1, owner._containedTableDepth);
      // Reserve all ancestor cell padding, nested-table flow gaps (6 + 4),
      // and this visual's flow gaps (8 + 10). Both real and temporary row
      // layouts use the same physical-page cap; model dimensions stay intact.
      final heightLimit =
          physical.contentHeight -
          18 -
          2 * LaidOutLine.tableCellPad * depth -
          10 * (depth - 1);
      if (!absolute && heightLimit <= 0) {
        throw UnsupportedError(
          'The page is too short for an inline picture at this table nesting depth.',
        );
      }
      cursor = owner
          ._layoutVisual(
            block.visual,
            section,
            pages,
            lines,
            frames,
            pageIndex,
            y,
            originX: originX,
            maxWidthOverride: maxWidth,
            maxHeightOverride: absolute ? null : heightLimit,
            allowBreak: false,
          )
          .y;
    case WmlTable():
      cursor = owner
          ._layoutTable(
            block,
            section,
            pages,
            lines,
            frames,
            pageIndex,
            y,
            paragraphIndex,
            originX: originX,
            maxWidthOverride: maxWidth,
            allowBreak: false,
          )
          .y;
      nextParagraph += WordLayoutEngine._tableParagraphCount(block);
    case WmlToc():
      cursor = owner
          ._layoutToc(
            block,
            section,
            pages,
            lines,
            frames,
            pageIndex,
            y,
            paragraphIndex,
            originX: originX,
            maxWidthOverride: maxWidth,
            allowBreak: false,
          )
          .y;
      nextParagraph += 1 + block.itemParagraphs.length;
    case WmlFrame():
      final deferred = owner._deferredContainedFrames;
      if (deferred != null) {
        if (owner._containedMeasureDepth == 0) {
          deferred[block] = (y: y, paragraphIndex: paragraphIndex);
        }
        nextParagraph += WordTree.paragraphs(block.blocks).length;
      } else {
        nextParagraph = owner._layoutFrameContents(
          block,
          section,
          pages,
          lines,
          frames,
          pageIndex,
          paragraphIndex,
        );
      }
    case WmlEquation():
      final omml = OmmlLayout.layout(block.math, fontSize: 14);
      frames.add(
        LaidOutBox(
          x: originX,
          y: y,
          width: math.min(maxWidth, omml.width),
          height: omml.height,
          fillColor: 'F7FBFF',
          strokeColor: '8FAADC',
          kind: LaidOutBoxKind.equation,
          equation: block,
          omml: omml,
        ),
      );
      cursor += omml.height + 4;
    case WmlContentControlBlock():
      for (final child in WordTree.visibleBlocks(block.blocks)) {
        final result = _layoutContainedBlock(
          owner,
          child,
          section,
          pages,
          lines,
          frames,
          pageIndex,
          cursor,
          nextParagraph,
          originX: originX,
          maxWidth: maxWidth,
        );
        cursor = result.y;
        nextParagraph = result.nextParagraphIndex;
      }
    case WmlOpaqueBlock():
      break;
  }
  return (y: cursor, nextParagraphIndex: nextParagraph);
}
