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
}
