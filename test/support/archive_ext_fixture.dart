// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Original synthetic ext2 assembler for malformed-input and boundary controls.

import 'dart:convert';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

void extPut16(Uint8List bytes, int at, int value) =>
    ByteData.sublistView(bytes).setUint16(at, value, Endian.little);
void extPut32(Uint8List bytes, int at, int value) =>
    ByteData.sublistView(bytes).setUint32(at, value, Endian.little);
int extGet16(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint16(at, Endian.little);
int extGet32(Uint8List bytes, int at) =>
    ByteData.sublistView(bytes).getUint32(at, Endian.little);

class ExtFixture {
  ExtFixture({List<int>? payload, String name = 'hello.txt'})
    : payload = Uint8List.fromList(payload ?? utf8.encode('hello ext\n')) {
    const sb = 1024;
    extPut32(bytes, sb, 16);
    extPut32(bytes, sb + 4, 128);
    extPut32(bytes, sb + 20, 1);
    extPut32(bytes, sb + 32, 128);
    extPut32(bytes, sb + 36, 128);
    extPut32(bytes, sb + 40, 16);
    extPut16(bytes, sb + 56, 0xef53);
    extPut16(bytes, sb + 58, 1);
    extPut32(bytes, sb + 76, 1);
    extPut32(bytes, sb + 84, 11);
    extPut16(bytes, sb + 88, 128);
    extPut32(bytes, sb + 96, 2);
    extPut32(bytes, 2048, 3);
    extPut32(bytes, 2052, 4);
    extPut32(bytes, 2056, 5);
    for (var i = 1; i <= 8; i++) {
      allocatedBlock(i);
    }
    inode(2, mode: 0x41ed, size: 1024, block: 7, links: 2);
    inode(12, size: this.payload.length, block: this.payload.isEmpty ? 0 : 8);
    directory(7, [(2, '.', 2), (2, '..', 2), (12, name, 1)]);
    bytes.setRange(8192, 8192 + this.payload.length, this.payload);
  }

  final bytes = Uint8List(128 * 1024);
  final Uint8List payload;
  int inodeOffset(int number) => 5120 + (number - 1) * 128;
  void allocatedBlock(int block, {bool allocated = true}) {
    final bit = block - 1;
    if (allocated) {
      bytes[3072 + bit ~/ 8] |= 1 << (bit % 8);
    } else {
      bytes[3072 + bit ~/ 8] &= ~(1 << (bit % 8));
    }
  }

  void inode(
    int number, {
    int mode = 0x81a4,
    int size = 0,
    int block = 0,
    int links = 1,
    int flags = 0,
  }) {
    final at = inodeOffset(number);
    bytes.fillRange(at, at + 128, 0);
    bytes[4096 + (number - 1) ~/ 8] |= 1 << ((number - 1) % 8);
    extPut16(bytes, at, mode);
    extPut32(bytes, at + 4, size);
    extPut32(bytes, at + 16, 1700000000);
    extPut16(bytes, at + 26, links);
    extPut32(bytes, at + 28, block == 0 ? 0 : 2);
    extPut32(bytes, at + 32, flags);
    extPut32(bytes, at + 40, block);
  }

  void directory(int block, List<(int, String, int)> entries) {
    final start = block * 1024;
    bytes.fillRange(start, start + 1024, 0);
    var cursor = 0;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i], name = utf8.encode(entry.$2);
      final length = i == entries.length - 1
          ? 1024 - cursor
          : ((8 + name.length + 3) ~/ 4) * 4;
      extPut32(bytes, start + cursor, entry.$1);
      extPut16(bytes, start + cursor + 4, length);
      bytes[start + cursor + 6] = name.length;
      bytes[start + cursor + 7] = entry.$3;
      bytes.setRange(
        start + cursor + 8,
        start + cursor + 8 + name.length,
        name,
      );
      cursor += length;
    }
  }

  ExtFixtureSource source({bool borrowedReads = false}) =>
      ExtFixtureSource(bytes, borrowedReads: borrowedReads);
}

class ExtFixtureSource implements koni.ByteSource {
  ExtFixtureSource(this.bytes, {this.borrowedReads = false});
  final Uint8List bytes;
  final bool borrowedReads;
  final reads = <(int, int)>[];
  int closeCount = 0;
  Object? readFailure, closeFailure;
  bool Function(int offset, int length)? failWhen;
  void Function(int offset, int length)? afterRead;
  bool shortRead = false;
  @override
  int get length => bytes.length;
  @override
  String get name => 'synthetic-ext.img';
  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closeCount != 0) throw StateError('Source is closed.');
    reads.add((offset, count));
    if (readFailure != null && (failWhen?.call(offset, count) ?? true)) {
      throw readFailure!;
    }
    if (offset < 0 || count < 0 || offset > length - count) {
      throw RangeError('Synthetic ext source read leaves the image.');
    }
    final result = borrowedReads
        ? Uint8List.sublistView(bytes, offset, offset + count)
        : Uint8List.fromList(bytes.sublist(offset, offset + count));
    afterRead?.call(offset, count);
    if (shortRead && result.isNotEmpty) {
      return Uint8List.sublistView(result, 0, result.length - 1);
    }
    return result;
  }

  @override
  Future<void> close() async {
    closeCount++;
    if (closeFailure != null) throw closeFailure!;
  }
}
