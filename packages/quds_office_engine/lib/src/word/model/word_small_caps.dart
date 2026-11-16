import '../../bidi/grapheme_clusters.dart';

/// Synthetic small capitals shared by document layout and UI previews.
///
/// The native formatting flag and authored letters remain in the document.
/// Display conversion happens per grapheme, retaining its complete UTF-16
/// source range even when Unicode uppercase mapping expands a character.
/// Capital letters, punctuation, numbers and uncased scripts keep their size.
abstract final class WordSmallCaps {
  /// A consistent synthetic fallback independent of font feature availability.
  /// DOCX consumers receive native `w:smallCaps` and may use designed glyphs.
  static const double fontScale = 0.8;

  static List<({String text, int start, int end, double scale})> segments(
    String text,
  ) => [
    for (final cluster in GraphemeClusters.segment(text))
      (
        text: cluster.text.toUpperCase(),
        start: cluster.start,
        end: cluster.end,
        scale: cluster.text.toUpperCase() == cluster.text ? 1 : fontScale,
      ),
  ];
}
