import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:madedit2_hex/hex_document.dart';

class _SyntheticSource implements HexByteSource {
  _SyntheticSource(this.length);

  @override
  final int length;
  int reads = 0;

  @override
  Future<Uint8List> read(int offset, int length) async {
    reads++;
    return Uint8List.fromList(
      List.generate(length, (index) => (offset + index) & 255),
    );
  }
}

void main() {
  group('bounded undo storage', () {
    test('defaults to 64 MiB and rejects a negative budget', () {
      final source = MemoryHexByteSource([]);
      expect(HexDocument(source).maxUndoBytes, 64 * 1024 * 1024);
      expect(() => HexDocument(source, maxUndoBytes: -1), throwsArgumentError);
    });

    test(
      'shared buffers and split ranges count their allocation once',
      () async {
        final doc = HexDocument(MemoryHexByteSource([]), maxUndoBytes: 8);
        doc.insert(0, List.generate(8, (index) => index));
        expect(
          doc.historyBytes,
          0,
        ); // The original empty state is the only undo.
        doc.delete(2, 3);
        expect(doc.historyBytes, 8);
        doc.delete(1, 1);
        expect(doc.historyBytes, 8);
        expect(await doc.read(0, doc.length), [0, 5, 6, 7]);
        expect(doc.undo(), isTrue);
        expect(doc.historyBytes, 8);
        expect(await doc.read(0, doc.length), [0, 1, 5, 6, 7]);
        expect(doc.undo(), isTrue);
        expect(doc.historyBytes, 8);
        expect(
          await doc.read(0, doc.length),
          List.generate(8, (index) => index),
        );
        expect(doc.redo(), isTrue);
        expect(doc.historyBytes, 8);
        expect(await doc.read(0, doc.length), [0, 1, 5, 6, 7]);
      },
    );

    test(
      'evicts oldest history without changing current or saved snapshots',
      () async {
        final doc = HexDocument(
          MemoryHexByteSource([0, 0, 0, 0]),
          maxUndoBytes: 8,
        );
        doc.overwrite(0, [1, 1, 1, 1]);
        final saved = doc.snapshot;
        doc.markSaved(saved);
        doc.overwrite(0, [2, 2, 2, 2]);
        doc.overwrite(0, [3, 3, 3, 3]);
        doc.overwrite(0, [4, 4, 4, 4]);
        expect(doc.historyBytes, 8);
        expect(doc.isDirty, isTrue);
        expect(await doc.read(0, 4), [4, 4, 4, 4]);
        expect(await saved.read(0, 4), [1, 1, 1, 1]);
        expect(doc.undo(), isTrue);
        expect(await doc.read(0, 4), [3, 3, 3, 3]);
        expect(doc.historyBytes, 8);
        expect(doc.undo(), isTrue);
        expect(await doc.read(0, 4), [2, 2, 2, 2]);
        expect(doc.historyBytes, 8);
        expect(doc.undo(), isFalse);
        expect(doc.redo(), isTrue);
        expect(doc.redo(), isTrue);
        expect(await doc.read(0, 4), [4, 4, 4, 4]);
        expect(doc.undo(), isTrue);
        doc.overwrite(0, [5, 5, 5, 5]);
        expect(doc.canRedo, isFalse);
        expect(doc.historyBytes, 8);
        expect(await doc.read(0, 4), [5, 5, 5, 5]);
        expect(await saved.read(0, 4), [1, 1, 1, 1]);
      },
    );

    test(
      'zero budget allows original ranges but releases added-byte redo',
      () async {
        final doc = HexDocument(MemoryHexByteSource([1, 2]), maxUndoBytes: 0);
        doc.overwrite(0, [3]);
        final edited = doc.snapshot;
        expect(doc.canUndo, isTrue);
        expect(doc.undo(), isTrue);
        expect(doc.canRedo, isFalse);
        expect(doc.historyBytes, 0);
        expect(doc.isDirty, isFalse);
        expect(await doc.read(0, 2), [1, 2]);
        expect(await edited.read(0, 2), [3, 2]);
        doc.delete(0, 1);
        expect(doc.undo(), isTrue);
        expect(doc.redo(), isTrue);
        expect(doc.historyBytes, 0);
        expect(await doc.read(0, 1), [2]);
      },
    );

    test('multi-terabyte original ranges need no reads or byte budget', () {
      final source = _SyntheticSource(0x40000000000);
      final doc = HexDocument(source, maxUndoBytes: 0);
      doc.delete(100, 0x100000000);
      expect(doc.historyBytes, 0);
      expect(doc.undo(), isTrue);
      expect(doc.length, source.length);
      expect(doc.redo(), isTrue);
      expect(doc.length, source.length - 0x100000000);
      expect(doc.historyBytes, 0);
      expect(source.reads, 0);
    });

    test(
      'nibble coalescing and saved revisions retain the byte limit',
      () async {
        final doc = HexDocument(MemoryHexByteSource([0]), maxUndoBytes: 1);
        doc.overwrite(0, [0x10]);
        doc.replace(0, 1, [0x11], coalesce: true);
        expect(doc.historyBytes, 0);
        expect(doc.undo(), isTrue);
        expect(doc.historyBytes, 1);
        expect(await doc.read(0, 1), [0]);
        expect(doc.redo(), isTrue);
        expect(doc.historyBytes, 0);
        final saved = doc.snapshot;
        doc.markSaved(saved);
        doc.replace(0, 1, [0x12], coalesce: true);
        doc.replace(0, 1, [0x13], coalesce: true);
        expect(doc.historyBytes, 1);
        expect(doc.undo(), isTrue);
        expect(doc.historyBytes, 1);
        expect(await doc.read(0, 1), [0x11]);
        expect(doc.isDirty, isFalse);
        expect(doc.redo(), isTrue);
        expect(doc.historyBytes, 1);
        expect(await doc.read(0, 1), [0x13]);
        expect(doc.isDirty, isTrue);
        expect(await saved.read(0, 1), [0x11]);
      },
    );
  });
}
