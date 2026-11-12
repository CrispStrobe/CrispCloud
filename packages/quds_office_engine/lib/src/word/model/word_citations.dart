import '../properties/wml_properties.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_fields.dart';

/// Citation / bibliography / index helpers.
abstract final class WordCitations {
  /// insert API.
  static void insert(
    WmlDocument document,
    WmlParagraph paragraph,
    WmlCitation citation, {
    int? index,
  }) {
    if (paragraph.properties.fieldInstruction?.trim().isNotEmpty == true ||
        paragraph.properties.pageNumberField) {
      throw UnsupportedError(
        'Insert an inline citation in an ordinary paragraph; this paragraph '
        'is already modeled as a whole-paragraph field.',
      );
    }
    document.citations.removeWhere((WmlCitation c) => c.tag == citation.tag);
    document.citations.add(citation);
    final String text = paragraph.text;
    final int requested = index ?? text.length;
    final int at = WmlRunEdit.normalizeRange(
      paragraph,
      requested,
      requested,
    ).start;
    final WmlRunProps properties = WmlRunEdit.propsAt(
      paragraph,
      at == text.length ? at - 1 : at,
    ).copy();
    final whitespace = RegExp(r'\s');
    WmlRunEdit.insertRuns(paragraph, at, <WmlRun>[
      if (at > 0 && !whitespace.hasMatch(text[at - 1]))
        WmlRun(text: ' ', properties: properties.copy()),
      WmlRun(
        text: citation.inText,
        properties: properties,
        fieldInstruction: WordFields.instructionOf(
          WmlFieldKind.citation,
          argument: citation.tag,
        ),
      ),
      if (at < text.length && !whitespace.hasMatch(text[at]))
        WmlRun(text: ' ', properties: properties.copy()),
    ]);
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
