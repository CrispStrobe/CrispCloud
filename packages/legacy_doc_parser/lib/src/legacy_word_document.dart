// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'bounded_cfb_reader.dart';
import 'legacy_word_structured_model.dart';
import 'legacy_word_structured_parser.dart';

export 'legacy_word_structured_model.dart';

/// Parses referenced body text, resolved formatting and structural metadata.
/// Unsupported features are explicit in [LegacyWordDocument.warnings].
///
/// By default malformed structures are rejected. With [recover], damage
/// confined to an auxiliary feature — text-box stories, floating-drawing
/// anchors, list tables, a single picture record, a dangling style
/// reference, contradictory field flags — omits or normalizes that feature
/// and records a `recovered*`/`*Omitted` warning instead of refusing the
/// document, as Word does. Nothing is invented: omitted content is absent,
/// never guessed. Use it when a person opens a document; keep the default
/// for validation.
LegacyWordDocument parseLegacyWordDocument(
  Uint8List bytes, {
  bool recover = false,
}) => readStructuredLegacyWord(bytes, recover: recover);

/// Read-only body-text extraction for Word 6/95 and Word 97–2007 DOC/DOT.
/// Word 6/95 supports declared UTF-16, Mac Roman and bounded Windows-1252
/// profiles; unsupported legacy character sets/locales are explicitly refused.
///
/// Uses the documented FIB/CLX piece table, never a scan for printable strings:
/// unreferenced text and unrelated embedded-object streams must not appear in a
/// preview. Formatting, images, headers, notes and tracked-change semantics are
/// not reconstructed. The original compound file is never modified.
///
/// Format references: Microsoft [MS-DOC] §§2.4.1, 2.5, 2.8.35, 2.9.38,
/// 2.9.73 and 2.9.177 (FIB, CLX, PlcPcd, FcCompressed and Pcdt).
String extractLegacyWordText(Uint8List bytes) {
  const maxCharacters = 4 * 1024 * 1024;
  final compound = BoundedCfbReader(bytes);
  final word = compound.readPath('WordDocument');
  if (word == null || word.length < 32) {
    throw const FormatException('The WordDocument stream is missing.');
  }
  var fib = _WordBytes(word);
  if (fib.u16(0) == 0xa5dc) return _word6Text(word);
  if (fib.u16(0) != 0xa5ec) {
    throw const FormatException('This is not a Word binary document.');
  }
  if (!const {
    0x00c1,
    0x00c2,
    0x00d9,
    0x0101,
    0x010c,
    0x0112,
  }.contains(fib.u16(2))) {
    throw const FormatException(
      'This older Word binary version is not supported. Save it as DOCX.',
    );
  }
  final flags = fib.u16(10);
  if ((flags & 0x8100) != 0) {
    throw const FormatException(
      'This Word document is encrypted. Open it in Word and save an unlocked copy.',
    );
  }

  // Walk the variable-sized FIB arrays rather than assuming one fixed offset.
  final csw = fib.u16(32);
  if (csw != 14) throw const FormatException('Invalid Word FIB word count.');
  final cslwOffset = 34 + csw * 2;
  final cslw = fib.u16(cslwOffset);
  if (cslw != 22) throw const FormatException('Invalid Word FIB long count.');
  final longStart = cslwOffset + 2;
  final declaredExtent = fib.u32(longStart);
  if (declaredExtent != 0) {
    // Match the structured reader: a positive cbMac bounds every FIB and text
    // read, even when the physical CFB stream contains additional bytes. Zero
    // remains the historical minimal-export compatibility case.
    fib.require(0, declaredExtent);
    fib = _WordBytes(Uint8List.sublistView(word, 0, declaredExtent));
  }
  final characterCount = fib.u32(longStart + 3 * 4);
  if (characterCount > maxCharacters) {
    throw const FormatException('Word text exceeds the preview size limit.');
  }
  final pairCountOffset = longStart + cslw * 4;
  final pairCount = fib.u16(pairCountOffset);
  if (pairCount < 34 || pairCount > 183) {
    throw const FormatException('Invalid Word FIB offset count.');
  }
  fib.require(pairCountOffset + 2, pairCount * 8);
  final clxPair = pairCountOffset + 2 + 33 * 8;
  final clxOffset = fib.u32(clxPair);
  final clxLength = fib.u32(clxPair + 4);
  if (characterCount == 0) return '';
  final table = compound.readPath((flags & 0x0200) != 0 ? '1Table' : '0Table');
  if (table == null) {
    throw const FormatException('The selected Word text table is missing.');
  }
  return _readableBody(
    _textFromClx(word, fib, table, clxOffset, clxLength, characterCount),
  );
}

