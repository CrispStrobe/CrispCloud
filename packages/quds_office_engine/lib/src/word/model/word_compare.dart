import 'wml_document.dart';
import 'word_comparison.dart';

/// Compatibility entry point for read-only document comparison.
abstract final class WordCompare {
  /// Produces a bounded report without modifying either input.
  static WordComparisonResult diff(
    WmlDocument original,
    WmlDocument revised, {
    WordComparisonOptions options = const WordComparisonOptions(),
  }) => WordDocumentComparison.compare(original, revised, options: options);

  /// The former mutation API could record deleted text that was absent from
  /// the revised document and overlapping insert/delete ranges. It could not
  /// represent deleted paragraphs, so accepting its results could lose text.
  /// Use [diff] to review two documents and the revision API to review actual
  /// imported or authored tracked changes. Neither input is touched here.
  @Deprecated(
    'Use WordCompare.diff or WordDocumentComparison.compare for a read-only report.',
  )
  static WmlDocument compare(WmlDocument original, WmlDocument revised) {
    throw UnsupportedError(
      'WordCompare.compare no longer generates unsafe synthetic revisions. '
      'Use WordCompare.diff or WordDocumentComparison.compare for a read-only '
      'comparison. Review existing tracked changes with WordRevisions.',
    );
  }
}
