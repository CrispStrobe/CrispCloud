import 'dart:typed_data';

import '../../opc/ole/bounded_cfb_reader.dart';
import 'legacy_word_structured_model.dart';
import 'legacy_word_structured_render.dart';

part 'legacy_word_binary_source.dart';
part 'legacy_word_sprms.dart';
part 'legacy_word_format_tables.dart';

typedef _Props = Map<String, Object?>;

/// A bounded interpretation of referenced MS-DOC body content and properties.
/// The source compound file is never changed and no external content is read.
LegacyWordDocument readStructuredLegacyWord(Uint8List bytes) =>
    _StructuredWordParser(_BinarySource(bytes)).parse();

class _StructuredWordParser {
  _StructuredWordParser(this.source);
  final _BinarySource source;
  final budget = _Budget();
  final warnings = <LegacyWordWarning>{};
  final _prms = <int, List<_Sprm>>{};
  final _indirectProperties = <int, List<_Sprm>>{};
  final _indirectActive = <int>{};
  late final _FkpIndex characterFormatting;
  late final _FkpIndex paragraphFormatting;
  final styles = <int, _Style>{};
  final _resolvedStyles = <int, _ResolvedStyle>{};
  final _styleActive = <int>{};
  final fonts = <String>[];
  final authors = <String>[];
  int? defaultFont;
  int runCount = 0;
  final _fieldResults = <bool>[];
  late final Uint16List body;
  late final List<LegacyWordSection> sections;
  late final Set<int> sectionEnds;

  LegacyWordDocument parse() {
    _storyWarnings();
    if (source.bodyLength == 0) {
      return LegacyWordDocument(
        blocks: const [],
        sections: const [],
        plainText: '',
        safeHtml: '',
        warnings: List.unmodifiable(warnings),
      );
    }
    body = Uint16List(source.bodyLength);
    for (final piece in source.pieces) {
      if (piece.startCp >= body.length) break;
      final end = piece.endCp < body.length ? piece.endCp : body.length;
      for (var cp = piece.startCp; cp < end; cp++) {
        final fc = piece.fc(cp);
        final unit = piece.compressed
            ? source.word.u8(fc)
            : source.word.u16(fc);
        body[cp] = piece.compressed
            ? (_wordCompressedUnicode[unit] ?? unit)
            : unit;
      }
    }
    _validateUnicode(body);
    _readFonts();
    _readStyles();
    _readAuthors();
    characterFormatting = _readFkp(paragraph: false);
    paragraphFormatting = _readFkp(paragraph: true);
    sections = _readSections();
    sectionEnds = {
      for (final section in sections.take(sections.length - 1)) section.endCp,
    };
    final paragraphs = <_Paragraph>[];
    var start = 0;
    for (var cp = 0; cp < body.length; cp++) {
      final unit = body[cp];
      if (unit == 13 ||
          unit == 7 ||
          (unit == 12 && sectionEnds.contains(cp + 1))) {
        paragraphs.add(_paragraph(start, cp, cp + 1, unit));
        start = cp + 1;
        if (paragraphs.length > 50000) {
          throw const FormatException(
            'Word paragraphs exceed the preview complexity limit.',
          );
        }
      }
    }
    if (start < body.length) {
      paragraphs.add(_paragraph(start, body.length, body.length, 0));
    }
    if (_fieldResults.isNotEmpty) {
      throw const FormatException('Unclosed Word field.');
    }
    final blocks = _assembleTables(paragraphs);
    final plain = StringBuffer();
    void paragraphText(LegacyWordParagraph paragraph) {
      for (final run in paragraph.runs) {
        if (!run.style.hidden) plain.write(run.text);
      }
    }

    for (final block in blocks) {
      switch (block) {
        case LegacyWordParagraph():
          paragraphText(block);
          plain.writeln();
        case LegacyWordTable():
          for (final row in block.rows) {
            for (var cell = 0; cell < row.cells.length; cell++) {
              if (cell != 0) plain.write('\t');
              final paragraphs = row.cells[cell].paragraphs;
              for (var p = 0; p < paragraphs.length; p++) {
                if (p != 0) plain.write('\n');
                paragraphText(paragraphs[p]);
              }
            }
            plain.writeln();
          }
      }
    }
    final orderedWarnings = warnings.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final plainText = plain.toString();
    return LegacyWordDocument(
      blocks: List.unmodifiable(blocks),
      sections: List.unmodifiable(sections),
      plainText: plainText.endsWith('\n')
          ? plainText.substring(0, plainText.length - 1)
          : plainText,
      safeHtml: renderLegacyWordHtml(blocks),
      warnings: List.unmodifiable(orderedWarnings),
    );
  }

