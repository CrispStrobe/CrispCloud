// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Original sparse UDF fixture assembler; intentionally independent of the reader.
import 'dart:convert';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

const udfBlockBytes = 2048;
void udfPut16(Uint8List bytes, int at, int value) =>
    ByteData.sublistView(bytes).setUint16(at, value, Endian.little);
void udfPut32(Uint8List bytes, int at, int value) =>
    ByteData.sublistView(bytes).setUint32(at, value, Endian.little);
void udfPut64(Uint8List bytes, int at, int value) {
  udfPut32(bytes, at, value % 4294967296);
  udfPut32(bytes, at + 4, value ~/ 4294967296);
}

int udfGet16(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint16(at, Endian.little);
int udfGet32(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint32(at, Endian.little);

/// Independent bit-by-bit polynomial division, with no shared reader code.
void udfTag(
  Uint8List bytes,
  int id,
  int block,
  int length, {
  int version = 2,
  int? crcLength,
}) {
  udfPut16(bytes, 0, id);
  udfPut16(bytes, 2, version);
  bytes[5] = 0;
  udfPut16(bytes, 6, 1);
  udfPut32(bytes, 12, block);
  final count = crcLength ?? length - 16;
  var remainder = 0;
  for (var at = 16; at < 16 + count; at++) {
    for (var bit = 7; bit >= 0; bit--) {
      final feedback = ((remainder ~/ 32768) ^ (bytes[at] >> bit)) & 1;
      remainder = (remainder * 2) & 65535;
      if (feedback == 1) remainder ^= 0x1021;
    }
  }
  udfPut16(bytes, 8, remainder);
  udfPut16(bytes, 10, count);
  bytes[4] = 0;
  var sum = 0;
  for (var at = 0; at < 16; at++) {
    sum += bytes[at];
  }
  bytes[4] = sum & 255;
}

void udfRetag(Uint8List bytes, {int? length, int? block}) => udfTag(
  bytes,
  udfGet16(bytes, 0),
  block ?? udfGet32(bytes, 12),
  length ?? udfGet16(bytes, 10) + 16,
  version: udfGet16(bytes, 2),
);

void udfLong(
  Uint8List bytes,
  int at,
  int length,
  int block, {
  int partition = 0,
  int kind = 0,
}) {
  udfPut32(bytes, at, length + kind * 1073741824);
  udfPut32(bytes, at + 4, block);
  udfPut16(bytes, at + 8, partition);
}

void udfShort(Uint8List bytes, int at, int length, int block, {int kind = 0}) {
  udfPut32(bytes, at, length + kind * 1073741824);
  udfPut32(bytes, at + 4, block);
}

void _ascii(Uint8List bytes, int at, String text) =>
    bytes.setRange(at, at + text.length, ascii.encode(text));
void _charset(Uint8List bytes, int at) =>
    _ascii(bytes, at + 1, 'OSTA Compressed Unicode');
void _domain(Uint8List bytes, int at, int revision) {
  _ascii(bytes, at + 1, '*OSTA UDF Compliant');
  udfPut16(bytes, at + 24, revision);
}

Uint8List udfName(String name) {
  if (name.codeUnits.every((unit) => unit <= 255)) {
    return Uint8List.fromList([8, ...name.codeUnits]);
  }
  return Uint8List.fromList([
    16,
    for (final unit in name.codeUnits) ...[unit >> 8, unit & 255],
  ]);
}

Uint8List udfFid({
  required int directoryBlock,
  required int childBlock,
  String? name,
  bool isDirectory = false,
  int flags = 0,
}) {
  final encoded = name == null ? Uint8List(0) : udfName(name);
  final length = (38 + encoded.length + 3) ~/ 4 * 4;
  final bytes = Uint8List(length);
  udfPut16(bytes, 16, 1);
  bytes[18] = flags | (isDirectory ? 2 : 0) | (name == null ? 10 : 0);
  bytes[19] = encoded.length;
  udfLong(bytes, 20, udfBlockBytes, childBlock);
  bytes.setRange(38, 38 + encoded.length, encoded);
  udfTag(bytes, 257, directoryBlock, length);
  return bytes;
}

class UdfFixture {
  UdfFixture({
    this.revision = 0x102,
    this.extended = false,
    this.allocation = 'short',
    this.embeddedDirectory = false,
    this.partitionStart = 300,
    this.partitionBlocks = 100,
    this.imageBlocks,
    this.fileName = 'hello.txt',
    List<int>? fileData,
  }) : payload = Uint8List.fromList(fileData ?? utf8.encode('hello UDF\n')) {
    for (final (block, id) in [(16, 'BEA01'), (17, 'NSR02'), (18, 'TEA01')]) {
      final bytes = sector(block);
      _ascii(bytes, 1, id);
      bytes[6] = 1;
    }
    if (revision >= 0x200) _ascii(sector(17), 1, 'NSR03');
    final anchor = sector(256);
    udfPut32(anchor, 16, 4 * udfBlockBytes);
    udfPut32(anchor, 20, 257);
    udfTag(anchor, 2, 256, 512);
    final primary = sector(257);
    udfPut32(primary, 16, 1);
    udfPut16(primary, 56, 1);
    udfPut16(primary, 58, 1);
    udfTag(primary, 1, 257, 512);
    final partition = sector(258);
    udfPut32(partition, 16, 2);
    udfPut16(partition, 20, 1);
    _ascii(partition, 25, revision >= 0x200 ? '+NSR03' : '+NSR02');
    udfPut32(partition, 184, 1);
    udfPut32(partition, 188, partitionStart);
    udfPut32(partition, 192, partitionBlocks);
    udfTag(partition, 5, 258, 512);
    final logical = sector(259);
    udfPut32(logical, 16, 3);
    _charset(logical, 20);
    udfPut32(logical, 212, udfBlockBytes);
    _domain(logical, 216, revision);
    udfLong(logical, 248, udfBlockBytes, 0);
    udfPut32(logical, 264, 6);
    udfPut32(logical, 268, 1);
    udfPut32(logical, 432, 2 * udfBlockBytes);
    udfPut32(logical, 436, 264);
    logical[440] = 1;
    logical[441] = 6;
    udfPut16(logical, 442, 1);
    udfTag(logical, 6, 259, 446);
    udfTag(sector(260), 8, 260, 512);
    final integrity = sector(264);
    udfPut32(integrity, 28, 1);
    udfPut32(integrity, 72, 1);
    udfPut32(integrity, 76, 46);
    udfPut32(integrity, 84, partitionBlocks);
    udfPut16(integrity, 128, revision);
    udfPut16(integrity, 130, revision);
    udfPut16(integrity, 132, revision);
    udfTag(integrity, 9, 264, 134);
    udfTag(sector(265), 8, 265, 512);
    final fsd = partitionSector(0);
    udfPut16(fsd, 28, 3);
    udfPut16(fsd, 30, 3);
    udfPut32(fsd, 32, 1);
    udfPut32(fsd, 36, 1);
    _charset(fsd, 48);
    _charset(fsd, 240);
    _domain(fsd, 416, revision);
    udfLong(fsd, 400, udfBlockBytes, 1);
    udfTag(fsd, 256, 0, 512);
    final directoryBlock = embeddedDirectory ? 1 : 10;
    final parent = udfFid(directoryBlock: directoryBlock, childBlock: 1);
    final file = udfFid(
      directoryBlock: directoryBlock,
      childBlock: 2,
      name: fileName,
    );
    final contents = Uint8List.fromList([...parent, ...file]);
    directoryBytes = contents;
    makeFile(
      1,
      type: 4,
      size: contents.length,
      data: contents,
      dataBlock: 10,
      allocation: embeddedDirectory ? 'embedded' : 'short',
    );
    makeFile(
      2,
      type: 5,
      size: payload.length,
      data: payload,
      dataBlock: 20,
      allocation: allocation,
      extended: extended,
    );
  }
  final int revision, partitionStart, partitionBlocks;
  final int? imageBlocks;
  final bool extended, embeddedDirectory;
  final String allocation, fileName;
  final Uint8List payload;
  late Uint8List directoryBytes;
  final sectors = <int, Uint8List>{};
  int get length =>
      (imageBlocks ?? partitionStart + partitionBlocks) * udfBlockBytes;
  Uint8List sector(int block) =>
      sectors.putIfAbsent(block, () => Uint8List(udfBlockBytes));
  Uint8List partitionSector(int block) => sector(partitionStart + block);
  Uint8List get fileEntry => partitionSector(2);
  Uint8List get rootEntry => partitionSector(1);
  Uint8List get rootDirectory => partitionSector(10);
  int get fileAllocationAt => extended ? 216 : 176;

  void makeFile(
    int block, {
    required int type,
    required int size,
    required Uint8List data,
    required int dataBlock,
    String allocation = 'short',
    bool extended = false,
  }) {
    final bytes = partitionSector(block)..fillRange(0, udfBlockBytes, 0);
    final fixed = extended ? 216 : 176;
    udfPut16(bytes, 20, 4);
    udfPut16(bytes, 24, 1);
    bytes[27] = type;
    udfPut16(
      bytes,
      34,
      allocation == 'embedded'
          ? 3
          : allocation == 'long'
          ? 1
          : 0,
    );
    udfPut32(bytes, 44, 0x1084);
    udfPut16(bytes, 48, 1);
    udfPut64(bytes, 56, size);
    if (extended) udfPut64(bytes, 64, size);
    udfPut64(
      bytes,
      extended ? 72 : 64,
      allocation == 'embedded' ? 0 : (size + 2047) ~/ 2048,
    );
    final stamp = extended ? 92 : 84;
    udfPut16(bytes, stamp, 0x1000);
    udfPut16(bytes, stamp + 2, 2026);
    bytes[stamp + 4] = 11;
    bytes[stamp + 5] = 14;
    bytes[stamp + 6] = 8;
    bytes[stamp + 7] = 30;
    bytes[stamp + 8] = 12;
    final adLength = allocation == 'embedded'
        ? data.length
        : size == 0
        ? 0
        : allocation == 'long'
        ? 16
        : 8;
    udfPut32(bytes, fixed - 4, adLength);
    if (allocation == 'embedded') {
      bytes.setRange(fixed, fixed + data.length, data);
    } else if (size != 0) {
      if (allocation == 'long') {
        udfLong(bytes, fixed, size, dataBlock);
      } else {
        udfShort(bytes, fixed, size, dataBlock);
      }
      for (var at = 0; at < data.length; at += udfBlockBytes) {
        final end = at + udfBlockBytes < data.length
            ? at + udfBlockBytes
            : data.length;
        partitionSector(dataBlock + at ~/ udfBlockBytes)
            .setRange(0, end - at, data.sublist(at, end));
      }
    }
    udfTag(
      bytes,
      extended ? 266 : 261,
      block,
      fixed + adLength,
      version: revision >= 0x200 ? 3 : 2,
    );
  }

  Uint8List materialize() {
    if (length > 16 * 1024 * 1024) {
      throw StateError('Use sparse source for large fixtures.');
    }
    final bytes = Uint8List(length);
    for (final entry in sectors.entries) {
      bytes.setRange(
        entry.key * udfBlockBytes,
        (entry.key + 1) * udfBlockBytes,
        entry.value,
      );
    }
    return bytes;
  }

  UdfFixtureSource source() => UdfFixtureSource(this);
}

class UdfFixtureSource implements koni.ByteSource {
  UdfFixtureSource(this.fixture);
  final UdfFixture fixture;
  @override
  int get length => fixture.length;
  @override
  String? get name => 'fixture.udf';
  bool closed = false;
  int closeCount = 0;
  final reads = <(int, int)>[];
  @override
  Future<Uint8List> read(int offset, int length) async {
    if (closed) throw StateError('Source is closed.');
    if (offset < 0 || length < 0 || offset > this.length - length) {
      throw RangeError('fixture read');
    }
    reads.add((offset, length));
    final result = Uint8List(length);
    for (var at = 0; at < length;) {
      final physical = offset + at;
      final block = physical ~/ udfBlockBytes;
      final within = physical % udfBlockBytes;
      final count = length - at < udfBlockBytes - within
          ? length - at
          : udfBlockBytes - within;
      final data = fixture.sectors[block];
      if (data != null) result.setRange(at, at + count, data, within);
      at += count;
    }
    return result;
  }

  @override
  Future<void> close() async {
    closed = true;
    closeCount++;
  }
}
