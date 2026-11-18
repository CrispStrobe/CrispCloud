import 'dart:convert';
import 'dart:typed_data';

const int spacyMaximumTextBytes = 1024 * 1024;
const int spacyMaximumTokens = 2048;

/// Exact coordinate maps for the original snapshot. Surrogates are validated
/// before UTF-8 encoding; Dart's replacement-character fallback is not used.
final class SpacySourceText {
  SpacySourceText(this.text) {
    if (text.length > spacyMaximumTextBytes) {
      throw const FormatException('Text exceeds the native input limit.');
    }
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i == text.length ||
            text.codeUnitAt(i) < 0xdc00 ||
            text.codeUnitAt(i) > 0xdfff) {
          throw const FormatException('Text contains an unpaired surrogate.');
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('Text contains an unpaired surrogate.');
      }
    }
    bytes = Uint8List.fromList(utf8.encode(text)).asUnmodifiableView();
    if (bytes.length > spacyMaximumTextBytes) {
      throw const FormatException('Text exceeds the native UTF-8 byte limit.');
    }
    _utf16 = Int32List(bytes.length + 1)..fillRange(0, bytes.length + 1, -1);
    _scalars = Int32List(bytes.length + 1)..fillRange(0, bytes.length + 1, -1);
    var offset = 0;
    var units = 0;
    var scalars = 0;
    _utf16[0] = 0;
    _scalars[0] = 0;
    for (final rune in text.runes) {
      offset += rune <= 0x7f
          ? 1
          : rune <= 0x7ff
          ? 2
          : rune <= 0xffff
          ? 3
          : 4;
      units += rune <= 0xffff ? 1 : 2;
      _utf16[offset] = units;
      _scalars[offset] = ++scalars;
    }
  }

  final String text;
  late final Uint8List bytes;
  late final Int32List _utf16;
  late final Int32List _scalars;

  bool isBoundary(int byteOffset) =>
      byteOffset >= 0 && byteOffset < _utf16.length && _utf16[byteOffset] >= 0;

  int utf16At(int byteOffset) {
    if (!isBoundary(byteOffset)) {
      throw const FormatException('Token splits a Unicode scalar boundary.');
    }
    return _utf16[byteOffset];
  }

  int scalarAt(int byteOffset) {
    utf16At(byteOffset);
    return _scalars[byteOffset];
  }
}
