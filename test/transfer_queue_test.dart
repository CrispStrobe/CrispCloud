import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/transfer_queue.dart';
import 'package:crisp_cloud/models/operation_progress.dart';

OperationProgress _makeOp(String id) => OperationProgress(
      id: id,
      type: OperationType.upload,
      sourcePath: '/local/$id',
      targetPath: '/remote/$id',
      fileName: id,
      totalBytes: 100,
    );

void main() {
  group('TransferQueue', () {
    test('executes tasks up to maxConcurrent', () async {
      final queue = TransferQueue(maxConcurrent: 2);
      final order = <String>[];
      final c1 = Completer<void>();
      final c2 = Completer<void>();
      final c3 = Completer<void>();

      queue.enqueue(TransferTask(
        id: 'a',
        operation: _makeOp('a'),
        execute: () async {
          order.add('a-start');
          await c1.future;
          order.add('a-end');
        },
      ));
      queue.enqueue(TransferTask(
        id: 'b',
        operation: _makeOp('b'),
        execute: () async {
          order.add('b-start');
          await c2.future;
          order.add('b-end');
        },
      ));
      queue.enqueue(TransferTask(
        id: 'c',
        operation: _makeOp('c'),
        execute: () async {
          order.add('c-start');
          await c3.future;
          order.add('c-end');
        },
      ));

      await Future.delayed(Duration.zero);

      expect(queue.activeCount, 2);
      expect(queue.pendingCount, 1);
      expect(order, ['a-start', 'b-start']);

      c1.complete();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(order, contains('c-start'));

      c2.complete();
      c3.complete();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(queue.activeCount, 0);
      expect(queue.completedCount, 3);
      queue.dispose();
    });

    test('cancels all tasks', () async {
      final queue = TransferQueue(maxConcurrent: 1);
      final neverCompletes = Completer<void>();

      final op = _makeOp('x');
      queue.enqueue(TransferTask(
        id: 'x',
        operation: op,
        execute: () => neverCompletes.future,
      ));

      final op2 = _makeOp('y');
      queue.enqueue(TransferTask(
        id: 'y',
        operation: op2,
        execute: () async {},
      ));

      queue.cancelAll();

      expect(op.isCancelled, isTrue);
      expect(op2.isCancelled, isTrue);
      expect(queue.pendingCount, 0);
      queue.dispose();
    });

    test('retries on transient error then succeeds', () async {
      final queue = TransferQueue(
        maxConcurrent: 1,
        maxRetries: 2,
        retryBaseDelay: const Duration(milliseconds: 10),
      );
      int attempts = 0;
      Object? lastError = 'sentinel';

      queue.enqueue(TransferTask(
        id: 'retry',
        operation: _makeOp('retry'),
        execute: () async {
          attempts++;
          if (attempts < 2) throw Exception('connection timeout');
        },
        onDone: (e) => lastError = e,
      ));

      await Future.delayed(const Duration(milliseconds: 200));

      expect(attempts, 2);
      expect(lastError, isNull); // succeeded on second attempt
      queue.dispose();
    });

    test('fails after max retries', () async {
      final queue = TransferQueue(
        maxConcurrent: 1,
        maxRetries: 2,
        retryBaseDelay: const Duration(milliseconds: 10),
      );
      Object? lastError;

      queue.enqueue(TransferTask(
        id: 'fail',
        operation: _makeOp('fail'),
        execute: () async => throw Exception('connection timeout'),
        onDone: (e) => lastError = e,
      ));

      await Future.delayed(const Duration(milliseconds: 500));

      expect(lastError, isNotNull);
      queue.dispose();
    });

    test('does not retry non-transient errors', () async {
      final queue = TransferQueue(
        maxConcurrent: 1,
        maxRetries: 3,
        retryBaseDelay: const Duration(milliseconds: 10),
      );
      int attempts = 0;

      queue.enqueue(TransferTask(
        id: 'perm',
        operation: _makeOp('perm'),
        execute: () async {
          attempts++;
          throw Exception('permission denied');
        },
        onDone: (e) {},
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(attempts, 1);
      queue.dispose();
    });

    test('clearCompleted removes finished tasks', () async {
      final queue = TransferQueue(maxConcurrent: 3);

      queue.enqueue(TransferTask(
        id: 'done',
        operation: _makeOp('done'),
        execute: () async {},
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(queue.completedCount, 1);
      queue.clearCompleted();
      expect(queue.completedCount, 0);
      queue.dispose();
    });

    test('onDone fires with null on success', () async {
      final queue = TransferQueue(maxConcurrent: 1);
      Object? receivedError = 'sentinel';

      queue.enqueue(TransferTask(
        id: 'ok',
        operation: _makeOp('ok'),
        execute: () async {},
        onDone: (e) => receivedError = e,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(receivedError, isNull);
      queue.dispose();
    });

    test('onDone fires with error on failure', () async {
      final queue = TransferQueue(maxConcurrent: 1, maxRetries: 0);
      Object? receivedError;

      queue.enqueue(TransferTask(
        id: 'err',
        operation: _makeOp('err'),
        execute: () async => throw Exception('boom'),
        onDone: (e) => receivedError = e,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(receivedError, isNotNull);
      expect(receivedError.toString(), contains('boom'));
      queue.dispose();
    });
  });
}
