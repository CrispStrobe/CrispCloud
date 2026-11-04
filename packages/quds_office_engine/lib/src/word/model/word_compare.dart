import 'wml_document.dart';
import 'word_revision.dart';

/// Builds insert/delete revisions that turn [original] into [revised].
abstract final class WordCompare {
  /// Records paragraph-level differences on [revised].
  static WmlDocument compare(WmlDocument original, WmlDocument revised) {
    final List<WmlParagraph> a = original.paragraphs.toList();
    final List<WmlParagraph> b = revised.paragraphs.toList();
    final int n = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < n; i++) {
      final String left = a[i].text;
      final String right = b[i].text;
      if (left == right) {
        continue;
      }
      final int prefix = _commonPrefix(left, right);
      final int suffix = _commonSuffix(left.substring(prefix), right.substring(prefix));
      final String deleted = left.substring(prefix, left.length - suffix);
      final String inserted = right.substring(prefix, right.length - suffix);
      if (deleted.isNotEmpty) {
        WordRevisions.record(
          revised,
          kind: WmlRevisionKind.delete,
          paragraphIndex: i,
          start: prefix,
          end: prefix + inserted.length,
          text: deleted,
        );
      }
      if (inserted.isNotEmpty) {
        WordRevisions.record(
          revised,
          kind: WmlRevisionKind.insert,
          paragraphIndex: i,
          start: prefix,
          end: prefix + inserted.length,
          text: inserted,
        );
      }
    }
    for (int i = n; i < b.length; i++) {
      WordRevisions.record(
        revised,
        kind: WmlRevisionKind.insert,
        paragraphIndex: i,
        start: 0,
        end: b[i].text.length,
        text: b[i].text,
      );
    }
    for (int i = n; i < a.length; i++) {
      WordRevisions.record(
        revised,
        kind: WmlRevisionKind.delete,
        paragraphIndex: n == 0 ? 0 : n - 1,
        start: 0,
        end: 0,
        text: a[i].text,
      );
    }
    return revised;
  }

  static int _commonPrefix(String a, String b) {
    final int n = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < n && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  static int _commonSuffix(String a, String b) {
    final int n = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < n &&
        a.codeUnitAt(a.length - 1 - i) == b.codeUnitAt(b.length - 1 - i)) {
      i++;
    }
    return i;
  }
}
