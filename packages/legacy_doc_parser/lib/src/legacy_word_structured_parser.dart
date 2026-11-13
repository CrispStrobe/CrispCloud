// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'bounded_cfb_reader.dart';
import 'compound/cfbf_writer.dart';
import 'legacy_word_metafile.dart';
import 'legacy_word_number_formats.dart';
import 'legacy_word_numbering.dart';
import 'legacy_word_structured_model.dart';
import 'legacy_word_structured_render.dart';
import 'legacy_word_textbox_alias.dart';

part 'legacy_word_binary_source.dart';
part 'legacy_word_compatibility_parser.dart';
part 'legacy_word_sprms.dart';
part 'legacy_word_layout_parser.dart';
part 'legacy_word_revisions.dart';
part 'legacy_word_decorations.dart';
part 'legacy_word_format_tables.dart';
part 'legacy_word_stories.dart';
part 'legacy_word_fields.dart';
part 'legacy_word_lists.dart';
part 'legacy_word_tables.dart';
part 'legacy_word_table_revisions.dart';
part 'legacy_word_table_operations.dart';
part 'legacy_word_table_styles.dart';
part 'legacy_word_table_text.dart';
part 'legacy_word_media_parser.dart';
part 'legacy_word_officeart_parser.dart';

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
  int? defaultEastAsianFont;
  int? defaultNonAsciiFont;
  int? defaultComplexScriptFont;
  int runCount = 0;
  int paragraphCount = 0;
  int fieldTextUnits = 0;
  final _fieldResults = <bool>[];
  final _fieldIndicesByStart = <int, int>{};
  final _activeFieldIndices = <int>[];
  final _displayFieldRevisions = <int, _DisplayFieldRevisionCapture>{};
  final _privateFieldSeparators = <int>{};
  final _fieldFlags = <int, int>{};
  List<(int, int)> _invisibleMediaRanges = const [];
  final _noteMarkerCps = <int>{};
  final _commentMarkerCps = <int>{};
  final _referenceAnchors = <int>{};
  final _referencePresentations = <int, LegacyWordMediaPresentation>{};
  final _referenceCharacterStyles = <int, LegacyWordCharacterStyle>{};
  final stories = <LegacyWordStory>[];
  final noteReferences = <LegacyWordNoteReference>[];
  final commentReferences = <LegacyWordCommentReference>[];
  final textboxReferences = <LegacyWordTextboxReference>[];
  final bookmarks = <LegacyWordBookmark>[];
  final fields = <LegacyWordField>[];
  final mediaRuns = <LegacyWordMediaRun>[];
  final numbering = <LegacyWordNumberingDefinition>[];
  final _numberingById = <int, LegacyWordNumberingDefinition>{};
  final _listLevels = <(int, int), _ListLevelData>{};
  final _tableStyles = <int, LegacyWordTableStyle>{};
  final _tableTextOperations = <int, _TableTextOperations>{};
  late final Uint16List body;
  late final List<LegacyWordSection> sections;
  late final Set<int> sectionEnds;

  LegacyWordDocument parse() {
    _storyWarnings();
    if (source.compatibility.issues.isNotEmpty) {
      warnings.add(LegacyWordWarning.unsupportedFormatting);
    }
    if (source.totalLength == 0) {
      final media = _readMediaCatalog(const []);
      final orderedWarnings = warnings.toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      return LegacyWordDocument(
        blocks: const [],
        sections: const [],
        plainText: '',
        safeHtml: '',
        warnings: List.unmodifiable(orderedWarnings),
        media: media,
        evenAndOddHeaders: source.evenAndOddHeaders,
        defaultTabStopTwips: source.defaultTabStopTwips,
        compatibility: source.compatibility,
      );
    }
    body = Uint16List(source.totalLength);
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
    final lineNumberStyle = _lineNumberStyle();
    _readTableStyles();
    _readAuthors();
    characterFormatting = _readFkp(paragraph: false);
    paragraphFormatting = _readFkp(paragraph: true);
    sections = _readSections();
    sectionEnds = {
      for (final section in sections.take(
        sections.isEmpty ? 0 : sections.length - 1,
      ))
        section.endCp,
    };
    _readNumbering();
    _readBookmarks();
    _readFieldTables();
    _readAuxiliaryStories();
    _validateBookmarkStories();
    final blocks = _parseRange(0, source.bodyLength, 'main');
    _resolveReferencePresentations();
    final media = _readMediaCatalog(mediaRuns);
    _linkTextboxDrawings(media);
    final renderer = LegacyWordHtmlRenderer(
      numberingDefinitions: numbering,
      defaultTabStopTwips: source.defaultTabStopTwips,
      media: media,
    );
    final previews = renderer.renderAll([
      blocks,
      for (final story in stories) story.blocks,
    ]);
    final mainHtml = previews.first;
    for (var i = 0; i < stories.length; i++) {
      final story = stories[i];
      stories[i] = LegacyWordStory(
        id: story.id,
        kind: story.kind,
        startCp: story.startCp,
        endCp: story.endCp,
        blocks: story.blocks,
        plainText: story.plainText,
        safeHtml: previews[i + 1],
        sectionIndex: story.sectionIndex,
        headerFooterType: story.headerFooterType,
      );
    }
    final orderedWarnings = warnings.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return LegacyWordDocument(
      blocks: List.unmodifiable(blocks),
      sections: List.unmodifiable(sections),
      plainText: _plainText(blocks),
      safeHtml: mainHtml,
      warnings: List.unmodifiable(orderedWarnings),
      stories: List.unmodifiable(stories),
      noteReferences: List.unmodifiable(noteReferences),
      commentReferences: List.unmodifiable(commentReferences),
      textboxReferences: List.unmodifiable(textboxReferences),
      bookmarks: List.unmodifiable(bookmarks),
      fields: List.unmodifiable(fields),
      numbering: List.unmodifiable(numbering),
      tableStyles: List.unmodifiable(_tableStyles.values),
      media: media,
      evenAndOddHeaders: source.evenAndOddHeaders,
      defaultTabStopTwips: source.defaultTabStopTwips,
      compatibility: source.compatibility,
      lineNumberStyle: lineNumberStyle,
    );
  }

  List<LegacyWordBlock> _parseRange(int first, int limit, String storyId) {
    if (first == limit) return const [];
    final priorFields = fields.length;
    _collectFields(first, limit, storyId);
    _prepareFieldRevisions(priorFields);
    _invisibleMediaRanges = _fieldHiddenMediaRanges(priorFields);
    _fieldResults.clear();
    final segments = <(int, int, int, int, _PreparedParagraph)>[];
    var start = first;
    for (var cp = first; cp < limit; cp++) {
      final unit = body[cp];
      if (unit == 13 ||
          unit == 7 ||
          (unit == 12 && sectionEnds.contains(cp + 1))) {
        segments.add((
          start,
          cp,
          cp + 1,
          unit,
          _prepareParagraph(start, cp + 1),
        ));
        start = cp + 1;
        if (++paragraphCount > 50000) {
          throw const FormatException(
            'Word paragraphs exceed the preview complexity limit.',
          );
        }
      }
    }
    if (start < limit) {
      if (++paragraphCount > 50000) {
        throw const FormatException(
          'Word paragraphs exceed the preview complexity limit.',
        );
      }
      segments.add((start, limit, limit, 0, _prepareParagraph(start, limit)));
    }
    // Discover row/cell conditions before reading any character runs. A
    // structural prepass has no field, media, revision, or reference effects.
    final contexts = _tableTextOperations.values.any((v) => v.isNotEmpty)
        ? _tableTextContexts(
            _assembleTables([
              for (final segment in segments)
                _Paragraph(
                  LegacyWordParagraph(
                    startCp: segment.$1,
                    endCp: segment.$3,
                    runs: const [],
                    style: const LegacyWordParagraphStyle(),
                  ),
                  segment.$5.properties,
                  segment.$4,
                ),
            ]),
          )
        : const <int, _TableTextContext>{};
    final paragraphs = [
      for (final segment in segments)
        _paragraph(
          segment.$1,
          segment.$2,
          segment.$3,
          segment.$4,
          segment.$5,
          contexts[segment.$1],
        ),
    ];
    if (_fieldResults.isNotEmpty) {
      throw const FormatException('Unclosed Word field.');
    }
    _finishFieldRevisions();
    return _assembleTables(paragraphs);
  }

  String _plainText(List<LegacyWordBlock> blocks) {
    final plain = StringBuffer();
    void content(List<LegacyWordBlock> values, int depth) {
      if (depth > 63) {
        throw const FormatException('Word tables are nested too deeply.');
      }
      for (var index = 0; index < values.length; index++) {
        if (index != 0) plain.write('\n');
        switch (values[index]) {
          case LegacyWordParagraph(:final runs):
            for (final run in runs) {
              if (!run.style.hidden) plain.write(run.text);
            }
          case LegacyWordTable(:final rows):
            for (var row = 0; row < rows.length; row++) {
              if (row != 0) plain.write('\n');
              for (var cell = 0; cell < rows[row].cells.length; cell++) {
                if (cell != 0) plain.write('\t');
                content(rows[row].cells[cell].blocks, depth + 1);
              }
            }
        }
      }
    }

    content(blocks, 0);
    return plain.toString();
  }

  void _storyWarnings() {
    if (source.missingDeclaredExtent) {
      warnings.add(LegacyWordWarning.unsupportedFormatting);
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

  List<_Sprm> _readProperties(
    Uint8List bytes, [
    int depth = 0,
    bool recoverPapxOrphanByte = false,
  ]) {
    if (depth > 16) {
      throw const FormatException(
        'Word indirect properties are nested too deeply.',
      );
    }
    final operations = _decodeSprms(
      bytes,
      budget,
      stopAtTableProperties: true,
      onPapxOrphanByte: recoverPapxOrphanByte
          ? () {
              warnings.add(LegacyWordWarning.recoveredNonconformingProperties);
              warnings.add(LegacyWordWarning.unsupportedFormatting);
            }
          : null,
    );
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
      if (operation.code != 0x6646 &&
          operation.code != 0x646b &&
          operation.code != 0x6645) {
        append([operation]);
        continue;
      }
      final offset = operation.data.u32(0);
      final data = source.data;
      final length = data.u16(offset);
      if (operation.code == 0x646b && length < 10) {
        throw const FormatException('Invalid Word indirect table properties.');
      }
      final cached = _indirectProperties[offset];
      if (cached != null) {
        append(cached);
        if (operation.code == 0x646b) break;
        continue;
      }
      if (!_indirectActive.add(offset)) {
        throw const FormatException('Cyclic Word indirect properties.');
      }
      final nested = _readProperties(data.slice(offset + 2, length), depth + 1);
      _indirectActive.remove(offset);
      _indirectProperties[offset] = nested;
      append(nested);
      // PTableProps replaces the remainder of its containing array; older
      // table properties after it are intended for readers without styles.
      if (operation.code == 0x646b) break;
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

  _Paragraph _paragraph(
    int start,
    int contentEnd,
    int end,
    int terminator,
    _PreparedParagraph prepared,
    _TableTextContext? tableContext,
  ) {
    final terminalCp = end > start ? end - 1 : start;
    _ResolvedStyle resolve(int index) => tableContext == null
        ? _resolveStyle(index)
        : _resolveStyleOverTable(index, tableContext);
    final properties = tableContext == null
        ? prepared.properties
        : <String, Object?>{
            ...resolve(prepared.styleIndex).paragraph,
            'styleIndex': prepared.styleIndex,
          };
    if (tableContext != null) {
      _applyParagraph(
        prepared.operations,
        properties,
        budget,
        warnings,
        resolveParagraphStyle: (index) => resolve(index).paragraph,
      );
    }
    final styleIndex = properties['styleIndex'] as int? ?? prepared.styleIndex;
    final resolved = resolve(styleIndex);
    final characterBase = _applyListFormatting(properties, resolved.character);
    final style = _paragraphStyle(properties, styleIndex);
    final formattingRevision = _paragraphRevision(properties);
    final mark = terminator == 13 || terminator == 12 || terminator == 7
        ? _paragraphMark(terminalCp, characterBase)
        : null;
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
      final character = _characterAt(cp, characterBase);
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
      final insertionRevision = inserted
          ? _revisionInfo(character, 'insertion')
          : null;
      final deletionRevision = deleted
          ? _revisionInfo(character, 'deletion')
          : null;
      final revision = deletionRevision ?? insertionRevision;
      final author = revision?.author;
      final time = revision?.time;
      final characterRevision = _characterRevision(character);
      final formattingSaveId = character['formattingSaveId'] as int?;
      if (character['special'] == true ||
          character['object'] == true ||
          character['ole2'] == true ||
          character['pictureLocation'] != null) {
        _appendMediaRuns(
          cp,
          spanEnd,
          character,
          LegacyWordMediaPresentation(
            hidden: runStyle.hidden,
            inserted: inserted,
            deleted: deleted,
            revisionAuthor: author,
            revisionTime: time,
            insertionRevision: insertionRevision,
            deletionRevision: deletionRevision,
          ),
        );
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
            previous.time == time &&
            previous.insertionRevision == insertionRevision &&
            previous.deletionRevision == deletionRevision &&
            previous.formattingRevision == characterRevision &&
            previous.formattingSaveId == formattingSaveId) {
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
          insertionRevision,
          deletionRevision,
          characterRevision,
          formattingSaveId,
        );
      }

      while (cp < spanEnd) {
        final unit = body[cp];
        _captureFieldRevision(cp, unit, character, runStyle.hidden);
        if (_referenceAnchors.contains(cp)) {
          _referenceCharacterStyles[cp] = runStyle;
          _referencePresentations[cp] = LegacyWordMediaPresentation(
            hidden: runStyle.hidden || _fieldResults.contains(false),
            inserted: inserted,
            deleted: deleted,
            revisionAuthor: author,
            revisionTime: time,
            insertionRevision: insertionRevision,
            deletionRevision: deletionRevision,
          );
        }
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
              _fieldResults[_fieldResults.length - 1] = !_privateFieldSeparators
                  .contains(cp);
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
            if (!_noteMarkerCps.contains(cp)) {
              warnings.add(LegacyWordWarning.notesOmitted);
            }
            printable = -1;
          case 5:
            if (!_commentMarkerCps.contains(cp)) {
              warnings.add(LegacyWordWarning.commentsOmitted);
            }
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
            if (unit < 32 && unit != 9 && unit != 12 && unit != 14) {
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
        formattingRevision: formattingRevision,
        numberingRevision: _numberingRevision(properties),
        mark: mark,
        revisionSaveId: properties['paragraphSaveId'] as int?,
      ),
      properties,
      terminator,
    );
  }

  void _appendMediaRuns(
    int first,
    int end,
    _Props character,
    LegacyWordMediaPresentation presentation,
  ) {
    var low = 0, high = _invisibleMediaRanges.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_invisibleMediaRanges[middle].$2 <= first) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    var cursor = first, index = low;
    while (cursor < end) {
      final range = index < _invisibleMediaRanges.length
          ? _invisibleMediaRanges[index]
          : null;
      final hidden = range != null && range.$1 <= cursor;
      final boundary = range == null
          ? end
          : hidden
          ? range.$2
          : range.$1;
      final finish = boundary < end ? boundary : end;
      if (mediaRuns.length >= 200000 || finish <= cursor) {
        throw const FormatException(
          'Word media references exceed the complexity limit.',
        );
      }
      mediaRuns.add(
        LegacyWordMediaRun(
          startCp: cursor,
          endCp: finish,
          pictureLocation: character['pictureLocation'] as int?,
          special: character['special'] == true,
          object: character['object'] == true,
          ole2: character['ole2'] == true,
          data: character['data'] == true,
          presentation: hidden
              ? LegacyWordMediaPresentation(
                  hidden: true,
                  inserted: presentation.inserted,
                  deleted: presentation.deleted,
                  revisionAuthor: presentation.revisionAuthor,
                  revisionTime: presentation.revisionTime,
                  insertionRevision: presentation.insertionRevision,
                  deletionRevision: presentation.deletionRevision,
                )
              : presentation,
        ),
      );
      cursor = finish;
      if (hidden && cursor == range.$2) index++;
    }
  }

  LegacyWordParagraphStyle _paragraphStyle(_Props properties, int styleIndex) {
    final outline = properties['outline'] as int?;
    return LegacyWordParagraphStyle(
      layout: _paragraphLayout(properties),
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
      listId: properties['listId'] as int?,
      listLevel: properties['listLevel'] as int?,
      tabs: properties['tabs'] as List<LegacyWordTabStop>? ?? const [],
      borders:
          properties['borders']
              as Map<LegacyWordBorderSide, LegacyWordBorder>? ??
          const {},
      shading: properties['shading'] as LegacyWordShading?,
    );
  }

  LegacyWordCharacterStyle _characterStyle(
    _Props properties, {
    bool useDocumentDefaultFont = true,
  }) {
    String? font(String key, int? documentDefault) {
      final index =
          properties[key] as int? ??
          (useDocumentDefaultFont ? documentDefault : null);
      if (index != null) {
        if (index >= 0 && index < fonts.length) {
          return fonts[index];
        } else if (fonts.isNotEmpty) {
          warnings.add(LegacyWordWarning.unsupportedFormatting);
        }
      }
      return null;
    }

    return LegacyWordCharacterStyle(
      bold: properties['bold'] == true,
      italic: properties['italic'] == true,
      underline: properties['underline'] == true,
      underlineStyle: properties['underlineStyle'] as String?,
      strike: properties['strike'] == true,
      doubleStrike: properties['doubleStrike'] == true,
      smallCaps: properties['smallCaps'] == true,
      allCaps: properties['allCaps'] == true,
      hidden: properties['hidden'] == true,
      fontName: font('fontIndex', defaultFont),
      scriptFonts: LegacyWordScriptFonts(
        nonAscii: font('nonAsciiFontIndex', defaultNonAsciiFont),
        eastAsia: font('eastAsianFontIndex', defaultEastAsianFont),
        complexScript: font('complexScriptFontIndex', defaultComplexScriptFont),
      ),
      fontSizeHalfPoints: properties['fontSize'] as int?,
      kerningThresholdHalfPoints: properties['kerning'] as int? ?? 0,
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
    this.insertionRevision,
    this.deletionRevision,
    this.formattingRevision,
    this.formattingSaveId,
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
  final LegacyWordRevisionInfo? insertionRevision;
  final LegacyWordRevisionInfo? deletionRevision;
  final LegacyWordCharacterFormattingRevision? formattingRevision;
  final int? formattingSaveId;
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
    insertionRevision: insertionRevision,
    deletionRevision: deletionRevision,
    formattingRevision: formattingRevision,
    formattingSaveId: formattingSaveId,
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