/// Main-body text through the piece table (CLX) in [table].
String _textFromClx(
  Uint8List word,
  _WordBytes fib,
  Uint8List table,
  int clxOffset,
  int clxLength,
  int characterCount,
) {
  final textTable = _WordBytes(table);
  textTable.require(clxOffset, clxLength);
  if (clxLength < 5) {
    throw const FormatException('Word has no text piece table.');
  }
  var position = clxOffset;
  final end = clxOffset + clxLength;
  while (position < end && table[position] == 1) {
    if (position + 3 > end) {
      throw const FormatException('Truncated Word text properties.');
    }
    position += 3 + textTable.u16(position + 1);
    if (position > end) {
      throw const FormatException('Truncated Word text properties.');
    }
  }
  if (position + 5 > end || table[position] != 2) {
    throw const FormatException('Word has no valid text piece table.');
  }
  final pieceBytes = textTable.u32(position + 1);
  position += 5;
  if (pieceBytes < 16 ||
      (pieceBytes - 4) % 12 != 0 ||
      position + pieceBytes != end) {
    throw const FormatException('Invalid Word text piece table size.');
  }
  final pieceCount = (pieceBytes - 4) ~/ 12;
  if (pieceCount > 100000 || textTable.u32(position) != 0) {
    throw const FormatException('Invalid Word text piece count or start.');
  }
  final pcdStart = position + (pieceCount + 1) * 4;
  final output = StringBuffer();
  var extracted = 0;
  for (var index = 0; index < pieceCount; index++) {
    final start = textTable.u32(position + index * 4);
    final next = textTable.u32(position + (index + 1) * 4);
    if (next <= start || next > 0x7fffffff) {
      throw const FormatException('Word text positions are not ordered.');
    }
    if (start >= characterCount) continue;
    final count = (next < characterCount ? next : characterCount) - start;
    final fc = textTable.u32(pcdStart + index * 8 + 2);
    if ((fc & 0x80000000) != 0) {
      throw const FormatException('Invalid Word text piece offset.');
    }
    final compressed = (fc & 0x40000000) != 0;
    final rawOffset = fc & 0x3fffffff;
    if (compressed && rawOffset.isOdd) {
      throw const FormatException('Invalid compressed Word text offset.');
    }
    final offset = compressed ? rawOffset ~/ 2 : rawOffset;
    fib.require(offset, count * (compressed ? 1 : 2));
    if (compressed) {
      for (var character = 0; character < count; character++) {
        final code = word[offset + character];
        output.writeCharCode(_compressedUnicode[code] ?? code);
      }
    } else {
      // CPs are UTF-16 code units; keep surrogate pairs intact across pieces.
      output.write(
        String.fromCharCodes([
          for (var character = 0; character < count; character++)
            fib.u16(offset + character * 2),
        ]),
      );
    }
    extracted += count;
  }
  if (extracted != characterCount) {
    throw const FormatException('Word text is incomplete.');
  }
  return output.toString();
}

// [MS-DOC] FcCompressed uses these mappings, not an arbitrary locale code page.
const _compressedUnicode = <int, int>{
  0x82: 0x201a,
  0x83: 0x0192,
  0x84: 0x201e,
  0x85: 0x2026,
  0x86: 0x2020,
  0x87: 0x2021,
  0x88: 0x02c6,
  0x89: 0x2030,
  0x8a: 0x0160,
  0x8b: 0x2039,
  0x8c: 0x0152,
  0x91: 0x2018,
  0x92: 0x2019,
  0x93: 0x201c,
  0x94: 0x201d,
  0x95: 0x2022,
  0x96: 0x2013,
  0x97: 0x2014,
  0x98: 0x02dc,
  0x99: 0x2122,
  0x9a: 0x0161,
  0x9b: 0x203a,
  0x9c: 0x0153,
  0x9f: 0x0178,
};

