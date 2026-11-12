import 'wml_document.dart';

/// Shared traversal and exact ownership for editable Word block trees.
///
/// A located parent is the original mutable list. Structural edits must use
/// this list instead of rebuilding a flattened view or falling back to the
/// section when a paragraph lives in a frame or nested table.
abstract final class WordTree {
  /// Blocks participating directly in the current layout flow.
  ///
  /// Tables and frames remain layout objects; their children have their own
  /// layout context. Transparent content-control containers are unwrapped.
  static Iterable<WmlBlock> visibleBlocks(Iterable<WmlBlock> blocks) sync* {
    for (final block in blocks) {
      if (block is WmlContentControlBlock) {
        yield* visibleBlocks(block.blocks);
      } else {
        yield block;
      }
    }
  }

  /// Every block in document order, including containers themselves.
  static Iterable<WmlBlock> descendants(Iterable<WmlBlock> blocks) sync* {
    for (final block in blocks) {
      yield block;
      for (final children in childLists(block)) {
        yield* descendants(children);
      }
    }
  }

  /// Actual mutable block lists owned by a container.
  static Iterable<List<WmlBlock>> childLists(WmlBlock block) sync* {
    if (block is WmlContentControlBlock) {
      yield block.blocks;
    } else if (block is WmlFrame) {
      yield block.blocks;
    } else if (block is WmlTable) {
      for (final row in block.rows) {
        for (final cell in row.cells) {
          yield cell.blocks;
        }
      }
    }
  }

  /// Live logical paragraphs, including the title and results of a TOC.
  static Iterable<WmlParagraph> paragraphs(Iterable<WmlBlock> blocks) sync* {
    for (final block in descendants(blocks)) {
      if (block is WmlParagraph) {
        yield block;
      } else if (block is WmlToc) {
        yield block.titleParagraph;
        yield* block.itemParagraphs;
      }
    }
  }

  /// Exact parent list and position of [target] inside [blocks].
  static ({List<WmlBlock> parent, int index})? locateIn(
    List<WmlBlock> blocks,
    WmlBlock target,
  ) {
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (identical(block, target)) return (parent: blocks, index: index);
      for (final children in childLists(block)) {
        final found = locateIn(children, target);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Exact ownership in the body or a footnote/endnote block story.
  ///
  /// Paragraph-only header/footer/comment editors already own their lists;
  /// they should continue to use those lists rather than a body fallback.
  static ({List<WmlBlock> parent, int index})? locate(
    WmlDocument document,
    WmlBlock target,
  ) {
    for (final section in document.sections) {
      final found = locateIn(section.blocks, target);
      if (found != null) return found;
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      final found = locateIn(note.blocks, target);
      if (found != null) return found;
    }
    return null;
  }

  /// The paragraph or table/frame/TOC hosting it in the current flow.
  ///
  /// Inserting a block after a paragraph inside a table should use the table's
  /// flow position. Transparent controls instead expose their content list so
  /// such insertion does not escape the owning control.
  static ({List<WmlBlock> parent, int index})? flowHostIn(
    List<WmlBlock> blocks,
    WmlParagraph paragraph,
  ) {
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (block is WmlContentControlBlock) {
        final found = flowHostIn(block.blocks, paragraph);
        if (found != null) return found;
        continue;
      }
      if (identical(block, paragraph) ||
          paragraphs(<WmlBlock>[block]).any((p) => identical(p, paragraph))) {
        return (parent: blocks, index: index);
      }
    }
    return null;
  }

  /// The current flow host in the body or an editable note block story.
  static ({List<WmlBlock> parent, int index})? flowHost(
    WmlDocument document,
    WmlParagraph paragraph,
  ) {
    for (final section in document.sections) {
      final found = flowHostIn(section.blocks, paragraph);
      if (found != null) return found;
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      final found = flowHostIn(note.blocks, paragraph);
      if (found != null) return found;
    }
    return null;
  }
}
