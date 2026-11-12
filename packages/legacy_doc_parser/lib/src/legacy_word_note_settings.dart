// SPDX-License-Identifier: MPL-2.0

/// Fixed WordprocessingML numbering formats used by MS-DOC note settings.
/// Bullet and application-defined MSONFC values require an explicit fallback;
/// they cannot inject arbitrary formatting names into a converted package.
enum LegacyWordNoteNumberFormat {
  decimal,
  upperRoman,
  lowerRoman,
  upperLetter,
  lowerLetter,
  ordinal,
  cardinalText,
  ordinalText,
  hex,
  chicago,
  ideographDigital,
  japaneseCounting,
  aiueo,
  iroha,
  decimalFullWidth,
  decimalHalfWidth,
  japaneseLegal,
  japaneseDigitalTenThousand,
  decimalEnclosedCircle,
  decimalFullWidth2,
  aiueoFullWidth,
  irohaFullWidth,
  decimalZero,
  ganada,
  chosung,
  decimalEnclosedFullstop,
  decimalEnclosedParen,
  decimalEnclosedCircleChinese,
  ideographEnclosedCircle,
  ideographTraditional,
  ideographZodiac,
  ideographZodiacTraditional,
  taiwaneseCounting,
  ideographLegalTraditional,
  taiwaneseCountingThousand,
  taiwaneseDigital,
  chineseCounting,
  chineseLegalSimplified,
  chineseCountingThousand,
  koreanDigital,
  koreanCounting,
  koreanLegal,
  koreanDigital2,
  hebrew1,
  arabicAlpha,
  hebrew2,
  arabicAbjad,
  hindiVowels,
  hindiConsonants,
  hindiNumbers,
  hindiCounting,
  thaiLetters,
  thaiNumbers,
  thaiCounting,
  vietnameseCounting,
  numberInDash,
  russianLower,
  russianUpper,
  none,
}

enum LegacyWordNoteRestart { continuous, eachSection, eachPage }

enum LegacyWordFootnotePosition { pageBottom, beneathText, sectionEnd }

enum LegacyWordEndnotePosition { documentEnd, sectionEnd }

class LegacyWordNoteNumbering {
  const LegacyWordNoteNumbering({
    this.format = LegacyWordNoteNumberFormat.decimal,
    this.startAt = 1,
    this.restart = LegacyWordNoteRestart.continuous,
  });

  final LegacyWordNoteNumberFormat format;

  /// Source start/offset parameter, bounded to 0..16383. For the modern
  /// section SPRMs, this parameter offsets continuous numbering by startAt-1;
  /// it is ignored when that section restarts numbering. Legacy DOP starts
  /// also apply at each restart. The parser resolves that distinction.
  final int startAt;
  final LegacyWordNoteRestart restart;
}

class LegacyWordFootnoteSettings {
  const LegacyWordFootnoteSettings({
    this.numbering = const LegacyWordNoteNumbering(),
    this.position = LegacyWordFootnotePosition.pageBottom,
  });

  final LegacyWordNoteNumbering numbering;
  final LegacyWordFootnotePosition position;
}

class LegacyWordEndnoteSettings {
  const LegacyWordEndnoteSettings({
    this.numbering = const LegacyWordNoteNumbering(
      format: LegacyWordNoteNumberFormat.lowerRoman,
    ),
    this.position = LegacyWordEndnotePosition.documentEnd,
  });

  final LegacyWordNoteNumbering numbering;
  final LegacyWordEndnotePosition position;
}
