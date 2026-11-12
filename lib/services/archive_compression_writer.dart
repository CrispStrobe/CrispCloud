import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crypto/crypto.dart';
import 'package:koni_codecs/koni_codecs.dart' as koni;

import 'archive_types.dart';

enum ArchiveCompressionKind { gzip, bzip2, xz, zstd }

ArchiveCompressionKind? archiveCompressionForBytes(Uint8List bytes) {
  bool starts(List<int> signature) =>
      bytes.length >= signature.length &&
      Iterable<int>.generate(signature.length)
          .every((i) => bytes[i] == signature[i]);
  if (starts(const [0x1f, 0x8b])) return ArchiveCompressionKind.gzip;
  if (starts(const [0x42, 0x5a, 0x68])) return ArchiveCompressionKind.bzip2;
  if (starts(const [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0])) {
    return ArchiveCompressionKind.xz;
  }
  if (starts(const [0x28, 0xb5, 0x2f, 0xfd])) {
    return ArchiveCompressionKind.zstd;
  }
  return null;
}

/// Bounded portable encoders for single-file streams and TAR wrappers. XZ
/// uses real LZMA2 compression, with the standard XZ framing and integrity
/// checks, rather than the store-only encoder provided by archive 4.6.0.
/// https://tukaani.org/xz/xz-file-format.txt
Uint8List encodeArchiveCompression(
  Uint8List input,
  ArchiveCompressionKind kind, {
  int level = 6,
  int maxOutputBytes = kArchiveReadLimit,
  Uint8List? gzipHeader,
  int xzCheck = 4,
}) {
  if (input.length > kArchiveReadLimit) {
    throw const ArchiveViewException(
      'Compressed archive contents exceed 64 MiB.',
    );
  }
  if (level < 0 || level > 9 || maxOutputBytes <= 0) {
    throw ArgumentError('Invalid archive compression options.');
  }
  if (gzipHeader != null && kind != ArchiveCompressionKind.gzip) {
    throw ArgumentError('A gzip header requires gzip compression.');
  }
  final output = _CompressionOutput(maxOutputBytes);
  final source = codecs.InputMemoryStream(input);
  switch (kind) {
    case ArchiveCompressionKind.gzip:
      const codecs.GZipEncoder().encodeStream(source, output, level: level);
      if (gzipHeader != null) {
        final packed = output.getBytes();
        if (_gzipHeaderLength(gzipHeader) != gzipHeader.length ||
            packed.length < 18 ||
            _gzipHeaderLength(packed) != 10) {
          throw const ArchiveViewException('Unsupported gzip header.');
        }
        final replaced = _CompressionOutput(maxOutputBytes)
          ..writeBytes(gzipHeader)
          ..writeBytes(Uint8List.sublistView(packed, 10));
        return Uint8List.fromList(replaced.getBytes());
      }
    case ArchiveCompressionKind.bzip2:
      if (!codecs.BZip2Encoder().encodeStream(
        source,
        output,
        blockSize100k: level.clamp(1, 9),
      )) {
        throw const ArchiveViewException('Bzip2 compression failed.');
      }
    case ArchiveCompressionKind.xz:
      _writeXz(input, output, level: level, check: xzCheck);
    case ArchiveCompressionKind.zstd:
      codecs.ZstdEncoder().encodeStream(
        source,
        output,
        level: level == 0 ? 1 : level,
        checksum: true,
      );
  }
  return Uint8List.fromList(output.getBytes());
}

/// Retains a gzip member's name, comment, timestamp, OS and extra fields.
/// The parser is bounded independently of compressed payload size.
Uint8List archiveGzipHeader(Uint8List bytes) =>
    Uint8List.fromList(bytes.sublist(0, _gzipHeaderLength(bytes)));

