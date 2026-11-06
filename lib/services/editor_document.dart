// LF is an editing representation, not a storage conversion. Every surviving
// newline has its own CR/LF/CRLF metadata; conversion is an explicit policy.
import 'dart:convert';
import 'dart:typed_data';

enum EditorEncoding {
  utf8('UTF-8'),
  utf8Bom('UTF-8 BOM'),
  utf16le('UTF-16 LE'),
  utf16be('UTF-16 BE'),
  utf32le('UTF-32 LE'),
  utf32be('UTF-32 BE'),
  latin1('Latin-1');

  const EditorEncoding(this.label);
  final String label;
}

enum EditorLineEnding {
  lf('LF', '\n'),
  crlf('CRLF', '\r\n'),
  cr('CR', '\r');

  const EditorLineEnding(this.label, this.sequence);
  final String label;
  final String sequence;
}

enum EditorLineEndingPolicy { preserve, normalize }

class EditorEncodingException implements Exception {
  const EditorEncodingException(this.encoding, this.message);
  final EditorEncoding encoding;
  final String message;
  @override
  String toString() => message;
}

/// An immutable text snapshot. [lineEnding] is the preference for NEW breaks.
/// In preserve mode each existing break retains its individual representation.
/// LF-normalized controller values must be applied after EACH editing event,
/// not only at save time. [replace] accepts an exact UTF-16 edit range.
class EditorDocument {
  const EditorDocument({
    required this.text,
    required this.encoding,
    required this.lineEnding,
    this.hadMixedLineEndings = false,
    this.hadBom = false,
    this.originalLineEndings,
    this.originalNormalizedText,
    this.lineEndingPolicy = EditorLineEndingPolicy.preserve,
    this.writeBom,
  });

  final String text;
  final EditorEncoding encoding;
  final EditorLineEnding lineEnding;
  final EditorLineEndingPolicy lineEndingPolicy;
  final bool hadMixedLineEndings;
  final bool hadBom;
  final bool? writeBom;

  // Retain the public names from the first checkpoint, but keep this map in
  // sync with this snapshot's text. Never keep mapping new edits to load-time
  // line numbers: that loses metadata after a second edit or a save.
  final List<EditorLineEnding>? originalLineEndings;
  final String? originalNormalizedText;

  bool get hasFinalNewline => text.endsWith('\n');
  bool get writesBom =>
      writeBom ??
      (encoding == EditorEncoding.utf8Bom ||
          (encoding != EditorEncoding.utf8 &&
              encoding != EditorEncoding.latin1 &&
              hadBom));
  List<EditorLineEnding> get lineEndings =>
      originalLineEndings ??
      List.filled(_newlines(text), lineEnding, growable: false);
  Map<EditorLineEnding, int> get lineEndingCounts => {
    for (final style in EditorLineEnding.values)
      style: lineEndings.where((value) => value == style).length,
  };

