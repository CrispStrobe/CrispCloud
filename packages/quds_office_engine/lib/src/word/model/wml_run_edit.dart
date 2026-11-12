import '../properties/wml_properties.dart';
import 'wml_document.dart';

/// Split and format [WmlRun] spans inside a paragraph.
abstract final class WmlRunEdit {
  /// propsAt API.
  static WmlRunProps propsAt(WmlParagraph paragraph, int index) {
    var offset = 0;
    WmlRunProps last = WmlRunProps();
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is! WmlRun) {
        continue;
      }
      last = inline.properties;
      final int end = offset + inline.text.length;
      if (index < end) {
        return inline.properties;
      }
      offset = end;
    }
    return last;
  }

  /// splitAt API.
  static void splitAt(WmlParagraph paragraph, int index) {
    var offset = 0;
    for (int i = 0; i < paragraph.inlines.length; i++) {
      final WmlInline inline = paragraph.inlines[i];
      if (inline is! WmlRun) {
        continue;
      }
      final int end = offset + inline.text.length;
      if (index > offset && index < end) {
        // Note marks and cached inline field results are indivisible.
        if (inline.isAtomic) return;
        final int local = index - offset;
        paragraph.inlines.replaceRange(i, i + 1, <WmlInline>[
          WmlRun(
            text: inline.text.substring(0, local),
            properties: inline.properties.copy(),
            hyperlink: inline.hyperlink,
            commentIds: List<int>.from(inline.commentIds),
            noteRefId: inline.noteRefId,
            noteRefEndnote: inline.noteRefEndnote,
            fieldInstruction: inline.fieldInstruction,
            fieldLocked: inline.fieldLocked,
            fieldDirty: inline.fieldDirty,
          ),
          WmlRun(
            text: inline.text.substring(local),
            properties: inline.properties.copy(),
            hyperlink: inline.hyperlink,
            commentIds: List<int>.from(inline.commentIds),
            noteRefId: inline.noteRefId,
            noteRefEndnote: inline.noteRefEndnote,
            fieldInstruction: inline.fieldInstruction,
            fieldLocked: inline.fieldLocked,
            fieldDirty: inline.fieldDirty,
          ),
        ]);
        return;
      }
      offset = end;
    }
  }

  /// applyRange API.
  static void applyRange(
    WmlParagraph paragraph,
    int start,
    int end,
    void Function(WmlRunProps props) update,
  ) {
    if (start > end) {
      final int swap = start;
      start = end;
      end = swap;
    }
    final int length = paragraph.text.length;
    start = start.clamp(0, length);
    end = end.clamp(0, length);
    if (start == end) {
      if (paragraph.inlines.whereType<WmlRun>().isEmpty) {
        final WmlRunProps props = WmlRunProps();
        update(props);
        paragraph.inlines.add(WmlRun(properties: props));
      }
      return;
    }
    splitAt(paragraph, end);
    splitAt(paragraph, start);
    var offset = 0;
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is! WmlRun) {
        continue;
      }
      final int runEnd = offset + inline.text.length;
      if (((offset >= start && runEnd <= end) ||
              (inline.isAtomic && offset < end && runEnd > start)) &&
          inline.text.isNotEmpty) {
        update(inline.properties);
      }
      offset = runEnd;
    }
    coalesce(paragraph);
  }

  /// replaceRange API.
  static void replaceRange(
    WmlParagraph paragraph,
    int start,
    int end,
    String insert,
  ) {
    final range = normalizeRange(paragraph, start, end);
    start = range.start;
    end = range.end;
    final int length = paragraph.text.length;
    final WmlRunProps props = propsAt(
      paragraph,
      start == length ? start - 1 : start,
    );
    final List<int> commentIds = _commentIdsAt(
      paragraph,
      start == length ? start - 1 : start,
    );
    splitAt(paragraph, end);
    splitAt(paragraph, start);
    final List<WmlInline> next = <WmlInline>[];
    var offset = 0;
    var inserted = false;
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is! WmlRun) {
        next.add(inline);
        continue;
      }
      final int runEnd = offset + inline.text.length;
      final bool inside = offset >= start && runEnd <= end;
      if (inside) {
        if (!inserted) {
          if (insert.isNotEmpty) {
            next.add(
              WmlRun(
                text: insert,
                properties: props.copy(),
                commentIds: List<int>.from(commentIds),
              ),
            );
          }
          inserted = true;
        }
      } else {
        if (!inserted && offset >= end) {
          if (insert.isNotEmpty) {
            next.add(
              WmlRun(
                text: insert,
                properties: props.copy(),
                commentIds: List<int>.from(commentIds),
              ),
            );
          }
          inserted = true;
        }
        next.add(inline);
      }
      offset = runEnd;
    }
    if (!inserted && insert.isNotEmpty) {
      next.add(
        WmlRun(
          text: insert,
          properties: props.copy(),
          commentIds: List<int>.from(commentIds),
        ),
      );
    }
    paragraph.inlines
      ..clear()
      ..addAll(next);
    if (paragraph.inlines.whereType<WmlRun>().isEmpty) {
      paragraph.inlines.add(WmlRun(properties: props.copy()));
    }
    coalesce(paragraph);
  }

  /// Bounds for an edit that cannot split a note mark or inline field result.
  ///
  /// A nonempty selection touching an atomic field includes the whole result. A
  /// collapsed caret inside a result moves after it, just as
  /// [insertRuns] does. Callers can use these bounds for undo and selection.
  static ({int start, int end}) normalizeRange(
    WmlParagraph paragraph,
    int start,
    int end,
  ) {
    if (start > end) {
      final int swap = start;
      start = end;
      end = swap;
    }
    final int length = paragraph.text.length;
    start = start.clamp(0, length);
    end = end.clamp(0, length);
    final bool collapsed = start == end;
    var offset = 0;
    for (final WmlRun run in paragraph.inlines.whereType<WmlRun>()) {
      final int runEnd = offset + run.text.length;
      if (run.isAtomic) {
        if (collapsed && start > offset && start < runEnd) {
          return (start: runEnd, end: runEnd);
        }
        if (!collapsed && start < runEnd && end > offset) {
          if (start > offset) start = offset;
          if (end < runEnd) end = runEnd;
        }
      }
      offset = runEnd;
    }
    return (start: start, end: end);
  }

  /// extractRuns API.
  static List<WmlRun> extractRuns(WmlParagraph paragraph, int start, int end) {
    if (start > end) {
      final int swap = start;
      start = end;
      end = swap;
    }
    final int length = paragraph.text.length;
    start = start.clamp(0, length);
    end = end.clamp(0, length);
    if (start == end) {
      return <WmlRun>[];
    }
    final List<WmlRun> out = <WmlRun>[];
    var offset = 0;
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is! WmlRun) {
        continue;
      }
      final int runEnd = offset + inline.text.length;
      final int from = start > offset ? start : offset;
      final int to = end < runEnd ? end : runEnd;
      if (to > from) {
        out.add(
          WmlRun(
            text: inline.isAtomic
                ? inline.text
                : inline.text.substring(from - offset, to - offset),
            properties: inline.properties.copy(),
            hyperlink: inline.hyperlink,
            commentIds: List<int>.from(inline.commentIds),
            noteRefId: inline.noteRefId,
            noteRefEndnote: inline.noteRefEndnote,
            fieldInstruction: inline.fieldInstruction,
            fieldLocked: inline.fieldLocked,
            fieldDirty: inline.fieldDirty,
          ),
        );
      }
      offset = runEnd;
    }
    return out;
  }

  /// insertRuns API.
  static void insertRuns(WmlParagraph paragraph, int index, List<WmlRun> runs) {
    if (runs.isEmpty) {
      return;
    }
    final int length = paragraph.text.length;
    index = index.clamp(0, length);
    splitAt(paragraph, index);
    var offset = 0;
    var insertAt = paragraph.inlines.length;
    for (int i = 0; i < paragraph.inlines.length; i++) {
      final WmlInline inline = paragraph.inlines[i];
      if (inline is! WmlRun) {
        continue;
      }
      if (offset >= index) {
        insertAt = i;
        break;
      }
      offset += inline.text.length;
      insertAt = i + 1;
    }
    paragraph.inlines.insertAll(insertAt, <WmlInline>[
      for (final WmlRun run in runs)
        WmlRun(
          text: run.text,
          properties: run.properties.copy(),
          hyperlink: run.hyperlink,
          commentIds: List<int>.from(run.commentIds),
          noteRefId: run.noteRefId,
          noteRefEndnote: run.noteRefEndnote,
          fieldInstruction: run.fieldInstruction,
          fieldLocked: run.fieldLocked,
          fieldDirty: run.fieldDirty,
        ),
    ]);
    coalesce(paragraph);
  }

  /// coalesce API.
  static void coalesce(WmlParagraph paragraph) {
    if (paragraph.inlines.length < 2) {
      return;
    }
    final List<WmlInline> next = <WmlInline>[];
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is WmlRun &&
          next.isNotEmpty &&
          next.last is WmlRun &&
          _sameRun(next.last as WmlRun, inline)) {
        (next.last as WmlRun).text += inline.text;
      } else {
        next.add(inline);
      }
    }
    paragraph.inlines
      ..clear()
      ..addAll(next);
  }

  static List<int> _commentIdsAt(WmlParagraph paragraph, int index) {
    var offset = 0;
    List<int> last = const <int>[];
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is! WmlRun) {
        continue;
      }
      last = inline.commentIds;
      final int end = offset + inline.text.length;
      if (index < end) {
        return List<int>.from(inline.commentIds);
      }
      offset = end;
    }
    return List<int>.from(last);
  }

  static bool _sameRun(WmlRun a, WmlRun b) {
    return !a.isAtomic &&
        !b.isAtomic &&
        _sameProps(a.properties, b.properties) &&
        _sameLink(a.hyperlink, b.hyperlink) &&
        _sameInts(a.commentIds, b.commentIds);
  }

  static bool _sameLink(WmlHyperlink? a, WmlHyperlink? b) {
    if (a == null || b == null) return a == b;
    return a.anchor == b.anchor && a.url == b.url && a.file == b.file;
  }

  static bool _sameValues(Map<String, String>? a, Map<String, String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    return a.entries.every((entry) => b[entry.key] == entry.value);
  }

  static bool _sameInts(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _sameProps(WmlRunProps a, WmlRunProps b) {
    // Equal visible formatting is insufficient: source XML retains properties
    // such as language, direction, and proofing that the model cannot edit.
    // Import baselines and explicit defaults also affect subsequent export.
    return a.styleId == b.styleId &&
        a.sourcePropertiesXml == b.sourcePropertiesXml &&
        _sameValues(a.importedValues, b.importedValues) &&
        a.explicitProperties.length == b.explicitProperties.length &&
        a.explicitProperties.containsAll(b.explicitProperties) &&
        a.bold == b.bold &&
        a.italic == b.italic &&
        a.underline == b.underline &&
        a.strike == b.strike &&
        a.color == b.color &&
        a.highlight == b.highlight &&
        a.fontSizeHalfPoints == b.fontSizeHalfPoints &&
        a.asciiFont == b.asciiFont &&
        a.csFont == b.csFont &&
        a.vertAlign == b.vertAlign;
  }
}
