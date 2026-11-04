import '../properties/wml_properties.dart';
import 'wml_document.dart';
import 'word_fields.dart';

/// Citation / bibliography / index helpers.
abstract final class WordCitations {
  /// insert API.
  static void insert(
    WmlDocument document,
    WmlParagraph paragraph,
    WmlCitation citation,
  ) {
    document.citations.removeWhere((WmlCitation c) => c.tag == citation.tag);
    document.citations.add(citation);
    paragraph.properties.fieldInstruction = WordFields.instructionOf(
      WmlFieldKind.citation,
      argument: citation.tag,
    );
    paragraph.inlines.add(WmlRun(text: ' ${citation.inText}'));
  }

  /// bibliography API.
  static WmlParagraph bibliography(
    WmlDocument document, {
    String title = 'Bibliography',
  }) {
    final List<WmlCitation> items = List<WmlCitation>.from(document.citations)
      ..sort((WmlCitation a, WmlCitation b) => a.author.compareTo(b.author));
    final String body = <String>[
      title,
      for (final WmlCitation item in items) item.bibliographyLine,
    ].join('\n');
    return WmlParagraph(
      properties: WmlParagraphProps(styleId: 'Bibliography'),
      inlines: <WmlInline>[WmlRun(text: body)],
    );
  }

  /// markIndex API.
  static void markIndex(
    WmlDocument document,
    WmlParagraph paragraph,
    String term,
  ) {
    final int index = document.paragraphs.toList().indexOf(paragraph);
    document.indexMarks.add(
      WmlIndexMark(term: term, paragraphIndex: index < 0 ? 0 : index),
    );
  }

  /// Builds a sorted index paragraph from marked terms.
  static WmlParagraph index(WmlDocument document, {String title = 'Index'}) {
    final Map<String, Set<int>> pages = <String, Set<int>>{};
    for (final WmlIndexMark mark in document.indexMarks) {
      pages.putIfAbsent(mark.term, () => <int>{}).add(mark.paragraphIndex + 1);
    }
    final List<String> keys = pages.keys.toList()..sort();
    final String body = <String>[
      title,
      for (final String key in keys)
        '$key\t${(pages[key]!.toList()..sort()).join(', ')}',
    ].join('\n');
    final WmlParagraph paragraph = WmlParagraph(
      properties: WmlParagraphProps(styleId: 'Index'),
      inlines: <WmlInline>[WmlRun(text: body)],
    );
    WordFields.stamp(paragraph, WmlFieldKind.indexList, result: body);
    return paragraph;
  }
}
