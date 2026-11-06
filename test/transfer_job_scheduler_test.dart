import 'dart:async';

import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/services/transfer_queue.dart';
import 'package:crisp_storage/crisp_storage.dart'
    show RemoteException, TransferCancelled;
import 'package:flutter_test/flutter_test.dart';

OperationProgress _operation(String id) => OperationProgress(
  id: id,
  type: OperationType.copy,
  sourcePath: '/source/$id',
  targetPath: '/destination/$id',
  fileName: id,
);

TransferTask _task(
  String id, {
  required Future<void> Function() execute,
  OperationProgress? operation,
  FutureOr<void> Function(Object? error)? onDone,
  String? providerName,
  Set<String> providerNames = const {},
  List<TransferResourceClaim> resourceClaims = const [],
  DateTime? notBefore,
  int priority = 0,
  int? maxRetries,
}) => TransferTask(
  id: id,
  operation: operation ?? _operation(id),
  execute: execute,
  onDone: onDone,
  providerName: providerName,
  providerNames: providerNames,
  resourceClaims: resourceClaims,
  notBefore: notBefore,
  priority: priority,
  maxRetries: maxRetries,
);

TransferResourceClaim _claim(
  List<String> segments, {
  Object namespace = 'account',
  bool write = true,
}) => TransferResourceClaim(
  namespace: namespace,
  pathSegments: segments,
  write: write,
);

class _CountingNamespace {
  _CountingNamespace(this.key, this.onComparison);

  final String key;
  final void Function() onComparison;

  @override
  bool operator ==(Object other) {
    onComparison();
    return other is _CountingNamespace && other.key == key;
  }

  @override
  int get hashCode => key.hashCode;
}

