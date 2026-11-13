// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

/// Version 3 stores one mini-stream and one ordinary stream. Version 4 is an
/// independently authored header, data sector, directory sector and FAT sector.
/// The latter has one 4096-byte stream and no mini-stream, so identical high
/// DWORD mutations can test version-sensitive bounds without a huge input.
Uint8List compoundSizeFixture({
  bool version4 = false,
  int highWord = 0,
  bool root = true,
  bool streams = true,
  bool oversizedLowWord = false,
  int? lowWord,
}) {
  final bytes = version4
      ? _version4()
      : (CfbfWriter()
              ..addStream('Small', [1, 2, 3])
              ..addStream('Large', List.generate(4096, (index) => index & 255)))
            .build();
  final data = ByteData.sublistView(bytes);
  final sectorSize = version4 ? 4096 : 512;
  final directory = (data.getUint32(48, Endian.little) + 1) * sectorSize;
  for (var index = 0; index < sectorSize; index += 128) {
    final type = data.getUint8(directory + index + 66);
    if ((root && type == 5) || (streams && type == 2)) {
      data.setUint32(directory + index + 124, highWord, Endian.little);
      if (oversizedLowWord) {
        data.setUint32(
          directory + index + 120,
          bytes.length + 1,
          Endian.little,
        );
      } else if (lowWord != null) {
        data.setUint32(directory + index + 120, lowWord, Endian.little);
      }
    }
  }
  return bytes;
}

Uint8List _version4() {
  const sectorSize = 4096;
  final bytes = Uint8List(4 * sectorSize);
  final data = ByteData.sublistView(bytes);
  void u16(int offset, int value) =>
      data.setUint16(offset, value, Endian.little);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  bytes.setRange(0, cfbfSignature.length, cfbfSignature);
  u16(24, 0x3e);
  u16(26, 4);
  u16(28, 0xfffe);
  u16(30, 12);
  u16(32, 6);
  u32(40, 1); // One directory sector.
  u32(44, 1); // One FAT sector.
  u32(48, 1); // Directory is sector 1.
  u32(56, 4096);
  u32(60, cfbfEndOfChain);
  u32(68, cfbfEndOfChain);
  for (var index = 0; index < 109; index++) {
    u32(76 + 4 * index, index == 0 ? 2 : cfbfFreeSect);
  }
  for (var index = 0; index < sectorSize; index++) {
    bytes[sectorSize + index] = index & 255;
  }
  void entry(int index, String name, int type, int start, int size, int child) {
    final offset = 2 * sectorSize + 128 * index;
    for (var unit = 0; unit < name.length; unit++) {
      u16(offset + 2 * unit, name.codeUnitAt(unit));
    }
    u16(offset + 64, 2 * (name.length + 1));
    bytes[offset + 66] = type;
    bytes[offset + 67] = 1;
    u32(offset + 68, cfbfNoStream);
    u32(offset + 72, cfbfNoStream);
    u32(offset + 76, child);
    u32(offset + 116, start);
    u32(offset + 120, size);
  }

  entry(0, 'Root Entry', 5, cfbfEndOfChain, 0, 1);
  entry(1, 'Large', 2, 0, sectorSize, cfbfNoStream);
  for (var index = 2; index < 32; index++) {
    final offset = 2 * sectorSize + 128 * index;
    for (final field in [68, 72, 76]) {
      u32(offset + field, cfbfNoStream);
    }
  }
  for (var index = 0; index < sectorSize ~/ 4; index++) {
    u32(3 * sectorSize + index * 4, switch (index) {
      0 || 1 => cfbfEndOfChain,
      2 => cfbfFatSect,
      _ => cfbfFreeSect,
    });
  }
  return bytes;
}