String _readableBody(String value) {
  final output = StringBuffer();
  final fields = <bool>[];
  var hiddenFields = 0;
  var needsLowSurrogate = false;
  for (final code in value.codeUnits) {
    // Validate the consumed main body before dropping controls or hidden
    // instruction text. Filtering first can hide an isolated surrogate or
    // manufacture a valid scalar from halves separated by source controls.
    // The value is assembled in CP order, so a pair may cross physical pieces
    // but cannot borrow its second unit from an unconsumed auxiliary story.
    final lowSurrogate = code >= 0xdc00 && code <= 0xdfff;
    if (needsLowSurrogate != lowSurrogate) {
      throw const FormatException('Invalid UTF-16 in Word text.');
    }
    needsLowSurrogate = code >= 0xd800 && code <= 0xdbff;
    if (code == 0x13) {
      fields.add(false);
      hiddenFields++;
    } else if (code == 0x14) {
      if (fields.isNotEmpty && !fields.last) {
        fields[fields.length - 1] = true;
        hiddenFields--;
      }
    } else if (code == 0x15) {
      if (fields.isNotEmpty && !fields.removeLast()) hiddenFields--;
    } else if (hiddenFields == 0) {
      switch (code) {
        case 0x07:
        case 0x09:
          output.write('\t');
        case 0x0b:
        case 0x0c:
        case 0x0d:
        case 0x0e:
          output.write('\n');
        case 0x1e:
          output.writeCharCode(0x2011);
        case 0x1f:
          output.writeCharCode(0x00ad);
        default:
          if (code >= 0x20 || code == 0x0a) output.writeCharCode(code);
      }
    }
  }
  if (needsLowSurrogate) {
    throw const FormatException('Invalid UTF-16 in Word text.');
  }
  return output.toString().trimRight();
}

class _WordBytes {
  _WordBytes(Uint8List bytes) : data = ByteData.sublistView(bytes);
  final ByteData data;

  void require(int start, int count) {
    if (start < 0 || count < 0 || start > data.lengthInBytes - count) {
      throw const FormatException('Truncated Word binary document.');
    }
  }

  int u16(int offset) {
    require(offset, 2);
    return data.getUint16(offset, Endian.little);
  }

  int u32(int offset) {
    require(offset, 4);
    return data.getUint32(offset, Endian.little);
  }
}

/// Main-body text recovered from a Word 97+ file whose compound directory is
/// damaged (overwritten directory or FAT entries, truncated chains), so that
/// neither this parser nor Word can open it.
///
/// Word writes the WordDocument stream first, starting at sector 0, and the
/// FAT usually survives when the directory does not. The WordDocument stream
/// is read from its FIB; the table stream is found as the FAT chain whose
/// bytes hold a valid piece table (CLX) at the FIB's `fcClx`, and the text is
/// read through that piece table exactly as [extractLegacyWordText] does.
/// Returns `null` when either stream cannot be found or a recovery bound is
/// exceeded; formatting, pictures, tables and notes are not recovered.
///
/// Admission is bounded to 64 MiB. Referenced stream extents are limited to
/// 32 MiB; CLX records to 16 MiB; main-body text to 4 Mi UTF-16 units. Across
/// attempts, at most 4096 candidates, 64 MiB of chain/CLX work and 8 Mi declared
/// character units are admitted. Rejected candidates consume the same work
/// budget, so malformed alternatives cannot repeatedly decode a large body.
String? recoverLegacyWordText(Uint8List bytes) {
  if (bytes.length > 64 * 1024 * 1024) return null;
  try {
    return _recoverLegacyWordText(bytes, _WordRecoveryBudget());
  } on _WordRecoveryLimit {
    return null;
  } on FormatException {
    return null;
  }
}

const _maxRecoveryStreamBytes = 32 * 1024 * 1024;

class _WordRecoveryLimit implements Exception {
  const _WordRecoveryLimit();
}

class _WordRecoveryBudget {
  int _bytes = 0;
  int _characters = 0;
  int _candidates = 0;

  void readBytes(int count) {
    if (count > 64 * 1024 * 1024 - _bytes) {
      throw const _WordRecoveryLimit();
    }
    _bytes += count;
  }

  void candidate(int clxBytes, int characters) {
    if (++_candidates > 4096 || characters > 8 * 1024 * 1024 - _characters) {
      throw const _WordRecoveryLimit();
    }
    _characters += characters;
    readBytes(clxBytes);
  }
}