void main() {
  testWidgets('queue pause preserves limits and drains only admitted work', (
    tester,
  ) async {
    final queue = TransferQueue(maxConcurrent: 2);
    addTearDown(queue.dispose);
    final active = Completer<void>();
    final starts = <String>[];
    final operation = _operation('active');
    queue.enqueue(
      _task(
        'active',
        operation: operation,
        execute: () async {
          starts.add('active');
          await active.future;
        },
      ),
    );
    queue.pause();
    for (final id in ['b', 'c']) {
      queue.enqueue(_task(id, execute: () async => starts.add(id)));
    }
    expect(queue.isPaused, isTrue);
    expect(queue.maxConcurrent, 2);
    expect(queue.activeCount, 1);
    expect(queue.blockedReason('b'), 'Queue paused');
    expect(operation.isPaused, isFalse);
    expect(operation.isCancelled, isFalse);

    queue.setMaxConcurrent(3);
    active.complete();
    await tester.pump();
    expect(starts, ['active']);
    expect(queue.pendingCount, 2);
    expect(queue.activeCount, 0);
    queue.resume();
    await tester.pump();
    expect(starts, ['active', 'b', 'c']);
    expect(queue.maxConcurrent, 3);
    expect(queue.isPaused, isFalse);
  });

  testWidgets('scheduled jobs do not take slots or block ready work', (
    tester,
  ) async {
    final now = tester.binding.clock.now;
    final queue = TransferQueue(maxConcurrent: 1, now: now);
    addTearDown(queue.dispose);
    final start = now();
    final starts = <String>[];
    queue.enqueue(
      _task(
        'ten',
        priority: 100,
        notBefore: start.add(const Duration(seconds: 10)),
        execute: () async => starts.add('ten'),
      ),
    );
    queue.enqueue(
      _task(
        'thirty',
        notBefore: start.add(const Duration(seconds: 30)),
        execute: () async => starts.add('thirty'),
      ),
    );
    expect(queue.activeCount, 0);
    expect(queue.blockedReason('ten'), 'Scheduled start');
    queue.enqueue(_task('ready', execute: () async => starts.add('ready')));
    await tester.pump();
    expect(starts, ['ready']);
    expect(queue.pendingCount, 2);

    // Moving a deadline earlier must replace the existing wake-up.
    queue.setPendingStart('thirty', start.add(const Duration(seconds: 5)));
    await tester.pump(const Duration(seconds: 4));
    expect(starts, ['ready']);
    await tester.pump(const Duration(seconds: 1));
    expect(starts, ['ready', 'thirty']);
    await tester.pump(const Duration(seconds: 4));
    expect(starts, ['ready', 'thirty']);
    await tester.pump(const Duration(seconds: 1));
    expect(starts, ['ready', 'thirty', 'ten']);
    expect(queue.activeCount, 0);
    expect(queue.pendingCount, 0);
  });

  testWidgets('rescheduling, pausing and disposal cancel stale wake-ups', (
    tester,
  ) async {
    final now = tester.binding.clock.now;
    final queue = TransferQueue(now: now);
    final start = now();
    var runs = 0;
    final outcomes = <Object?>[];
    queue.enqueue(
      _task(
        'later',
        notBefore: start.add(const Duration(seconds: 5)),
        execute: () async => runs++,
        onDone: outcomes.add,
      ),
    );
    queue.setPendingStart('later', start.add(const Duration(seconds: 20)));
    await tester.pump(const Duration(seconds: 5));
    expect(runs, 0);
    queue.pause();
    await tester.pump(const Duration(seconds: 20));
    expect(runs, 0);
    queue.resume();
    await tester.pump();
    expect(runs, 1);
    expect(outcomes, [null]);

    queue.enqueue(
      _task(
        'disposed',
        notBefore: now().add(const Duration(days: 1)),
        execute: () async => runs++,
        onDone: outcomes.add,
      ),
    );
    queue.dispose();
    queue.dispose();
    await tester.pump();
    expect(outcomes, [null, isA<TransferCancelled>()]);
    await tester.pump(const Duration(days: 2));
    expect(runs, 1);
    expect(outcomes.length, 2);
    expect(
      () => queue.enqueue(_task('closed', execute: () async {})),
      throwsStateError,
    );
  });

  testWidgets('priority changes retain all policies and disable blind replay', (
    tester,
  ) async {
    final now = tester.binding.clock.now;
    final queue = TransferQueue(maxConcurrent: 0, maxRetries: 5, now: now);
    addTearDown(queue.dispose);
    final providers = {'source'};
    final segments = ['destination', 'directory'];
    final claim = _claim(segments);
    final claims = [claim];
    final scheduledAt = now().add(const Duration(hours: 1));
    final operation = _operation('move');
    var attempts = 0;
    final outcomes = <Object?>[];
    Future<void> execute() async {
      attempts++;
      throw const RemoteException('temporary network error', retryable: true);
    }

    final task = _task(
      'move',
      operation: operation,
      execute: execute,
      onDone: outcomes.add,
      notBefore: scheduledAt,
      providerName: 'destination',
      providerNames: providers,
      resourceClaims: claims,
      maxRetries: 0,
    );
    queue.enqueue(task);
    expect(() => queue.enqueue(task), throwsStateError);
    providers.add('mutated');
    segments.add('mutated');
    claims.clear();
    queue.setPendingPriority('move', 40);
    final updated = queue.pendingTasks.single;
    expect(updated.priority, 40);
    expect(updated.notBefore, scheduledAt);
    expect(updated.providerName, 'destination');
    expect(updated.providerNames, {'source', 'destination'});
    expect(updated.resourceClaims.single.pathSegments, [
      'destination',
      'directory',
    ]);
    expect(updated.maxRetries, 0);
    expect(updated.operation, same(operation));
    expect(updated.execute, same(task.execute));
    expect(() => updated.providerNames.add('x'), throwsUnsupportedError);
    expect(() => updated.resourceClaims.clear(), throwsUnsupportedError);
    expect(() => claim.pathSegments.clear(), throwsUnsupportedError);

    queue.setPendingStart('move', null);
    queue.setMaxConcurrent(1);
    await tester.pump();
    expect(attempts, 1);
    expect(outcomes, [isA<RemoteException>()]);
    expect(queue.activeCount, 0);
    expect(queue.completedCount, 1);
    expect(
      () => _task('invalid', execute: () async {}, maxRetries: -1),
      throwsArgumentError,
    );
  });

  testWidgets('both endpoints and legacy provider share admission limits', (
    tester,
  ) async {
    final queue = TransferQueue(maxConcurrent: 3);
    addTearDown(queue.dispose);
    queue.setProviderLimit('source', 1);
    queue.setProviderLimit('destination', 1);
    final gates = <String, Completer<void>>{};
    final starts = <String>[];
    void enqueue(String id, Set<String> providers, {String? legacy}) {
      gates[id] = Completer<void>();
      queue.enqueue(
        _task(
          id,
          providerName: legacy,
          providerNames: providers,
          execute: () async {
            starts.add(id);
            await gates[id]!.future;
          },
        ),
      );
    }

    enqueue('both', {'source', 'destination'}, legacy: 'destination');
    enqueue('source-only', {'source', 'other-target'});
    enqueue('destination-only', {'other-source'}, legacy: 'destination');
    enqueue('unrelated', {'other-account'});
    expect(starts, ['both', 'unrelated']);
    expect(queue.activeCount, 2);
    expect(queue.blockedReason('source-only'), 'Waiting for provider capacity');
    expect(
      queue.blockedReason('destination-only'),
      'Waiting for provider capacity',
    );
    gates['both']!.complete();
    await tester.pump();
    expect(starts, ['both', 'unrelated', 'source-only', 'destination-only']);
    expect(queue.activeCount, 3);
    for (final gate in gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pump();
    expect(queue.activeCount, 0);
  });

  testWidgets('provider pacing waits without occupying unrelated slots', (
    tester,
  ) async {
    final now = tester.binding.clock.now;
    final queue = TransferQueue(maxConcurrent: 1, now: now);
    addTearDown(queue.dispose);
    queue.setProviderRateLimit('source', minDelayMs: 1000);
    final starts = <String>[];
    queue.enqueue(
      _task(
        'first',
        providerNames: {'source', 'destination-a'},
        execute: () async => starts.add('first'),
      ),
    );
    await tester.pump();
    queue.enqueue(
      _task(
        'paced',
        providerNames: {'source', 'destination-b'},
        execute: () async => starts.add('paced'),
      ),
    );
    queue.enqueue(_task('free', execute: () async => starts.add('free')));
    await tester.pump();
    expect(starts, ['first', 'free']);
    expect(queue.activeCount, 0);
    expect(queue.blockedReason('paced'), 'Waiting for provider rate limit');
    await tester.pump(const Duration(milliseconds: 999));
    expect(starts, ['first', 'free']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(starts, ['first', 'free', 'paced']);
  });

  testWidgets('path reservations use segment ancestry and allow shared reads', (
    tester,
  ) async {
    final queue = TransferQueue(maxConcurrent: 6);
    addTearDown(queue.dispose);
    final starts = <String>[];
    final gates = <String, Completer<void>>{};
    void enqueue(String id, TransferResourceClaim claim) {
      gates[id] = Completer<void>();
      queue.enqueue(
        _task(
          id,
          resourceClaims: [claim],
          execute: () async {
            starts.add(id);
            await gates[id]!.future;
          },
        ),
      );
    }

    enqueue('read-parent', _claim(['docs'], write: false));
    enqueue('read-child', _claim(['docs', 'a'], write: false));
    enqueue('write-child', _claim(['docs', 'a']));
    enqueue('similar-name', _claim(['docs-old']));
    enqueue('other-account', _claim(['docs'], namespace: 'another-account'));
    enqueue('write-root', _claim([]));
    expect(starts, [
      'read-parent',
      'read-child',
      'similar-name',
      'other-account',
    ]);
    expect(queue.blockedReason('write-child'), 'Path busy');
    expect(queue.blockedReason('write-root'), 'Path busy');
    gates['read-parent']!.complete();
    await tester.pump();
    expect(starts, isNot(contains('write-child')));
    gates['read-child']!.complete();
    await tester.pump();
    expect(starts.last, 'write-child');
    expect(starts, isNot(contains('write-root')));
    gates['write-child']!.complete();
    gates['similar-name']!.complete();
    await tester.pump();
    expect(starts.last, 'write-root');
    for (final gate in gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pump();
    expect(queue.activeCount, 0);
  });

  testWidgets('indexed ancestor conflicts work in both admission directions', (
    tester,
  ) async {
    final cases =
        <(List<TransferResourceClaim>, List<TransferResourceClaim>, bool)>[
          (
            [
              _claim(['a'], write: false),
            ],
            [
              _claim(['a', 'b']),
            ],
            true,
          ),
          (
            [
              _claim(['a', 'b']),
            ],
            [
              _claim(['a'], write: false),
            ],
            true,
          ),
          (
            [
              _claim(['a']),
            ],
            [
              _claim(['a', 'b'], write: false),
            ],
            true,
          ),
          (
            [
              _claim(['a', 'b'], write: false),
            ],
            [
              _claim(['a']),
            ],
            true,
          ),
          (
            [
              _claim(['a', 'b'], write: false),
            ],
            [
              _claim(['a', 'c']),
            ],
            false,
          ),
          (
            [_claim([], write: false)],
            [
              _claim(['a', 'b']),
            ],
            true,
          ),
          (
            [
              _claim(['a', 'b']),
            ],
            [_claim([], write: false)],
            true,
          ),
          (
            [
              _claim(['a'], write: false),
              _claim(['a', 'b']),
            ],
            [
              _claim(['a', 'c'], write: false),
            ],
            false,
          ),
          (
            [
              _claim(['a'], write: false),
              _claim(['a', 'b']),
            ],
            [
              _claim(['a', 'c']),
            ],
            true,
          ),
          (
            [
              _claim(['a', 'b']),
              _claim(['a']),
            ],
            [
              _claim(['a', 'c'], write: false),
            ],
            true,
          ),
        ];
    for (final (activeClaims, pendingClaims, blocked) in cases) {
      final queue = TransferQueue(maxConcurrent: 2);
      addTearDown(queue.dispose);
      final active = Completer<void>();
      var successorRan = false;
      queue.enqueue(
        _task(
          'active',
          resourceClaims: activeClaims,
          execute: () => active.future,
        ),
      );
      queue.enqueue(
        _task(
          'successor',
          resourceClaims: pendingClaims,
          execute: () async => successorRan = true,
        ),
      );
      expect(successorRan, !blocked);
      if (blocked) expect(queue.blockedReason('successor'), 'Path busy');
      active.complete();
      await tester.pump();
      expect(successorRan, isTrue);
      queue.dispose();
    }
  });

  testWidgets(
    'large flat copy and move selections avoid pairwise claim comparisons',
    (tester) async {
      const files = 10000;
      for (final moving in [false, true]) {
        var comparisons = 0;
        final firstNamespace = _CountingNamespace(
          'same-account',
          () => comparisons++,
        );
        final secondNamespace = _CountingNamespace(
          'same-account',
          () => comparisons++,
        );
        final firstClaims = [
          for (var file = 0; file < files; file++)
            _claim(
              [moving ? 'source-a' : 'source', '$file'],
              namespace: firstNamespace,
              write: moving,
            ),
          _claim(['destination-a'], namespace: firstNamespace),
        ];
        final secondClaims = [
          for (var file = 0; file < files; file++)
            _claim(
              [moving ? 'source-b' : 'source', '$file'],
              namespace: secondNamespace,
              write: moving,
            ),
          _claim(['destination-b'], namespace: secondNamespace),
        ];
        final queue = TransferQueue(maxConcurrent: 0);
        addTearDown(queue.dispose);
        final gate = Completer<void>();
        final starts = <String>[];
        for (final (id, claims) in [
          ('first', firstClaims),
          ('second', secondClaims),
        ]) {
          queue.enqueue(
            _task(
              id,
              resourceClaims: claims,
              execute: () async {
                starts.add(id);
                await gate.future;
              },
            ),
          );
        }
        final afterIndexConstruction = comparisons;
        queue.setPendingPriority('second', 10);
        queue.setPendingStart('second', null);
        expect(comparisons, afterIndexConstruction);
        queue.setMaxConcurrent(2);
        expect(starts, ['second', 'first']);
        expect(queue.activeCount, 2);
        // This is a work-count bound, not a timing assertion. Pairwise claim
        // comparisons perform roughly files squared namespace comparisons.
        expect(comparisons, lessThan(files * 8));
        gate.complete();
        await tester.pump();
        expect(queue.activeCount, 0);
        queue.dispose();
      }
    },
  );

  testWidgets('asynchronous completion retains every active reservation', (
    tester,
  ) async {
    final queue = TransferQueue(maxConcurrent: 3);
    addTearDown(queue.dispose);
    queue.setProviderLimit('source', 1);
    final finalize = Completer<void>();
    final starts = <String>[];
    final operation = _operation('first');
    final finalizationErrors = <Object?>[];
    var callbacks = 0;
    queue.enqueue(
      _task(
        'first',
        operation: operation,
        providerNames: {'source'},
        resourceClaims: [
          _claim(['destination']),
        ],
        execute: () async => starts.add('first'),
        onDone: (error) async {
          callbacks++;
          finalizationErrors.add(error);
          await finalize.future;
        },
      ),
    );
    queue.enqueue(
      _task(
        'same-provider',
        providerNames: {'source'},
        resourceClaims: [
          _claim(['elsewhere']),
        ],
        execute: () async => starts.add('same-provider'),
      ),
    );
    queue.enqueue(
      _task(
        'same-path',
        providerNames: {'different'},
        resourceClaims: [
          _claim(['destination', 'file']),
        ],
        execute: () async => starts.add('same-path'),
      ),
    );
    queue.enqueue(_task('free', execute: () async => starts.add('free')));
    await tester.pump();
    expect(callbacks, 1);
    expect(finalizationErrors, [null]);
    expect(starts, ['first', 'free']);
    expect(queue.activeCount, 1);
    expect(queue.blockedReason('same-path'), 'Path busy');
    expect(
      queue.blockedReason('same-provider'),
      'Waiting for provider capacity',
    );
    expect(
      () => queue.enqueue(_task('first', execute: () async {})),
      throwsStateError,
    );
    queue.cancel('first');
    expect(operation.isCancelled, isFalse);
    finalize.complete();
    await tester.pump();
    expect(starts, ['first', 'free', 'same-provider', 'same-path']);
    expect(callbacks, 1);
    expect(queue.activeCount, 0);
  });

  testWidgets(
    'active cancellation waits for the executor to relinquish paths',
    (tester) async {
      final queue = TransferQueue(maxConcurrent: 2);
      addTearDown(queue.dispose);
      final execution = Completer<void>();
      final outcomes = <Object?>[];
      var successorRan = false;
      queue.enqueue(
        _task(
          'active',
          resourceClaims: [
            _claim(['directory']),
          ],
          execute: () => execution.future,
          onDone: outcomes.add,
        ),
      );
      queue.enqueue(
        _task(
          'successor',
          resourceClaims: [
            _claim(['directory', 'file']),
          ],
          execute: () async => successorRan = true,
        ),
      );
      queue.cancel('active');
      await tester.pump();
      expect(queue.activeCount, 1);
      expect(successorRan, isFalse);
      expect(outcomes, isEmpty);
      execution.complete();
      await tester.pump();
      expect(outcomes, [isA<TransferCancelled>()]);
      expect(successorRan, isTrue);
    },
  );

  testWidgets('cancel and dispose callbacks are once-only under reentrancy', (
    tester,
  ) async {
    final queue = TransferQueue(maxConcurrent: 0);
    final shared = _operation('batch');
    final finishing = Completer<void>();
    final outcomes = <String, List<Object?>>{};
    Object? reentrantEnqueueError;
    final a = _task(
      'a',
      operation: shared,
      execute: () async => fail('Cancelled task executed'),
      onDone: (error) async {
        outcomes.putIfAbsent('a', () => []).add(error);
        queue.cancelAll();
        try {
          queue.enqueue(_task('a', execute: () async {}));
        } catch (error) {
          reentrantEnqueueError = error;
        }
        await finishing.future;
      },
    );
    queue.enqueue(a);
    queue.enqueue(
      _task(
        'b',
        operation: shared,
        execute: () async => fail('Cancelled task executed'),
        onDone: (error) {
          outcomes.putIfAbsent('b', () => []).add(error);
          queue.cancel('a');
        },
      ),
    );
    queue.setPendingPriority('a', 20);
    queue.setPendingStart('a', tester.binding.clock.now());
    queue.cancel('a');
    queue.dispose();
    await tester.pump();
    expect(reentrantEnqueueError, isA<StateError>());
    expect(outcomes['a'], [isA<TransferCancelled>()]);
    expect(outcomes['b'], [isA<TransferCancelled>()]);
    expect(queue.pendingCount, 0);
    finishing.complete();
    await tester.pump();
    expect(outcomes['a']!.length, 1);
    expect(outcomes['b']!.length, 1);
    expect(queue.activeCount, 0);
    expect(queue.completedCount, 2);
  });

  testWidgets('an active finalizer may cancel and dispose reentrantly', (
    tester,
  ) async {
    final queue = TransferQueue(maxConcurrent: 1);
    final finishing = Completer<void>();
    final operation = _operation('active');
    final outcomes = <String, List<Object?>>{};
    queue.enqueue(
      _task(
        'active',
        operation: operation,
        execute: () async {},
        onDone: (error) async {
          outcomes.putIfAbsent('active', () => []).add(error);
          queue.cancelAll();
          queue.dispose();
          await finishing.future;
        },
      ),
    );
    queue.enqueue(
      _task(
        'pending',
        execute: () async => fail('Disposed task executed'),
        onDone: (error) => outcomes.putIfAbsent('pending', () => []).add(error),
      ),
    );
    await tester.pump();
    expect(outcomes['active'], [null]);
    expect(outcomes['pending'], [isA<TransferCancelled>()]);
    expect(operation.isCancelled, isFalse);
    expect(queue.activeCount, 1);
    finishing.complete();
    await tester.pump();
    expect(queue.activeCount, 0);
    expect(outcomes['active']!.length, 1);
    expect(outcomes['pending']!.length, 1);
  });

  for (final asynchronous in [false, true]) {
    testWidgets(
      '${asynchronous ? 'async' : 'sync'} finalizer failure is recorded without replay or stalled work',
      (tester) async {
        final reported = <String>[];
        final queue = TransferQueue(
          maxConcurrent: 1,
          onCallbackError: (id, error, stackTrace) {
            reported.add(id);
          },
        );
        addTearDown(queue.dispose);
        final failure = StateError('journal unavailable');
        final finishing = Completer<void>();
        var attempts = 0;
        var callbacks = 0;
        var successorRan = false;
        queue.enqueue(
          _task(
            'first',
            execute: () async => attempts++,
            onDone: (error) {
              callbacks++;
              if (asynchronous) return finishing.future;
              throw failure;
            },
          ),
        );
        queue.enqueue(
          _task('successor', execute: () async => successorRan = true),
        );
        await tester.pump();
        if (asynchronous) {
          expect(queue.activeCount, 1);
          expect(successorRan, isFalse);
          finishing.completeError(failure);
          await tester.pump();
        }
        expect(queue.callbackErrors['first'], same(failure));
        expect(reported, ['first']);
        expect(attempts, 1);
        expect(callbacks, 1);
        expect(successorRan, isTrue);
        expect(queue.activeCount, 0);
        expect(() => queue.callbackErrors.clear(), throwsUnsupportedError);
        queue.clearCompleted();
        expect(queue.callbackErrors, isEmpty);
      },
    );
  }
}
