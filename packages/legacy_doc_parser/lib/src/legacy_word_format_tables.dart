// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

// Traversal of FKP, STSH, FFN and SEPX structures is adapted in part from
// JSDoc src/docToText.js (0BSD), 821695a884e0c0bb8592a635d9524bb3e116cd67.
// License and exact source provenance: third_party/JSDoc-0BSD.txt.
// Bounds, CP/FC association, PRM precedence and error handling are authored
// against MS-DOC rather than inheriting its permissive fallbacks.

class _FkpRun {
  const _FkpRun(this.startFc, this.endFc, this.styleIndex, this.operations);
  final int startFc;
  final int endFc;
  final int styleIndex;
  final List<_Sprm> operations;
}

class _FkpIndex {
  const _FkpIndex(this.runs, this.fallback, {this.finalPageEndFc});
  final List<_FkpRun> runs;
  final _FkpRun? fallback;

  // Keep the physical final FKP limit separate from clipped BTE ranges.
  final int? finalPageEndFc;
  _FkpRun at(int fc) {
    if (fallback != null) return fallback!;
    var low = 0, high = runs.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final run = runs[middle];
      if (fc < run.startFc) {
        high = middle;
      } else if (fc >= run.endFc) {
        low = middle + 1;
      } else {
        return run;
      }
    }
    throw const FormatException('Word text has no referenced formatting run.');
  }
}

class _Style {
  const _Style(
    this.name,
    this.builtinId,
    this.parent,
    this.kind,
    this.paragraph,
    this.character,
    this.table,
  );
  final String name;
  final int builtinId;
  final int parent;
  final int kind;
  final List<_Sprm> paragraph;
  final List<_Sprm> character;
  final List<_Sprm> table;
}

class _ResolvedStyle {
  const _ResolvedStyle(this.paragraph, this.character);
  final _Props paragraph;
  final _Props character;
}

extension _WordFormattingTables on _StructuredWordParser {
  _FkpIndex _readFkp({required bool paragraph}) {
    final (offset, length) = source.pair(paragraph ? 13 : 12);
    if (length == 0) {
      // This also keeps the deliberately minimal historical text-only fixtures
      // readable. No formatting is invented when the bin table is absent.
      warnings.add(LegacyWordWarning.unsupportedFormatting);
      return _FkpIndex(const [], _FkpRun(0, source.word.length, 0, const []));
    }
    if (length < 12 || (length - 4) % 8 != 0) {
      throw const FormatException('Invalid Word formatting bin table.');
    }
    final count = (length - 4) ~/ 8;
    if (count > 8192) {
      throw const FormatException(
        'Word formatting exceeds the preview complexity limit.',
      );
    }
    final bins = _Bytes(source.table.slice(offset, length));
    final pages = (count + 1) * 4;
    final result = <_FkpRun>[];
    var previousLimit = -1;
    int? finalPageEndFc;
    for (var i = 0; i < count; i++) {
      final lower = bins.u32(i * 4), upper = bins.u32((i + 1) * 4);
      if (upper <= lower || lower < previousLimit) {
        throw const FormatException('Word formatting bins are not ordered.');
      }
      previousLimit = upper;
      // PnFkp's upper ten bits are unused and MUST be ignored (MS-DOC).
      final pageNumber = bins.u32(pages + i * 4) & 0x003fffff;
      final page = _Bytes(source.word.slice(pageNumber * 512, 512));
      final runs = page.u8(511);
      final descriptors = (runs + 1) * 4;
      final headerEnd = descriptors + runs * (paragraph ? 13 : 1);
      if (runs == 0 || headerEnd > 511) {
        throw const FormatException('Invalid Word formatting page.');
      }
      finalPageEndFc = page.u32(runs * 4);
      var previous = -1;
      var covered = lower;
      for (var run = 0; run < runs; run++) {
        final first = page.u32(run * 4), last = page.u32((run + 1) * 4);
        if (last <= first || first < previous) {
          throw const FormatException('Word formatting runs are not ordered.');
        }
        previous = last;
        // A bin selects this page for its FC interval. A page can describe a
        // larger range; only its intersection with the selected bin is used.
        if (last <= lower || first >= upper) continue;
        final clippedFirst = first < lower ? lower : first;
        final clippedLast = last > upper ? upper : last;
        if (clippedFirst != covered) {
          throw const FormatException('Incomplete Word formatting bin.');
        }
        covered = clippedLast;
        final propertyOffset =
            page.u8(descriptors + run * (paragraph ? 13 : 1)) * 2;
        var styleIndex = 0;
        var operations = const <_Sprm>[];
        if (propertyOffset != 0) {
          if (propertyOffset < headerEnd || propertyOffset >= 511) {
            throw const FormatException(
              'Invalid Word formatting property offset.',
            );
          }
          final cb = page.u8(propertyOffset);
          var start = propertyOffset + 1;
          var end = start + cb;
          if (paragraph) {
            if (cb == 0) {
              start = propertyOffset + 2;
              end = start + 2 * page.u8(propertyOffset + 1);
            } else {
              end = propertyOffset + 2 * cb;
            }
            if (end - start < 2) {
              throw const FormatException(
                'Invalid Word paragraph property size.',
              );
            }
            styleIndex = page.u16(start);
            start += 2;
          }
          if (end > 511 || end < start) {
            throw const FormatException(
              'Truncated Word formatting properties.',
            );
          }
          operations = _readProperties(
            page.slice(start, end - start),
            0,
            paragraph && cb == 0,
          );
        }
        result.add(_FkpRun(clippedFirst, clippedLast, styleIndex, operations));
        if (result.length > 200000) {
          throw const FormatException(
            'Word formatting runs exceed the preview complexity limit.',
          );
        }
      }
      if (covered != upper) {
        throw const FormatException('Incomplete Word formatting bin.');
      }
    }
    return _FkpIndex(result, null, finalPageEndFc: finalPageEndFc);
  }

