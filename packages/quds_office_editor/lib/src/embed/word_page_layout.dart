import 'package:quds_office_engine/quds_office_engine.dart';

/// Which sections receive a Page Layout edit.
enum WordPageLayoutScope { currentSection, wholeDocument }

/// A layout constraint that must be corrected before changing the document.
enum WordPageLayoutIssue {
  paperSize,
  margins,
  bodySize,
  headerFooterDistance,
  columnCount,
  columnSpace,
  columnWidth,
}

/// An immutable draft of the section settings supported by the Word engine.
///
/// All lengths are in points. Unmodeled imported section properties, story
/// contents, and section links are deliberately outside this value object.
final class WordPageLayoutSettings {
  const WordPageLayoutSettings({
    this.pageSize = const WmlPageSize(),
    this.margins = const WmlPageMargins(),
    this.columnCount = 1,
    this.columnSpace = 36,
    this.columnSeparator = false,
    this.sectionStart = WmlSectionBreakKind.nextPage,
    this.differentFirstPage = false,
    this.differentOddEven = false,
    this.lineNumbers = false,
  });

  factory WordPageLayoutSettings.fromSection(WmlSection section) =>
      WordPageLayoutSettings(
        pageSize: section.pageSize,
        margins: section.margins,
        columnCount: section.columnCount,
        columnSpace: section.columnSpace,
        columnSeparator: section.columnSep,
        sectionStart: section.breakKind,
        differentFirstPage: section.differentFirstPage,
        differentOddEven: section.differentOddEven,
        lineNumbers: section.lineNumbers,
      );

  final WmlPageSize pageSize;
  final WmlPageMargins margins;
  final int columnCount;
  final double columnSpace;
  final bool columnSeparator;
  final WmlSectionBreakKind sectionStart;
  final bool differentFirstPage;

  /// DOCX stores this as one setting for the entire document.
  final bool differentOddEven;
  final bool lineNumbers;

  double get contentWidth => pageSize.width - margins.left - margins.right;
  double get contentHeight => pageSize.height - margins.top - margins.bottom;
  double get columnWidth =>
      (contentWidth - columnSpace * (columnCount - 1)) / columnCount;

  /// The engine requires a usable body and at least 12 pt for each column.
  WordPageLayoutIssue? get validationIssue {
    if (!pageSize.width.isFinite ||
        !pageSize.height.isFinite ||
        pageSize.width <= 0 ||
        pageSize.height <= 0) {
      return WordPageLayoutIssue.paperSize;
    }
    if (<double>[
      margins.top,
      margins.bottom,
      margins.left,
      margins.right,
    ].any((value) => !value.isFinite || value < 0)) {
      return WordPageLayoutIssue.margins;
    }
    if (contentWidth < 12 || contentHeight < 12) {
      return WordPageLayoutIssue.bodySize;
    }
    if (<double>[margins.header, margins.footer].any(
      (value) => !value.isFinite || value < 0 || value >= pageSize.height,
    )) {
      return WordPageLayoutIssue.headerFooterDistance;
    }
    if (columnCount < 1 || columnCount > 4) {
      return WordPageLayoutIssue.columnCount;
    }
    if (!columnSpace.isFinite || columnSpace < 0) {
      return WordPageLayoutIssue.columnSpace;
    }
    if (columnWidth < 12) return WordPageLayoutIssue.columnWidth;
    return null;
  }

  WordPageLayoutSettings copyWith({
    WmlPageSize? pageSize,
    WmlPageMargins? margins,
    int? columnCount,
    double? columnSpace,
    bool? columnSeparator,
    WmlSectionBreakKind? sectionStart,
    bool? differentFirstPage,
    bool? differentOddEven,
    bool? lineNumbers,
  }) => WordPageLayoutSettings(
    pageSize: pageSize ?? this.pageSize,
    margins: margins ?? this.margins,
    columnCount: columnCount ?? this.columnCount,
    columnSpace: columnSpace ?? this.columnSpace,
    columnSeparator: columnSeparator ?? this.columnSeparator,
    sectionStart: sectionStart ?? this.sectionStart,
    differentFirstPage: differentFirstPage ?? this.differentFirstPage,
    differentOddEven: differentOddEven ?? this.differentOddEven,
    lineNumbers: lineNumbers ?? this.lineNumbers,
  );

  /// Compare exact model values, without the looser preset-matching tolerance.
  bool matches(WordPageLayoutSettings other) =>
      samePaper(other) &&
      sameMargins(other) &&
      columnCount == other.columnCount &&
      columnSpace == other.columnSpace &&
      columnSeparator == other.columnSeparator &&
      sectionStart == other.sectionStart &&
      differentFirstPage == other.differentFirstPage &&
      differentOddEven == other.differentOddEven &&
      lineNumbers == other.lineNumbers;

  bool samePaper(WordPageLayoutSettings other) =>
      pageSize.width == other.pageSize.width &&
      pageSize.height == other.pageSize.height;

  bool sameMargins(WordPageLayoutSettings other) =>
      margins.top == other.margins.top &&
      margins.bottom == other.margins.bottom &&
      margins.left == other.margins.left &&
      margins.right == other.margins.right &&
      margins.header == other.margins.header &&
      margins.footer == other.margins.footer;

  /// Restore modeled values without replacing section identity or contents.
  void applyTo(WmlSection section) {
    section
      ..pageSize = pageSize
      ..margins = margins
      ..columnCount = columnCount
      ..columnSpace = columnSpace
      ..columnSep = columnSeparator
      ..breakKind = sectionStart
      ..differentFirstPage = differentFirstPage
      ..differentOddEven = differentOddEven
      ..lineNumbers = lineNumbers;
  }
}

/// A detached Page Layout draft tied to the document and section it came from.
///
/// Obtain this from `WordEditorController.capturePageLayout`. Keeping the
/// snapshot lets a modal host reject edits if a native File command replaces
/// the document, another edit changes its revision, or a host replaces sections.
final class WordPageLayoutTarget {
  WordPageLayoutTarget({
    required this.document,
    required this.section,
    required this.contentRevision,
    required this.settings,
    required List<WmlSection> sections,
    required List<WordPageLayoutSettings> sectionSettings,
  }) : sections = List<WmlSection>.unmodifiable(sections),
       sectionSettings = List<WordPageLayoutSettings>.unmodifiable(
         sectionSettings,
       );

  final WmlDocument document;
  final WmlSection section;
  final int contentRevision;
  final WordPageLayoutSettings settings;
  final List<WmlSection> sections;
  final List<WordPageLayoutSettings> sectionSettings;
}
