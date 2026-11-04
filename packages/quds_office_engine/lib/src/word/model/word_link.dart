import '../properties/wml_properties.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';

/// Bookmark names, link look, and heading cross-references.
abstract final class WordLink {
  /// color API.
  static const String color = '0563C1';

  /// headingBookmark API.
  static String headingBookmark(String text, int level) {
    final String slug = text
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^\w\u0600-\u06FF\-_]'), '');
    final String safe = slug.isEmpty ? 'Heading' : slug;
    return '_Heading${level.clamp(1, 9)}_$safe';
  }

  /// applyLook API.
  static void applyLook(WmlRun run) {
    run.properties
      ..color = color
      ..underline = WmlUnderline.single;
  }

  /// linkedRun API.
  static WmlRun linkedRun(String text, WmlHyperlink link) {
    final WmlRun run = WmlRun(text: text, hyperlink: link);
    applyLook(run);
    return run;
  }

  /// ensureHeadingBookmarks API.
  static void ensureHeadingBookmarks(WmlDocument document) {
    final List<WmlParagraph> paras = document.paragraphs.toList();
    for (int i = 0; i < paras.length; i++) {
      final WmlParagraph para = paras[i];
      final String style = (para.properties.styleId ?? '').trim().toLowerCase();
      if (style == 'tocheading' ||
          style == 'toc heading' ||
          RegExp(r'^toc\d$').hasMatch(style)) {
        continue;
      }
      final int? level = para.properties.headingLevel;
      if (level == null) {
        continue;
      }
      para.properties.bookmarkName ??= headingBookmark(para.text, level);
    }
  }

  /// paragraphIndexForAnchor API.
  static int? paragraphIndexForAnchor(WmlDocument document, String anchor) {
    final String name = anchor.startsWith('#') ? anchor.substring(1) : anchor;
    if (name.isEmpty) {
      return null;
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    for (int i = 0; i < paras.length; i++) {
      if (paras[i].properties.bookmarkName == name) {
        return i;
      }
    }
    final String needle = name.toLowerCase();
    for (int i = 0; i < paras.length; i++) {
      final String text = paras[i].text.trim().toLowerCase();
      if (text.isNotEmpty &&
          (text == needle || name.endsWith(text.replaceAll(' ', '_')))) {
        return i;
      }
    }
    return null;
  }

  /// firstIn API.
  static WmlHyperlink? firstIn(WmlParagraph paragraph) {
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is WmlRun && inline.hyperlink != null) {
        return inline.hyperlink;
      }
    }
    return null;
  }

  /// at API.
  static WmlHyperlink? at(WmlParagraph paragraph, int index) {
    var offset = 0;
    WmlHyperlink? last;
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is! WmlRun) {
        continue;
      }
      last = inline.hyperlink ?? last;
      final int end = offset + inline.text.length;
      if (index < end) {
        return inline.hyperlink;
      }
      offset = end;
    }
    return last;
  }

  /// applyRange API.
  static void applyRange(
    WmlParagraph paragraph,
    int start,
    int end,
    WmlHyperlink link,
  ) {
    WmlRunEdit.splitAt(paragraph, end);
    WmlRunEdit.splitAt(paragraph, start);
    var offset = 0;
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is! WmlRun) {
        continue;
      }
      final int runEnd = offset + inline.text.length;
      if (offset >= start && runEnd <= end && inline.text.isNotEmpty) {
        inline.hyperlink = link;
        applyLook(inline);
      }
      offset = runEnd;
    }
  }
}
