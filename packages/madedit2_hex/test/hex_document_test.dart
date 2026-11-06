import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:madedit2_hex/src/core/hex_byte_source.dart';
import 'package:madedit2_hex/src/core/hex_document.dart';

void main() {
  group('raw byte editing', () {
    test(
      'preserves arbitrary binary bytes and owns inserted buffers',
      () async {
        final original = Uint8List.fromList([0, 255, 128, 10, 13, 254, 1]);
        final doc = HexDocument(MemoryHexByteSource(original));
        original.fillRange(0, original.length, 42);
        expect(await doc.read(0, doc.length), [0, 255, 128, 10, 13, 254, 1]);

        final inserted = Uint8List.fromList([0, 255, 129]);
        doc.insert(2, inserted);
        inserted.fillRange(0, inserted.length, 33);
        doc.overwrite(5, [240, 0]);
        doc.delete(7, 1);
        expect(await doc.read(0, doc.length), [
          0,
          255,
          0,
          255,
          129,
          240,
          0,
          254,
          1,
        ]);

        final returned = await doc.read(0, 3);
        returned.fillRange(0, returned.length, 77);
        expect(await doc.read(0, 3), [0, 255, 0]);
        expect(doc.debugValidate(), isNull);
        await doc.close();
      },
    );

    test('cross-piece reads clip at EOF and never decode bytes', () async {
      final doc = HexDocument(
        MemoryHexByteSource(Uint8List.fromList(List.generate(10, (i) => i))),
      );
      doc.replace(3, 2, [255, 0, 128]);
      doc.insert(0, [254]);
      doc.delete(8, 1);
      expect(await doc.read(2, 7), [1, 2, 255, 0, 128, 5, 7]);
      expect(await doc.read(doc.length - 2, 50), [8, 9]);
      expect(await doc.read(doc.length, 5), isEmpty);
      expect(await doc.read(0, 0), isEmpty);
      expect(doc.debugValidate(), isNull);
      await doc.close();
    });

    test('invalid edits fail before changing the document', () async {
      final doc = HexDocument(
        MemoryHexByteSource(Uint8List.fromList([1, 2, 3])),
      );
      final invalid = <void Function()>[
        () => doc.insert(-1, [4]),
        () => doc.insert(4, [4]),
        () => doc.delete(0, -1),
        () => doc.delete(2, 2),
        () => doc.overwrite(3, [4]),
        () => doc.replace(0, 1, [4, 256]),
        () => doc.replace(0, 1, [-1]),
      ];
      for (final edit in invalid) {
        expect(edit, throwsRangeError);
        expect(doc.revision, 0);
        expect(await doc.read(0, 3), [1, 2, 3]);
        expect(doc.debugValidate(), isNull);
      }
      doc.replace(3, 0, const []);
      expect(doc.revision, 0);
      expect(doc.canUndo, isFalse);
      await expectLater(doc.read(-1, 1), throwsRangeError);
      await expectLater(doc.read(4, 0), throwsRangeError);
      await expectLater(doc.read(0, -1), throwsRangeError);
      await doc.close();
    });

    test(
      'edits a multi-terabyte synthetic source without any source reads',
      () async {
        const originalLength = 1 << 42;
        var reads = 0;
        final doc = HexDocument(
          CallbackHexByteSource(
            length: originalLength,
            read: (offset, length) async {
              reads++;
              return Uint8List.fromList(
                List.generate(length, (index) => (offset + index) & 255),
              );
            },
          ),
          maxUndoBytes: 8,
        );
        doc.overwrite(originalLength - 2, [0, 255]);
        doc.insert(123, [128, 0, 255]);
        doc.delete(1000, 1 << 32);
        final snapshot = doc.snapshot();
        expect(doc.length, originalLength + 3 - (1 << 32));
        expect(reads, 0);
        expect(doc.historyBytes, 5);
        expect(await doc.read(123, 3), [128, 0, 255]);
        expect(reads, 0);
        expect(doc.undo(), isTrue);
        expect(doc.redo(), isTrue);
        expect(doc.undo(), isTrue);
        expect(doc.undo(), isTrue);
        expect(doc.undo(), isTrue);
        expect(doc.length, originalLength);
        expect(doc.isDirty, isFalse);
        expect(reads, 0);
        expect(await doc.read(0, 16), List.generate(16, (i) => i));
        expect(reads, 1);
        expect(doc.debugValidate(), isNull);
        await snapshot.close();
        await doc.close();
      },
    );

    test(
      'randomized edits and history agree with a plain-list model',
      () async {
        final random = Random(0xC125C10D);
        var expected = List<int>.generate(80, (_) => random.nextInt(256));
        final doc = HexDocument(
          MemoryHexByteSource(Uint8List.fromList(expected)),
          maxUndoSteps: 10000,
          maxUndoBytes: 16 << 20,
        );
        final past = <List<int>>[];
        final future = <List<int>>[];
        final snapshots = <(HexSnapshot, List<int>)>[];
        for (var step = 0; step < 1600; step++) {
          final operation = random.nextInt(10);
          if (operation < 7) {
            final offset = random.nextInt(expected.length + 1);
            final available = expected.length - offset;
            final remove = random.nextInt(min(available, 18) + 1);
            final bytes = List<int>.generate(
              random.nextInt(13),
              (_) => random.nextInt(256),
            );
            if (remove != 0 || bytes.isNotEmpty) {
              past.add(List<int>.from(expected));
              future.clear();
            }
            expected.replaceRange(offset, offset + remove, bytes);
            doc.replace(offset, remove, bytes);
          } else if (operation == 7) {
            final possible = past.isNotEmpty;
            expect(doc.undo(), possible, reason: 'undo at step $step');
            if (possible) {
              future.add(expected);
              expected = past.removeLast();
            }
          } else if (operation == 8) {
            final possible = future.isNotEmpty;
            expect(doc.redo(), possible, reason: 'redo at step $step');
            if (possible) {
              past.add(expected);
              expected = future.removeLast();
            }
          } else {
            final offset = random.nextInt(expected.length + 1);
            final count = random.nextInt(expected.length + 10);
            expect(
              await doc.read(offset, count),
              expected.sublist(offset, min(offset + count, expected.length)),
              reason: 'range at step $step',
            );
          }
          if (step % 317 == 0) {
            snapshots.add((doc.snapshot(), List<int>.from(expected)));
          }
          expect(doc.length, expected.length, reason: 'length at step $step');
          expect(doc.debugValidate(), isNull, reason: 'tree at step $step');
          expect(
            await doc.read(0, doc.length + 10),
            expected,
            reason: 'bytes at step $step',
          );
        }
        for (final (snapshot, bytes) in snapshots) {
          expect(await snapshot.read(0, snapshot.length), bytes);
          await snapshot.close();
        }
        await doc.close();
      },
    );
  });

  group('undo and saved state', () {
    test(
      'overwrite is one step and undo/redo recognize the saved state',
      () async {
        final doc = HexDocument(
          MemoryHexByteSource(Uint8List.fromList([1, 2, 3])),
        );
        doc.overwrite(1, [255, 128]);
        expect(doc.undoSteps, 1);
        expect(doc.isDirty, isTrue);
        doc.markSaved();
        expect(doc.isDirty, isFalse);
        doc.insert(0, [0]);
        expect(doc.isDirty, isTrue);
        expect(doc.undo(), isTrue);
        expect(doc.isDirty, isFalse);
        expect(doc.undo(), isTrue);
        expect(doc.isDirty, isTrue);
        expect(await doc.read(0, doc.length), [1, 2, 3]);
        expect(doc.redo(), isTrue);
        expect(doc.isDirty, isFalse);
        expect(await doc.read(0, doc.length), [1, 255, 128]);
        expect(doc.revision, 5);
        await doc.close();
      },
    );

    test('saving a snapshot never clears edits made during the save', () async {
      final doc = HexDocument(MemoryHexByteSource(Uint8List.fromList([1])));
      doc.insert(1, [2]);
      final snapshot = doc.snapshot();
      final secondOwner = doc.snapshot();
      await secondOwner.close();
      doc.insert(2, [3]);
      doc.markSaved(snapshot.revision);
      expect(doc.isDirty, isTrue);
      expect(await snapshot.read(0, snapshot.length), [1, 2]);
      doc.undo();
      expect(doc.isDirty, isFalse);
      doc.redo();
      expect(doc.isDirty, isTrue);
      await snapshot.close();
      expect(() => doc.markSaved(snapshot.revision), throwsArgumentError);
      await doc.close();
    });

    test(
      'step and byte budgets discard oldest history without losing content',
      () async {
        final doc = HexDocument(
          MemoryHexByteSource(Uint8List(0)),
          maxUndoSteps: 2,
          maxUndoBytes: 4,
        );
        doc.insert(0, [1, 2]);
        doc.insert(2, [3, 4]);
        final snapshot = doc.snapshot();
        doc.insert(4, [5, 6]);
        expect(doc.undoSteps, 2);
        expect(doc.historyBytes, 4);
        expect(doc.undo(), isTrue);
        expect(doc.undo(), isTrue);
        expect(doc.undo(), isFalse);
        expect(await doc.read(0, doc.length), [1, 2]);
        expect(await snapshot.read(0, snapshot.length), [1, 2, 3, 4]);
        doc.insert(0, [9]);
        expect(doc.canRedo, isFalse);
        expect(await doc.read(0, doc.length), [9, 1, 2]);
        doc.clearHistory();
        expect(doc.historyBytes, 0);
        expect(doc.historyPieces, 0);
        expect(doc.canUndo, isFalse);
        expect(doc.isDirty, isTrue);
        await snapshot.close();
        await doc.close();
      },
    );

    test('history counts shared chunks once and can be disabled', () async {
      final doc = HexDocument(
        MemoryHexByteSource(Uint8List(0)),
        maxUndoBytes: 8,
      );
      doc.insert(0, List.generate(8, (i) => i));
      doc.delete(2, 3);
      expect(doc.historyBytes, 8);
      expect(doc.undoSteps, 2);
      doc.undo();
      expect(doc.historyBytes, 8);
      await doc.close();

      final withoutHistory = HexDocument(
        MemoryHexByteSource(Uint8List(0)),
        maxUndoSteps: 0,
      );
      withoutHistory.insert(0, [0, 255]);
      expect(withoutHistory.canUndo, isFalse);
      expect(withoutHistory.historyBytes, 0);
      expect(withoutHistory.isDirty, isTrue);
      expect(await withoutHistory.read(0, 2), [0, 255]);
      await withoutHistory.close();
    });

    test(
      'piece budget bounds metadata even for original-source history',
      () async {
        final doc = HexDocument(
          MemoryHexByteSource(Uint8List.fromList([0, 1, 2, 3, 4, 5])),
          maxUndoPieces: 2,
        );
        doc.delete(1, 1);
        doc.delete(2, 1);
        doc.delete(0, 1);
        expect(doc.undoSteps, 2);
        expect(doc.historyPieces, 2);
        expect(doc.historyBytes, 0);
        doc.undo();
        doc.undo();
        expect(doc.undo(), isFalse);
        expect(await doc.read(0, doc.length), [0, 2, 3, 4, 5]);
        await doc.close();
      },
    );
  });

  group('snapshot and I/O concurrency', () {
    test(
      'subscribing retains a snapshot before asynchronous delivery',
      () async {
        var closes = 0;
        final doc = HexDocument(
          CallbackHexByteSource(
            length: 8,
            read: (offset, length) async => Uint8List.fromList(
              List.generate(length, (index) => offset + index),
            ),
            close: () => closes++,
          ),
        );
        final snapshot = doc.snapshot();
        final output = snapshot.stream(chunkSize: 3).toList();
        final closingSnapshot = snapshot.close();
        final closingDocument = doc.close();
        expect(await output, [
          [0, 1, 2],
          [3, 4, 5],
          [6, 7],
        ]);
        await Future.wait([closingSnapshot, closingDocument]);
        expect(closes, 1);
      },
    );

    test(
      'canceling before the first chunk releases the stream lease',
      () async {
        var closes = 0;
        var reads = 0;
        final doc = HexDocument(
          CallbackHexByteSource(
            length: 8,
            read: (offset, length) async {
              reads++;
              return Uint8List(length);
            },
            close: () => closes++,
          ),
        );
        final snapshot = doc.snapshot();
        final subscription = snapshot.stream().listen((_) {});
        final cancellation = subscription.cancel();
        await snapshot.close();
        await doc.close();
        await cancellation;
        expect(reads, 0);
        expect(closes, 1);
      },
    );

    test('an in-flight document read sees a single revision', () async {
      final start = Completer<void>();
      final release = Completer<void>();
      final bytes = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      final doc = HexDocument(
        CallbackHexByteSource(
          length: bytes.length,
          read: (offset, length) async {
            if (!start.isCompleted) start.complete();
            await release.future;
            return bytes.sublist(offset, offset + length);
          },
        ),
      );
      final before = doc.read(0, 6);
      await start.future;
      doc.replace(0, 6, [255, 128]);
      release.complete();
      expect(await before, [0, 1, 2, 3, 4, 5]);
      expect(await doc.read(0, 6), [255, 128]);
      await doc.close();
    });

    test(
      'streaming a snapshot survives concurrent edits and snapshot close',
      () async {
        final bytes = List<int>.generate(173, (i) => i);
        final doc = HexDocument(MemoryHexByteSource(Uint8List.fromList(bytes)));
        doc.insert(20, [255, 0, 128]);
        final expected = [
          ...bytes.sublist(0, 20),
          255,
          0,
          128,
          ...bytes.sublist(20),
        ];
        final snapshot = doc.snapshot();
        final output = <int>[];
        await for (final chunk in snapshot.stream(chunkSize: 17)) {
          if (output.isEmpty) {
            doc.replace(0, doc.length, [3, 2, 1]);
            doc.clearHistory();
            await snapshot.close();
          }
          expect(chunk.length, lessThanOrEqualTo(17));
          output.addAll(chunk);
        }
        expect(output, expected);
        expect(await doc.read(0, doc.length), [3, 2, 1]);
        await doc.close();
      },
    );

    test(
      'close waits for in-flight owners without invalidating them',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        var closes = 0;
        final doc = HexDocument(
          CallbackHexByteSource(
            length: 10,
            read: (offset, length) async {
              started.complete();
              await release.future;
              return Uint8List.fromList(
                List.generate(length, (i) => offset + i),
              );
            },
            close: () => closes++,
          ),
        );
        final snapshot = doc.snapshot();
        final read = snapshot.read(3, 4);
        await started.future;
        await doc.close();
        await snapshot.close();
        expect(closes, 0);
        release.complete();
        expect(await read, [3, 4, 5, 6]);
        expect(closes, 1);
        await doc.close();
        await snapshot.close();
        expect(closes, 1);
        expect(() => doc.insert(0, [1]), throwsStateError);
        await expectLater(doc.read(0, 1), throwsStateError);
        await expectLater(snapshot.read(0, 1), throwsStateError);
      },
    );

    test('canceling a snapshot stream releases its source lease', () async {
      var closes = 0;
      final doc = HexDocument(
        CallbackHexByteSource(
          length: 100,
          read: (offset, length) async => Uint8List(length),
          close: () => closes++,
        ),
      );
      final snapshot = doc.snapshot();
      final iterator = StreamIterator(snapshot.stream(chunkSize: 4));
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, [0, 0, 0, 0]);
      await doc.close();
      await snapshot.close();
      expect(closes, 0);
      await iterator.cancel();
      expect(closes, 1);
    });

    test(
      'source partial reads are completed and parallel requests serialized',
      () async {
        var active = 0;
        var maxActive = 0;
        var calls = 0;
        final doc = HexDocument(
          CallbackHexByteSource(
            length: 30,
            read: (offset, length) async {
              calls++;
              active++;
              maxActive = max(maxActive, active);
              await Future<void>.delayed(Duration.zero);
              final result = Uint8List.fromList(
                List.generate(min(3, length), (i) => offset + i),
              );
              active--;
              return result;
            },
          ),
        );
        final results = await Future.wait([doc.read(2, 10), doc.read(20, 6)]);
        expect(results[0], List.generate(10, (i) => i + 2));
        expect(results[1], List.generate(6, (i) => i + 20));
        expect(calls, 6);
        expect(maxActive, 1);
        await doc.close();
      },
    );

    test(
      'unexpected source EOF fails clearly without poisoning later reads',
      () async {
        var closes = 0;
        final doc = HexDocument(
          CallbackHexByteSource(
            length: 8,
            read: (offset, length) async => offset >= 5
                ? Uint8List(0)
                : Uint8List.fromList(
                    List.generate(min(length, 5 - offset), (i) => i + offset),
                  ),
            close: () => closes++,
          ),
        );
        await expectLater(doc.read(0, 8), throwsStateError);
        expect(await doc.read(0, 3), [0, 1, 2]);
        expect(doc.revision, 0);
        await doc.close();
        expect(closes, 1);
      },
    );
  });
}
