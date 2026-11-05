// lib/services/editor_document.dart
//
// Encoding and line-ending handling for the code editor.
//
// The editor always works on LF-normalized text. The original byte encoding
// and line-ending style are retained here so that a save writes the file back
// in the same shape whenever the content allows it. This avoids silently
// converting Latin-1 files to UTF-8, dropping a BOM, or changing CRLF files to
// LF (all of which the previous TextField-based editor did).

import 'dart:convert';
import 'dart:typed_data';

/// Byte encoding used by an editable text document.
enum EditorEncoding {
  utf8('UTF-8'),
  utf8Bom('UTF-8 BOM'),
  utf16le('UTF-16 LE'),
  utf16be('UTF-16 BE'),
  utf32le('UTF-32 LE'),
  utf32be('UTF-32 BE'),
  latin1('Latin-1');

  const EditorEncoding(this.label);

  /// Human-readable name shown in the editor status bar.
  final String label;
}

/// Line-ending style used when the document is written back to storage.
///
/// A document is decoded into LF internally. Mixed line endings are normalized
/// to the dominant style on load, and [EditorDocument.hadMixedLineEndings]
/// records that this conversion happened.
enum EditorLineEnding {
  lf('LF', '\n'),
  crlf('CRLF', '\r\n'),
  cr('CR', '\r');

  const EditorLineEnding(this.label, this.sequence);

  final String label;
  final String sequence;
}

/// Thrown when the selected encoding cannot represent the document text.
///
/// The editor surfaces this instead of silently writing replacement bytes.
class EditorEncodingException implements Exception {
  const EditorEncodingException(this.encoding, this.message);

  final EditorEncoding encoding;
  final String message;

  @override
  String toString() => message;
}

/// Immutable text document plus the metadata required to save it losslessly.
class EditorDocument {
  const EditorDocument({
    required this.text,
    required this.encoding,
    required this.lineEnding,
    this.hadMixedLineEndings = false,
    this.hadBom = false,
  });

  /// LF-normalized document text without a byte-order mark.
  final String text;

  final EditorEncoding encoding;
  final EditorLineEnding lineEnding;

  /// True when the source contained more than one line-ending style.
  final bool hadMixedLineEndings;

  /// True when the source began with a byte-order mark.
  final bool hadBom;

  /// Decode [bytes], detect the encoding and line-ending style, and normalize
  /// the text to LF.
  factory EditorDocument.decode(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final detection = _detectEncoding(data);
    final decoded = detection.decode(data);
    final endings = _countLineEndings(decoded);
    final lineEnding = endings.dominant;
    return EditorDocument(
      text: _normalizeLineEndings(decoded),
      encoding: detection.encoding,
      lineEnding: lineEnding,
      hadMixedLineEndings: endings.isMixed,
      hadBom: detection.bomLength > 0,
    );
  }

  EditorDocument copyWith({
    String? text,
    EditorEncoding? encoding,
    EditorLineEnding? lineEnding,
    bool? hadMixedLineEndings,
    bool? hadBom,
  }) {
    return EditorDocument(
      text: text ?? this.text,
      encoding: encoding ?? this.encoding,
      lineEnding: lineEnding ?? this.lineEnding,
      hadMixedLineEndings: hadMixedLineEndings ?? this.hadMixedLineEndings,
      hadBom: hadBom ?? this.hadBom,
    );
  }

  /// Encode [source] (or the stored text) using this document's metadata.
  ///
  /// Throws [EditorEncodingException] when the chosen legacy encoding cannot
  /// represent a character added by the user.
  Uint8List encode([String? source]) {
    final normalized = _normalizeLineEndings(source ?? text);
    final withLineEndings = normalized.replaceAll('\n', lineEnding.sequence);
    switch (encoding) {
      case EditorEncoding.utf8:
        return Uint8List.fromList(utf8.encode(withLineEndings));
      case EditorEncoding.utf8Bom:
        return Uint8List.fromList(<int>[
          0xEF,
          0xBB,
          0xBF,
          ...utf8.encode(withLineEndings),
        ]);
      case EditorEncoding.utf16le:
        return _encodeUtf16(withLineEndings, littleEndian: true);
      case EditorEncoding.utf16be:
        return _encodeUtf16(withLineEndings, littleEndian: false);
      case EditorEncoding.utf32le:
        return _encodeUtf32(withLineEndings, littleEndian: true);
      case EditorEncoding.utf32be:
        return _encodeUtf32(withLineEndings, littleEndian: false);
      case EditorEncoding.latin1:
        if (withLineEndings.runes.any((rune) => rune > 0xFF)) {
          throw EditorEncodingException(
            encoding,
            'The file is ${encoding.label}, but the text now contains '
            'characters that encoding cannot represent. Switch the encoding '
            'to UTF-8 to save it.',
          );
        }
        return Uint8List.fromList(latin1.encode(withLineEndings));
    }
  }