  void _storyWarnings() {
    if (source.missingDeclaredExtent) {
      warnings.add(LegacyWordWarning.unsupportedFormatting);
    }
    final lengths = source.storyLengths;
    if (lengths[0] != 0 || lengths[3] != 0) {
      warnings.add(LegacyWordWarning.notesOmitted);
    }
    if (lengths[1] != 0) warnings.add(LegacyWordWarning.headersFootersOmitted);
    if (lengths[2] != 0) warnings.add(LegacyWordWarning.commentsOmitted);
    if (lengths[4] != 0 || lengths[5] != 0) {
      warnings.add(LegacyWordWarning.textboxesOmitted);
    }
    for (final entry in source.compound.childrenOf(source.compound.root)) {
      if (const {
        'MACROS',
        'VBA',
        '_VBA_PROJECT_CUR',
      }.contains(entry.name.toUpperCase())) {
        warnings.add(LegacyWordWarning.macrosOmitted);
      }
      if (entry.name == 'ObjectPool') {
        warnings.add(LegacyWordWarning.floatingObjectsOmitted);
      }
    }
  }

  List<_Sprm> _readProperties(Uint8List bytes, [int depth = 0]) {
    if (depth > 16) {
      throw const FormatException(
        'Word indirect properties are nested too deeply.',
      );
    }
    final operations = _decodeSprms(bytes, budget);
    final output = <_Sprm>[];
    void append(List<_Sprm> values) {
      if (values.length > 100000 - output.length) {
        throw const FormatException(
          'Word properties exceed the preview complexity limit.',
        );
      }
      budget.expand(values.length);
      output.addAll(values);
    }

    for (final operation in operations) {
      if ((const {0x2a83, 0x3668}.contains(operation.code) &&
              operation.data.u8(0) != 0) ||
          const {0xca89, 0xd667}.contains(operation.code)) {
        warnings.add(LegacyWordWarning.revisionMetadataIncomplete);
      }
      if (operation.code != 0x6646 &&
          operation.code != 0x646b &&
          operation.code != 0x6645) {
        append([operation]);
        continue;
      }
      final offset = operation.data.u32(0);
      final cached = _indirectProperties[offset];
      if (cached != null) {
        append(cached);
        continue;
      }
      if (!_indirectActive.add(offset)) {
        throw const FormatException('Cyclic Word indirect properties.');
      }
      final data = source.data;
      final length = data.u16(offset);
      final nested = _readProperties(data.slice(offset + 2, length), depth + 1);
      _indirectActive.remove(offset);
      _indirectProperties[offset] = nested;
      append(nested);
    }
    return output;
  }

  List<_Sprm> _pieceProperties(_Piece piece) => _prms.putIfAbsent(
    piece.prm,
    () {
      if (piece.prm == 0) return const [];
      if (piece.prm.isOdd) return _readProperties(source.prcs[piece.prm >> 1]);
      final index = (piece.prm >> 1) & 0x7f;
      final code = _prm0Codes[index];
      if (code == null) {
        warnings.add(LegacyWordWarning.unsupportedFormatting);
        return const [];
      }
      return [
        _Sprm(code, Uint8List.fromList([piece.prm >> 8])),
      ];
    },
  );

