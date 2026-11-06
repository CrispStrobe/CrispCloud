import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:madedit2_hex/hex_document.dart';

void main() {
  test('insert, delete, overwrite, undo and redo are byte accurate', () async {
    final document = HexDocument(MemoryHexByteSource([1, 2, 3, 4]));
    document.insert(2, [9, 8]);
    expect(await document.read(0, 6), [1, 2, 9, 8, 3, 4]);
    document.overwrite(1, [7, 6]);
    expect(await document.read(0, 6), [1, 7, 6, 8, 3, 4]);
    document.delete(3, 2);
    expect(await document.read(0, 4), [1, 7, 6, 4]);
    expect(document.undo(), isTrue);
    expect(await document.read(0, 6), [1, 7, 6, 8, 3, 4]);
    expect(document.redo(), isTrue);
    expect(await document.read(0, 4), [1, 7, 6, 4]);
  });

  test('snapshot remains stable while edits continue', () async {
    final document = HexDocument(MemoryHexByteSource([1, 2, 3]));
    final old = document.snapshot;
    document.overwrite(0, [9]);
    expect(await old.read(0, 3), [1, 2, 3]);
    expect(await document.read(0, 3), [9, 2, 3]);
    document.markSaved(old);
    expect(document.isDirty, isTrue);
  });

  test('insertion at EOF and zero-length source', () async {
    final document = HexDocument(MemoryHexByteSource([]));
    document.insert(0, [1, 2]);
    document.insert(2, [3]);
    expect(await document.read(0, 3), [1, 2, 3]);
    expect(await document.snapshot.chunks().toList(), [
      Uint8List.fromList([1, 2, 3]),
    ]);
  });

  test('rejects invalid ranges and bytes', () {
    final document = HexDocument(MemoryHexByteSource([0]));
    expect(() => document.delete(1, 1), throwsRangeError);
    expect(() => document.insert(0, [256]), throwsRangeError);
  });
}
