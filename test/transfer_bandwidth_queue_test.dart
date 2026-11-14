import 'dart:async';

import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/services/transfer_queue.dart';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/transfer_bandwidth_test_clock.dart';

Future<void> _pump() => Future<void>.delayed(Duration.zero);

OperationProgress _operation(String id) => OperationProgress(
  id: id,
  type: OperationType.copy,
  sourcePath: '/source',
  targetPath: '/target',
  fileName: id,
);

Future<Object?> _enqueue(
  TransferQueue queue,
  String taskId,
  OperationProgress operation,
  Future<void> Function() execute,
) {
  final done = Completer<Object?>();
  queue.enqueue(
    TransferTask(
      id: taskId,
      operation: operation,
      execute: execute,
      retainCompletedTask: false,
      onDone: done.complete,
    ),
  );
  return done.future;
}

void main() {
  test(
    'batch tasks share one fair identity and retain sibling lifetimes',
    () async {
      final clock = ManualBandwidthClock();
      final allocator = TransferBandwidthAllocator(
        limits: const TransferBandwidthLimits(uploadBytesPerSecond: 10),
        clock: () => clock.elapsed,
        createTimer: clock.timer,
      );
      final queue = TransferQueue(maxConcurrent: 3, bandwidth: allocator);
      addTearDown(() {
        queue.dispose();
        allocator.dispose();
      });
      final batch = _operation('batch');
      final other = _operation('other');
      final counts = <String, int>{'batch': 0, 'other': 0};
      final contexts = <TransferBandwidthContext>[];
      Future<void> execute(OperationProgress operation, int length) async {
        final context = TransferBandwidthContext.current!;
        expect(context.operationId, operation.id);
        contexts.add(context);
        await for (final part in context.bind(
          Stream.value(List<int>.filled(length, 7)),
          direction: TransferBandwidthDirection.upload,
        )) {
          counts[operation.id] = counts[operation.id]! + part.length;
        }
      }

      final work = [
        _enqueue(queue, 'batch-a', batch, () => execute(batch, 4)),
        _enqueue(queue, 'batch-b', batch, () => execute(batch, 4)),
        _enqueue(queue, 'other', other, () => execute(other, 8)),
      ];
      await _pump();
      expect(contexts.length, 3);
      expect(allocator.snapshot.activeJobs, 2);
      for (var i = 0; i < 8; i++) {
        await clock.next();
      }
      expect(counts, {'batch': 4, 'other': 4});
      expect(clock.elapsed, const Duration(milliseconds: 800));
      for (var i = 0; i < 8; i++) {
        await clock.next();
      }
      expect(await Future.wait(work), everyElement(isNull));
      expect(counts, {'batch': 8, 'other': 8});
      expect(contexts.every((context) => context.isClosed), isTrue);
      expect(allocator.snapshot.activeJobs, 0);
      expect(allocator.snapshot.uploadBytes, 16);
      expect(clock.activeTimers, 0);
    },
  );

  test(
    'individual pause releases demand while another operation progresses',
    () async {
      final clock = ManualBandwidthClock();
      final allocator = TransferBandwidthAllocator(
        limits: const TransferBandwidthLimits(uploadBytesPerSecond: 10),
        clock: () => clock.elapsed,
        createTimer: clock.timer,
      );
      final queue = TransferQueue(maxConcurrent: 2, bandwidth: allocator);
      addTearDown(() {
        queue.dispose();
        allocator.dispose();
      });
      final first = _operation('first');
      final second = _operation('second');
      final output = <String>[];
      Future<void> execute(OperationProgress operation) async {
        final context = TransferBandwidthContext.current!;
        await for (final part in context.bind(
          Stream.value([1, 2]),
          direction: TransferBandwidthDirection.upload,
        )) {
          output.addAll(List<String>.filled(part.length, operation.id));
        }
      }

      final a = _enqueue(queue, 'a', first, () => execute(first));
      final b = _enqueue(queue, 'b', second, () => execute(second));
      await _pump();
      clock.advance(const Duration(milliseconds: 50));
      first.pause();
      await _pump();
      expect(allocator.snapshot.pendingUploadJobs, 1);
      await clock.next();
      await clock.next();
      expect(await b, isNull);
      expect(output, ['second', 'second']);
      expect(clock.activeTimers, 0);
      clock.advance(const Duration(hours: 1));
      first.resume();
      await _pump();
      expect(output, ['second', 'second']);
      clock.advance(const Duration(milliseconds: 99));
      await _pump();
      expect(output, ['second', 'second']);
      clock.advance(const Duration(milliseconds: 1));
      await _pump();
      await clock.next();
      expect(await a, isNull);
      expect(output, ['second', 'second', 'first', 'first']);
      expect(allocator.snapshot.uploadBytes, 4);
    },
  );

  test(
    'Stop cancels a quota wait without waiting for upstream cleanup',
    () async {
      final clock = ManualBandwidthClock();
      final allocator = TransferBandwidthAllocator(
        limits: const TransferBandwidthLimits(uploadBytesPerSecond: 1),
        clock: () => clock.elapsed,
        createTimer: clock.timer,
      );
      final queue = TransferQueue(bandwidth: allocator);
      final cleanup = Completer<void>();
      var sourceCancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () {
          sourceCancelled = true;
          return cleanup.future;
        },
      );
      addTearDown(() async {
        cleanup.complete();
        await source.close();
        queue.dispose();
        allocator.dispose();
      });
      final operation = _operation('cancel');
      final done = _enqueue(queue, 'cancel', operation, () async {
        await TransferBandwidthContext.current!
            .bind(source.stream, direction: TransferBandwidthDirection.upload)
            .drain<void>();
      });
      source.add([1]);
      await _pump();
      expect(clock.activeTimers, 1);
      operation.cancel();
      expect(
        await done.timeout(const Duration(seconds: 2)),
        isA<TransferCancelled>(),
      );
      expect(sourceCancelled, isTrue);
      expect(cleanup.isCompleted, isFalse);
      expect(clock.elapsed, Duration.zero);
      expect(clock.activeTimers, 0);
      expect(allocator.snapshot.uploadBytes, 0);
      expect(allocator.snapshot.activeJobs, 0);
    },
  );

  test(
    'queue pause remains admission-only for already active transport',
    () async {
      final clock = ManualBandwidthClock();
      final allocator = TransferBandwidthAllocator(
        limits: const TransferBandwidthLimits(uploadBytesPerSecond: 10),
        clock: () => clock.elapsed,
        createTimer: clock.timer,
      );
      final queue = TransferQueue(maxConcurrent: 1, bandwidth: allocator);
      addTearDown(() {
        queue.dispose();
        allocator.dispose();
      });
      final started = <String>[];
      Future<void> execute(String id) async {
        started.add(id);
        await TransferBandwidthContext.current!
            .bind(
              Stream.value([1]),
              direction: TransferBandwidthDirection.upload,
            )
            .drain<void>();
      }

      final a = _enqueue(queue, 'a', _operation('a'), () => execute('a'));
      await _pump();
      queue.pause();
      final b = _enqueue(queue, 'b', _operation('b'), () => execute('b'));
      await clock.next();
      expect(await a, isNull);
      expect(started, ['a']);
      expect(queue.pendingCount, 1);
      queue.resume();
      await clock.next();
      expect(await b, isNull);
      expect(started, ['a', 'b']);
    },
  );

  test(
    'policy readiness and an intervening pause precede the first body',
    () async {
      final allocator = TransferBandwidthAllocator();
      final policy = Completer<void>();
      final queue = TransferQueue(
        bandwidth: allocator,
        bandwidthReady: () => policy.future,
      );
      addTearDown(() {
        queue.dispose();
        allocator.dispose();
      });
      final operation = _operation('restore');
      var started = false;
      final done = _enqueue(queue, 'restore', operation, () async {
        started = true;
        expect(TransferBandwidthContext.current!.operationId, 'restore');
      });
      await _pump();
      expect(started, isFalse);
      expect(allocator.snapshot.activeJobs, 0);
      operation.pause();
      policy.complete();
      await _pump();
      expect(started, isFalse);
      operation.resume();
      expect(await done, isNull);
      expect(started, isTrue);
      expect(allocator.snapshot.activeJobs, 0);
    },
  );

  for (final stop in ['cancel', 'dispose']) {
    test(
      '$stop settles a task while policy loading is still pending',
      () async {
        final allocator = TransferBandwidthAllocator();
        final policy = Completer<void>();
        final queue = TransferQueue(
          bandwidth: allocator,
          bandwidthReady: () => policy.future,
        );
        addTearDown(() {
          policy.complete();
          queue.dispose();
          allocator.dispose();
        });
        final operation = _operation(stop);
        var started = false;
        final done = _enqueue(
          queue,
          stop,
          operation,
          () async => started = true,
        );
        await _pump();
        if (stop == 'cancel') {
          operation.cancel();
        } else {
          queue.dispose();
        }
        expect(
          await done.timeout(const Duration(seconds: 2)),
          isA<TransferCancelled>(),
        );
        expect(policy.isCompleted, isFalse);
        expect(started, isFalse);
        expect(allocator.snapshot.activeJobs, 0);
      },
    );
  }

  test(
    'retry uses a fresh captured lifetime and charges transmitted bytes again',
    () async {
      final allocator = TransferBandwidthAllocator();
      final queue = TransferQueue(
        bandwidth: allocator,
        maxRetries: 1,
        retryBaseDelay: Duration.zero,
      );
      addTearDown(() {
        queue.dispose();
        allocator.dispose();
      });
      final contexts = <TransferBandwidthContext>[];
      final done = _enqueue(queue, 'retry', _operation('retry-job'), () async {
        final context = TransferBandwidthContext.current!;
        contexts.add(context);
        await context
            .bind(
              Stream.value([1, 2, 3]),
              direction: TransferBandwidthDirection.upload,
            )
            .drain<void>();
        if (contexts.length == 1) throw StateError('Connection interrupted');
      });
      expect(await done, isNull);
      expect(contexts, hasLength(2));
      expect(identical(contexts[0], contexts[1]), isFalse);
      expect(
        contexts.every((context) => context.operationId == 'retry-job'),
        isTrue,
      );
      expect(contexts.every((context) => context.isClosed), isTrue);
      expect(allocator.snapshot.uploadBytes, 6);
      expect(allocator.snapshot.activeJobs, 0);
    },
  );

  test(
    'failed policy load prevents transport and a later saved policy recovers',
    () async {
      final allocator = TransferBandwidthAllocator();
      Future<void> Function() ready = () =>
          Future.error(StateError('Invalid policy'));
      final queue = TransferQueue(
        bandwidth: allocator,
        bandwidthReady: () => ready(),
        maxRetries: 0,
      );
      addTearDown(() {
        queue.dispose();
        allocator.dispose();
      });
      var starts = 0;
      Future<void> execute() async {
        starts++;
        await TransferBandwidthContext.current!
            .bind(
              Stream.value([9]),
              direction: TransferBandwidthDirection.upload,
            )
            .drain<void>();
      }

      expect(
        await _enqueue(queue, 'blocked', _operation('blocked'), execute),
        isA<StateError>(),
      );
      expect(starts, 0);
      expect(allocator.snapshot.uploadBytes, 0);
      ready = () async {};
      expect(
        await _enqueue(queue, 'recovered', _operation('recovered'), execute),
        isNull,
      );
      expect(starts, 1);
      expect(allocator.snapshot.uploadBytes, 1);
    },
  );
}