  void _readFonts() {
    final (offset, length) = source.pair(15);
    if (length == 0) return;
    final input = _Bytes(source.table.slice(offset, length));
    var position = 0;
    if (input.u16(0) == 0xffff) position += 2;
    final count = input.u16(position), extra = input.u16(position + 2);
    position += 4;
    if (count > 4096 || extra > 1024) {
      throw const FormatException('Invalid Word font table size.');
    }
    for (var index = 0; index < count; index++) {
      final size = input.u8(position) + 1;
      if (size < 42 || size.isOdd) {
        throw const FormatException('Invalid Word font record.');
      }
      input.require(position, size + extra);
      final units = <int>[];
      var terminated = false;
      for (var q = position + 40; q < position + size; q += 2) {
        final unit = input.u16(q);
        if (unit == 0) {
          terminated = true;
          break;
        }
        units.add(unit);
      }
      if (!terminated) {
        throw const FormatException('Unterminated Word font name.');
      }
      _validateUnicode(units);
      fonts.add(String.fromCharCodes(units));
      position += size + extra;
    }
    if (position != input.length) {
      throw const FormatException('Unexpected Word font table data.');
    }
  }

  void _readStyles() {
    final (offset, length) = source.pair(1);
    if (length == 0) return;
    final input = _Bytes(source.table.slice(offset, length));
    final headerLength = input.u16(0);
    input.require(2, headerLength);
    if (headerLength < 4) {
      throw const FormatException('Invalid Word stylesheet header.');
    }
    final count = input.u16(2), baseLength = input.u16(4);
    if (count > 4096 ||
        baseLength < 10 ||
        baseLength > 64 ||
        baseLength.isOdd) {
      throw const FormatException('Invalid Word stylesheet size.');
    }
    // MS-DOC 2.9.274 Stshif / 2.9.272 STSHI. Each script has its own
    // default font index; the ASCII face must not replace the other slots.
    if (headerLength >= 18) {
      defaultFont = input.i16(14);
      defaultEastAsianFont = input.i16(16);
      defaultNonAsciiFont = input.i16(18);
    }
    if (headerLength >= 20) defaultComplexScriptFont = input.i16(20);
    var position = 2 + headerLength;
    for (var index = 0; index < count; index++) {
      final size = input.u16(position);
      position += 2;
      if (size == 0) continue;
      final record = _Bytes(input.slice(position, size));
      position += size;
      record.require(0, baseLength);
      final builtin = record.u16(0) & 0x0fff;
      final kindParent = record.u16(2),
          kind = kindParent & 15,
          parent = kindParent >> 4;
      final upxCount = record.u16(4) & 15;
      final nameLength = record.u16(baseLength);
      if (nameLength > 1024) {
        throw const FormatException('Word style name exceeds the size limit.');
      }
      record.require(baseLength + 2, (nameLength + 1) * 2);
      final nameUnits = [
        for (var j = 0; j < nameLength; j++) record.u16(baseLength + 2 + j * 2),
      ];
      _validateUnicode(nameUnits);
      if (record.u16(baseLength + 2 + nameLength * 2) != 0) {
        throw const FormatException('Unterminated Word style name.');
      }
      var upx = baseLength + 4 + nameLength * 2;
      var paragraph = const <_Sprm>[];
      var character = const <_Sprm>[];
      var table = const <_Sprm>[];
      for (var u = 0; u < upxCount; u++) {
        final bytes = record.u16(upx);
        upx += 2;
        final data = record.slice(upx, bytes);
        if (kind == 3 && u == 0) {
          // Table styles cannot contain Data-stream indirections. Decode the
          // actual UPX first and validate its property group before use.
          table = _decodeSprms(data, budget);
        } else if ((kind == 1 && u == 0) || (kind == 3 && u == 1)) {
          if (bytes < 2) {
            throw const FormatException(
              'Invalid Word style paragraph properties.',
            );
          }
          paragraph = kind == 3
              ? _decodeSprms(Uint8List.sublistView(data, 2), budget)
              : _readProperties(Uint8List.sublistView(data, 2));
        } else if ((kind == 1 && u == 1) ||
            (kind == 2 && u == 0) ||
            (kind == 3 && u == 2)) {
          character = kind == 3
              ? _decodeSprms(data, budget)
              : _readProperties(data);
        } else if (bytes != 0) {
          warnings.add(LegacyWordWarning.unsupportedFormatting);
        }
        upx += bytes;
        if (upx.isOdd) upx++;
        record.require(0, upx);
      }
      if (kind != 1 && kind != 2 && kind != 3) {
        warnings.add(LegacyWordWarning.unsupportedFormatting);
      }
      styles[index] = _Style(
        String.fromCharCodes(nameUnits),
        builtin,
        parent,
        kind,
        paragraph,
        character,
        table,
      );
    }
    // Newer STSH records can carry documented post-STD structures. They are
    // outside the supported visual subset, never interpreted as more styles.
    if (position < input.length) {
      warnings.add(LegacyWordWarning.unsupportedFormatting);
    }
  }