/// Refuses frame collections whose per-frame metadata would be lost by a
/// one-stream rewrite. The normal reader has already checked payload integrity.
void validateArchiveCompressionRewrite(
  Uint8List bytes,
  ArchiveCompressionKind kind,
) {
  void refuse() => throw const ArchiveViewException(
    'Concatenated streams, extra frames or unsupported compression metadata cannot be preserved by this writer.',
  );
  switch (kind) {
    case ArchiveCompressionKind.gzip:
      final header = _gzipHeaderLength(bytes);
      final input = codecs.InputMemoryStream(
        Uint8List.sublistView(bytes, header),
      );
      final output = _CompressionOutput(kArchiveReadLimit);
      final inflate = codecs.Inflate.stream(
        input,
        output: output,
        throwOnError: true,
      );
      if (!inflate.isFinished || input.length != 8) refuse();
      final crc = input.readUint32(), size = input.readUint32();
      if (size != output.length || crc != codecs.getCrc32(output.getBytes())) {
        refuse();
      }
    case ArchiveCompressionKind.xz:
      if (bytes.length < 32 ||
          bytes[bytes.length - 2] != 0x59 ||
          bytes.last != 0x5a) {
        refuse();
      }
      final data = ByteData.sublistView(bytes);
      final footer = bytes.length - 12;
      final indexBytes = (data.getUint32(footer + 4, Endian.little) + 1) * 4;
      final index = footer - indexBytes;
      if (index < 12 ||
          index >= footer ||
          bytes[index] != 0 ||
          bytes[footer + 8] != bytes[6] ||
          bytes[footer + 9] != bytes[7]) {
        refuse();
      }
      var at = index + 1;
      int variable() {
        var value = 0, scale = 1;
        for (var i = 0; i < 8; i++) {
          if (at >= footer - 4) refuse();
          final byte = bytes[at++];
          value += (byte & 0x7f) * scale;
          if (value > 0x1fffffffffffff) refuse();
          if (byte < 0x80) {
            if (i > 0 && byte == 0) refuse();
            return value;
          }
          scale *= 128;
        }
        refuse();
        return 0;
      }
      final count = variable();
      if (count > 200000) refuse();
      var blockEnd = 12, decoded = 0;
      for (var i = 0; i < count; i++) {
        final unpadded = variable();
        if (unpadded < 5) refuse();
        blockEnd += (unpadded + 3) ~/ 4 * 4;
        decoded += variable();
        if (blockEnd > index || decoded > kArchiveReadLimit) refuse();
      }
      if (blockEnd != index || footer - 4 - at > 3) refuse();
      while (at < footer - 4) {
        if (bytes[at++] != 0) refuse();
      }
    case ArchiveCompressionKind.zstd:
      if (bytes.length < 6 || archiveCompressionForBytes(bytes) != kind) {
        refuse();
      }
      final flags = bytes[4];
      // Dictionary IDs and skippable extension frames require another writer.
      if (flags & 0x1b != 0) refuse();
      final singleSegment = flags & 0x20 != 0;
      final sizeFlag = flags >> 6;
      var at =
          5 +
          (singleSegment ? 0 : 1) +
          (sizeFlag == 0 ? (singleSegment ? 1 : 0) : 1 << sizeFlag);
      var blocks = 0;
      while (true) {
        if (at + 3 > bytes.length || ++blocks > 1000000) refuse();
        final block = bytes[at] | bytes[at + 1] << 8 | bytes[at + 2] << 16;
        at += 3;
        final type = block >> 1 & 3, size = block >> 3;
        if (type == 3 || size > 128 * 1024) refuse();
        at += type == 1 ? 1 : size;
        if (at > bytes.length) refuse();
        if (block & 1 != 0) break;
      }
      if (flags & 4 != 0) at += 4;
      if (at != bytes.length) refuse();
    case ArchiveCompressionKind.bzip2:
      // Bzip2 streams carry no per-file names, dates or opaque extension data.
      if (bytes.length < 4 || bytes[3] < 0x31 || bytes[3] > 0x39) refuse();
  }
}