String? _recoverLegacyWordText(Uint8List bytes, _WordRecoveryBudget budget) {
  const maxCharacters = 4 * 1024 * 1024;
  const magic = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
  if (bytes.length < 1024) return null;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return null;
  }
  final header = ByteData.sublistView(bytes);
  final shift = header.getUint16(30, Endian.little);
  if (shift != 9 && shift != 12) return null;
  final sectorSize = 1 << shift;
  final firstSector = sectorSize; // the header occupies one sector (512 → 512)
  final sectorCount = (bytes.length - firstSector) ~/ sectorSize;
  if (sectorCount < 1) return null;

  // The FAT sectors listed in the header; unusable entries are skipped.
  final fat = <int>[];
  final fatSectors = header.getUint32(44, Endian.little);
  for (var i = 0; i < 109 && i < fatSectors; i++) {
    final sector = header.getUint32(76 + i * 4, Endian.little);
    if (sector >= sectorCount) {
      fat.addAll(List.filled(sectorSize ~/ 4, 0xFFFFFFFF));
      continue;
    }
    final base = firstSector + sector * sectorSize;
    for (var j = 0; j < sectorSize; j += 4) {
      fat.add(header.getUint32(base + j, Endian.little));
    }
  }

  // Locate the FIB: sector 0 for Word-written files, else the first sector
  // that carries the Word 97+ signature.
  bool isFib(int sector) {
    final at = firstSector + sector * sectorSize;
    return header.getUint16(at, Endian.little) == 0xa5ec &&
        const {
          0x00c1,
          0x00c2,
          0x00d9,
          0x0101,
          0x010c,
          0x0112,
        }.contains(header.getUint16(at + 2, Endian.little));
  }

  var start = -1;
  for (var sector = 0; sector < sectorCount && sector < 64; sector++) {
    if (isFib(sector)) {
      start = sector;
      break;
    }
  }
  if (start < 0) return null;

  // The FAT is trusted only if it marks its own sectors as FAT sectors; an
  // overwritten FAT holds arbitrary values that would send chains astray.
  var fatSane = fat.isNotEmpty;
  for (var i = 0; i < 109 && i < fatSectors; i++) {
    final sector = header.getUint32(76 + i * 4, Endian.little);
    if (sector >= fat.length || fat[sector] != 0xFFFFFFFD) fatSane = false;
  }
  if (!fatSane) fat.clear();

  // WordDocument: its FAT chain, or (FAT lost) the contiguous bytes from its
  // FIB, which is how Word allocates it.
  final wordStart = firstSector + start * sectorSize;
  final wordLimit = wordStart + _maxRecoveryStreamBytes;
  final contiguousWord = Uint8List.sublistView(
    bytes,
    wordStart,
    wordLimit < bytes.length ? wordLimit : bytes.length,
  );
  var word = fatSane
      ? _chainBytes(
              bytes,
              fat,
              start,
              firstSector: firstSector,
              sectorSize: sectorSize,
              sectorCount: sectorCount,
              limit: _maxRecoveryStreamBytes,
              budget: budget,
            ) ??
            contiguousWord
      : contiguousWord;
  final cbMac = ByteData.sublistView(word).getUint32(64, Endian.little);
  if (cbMac != 0) {
    // A positive declared extent is authoritative even when it is too small
    // for the FIB or larger than the available stream. Never ignore it and
    // borrow bytes from an unrelated following stream.
    if (cbMac > _maxRecoveryStreamBytes || cbMac > word.length) return null;
    word = Uint8List.sublistView(word, 0, cbMac);
  }
  final fib = _WordBytes(word);
  try {
    if ((fib.u16(10) & 0x8100) != 0) return null; // encrypted / obfuscated
    final csw = fib.u16(32);
    if (csw != 14) return null;
    final cslwOffset = 34 + csw * 2;
    final cslw = fib.u16(cslwOffset);
    if (cslw != 22) return null;
    final longStart = cslwOffset + 2;
    final characterCount = fib.u32(longStart + 3 * 4);
    if (characterCount == 0 || characterCount > maxCharacters) return null;
    final pairCountOffset = longStart + cslw * 4;
    final pairCount = fib.u16(pairCountOffset);
    if (pairCount < 34 || pairCount > 183) return null;
    fib.require(pairCountOffset + 2, pairCount * 8);
    final clxPair = pairCountOffset + 2 + 33 * 8;
    final clxOffset = fib.u32(clxPair);
    final clxLength = fib.u32(clxPair + 4);
    if (clxLength < 5 ||
        clxLength > 16 * 1024 * 1024 ||
        clxOffset > _maxRecoveryStreamBytes - clxLength) {
      return null;
    }

    // The table stream is a FAT chain no other entry points into, or (FAT
    // lost) a contiguous run starting at some sector. Only a piece table that
    // validates at exactly fcClx, accounting for every character, counts.
    final pointedTo = <int>{
      for (final next in fat)
        if (next < sectorCount) next,
    };
    Iterable<Uint8List?> candidates() sync* {
      for (var head = 0; head < sectorCount && head < fat.length; head++) {
        if (head == start || pointedTo.contains(head)) continue;
        if (fat[head] >= 0xFFFFFFFC && fat[head] != 0xFFFFFFFE) continue;
        yield _chainBytes(
          bytes,
          fat,
          head,
          firstSector: firstSector,
          sectorSize: sectorSize,
          sectorCount: sectorCount,
          limit: clxOffset + clxLength,
          budget: budget,
        );
      }
      // Small table streams live in the mini stream (64-byte mini sectors),
      // so a contiguous table can start at any 64-byte boundary.
      final wordAt = firstSector + start * sectorSize;
      for (var at = firstSector; ; at += 64) {
        if (at + clxOffset + clxLength > bytes.length) break;
        if (at == wordAt) continue;
        if (bytes[at + clxOffset] != 1 && bytes[at + clxOffset] != 2) continue;
        yield Uint8List.sublistView(bytes, at, at + clxOffset + clxLength);
      }
    }

    for (final table in candidates()) {
      if (table == null || table.length < clxOffset + clxLength) continue;
      if (table[clxOffset] != 1 && table[clxOffset] != 2) continue;
      budget.candidate(clxLength, characterCount);
      try {
        final text = _textFromClx(
          word,
          fib,
          table,
          clxOffset,
          clxLength,
          characterCount,
        );
        return _readableBody(text);
      } on FormatException {
        continue;
      }
    }
    return null;
  } on FormatException {
    return null;
  }
}

