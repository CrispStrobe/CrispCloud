import 'wml_document.dart';
import 'word_tree.dart';

/// Well-formedness of complex-field boundaries ([WmlFieldBoundary]).
abstract final class WordFieldSpans {
  /// Boundaries that do not form a well-formed `begin, instruction*,
  /// (separate)?, ..., end` sequence within their story — e.g. after an edit
  /// deleted part of a field. The serializer skips them, so the field's
  /// result degrades to plain text instead of producing an unbalanced
  /// (corrupt) package.
  static Set<WmlFieldBoundary> unbalanced(WmlDocument document) {
    final skipped = Set<WmlFieldBoundary>.identity();
    for (final story in _stories(document)) {
      // Open fields: their boundaries so far, and whether separated.
      final open = <({List<WmlFieldBoundary> members, bool separated})>[];
      for (final paragraph in story) {
        for (final inline in paragraph.inlines) {
          if (inline is! WmlFieldBoundary) continue;
          switch (inline.kind) {
            case WmlFieldBoundaryKind.begin:
              open.add((members: [inline], separated: false));
            case WmlFieldBoundaryKind.instruction:
              if (open.isEmpty || open.last.separated) {
                skipped.add(inline);
              } else {
                open.last.members.add(inline);
              }
            case WmlFieldBoundaryKind.separate:
              if (open.isEmpty || open.last.separated) {
                skipped.add(inline);
              } else {
                final top = open.removeLast();
                open.add((members: [...top.members, inline], separated: true));
              }
            case WmlFieldBoundaryKind.end:
              if (open.isEmpty) {
                skipped.add(inline);
              } else {
                open.removeLast();
              }
          }
        }
      }
      for (final field in open) {
        skipped.addAll(field.members);
      }
    }
    return skipped;
  }

  static Iterable<Iterable<WmlParagraph>> _stories(WmlDocument doc) sync* {
    yield WordTree.paragraphs(doc.sections.expand((s) => s.blocks));
    for (final section in doc.sections) {
      yield section.header;
      yield section.footer;
      yield section.firstHeader;
      yield section.firstFooter;
      yield section.evenHeader;
      yield section.evenFooter;
    }
    for (final note in [...doc.footnotes, ...doc.endnotes]) {
      yield WordTree.paragraphs(note.blocks);
    }
    for (final comment in doc.comments) {
      yield comment.paragraphs;
    }
  }
}
