import 'models.dart';

/// Parses human-facing page ranges into zero-based indices, retaining order.
class PdfPageRange {
  PdfPageRange._();

  /// Accepts `all`, `1`, `1-3,7`, and descending ranges such as `4-2,1`.
  /// Every number must exist; duplicates and empty components are errors.
  static List<int> parse(String expression, int pageCount,
      {bool allowDuplicates = false}) {
    if (pageCount < 1) {
      throw PdfOperationException('invalidPages', 'The PDF has no pages.');
    }
    final text = expression.trim();
    if (text.toLowerCase() == 'all') {
      return List<int>.unmodifiable(List.generate(pageCount, (i) => i));
    }
    if (text.isEmpty || text.length > 16384) {
      throw PdfOperationException(
          'invalidPages', 'Enter page numbers, ranges such as 1-3,7, or all.');
    }
    final pages = <int>[];
    final seen = <int>{};
    void add(int page) {
      if (page < 1 || page > pageCount) {
        throw PdfOperationException('invalidPages',
            'Page $page is outside the document (1–$pageCount).');
      }
      if (!seen.add(page) && !allowDuplicates) {
        throw PdfOperationException(
            'invalidPages', 'Page $page appears more than once.');
      }
      pages.add(page - 1);
    }

    final pattern = RegExp(r'^([0-9]+)(?:\s*-\s*([0-9]+))?$');
    for (final component in text.split(',')) {
      final match = pattern.firstMatch(component.trim());
      if (match == null) {
        throw PdfOperationException('invalidPages',
            'Invalid page range. Use page numbers and inclusive ranges.');
      }
      final first = int.tryParse(match.group(1)!);
      final last = int.tryParse(match.group(2) ?? match.group(1)!);
      if (first == null ||
          last == null ||
          first < 1 ||
          last < 1 ||
          first > pageCount ||
          last > pageCount) {
        throw PdfOperationException('invalidPages',
            'Every selected page must be between 1 and $pageCount.');
      }
      final step = last >= first ? 1 : -1;
      for (var page = first;; page += step) {
        add(page);
        if (page == last) break;
      }
    }
    return List<int>.unmodifiable(pages);
  }
}