Uint8List? _chainBytes(
  Uint8List bytes,
  List<int> fat,
  int head, {
  required int firstSector,
  required int sectorSize,
  required int sectorCount,
  required int limit,
  required _WordRecoveryBudget budget,
}) {
  final out = BytesBuilder(copy: false);
  final visited = <int>{};
  var sector = head;
  while (out.length < limit) {
    if (sector >= sectorCount || !visited.add(sector)) return null;
    final at = firstSector + sector * sectorSize;
    final remaining = limit - out.length;
    final take = remaining < sectorSize ? remaining : sectorSize;
    budget.readBytes(take);
    out.add(Uint8List.sublistView(bytes, at, at + take));
    final next = sector < fat.length ? fat[sector] : 0xFFFFFFFF;
    if (next == 0xFFFFFFFE) break;
    sector = next;
  }
  return out.takeBytes();
}

/// Text of a Word 6.0 / Word 95 document (`wIdent` 0xA5DC, nFib 101–105).
///
/// Only the main text is read: these files have 8-bit or UTF-16 text in the
/// WordDocument stream, either at `fcMin` (fast-saved files are complex and
/// carry their piece table in the same stream at `fcClx`). The character
/// set is declared UTF-16 (`fExtChar`), Mac Roman, or Windows-1252 when the
/// charset is ANSI and the locale is unspecified/legacy or explicitly en-US.
/// Other 8-bit charset/locale declarations are refused rather than guessed.
String _word6Text(Uint8List word) {
  const maxCharacters = 4 * 1024 * 1024;
  final fib = _WordBytes(word);
  final nFib = fib.u16(2);
  if (nFib < 101 || nFib > 105) {
    throw const FormatException(
      'This older Word binary version is not supported. Save it as DOCX.',
    );
  }
  final flags = fib.u16(10);
  if ((flags & 0x0100) != 0) {
    throw const FormatException(
      'This Word document is encrypted. Open it in Word and save an unlocked copy.',
    );
  }
  final unicode = (flags & 0x1000) != 0;
  final charset = fib.u16(0x14);
  final locale = fib.u16(6);
  final mac = charset == 256;
  if (!unicode &&
      !mac &&
      (charset != 0 || (locale >= 999 && locale != 0x0409))) {
    throw const FormatException(
      'This Word 6/95 character encoding is not supported. Save it as DOCX or Unicode text.',
    );
  }
  final characterCount = fib.u32(0x34);
  if (characterCount > maxCharacters) {
    throw const FormatException('Word text exceeds the preview size limit.');
  }
  if (characterCount == 0) return '';
  int decode(int byte) => byte < 0x80
      ? byte
      : mac
      ? _macRoman.codeUnitAt(byte - 0x80)
      : (_windows1252[byte] ?? byte);
  final output = StringBuffer();
  void appendPiece(int offset, int count) {
    fib.require(offset, count * (unicode ? 2 : 1));
    if (unicode) {
      output.write(
        String.fromCharCodes([
          for (var i = 0; i < count; i++) fib.u16(offset + i * 2),
        ]),
      );
    } else {
      for (var i = 0; i < count; i++) {
        output.writeCharCode(decode(word[offset + i]));
      }
    }
  }

  if ((flags & 0x0004) == 0) {
    appendPiece(fib.u32(0x18), characterCount);
    return _readableBody(output.toString());
  }
  // Complex (fast-saved): the CLX lives in the WordDocument stream.
  final clxOffset = fib.u32(0x1a2);
  final clxLength = fib.u32(0x1a6);
  fib.require(clxOffset, clxLength);
  var position = clxOffset;
  final end = clxOffset + clxLength;
  while (position < end && word[position] == 1) {
    fib.require(position + 1, 2);
    position += 3 + fib.u16(position + 1);
  }
  if (position + 5 > end || word[position] != 2) {
    throw const FormatException('Word has no valid text piece table.');
  }
  final pieceBytes = fib.u32(position + 1);
  position += 5;
  if (pieceBytes < 16 ||
      (pieceBytes - 4) % 12 != 0 ||
      position + pieceBytes > end) {
    throw const FormatException('Invalid Word text piece table size.');
  }
  final pieceCount = (pieceBytes - 4) ~/ 12;
  if (pieceCount > 100000 || fib.u32(position) != 0) {
    throw const FormatException('Invalid Word text piece count or start.');
  }
  final pcdStart = position + (pieceCount + 1) * 4;
  var extracted = 0;
  for (var index = 0; index < pieceCount; index++) {
    final start = fib.u32(position + index * 4);
    final next = fib.u32(position + (index + 1) * 4);
    if (next <= start || next > 0x7fffffff) {
      throw const FormatException('Word text positions are not ordered.');
    }
    if (start >= characterCount) continue;
    final count = (next < characterCount ? next : characterCount) - start;
    final fc = fib.u32(pcdStart + index * 8 + 2);
    appendPiece(fc, count);
    extracted += count;
  }
  if (extracted != characterCount) {
    throw const FormatException('Word text is incomplete.');
  }
  return _readableBody(output.toString());
}