  /// BOM-less UTF-16/32 is deliberately NOT guessed. Pass [encoding] explicitly
  /// to reopen a known encoding. A malformed BOM-marked file is rejected, never
  /// decoded with replacements and subsequently written over the original.
  factory EditorDocument.decode(
    List<int> bytes, {
    EditorEncoding? encoding,
    EditorEncoding? encodingOverride,
  }) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final requested = encodingOverride ?? encoding;
    final detection = requested == null
        ? _detectEncoding(data)
        : _explicitEncoding(data, requested);
    late final String decoded;
    try {
      decoded = detection.decode(data);
    } on FormatException catch (error) {
      throw EditorEncodingException(
        detection.encoding,
        'Invalid ${detection.encoding.label}: ${error.message} Open in Hex, or reopen with the correct encoding; the original has not been changed.',
      );
    }
    final parsed = _parse(decoded);
    return EditorDocument(
      text: parsed.$1,
      encoding: detection.encoding,
      lineEnding: _dominant(parsed.$2),
      hadMixedLineEndings: parsed.$2.toSet().length > 1,
      hadBom: detection.bomLength > 0,
      writeBom: detection.bomLength > 0,
      originalNormalizedText: parsed.$1,
      originalLineEndings: List.unmodifiable(parsed.$2),
    );
  }

  /// Supplying [lineEnding] explicitly requests whole-document conversion,
  /// even when it equals the dominant style. To only choose the style of new
  /// breaks, use [withNewLineEnding]. Preserve policy is independently selectable.
  EditorDocument copyWith({
    String? text,
    EditorEncoding? encoding,
    EditorLineEnding? lineEnding,
    bool? hadMixedLineEndings,
    bool? hadBom,
    EditorLineEndingPolicy? lineEndingPolicy,
    bool? writeBom,
  }) {
    final nextText = _parse(text ?? this.text).$1;
    final preference = lineEnding ?? this.lineEnding;
    final map = nextText == this.text
        ? lineEndings
        : _remap(this.text, nextText, lineEndings, preference);
    final policy =
        lineEndingPolicy ??
        (lineEnding != null
            ? EditorLineEndingPolicy.normalize
            : this.lineEndingPolicy);
    final nextEncoding = encoding ?? this.encoding;
    return EditorDocument(
      text: nextText,
      encoding: nextEncoding,
      lineEnding: preference,
      lineEndingPolicy: policy,
      hadMixedLineEndings: map.toSet().length > 1,
      hadBom:
          hadBom ??
          (nextEncoding == EditorEncoding.utf8Bom
              ? true
              : nextEncoding == EditorEncoding.utf8 ||
                    nextEncoding == EditorEncoding.latin1
              ? false
              : this.hadBom),
      originalNormalizedText: nextText,
      originalLineEndings: List.unmodifiable(map),
      writeBom:
          writeBom ??
          (encoding != null && encoding != this.encoding
              ? null
              : this.writeBom),
    );
  }

  EditorDocument withNewLineEnding(EditorLineEnding style) =>
      copyWith(lineEnding: style, lineEndingPolicy: lineEndingPolicy);

  /// Exact replacement for adapters with edit deltas. Existing LF tokens outside
  /// [start,end) keep their metadata. Inserted breaks use the document preference
  /// by default; [preserveInsertedEndings] is useful for a raw clipboard import.
  EditorDocument replace(
    int start,
    int end,
    String inserted, {
    bool preserveInsertedEndings = false,
  }) {
    RangeError.checkValidRange(start, end, text.length);
    final parsed = _parse(inserted);
    final before = _newlines(text.substring(0, start));
    final removed = _newlines(text.substring(start, end));
    final map = lineEndings;
    final result = text.replaceRange(start, end, parsed.$1);
    return _withMap(result, [
      ...map.take(before),
      ...(preserveInsertedEndings
          ? parsed.$2
          : List.filled(parsed.$2.length, lineEnding)),
      ...map.skip(before + removed),
    ]);
  }

  /// Restore newline metadata for an undo/redo value, retaining current format
  /// settings. The host keys these snapshots by the editor's history values.
  EditorDocument restoreText(EditorDocument value) =>
      _withMap(value.text, value.lineEndings);

  EditorDocument _withMap(String value, List<EditorLineEnding> map) =>
      EditorDocument(
        text: value,
        encoding: encoding,
        lineEnding: lineEnding,
        lineEndingPolicy: lineEndingPolicy,
        hadBom: hadBom,
        hadMixedLineEndings: map.toSet().length > 1,
        originalNormalizedText: value,
        originalLineEndings: List.unmodifiable(map),
      );

  Uint8List encode([String? source]) {
    final current = source != null && source != text
        ? copyWith(text: source)
        : this;
    final normalized = _parse(current.text).$1;
    final map = current.lineEndings;
    final count = _newlines(normalized);
    if (map.length != count)
      throw StateError('Line-ending map is out of sync; refusing to save.');
    final output = StringBuffer();
    var from = 0, boundary = 0;
    for (var i = 0; i < normalized.length; i++) {
      if (normalized.codeUnitAt(i) != 10) continue;
      output.write(normalized.substring(from, i));
      output.write(
        (current.lineEndingPolicy == EditorLineEndingPolicy.normalize
                ? current.lineEnding
                : map[boundary])
            .sequence,
      );
      boundary++;
      from = i + 1;
    }
    output.write(normalized.substring(from));
    final value = output.toString();
    try {
      _validateUnicode(value);
    } on FormatException {
      throw EditorEncodingException(
        encoding,
        'The edited text contains an unpaired Unicode surrogate. Correct it before saving.',
      );
    }
    switch (encoding) {
      case EditorEncoding.utf8:
      case EditorEncoding.utf8Bom:
        return Uint8List.fromList([
          if (encoding == EditorEncoding.utf8Bom) ...[0xef, 0xbb, 0xbf],
          ...utf8.encode(value),
        ]);
      case EditorEncoding.latin1:
        if (value.runes.any((point) => point > 255)) {
          throw EditorEncodingException(
            encoding,
            'The file is Latin-1, but the text contains characters that encoding cannot represent. Switch to UTF-8 to save it.',
          );
        }
        return Uint8List.fromList(latin1.encode(value));
      case EditorEncoding.utf16le:
      case EditorEncoding.utf16be:
      case EditorEncoding.utf32le:
      case EditorEncoding.utf32be:
        final wide =
            encoding == EditorEncoding.utf32le ||
            encoding == EditorEncoding.utf32be;
        final little =
            encoding == EditorEncoding.utf16le ||
            encoding == EditorEncoding.utf32le;
        final width = wide ? 4 : 2;
        final units = wide
            ? value.runes.toList(growable: false)
            : value.codeUnits;
        final result = Uint8List(width * (units.length + (writesBom ? 1 : 0)));
        final view = ByteData.sublistView(result);
        final endian = little ? Endian.little : Endian.big;
        var offset = 0;
        void write(int unit) {
          if (wide) {
            view.setUint32(offset, unit, endian);
          } else {
            view.setUint16(offset, unit, endian);
          }
          offset += width;
        }
        if (writesBom) write(0xfeff);
        for (final unit in units) {
          write(unit);
        }
        return result;
    }
  }
}

