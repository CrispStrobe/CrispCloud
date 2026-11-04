import '../properties/wml_properties.dart';
import 'wml_document.dart';

/// Multilevel list scheme (1 / 1.1 / أ).
abstract final class WordLists {
  /// Applies outline numbering at [level] (0–8) using [numId] 1 (bullets)
  /// or 2 (numbers).
  static void applyLevel(
    WmlParagraph paragraph, {
    required bool numbered,
    int level = 0,
  }) {
    final int safe = level.clamp(0, 8);
    paragraph.properties
      ..numId = numbered ? 2 : 1
      ..ilvl = safe
      ..listLabel = numbered ? _numberLabel(safe) : _bulletLabel(safe)
      ..indent = WmlIndent(left: 18.0 + safe * 18);
  }

  /// Restarts numbering for [paragraph]'s list at the current level.
  ///
  /// Sets [WmlParagraphProps.listRestart] so serializers/deserializers can
  /// emit `lvlOverride` / treat the item as a fresh counter.
  static void restart(WmlParagraph paragraph, {int? at}) {
    if (paragraph.properties.numId == null) {
      return;
    }
    paragraph.properties.listRestart = at ?? 1;
  }

  /// clear API.
  static void clear(WmlParagraph paragraph) {
    paragraph.properties
      ..numId = null
      ..ilvl = 0
      ..listLabel = null
      ..listRestart = null;
  }

  /// increment API.
  static void changeLevel(WmlParagraph paragraph, int delta) {
    if (paragraph.properties.numId == null) {
      return;
    }
    applyLevel(
      paragraph,
      numbered: paragraph.properties.numId == 2,
      level: paragraph.properties.ilvl + delta,
    );
  }

  /// Recomputes `listLabel` for consecutive numbered paragraphs in [story].
  ///
  /// Higher-level increments reset deeper levels (Word multilevel behaviour).
  static void resolveLabels(Iterable<WmlParagraph> story) {
    final Map<int, List<int>> counters = <int, List<int>>{};
    for (final WmlParagraph paragraph in story) {
      final int? numId = paragraph.properties.numId;
      if (numId == null) {
        continue;
      }
      final int ilvl = paragraph.properties.ilvl.clamp(0, 8);
      final bool numbered = numId == 2 || !(_looksBullet(paragraph));
      if (!numbered) {
        paragraph.properties.listLabel = _bulletLabel(ilvl);
        continue;
      }
      final List<int> stack = counters.putIfAbsent(
        numId,
        () => List<int>.filled(9, 0),
      );
      final int? restart = paragraph.properties.listRestart;
      if (restart != null) {
        stack[ilvl] = restart - 1;
        for (int i = ilvl + 1; i < stack.length; i++) {
          stack[i] = 0;
        }
        paragraph.properties.listRestart = null;
      }
      stack[ilvl] = stack[ilvl] + 1;
      for (int i = ilvl + 1; i < stack.length; i++) {
        stack[i] = 0;
      }
      paragraph.properties.listLabel = _formatOutline(stack, ilvl);
    }
  }

  static bool _looksBullet(WmlParagraph paragraph) {
    final String? label = paragraph.properties.listLabel;
    if (label == null || label.isEmpty) {
      return paragraph.properties.numId == 1;
    }
    final String t = label.trim();
    return t == '•' || t == '◦' || t == '▪' || t == 'o';
  }

  static String _formatOutline(List<int> stack, int ilvl) {
    if (ilvl == 0) {
      return '${stack[0]}. ';
    }
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i <= ilvl; i++) {
      if (i > 0) {
        buffer.write('.');
      }
      buffer.write(stack[i] == 0 ? 1 : stack[i]);
    }
    buffer.write(' ');
    return buffer.toString();
  }

  static String _numberLabel(int level) {
    return switch (level) {
      0 => '1. ',
      1 => '1.1 ',
      2 => '1.1.1 ',
      _ => '${List<String>.filled(level + 1, '1').join('.')}. ',
    };
  }

  static String _bulletLabel(int level) {
    return switch (level) {
      0 => '• ',
      1 => '◦ ',
      _ => '▪ ',
    };
  }
}
