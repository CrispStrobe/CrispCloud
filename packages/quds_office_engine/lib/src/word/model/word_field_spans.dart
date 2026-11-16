import 'wml_document.dart';
import 'word_tree.dart';
import 'word_zotero.dart';

/// One complete inline Zotero citation and its protected visible text range.
/// Unsupported packets are retained as guards rather than treated as text.
final class WmlZoteroEditSpan {
  const WmlZoteroEditSpan({
    required this.first,
    required this.last,
    required this.start,
    required this.end,
    required this.canEdit,
    this.paragraphOwned = false,
  });
  final int first;
  final int last;
  final int start;
  final int end;
  final bool canEdit;
  final bool paragraphOwned;

  bool touches(int from, int to) => from == to
      ? paragraphOwned || (from > start && from < end)
      : from < end && to > start ||
            (start == end && from <= start && to >= end);
}

/// Well-formedness of complex-field boundaries ([WmlFieldBoundary]).
abstract final class WordFieldSpans {
  /// Zotero-only edit protection. Ordinary Word field semantics are unchanged.
  ///
  /// Native parsing supplies editability; the structural scan additionally
  /// guards malformed marker sequences and unfinished citations. No mutation
  /// or edit normalization occurs while inspecting these packets.
  static List<WmlZoteroEditSpan> zoteroCitations(WmlParagraph paragraph) {
    if (paragraph.properties.fieldInstruction == null &&
        !paragraph.inlines.any(
          (inline) =>
              inline is WmlFieldBoundary ||
              (inline is WmlRun && inline.fieldInstruction != null),
        )) {
      return const [];
    }
    final native = WordZotero.citationEditPackets(paragraph);
    final spans = <WmlZoteroEditSpan>[
      for (final packet in native)
        if (packet.paragraphOwned || packet.first == packet.last)
          WmlZoteroEditSpan(
            first: packet.first,
            last: packet.last,
            start: packet.start,
            end: packet.end,
            // Paragraph-owned fields have no inline insertion boundary.
            canEdit: packet.canEdit && !packet.paragraphOwned,
            paragraphOwned: packet.paragraphOwned,
          ),
    ];
    final stack = <_ZoteroSpanScan>[];
    var offset = 0;
    for (var index = 0; index < paragraph.inlines.length; index++) {
      final inline = paragraph.inlines[index];
      if (inline is WmlFieldBoundary) {
        switch (inline.kind) {
          case WmlFieldBoundaryKind.begin:
            for (final open in stack) {
              open.valid = false;
            }
            stack.add(_ZoteroSpanScan(index, offset, stack.isEmpty));
          case WmlFieldBoundaryKind.instruction:
            if (stack.isNotEmpty) {
              final open = stack.last;
              if (open.separated) open.valid = false;
              open.instruction.write(inline.text);
            }
          case WmlFieldBoundaryKind.separate:
            if (stack.isNotEmpty) {
              final open = stack.last;
              if (open.separated) open.valid = false;
              open.separated = true;
            }
          case WmlFieldBoundaryKind.end:
            if (stack.isEmpty) continue;
            final open = stack.removeLast();
            if (!_citationCode(open.instruction.toString())) continue;
            final packet = native
                .where((p) => p.first == open.first && p.last == index)
                .firstOrNull;
            spans.add(
              WmlZoteroEditSpan(
                first: open.first,
                last: index,
                start: open.start,
                end: offset,
                canEdit:
                    open.valid && open.separated && packet?.canEdit == true,
              ),
            );
        }
      } else {
        if (stack.isNotEmpty && !stack.last.separated) {
          stack.last.valid = false;
        }
        if (inline is WmlRun) offset += inline.text.length;
      }
    }
    for (final open in stack) {
      if (!_citationCode(open.instruction.toString())) continue;
      spans.add(
        WmlZoteroEditSpan(
          first: open.first,
          last: paragraph.inlines.length - 1,
          start: open.start,
          end: offset,
          canEdit: false,
        ),
      );
    }
    spans.sort((a, b) => a.first.compareTo(b.first));
    return spans;
  }

  static bool _citationCode(String code) =>
      WordZotero.kindOfInstruction(code) == ZoteroFieldKind.citation ||
      RegExp(
        r'^\s*(?:ADDIN\s+ZOTERO_ITEM\b|(?:ADDIN\s+)?CSL_CITATION\b)',
        caseSensitive: false,
      ).hasMatch(code);

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

final class _ZoteroSpanScan {
  _ZoteroSpanScan(this.first, this.start, this.valid);
  final int first;
  final int start;
  final instruction = StringBuffer();
  bool valid;
  bool separated = false;
}
