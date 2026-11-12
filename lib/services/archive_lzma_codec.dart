import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:koni_codecs/koni_codecs.dart' as koni;

import 'archive_types.dart';

// LZMA-alone framing and packet control using the public range-decoder API
// from MIT-licensed package:archive and the encoder from MIT koni_codecs.
// The normal LzmaDecoder does not expose consumed input, so this driver keeps
// the framing boundary explicit instead of silently ignoring trailing bytes.
// https://github.com/tukaani-project/xz/blob/master/doc/lzma-file-format.txt
// Igor Pavlov's LZMA specification (also distributed in the public-domain SDK):
// https://android.googlesource.com/platform/external/lzma/+/refs/heads/nougat-dev/DOC/lzma-specification.txt

/// Decodes exactly one LZMA-alone stream. Both known-size variants (with or
/// without an end marker) and unknown-size streams with a mandatory marker are
/// accepted. Range-coder completion, input consumption and dictionary distances
/// are checked, so a successful result is safe to rewrite as one new stream.
Uint8List decodeArchiveLzma(
  Uint8List input, {
  int maxOutputBytes = kArchiveReadLimit,
}) {
  _checkLimit(maxOutputBytes);
  if (input.length > kArchiveReadLimit) {
    _fail('LZMA compressed input exceeds 64 MiB.');
  }
  if (input.length < 18) {
    _fail('LZMA header or range-coder state is truncated.');
  }
  final properties = input[0];
  if (properties >= 225) _fail('LZMA has an invalid properties byte.');
  final lc = properties % 9;
  final lp = properties ~/ 9 % 5;
  final pb = properties ~/ 45;
  // This is the interoperable liblzma profile, with bounded probability tables.
  if (lc + lp > 4) {
    _fail(
      'LZMA literal context and position bits exceed the supported profile.',
    );
  }
  final header = ByteData.sublistView(input);
  final dictionaryField = header.getUint32(1, Endian.little);
  final dictionary = dictionaryField < 4096 ? 4096 : dictionaryField;
  if (dictionary > kArchiveReadLimit) {
    _fail('LZMA dictionary exceeds the supported 64 MiB limit.');
  }
  final lowSize = header.getUint32(5, Endian.little);
  final highSize = header.getUint32(9, Endian.little);
  final unknownSize = lowSize == 0xffffffff && highSize == 0xffffffff;
  if (!unknownSize && (highSize != 0 || lowSize > maxOutputBytes)) {
    _fail('LZMA declared contents exceed the output limit.');
  }
  final expected = unknownSize ? null : lowSize;
  final payload = Uint8List.sublistView(input, 13);
  if (payload[0] != 0) _fail('LZMA range-coder initial byte must be zero.');
  final range = codecs.RangeDecoder()
    ..setBuffer(payload)
    ..initialize();
  if (range.code >= range.range) {
    _fail('LZMA initial range-coder state is invalid.');
  }
  final output = _LzmaOutput(expected ?? maxOutputBytes);
  final isMatch = _probabilities(12 * 16);
  final isRepeat = _probabilities(12);
  final repeat0 = _probabilities(12);
  final repeat1 = _probabilities(12);
  final repeat2 = _probabilities(12);
  final isShortRepeat = _probabilities(12 * 16);
  final lengths = _probabilities(codecs.lengthProbsLength);
  final repeatLengths = _probabilities(codecs.lengthProbsLength);
  final distances = _probabilities(codecs.distanceProbsLength);
  final literals = _probabilities(0x300 << (lc + lp));
  final history = List<int>.filled(4, 0);
  final positionMask = (1 << pb) - 1;
  final literalMask = (1 << lp) - 1;
  var state = 0;
  var endMarker = false;

  void checkPacket() {
    if (range.isOverrun || range.code >= range.range) {
      _fail('LZMA compressed data is truncated or corrupt.');
    }
  }

  void checkDistance(int distance) {
    if (distance >= dictionary || distance >= output.length) {
      _fail('LZMA match refers outside its declared dictionary.');
    }
  }

  while (true) {
    checkPacket();
    if (expected != null && output.length == expected && range.code == 0) {
      break;
    }
    final position = output.length & positionMask;
    final statePosition = state * 16 + position;
    if (range.readBitRaw(isMatch, statePosition) == 0) {
      final previous = output.length == 0 ? 0 : output.byteBack(1);
      final context =
          ((output.length & literalMask) << lc) | (previous >> (8 - lc));
      final base = context * 0x300;
      int byte;
      if (state < 7) {
        byte = range.decodeByte(literals, base);
      } else {
        checkDistance(history[0]);
        byte = range.decodeMatchedByte(
          literals,
          base,
          output.byteBack(history[0] + 1),
        );
      }
      checkPacket();
      output.addByte(byte);
      state = state < 4 ? 0 : (state < 10 ? state - 3 : state - 6);
      continue;
    }

    int length;
    if (range.readBitRaw(isRepeat, state) == 0) {
      length = range.decodeLength(lengths, position);
      final distance = range.decodeDistance(
        distances,
        length < 6 ? length - 2 : 3,
      );
      checkPacket();
      if (distance == 0xffffffff) {
        if (length != 2) _fail('LZMA end marker has an invalid length.');
        if (expected != null && output.length != expected) {
          _fail('LZMA end marker precedes the declared content size.');
        }
        endMarker = true;
        break;
      }
      history
        ..[3] = history[2]
        ..[2] = history[1]
        ..[1] = history[0]
        ..[0] = distance;
      state = state < 7 ? 7 : 10;
    } else {
      if (range.readBitRaw(repeat0, state) == 0) {
        if (range.readBitRaw(isShortRepeat, statePosition) == 0) {
          checkPacket();
          checkDistance(history[0]);
          output.copyMatch(history[0] + 1, 1);
          state = state < 7 ? 9 : 11;
          continue;
        }
      } else {
        final selected = range.readBitRaw(repeat1, state) == 0
            ? 1
            : (range.readBitRaw(repeat2, state) == 0 ? 2 : 3);
        final distance = history[selected];
        for (var index = selected; index > 0; index--) {
          history[index] = history[index - 1];
        }
        history[0] = distance;
      }
      length = range.decodeLength(repeatLengths, position);
      state = state < 7 ? 8 : 11;
      checkPacket();
    }
    checkDistance(history[0]);
    output.copyMatch(history[0] + 1, length);
  }

  if (unknownSize && !endMarker) {
    _fail('LZMA is missing its required end marker.');
  }
  var consumed = payload.length - range.available;
  var finalCode = range.code;
  // RangeDecoder normalizes before each bit; the file format also requires
  // the pending normalization after the final bit. No probability is decoded.
  if (range.range < 0x1000000) {
    if (consumed == payload.length) _fail('LZMA final range byte is missing.');
    finalCode = ((finalCode << 8) | payload[consumed++]) & 0xffffffff;
  }
  if (finalCode != 0) _fail('LZMA final range-coder state is corrupt.');
  if (consumed != payload.length) {
    _fail('LZMA trailing data or concatenated streams are not supported.');
  }
  return output.takeBytes();
}