/// Windows-1252 in 0x80–0x9F (the rest of the high half is Latin-1).
const _windows1252 = <int, int>{0x80: 0x20ac, ..._compressedUnicode};

/// Mac Roman 0x80–0xFF.
const _macRoman =
    '\u{c4}\u{c5}\u{c7}\u{c9}\u{d1}\u{d6}\u{dc}\u{e1}\u{e0}\u{e2}'
    '\u{e4}\u{e3}\u{e5}\u{e7}\u{e9}\u{e8}\u{ea}\u{eb}\u{ed}\u{ec}'
    '\u{ee}\u{ef}\u{f1}\u{f3}\u{f2}\u{f4}\u{f6}\u{f5}\u{fa}\u{f9}'
    '\u{fb}\u{fc}\u{2020}\u{b0}\u{a2}\u{a3}\u{a7}\u{2022}\u{b6}\u{df}'
    '\u{ae}\u{a9}\u{2122}\u{b4}\u{a8}\u{2260}\u{c6}\u{d8}\u{221e}'
    '\u{b1}\u{2264}\u{2265}\u{a5}\u{b5}\u{2202}\u{2211}\u{220f}'
    '\u{3c0}\u{222b}\u{aa}\u{ba}\u{3a9}\u{e6}\u{f8}\u{bf}\u{a1}\u{ac}'
    '\u{221a}\u{192}\u{2248}\u{2206}\u{ab}\u{bb}\u{2026}\u{a0}\u{c0}'
    '\u{c3}\u{d5}\u{152}\u{153}\u{2013}\u{2014}\u{201c}\u{201d}'
    '\u{2018}\u{2019}\u{f7}\u{25ca}\u{ff}\u{178}\u{2044}\u{20ac}'
    '\u{2039}\u{203a}\u{fb01}\u{fb02}\u{2021}\u{b7}\u{201a}\u{201e}'
    '\u{2030}\u{c2}\u{ca}\u{c1}\u{cb}\u{c8}\u{cd}\u{ce}\u{cf}\u{cc}'
    '\u{d3}\u{d4}\u{f8ff}\u{d2}\u{da}\u{db}\u{d9}\u{131}\u{2c6}'
    '\u{2dc}\u{af}\u{2d8}\u{2d9}\u{2da}\u{b8}\u{2dd}\u{2db}\u{2c7}';
