import '../properties/wml_properties.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_bookmarks.dart';

/// Bookmark names, link look, and heading cross-references.
abstract final class WordLink {
  /// color API.
  static const String color = '0563C1';

  /// headingBookmark API.
  static String headingBookmark(String text, int level) {
    final String slug = text
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    final String safe = slug.isEmpty ? 'Heading' : slug;
    final String name = '_Heading${level.clamp(1, 9)}_$safe';
    return name.length <= 40 ? name : name.substring(0, 40);
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
    final native = WordBookmarks.ranges(document);
    final nativeNames = native.map((range) => range.name).toSet();
    final Map<WmlParagraph, int> headings = <WmlParagraph, int>{};
    for (final WmlParagraph para in paras) {
      final String style = (para.properties.styleId ?? '').trim().toLowerCase();
      if (style == 'tocheading' ||
          style == 'toc heading' ||
          RegExp(r'^toc\d$').hasMatch(style)) {
        continue;
      }
      final int? stored = para.properties.headingLevel;
      final int? level = stored != null && stored >= 1 && stored <= 9
          ? stored
          : int.tryParse(
              RegExp(
                    r'^(?:heading|عنوان)\s*([1-9])$',
                  ).firstMatch(style)?.group(1) ??
                  '',
            );
      if (level == null) {
        continue;
      }
      headings[para] = level;
    }
    // Reserve existing names before assigning any new ones, so an earlier
    // unbookmarked heading cannot steal a later imported target's identity.
    final Set<String> reserved = <String>{
      ...nativeNames,
      for (final para in paras)
        if (para.properties.bookmarkName?.isNotEmpty ?? false)
          para.properties.bookmarkName!,
    };
    final Set<String> used = <String>{
      ...nativeNames,
      for (final para in paras)
        if (!headings.containsKey(para) &&
            (para.properties.bookmarkName?.isNotEmpty ?? false))
          para.properties.bookmarkName!,
    };
    for (final entry in headings.entries) {
      final WmlParagraph para = entry.key;
      final String? existing = para.properties.bookmarkName;
      if (existing == null || existing == para.properties.sourceBookmarkName) {
        final starts = para.inlines
            .whereType<WmlBookmarkBoundary>()
            .where((boundary) => boundary.isStart && boundary.name != null)
            .toList();
        final imported =
            starts.where((boundary) => boundary.name == existing).firstOrNull ??
            starts.firstOrNull;
        if (imported != null) {
          para.properties
            ..bookmarkName = imported.name
            ..sourceBookmarkName = imported.name;
          continue;
        }
      }
      if (existing != null && existing.isNotEmpty && used.add(existing)) {
        continue;
      }
      final String base = headingBookmark(para.text, entry.value);
      String name = base;
      var suffix = 2;
      while (reserved.contains(name) || used.contains(name)) {
        final String tail = '_${suffix++}';
        final int length = base.length < 40 - tail.length
            ? base.length
            : 40 - tail.length;
        name = '${base.substring(0, length)}$tail';
      }
      para.properties.bookmarkName = name;
      reserved.add(name);
      used.add(name);
    }
  }

  /// paragraphIndexForAnchor API.
  static int? paragraphIndexForAnchor(WmlDocument document, String anchor) {
    final String name = anchor.startsWith('#') ? anchor.substring(1) : anchor;
    if (name.isEmpty) {
      return null;
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    final native = WordBookmarks.byName(document, name);
    if (native != null) {
      final index = paras.indexOf(native.startParagraph);
      return index < 0 ? null : index;
    }
    for (int i = 0; i < paras.length; i++) {
      if (WordBookmarks.generatedName(paras[i]) == name) {
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
