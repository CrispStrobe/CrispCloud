import '../layout/word_layout.dart';
import '../properties/wml_properties.dart';
import 'wml_clone.dart';
import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_link.dart';
import 'word_tree.dart';

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

  /// Reads the native TOC page-number suppression switch without losing a
  /// partial level range. An unqualified \\n suppresses all entry numbers.
  static void applyPageNumberInstruction(WmlToc toc, String? instruction) {
    toc
      ..showPageNumbers = true
      ..omitPageNumbersFromLevel = null
      ..omitPageNumbersThroughLevel = null;
    final Match? match = RegExp(
      r'\\n\b(?:\s+"?([1-9])(?:-([1-9]))?"?)?',
      caseSensitive: false,
    ).firstMatch(instruction ?? '');
    if (match == null) return;
    final String? first = match.group(1);
    if (first == null) {
      toc.showPageNumbers = false;
      return;
    }
    final int start = int.parse(first);
    final int end = int.parse(match.group(2) ?? first);
    if (end >= start) {
      toc
        ..omitPageNumbersFromLevel = start
        ..omitPageNumbersThroughLevel = end;
    }
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
      paragraph.properties.bookmarkName ??= WordLink.headingBookmark(
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
      for (final WmlBlock block in WordTree.descendants(section.blocks)) {
        if (block is WmlToc) {
          yield block;
        }
      }
    }
  }

  /// refreshAll API.
  static void refreshAll(WmlDocument document) {
    final targets = tocs(document).toList();
    for (final toc in targets) {
      assertCanRefresh(toc);
    }
    for (final toc in targets) {
      refresh(toc, document);
    }
  }

  /// Fills a TOC that has never been built so a newly opened document shows entries.
  static void refreshEmpty(WmlDocument document) {
    final targets = tocs(document).where((toc) => toc.entries.isEmpty).toList();
    for (final toc in targets) {
      assertCanRefresh(toc);
    }
    for (final toc in targets) {
      refresh(toc, document);
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
    assertCanRefresh(toc);
    toc.sourcePresentation = null;
    // Native headings need durable, unique targets even when the caller is a
    // script or engine client rather than the editor's relayout path.
    WordLink.ensureHeadingBookmarks(document);
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
          properties: WmlRunProps(
            fontSizeHalfPoints: 22,
            color: '2E75B6',
            underline: link == null ? WmlUnderline.none : WmlUnderline.single,
          ),
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
    final int level =
        tocLevelFromStyle(paragraph.properties.styleId) ??
        ((paragraph.properties.indent.left / 18).round() + 1).clamp(1, 9);
    final RegExpMatch? page = toc.showsPageNumberForLevel(level)
        ? _trailingPage.firstMatch(raw)
        : null;
    final String text = page == null
        ? raw
        : raw.substring(0, page.start).trim();
    if (text.isEmpty) {
      return;
    }
    _keepPrefix(paragraph, text);
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

  static (int, int, bool, int?, int?, String?) _configuration(WmlToc toc) => (
    toc.minLevel,
    toc.maxLevel,
    toc.showPageNumbers,
    toc.omitPageNumbersFromLevel,
    toc.omitPageNumbersThroughLevel,
    toc.captionLabel,
  );

  /// Records the native paragraph before the editor separates title and page
  /// suffix. This is parsed content, so later edits still come from live items.
  static void absorbNativeResult(WmlToc toc, WmlParagraph paragraph) {
    final source = WmlClone.paragraph(paragraph);
    final index = toc.itemParagraphs.length;
    absorbResult(toc, paragraph);
    final title = identical(toc.titleParagraph, paragraph);
    final entry = toc.itemParagraphs.length > index;
    final start = entry ? source.text.indexOf(paragraph.text) : 0;
    final end = entry ? start + paragraph.text.length : 0;
    final match = entry && toc.showsPageNumberForLevel(toc.entries[index].level)
        ? RegExp(r'\s+(\d+)\s*$').firstMatch(source.text)
        : null;
    final pageStart = match == null
        ? null
        : source.text.lastIndexOf(match.group(1)!, match.end - 1);
    final presentation = toc.sourcePresentation ??= WmlTocPresentation(
      configuration: _configuration(toc),
      paragraphs: [],
    );
    presentation.configuration = _configuration(toc);
    presentation.paragraphs.add(
      WmlTocSourceParagraph(
        paragraph: source,
        title: title,
        entryIndex: entry ? index : null,
        textStart: start,
        textEnd: end,
        pageStart: pageStart,
        pageEnd: pageStart == null ? null : pageStart + match!.group(1)!.length,
      ),
    );
  }

  /// Rebuilds native cache paragraphs from the current editable title/items and
  /// page values. Imported suffix runs keep their formatting and tab omission.
  /// Changing TOC settings or rebuilding its entries selects generated output.
  static List<WmlParagraph>? nativeParagraphs(WmlToc toc) {
    final presentation = toc.sourcePresentation;
    if (presentation == null) return null;
    if (presentation.configuration != _configuration(toc)) {
      assertCanRefresh(toc);
      return null;
    }
    final sources = presentation.paragraphs;
    final entryCount = sources.where((p) => p.entryIndex != null).length;
    if (entryCount != toc.itemParagraphs.length ||
        entryCount != toc.entries.length ||
        sources.any((p) => p.textStart < 0)) {
      assertCanRefresh(toc);
      return null;
    }
    return [for (final source in sources) _nativeParagraph(toc, source)];
  }

  static WmlParagraph _nativeParagraph(
    WmlToc toc,
    WmlTocSourceParagraph source,
  ) {
    if (source.title) return WmlClone.paragraph(toc.titleParagraph);
    final index = source.entryIndex;
    if (index == null) return WmlClone.paragraph(source.paragraph);
    final paragraph = WmlClone.paragraph(toc.itemParagraphs[index]);
    final native = WmlClone.paragraph(source.paragraph);
    final pageText = '${toc.entries[index].pageNumber}';
    if (source.pageStart != null &&
        source.pageEnd != null &&
        native.text.substring(source.pageStart!, source.pageEnd!) != pageText) {
      WmlRunEdit.replaceRange(
        native,
        source.pageStart!,
        source.pageEnd!,
        pageText,
      );
    }
    final sides = _nativeSides(native, source.textStart, source.textEnd);
    // Text trimming keeps zero-width ranges in the editable item. Endpoints
    // owned by the preserved leading/suffix content move back there exactly
    // once, while endpoints inside the live title retain their edited offsets.
    paragraph.inlines.removeWhere(
      (inline) => sides.moved.contains(_boundaryKey(inline)),
    );
    paragraph.inlines.insertAll(0, sides.prefix);
    paragraph.inlines.addAll(sides.suffix);
    paragraph.properties
      ..fieldInstruction = source.paragraph.properties.fieldInstruction
      ..fieldBegin = source.paragraph.properties.fieldBegin
      ..fieldSeparate = source.paragraph.properties.fieldSeparate
      ..fieldEnd = source.paragraph.properties.fieldEnd;
    return paragraph;
  }

  /// Rebuilding a native cache needs range remapping. Call before changing
  /// settings or heading bookmarks so the unsupported operation stays atomic.
  static void assertCanRefresh(WmlToc toc) {
    bool hasRanges(WmlParagraph paragraph) => paragraph.inlines.any(
      (inline) =>
          inline is WmlBookmarkBoundary || inline is WmlContentControlBoundary,
    );
    if (toc.itemParagraphs.any(hasRanges) ||
        (toc.sourcePresentation?.paragraphs.any(
              (source) => !source.title && hasRanges(source.paragraph),
            ) ??
            false)) {
      throw UnsupportedError(
        'Regenerating a TOC with native bookmark or content-control cache '
        'ranges requires remapping those ranges. Edit the existing title, '
        'formatting or page values without rebuilding its cache.',
      );
    }
  }

  static Object? _boundaryKey(WmlInline inline) => switch (inline) {
    WmlBookmarkBoundary() => ('bookmark', inline.id, inline.isStart),
    WmlContentControlBoundary() => ('control', inline.control, inline.start),
    _ => null,
  };

  static Object? _rangeKey(WmlInline inline) => switch (inline) {
    WmlBookmarkBoundary() => (
      'bookmark',
      BigInt.tryParse(inline.id) ?? inline.id,
    ),
    WmlContentControlBoundary() => ('control', inline.control),
    _ => null,
  };

  static bool _startsRange(WmlInline inline) => switch (inline) {
    WmlBookmarkBoundary() => inline.isStart,
    WmlContentControlBoundary() => inline.start,
    _ => false,
  };

  /// This composes one complete paragraph; it is not a user paragraph split.
  /// A control may legitimately span the editable title and its cached page.
  static ({List<WmlInline> prefix, List<WmlInline> suffix, Set<Object> moved})
  _nativeSides(WmlParagraph source, int start, int end) {
    final empty = <Object>{};
    final starts = <Object, int>{};
    var offset = 0;
    for (final inline in source.inlines) {
      if (inline is WmlRun) offset += inline.text.length;
      final key = _rangeKey(inline);
      if (key == null) continue;
      if (_startsRange(inline)) {
        starts[key] = offset;
      } else if (starts[key] == offset) {
        empty.add(key);
      }
    }
    final prefix = <WmlInline>[];
    final suffix = <WmlInline>[];
    final moved = <Object>{};
    offset = 0;
    for (final inline in WmlClone.inlines(source.inlines)) {
      if (inline is WmlRun) {
        final next = offset + inline.text.length;
        if (offset < start) {
          final run = WmlClone.inlines([inline]).single as WmlRun;
          run.text = inline.text.substring(
            0,
            (start - offset).clamp(0, inline.text.length),
          );
          if (run.text.isNotEmpty) prefix.add(run);
        }
        if (next > end) {
          inline.text = inline.text.substring(
            (end - offset).clamp(0, inline.text.length),
          );
          if (inline.text.isNotEmpty) suffix.add(inline);
        }
        offset = next;
        continue;
      }
      final key = _boundaryKey(inline);
      final range = _rangeKey(inline);
      final emptyRange = range != null && empty.contains(range);
      final before =
          offset < start ||
          (offset == start &&
              key != null &&
              !_startsRange(inline) &&
              !emptyRange);
      final after =
          offset > end ||
          (offset == end &&
              (key == null || _startsRange(inline) || emptyRange));
      if (before || after) {
        (before ? prefix : suffix).add(inline);
        if (key != null) moved.add(key);
      }
    }
    return (prefix: prefix, suffix: suffix, moved: moved);
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
