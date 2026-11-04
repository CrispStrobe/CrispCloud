import 'wml_document.dart';
import 'word_styles.dart';
import 'word_toc.dart';

/// Figure / table captions using the Caption style.
abstract final class WordCaptions {
  /// nextNumber API.
  static int nextNumber(WmlDocument document, {String label = 'Figure'}) {
    var n = 0;
    final String prefix = '$label ';
    for (final WmlParagraph paragraph in document.paragraphs) {
      if (paragraph.properties.styleId == 'Caption' &&
          paragraph.text.startsWith(prefix)) {
        n++;
      }
    }
    return n + 1;
  }

  /// Builds a caption paragraph. The host inserts it after the target.
  static WmlParagraph create(
    WmlDocument document, {
    String label = 'Figure',
    String text = '',
  }) {
    final int number = nextNumber(document, label: label);
    final String body = text.isEmpty ? '$label $number' : '$label $number: $text';
    final WmlParagraph paragraph = WmlParagraph(
      inlines: <WmlInline>[WmlRun(text: body)],
    );
    WordStyles.apply(paragraph, 'Caption');
    return paragraph;
  }

  /// tableOfFigures API.
  static WmlToc tableOfFigures(WmlDocument document, {String label = 'Figure'}) {
    final WmlToc toc = WmlToc(
      title: 'Table of $label',
      captionLabel: label,
      minLevel: 1,
      maxLevel: 9,
    );
    WordToc.refresh(toc, document);
    return toc;
  }
}
