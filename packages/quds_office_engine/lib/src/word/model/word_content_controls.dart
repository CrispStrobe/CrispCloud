import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import 'wml_document.dart';
import 'word_tree.dart';

/// Balanced inline content-control spans and bounded edit semantics.
///
/// Text edits contained in a control preserve its wrapper. Splitting a native
/// inline control across paragraphs or deleting across its boundary requires
/// richer control-edit semantics and is rejected before changing content.
abstract final class WordContentControls {
  static bool hasInlineControls(WmlParagraph paragraph) =>
      paragraph.inlines.any((inline) => inline is WmlContentControlBoundary);

  /// Controls whose boundaries prohibit paragraph joins or multi-paragraph
  /// replacements. Paragraph-owned block wrappers are separate from inline
  /// field spans, so a wrapped PAGE field can still refresh normally.
  static bool hasStructuralControls(WmlParagraph paragraph) =>
      paragraph.contentControlWrappers.isNotEmpty ||
      hasInlineControls(paragraph);

  static List<({WmlContentControlData control, int start, int end})> spans(
    WmlParagraph paragraph,
  ) {
    final stack = <({WmlContentControlData control, int start})>[];
    final result = <({WmlContentControlData control, int start, int end})>[];
    var offset = 0;
    for (final inline in paragraph.inlines) {
      if (inline is WmlRun) {
        offset += inline.text.length;
      } else if (inline is WmlContentControlBoundary) {
        if (inline.start) {
          stack.add((control: inline.control, start: offset));
        } else {
          if (stack.isEmpty || !identical(stack.last.control, inline.control)) {
            throw StateError(
              'Inline content-control boundaries are unbalanced',
            );
          }
          final open = stack.removeLast();
          result.add((control: open.control, start: open.start, end: offset));
        }
      }
    }
    if (stack.isNotEmpty) {
      throw StateError('Inline content-control boundaries cross a paragraph');
    }
    return result;
  }

  static void assertCanSplit(WmlParagraph paragraph, int offset) {
    if (paragraph.contentControlWrappers.isNotEmpty) {
      throw UnsupportedError(
        'Splitting an auxiliary paragraph inside a native block content '
        'control is not supported. Edit its text or formatting within the '
        'existing paragraph.',
      );
    }
    for (final span in spans(paragraph)) {
      if (offset > span.start && offset < span.end) {
        throw UnsupportedError(
          'Splitting inside an inline content control is not supported. '
          'Place the paragraph break outside the control.',
        );
      }
    }
  }

  static void assertCanEdit(WmlParagraph paragraph, int start, int end) {
    for (final span in spans(paragraph)) {
      if ((span.start > start && span.start < end) ||
          (span.end > start && span.end < end)) {
        throw UnsupportedError(
          'Replacing text across an inline content-control boundary is not '
          'supported. Edit the control content or the surrounding text separately.',
        );
      }
    }
  }

  /// Controls that can be copied as complete wrappers in a text slice.
  static Set<WmlContentControlData> controlsInSlice(
    WmlParagraph paragraph,
    int from,
    int to,
  ) {
    final selected = <WmlContentControlData>{};
    for (final span in spans(paragraph)) {
      if (span.start == span.end) {
        if (span.start >= from &&
            (span.start < to ||
                (to == paragraph.text.length &&
                    from < to &&
                    span.start == to))) {
          selected.add(span.control);
        }
        continue;
      }
      if (from <= span.start && to >= span.end) {
        selected.add(span.control);
      } else if (from < span.end && to > span.start) {
        throw UnsupportedError(
          'Copying part of an inline content control is not supported',
        );
      }
    }
    return selected;
  }

  /// Inline insertion affinity: a control start includes newly typed text;
  /// a control end leaves it outside. Empty controls accept text inside.
  static int? insertionIndex(WmlParagraph paragraph, int at) {
    if (!hasInlineControls(paragraph)) return null;
    spans(paragraph);
    var offset = 0;
    var position = paragraph.inlines.length;
    int? insideStart;
    for (var index = 0; index < paragraph.inlines.length; index++) {
      final inline = paragraph.inlines[index];
      if (inline is WmlRun) {
        if (offset >= at) return insideStart ?? index;
        offset += inline.text.length;
        position = index + 1;
      } else if (offset == at) {
        if (inline is WmlContentControlBoundary) {
          if (inline.start) insideStart = index + 1;
        } else if (insideStart != null) {
          insideStart = index + 1;
        }
        position = index + 1;
      }
    }
    return insideStart ?? position;
  }

  /// Validates balanced inline boundaries and unique native control IDs before
  /// a serializer mutates its package. Imported IDs are never rewritten.
  static void validate(WmlDocument document) =>
      _validateIds(_documentControls(document), insertion: false);

  /// Rejects a rich insertion that would duplicate an existing native ID.
  ///
  /// Cloning for independent snapshots is safe. Inserting that clone alongside
  /// its original requires document-aware ID allocation, which is deliberately
  /// guarded until it is implemented; ordinary text edits remain supported.
  static void assertCanInsert(WmlDocument document, Iterable<WmlBlock> blocks) {
    _validateIds([
      ..._documentControls(document),
      ..._blockControls(blocks),
    ], insertion: true);
  }

  static void _validateIds(
    Iterable<WmlContentControlData> controls, {
    required bool insertion,
  }) {
    final seen = <String>{};
    for (final control in controls) {
      // Check the native shell, not optional convenience metadata supplied by
      // a model caller. A stale/null cached ID must not bypass the guard.
      final native = XmlDocument.parse(control.xml).root;
      final id = native
          ?.firstChild('sdtPr', namespaceUri: OfficeNamespaces.w)
          ?.firstChild('id', namespaceUri: OfficeNamespaces.w)
          ?.getAttribute('val', namespaceUri: OfficeNamespaces.w);
      if (id == null || id.isEmpty) continue;
      final key = BigInt.tryParse(id.trim())?.toString() ?? id;
      if (!seen.add(key)) {
        final message =
            'Duplicate native content-control ID $id. Copying a content '
            'control into the same document requires a new native ID and is '
            'not supported yet.';
        if (insertion) throw UnsupportedError(message);
        throw StateError(message);
      }
    }
  }

  static Iterable<WmlContentControlData> _paragraphControls(
    Iterable<WmlParagraph> paragraphs,
  ) sync* {
    for (final paragraph in paragraphs) {
      yield* paragraph.contentControlWrappers;
      for (final span in spans(paragraph)) {
        yield span.control;
      }
    }
  }

  static Iterable<WmlContentControlData> _blockControls(
    Iterable<WmlBlock> blocks,
  ) sync* {
    for (final block in WordTree.descendants(blocks)) {
      if (block is WmlContentControlBlock) yield block.control;
      if (block is WmlParagraph) {
        yield* _paragraphControls([block]);
      } else if (block is WmlToc) {
        yield* _paragraphControls([
          block.titleParagraph,
          ...block.itemParagraphs,
        ]);
      }
    }
  }

  static Iterable<WmlContentControlData> _documentControls(
    WmlDocument document,
  ) sync* {
    for (final section in document.sections) {
      yield* _blockControls(section.blocks);
      yield* _paragraphControls([
        ...section.header,
        ...section.footer,
        ...section.firstHeader,
        ...section.firstFooter,
        ...section.evenHeader,
        ...section.evenFooter,
      ]);
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      yield* _blockControls(note.blocks);
    }
    for (final comment in document.comments) {
      yield* _paragraphControls(comment.paragraphs);
    }
  }
}
