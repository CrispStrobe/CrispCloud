import 'dart:async';

import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/services/transfer_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TransferTask task(
    String id,
    Future<void> Function() execute, {
    OperationProgress? operation,
    int priority = 0,
  }) => TransferTask(
    id: id,
    operation:
        operation ??
        OperationProgress(
          id: id,
          type: OperationType.copy,
          sourcePath: '/source',
          targetPath: '/target',
          fileName: id,
        ),
    execute: execute,
    priority: priority,
  );

  test(
    'concurrency changes start pending work and never cancel active work',
    () async {
      final queue = TransferQueue(maxConcurrent: 0);
      addTearDown(queue.dispose);
      final gates = [Completer<void>(), Completer<void>(), Completer<void>()];
      final starts = <int>[];
      for (var i = 0; i < gates.length; i++) {
        queue.enqueue(
          task('$i', () async {
            starts.add(i);
            await gates[i].future;
          }),
        );
      }
      expect(starts, isEmpty);
      queue.setMaxConcurrent(2);
      await Future<void>.delayed(Duration.zero);
      expect(starts, [0, 1]);
      queue.setMaxConcurrent(1);
      expect(queue.activeCount, 2);
      gates[0].complete();
      await Future<void>.delayed(Duration.zero);
      expect(starts, [0, 1]);
      gates[1].complete();
      await Future<void>.delayed(Duration.zero);
      expect(starts, [0, 1, 2]);
      gates[2].complete();
      await Future<void>.delayed(Duration.zero);
      expect(queue.activeCount, 0);
      expect(() => queue.setMaxConcurrent(-1), throwsArgumentError);
    },
  );

  test(
    'pending pause does not occupy a slot and resume schedules it',
    () async {
      final queue = TransferQueue(maxConcurrent: 0);
      addTearDown(queue.dispose);
      final paused = OperationProgress(
        id: 'paused',
        type: OperationType.copy,
        sourcePath: '/source',
        targetPath: '/target',
        fileName: 'paused',
      )..pause();
      final starts = <String>[];
      queue.enqueue(
        task('paused', () async {
          starts.add('paused');
        }, operation: paused),
      );
      queue.enqueue(
        task('ready', () async {
          starts.add('ready');
        }),
      );
      queue.setMaxConcurrent(1);
      await Future<void>.delayed(Duration.zero);
      expect(starts, ['ready']);
      expect(queue.pendingCount, 1);
      paused.resume();
      queue.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(starts, ['ready', 'paused']);
    },
  );

  test(
    'changing priority and manual order preserves tasks and callbacks',
    () async {
      final queue = TransferQueue(maxConcurrent: 0);
      addTearDown(queue.dispose);
      final starts = <String>[];
      for (final id in ['a', 'b', 'c']) {
        queue.enqueue(
          task(id, () async {
            starts.add(id);
          }),
        );
      }
      queue.setPendingPriority('c', 10);
      expect(queue.pendingTasks.map((task) => task.id), ['c', 'a', 'b']);
      expect(queue.pendingTasks.first.priority, 10);
      queue.movePendingToTop('b');
      expect(queue.pendingTasks.map((task) => task.id), ['b', 'c', 'a']);
      queue.setMaxConcurrent(1);
      await Future<void>.delayed(Duration.zero);
      expect(starts, ['b', 'c', 'a']);
    },
  );
}
