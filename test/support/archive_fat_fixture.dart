// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Original sparse FAT fixture assembler, independent of the production reader.

import 'dart:convert';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

void fatPut16(Uint8List bytes, int at, int value) =>
    ByteData.sublistView(bytes).setUint16(at, value, Endian.little);
void fatPut32(Uint8List bytes, int at, int value) =>
    ByteData.sublistView(bytes).setUint32(at, value, Endian.little);
int fatGet16(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint16(at, Endian.little);
int fatGet32(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint32(at, Endian.little);

Uint8List fatAlias(String name) {
  if (name == '.' || name == '..') {
    return Uint8List.fromList(ascii.encode(name.padRight(11)));
  }
  final parts = name.split('.');
  assert(parts.length <= 2 && parts.first.length <= 8);
  final extension = parts.length == 2 ? parts[1] : '';
  assert(extension.length <= 3);
  return Uint8List.fromList(
    ascii.encode(
      '${parts.first.toUpperCase().padRight(8)}${extension.toUpperCase().padRight(3)}',
    ),
  );
}

Uint8List fatShortEntry(
  String name, {
  int firstCluster = 0,
  int size = 0,
  bool isDirectory = false,
  int? attributes,
  int ntCase = 0,
  Uint8List? alias,
}) {
  final entry = Uint8List(32);
  entry.setRange(0, 11, alias ?? fatAlias(name));
  entry[11] = attributes ?? (isDirectory ? 0x10 : 0x20);
  entry[12] = ntCase;
  fatPut16(entry, 20, firstCluster ~/ 65536);
  fatPut16(entry, 22, (12 << 11) | (34 << 5) | 28);
  fatPut16(entry, 24, (20 << 9) | (1 << 5) | 1);
  fatPut16(entry, 26, firstCluster % 65536);
  fatPut32(entry, 28, size);
  return entry;
}

List<Uint8List> fatLongEntries(String name, Uint8List alias) {
  final count = (name.length + 12) ~/ 13;
  final units = List<int>.from(name.codeUnits);
  if (units.length % 13 != 0) units.add(0);
  while (units.length < count * 13) {
    units.add(65535);
  }
  var checksum = 0;
  for (final byte in alias.take(11)) {
    checksum = ((((checksum & 1) << 7) | (checksum >> 1)) + byte) & 255;
  }
  final result = <Uint8List>[];
  for (var ordinal = count; ordinal >= 1; ordinal--) {
    final entry = Uint8List(32);
    entry[0] = ordinal + (ordinal == count ? 64 : 0);
    entry[11] = 15;
    entry[13] = checksum;
    final positions = [1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30];
    for (var at = 0; at < 13; at++) {
      fatPut16(entry, positions[at], units[(ordinal - 1) * 13 + at]);
    }
    result.add(entry);
  }
  return result;
}

class FatFixture {
  FatFixture({
    this.bits = 12,
    this.sectorBytes = 512,
    this.sectorsPerCluster = 1,
    int? clusterCount,
    this.fatCount = 2,
    this.mirrored = true,
    this.activeFat = 0,
    this.fileName = 'HELLO.TXT',
    List<int>? fileData,
    List<int>? fileClusters,
    bool includeFile = true,
  }) : clusterCount =
           clusterCount ?? (bits == 12 ? 1000 : (bits == 16 ? 5000 : 65525)),
       payload = Uint8List.fromList(fileData ?? utf8.encode('hello FAT\n')) {
    assert([12, 16, 32].contains(bits));
    final boot = sector(0);
    boot.setRange(0, 3, [0xeb, 0x58, 0x90]);
    boot.setRange(3, 11, ascii.encode('CRISPFAT'));
    fatPut16(boot, 11, sectorBytes);
    boot[13] = sectorsPerCluster;
    fatPut16(boot, 14, reservedSectors);
    boot[16] = fatCount;
    fatPut16(boot, 17, rootEntries);
    if (bits != 32 && totalSectors < 65536) {
      fatPut16(boot, 19, totalSectors);
    } else {
      fatPut32(boot, 32, totalSectors);
    }
    boot[21] = 0xf8;
    fatPut16(boot, 24, 63);
    fatPut16(boot, 26, 255);
    if (bits == 32) {
      fatPut32(boot, 36, fatSectors);
      fatPut16(boot, 40, mirrored ? 0 : 0x80 | activeFat);
      fatPut32(boot, 44, 2);
      fatPut16(boot, 48, 1);
      fatPut16(boot, 50, 6);
      boot[66] = 0x29;
      fatPut32(boot, 67, 0x43524953);
      boot.setRange(71, 82, ascii.encode('CRISP TEST '));
      boot.setRange(82, 90, ascii.encode('FAT32   '));
    } else {
      fatPut16(boot, 22, fatSectors);
      boot[38] = 0x29;
      fatPut32(boot, 39, 0x43524953);
      boot.setRange(43, 54, ascii.encode('CRISP TEST '));
      boot.setRange(54, 62, ascii.encode(bits == 12 ? 'FAT12   ' : 'FAT16   '));
    }
    boot[510] = 0x55;
    boot[511] = 0xaa;
    setFat(0, (fatMask & ~255) | 0xf8);
    setFat(1, fatMask);
    if (bits == 32) {
      final info = sector(1);
      fatPut32(info, 0, 0x41615252);
      fatPut32(info, 484, 0x61417272);
      fatPut32(info, 488, 0xffffffff);
      fatPut32(info, 492, 0xffffffff);
      fatPut32(info, 508, 0xaa550000);
      sector(6).setAll(0, boot);
      sector(7).setAll(0, info);
      setFat(2, fatMask);
    }
    if (includeFile) {
      final needed = (payload.length + clusterBytes - 1) ~/ clusterBytes;
      final clusters =
          fileClusters ??
          List.generate(needed, (i) => i + (bits == 32 ? 3 : 2));
      assert(clusters.length == needed);
      this.fileClusters = List.unmodifiable(clusters);
      fileStartCluster = clusters.isEmpty ? 0 : clusters.first;
      if (clusters.isNotEmpty) writeFile(clusters, payload);
      final alias =
          fileName == fileName.toUpperCase() &&
              RegExp(r'^[A-Z0-9_-]{1,8}(\.[A-Z0-9_-]{1,3})?$')
                  .hasMatch(fileName)
          ? fatAlias(fileName)
          : fatAlias('CRISPF~1.TXT');
      final short = fatShortEntry(
        'HELLO.TXT',
        alias: alias,
        firstCluster: fileStartCluster,
        size: payload.length,
      );
      final shortDisplay =
          ascii.decode(alias.sublist(0, 8)).trimRight() +
          (ascii.decode(alias.sublist(8, 11)).trimRight().isEmpty
              ? ''
              : '.${ascii.decode(alias.sublist(8, 11)).trimRight()}');
      setRoot([
        if (fileName != shortDisplay) ...fatLongEntries(fileName, alias),
        short,
      ]);
    }
  }

  final int bits, sectorBytes, sectorsPerCluster, clusterCount, fatCount;
  final bool mirrored;
  final int activeFat;
  final String fileName;
  final Uint8List payload;
  final sectors = <int, Uint8List>{};
  List<int> fileClusters = const [];
  int fileStartCluster = 0;
  int get clusterBytes => sectorBytes * sectorsPerCluster;
  int get reservedSectors => bits == 32 ? 32 : 1;
  int get rootEntries => bits == 32 ? 0 : 128;
  int get fatSectors =>
      (((clusterCount + 2) * bits + 7) ~/ 8 + sectorBytes - 1) ~/ sectorBytes;
  int get rootSectors => (rootEntries * 32 + sectorBytes - 1) ~/ sectorBytes;
  int get dataSector => reservedSectors + fatCount * fatSectors + rootSectors;
  int get totalSectors => dataSector + clusterCount * sectorsPerCluster;
  int get length => totalSectors * sectorBytes;
  int get fatMask => bits == 12 ? 0xfff : (bits == 16 ? 0xffff : 0x0fffffff);
  int get rootOffset => bits == 32
      ? clusterOffset(2)
      : (reservedSectors + fatCount * fatSectors) * sectorBytes;
  int get rootBytes => bits == 32 ? clusterBytes : rootEntries * 32;
  int get fileOffset =>
      fileStartCluster == 0 ? 0 : clusterOffset(fileStartCluster);
  Uint8List get boot => sector(0);
  Uint8List get fileEntry {
    final position = rootOffset + _rootEntryOffset;
    final within = position % sectorBytes;
    return Uint8List.sublistView(
      sector(position ~/ sectorBytes),
      within,
      within + 32,
    );
  }

  int _rootEntryOffset = 0;

  Uint8List sector(int index) =>
      sectors.putIfAbsent(index, () => Uint8List(sectorBytes));
  int clusterOffset(int cluster) =>
      (dataSector + (cluster - 2) * sectorsPerCluster) * sectorBytes;
  int byteAt(int offset) =>
      sectors[offset ~/ sectorBytes]?[offset % sectorBytes] ?? 0;
  void setByte(int offset, int value) =>
      sector(offset ~/ sectorBytes)[offset % sectorBytes] = value;

  void write(int offset, List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      setByte(offset + i, bytes[i]);
    }
  }

  void setFat(int cluster, int value, {int? table}) {
    for (final copy
        in table == null ? List.generate(fatCount, (i) => i) : [table]) {
      final offset =
          (reservedSectors + copy * fatSectors) * sectorBytes +
          (bits == 12 ? cluster * 3 ~/ 2 : cluster * (bits ~/ 8));
      if (bits == 12) {
        final old = byteAt(offset) | (byteAt(offset + 1) << 8);
        final packed = cluster.isOdd
            ? (old & 15) | ((value & 4095) << 4)
            : (old & 0xf000) | (value & 4095);
        setByte(offset, packed & 255);
        setByte(offset + 1, packed >> 8);
      } else {
        for (var i = 0; i < bits ~/ 8; i++) {
          setByte(offset + i, (value ~/ (1 << (i * 8))) & 255);
        }
      }
    }
  }

  void writeFile(List<int> clusters, List<int> bytes) {
    assert(clusters.length * clusterBytes >= bytes.length);
    for (var i = 0; i < clusters.length; i++) {
      setFat(clusters[i], i + 1 == clusters.length ? fatMask : clusters[i + 1]);
      final start = i * clusterBytes;
      final end = start + clusterBytes < bytes.length
          ? start + clusterBytes
          : bytes.length;
      if (start < end) {
        write(clusterOffset(clusters[i]), bytes.sublist(start, end));
      }
    }
  }

  void setRoot(List<Uint8List> entries) {
    assert(entries.length * 32 <= rootBytes);
    write(rootOffset, Uint8List(rootBytes));
    for (var i = 0; i < entries.length; i++) {
      write(rootOffset + i * 32, entries[i]);
    }
    _rootEntryOffset = entries.isEmpty ? 0 : (entries.length - 1) * 32;
  }

  void setDirectory(
    int cluster,
    List<Uint8List> entries, {
    int parent = 0,
    List<int>? clusters,
  }) {
    final chain = clusters ?? [cluster];
    final content = Uint8List(chain.length * clusterBytes);
    final all = [
      fatShortEntry('.', firstCluster: cluster, isDirectory: true),
      fatShortEntry('..', firstCluster: parent, isDirectory: true),
      ...entries,
    ];
    assert(all.length * 32 <= content.length);
    for (var i = 0; i < all.length; i++) {
      content.setRange(i * 32, i * 32 + 32, all[i]);
    }
    writeFile(chain, content);
  }

  FatFixtureSource source({
    String name = 'fixture.fat',
    bool offsetView = false,
  }) => FatFixtureSource(this, name: name, offsetView: offsetView);
}

class FatFixtureSource implements koni.ByteSource {
  FatFixtureSource(
    this.fixture, {
    this.name = 'fixture.fat',
    this.offsetView = false,
  });
  final FatFixture fixture;
  final bool offsetView;
  @override
  final String name;
  @override
  int get length => fixture.length;
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
    final storage = Uint8List(length + (offsetView ? 14 : 0));
    final bytes = offsetView
        ? Uint8List.sublistView(storage, 7, 7 + length)
        : storage;
    for (var at = 0; at < length;) {
      final position = offset + at;
      final within = position % fixture.sectorBytes;
      final count = length - at < fixture.sectorBytes - within
          ? length - at
          : fixture.sectorBytes - within;
      final sector = fixture.sectors[position ~/ fixture.sectorBytes];
      if (sector != null) bytes.setRange(at, at + count, sector, within);
      at += count;
    }
    return bytes;
  }

  @override
  Future<void> close() async {
    closed = true;
    closeCount++;
  }
}
