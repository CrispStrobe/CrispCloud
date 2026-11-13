// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'bounded_cfb_reader.dart';
import 'legacy_word_structured_model.dart';
import 'legacy_word_structured_parser.dart';

export 'legacy_word_structured_model.dart';

/// Parses referenced body text, resolved formatting and structural metadata.
/// Unsupported features are explicit in [LegacyWordDocument.warnings].
LegacyWordDocument parseLegacyWordDocument(Uint8List bytes) =>
    readStructuredLegacyWord(bytes);

/// Read-only body-text extraction for Word 97–2007 binary DOC/DOT files.
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
  if (fib.u16(0) != 0xa5ec) {
    throw const FormatException('This is not a Word binary document.');
  }
  if (!const {0x00c1, 0x00d9, 0x0101, 0x010c, 0x0112}.contains(fib.u16(2))) {
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
  return _readableBody(output.toString());
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
  for (final code in value.codeUnits) {
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
