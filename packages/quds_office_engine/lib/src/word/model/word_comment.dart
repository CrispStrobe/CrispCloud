import 'wml_document.dart';
import 'wml_run_edit.dart';

/// Review comments attached to text runs.
abstract final class WordComment {
  /// idsAt API.
  static List<int> idsAt(WmlParagraph paragraph, int index) {
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

  /// byId API.
  static WmlComment? byId(WmlDocument document, int id) {
    for (final WmlComment comment in document.comments) {
      if (comment.id == id) {
        return comment;
      }
    }
    return null;
  }

  /// nextId API.
  static int nextId(WmlDocument document) {
    var maxId = -1;
    for (final WmlComment comment in document.comments) {
      if (comment.id > maxId) {
        maxId = comment.id;
      }
    }
    return maxId + 1;
  }

  static ({int paragraphIndex, int start, int end})? rangeOf(
    WmlDocument document,
    int id,
  ) {
    final List<WmlParagraph> paras = document.paragraphs.toList();
    for (int p = 0; p < paras.length; p++) {
      var offset = 0;
      int? start;
      var end = 0;
      for (final WmlInline inline in paras[p].inlines) {
        if (inline is! WmlRun) {
          continue;
        }
        final int runEnd = offset + inline.text.length;
        if (inline.commentIds.contains(id)) {
          start ??= offset;
          end = runEnd;
        } else if (start != null) {
          return (paragraphIndex: p, start: start, end: end);
        }
        offset = runEnd;
      }
      if (start != null) {
        return (paragraphIndex: p, start: start, end: end);
      }
    }
    return null;
  }

  /// applyRange API.
  static void applyRange(WmlParagraph paragraph, int start, int end, int id) {
    final int length = paragraph.text.length;
    start = start.clamp(0, length);
    end = end.clamp(0, length);
    if (start > end) {
      final int swap = start;
      start = end;
      end = swap;
    }
    if (start == end) {
      if (paragraph.inlines.whereType<WmlRun>().isEmpty) {
        paragraph.inlines.add(WmlRun(commentIds: <int>[id]));
        return;
      }
      end = (start + 1).clamp(0, length);
      if (start == end) {
        start = (end - 1).clamp(0, length);
      }
    }
    WmlRunEdit.splitAt(paragraph, end);
    WmlRunEdit.splitAt(paragraph, start);
    var offset = 0;
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is! WmlRun) {
        continue;
      }
      final int runEnd = offset + inline.text.length;
      if (offset >= start && runEnd <= end && !inline.commentIds.contains(id)) {
        inline.commentIds.add(id);
      }
      offset = runEnd;
    }
    WmlRunEdit.coalesce(paragraph);
  }

  /// applyDocumentRange API.
  static void applyDocumentRange(
    WmlDocument document, {
    required int startPara,
    required int startIdx,
    required int endPara,
    required int endIdx,
    required int id,
  }) {
    final List<WmlParagraph> paras = document.paragraphs.toList();
    if (paras.isEmpty) {
      return;
    }
    final int fromP = startPara.clamp(0, paras.length - 1);
    final int toP = endPara.clamp(0, paras.length - 1);
    for (int p = fromP; p <= toP; p++) {
      final int from = p == fromP ? startIdx : 0;
      final int to = p == toP ? endIdx : paras[p].text.length;
      applyRange(paras[p], from, to, id);
    }
  }

  /// roots API.
  static List<WmlComment> roots(WmlDocument document) {
    return <WmlComment>[
      for (final WmlComment comment in document.comments)
        if (comment.parentId == null) comment,
    ];
  }

  /// repliesOf API.
  static List<WmlComment> repliesOf(WmlDocument document, int id) {
    return <WmlComment>[
      for (final WmlComment comment in document.comments)
        if (comment.parentId == id) comment,
    ];
  }

  /// threadRootId API.
  static int threadRootId(WmlDocument document, int id) {
    WmlComment? current = byId(document, id);
    final Set<int> seen = <int>{};
    while (current != null &&
        current.parentId != null &&
        seen.add(current.id)) {
      current = byId(document, current.parentId!);
    }
    return current?.id ?? id;
  }

  /// removeId API.
  static void removeId(WmlDocument document, int id) {
    final List<int> drop = <int>[id];
    if (byId(document, id)?.parentId == null) {
      for (final WmlComment reply in repliesOf(document, id)) {
        drop.add(reply.id);
      }
    }
    document.comments.removeWhere(
      (WmlComment comment) => drop.contains(comment.id),
    );
    for (final WmlParagraph paragraph in document.paragraphs) {
      for (final WmlInline inline in paragraph.inlines) {
        if (inline is WmlRun) {
          inline.commentIds.removeWhere(drop.contains);
        }
      }
    }
  }
}