  static String _normalizeLineEndings(String source) {
    return source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static Uint8List _encodeUtf16(String source, {required bool littleEndian}) {
    final units = source.codeUnits;
    final out = Uint8List(2 + units.length * 2);
    var i = 0;
    if (littleEndian) {
      out[i++] = 0xFF;
      out[i++] = 0xFE;
    } else {
      out[i++] = 0xFE;
      out[i++] = 0xFF;
    }
    for (final unit in units) {
      if (littleEndian) {
        out[i++] = unit & 0xFF;
        out[i++] = (unit >> 8) & 0xFF;
      } else {
        out[i++] = (unit >> 8) & 0xFF;
        out[i++] = unit & 0xFF;
      }
    }
    return out;
  }

  static Uint8List _encodeUtf32(String source, {required bool littleEndian}) {
    final runes = source.runes.toList(growable: false);
    final out = Uint8List(4 + runes.length * 4);
    var i = 0;
    if (littleEndian) {
      out[i++] = 0xFF;
      out[i++] = 0xFE;
      out[i++] = 0x00;
      out[i++] = 0x00;
    } else {
      out[i++] = 0x00;
      out[i++] = 0x00;
      out[i++] = 0xFE;
      out[i++] = 0xFF;
    }
    for (final rune in runes) {
      if (littleEndian) {
        out[i++] = rune & 0xFF;
        out[i++] = (rune >> 8) & 0xFF;
        out[i++] = (rune >> 16) & 0xFF;
        out[i++] = (rune >> 24) & 0xFF;
      } else {
        out[i++] = (rune >> 24) & 0xFF;
        out[i++] = (rune >> 16) & 0xFF;
        out[i++] = (rune >> 8) & 0xFF;
        out[i++] = rune & 0xFF;
      }
    }
    return out;
  }
}

class _EncodingDetection {
  const _EncodingDetection({
    required this.encoding,
    required this.bomLength,
    required this.decode,
  });

  final EditorEncoding encoding;
  final int bomLength;
  final String Function(Uint8List bytes) decode;
}

_EncodingDetection _detectEncoding(Uint8List bytes) {
  if (_startsWith(bytes, const [0x00, 0x00, 0xFE, 0xFF])) {
    return _EncodingDetection(
      encoding: EditorEncoding.utf32be,
      bomLength: 4,
      decode: (data) => _decodeUtf32(data, littleEndian: false),
    );
  }
  if (_startsWith(bytes, const [0xFF, 0xFE, 0x00, 0x00])) {
    return _EncodingDetection(
      encoding: EditorEncoding.utf32le,
      bomLength: 4,
      decode: (data) => _decodeUtf32(data, littleEndian: true),
    );
  }
  if (_startsWith(bytes, const [0xFE, 0xFF])) {
    return _EncodingDetection(
      encoding: EditorEncoding.utf16be,
      bomLength: 2,
      decode: (data) => _decodeUtf16(data, littleEndian: false),
    );
  }
  if (_startsWith(bytes, const [0xFF, 0xFE])) {
    return _EncodingDetection(
      encoding: EditorEncoding.utf16le,
      bomLength: 2,
      decode: (data) => _decodeUtf16(data, littleEndian: true),
    );
  }
  if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
    return _EncodingDetection(
      encoding: EditorEncoding.utf8Bom,
      bomLength: 3,
      decode: (data) {
        try {
          return utf8.decode(_slice(data, 3));
        } on FormatException {
          return latin1.decode(_slice(data, 3));
        }
      },
    );
  }
  try {
    utf8.decode(bytes);
  } on FormatException {
    // Preserve the bytes of a legacy single-byte file instead of emitting
    // replacement characters. Detecting Latin-1 here (rather than merely
    // decoding with it) is what lets a save write the same bytes back.
    return _EncodingDetection(
      encoding: EditorEncoding.latin1,
      bomLength: 0,
      decode: latin1.decode,
    );
  }
  return _EncodingDetection(
    encoding: EditorEncoding.utf8,
    bomLength: 0,
    decode: utf8.decode,
  );
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

Uint8List _slice(Uint8List bytes, int start) {
  return Uint8List.sublistView(bytes, start);
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final data = _slice(bytes, 2);
  final units = <int>[];
  for (var i = 0; i + 1 < data.length; i += 2) {
    units.add(
      littleEndian
          ? data[i] | (data[i + 1] << 8)
          : (data[i] << 8) | data[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

String _decodeUtf32(Uint8List bytes, {required bool littleEndian}) {
  final data = _slice(bytes, 4);
  final runes = <int>[];
  for (var i = 0; i + 3 < data.length; i += 4) {
    final value = littleEndian
        ? data[i] |
              (data[i + 1] << 8) |
              (data[i + 2] << 16) |
              (data[i + 3] << 24)
        : (data[i] << 24) |
              (data[i + 1] << 16) |
              (data[i + 2] << 8) |
              data[i + 3];
    runes.add(_isValidRune(value) ? value : 0xFFFD);
  }
  return String.fromCharCodes(runes);
}

bool _isValidRune(int value) {
  return value >= 0 &&
      value <= 0x10FFFF &&
      !(value >= 0xD800 && value <= 0xDFFF);
}

class _LineEndingCounts {
  _LineEndingCounts(this.crlf, this.cr, this.lf);

  final int crlf;
  final int cr;
  final int lf;

  bool get isMixed {
    var kinds = 0;
    if (crlf > 0) kinds++;
    if (cr > 0) kinds++;
    if (lf > 0) kinds++;
    return kinds > 1;
  }

  EditorLineEnding get dominant {
    if (crlf == 0 && cr == 0 && lf == 0) return EditorLineEnding.lf;
    // Prefer CRLF on a tie: Windows-style documents commonly mix in a few
    // LF-only generated lines, and retaining CRLF minimizes the diff.
    if (crlf >= lf && crlf >= cr) return EditorLineEnding.crlf;
    if (lf >= cr) return EditorLineEnding.lf;
    return EditorLineEnding.cr;
  }
}

_LineEndingCounts _countLineEndings(String text) {
  var crlf = 0;
  var cr = 0;
  var lf = 0;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x0D) {
      if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) {
        crlf++;
        i++;
      } else {
        cr++;
      }
    } else if (unit == 0x0A) {
      lf++;
    }
  }
  return _LineEndingCounts(crlf, cr, lf);
}
