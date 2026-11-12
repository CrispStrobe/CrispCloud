// SPDX-License-Identifier: MPL-2.0

/// Paragraph layout controls resolved from MS-DOC paragraph properties.
/// Defaults follow MS-DOC; nullable East Asian properties retain unspecified
/// state. These are instructions for a renderer, not cached pagination.
class LegacyWordParagraphLayout {
  const LegacyWordParagraphLayout({
    this.widowControl = true,
    this.suppressAutoHyphens = false,
    this.suppressLineNumbers = false,
    this.contextualSpacing = false,
    this.mirrorIndents = false,
    this.rightToLeft = false,
    this.spaceBeforeAuto = false,
    this.spaceAfterAuto = false,
    this.kinsoku,
    this.wordWrap,
    this.overflowPunctuation,
    this.autoSpaceEastAsianLatin,
    this.autoSpaceEastAsianNumbers,
  });
  final bool widowControl;
  final bool suppressAutoHyphens;
  final bool suppressLineNumbers;
  final bool contextualSpacing;
  final bool mirrorIndents;
  final bool rightToLeft;
  final bool spaceBeforeAuto;
  final bool spaceAfterAuto;
  final bool? kinsoku;
  final bool? wordWrap;
  final bool? overflowPunctuation;
  final bool? autoSpaceEastAsianLatin;
  final bool? autoSpaceEastAsianNumbers;
}

enum LegacyWordPageVerticalAlignment { top, center, both, bottom }

enum LegacyWordLineNumberRestart { newPage, newSection, continuous }

enum LegacyWordDocumentGrid { none, linesAndChars, lines, snapToChars }

enum LegacyWordNoteRestart { continuous, eachSect, eachPage }

enum LegacyWordFootnotePosition { pageBottom, beneathText, sectEnd }

enum LegacyWordEndnotePosition { sectEnd, docEnd }

/// Resolved automatic note labels. Custom reference marks remain on their
/// individual references. A source section offset is retained even when the
/// restart mode makes it inactive, as required by MS-DOC 2.6.4.
class LegacyWordNoteNumbering {
  const LegacyWordNoteNumbering({
    this.format = 'decimal',
    this.start = 1,
    this.restart = LegacyWordNoteRestart.continuous,
    this.sourceFormatCode,
    this.sourceContinuousOffset,
    this.usesDecimalFallback = false,
  });

  /// Native OOXML numbering format, or null for an unknown binary format.
  /// `none` is an explicit no-label instruction, distinct from null.
  final String? format;
  final int start;
  final LegacyWordNoteRestart restart;
  final int? sourceFormatCode;
  final int? sourceContinuousOffset;

  /// The source requested bullet or the legacy 0x28 format, for which the
  /// conversion uses decimal and retains the original code with a diagnostic.
  final bool usesDecimalFallback;
}

/// A source column's width and the space following it, in twips.
class LegacyWordPageColumn {
  const LegacyWordPageColumn({
    required this.widthTwips,
    this.spaceAfterTwips = 0,
  });
  final int widthTwips;
  final int spaceAfterTwips;
}

class LegacyWordSectionLayout {
  const LegacyWordSectionLayout({
    this.equalColumnWidths = true,
    this.columns = const [],
    this.columnSeparator = false,
    this.verticalAlignment = LegacyWordPageVerticalAlignment.top,
    this.lineNumberInterval = 0,
    this.lineNumberStart = 1,
    this.lineNumberDistanceTwips = 0,
    this.lineNumberRestart = LegacyWordLineNumberRestart.newPage,
    this.restartPageNumbering = false,
    this.pageNumberStart = 0,
    this.pageNumberFormat,
    this.grid = LegacyWordDocumentGrid.none,
    this.gridLinePitchTwips,
    this.gridCharacterSpace,
    this.footnoteNumbering = const LegacyWordNoteNumbering(),
    this.endnoteNumbering = const LegacyWordNoteNumbering(format: 'lowerRoman'),
    this.footnotePosition = LegacyWordFootnotePosition.pageBottom,
    this.endnotePosition,
    this.suppressEndnotes = false,
  });
  final bool equalColumnWidths;
  final List<LegacyWordPageColumn> columns;
  final bool columnSeparator;
  final LegacyWordPageVerticalAlignment verticalAlignment;
  final int lineNumberInterval;
  final int lineNumberStart;
  final int lineNumberDistanceTwips;
  final LegacyWordLineNumberRestart lineNumberRestart;
  final bool restartPageNumbering;
  final int pageNumberStart;

  /// Supported fixed OOXML counting format, not arbitrary markup.
  final String? pageNumberFormat;
  final LegacyWordDocumentGrid grid;
  final int? gridLinePitchTwips;

  /// Difference in character pitch, in 1/4096 point, including its sign.
  final int? gridCharacterSpace;
  final LegacyWordNoteNumbering footnoteNumbering;
  final LegacyWordNoteNumbering endnoteNumbering;
  final LegacyWordFootnotePosition footnotePosition;
  final LegacyWordEndnotePosition? endnotePosition;
  final bool suppressEndnotes;
}