// The controller reports complete LF-normalized values. Keep all unaffected
// prefix/suffix boundaries, and retain one-to-one boundaries in a same-line-
// count replacement (e.g. replacing a word on many lines). Call after each edit.
List<EditorLineEnding> _remap(
  String old,
  String next,
  List<EditorLineEnding> map,
  EditorLineEnding preference,
) {
  var prefix = 0;
  while (prefix < old.length &&
      prefix < next.length &&
      old.codeUnitAt(prefix) == next.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < old.length - prefix &&
      suffix < next.length - prefix &&
      old.codeUnitAt(old.length - suffix - 1) ==
          next.codeUnitAt(next.length - suffix - 1)) {
    suffix++;
  }
  final before = _newlines(old.substring(0, prefix));
  final removed = _newlines(old.substring(prefix, old.length - suffix));
  final inserted = _newlines(next.substring(prefix, next.length - suffix));
  return [
    ...map.take(before),
    ...(removed == inserted
        ? map.skip(before).take(removed)
        : List.filled(inserted, preference)),
    ...map.skip(before + removed),
  ];
}

(String, List<EditorLineEnding>) _parse(String source) {
  final output = StringBuffer();
  final endings = <EditorLineEnding>[];
  var from = 0;
  for (var i = 0; i < source.length; i++) {
    final c = source.codeUnitAt(i);
    if (c != 10 && c != 13) continue;
    output.write(source.substring(from, i));
    output.write('\n');
    if (c == 13 && i + 1 < source.length && source.codeUnitAt(i + 1) == 10) {
      endings.add(EditorLineEnding.crlf);
      i++;
    } else {
      endings.add(c == 13 ? EditorLineEnding.cr : EditorLineEnding.lf);
    }
    from = i + 1;
  }
  output.write(source.substring(from));
  return (output.toString(), endings);
}

int _newlines(String value) {
  var result = 0;
  for (var i = 0; i < value.length; i++) {
    if (value.codeUnitAt(i) == 10) result++;
  }
  return result;
}

EditorLineEnding _dominant(List<EditorLineEnding> values) {
  if (values.isEmpty) return EditorLineEnding.lf;
  // Deterministic on every platform, including ties. Never consult host OS.
  var best = EditorLineEnding.crlf, maximum = -1;
  for (final candidate in [
    EditorLineEnding.crlf,
    EditorLineEnding.lf,
    EditorLineEnding.cr,
  ]) {
    final count = values.where((value) => value == candidate).length;
    if (count > maximum) {
      best = candidate;
      maximum = count;
    }
  }
  return best;
}

bool _sameEncoding(EditorEncoding a, EditorEncoding b) =>
    a == b ||
    ([EditorEncoding.utf8, EditorEncoding.utf8Bom].contains(a) &&
        [EditorEncoding.utf8, EditorEncoding.utf8Bom].contains(b));
(EditorEncoding, int)? _bom(Uint8List data) {
  bool starts(List<int> prefix) {
    if (data.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) return false;
    }
    return true;
  }

  if (starts([0, 0, 0xfe, 0xff])) return (EditorEncoding.utf32be, 4);
  if (starts([0xff, 0xfe, 0, 0])) return (EditorEncoding.utf32le, 4);
  if (starts([0xfe, 0xff])) return (EditorEncoding.utf16be, 2);
  if (starts([0xff, 0xfe])) return (EditorEncoding.utf16le, 2);
  if (starts([0xef, 0xbb, 0xbf])) return (EditorEncoding.utf8Bom, 3);
  return null;
}

EditorEncoding _unmarkedEncoding(Uint8List data) {
  try {
    utf8.decode(data, allowMalformed: false);
    return EditorEncoding.utf8;
  } on FormatException {
    return EditorEncoding.latin1;
  }
}

void _validateUnicode(String value) {
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      if (++i >= value.length)
        throw const FormatException('Unpaired UTF-16 surrogate.');
      final low = value.codeUnitAt(i);
      if (low < 0xdc00 || low > 0xdfff)
        throw const FormatException('Unpaired UTF-16 surrogate.');
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      throw const FormatException('Unpaired UTF-16 surrogate.');
    }
  }
}

