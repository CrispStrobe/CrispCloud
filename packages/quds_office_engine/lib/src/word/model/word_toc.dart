import '../layout/word_layout.dart';
import '../properties/wml_properties.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_link.dart';

/// Heading styles and live TOC field maintenance.
abstract final class WordToc {
  /// RegExp API.
  static final RegExp _headingStyle = RegExp(
    r'^(?:Heading|heading|عنوان)\s*(\d)$',
  );

  /// RegExp API.
  static final RegExp _tocStyle = RegExp(r'^(?:TOC|toc)(\d)$');

  /// RegExp API.
  static final RegExp _tocRange = RegExp(r'\\o\s+"(\d+)\s*-\s*(\d+)"');

  /// RegExp API.
  static final RegExp _trailingPage = RegExp(r'\s+(\d+)\s*$');

  /// headingLevelOf API.
  static int? headingLevelOf(WmlParagraph paragraph) {
    final int? stored = paragraph.properties.headingLevel;
    if (stored != null && stored >= 1 && stored <= 9) {
      return stored;
    }
    return headingLevelFromStyle(paragraph.properties.styleId);
  }

  /// headingLevelFromStyle API.
  static int? headingLevelFromStyle(String? styleId) {
    if (styleId == null || styleId.isEmpty) {
      return null;
    }
    final RegExpMatch? match = _headingStyle.firstMatch(styleId.trim());
    if (match == null) {
      return null;
    }
    final int level = int.parse(match.group(1)!);
    return level < 1 || level > 9 ? null : level;
  }

  /// tocLevelFromStyle API.
  static int? tocLevelFromStyle(String? styleId) {
    if (styleId == null || styleId.isEmpty) {
      return null;
    }
    final RegExpMatch? match = _tocStyle.firstMatch(styleId.trim());
    if (match == null) {
      return null;
    }
    return int.parse(match.group(1)!);
  }

  /// isTocHeadingStyle API.
  static bool isTocHeadingStyle(String? styleId) {
    final String id = (styleId ?? '').trim().toLowerCase();
    return id == 'tocheading' || id == 'toc heading';
  }

  /// isFieldParagraph API.
  static bool isFieldParagraph(WmlParagraph paragraph) {
    return isTocHeadingStyle(paragraph.properties.styleId) ||
        tocLevelFromStyle(paragraph.properties.styleId) != null;
  }

  /// ownsParagraph API.
  static bool ownsParagraph(WmlToc toc, WmlParagraph paragraph) {
    return identical(toc.titleParagraph, paragraph) ||
        toc.itemParagraphs.contains(paragraph);
  }

  /// isInsideToc API.
  static bool isInsideToc(WmlDocument document, WmlParagraph paragraph) {
    for (final WmlToc toc in tocs(document)) {
      if (ownsParagraph(toc, paragraph)) {
        return true;
      }
    }
    return false;
  }

  /// isTocInstruction API.
  static bool isTocInstruction(String? instruction) {
    if (instruction == null) {
      return false;
    }
    return RegExp(r'\bTOC\b', caseSensitive: false).hasMatch(instruction);
  }

  static (int min, int max) rangeFromInstruction(String? instruction) {
    if (instruction == null) {
      return (1, 3);
    }
    final RegExpMatch? match = _tocRange.firstMatch(instruction);
    if (match == null) {
      return (1, 3);
    }
    final int min = int.parse(match.group(1)!).clamp(1, 9);
    final int max = int.parse(match.group(2)!).clamp(min, 9);
    return (min, max);
  }

  /// runLook API.
  static WmlRunProps runLook(int level) {
    return switch (level) {
      1 => WmlRunProps(bold: true, fontSizeHalfPoints: 32, color: '1F4E79'),
      2 => WmlRunProps(bold: true, fontSizeHalfPoints: 26, color: '2E75B6'),
      3 => WmlRunProps(bold: true, fontSizeHalfPoints: 24, color: '2E75B6'),
      4 => WmlRunProps(
        bold: true,
        italic: true,
        fontSizeHalfPoints: 22,
        color: '404040',
      ),
      _ => WmlRunProps(fontSizeHalfPoints: 22, color: '000000'),
    };
  }