  _ResolvedStyle _resolveStyle(int index, [int depth = 0]) {
    final cached = _resolvedStyles[index];
    if (cached != null) return cached;
    if (index == 0xfff) return const _ResolvedStyle({}, {});
    if (depth > 64 || !_styleActive.add(index)) {
      throw const FormatException(
        'Cyclic or excessive Word style inheritance.',
      );
    }
    final style = styles[index];
    if (style == null) {
      _styleActive.remove(index);
      if (index == 0 || index == 10) return const _ResolvedStyle({}, {});
      throw const FormatException('Referenced Word style is missing.');
    }
    final parent = style.parent == 0xfff
        ? const _ResolvedStyle({}, {})
        : _resolveStyle(style.parent, depth + 1);
    final paragraph = <String, Object?>{...parent.paragraph};
    final character = <String, Object?>{...parent.character};
    if (style.builtinId >= 1 && style.builtinId <= 9) {
      paragraph['outline'] = style.builtinId - 1;
    }
    _applyParagraph(style.paragraph, paragraph, budget, warnings);
    _applyCharacter(
      style.character,
      character,
      parent.character,
      budget,
      warnings,
    );
    _styleActive.remove(index);
    return _resolvedStyles[index] = _ResolvedStyle(paragraph, character);
  }

  LegacyWordCharacterStyle? _lineNumberStyle() {
    // StdfBase.sti is the semantic built-in identity, independent of the
    // stylesheet index and localized display name. These generated characters
    // have no CP/CHPX run from which the usual text writer can recover it.
    final matches = styles.entries
        .where((entry) => entry.value.builtinId == 40)
        .toList();
    if (matches.isEmpty) return null;
    if (matches.length != 1 || matches.single.value.kind != 2) {
      throw const FormatException(
        'Invalid or duplicate Word line number style.',
      );
    }
    return _characterStyle(_resolveStyle(matches.single.key).character);
  }

