// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

/// The supported layout-only subset of MS-DOC Copts60/Copts80/Copts. Names are
/// fixed WordprocessingML compatibility element names, in schema order. This
/// list cannot enable fields, external links, macros, or document protection.
/// [sourceWord] and [sourceBit] locate the bit in the 32-byte Copts structure;
/// [inverted] records the six binary flags whose OOXML meaning is opposite.
enum LegacyWordCompatibilityFlag {
  useSingleBorderforContiguousCells(0, 8),
  wpJustification(0, 30),
  noTabHangInd(0, 0),
  noLeading(0, 19),
  spaceForUL(0, 20, inverted: true),
  noColumnBalance(0, 5),
  balanceSingleByteDoubleByteWidth(0, 15, inverted: true),
  noExtraLineSpacing(0, 27),
  doNotLeaveBackslashAlone(0, 12, inverted: true),
  ulTrailSpace(0, 14, inverted: true),
  doNotExpandShiftReturn(0, 13, inverted: true),
  spacingInWholePoints(0, 17),
  lineWrapLikeWord6(0, 25),
  printBodyTextBeforeHeader(0, 18),
  wpSpaceWidth(0, 29),
  showBreaksInFrames(0, 10),
  subFontBySize(0, 24),
  suppressBottomSpacing(0, 28),
  suppressTopSpacing(0, 7),
  suppressSpacingAtTopOfPage(0, 16),
  suppressTopSpacingWP(0, 22),
  suppressSpBfAfterPgBrk(0, 2),
  swapBordersFacingPages(0, 11),
  truncateFontHeightsLikeWP6(0, 23),
  mwSmallCaps(0, 21),
  usePrinterMetrics(0, 31),
  doNotSuppressParagraphBorders(0, 26),
  wrapTrailSpaces(0, 3),
  footnoteLayoutLikeWW8(1, 1),
  shapeLayoutLikeWW8(1, 0),
  alignTablesRowByRow(1, 6),
  forgetLastTabAlignment(1, 4),
  adjustLineHeightInTable(1, 3, inverted: true),
  autoSpaceLikeWord95(1, 5),
  noSpaceRaiseLower(0, 1),
  doNotUseHTMLParagraphAutoSpacing(1, 2),
  layoutRawTableWidth(1, 7),
  layoutTableRowsApart(1, 8),
  useWord97LineBreakRules(1, 9),
  doNotBreakWrappedTables(1, 10),
  doNotSnapToGridInCell(1, 11),
  applyBreakingRules(1, 13),
  doNotWrapTextWithPunct(1, 14),
  doNotUseEastAsianBreakRules(1, 15),
  useWord2002TableStyleRules(1, 16),
  growAutofit(1, 17),
  useNormalStyleForList(1, 18),
  doNotUseIndentAsNumberingTabStop(1, 19),
  useAltKinsokuLineBreakRules(1, 20),
  allowSpaceOfSameStyleInTable(1, 21),
  doNotSuppressIndentation(1, 22),
  doNotAutofitConstrainedTables(1, 23),
  autofitToFirstFixedWidthCell(1, 24),
  underlineTabInNumList(1, 25),
  displayHangulFixedWidth(1, 26),
  splitPgBreakAndParaMark(1, 27),
  doNotVertAlignCellWithSp(1, 28),
  doNotBreakConstrainedForcedTable(1, 29),
  doNotVertAlignInTxbx(1, 30),
  useAnsiKerningPairs(1, 31),
  cachedColBalance(2, 0);

  const LegacyWordCompatibilityFlag(
    this.sourceWord,
    this.sourceBit, {
    this.inverted = false,
  });

  final int sourceWord;
  final int sourceBit;
  final bool inverted;
}

enum LegacyWordCompatibilityBlockKind {
  copts60(2, 8),
  copts80(4, 84),
  copts(32, 508);

  const LegacyWordCompatibilityBlockKind(this.byteLength, this.offsetInDop);
  final int byteLength;
  final int offsetInDop;
}

/// Original compatibility bytes, including non-layout and reserved bits, for
/// provenance. They are never interpreted as executable or external content.
class LegacyWordCompatibilityBlock {
  LegacyWordCompatibilityBlock({required this.kind, required Uint8List bytes})
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (bytes.length != kind.byteLength) {
      throw const FormatException('Invalid Word compatibility block size.');
    }
  }

  final LegacyWordCompatibilityBlockKind kind;
  final Uint8List bytes;
  int get offsetInDop => kind.offsetInDop;
}

enum LegacyWordCompatibilityIssue {
  /// A historical partial DOP contains only the complete 84/88-byte prefix.
  partialLegacyDop,

  /// The observed LibreOffice 610-byte layout has an unadvertised complete
  /// extended Copts. Its repeated later copy agrees, allowing bounded recovery.
  legacyExtendedBlockRecovered,

  /// Source copies disagree. Disputed flags are left unspecified except the
  /// documented, narrowly recognized older LibreOffice fExpShRtn copy pattern.
  conflictingCopies,

  /// An unadvertised extended block could not be corroborated by its duplicate.
  ambiguousExtendedBlock,

  /// Bytes beyond the recognized DOP version have no inferred semantics.
  unrecognizedExtension,

  /// A fully bounded FIB extension has extra uninterpreted words, or matches
  /// the independently retained older Word97-family extension signature.
  nonstandardFibExtension,
}

/// Immutable explicit source choices. An absent flag is unknown/unspecified,
/// whereas a present `false` is a source instruction to disable that behavior.
/// No application version or blanket `compatibilityMode` is inferred.
class LegacyWordCompatibility {
  const LegacyWordCompatibility.unspecified()
    : flags = const {},
      sourceBlocks = const [],
      issues = const [],
      ambiguousFlags = const {},
      sourceDopOffset = null,
      sourceDopLength = null,
      sourceFibVersion = null,
      sourceFibNewVersion = null;

  LegacyWordCompatibility({
    Map<LegacyWordCompatibilityFlag, bool> flags = const {},
    List<LegacyWordCompatibilityBlock> sourceBlocks = const [],
    List<LegacyWordCompatibilityIssue> issues = const [],
    Set<LegacyWordCompatibilityFlag> ambiguousFlags = const {},
    this.sourceDopOffset,
    this.sourceDopLength,
    this.sourceFibVersion,
    this.sourceFibNewVersion,
  }) : flags = Map.unmodifiable(flags),
       sourceBlocks = List.unmodifiable(sourceBlocks),
       issues = List.unmodifiable(issues.toSet()),
       ambiguousFlags = Set.unmodifiable(ambiguousFlags) {
    if (sourceBlocks.length > 3 ||
        sourceBlocks.map((block) => block.kind).toSet().length !=
            sourceBlocks.length ||
        ambiguousFlags.any(flags.containsKey)) {
      throw const FormatException('Invalid Word compatibility provenance.');
    }
  }

  final Map<LegacyWordCompatibilityFlag, bool> flags;
  final List<LegacyWordCompatibilityBlock> sourceBlocks;
  final List<LegacyWordCompatibilityIssue> issues;
  final Set<LegacyWordCompatibilityFlag> ambiguousFlags;
  final int? sourceDopOffset;
  final int? sourceDopLength;
  final int? sourceFibVersion;
  final int? sourceFibNewVersion;

  bool? operator [](LegacyWordCompatibilityFlag flag) => flags[flag];
}
