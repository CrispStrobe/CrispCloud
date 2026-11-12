import 'dart:typed_data';

import 'archive_types.dart';

// Original portable implementation of the public LZ4 frame/block formats and
// XXH32 algorithm. No native library is required by the application.
// https://github.com/lz4/lz4/blob/dev/doc/lz4_Frame_format.md
// https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
// https://github.com/Cyan4973/xxHash/blob/dev/doc/xxhash_spec.md

const _frameMagic = 0x184d2204;
const _maxFrameCount = 4096;
const _maxBlockCount = 1000000;

/// Decoded content and the framing information needed to decide whether a
/// one-frame rewrite would discard a frame collection or extension metadata.
class ArchiveLz4Decoded {
  final Uint8List bytes;
  final int frameCount;
  final int skippableFrameCount;
  final bool hasLinkedBlocks;
  final bool hasBlockChecksums;
  final bool hasContentChecksums;

  const ArchiveLz4Decoded({
    required this.bytes,
    required this.frameCount,
    required this.skippableFrameCount,
    required this.hasLinkedBlocks,
    required this.hasBlockChecksums,
    required this.hasContentChecksums,
  });

  bool get canRewrite => frameCount == 1 && skippableFrameCount == 0;
}

/// Reads modern LZ4 frames, including linked blocks and frame collections.
/// Every checksum that is present is verified. Skippable extension frames are
/// counted, so writers can refuse to discard their opaque metadata. External
/// dictionaries and the old legacy framing are explicitly unsupported.
ArchiveLz4Decoded decodeArchiveLz4(
  Uint8List input, {
  int maxOutputBytes = kArchiveReadLimit,
}) {
  _checkLimit(maxOutputBytes);
  if (input.length > kArchiveReadLimit) {
    _fail('LZ4 compressed input exceeds 64 MiB.');
  }
  final output = _Lz4Buffer(maxOutputBytes);
  var at = 0, frames = 0, skipped = 0, blocks = 0;
  var linked = false, blockChecksums = false, contentChecksums = false;

  void require(int count) {
    if (count < 0 || count > input.length - at) {
      _fail('LZ4 frame is truncated.');
    }
  }

  int word() {
    require(4);
    final value = _word(input, at);
    at += 4;
    return value;
  }

  while (at < input.length) {
    if (frames + skipped >= _maxFrameCount) {
      _fail('LZ4 contains too many frames.');
    }
    final magic = word();
    if (magic >= 0x184d2a50 && magic <= 0x184d2a5f) {
      final size = word();
      require(size);
      at += size;
      skipped++;
      continue;
    }
    if (magic == 0x184c2102) {
      _fail('Legacy LZ4 framing is not supported.');
    }
    if (magic != _frameMagic) {
      _fail('LZ4 has an invalid frame signature or trailing data.');
    }
    frames++;
    require(3);
    final descriptor = at;
    final flags = input[at++], blockDescriptor = input[at++];
    if ((flags & 0xc0) != 0x40 || flags & 2 != 0) {
      _fail('LZ4 uses an unsupported frame version or reserved flags.');
    }
    final blockCode = blockDescriptor >> 4 & 7;
    if (blockDescriptor & 0x8f != 0 || blockCode < 4) {
      _fail('LZ4 has an invalid block-size descriptor.');
    }
    final blockMaximum = 1 << (8 + 2 * blockCode);
    final independent = flags & 0x20 != 0;
    final blockCheck = flags & 0x10 != 0;
    final contentCheck = flags & 4 != 0;
    linked |= !independent;
    blockChecksums |= blockCheck;
    contentChecksums |= contentCheck;
    int? contentSize;
    if (flags & 8 != 0) {
      final low = word(), high = word();
      // Compare the words before constructing a 64-bit value, so web builds
      // never round a large declared size into the accepted range.
      if (high != 0 || low > maxOutputBytes - output.length) {
        _fail('LZ4 declared contents exceed the output limit.');
      }
      contentSize = low;
    }
    if (flags & 1 != 0) {
      _fail('LZ4 external dictionaries are not supported.');
    }
    require(1);
    final headerCheck =
        archiveLz4Xxh32(Uint8List.sublistView(input, descriptor, at)) >> 8 &
        0xff;
    if (input[at++] != headerCheck) {
      _fail('LZ4 frame header checksum does not match.');
    }
    final frameStart = output.length;
    while (true) {
      final blockWord = word();
      if (blockWord == 0) break;
      if (++blocks > _maxBlockCount) {
        _fail('LZ4 contains too many blocks.');
      }
      final stored = blockWord & 0x80000000 != 0;
      final size = blockWord & 0x7fffffff;
      if (size > blockMaximum) {
        _fail('LZ4 block exceeds its declared maximum size.');
      }
      require(size);
      final block = Uint8List.sublistView(input, at, at + size);
      at += size;
      if (blockCheck && word() != archiveLz4Xxh32(block)) {
        _fail('LZ4 block checksum does not match.');
      }
      final blockStart = output.length;
      if (stored) {
        output.addRange(block, 0, block.length);
      } else {
        _decodeBlock(
          block,
          output,
          dictionaryStart: independent ? blockStart : frameStart,
          blockMaximum: blockMaximum,
        );
      }
      if (contentSize != null && output.length - frameStart > contentSize) {
        _fail('LZ4 block exceeds the declared content size.');
      }
    }
    if (contentSize != null && output.length - frameStart != contentSize) {
      _fail('LZ4 decoded length does not match its declared content size.');
    }
    if (contentCheck && word() != archiveLz4Xxh32(output.view(frameStart))) {
      _fail('LZ4 content checksum does not match.');
    }
  }
  if (frames == 0) _fail('LZ4 contains no data frame.');
  return ArchiveLz4Decoded(
    bytes: output.takeBytes(),
    frameCount: frames,
    skippableFrameCount: skipped,
    hasLinkedBlocks: linked,
    hasBlockChecksums: blockChecksums,
    hasContentChecksums: contentChecksums,
  );
}