/// Creates real LZMA compression with an exact size in the LZMA-alone header.
/// The raw encoder uses a known-size stream without an end marker. Levels
/// select a dictionary from 4 KiB through 64 MiB; no native runtime is used.
Uint8List encodeArchiveLzma(
  Uint8List input, {
  int level = 6,
  int maxOutputBytes = kArchiveReadLimit,
}) {
  _checkLimit(maxOutputBytes);
  if (input.length > kArchiveReadLimit) _fail('LZMA contents exceed 64 MiB.');
  if (level < 0 || level > 9) throw ArgumentError.value(level, 'level');
  if (maxOutputBytes < 18) _fail('LZMA output exceeds its size limit.');
  const dictionaryByLevel = [
    4096,
    65536,
    262144,
    1048576,
    2097152,
    4194304,
    8388608,
    16777216,
    33554432,
    67108864,
  ];
  final encoder = koni.LzmaEncoder(dictSize: dictionaryByLevel[level])
    ..bind(input);
  // The encoder reserves 64 bytes before the requested limit. Giving that
  // headroom prevents false failures for small valid streams; the final exact
  // bound below is authoritative, and an incomplete encode never gets saved.
  final reached = encoder.encodeChunk(
    0,
    input.length,
    packLimit: maxOutputBytes - 13 + 64,
  );
  if (reached != input.length) _fail('LZMA output exceeds its size limit.');
  final packed = encoder.takeChunk();
  if (packed.length > maxOutputBytes - 13) {
    _fail('LZMA output exceeds its size limit.');
  }
  final result = Uint8List(13 + packed.length)
    ..setRange(0, 5, encoder.sevenZipProps());
  ByteData.sublistView(result).setUint32(5, input.length, Endian.little);
  result.setRange(13, result.length, packed);
  return result;
}

Uint16List _probabilities(int length) =>
    Uint16List(length)..fillRange(0, length, 1024);

void _checkLimit(int value) {
  if (value < 0 || value > kArchiveReadLimit) {
    throw ArgumentError.value(value, 'maxOutputBytes', 'Expected 0 to 64 MiB.');
  }
}

Never _fail(String message) => throw ArchiveViewException(message);

class _LzmaOutput {
  final int maximum;
  Uint8List _bytes = Uint8List(0);
  int length = 0;

  _LzmaOutput(this.maximum);

  void _reserve(int count) {
    if (count > maximum - length) {
      _fail('LZMA contents exceed the declared size or output limit.');
    }
    final required = length + count;
    if (required <= _bytes.length) return;
    var capacity = _bytes.isEmpty ? 4096 : _bytes.length;
    while (capacity < required) {
      capacity *= 2;
    }
    if (capacity > maximum) capacity = maximum;
    _bytes = Uint8List(capacity)..setRange(0, length, _bytes);
  }

  int byteBack(int distance) => _bytes[length - distance];

  void addByte(int byte) {
    _reserve(1);
    _bytes[length++] = byte;
  }

  void copyMatch(int distance, int count) {
    _reserve(count);
    final end = length + count;
    while (length < end) {
      _bytes[length] = _bytes[length - distance];
      length++;
    }
  }

  Uint8List takeBytes() => length == _bytes.length
      ? _bytes
      : Uint8List.fromList(Uint8List.sublistView(_bytes, 0, length));
}
