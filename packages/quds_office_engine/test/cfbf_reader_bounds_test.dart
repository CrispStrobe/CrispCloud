import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('an out-of-range stream start sector is a typed CFBF rejection', () {
    final writer = CfbfWriter()
      ..addStream('Big', Uint8List.fromList(List<int>.filled(5000, 0x41)));
    final bytes = writer.build();
    final parsed = CfbfFile.fromBytes(bytes);
    final entry = parsed.entries.firstWhere((row) => row.name == 'Big');
    final header = CfbfHeader.parse(MemoryByteSource(bytes));
    final directoryOffset =
        header.sectorOffset(header.firstDirectorySector) + entry.index * 128;
    // CFBF directory entry: start sector is the 4-byte field at offset 116.
    ByteData.sublistView(
      bytes,
    ).setUint32(directoryOffset + 116, 0xfffff000, Endian.little);

    final bounded = BoundedCfbReader(bytes);
    expect(() => bounded.readPath('Big'), throwsA(isA<CfbfException>()));
  });

  test('a FAT sector outside the container is a typed CFBF rejection', () {
    final writer = CfbfWriter()
      ..addStream('Big', Uint8List.fromList(List<int>.filled(5000, 0x42)));
    final bytes = writer.build();
    // Point the first DIFAT entry at a sector far beyond the file. The header
    // DIFAT table starts at byte 76 (109 entries).
    ByteData.sublistView(bytes).setUint32(76, 0x0fffffff, Endian.little);
    expect(() => BoundedCfbReader(bytes), throwsA(isA<FormatException>()));
  });
}