/// Creates a standard LZ4 frame with independent 256 KiB blocks, exact content
/// size and both block/content checksums. The bounded fast match finder emits
/// actual compression where useful and stores incompressible blocks unchanged.
Uint8List encodeArchiveLz4(
  Uint8List input, {
  int maxOutputBytes = kArchiveReadLimit,
  bool compress = true,
}) {
  _checkLimit(maxOutputBytes);
  if (input.length > kArchiveReadLimit) {
    _fail('LZ4 contents exceed 64 MiB.');
  }
  final output = _Lz4Buffer(maxOutputBytes)..addWord(_frameMagic);
  final descriptor = Uint8List(10)
    ..[0] =
        0x7c // version 1; independent; checksums; content size
    ..[1] = 0x50; // maximum decoded block: 256 KiB
  ByteData.sublistView(descriptor).setUint32(2, input.length, Endian.little);
  output
    ..addRange(descriptor, 0, descriptor.length)
    ..addByte(archiveLz4Xxh32(descriptor) >> 8 & 0xff);
  const blockSize = 256 * 1024;
  for (var at = 0; at < input.length; at += blockSize) {
    final end = at + blockSize < input.length ? at + blockSize : input.length;
    final raw = Uint8List.sublistView(input, at, end);
    final packed = compress ? _encodeBlock(raw) : raw;
    final stored = !compress || packed.length >= raw.length;
    final payload = stored ? raw : packed;
    output
      ..addWord(payload.length | (stored ? 0x80000000 : 0))
      ..addRange(payload, 0, payload.length)
      ..addWord(archiveLz4Xxh32(payload));
  }
  output
    ..addWord(0)
    ..addWord(archiveLz4Xxh32(input));
  return output.takeBytes();
}

