import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_comparison_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

import 'support/workflow_fake_client.dart';

class _ObservedLocal extends LocalOperationBackend {
  _ObservedLocal() : super(LocalFileService(), isCurrent: () => true);
  int wholeReads = 0;
  final rangeOffsets = <int>[];
  @override
  Stream<List<int>> readFile(FileItem file) {
    wholeReads++;
    return super.readFile(file);
  }

  @override
  Stream<List<int>> readRange(FileItem file, int offset) {
    rangeOffsets.add(offset);
    return super.readRange(file, offset);
  }
}

void main() {
  test(
    'cloud navigation bounds a fallback range stream and closes at EOF',
    () async {
      final cloud = WorkflowFakeClient()
        ..put('/left', [1, 2, 3, 4, 5, 6, 7, 8, 9])
        ..put('/right', [1, 99, 3, 4, 77, 66, 7, 8, 9, 0]);
      final backend = CloudOperationBackend(cloud, isCurrent: () => true);
      final session = await BinaryComparisonSession.open(
        backend,
        (await backend.stat('/left'))!,
        backend,
        (await backend.stat('/right'))!,
      );
      final window = await session
          .window(0)
          .timeout(const Duration(seconds: 2));
      expect(window.left.length, 9);
      expect(window.right.length, 10);
      expect((await session.difference(1)).start, 4);
    },
  );
  test(
    'contiguous binary ranges survive chunk boundaries and unmatched tails',
    () async {
      final comparison = await compareBinaryStreams(
        Stream.fromIterable([
          [0, 1],
          [],
          [2, 3, 4, 5],
          [6, 7],
        ]),
        Stream.fromIterable([
          [0],
          [8, 9, 3],
          [4, 8, 8, 7, 9, 9],
        ]),
      );
      expect(comparison.rangeCount, 3);
      expect(comparison.differingBytes, 6);
      expect(comparison.ranges.map((r) => [r.index, r.start, r.end]), [
        [0, 1, 3],
        [1, 5, 7],
        [2, 8, 10],
      ]);
    },
  );

  test(
    'a sparse index navigates every range without retaining every difference',
    () async {
      final directory = await Directory.systemTemp.createTemp('binary-index-');
      addTearDown(() => directory.delete(recursive: true));
      final left = File('${directory.path}/left.bin');
      final right = File('${directory.path}/right.bin');
      await left.writeAsBytes(Uint8List(40000));
      await right.writeAsBytes(
        Uint8List.fromList(List.generate(40000, (i) => i.isEven ? 1 : 0)),
      );
      final a = _ObservedLocal(), b = _ObservedLocal();
      final session = await BinaryComparisonSession.open(
        a,
        (await a.stat(left.path))!,
        b,
        (await b.stat(right.path))!,
        maxIndexedRanges: 8,
      );
      expect(session.result.rangeCount, 20000);
      expect(session.result.ranges.length, lessThanOrEqualTo(9));
      for (final index in [0, 1, 77, 12345, 12346, 19999, 10000]) {
        final range = await session.difference(index);
        expect(
          [range.index, range.start, range.end],
          [index, index * 2, index * 2 + 1],
        );
      }
      final page = await session.window(24688, length: 64);
      expect(page.left.length, 64);
      expect(page.right.length, 64);
      expect(page.right[2], 1);
      expect(a.wholeReads, 1);
      expect(b.wholeReads, 1);
      expect(a.rangeOffsets.any((offset) => offset > 0), isTrue);
      expect(b.rangeOffsets.any((offset) => offset > 0), isTrue);
    },
  );

  test(
    'large sparse files expose differences beyond the editable text limit',
    () async {
      final directory = await Directory.systemTemp.createTemp('binary-large-');
      addTearDown(() => directory.delete(recursive: true));
      const size = 9 * 1024 * 1024;
      const changed = 8 * 1024 * 1024 + 123;
      final left = File('${directory.path}/left.bin');
      final right = File('${directory.path}/right.bin');
      final writerA = await left.open(mode: FileMode.write);
      await writerA.truncate(size);
      await writerA.close();
      final writerB = await right.open(mode: FileMode.write);
      await writerB.truncate(size + 3);
      await writerB.setPosition(changed);
      await writerB.writeByte(99);
      await writerB.close();
      final a = _ObservedLocal(), b = _ObservedLocal();
      final session = await BinaryComparisonSession.open(
        a,
        (await a.stat(left.path))!,
        b,
        (await b.stat(right.path))!,
      );
      expect(session.result.rangeCount, 2);
      expect((await session.difference(0)).start, changed);
      final last = await session.difference(1);
      expect([last.start, last.end], [size, size + 3]);
      final page = await session.window(changed - 3, length: 16);
      expect(page.right[3], 99);
      expect(page.left, Uint8List(16));
      final tail = await session.window(size - 1, length: 16);
      expect(tail.left.length, 1);
      expect(tail.right.length, 4);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test('navigation refuses a source that changed after comparison', () async {
    final directory = await Directory.systemTemp.createTemp('binary-changed-');
    addTearDown(() => directory.delete(recursive: true));
    final left = File('${directory.path}/a')..writeAsBytesSync([1, 2]);
    final right = File('${directory.path}/b')..writeAsBytesSync([1, 3]);
    final backend = _ObservedLocal();
    final session = await BinaryComparisonSession.open(
      backend,
      (await backend.stat(left.path))!,
      backend,
      (await backend.stat(right.path))!,
    );
    await right.writeAsBytes([1, 4, 5]);
    await expectLater(session.window(0), throwsStateError);
    await expectLater(session.difference(0), throwsStateError);
  });

  test(
    'cancellation interrupts a binary source stalled before its first chunk',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var cancelled = false;
      Stream<List<int>> stalled() async* {
        entered.complete();
        await release.future;
        yield [1];
      }

      final pending = compareBinaryStreams(
        stalled(),
        Stream.value([2]),
        isCancelled: () => cancelled,
      );
      await entered.future;
      cancelled = true;
      try {
        await expectLater(
          pending.timeout(const Duration(seconds: 2)),
          throwsStateError,
        );
      } finally {
        release.complete();
      }
    },
  );
}
