import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart' as crypto;

import 'archive_package_fixtures.dart';

class RpmFixtureTag {
  const RpmFixtureTag(this.tag, this.type, this.count, this.data);
  factory RpmFixtureTag.string(int tag, String value) =>
      RpmFixtureTag(tag, 6, 1, [...utf8.encode(value), 0]);
  factory RpmFixtureTag.strings(int tag, List<String> values) =>
      RpmFixtureTag(tag, 8, values.length, [
        for (final value in values) ...[...utf8.encode(value), 0],
      ]);
  factory RpmFixtureTag.uint32(int tag, int value) => RpmFixtureTag(
    tag,
    4,
    1,
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List(),
  );
  final int tag, type, count;
  final List<int> data;
}

/// Independent layout builder for precise malformed-header and payload tests.
/// Native rpmbuild reference fixtures are tested separately from this builder.
class RpmFixture {
  RpmFixture({
    String compressor = 'gzip',
    String? declaredCompressor,
    String format = 'cpio',
    List<PackageFixtureEntry>? entries,
    Uint8List? payload,
    Uint8List? packedPayload,
    bool checksum = true,
    bool payloadDigests = true,
    bool payloadTags = true,
    bool crc = false,
    List<RpmFixtureTag> headerTags = const [],
    List<RpmFixtureTag> signatureTags = const [],
  }) {
    final unpacked =
        payload ??
        cpioFixture(
          entries ??
              const [
                PackageFixtureEntry('docs', [], mode: 0x41ed),
                PackageFixtureEntry('docs/hello.txt', [
                  104,
                  101,
                  108,
                  108,
                  111,
                  10,
                ]),
                PackageFixtureEntry('empty', []),
              ],
          crc: crc,
        );
    final packed =
        packedPayload ??
        Uint8List.fromList(switch (compressor) {
          'gzip' => const ar.GZipEncoder().encode(unpacked),
          'bzip2' => ar.BZip2Encoder().encode(unpacked),
          'xz' => ar.XZEncoder().encode(unpacked),
          'zstd' => ar.ZstdEncoder().encode(unpacked),
          _ => unpacked,
        });
    final header = _header([
      RpmFixtureTag.string(1000, 'crispcloud-reader-fixture'),
      RpmFixtureTag.string(1001, '1.0'),
      RpmFixtureTag.string(1002, '1'),
      RpmFixtureTag.uint32(1046, unpacked.length),
      if (payloadTags) ...[
        RpmFixtureTag.string(1124, format),
        RpmFixtureTag.string(1125, declaredCompressor ?? compressor),
      ],
      if (payloadDigests) ...[
        RpmFixtureTag.strings(5092, [crypto.sha256.convert(packed).toString()]),
        RpmFixtureTag.uint32(5093, 8),
        RpmFixtureTag.strings(5097, [
          crypto.sha256.convert(unpacked).toString(),
        ]),
      ],
      ...headerTags,
    ]);
    final signature = _header([
      RpmFixtureTag.uint32(1000, header.length + packed.length),
      if (checksum)
        RpmFixtureTag(
          1004,
          7,
          16,
          crypto.md5.convert([...header, ...packed]).bytes,
        ),
      RpmFixtureTag.uint32(1007, unpacked.length),
      ...signatureTags,
    ]);
    headerOffset = (96 + signature.length + 7) ~/ 8 * 8;
    payloadOffset = headerOffset + header.length;
    final lead = ByteData(96)
      ..setUint32(0, 0xedabeedb)
      ..setUint8(4, 3)
      ..setUint16(78, 5);
    bytes = Uint8List.fromList([
      ...lead.buffer.asUint8List(),
      ...signature,
      ...List<int>.filled(headerOffset - 96 - signature.length, 0),
      ...header,
      ...packed,
    ]);
  }

  late final Uint8List bytes;
  late final int headerOffset, payloadOffset;

  int indexOffset(int tag, {bool signature = false}) {
    final start = signature ? 96 : headerOffset;
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < data.getUint32(start + 8); i++) {
      final at = start + 16 + i * 16;
      if (data.getUint32(at) == tag) return at;
    }
    throw StateError('Missing fixture tag $tag');
  }

  int dataOffset(int tag, {bool signature = false}) {
    final start = signature ? 96 : headerOffset;
    final data = ByteData.sublistView(bytes);
    return start +
        16 +
        data.getUint32(start + 8) * 16 +
        data.getUint32(indexOffset(tag, signature: signature) + 8);
  }
}

Uint8List _header(List<RpmFixtureTag> tags) {
  tags.sort((a, b) => a.tag.compareTo(b.tag));
  final index = ByteData(tags.length * 16);
  final data = BytesBuilder();
  for (var i = 0; i < tags.length; i++) {
    final tag = tags[i];
    final width = switch (tag.type) {
      3 => 2,
      4 => 4,
      5 => 8,
      _ => 1,
    };
    while (data.length % width != 0) {
      data.addByte(0);
    }
    index
      ..setUint32(i * 16, tag.tag)
      ..setUint32(i * 16 + 4, tag.type)
      ..setUint32(i * 16 + 8, data.length)
      ..setUint32(i * 16 + 12, tag.count);
    data.add(tag.data);
  }
  final prefix = ByteData(16)
    ..setUint32(0, 0x8eade801)
    ..setUint32(8, tags.length)
    ..setUint32(12, data.length);
  return Uint8List.fromList([
    ...prefix.buffer.asUint8List(),
    ...index.buffer.asUint8List(),
    ...data.takeBytes(),
  ]);
}