void _decodeBlock(
  Uint8List input,
  _Lz4Buffer output, {
  required int dictionaryStart,
  required int blockMaximum,
}) {
  var at = 0;
  final blockStart = output.length;
  int? lastMatch;

  int length(int nibble) {
    var value = nibble;
    if (nibble == 15) {
      int next;
      do {
        if (at == input.length) _fail('LZ4 block length is truncated.');
        next = input[at++];
        value += next;
        if (value > blockMaximum) {
          _fail('LZ4 block expansion exceeds its declared maximum size.');
        }
      } while (next == 255);
    }
    return value;
  }

  void checkSize(int count) {
    if (count > blockMaximum - (output.length - blockStart)) {
      _fail('LZ4 block expansion exceeds its declared maximum size.');
    }
  }

  while (at < input.length) {
    final token = input[at++];
    final literals = length(token >> 4);
    if (literals > input.length - at) _fail('LZ4 literals are truncated.');
    checkSize(literals);
    output.addRange(input, at, at + literals);
    at += literals;
    if (at == input.length) {
      if (lastMatch != null &&
          (literals < 5 || output.length - lastMatch < 12)) {
        _fail('LZ4 block violates its final-literal requirements.');
      }
      return;
    }
    if (input.length - at < 2) _fail('LZ4 match offset is truncated.');
    final offset = input[at] | input[at + 1] << 8;
    at += 2;
    if (offset == 0 || offset > output.length - dictionaryStart) {
      _fail('LZ4 match refers outside its available dictionary.');
    }
    final matchLength = length(token & 15) + 4;
    checkSize(matchLength);
    lastMatch = output.length;
    output.copyMatch(offset, matchLength);
  }
  _fail('LZ4 block is missing its final literal sequence.');
}

Uint8List _encodeBlock(Uint8List input) {
  if (input.length < 13) return input;
  final output = _Lz4Buffer(input.length + input.length ~/ 255 + 16);
  final positions = Uint32List(65536);
  var at = 0, anchor = 0;
  final matchLimit = input.length - 5;
  final lastMatchStart = input.length - 12;

  int hash(int position) => _multiply32(_word(input, position), _prime1) >>> 16;

  void extra(int remaining) {
    while (remaining >= 255) {
      output.addByte(255);
      remaining -= 255;
    }
    output.addByte(remaining);
  }

  while (at <= lastMatchStart) {
    final key = hash(at);
    final candidate = positions[key] - 1;
    positions[key] = at + 1;
    if (candidate < 0 ||
        at - candidate > 65535 ||
        _word(input, candidate) != _word(input, at)) {
      at++;
      continue;
    }
    final matchStart = at;
    var length = 4;
    while (at + length < matchLimit &&
        input[candidate + length] == input[at + length]) {
      length++;
    }
    final literals = at - anchor;
    final codedMatch = length - 4;
    output.addByte(
      (literals < 15 ? literals : 15) << 4 |
          (codedMatch < 15 ? codedMatch : 15),
    );
    if (literals >= 15) extra(literals - 15);
    output.addRange(input, anchor, at);
    final offset = at - candidate;
    output
      ..addByte(offset & 0xff)
      ..addByte(offset >> 8);
    if (codedMatch >= 15) extra(codedMatch - 15);
    at += length;
    anchor = at;
    // Populate the positions crossed by a match, without retaining a chain or
    // allowing the dictionary to grow with the size of the input.
    for (
      var position = matchStart + 1;
      position < at && position <= lastMatchStart;
      position++
    ) {
      positions[hash(position)] = position + 1;
    }
  }
  final literals = input.length - anchor;
  output.addByte((literals < 15 ? literals : 15) << 4);
  if (literals >= 15) extra(literals - 15);
  output.addRange(input, anchor, input.length);
  return output.takeBytes();
}

const _prime1 = 0x9e3779b1;
const _prime2 = 0x85ebca77;
const _prime3 = 0xc2b2ae3d;
const _prime4 = 0x27d4eb2f;
const _prime5 = 0x165667b1;