  void _readAuthors() {
    final (offset, length) = source.pair(51);
    if (length == 0) return;
    final input = _Bytes(source.table.slice(offset, length));
    var position = 0;
    final unicode = input.u16(0) == 0xffff;
    if (unicode) position += 2;
    final count = input.u16(position), extra = input.u16(position + 2);
    position += 4;
    if (count > 32768 || extra > 1024) {
      throw const FormatException(
        'Word revision metadata exceeds the size limit.',
      );
    }
    for (var i = 0; i < count; i++) {
      final units = unicode ? input.u16(position) : input.u8(position);
      position += unicode ? 2 : 1;
      if (units > 4096) {
        throw const FormatException(
          'Word revision author exceeds the size limit.',
        );
      }
      input.require(position, units * (unicode ? 2 : 1) + extra);
      final characters = [
        for (var j = 0; j < units; j++)
          unicode
              ? input.u16(position + j * 2)
              : (_wordCompressedUnicode[input.u8(position + j)] ??
                    input.u8(position + j)),
      ];
      _validateUnicode(characters);
      authors.add(String.fromCharCodes(characters));
      position += units * (unicode ? 2 : 1) + extra;
    }
    if (position != input.length) {
      throw const FormatException('Unexpected Word revision-author data.');
    }
  }

  List<LegacyWordSection> _readSections() {
    final mainLength = source.bodyLength;
    if (mainLength == 0) return const [];
    final noteDefaults = _documentNoteProperties();
    final (offset, length) = source.pair(6);
    if (length == 0) {
      return [_sectionFromProperties(noteDefaults, 0, mainLength)];
    }
    if (length < 20 || (length - 4) % 16 != 0) {
      throw const FormatException('Invalid Word section table.');
    }
    final count = (length - 4) ~/ 16;
    if (count > 4096) {
      throw const FormatException(
        'Word sections exceed the preview complexity limit.',
      );
    }
    final input = _Bytes(source.table.slice(offset, length));
    if (input.u32(0) != 0) {
      throw const FormatException('Invalid Word section start.');
    }
    final records = (count + 1) * 4;
    final result = <LegacyWordSection>[];
    for (var i = 0; i < count; i++) {
      final start = input.u32(i * 4), declaredEnd = input.u32((i + 1) * 4);
      // LibreOffice can emit an empty initial section on a DOCX -> DOC save.
      // Keep its layout/header identity rather than attaching its settings to
      // the following text. Other duplicate/decreasing CPs remain invalid.
      final emptyInitial =
          i == 0 && count > 1 && start == 0 && declaredEnd == 0;
      if ((declaredEnd <= start && !emptyInitial) ||
          start >= mainLength ||
          (i < count - 1 && declaredEnd > mainLength)) {
        throw const FormatException('Word section positions are not ordered.');
      }
      final end = declaredEnd > mainLength ? mainLength : declaredEnd;
      if (!emptyInitial && i < count - 1 && body[end - 1] != 12) {
        throw const FormatException(
          'Word section has no terminating section mark.',
        );
      }
      final sepx = input.u32(records + i * 12 + 2);
      var operations = const <_Sprm>[];
      if (sepx != 0xffffffff) {
        final size = source.word.u16(sepx);
        operations = _readProperties(source.word.slice(sepx + 2, size));
      }
      final properties = _sectionProperties(
        [
          ...operations,
          if (!emptyInitial) ..._pieceProperties(source.pieceAt(end - 1)),
        ],
        budget,
        warnings,
        initial: noteDefaults,
      );
      if (emptyInitial) warnings.add(LegacyWordWarning.recoveredEmptySection);
      result.add(_sectionFromProperties(properties, start, end));
    }
    if (result.last.endCp != mainLength) {
      throw const FormatException(
        'Word section table does not cover the body.',
      );
    }
    return result;
  }
}
