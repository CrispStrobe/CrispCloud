import 'dart:math' as math;
import 'dart:typed_data';

import 'file_bytes_loader.dart';

class ViewerDecodedText {
  const ViewerDecodedText(this.text, this.starts, this.ends);
  final String text;

  /// Each UTF-16 code unit maps to the complete original encoded scalar.
  final List<int> starts;
  final List<int> ends;
}

/// Incremental decoding with a byte-offset map, bounded by one input chunk.
/// Invalid UTF-8 uses maximal-subpart replacement, like Dart's UTF-8 decoder;
/// incomplete trailing UTF-16/32 units follow the existing text viewer.
class ViewerTextDecoder {
  ViewerTextDecoder(this.encoding, {this.skipBom = true}) {
    if (!const [
      'utf8',
      'utf16le',
      'utf16be',
      'utf32le',
      'utf32be',
      'latin1',
    ].contains(encoding)) {
      throw FormatException('Unsupported text encoding: $encoding');
    }
  }
  final String encoding;
  final bool skipBom;
  Uint8List _carry = Uint8List(0);
  int _carryOffset = 0;

  ViewerDecodedText add(Uint8List input, int offset, {bool last = false}) {
    final data = _carry.isEmpty
        ? input
        : (Uint8List(_carry.length + input.length)
            ..setAll(0, _carry)
            ..setAll(_carry.length, input));
    final base = _carry.isEmpty ? offset : _carryOffset;
    final text = StringBuffer();
    final starts = <int>[], ends = <int>[];
    void emit(int rune, int start, int length) {
      if (base + start == 0 &&
          rune == 0xfeff &&
          (skipBom || encoding == 'utf8')) {
        return;
      }
      text.writeCharCode(rune);
      for (var unit = 0; unit < (rune > 0xffff ? 2 : 1); unit++) {
        starts.add(base + start);
        ends.add(base + start + length);
      }
    }

    var index = 0;
    if (encoding == 'latin1') {
      for (; index < data.length; index++) {
        emit(data[index], index, 1);
      }
    } else if (encoding == 'utf8') {
      while (index < data.length) {
        final first = data[index];
        if (first < 0x80) {
          emit(first, index++, 1);
          continue;
        }
        final needed = first >= 0xc2 && first <= 0xdf
            ? 2
            : first >= 0xe0 && first <= 0xef
            ? 3
            : first >= 0xf0 && first <= 0xf4
            ? 4
            : 0;
        if (needed == 0) {
          emit(0xfffd, index++, 1);
          continue;
        }
        var valid = 1;
        while (valid < needed && index + valid < data.length) {
          final byte = data[index + valid];
          if (byte < 0x80 ||
              byte > 0xbf ||
              (valid == 1 &&
                  ((first == 0xe0 && byte < 0xa0) ||
                      (first == 0xed && byte > 0x9f) ||
                      (first == 0xf0 && byte < 0x90) ||
                      (first == 0xf4 && byte > 0x8f)))) {
            break;
          }
          valid++;
        }
        if (valid < needed) {
          if (index + valid == data.length && !last) break;
          emit(0xfffd, index, valid);
          index += valid;
          continue;
        }
        var rune =
            first &
            (needed == 2
                ? 0x1f
                : needed == 3
                ? 0x0f
                : 0x07);
        for (var j = 1; j < needed; j++) {
          rune = (rune << 6) | (data[index + j] & 0x3f);
        }
        emit(rune, index, needed);
        index += needed;
      }
    } else {
      final view = ByteData.sublistView(data);
      final endian = encoding.endsWith('be') ? Endian.big : Endian.little;
      final size = encoding.startsWith('utf32') ? 4 : 2;
      while (index + size <= data.length) {
        var rune = size == 4
            ? view.getUint32(index, endian)
            : view.getUint16(index, endian);
        var consumed = size;
        if (size == 2 && rune >= 0xd800 && rune <= 0xdbff) {
          if (index + 4 > data.length && !last) break;
          if (index + 4 <= data.length) {
            final low = view.getUint16(index + 2, endian);
            if (low >= 0xdc00 && low <= 0xdfff) {
              rune = 0x10000 + ((rune - 0xd800) << 10) + low - 0xdc00;
              consumed = 4;
            }
          }
        } else if (size == 4 &&
            (rune > 0x10ffff || (rune >= 0xd800 && rune <= 0xdfff))) {
          rune = 0xfffd;
        }
        emit(rune, index, consumed);
        index += consumed;
      }
    }
    _carry = last ? Uint8List(0) : Uint8List.fromList(data.sublist(index));
    _carryOffset = base + index;
    return ViewerDecodedText(text.toString(), starts, ends);
  }
}

/// Moves a text boundary to the start (or end) of a scalar it would split.
/// Keeping both page ends and long-row breaks on these boundaries preserves
/// UTF-8 characters and UTF-16 surrogate pairs across every visible window.
int alignViewerTextOffset(
  ViewBytesSource source,
  int requested,
  String encoding, {
  bool forward = false,
}) {
  var offset = requested.clamp(0, source.size);
  if (offset == source.size) return offset;
  final unit = encoding.startsWith('utf32')
      ? 4
      : encoding.startsWith('utf16')
      ? 2
      : 1;
  if (offset % unit != 0) {
    offset = forward
        ? math.min(source.size, offset + unit - offset % unit)
        : offset - offset % unit;
  }
  if (offset == 0 || offset == source.size) return offset;
  if (encoding == 'utf8') {
    final start = math.max(0, offset - 3);
    final bytes = source.readSync(start, math.min(source.size - start, 7));
    var lead = offset - start;
    if (bytes[lead] & 0xc0 != 0x80) return offset;
    while (lead > 0 && bytes[lead] & 0xc0 == 0x80) {
      lead--;
    }
    final first = bytes[lead];
    final length = first >= 0xc2 && first <= 0xdf
        ? 2
        : first >= 0xe0 && first <= 0xef
        ? 3
        : first >= 0xf0 && first <= 0xf4
        ? 4
        : 0;
    if (length > 0 &&
        lead + length <= bytes.length &&
        start + lead + length > offset) {
      final second = bytes[lead + 1];
      if ((first == 0xe0 && second < 0xa0) ||
          (first == 0xed && second > 0x9f) ||
          (first == 0xf0 && second < 0x90) ||
          (first == 0xf4 && second > 0x8f)) {
        return offset;
      }
      for (var i = 1; i < length; i++) {
        if (bytes[lead + i] & 0xc0 != 0x80) return offset;
      }
      return start + lead + (forward ? length : 0);
    }
  } else if (unit == 2 && offset + 2 <= source.size) {
    final view = ByteData.sublistView(source.readSync(offset - 2, 4));
    final endian = encoding.endsWith('be') ? Endian.big : Endian.little;
    final high = view.getUint16(0, endian), low = view.getUint16(2, endian);
    if (high >= 0xd800 && high <= 0xdbff && low >= 0xdc00 && low <= 0xdfff) {
      return offset + (forward ? 2 : -2);
    }
  }
  return offset;
}