/// XXH32, used by LZ4 frame descriptors and payload integrity checks. Products
/// are split into 16-bit parts to remain exact in JavaScript's number model.
int archiveLz4Xxh32(Uint8List input, {int seed = 0}) {
  int rotate(int value, int bits) =>
      ((value << bits) | (value >>> (32 - bits))) & 0xffffffff;
  int round(int value, int lane) => _multiply32(
    rotate((value + _multiply32(lane, _prime2)) & 0xffffffff, 13),
    _prime1,
  );

  var at = 0;
  int hash;
  if (input.length >= 16) {
    var v1 = (seed + _prime1 + _prime2) & 0xffffffff;
    var v2 = (seed + _prime2) & 0xffffffff;
    var v3 = seed & 0xffffffff;
    var v4 = (seed - _prime1) & 0xffffffff;
    do {
      v1 = round(v1, _word(input, at));
      v2 = round(v2, _word(input, at + 4));
      v3 = round(v3, _word(input, at + 8));
      v4 = round(v4, _word(input, at + 12));
      at += 16;
    } while (at <= input.length - 16);
    hash =
        (rotate(v1, 1) + rotate(v2, 7) + rotate(v3, 12) + rotate(v4, 18)) &
        0xffffffff;
  } else {
    hash = (seed + _prime5) & 0xffffffff;
  }
  hash = (hash + input.length) & 0xffffffff;
  while (at <= input.length - 4) {
    hash = _multiply32(
      rotate((hash + _multiply32(_word(input, at), _prime3)) & 0xffffffff, 17),
      _prime4,
    );
    at += 4;
  }
  while (at < input.length) {
    hash = _multiply32(
      rotate((hash + _multiply32(input[at++], _prime5)) & 0xffffffff, 11),
      _prime1,
    );
  }
  hash = _multiply32(hash ^ (hash >>> 15), _prime2);
  hash = _multiply32(hash ^ (hash >>> 13), _prime3);
  return (hash ^ (hash >>> 16)) & 0xffffffff;
}

int _multiply32(int a, int b) {
  final low = (a & 0xffff) * (b & 0xffff);
  final high = ((a >>> 16) * (b & 0xffff) + (a & 0xffff) * (b >>> 16)) & 0xffff;
  return (low + high * 65536) & 0xffffffff;
}

int _word(Uint8List bytes, int at) =>
    (bytes[at] |
        bytes[at + 1] << 8 |
        bytes[at + 2] << 16 |
        bytes[at + 3] << 24) &
    0xffffffff;

void _checkLimit(int value) {
  if (value < 0 || value > kArchiveReadLimit) {
    throw ArgumentError.value(value, 'maxOutputBytes', 'Expected 0 to 64 MiB.');
  }
}

Never _fail(String message) => throw ArchiveViewException(message);

class _Lz4Buffer {
  final int maximum;
  Uint8List _bytes = Uint8List(0);
  int length = 0;

  _Lz4Buffer(this.maximum);

  void reserve(int count) {
    if (count < 0 || count > maximum - length) {
      _fail('LZ4 contents exceed the output limit.');
    }
    final required = length + count;
    if (required <= _bytes.length) return;
    var capacity = _bytes.isEmpty ? 4096 : _bytes.length;
    while (capacity < required) {
      capacity *= 2;
    }
    if (capacity > maximum) capacity = maximum;
    final grown = Uint8List(capacity)..setRange(0, length, _bytes);
    _bytes = grown;
  }

  void addByte(int byte) {
    reserve(1);
    _bytes[length++] = byte;
  }

  void addWord(int word) {
    reserve(4);
    for (var i = 0; i < 4; i++) {
      _bytes[length++] = word >> (i * 8) & 0xff;
    }
  }

  void addRange(Uint8List input, int start, int end) {
    reserve(end - start);
    _bytes.setRange(length, length + end - start, input, start);
    length += end - start;
  }

  void copyMatch(int offset, int count) {
    reserve(count);
    final end = length + count;
    while (length < end) {
      _bytes[length] = _bytes[length - offset];
      length++;
    }
  }

  Uint8List view(int start) => Uint8List.sublistView(_bytes, start, length);

  Uint8List takeBytes() =>
      length == _bytes.length ? _bytes : Uint8List.fromList(view(0));
}
