import '../../bidi/grapheme_clusters.dart';

part 'word_small_caps_case_data.dart';

/// Synthetic capitals shared by document layout and UI previews.
///
/// The native formatting flag and authored letters remain in the document.
/// Display conversion happens per grapheme, retaining its complete UTF-16
/// source range even when Unicode uppercase mapping expands a character.
/// Small capitals reduce lowercase letters; all capitals retain the full size.
/// Capital letters, punctuation, numbers and uncased scripts keep their size.
abstract final class WordSmallCaps {
  /// A consistent synthetic fallback independent of font feature availability.
  /// DOCX consumers receive native `w:smallCaps` and may use designed glyphs.
  static const double fontScale = 0.8;

  /// Uppercase display graphemes with their original source ranges.
  ///
  /// [allCaps] uses full-size capitals, including lowercase expansions. The
  /// default retains the existing synthetic small-capital behavior.
  static List<({String text, int start, int end, double scale})> segments(
    String text, {
    bool allCaps = false,
  }) {
    final result = <({String text, int start, int end, double scale})>[];
    for (final cluster in GraphemeClusters.segment(text)) {
      final upper = _uppercase(cluster.text);
      result.add((
        text: upper,
        start: cluster.start,
        end: cluster.end,
        scale:
            !allCaps &&
                upper != cluster.text &&
                cluster.text.toLowerCase() == cluster.text
            ? fontScale
            : 1,
      ));
    }
    return result;
  }

  // Dart's simple case conversion omits expansions such as ß → SS. Use the
  // Unicode default full uppercase mapping, without locale-specific tailoring.
  // Defer Greek iota-subscript expansions until after the cluster's marks, so
  // an accent stays on its original base rather than the appended capital iota.
  static String _uppercase(String text) {
    final result = StringBuffer();
    var trailingIotas = 0;
    for (final cp in text.runes) {
      final expansion = _fullUppercaseExpansions[cp];
      if (cp == 0x0345) {
        trailingIotas++;
      } else if (expansion != null &&
          cp >= 0x1f80 &&
          cp <= 0x1ffc &&
          expansion.endsWith('\u0399')) {
        result.write(expansion.substring(0, expansion.length - 1));
        trailingIotas++;
      } else {
        result.write(expansion ?? String.fromCharCode(cp).toUpperCase());
      }
    }
    for (var i = 0; i < trailingIotas; i++) {
      result.write('\u0399');
    }
    return result.toString();
  }
}
