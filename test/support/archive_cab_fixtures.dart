import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;

class CabFixtureFile {
  const CabFixtureFile(this.name, this.data, {this.attributes = 0xa0});
  final String name;
  final List<int> data;
  final int attributes;
}

class CabFixtureFolder {
  const CabFixtureFolder(this.files, {this.method = 0});
  final List<CabFixtureFile> files;
  final int method;
}

/// Original CAB framing for malformed and boundary tests. Cross-implementation
/// fixtures (Windows MakeCAB and Python/zlib) are kept separately on disk.
Uint8List cabFixture(
  List<CabFixtureFolder> folders, {
  bool checksums = true,
  List<int> headerReserve = const [],
  List<int> folderReserve = const [],
  List<int> dataReserve = const [],
}) {
  final reserve =
      headerReserve.isNotEmpty ||
      folderReserve.isNotEmpty ||
      dataReserve.isNotEmpty;
  final files = BytesBuilder(copy: false);
  final payloads = <Uint8List>[];
  final blockCounts = <int>[];
  var count = 0;
  for (var folderIndex = 0; folderIndex < folders.length; folderIndex++) {
    final folder = folders[folderIndex];
    final content = BytesBuilder(copy: false);
    for (final file in folder.files) {
      final record = ByteData(16)
        ..setUint32(0, file.data.length, Endian.little)
        ..setUint32(4, content.length, Endian.little)
        ..setUint16(8, folderIndex, Endian.little)
        ..setUint16(10, (44 << 9) | (1 << 5) | 2, Endian.little)
        ..setUint16(12, (3 << 11) | (4 << 5) | 3, Endian.little)
        ..setUint16(14, file.attributes, Endian.little);
      files.add(record.buffer.asUint8List());
      files.add(utf8.encode(file.name));
      files.addByte(0);
      content.add(file.data);
      count++;
    }
    final plain = content.takeBytes();
    final packedFolder = BytesBuilder(copy: false);
    var blocks = 0;
    for (var at = 0; at < plain.length; at += 32768) {
      final end = at + 32768 < plain.length ? at + 32768 : plain.length;
      final block = Uint8List.sublistView(plain, at, end);
      final packed = folder.method == 1
          ? Uint8List.fromList([0x43, 0x4b, ...ar.Deflate(block).getBytes()])
          : block;
      final record = Uint8List(8 + dataReserve.length);
      record.setRange(8, record.length, dataReserve);
      final data = ByteData.sublistView(record)
        ..setUint16(4, packed.length, Endian.little)
        ..setUint16(6, block.length, Endian.little);
      if (checksums) {
        data.setUint32(
          0,
          cabFixtureChecksum(packed) ^
              cabFixtureChecksum(Uint8List.sublistView(record, 4)),
          Endian.little,
        );
      }
      packedFolder.add(record);
      packedFolder.add(packed);
      blocks++;
    }
    payloads.add(packedFolder.takeBytes());
    blockCounts.add(blocks);
  }
  final headerSize = 36 + (reserve ? 4 + headerReserve.length : 0);
  final folderSize = folders.length * (8 + folderReserve.length);
  final fileBytes = files.takeBytes();
  final dataOffset = headerSize + folderSize + fileBytes.length;
  final header = Uint8List(headerSize);
  header.setRange(0, 4, ascii.encode('MSCF'));
  final headerData = ByteData.sublistView(header)
    ..setUint32(
      8,
      dataOffset + payloads.fold(0, (a, b) => a + b.length),
      Endian.little,
    )
    ..setUint32(16, headerSize + folderSize, Endian.little)
    ..setUint8(24, 3)
    ..setUint8(25, 1)
    ..setUint16(26, folders.length, Endian.little)
    ..setUint16(28, count, Endian.little)
    ..setUint16(30, reserve ? 4 : 0, Endian.little);
  if (reserve) {
    headerData
      ..setUint16(36, headerReserve.length, Endian.little)
      ..setUint8(38, folderReserve.length)
      ..setUint8(39, dataReserve.length);
    header.setRange(40, header.length, headerReserve);
  }
  final folderTable = Uint8List(folderSize);
  final folderData = ByteData.sublistView(folderTable);
  var at = dataOffset;
  for (var i = 0; i < folders.length; i++) {
    final offset = i * (8 + folderReserve.length);
    folderData
      ..setUint32(offset, at, Endian.little)
      ..setUint16(offset + 4, blockCounts[i], Endian.little)
      ..setUint16(offset + 6, folders[i].method, Endian.little);
    folderTable.setRange(
      offset + 8,
      offset + 8 + folderReserve.length,
      folderReserve,
    );
    at += payloads[i].length;
  }
  return Uint8List.fromList([
    ...header,
    ...folderTable,
    ...fileBytes,
    ...payloads.expand((p) => p),
  ]);
}

int cabFixtureChecksum(Uint8List bytes) {
  var sum = 0;
  for (var at = 0; at < bytes.length; at += 4) {
    final left = bytes.length - at;
    if (left >= 4) {
      sum ^= ByteData.sublistView(bytes).getUint32(at, Endian.little);
    } else {
      var tail = 0;
      for (var i = 0; i < left; i++) {
        tail = (tail << 8) | bytes[at + i];
      }
      sum ^= tail;
    }
  }
  return sum & 0xffffffff;
}