  _Paragraph _paragraph(int start, int contentEnd, int end, int terminator) {
    final terminalCp = end > start ? end - 1 : start;
    final terminalPiece = source.pieceAt(terminalCp);
    final papx = paragraphFormatting.at(terminalPiece.fc(terminalCp));
    final prm = _pieceProperties(terminalPiece);
    var styleIndex = papx.styleIndex;
    for (final op in [...papx.operations, ...prm]) {
      if (op.code == 0x4600) styleIndex = op.data.u16(0);
    }
    final resolved = _resolveStyle(styleIndex);
    final properties = <String, Object?>{...resolved.paragraph};
    _applyParagraph(papx.operations, properties, budget, warnings);
    _applyParagraph(prm, properties, budget, warnings);
    final listId = properties['listId'] as int?;
    if (listId != null && listId != 0) {
      warnings.add(LegacyWordWarning.numberingNotReconstructed);
    }
    final outline = properties['outline'] as int?;
    final style = LegacyWordParagraphStyle(
      styleIndex: styleIndex,
      styleName: styles[styleIndex]?.name,
      headingLevel: outline != null && outline < 9 ? outline + 1 : null,
      alignment: switch (properties['alignment']) {
        1 => LegacyWordAlignment.center,
        2 => LegacyWordAlignment.right,
        3 => LegacyWordAlignment.justify,
        4 => LegacyWordAlignment.distribute,
        _ => LegacyWordAlignment.left,
      },
      leftIndentTwips: properties['leftIndent'] as int? ?? 0,
      rightIndentTwips: properties['rightIndent'] as int? ?? 0,
      firstLineIndentTwips: properties['firstIndent'] as int? ?? 0,
      spaceBeforeTwips: properties['before'] as int? ?? 0,
      spaceAfterTwips: properties['after'] as int? ?? 0,
      lineSpacingValue: properties['lineSpacing'] as int?,
      lineSpacingMultiple: properties['lineMultiple'] == true,
      keepNext: properties['keepNext'] == true,
      keepTogether: properties['keepTogether'] == true,
      pageBreakBefore: properties['pageBreakBefore'] == true,
      listId: listId,
      listLevel: properties['listLevel'] as int?,
    );
    final runs = <LegacyWordRun>[];
    _PendingRun? pendingRun;
    void finishRun() {
      final pending = pendingRun;
      if (pending == null) return;
      if (++runCount > 200000) {
        throw const FormatException(
          'Word runs exceed the preview complexity limit.',
        );
      }
      runs.add(pending.finish());
      pendingRun = null;
    }

    var cp = start;
    while (cp < contentEnd) {
      final piece = source.pieceAt(cp);
      final fc = piece.fc(cp);
      final chpx = characterFormatting.at(fc);
      final characterPrm = _pieceProperties(piece);
      final base = <String, Object?>{...resolved.character};
      final character = <String, Object?>{...base};
      _applyCharacter(
        [...chpx.operations, ...characterPrm],
        character,
        base,
        budget,
        warnings,
        paragraphStyle: resolved.character,
        resolveCharacterStyle: (index) {
          if (index == 10 && !styles.containsKey(index)) return const {};
          if (styles[index]?.kind != 2) {
            throw const FormatException(
              'Invalid Word character-style reference.',
            );
          }
          return _resolveStyle(index).character;
        },
      );
      var spanEnd = cp + (chpx.endFc - fc) ~/ (piece.compressed ? 1 : 2);
      if (spanEnd > piece.endCp) spanEnd = piece.endCp;
      if (spanEnd > contentEnd) spanEnd = contentEnd;
      if (spanEnd <= cp) {
        throw const FormatException('Unaligned Word character formatting.');
      }
      // A scalar is emitted atomically even when a valid surrogate pair crosses
      // an FKP or piece boundary; it takes the first code unit's properties.
      if (spanEnd < contentEnd && _highSurrogate(body[spanEnd - 1])) {
        spanEnd++;
        warnings.add(LegacyWordWarning.unsupportedFormatting);
      }
      final runStyle = _characterStyle(character);
      final inserted = character['inserted'] == true;
      final deleted = character['deleted'] == true;
      String? author;
      DateTime? time;
      if (inserted || deleted) {
        final authorIndex =
            character[deleted ? 'deletionAuthor' : 'insertionAuthor'] as int?;
        if (authorIndex != null && authorIndex < authors.length) {
          author = authors[authorIndex];
        }
        time = _revisionDate(
          character[deleted ? 'deletionDate' : 'insertionDate'] as int?,
        );
        if (author == null || time == null || (inserted && deleted)) {
          warnings.add(LegacyWordWarning.revisionMetadataIncomplete);
        }
      }
      var segmentStart = cp;
      var segmentEnd = cp;
      final text = StringBuffer();
      void flush() {
        if (text.isEmpty) return;
        final value = text.toString();
        text.clear();
        final previous = pendingRun;
        if (previous != null &&
            previous.endCp == segmentStart &&
            previous.style == runStyle &&
            previous.inserted == inserted &&
            previous.deleted == deleted &&
            previous.author == author &&
            previous.time == time) {
          previous.text.write(value);
          previous.endCp = segmentEnd;
          return;
        }
        finishRun();
        pendingRun = _PendingRun(
          segmentStart,
          segmentEnd,
          value,
          runStyle,
          inserted,
          deleted,
          author,
          time,
        );
      }

      while (cp < spanEnd) {
        final unit = body[cp];
        if (unit == 0x13 || unit == 0x14 || unit == 0x15) {
          flush();
          warnings.add(LegacyWordWarning.fieldsUseStoredResults);
          if (unit == 0x13) {
            if (_fieldResults.length >= 64) {
              throw const FormatException('Word fields are nested too deeply.');
            }
            _fieldResults.add(false);
          } else {
            if (_fieldResults.isEmpty) {
              throw const FormatException('Unmatched Word field marker.');
            }
            if (unit == 0x14) {
              if (_fieldResults.last) {
                throw const FormatException('Duplicate Word field separator.');
              }
              _fieldResults[_fieldResults.length - 1] = true;
            } else {
              _fieldResults.removeLast();
            }
          }
          cp++;
          continue;
        }
        if (_fieldResults.contains(false)) {
          flush();
          cp++;
          continue;
        }
        var printable = unit;
        switch (unit) {
          case 1:
            warnings.add(LegacyWordWarning.imagesOmitted);
            printable = -1;
          case 2:
            warnings.add(LegacyWordWarning.notesOmitted);
            printable = -1;
          case 5:
            warnings.add(LegacyWordWarning.commentsOmitted);
            printable = -1;
          case 8:
            warnings.add(LegacyWordWarning.floatingObjectsOmitted);
            printable = -1;
          case 10:
          case 11:
            printable = 10;
          case 30:
            printable = 0x2011;
          case 31:
            printable = 0x00ad;
          default:
            if (unit < 32 && unit != 9 && unit != 12) {
              warnings.add(LegacyWordWarning.unsupportedFormatting);
              printable = -1;
            }
        }
        if (printable < 0) {
          flush();
          cp++;
          continue;
        }
        if (text.isEmpty) segmentStart = cp;
        text.writeCharCode(printable);
        cp++;
        if (_highSurrogate(unit)) {
          text.writeCharCode(body[cp]);
          cp++;
        }
        segmentEnd = cp;
      }
      flush();
    }
    finishRun();
    return _Paragraph(
      LegacyWordParagraph(
        startCp: start,
        endCp: end,
        runs: List.unmodifiable(runs),
        style: style,
      ),
      properties,
      terminator,
    );
  }

