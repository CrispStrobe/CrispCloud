import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;

/// Small independently constructed ECMA-119 image: primary descriptor, path
/// tables, root/subdirectory records, two files and an empty directory. This
/// fixture encoder does not call the production ISO reader.
class IsoFixture {
  IsoFixture({
    this.fileName = 'HELLO.TXT;1',
    String? jolietName,
    String? rockRidgeName,
    bool rockRidgeContinuation = false,
    bool symbolicLink = false,
  }) {
    const volumeSectors = 40;
    bytes = Uint8List(volumeSectors * sectorSize);
    _descriptor(16, 1, rootSector, 20, 21);
    if (jolietName != null) {
      _descriptor(17, 2, jolietRootSector, 22, 23);
    }
    final terminator = (jolietName == null ? 17 : 18) * sectorSize;
    bytes[terminator] = 255;
    bytes.setRange(terminator + 1, terminator + 6, ascii.encode('CD001'));
    bytes[terminator + 6] = 1;
    _pathTable(20, false, rootSector, childSector, ascii.encode('DOCS'));
    _pathTable(21, true, rootSector, childSector, ascii.encode('DOCS'));
    final rock = rockRidgeName != null || symbolicLink;
    _rockRidge = rock;
    final rootSelf = _record(
      [0],
      rootSector,
      sectorSize,
      directory: true,
      systemUse: rock
          ? [
              0x53,
              0x50,
              7,
              1,
              0xbe,
              0xef,
              0,
              0x45,
              0x52,
              18,
              1,
              10,
              0,
              0,
              1,
              ...ascii.encode('RRIP_1991A'),
              ..._px(0x41ed),
            ]
          : const [],
    );
    final prefix = <int>[
      ...rootSelf,
      ..._record([1], rootSector, sectorSize, directory: true),
    ];
    fileRecordOffset = rootSector * sectorSize + prefix.length;
    final extensions = <int>[];
    if (rockRidgeName != null) {
      final name = _nm(rockRidgeName);
      if (rockRidgeContinuation) {
        final continuation = Uint8List(28);
        continuation.setAll(0, [0x43, 0x45, 28, 1]);
        isoBoth32(continuation, 4, continuationSector);
        isoBoth32(continuation, 12, 0);
        isoBoth32(continuation, 20, name.length);
        bytes.setAll(continuationSector * sectorSize, name);
        extensions.addAll(continuation);
      } else {
        extensions.addAll(name);
      }
    }
    if (rock) {
      final px = Uint8List(44)..setAll(0, [0x50, 0x58, 44, 1]);
      isoBoth32(px, 4, symbolicLink ? 0xa1ff : 0x81a4);
      isoBoth32(px, 12, 1);
      isoBoth32(px, 20, 1000);
      isoBoth32(px, 28, 1000);
      isoBoth32(px, 36, 2);
      extensions.addAll(px);
    }
    if (symbolicLink) extensions.addAll([0x53, 0x4c, 7, 1, 0, 8, 0]);
    final file = _record(
      ascii.encode(fileName),
      fileSector,
      9,
      systemUse: extensions,
    );
    directoryRecordOffset = fileRecordOffset + file.length;
    _putDirectory(rootSector, [
      ...prefix,
      ...file,
      ..._record(
        ascii.encode('DOCS'),
        childSector,
        sectorSize,
        directory: true,
      ),
      ..._record(
        ascii.encode('EMPTY'),
        emptySector,
        sectorSize,
        directory: true,
      ),
    ]);
    _putDirectory(childSector, [
      ..._record([0], childSector, sectorSize, directory: true),
      ..._record([1], rootSector, sectorSize, directory: true),
      ..._record(ascii.encode('NOTE.TXT;1'), nestedFileSector, 10),
    ]);
    _putDirectory(emptySector, [
      ..._record([0], emptySector, sectorSize, directory: true),
      ..._record([1], rootSector, sectorSize, directory: true),
    ]);
    bytes.setAll(fileSector * sectorSize, utf8.encode('hello iso'));
    bytes.setAll(nestedFileSector * sectorSize, utf8.encode('nested iso'));
    if (jolietName != null) {
      _pathTable(22, false, jolietRootSector, jolietChildSector, _ucs2('文書'));
      _pathTable(23, true, jolietRootSector, jolietChildSector, _ucs2('文書'));
      final first = [
        ..._record([0], jolietRootSector, sectorSize, directory: true),
        ..._record([1], jolietRootSector, sectorSize, directory: true),
      ];
      jolietFileRecordOffset = jolietRootSector * sectorSize + first.length;
      _putDirectory(jolietRootSector, [
        ...first,
        ..._record(_ucs2('$jolietName;1'), fileSector, 9),
        ..._record(_ucs2('文書'), jolietChildSector, sectorSize, directory: true),
      ]);
      _putDirectory(jolietChildSector, [
        ..._record([0], jolietChildSector, sectorSize, directory: true),
        ..._record([1], jolietRootSector, sectorSize, directory: true),
        ..._record(_ucs2('日本語.txt;1'), nestedFileSector, 10),
      ]);
    }
  }