int _explicitBomLength(Uint8List data, EditorEncoding encoding) {
  final prefix = switch (encoding) {
    EditorEncoding.utf8 || EditorEncoding.utf8Bom => [0xef, 0xbb, 0xbf],
    EditorEncoding.utf16le => [0xff, 0xfe],
    EditorEncoding.utf16be => [0xfe, 0xff],
    EditorEncoding.utf32le => [0xff, 0xfe, 0, 0],
    EditorEncoding.utf32be => [0, 0, 0xfe, 0xff],
    EditorEncoding.latin1 => <int>[],
  };
  if (prefix.isEmpty || data.length < prefix.length) return 0;
  for (var i = 0; i < prefix.length; i++) {
    if (data[i] != prefix[i]) return 0;
  }
  return prefix.length;
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

_EncodingDetection _explicitEncoding(Uint8List bytes, EditorEncoding encoding) {
  final bom = switch (encoding) {
    EditorEncoding.utf8 || EditorEncoding.utf8Bom => const [0xEF, 0xBB, 0xBF],
    EditorEncoding.utf16le => const [0xFF, 0xFE],
    EditorEncoding.utf16be => const [0xFE, 0xFF],
    EditorEncoding.utf32le => const [0xFF, 0xFE, 0, 0],
    EditorEncoding.utf32be => const [0, 0, 0xFE, 0xFF],
    EditorEncoding.latin1 => const <int>[],
  };
  final length = bom.isNotEmpty && _startsWith(bytes, bom) ? bom.length : 0;
  return _EncodingDetection(
    encoding: encoding == EditorEncoding.utf8 && length > 0
        ? EditorEncoding.utf8Bom
        : encoding,
    bomLength: length,
    decode: (data) => switch (encoding) {
      EditorEncoding.utf8 ||
      EditorEncoding.utf8Bom => utf8.decode(_slice(data, length)),
      EditorEncoding.utf16le => _decodeUtf16(
        data,
        littleEndian: true,
        bomLength: length,
      ),
      EditorEncoding.utf16be => _decodeUtf16(
        data,
        littleEndian: false,
        bomLength: length,
      ),
      EditorEncoding.utf32le => _decodeUtf32(
        data,
        littleEndian: true,
        bomLength: length,
      ),
      EditorEncoding.utf32be => _decodeUtf32(
        data,
        littleEndian: false,
        bomLength: length,
      ),
      EditorEncoding.latin1 => latin1.decode(data),
    },
  );
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
      decode: (data) => utf8.decode(_slice(data, 3)),
    );
  }
  // BOM-less UTF-16 is common for legacy Windows text. Detect it
  // conservatively by the NUL-byte pattern before treating the bytes as UTF-8.
  if (bytes.length >= 4 && bytes.length.isEven) {
    var evenNuls = 0;
    var oddNuls = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0) {
        if (i.isEven) {
          evenNuls++;
        } else {
          oddNuls++;
        }
      }
    }
    final half = bytes.length ~/ 2;
    if (oddNuls > half * 0.3 && evenNuls < half * 0.1) {
      return _EncodingDetection(
        encoding: EditorEncoding.utf16le,
        bomLength: 0,
        decode: (data) => _decodeUtf16(data, littleEndian: true, bomLength: 0),
      );
    }
    if (evenNuls > half * 0.3 && oddNuls < half * 0.1) {
      return _EncodingDetection(
        encoding: EditorEncoding.utf16be,
        bomLength: 0,
        decode: (data) => _decodeUtf16(data, littleEndian: false, bomLength: 0),
      );
    }
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

String _decodeUtf16(
  Uint8List bytes, {
  required bool littleEndian,
  int bomLength = 2,
}) {
  final data = _slice(bytes, bomLength);
  if (data.length.isOdd) {
    throw const FormatException('Incomplete UTF-16 code unit.');
  }
  final units = <int>[];
  for (var i = 0; i + 1 < data.length; i += 2) {
    units.add(
      littleEndian
          ? data[i] | (data[i + 1] << 8)
          : (data[i] << 8) | data[i + 1],
    );
  }
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= units.length ||
          units[i + 1] < 0xDC00 ||
          units[i + 1] > 0xDFFF) {
        throw const FormatException('Unpaired UTF-16 surrogate.');
      }
      i++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw const FormatException('Unpaired UTF-16 surrogate.');
    }
  }
  return String.fromCharCodes(units);
}

String _decodeUtf32(
  Uint8List bytes, {
  required bool littleEndian,
  int bomLength = 4,
}) {
  final data = _slice(bytes, bomLength);
  if (data.length % 4 != 0) {
    throw const FormatException('Incomplete UTF-32 code point.');
  }
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
    if (!_isValidRune(value)) {
      throw const FormatException('Invalid UTF-32 code point.');
    }
    runes.add(value);
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