  LegacyWordCharacterStyle _characterStyle(_Props properties) {
    final fontIndex = properties['fontIndex'] as int? ?? defaultFont;
    String? font;
    if (fontIndex != null) {
      if (fontIndex >= 0 && fontIndex < fonts.length) {
        font = fonts[fontIndex];
      } else if (fonts.isNotEmpty) {
        warnings.add(LegacyWordWarning.unsupportedFormatting);
      }
    }
    return LegacyWordCharacterStyle(
      bold: properties['bold'] == true,
      italic: properties['italic'] == true,
      underline: properties['underline'] == true,
      strike: properties['strike'] == true,
      doubleStrike: properties['doubleStrike'] == true,
      smallCaps: properties['smallCaps'] == true,
      allCaps: properties['allCaps'] == true,
      hidden: properties['hidden'] == true,
      fontName: font,
      fontSizeHalfPoints: properties['fontSize'] as int?,
      colorHex: properties['color'] as String?,
      highlightHex: properties['highlight'] as String?,
      verticalAlign: switch (properties['verticalAlign']) {
        1 => LegacyWordVerticalAlignment.superscript,
        2 => LegacyWordVerticalAlignment.subscript,
        _ => LegacyWordVerticalAlignment.baseline,
      },
      positionHalfPoints: properties['position'] as int?,
      spacingTwips: properties['spacing'] as int?,
    );
  }