  static const sectorSize = 2048;
  static const rootSector = 24;
  static const childSector = 25;
  static const fileSector = 34;
  static const nestedFileSector = 35;
  static const emptySector = 28;
  static const continuationSector = 29;
  static const jolietRootSector = 30;
  static const jolietChildSector = 31;
  final String fileName;
  late final Uint8List bytes;
  late final int fileRecordOffset;
  late final int directoryRecordOffset;
  int? jolietFileRecordOffset;
  bool _rockRidge = false;

  void _descriptor(
    int sector,
    int type,
    int root,
    int littlePath,
    int bigPath,
  ) {
    final at = sector * sectorSize;
    bytes[at] = type;
    bytes.setAll(at + 1, ascii.encode('CD001'));
    bytes[at + 6] = 1;
    bytes.fillRange(at + 8, at + 72, 0x20);
    isoBoth32(bytes, at + 80, bytes.length ~/ sectorSize);
    if (type == 2) bytes.setAll(at + 88, [0x25, 0x2f, 0x45]);
    isoBoth16(bytes, at + 120, 1);
    isoBoth16(bytes, at + 124, 1);
    isoBoth16(bytes, at + 128, sectorSize);
    isoBoth32(bytes, at + 132, type == 2 ? 22 : 36);
    final data = ByteData.sublistView(bytes);
    data.setUint32(at + 140, littlePath, Endian.little);
    data.setUint32(at + 148, bigPath, Endian.big);
    bytes.setAll(at + 156, _record([0], root, sectorSize, directory: true));
    bytes[at + 881] = 1;
  }

  void _pathTable(
    int sector,
    bool bigEndian,
    int root,
    int child,
    List<int> name,
  ) {
    final endian = bigEndian ? Endian.big : Endian.little;
    final primary = root == rootSector;
    final childEnd = 10 + 8 + name.length + name.length % 2;
    final path = Uint8List(childEnd + (primary ? 14 : 0));
    final data = ByteData.sublistView(path);
    path[0] = 1;
    data.setUint32(2, root, endian);
    data.setUint16(6, 1, endian);
    path[10] = name.length;
    data.setUint32(12, child, endian);
    data.setUint16(16, 1, endian);
    path.setAll(18, name);
    if (primary) {
      path[childEnd] = 5;
      data.setUint32(childEnd + 2, emptySector, endian);
      data.setUint16(childEnd + 6, 1, endian);
      path.setAll(childEnd + 8, ascii.encode('EMPTY'));
    }
    bytes.setAll(sector * sectorSize, path);
  }

  void _putDirectory(int sector, List<int> content) =>
      bytes.setAll(sector * sectorSize, content);

  Uint8List _record(
    List<int> name,
    int extent,
    int size, {
    bool directory = false,
    List<int> systemUse = const [],
  }) {
    if (_rockRidge && systemUse.isEmpty) {
      systemUse = _px(directory ? 0x41ed : 0x81a4);
    }
    final baseLength = 33 + name.length + (name.length.isEven ? 1 : 0);
    final length = baseLength + systemUse.length;
    final bytes = Uint8List(length + length % 2);
    bytes[0] = bytes.length;
    isoBoth32(bytes, 2, extent);
    isoBoth32(bytes, 10, size);
    bytes.setAll(18, [126, 11, 12, 10, 15, 30, 4]);
    bytes[25] = directory ? 2 : 0;
    isoBoth16(bytes, 28, 1);
    bytes[32] = name.length;
    bytes.setAll(33, name);
    bytes.setAll(baseLength, systemUse);
    return bytes;
  }

  static Uint8List _px(int mode) {
    final px = Uint8List(44)..setAll(0, [0x50, 0x58, 44, 1]);
    isoBoth32(px, 4, mode);
    isoBoth32(px, 12, 1);
    isoBoth32(px, 20, 1000);
    isoBoth32(px, 28, 1000);
    return px;
  }

  static List<int> _nm(String text) {
    final encoded = utf8.encode(text);
    return [0x4e, 0x4d, 5 + encoded.length, 1, 0, ...encoded];
  }

  static List<int> _ucs2(String text) => [
    for (final code in text.codeUnits) ...[code >> 8, code & 255],
  ];
}

void isoBoth16(Uint8List bytes, int at, int value) {
  final data = ByteData.sublistView(bytes);
  data.setUint16(at, value, Endian.little);
  data.setUint16(at + 2, value, Endian.big);
}

void isoBoth32(Uint8List bytes, int at, int value) {
  final data = ByteData.sublistView(bytes);
  data.setUint32(at, value, Endian.little);
  data.setUint32(at + 4, value, Endian.big);
}

/// Independently produced by libarchive 3.7.4's ISO writer (Joliet and Rock Ridge
/// enabled). Contains hello.txt, folder/日本語.txt and a 179-character name that
/// requires a Rock Ridge CE continuation. Zlib stores the sparse 382976-byte
/// image compactly in source. Original SHA-256:
/// 7d256df92fd7ecb38be1d7051b6918d62b17ffd87c9497a042aa22aa3fce1df3.
Uint8List independentLibarchiveIso() => const ar.ZLibDecoder().decodeBytes(
  base64.decode(_libarchiveIso),
  verify: true,
  maxOutputSize: 382976,
);

const _libarchiveIso =
    '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';