int _gzipHeaderLength(Uint8List bytes) {
  if (bytes.length < 10 ||
      bytes[0] != 0x1f ||
      bytes[1] != 0x8b ||
      bytes[2] != 8 ||
      bytes[3] & 0xe0 != 0) {
    throw const ArchiveViewException('Invalid gzip header.');
  }
  var offset = 10;
  void require(int count) {
    if (count < 0 || count > bytes.length - offset || offset + count > 65536) {
      throw const ArchiveViewException(
        'Gzip header exceeds its metadata limit.',
      );
    }
  }

  if (bytes[3] & 4 != 0) {
    require(2);
    final size = bytes[offset] | bytes[offset + 1] << 8;
    offset += 2;
    require(size);
    offset += size;
  }
  for (final flag in const [8, 16]) {
    if (bytes[3] & flag == 0) continue;
    while (true) {
      require(1);
      if (bytes[offset++] == 0) break;
    }
  }
  if (bytes[3] & 2 != 0) {
    require(2);
    final crc = codecs.getCrc32(Uint8List.sublistView(bytes, 0, offset));
    if ((crc & 0xffff) != (bytes[offset] | bytes[offset + 1] << 8)) {
      throw const ArchiveViewException('Gzip header checksum mismatch.');
    }
    offset += 2;
  }
  return offset;
}

void _writeXz(
  Uint8List input,
  _CompressionOutput output, {
  required int level,
  required int check,
}) {
  if (!const [0, 1, 4, 10].contains(check)) {
    throw const ArchiveViewException('Unsupported XZ integrity check.');
  }
  final flags = Uint8List.fromList([0, check]);
  output.writeBytes(const [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0]);
  output.writeBytes(flags);
  output.writeUint32(codecs.getCrc32(flags));
  var unpadded = 0;
  if (input.isNotEmpty) {
    // LZMA2 is bounded by the captured input size and a fixed dictionary.
    final encoder = koni.Lzma2Encoder(
      dictSize: level <= 1
          ? 1 << 20
          : level >= 9
          ? 1 << 24
          : 1 << 23,
    );
    final data = encoder.encode(input);
    final header = Uint8List.fromList([
      2,
      0,
      0x21,
      1,
      encoder.dictSizeProp,
      0,
      0,
      0,
    ]);
    output.writeBytes(header);
    output.writeUint32(codecs.getCrc32(header));
    output.writeBytes(data);
    final padding = (4 - data.length % 4) % 4;
    output.writeBytes(Uint8List(padding));
    final checksum = switch (check) {
      0 => Uint8List(0),
      1 =>
        (ByteData(4)..setUint32(0, codecs.getCrc32(input), Endian.little))
            .buffer
            .asUint8List(),
      4 => codecs.crc64Bytes(input),
      10 => Uint8List.fromList(sha256.convert(input).bytes),
      _ => throw StateError('Unreachable XZ check'),
    };
    output.writeBytes(checksum);
    unpadded = 12 + data.length + checksum.length;
  }
  final index = codecs.OutputMemoryStream()..writeByte(0);
  void variable(int value) {
    do {
      final next = value >> 7;
      index.writeByte((value & 0x7f) | (next == 0 ? 0 : 0x80));
      value = next;
    } while (value != 0);
  }

  variable(input.isEmpty ? 0 : 1);
  if (input.isNotEmpty) {
    variable(unpadded);
    variable(input.length);
  }
  while (index.length % 4 != 0) {
    index.writeByte(0);
  }
  index.writeUint32(codecs.getCrc32(index.getBytes()));
  output.writeBytes(index.getBytes());
  final footer = codecs.OutputMemoryStream()
    ..writeUint32(index.length ~/ 4 - 1)
    ..writeBytes(flags);
  output.writeUint32(codecs.getCrc32(footer.getBytes()));
  output.writeBytes(footer.getBytes());
  output.writeBytes(const [0x59, 0x5a]);
}

class _CompressionOutput extends codecs.OutputMemoryStream {
  _CompressionOutput(this.limit) : super(size: limit < 32768 ? limit : 32768);
  final int limit;

  void _check(int count) {
    if (count < 0 || count > limit - length) {
      throw const ArchiveViewException('Compressed output exceeds its limit.');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(codecs.InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void reserve(int total) {
    if (total > limit) {
      throw const ArchiveViewException('Compressed output exceeds its limit.');
    }
    super.reserve(total);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}