  List<LegacyWordBlock> _assembleTables(List<_Paragraph> paragraphs) {
    final blocks = <LegacyWordBlock>[];
    final rows = <LegacyWordTableRow>[];
    final cells = <List<LegacyWordParagraph>>[];
    var cell = <LegacyWordParagraph>[];
    int? start;
    var end = 0;
    void finishRow(_Props properties) {
      if (cell.isNotEmpty) {
        cells.add(cell);
        cell = [];
      }
      if (cells.isEmpty) {
        throw const FormatException('Word table row has no cells.');
      }
      final definition = properties['tableDefinition'] as _TableDefinition?;
      if (definition != null && definition.flags.length != cells.length) {
        throw const FormatException(
          'Word table cell count does not match its row.',
        );
      }
      rows.add(
        LegacyWordTableRow(
          isHeader: properties['rowHeader'] == true,
          cells: List.unmodifiable([
            for (var i = 0; i < cells.length; i++)
              LegacyWordTableCell(
                paragraphs: List.unmodifiable(cells[i]),
                widthTwips: definition == null
                    ? null
                    : definition.edges[i + 1] - definition.edges[i],
                mergeStart:
                    definition != null && (definition.flags[i] & 3) >= 2,
                mergeContinue:
                    definition != null && (definition.flags[i] & 3) == 1,
                verticalMergeStart:
                    definition != null && ((definition.flags[i] >> 5) & 3) >= 2,
                verticalMergeContinue:
                    definition != null && ((definition.flags[i] >> 5) & 3) == 1,
              ),
          ]),
        ),
      );
      cells.clear();
    }

    void finishTable() {
      if (start == null) return;
      if (cell.isNotEmpty || cells.isNotEmpty) {
        warnings.add(LegacyWordWarning.unsupportedFormatting);
        finishRow(const {});
      }
      blocks.add(
        LegacyWordTable(
          startCp: start!,
          endCp: end,
          rows: List.unmodifiable(rows),
        ),
      );
      rows.clear();
      start = null;
    }

    for (final item in paragraphs) {
      final paragraph = item.paragraph;
      final properties = item.properties;
      final depth = properties['tableDepth'] as int? ?? 0;
      if (depth > 1 ||
          properties['innerCellEnd'] == true ||
          properties['innerRowEnd'] == true) {
        warnings.add(LegacyWordWarning.nestedTablesFlattened);
        finishTable();
        blocks.add(paragraph);
        continue;
      }
      if (properties['inTable'] != true && depth == 0) {
        finishTable();
        blocks.add(paragraph);
        continue;
      }
      start ??= paragraph.startCp;
      end = paragraph.endCp;
      if (properties['rowEnd'] == true) {
        if (paragraph.runs.isNotEmpty) cell.add(paragraph);
        finishRow(properties);
      } else {
        cell.add(paragraph);
        if (item.terminator == 7) {
          cells.add(cell);
          cell = [];
        }
      }
      if (sectionEnds.contains(end)) finishTable();
    }
    finishTable();
    return blocks;
  }
}

class _Paragraph {
  const _Paragraph(this.paragraph, this.properties, this.terminator);
  final LegacyWordParagraph paragraph;
  final _Props properties;
  final int terminator;
}

class _PendingRun {
  _PendingRun(
    this.startCp,
    this.endCp,
    String value,
    this.style,
    this.inserted,
    this.deleted,
    this.author,
    this.time,
  ) {
    text.write(value);
  }
  final int startCp;
  int endCp;
  final LegacyWordCharacterStyle style;
  final bool inserted;
  final bool deleted;
  final String? author;
  final DateTime? time;
  final text = StringBuffer();
  LegacyWordRun finish() => LegacyWordRun(
    startCp: startCp,
    endCp: endCp,
    text: text.toString(),
    style: style,
    inserted: inserted,
    deleted: deleted,
    revisionAuthor: author,
    revisionTime: time,
  );
}

bool _highSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;
void _validateUnicode(List<int> units) {
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (_highSurrogate(unit)) {
      if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        throw const FormatException('Invalid UTF-16 in Word text.');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Invalid UTF-16 in Word text.');
    }
  }
}

DateTime? _revisionDate(int? value) {
  if (value == null || value == 0) return null;
  final minute = value & 63, hour = (value >> 6) & 31;
  final day = (value >> 11) & 31, month = (value >> 16) & 15;
  final year = 1900 + ((value >> 20) & 511);
  if (minute > 59 ||
      hour > 23 ||
      day < 1 ||
      day > 31 ||
      month < 1 ||
      month > 12) {
    return null;
  }
  // MS-DOC stores a wall-clock timestamp without an offset. UTC is a stable
  // transport representation; the original date/time fields remain intact.
  final date = DateTime.utc(year, month, day, hour, minute);
  return date.day == day && date.month == month ? date : null;
}