  /// applyHeading API.
  static void applyHeading(WmlParagraph paragraph, int level) {
    final int clamped = level.clamp(0, 9);
    paragraph.properties.headingLevel = clamped == 0 ? null : clamped;
    paragraph.properties.styleId = clamped == 0 ? 'Normal' : 'Heading$clamped';
    paragraph.properties.spacingBefore = switch (clamped) {
      1 => 18,
      2 => 14,
      3 => 12,
      0 => 0,
      _ => 10,
    };
    paragraph.properties.spacingAfter = clamped == 0 ? 8 : 8;
    paragraph.properties.keepTogether = clamped > 0;
    if (clamped > 0) {
      paragraph.properties.bookmarkName = WordLink.headingBookmark(
        paragraph.text,
        clamped,
      );
    }
    final WmlRunProps look = runLook(clamped);
    if (paragraph.inlines.isEmpty) {
      paragraph.inlines.add(WmlRun(properties: look.copy()));
      return;
    }
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is! WmlRun) {
        continue;
      }
      inline.properties
        ..bold = look.bold
        ..italic = look.italic
        ..fontSizeHalfPoints = look.fontSizeHalfPoints
        ..color = look.color;
    }
  }

  static bool _isCollectibleHeading(
    WmlDocument document,
    WmlParagraph paragraph, {
    required int minLevel,
    required int maxLevel,
  }) {
    if (isFieldParagraph(paragraph) || isInsideToc(document, paragraph)) {
      return false;
    }
    final int? level = headingLevelOf(paragraph);
    if (level == null || level < minLevel || level > maxLevel) {
      return false;
    }
    return paragraph.text.trim().isNotEmpty;
  }

  /// headings API.
  static List<WmlHeadingRef> headings(
    WmlDocument document, {
    int minLevel = 1,
    int maxLevel = 9,
  }) {
    final List<WmlHeadingRef> found = <WmlHeadingRef>[];
    final List<WmlParagraph> paras = document.paragraphs.toList();
    for (int i = 0; i < paras.length; i++) {
      final WmlParagraph para = paras[i];
      if (!_isCollectibleHeading(
        document,
        para,
        minLevel: minLevel,
        maxLevel: maxLevel,
      )) {
        continue;
      }
      found.add(
        WmlHeadingRef(
          index: i,
          level: headingLevelOf(para)!,
          text: para.text.trim(),
        ),
      );
    }
    return found;
  }

  /// tocs API.
  static Iterable<WmlToc> tocs(WmlDocument document) sync* {
    for (final WmlSection section in document.sections) {
      for (final WmlBlock block in section.blocks) {
        if (block is WmlToc) {
          yield block;
        }
      }
    }
  }

  /// refreshAll API.
  static void refreshAll(WmlDocument document) {
    for (final WmlToc toc in tocs(document)) {
      refresh(toc, document);
    }
  }

  /// Fills a TOC that has never been built so a newly opened document shows entries.
  static void refreshEmpty(WmlDocument document) {
    for (final WmlToc toc in tocs(document)) {
      if (toc.entries.isEmpty) {
        refresh(toc, document);
      }
    }
  }

  /// Points each TOC entry at the live heading paragraph so page sync works
  /// after a file open (absorbed entries store ordinals, not paragraph indexes).
  static void rebindHeadings(WmlDocument document) {
    final List<WmlParagraph> all = document.paragraphs.toList();
    for (final WmlToc toc in tocs(document)) {
      final List<WmlParagraph> headings = <WmlParagraph>[
        for (final WmlParagraph paragraph in all)
          if (_isCollectibleHeading(
            document,
            paragraph,
            minLevel: toc.minLevel,
            maxLevel: toc.maxLevel,
          ))
            paragraph,
      ];
      for (int i = 0; i < toc.entries.length; i++) {
        final WmlTocEntry entry = toc.entries[i];
        WmlParagraph? match;
        if (i < headings.length && headings[i].text.trim() == entry.text) {
          match = headings[i];
        } else {
          for (final WmlParagraph heading in headings) {
            if (heading.text.trim() == entry.text &&
                headingLevelOf(heading) == entry.level) {
              match = heading;
              break;
            }
          }
        }
        if (match != null) {
          entry.headingParagraphIndex = all.indexOf(match);
          final String? bookmark = match.properties.bookmarkName;
          if (bookmark != null &&
              bookmark.isNotEmpty &&
              i < toc.itemParagraphs.length) {
            for (final WmlInline inline in toc.itemParagraphs[i].inlines) {
              if (inline is WmlRun) {
                inline.hyperlink = WmlHyperlink(anchor: bookmark);
              }
            }
          }
        }
      }
    }
  }

  /// ensureBody API.
  static void ensureBody(WmlToc toc) {
    if (toc.itemParagraphs.isEmpty && toc.entries.isNotEmpty) {
      toc.itemParagraphs.addAll(<WmlParagraph>[
        for (final WmlTocEntry entry in toc.entries) entryParagraph(entry),
      ]);
    }
  }

  /// refresh API.
  static void refresh(WmlToc toc, WmlDocument document) {
    final String titleText = toc.titleParagraph.text.trim();
    if (titleText.isNotEmpty) {
      toc.title = titleText;
    }
    final String? caption = toc.captionLabel;
    final List<WmlParagraph> headingParas = caption == null
        ? <WmlParagraph>[
            for (final WmlParagraph paragraph in document.paragraphs)
              if (_isCollectibleHeading(
                document,
                paragraph,
                minLevel: toc.minLevel,
                maxLevel: toc.maxLevel,
              ))
                paragraph,
          ]
        : <WmlParagraph>[
            for (final WmlParagraph paragraph in document.paragraphs)
              if (paragraph.properties.styleId == 'Caption' &&
                  paragraph.text.startsWith(caption) &&
                  paragraph.text.trim().isNotEmpty)
                paragraph,
          ];
    final Map<(String, int), int> previousPages = <(String, int), int>{
      for (final WmlTocEntry entry in toc.entries)
        (entry.text, entry.level): entry.pageNumber,
    };
    toc.entries
      ..clear()
      ..addAll(<WmlTocEntry>[
        for (final WmlParagraph heading in headingParas)
          WmlTocEntry(
            text: heading.text.trim(),
            level: caption == null ? headingLevelOf(heading)! : 1,
            headingParagraphIndex: 0,
            pageNumber:
                previousPages[(
                  heading.text.trim(),
                  caption == null ? headingLevelOf(heading)! : 1,
                )] ??
                1,
          ),
      ]);
    toc.itemParagraphs
      ..clear()
      ..addAll(<WmlParagraph>[
        for (int i = 0; i < toc.entries.length; i++)
          entryParagraph(
            toc.entries[i],
            link: WmlHyperlink(
              anchor:
                  headingParas[i].properties.bookmarkName ??
                  headingParas[i].text.trim(),
            ),
          ),
      ]);
    final List<WmlParagraph> all = document.paragraphs.toList();
    for (int i = 0; i < headingParas.length; i++) {
      toc.entries[i].headingParagraphIndex = all.indexOf(headingParas[i]);
    }
  }

  /// syncPageNumbers API.
  static bool syncPageNumbers(WmlDocument document, LaidOutDocument laidOut) {
    final Map<int, int> pages = <int, int>{};
    for (final LaidOutPage page in laidOut.pages) {
      for (final LaidOutLine line in page.lines) {
        if (line.paragraphIndex < 0 || pages.containsKey(line.paragraphIndex)) {
          continue;
        }
        pages[line.paragraphIndex] = page.index + 1;
      }
    }
    var changed = false;
    for (final WmlToc toc in tocs(document)) {
      for (final WmlTocEntry entry in toc.entries) {
        final int next = pages[entry.headingParagraphIndex] ?? entry.pageNumber;
        if (next != entry.pageNumber) {
          entry.pageNumber = next;
          changed = true;
        }
      }
    }
    return changed;
  }

  /// titleParagraph API.
  static WmlParagraph titleParagraph(WmlToc toc) => toc.titleParagraph;

  /// entryParagraph API.
  static WmlParagraph entryParagraph(WmlTocEntry entry, {WmlHyperlink? link}) {
    return WmlParagraph(
      properties: WmlParagraphProps(
        styleId: 'TOC${entry.level}',
        spacingAfter: 4,
        spacingBefore: 0,
        indent: WmlIndent(left: (entry.level - 1) * 18.0),
      ),
      inlines: <WmlInline>[
        WmlRun(
          text: entry.text,
          properties: WmlRunProps(fontSizeHalfPoints: 22, color: '2E75B6'),
          hyperlink: link,
        ),
      ],
    );
  }

  /// absorbResult API.
  static void absorbResult(WmlToc toc, WmlParagraph paragraph) {
    if (isTocHeadingStyle(paragraph.properties.styleId)) {
      final String text = paragraph.text.trim();
      if (text.isNotEmpty) {
        toc.title = text;
      }
      toc.titleParagraph = paragraph;
      return;
    }
    if (isTocInstruction(paragraph.properties.fieldInstruction) &&
        paragraph.text.trim().isEmpty) {
      return;
    }
    final String original = paragraph.text;
    final String raw = original.replaceAll('\t', ' ').trim();
    if (raw.isEmpty) {
      return;
    }
    final RegExpMatch? page = _trailingPage.firstMatch(raw);
    final String text = page == null
        ? raw
        : raw.substring(0, page.start).trim();
    if (text.isEmpty) {
      return;
    }
    _keepPrefix(paragraph, text);
    final int level =
        tocLevelFromStyle(paragraph.properties.styleId) ??
        ((paragraph.properties.indent.left / 18).round() + 1).clamp(1, 9);
    toc.entries.add(
      WmlTocEntry(
        text: text,
        level: level,
        headingParagraphIndex: toc.entries.length,
        pageNumber: page == null ? 1 : int.parse(page.group(1)!),
      ),
    );
    toc.itemParagraphs.add(paragraph);
  }

  static void _keepPrefix(WmlParagraph paragraph, String prefix) {
    final String text = paragraph.text;
    if (prefix.isEmpty || text == prefix) {
      return;
    }
    final int at = text.indexOf(prefix);
    if (at < 0) {
      return;
    }
    if (at + prefix.length < text.length) {
      WmlRunEdit.replaceRange(paragraph, at + prefix.length, text.length, '');
    }
    if (at > 0) {
      WmlRunEdit.replaceRange(paragraph, 0, at, '');
    }
  }

  /// Right-aligned X of a TOC page number.
  static double pageNumberX({
    required double pageWidth,
    required double marginRight,
    required double numberWidth,
  }) {
    return (pageWidth - marginRight - numberWidth).clamp(0, pageWidth);
  }

  /// Where dotted leaders stop — just before the page number.
  static double leaderEndX({
    required double pageWidth,
    required double marginRight,
    required double numberWidth,
    double gap = 4,
  }) {
    return (pageWidth - marginRight - numberWidth - gap).clamp(0, pageWidth);
  }
}

/// Class WmlHeadingRef.
class WmlHeadingRef {
  /// WmlHeadingRef API.
  const WmlHeadingRef({
    required this.index,
    required this.level,
    required this.text,
  });

  /// index API.
  final int index;

  /// level API.
  final int level;

  /// text API.
  final String text;
}
