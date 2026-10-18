import 'dart:async';
import 'dart:convert';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:test/test.dart';

class Operation implements TransferOperation {
  final cancelled = Completer<void>();
  Completer<void>? paused;
  @override
  bool get isCancelled => cancelled.isCompleted;
  @override
  bool get isPaused => paused != null;
  @override
  Future<void> get cancellationFuture => cancelled.future;
  @override
  Future<void>? get pauseFuture => paused?.future;
  @override
  void cancel() {
    if (!isCancelled) cancelled.complete();
    resume();
  }

  void pause() {
    paused ??= Completer<void>();
  }

  void resume() {
    paused?.complete();
    paused = null;
  }
}

void main() {
  final pin = 'SHA256:${List.filled(43, 'A').join()}';
  final other = 'SHA256:${List.filled(43, 'B').join()}';
  group('SSH trust', () {
    String? stored;
    late SshKnownHosts hosts;
    setUp(() {
      stored = null;
      hosts = SshKnownHosts(
          read: () async => stored,
          write: (v) async {
            stored = v;
          });
    });
    test('unknown server requires explicit acceptance', () async {
      await expectLater(
          hosts.verify('nas:22', pin), throwsA(isA<SftpHostKeyException>()));
      expect(stored, isNull);
      await expectLater(
          hosts.verify('nas:22', pin, prompt: (_, __) async => false),
          throwsA(isA<SftpHostKeyException>()));
      expect(stored, isNull);
    });
    test('persists accepted key and recognizes it without another prompt',
        () async {
      expect(await hosts.verify('nas:22', pin, prompt: (_, __) async => true),
          isTrue);
      expect(await hosts.verify('nas:22', pin), isTrue);
      expect((jsonDecode(stored!) as Map)['nas:22'], pin);
    });
    test('changed key cannot be approved over an existing pin', () async {
      await hosts.verify('nas:22', pin, prompt: (_, __) async => true);
      var prompted = false;
      await expectLater(
          hosts.verify('nas:22', other, prompt: (_, __) async {
            prompted = true;
            return true;
          }),
          throwsA(isA<SftpHostKeyException>()));
      expect(prompted, isFalse);
      expect((jsonDecode(stored!) as Map)['nas:22'], pin);
    });
    test('concurrent clients preserve each accepted endpoint', () async {
      final second = SshKnownHosts(
          read: () async => stored,
          write: (v) async {
            await Future<void>.delayed(Duration.zero);
            stored = v;
          });
      await Future.wait([
        hosts.verify('nas:22', pin, prompt: (_, __) async => true),
        second.verify('nas:23', other, prompt: (_, __) async => true)
      ]);
      expect((jsonDecode(stored!) as Map).length, 2);
    });
    test('failed persistence rejects authentication and later writes recover',
        () async {
      final broken = SshKnownHosts(
          read: () async => null,
          write: (_) async => throw StateError('locked'));
      await expectLater(
          broken.verify('nas:22', pin, prompt: (_, __) async => true),
          throwsStateError);
      expect(await hosts.verify('nas:22', pin, prompt: (_, __) async => true),
          isTrue);
    });
    test('corrupt trust storage fails closed', () async {
      stored = 'invalid';
      await expectLater(
          hosts.verify('nas:22', pin, prompt: (_, __) async => true),
          throwsFormatException);
    });
  });
  test('profiles serialize overlapping edits and recover after failed writes',
      () async {
    String? raw;
    var fail = false;
    final store = ConnectionProfileStore(
        read: () async => raw,
        write: (s) async {
          await Future<void>.delayed(Duration.zero);
          if (fail) throw StateError('locked');
          raw = s;
        });
    await Future.wait([
      for (var i = 0; i < 12; i++)
        store.save(ConnectionProfile(
            name: '$i', provider: 'sftp', fields: {'host': 'nas'}))
    ]);
    expect((await store.getAll()).length, 12);
    fail = true;
    await expectLater(store.delete('0', 'sftp'), throwsStateError);
    fail = false;
    await store.delete('0', 'sftp');
    expect((await store.getAll()).length, 11);
  });
  group('scheduler', () {
    test('queued cancellation finishes its callback and never executes',
        () async {
      final q = TransferScheduler<Operation>(maxConcurrent: 1);
      addTearDown(q.dispose);
      final gate = Completer<void>(), done = Completer<Object?>();
      var ran = false;
      q.enqueue(ScheduledTransfer(
          id: '1', operation: Operation(), execute: () => gate.future));
      q.enqueue(ScheduledTransfer(
          id: '2',
          operation: Operation(),
          execute: () async {
            ran = true;
          },
          onDone: done.complete));
      q.cancel('2');
      expect(await done.future, isA<TransferCancelled>());
      expect(ran, isFalse);
      gate.complete();
    });
    test('cancellation interrupts exponential retry wait immediately',
        () async {
      final q = TransferScheduler<Operation>(
          maxConcurrent: 1, retryBaseDelay: const Duration(minutes: 1));
      addTearDown(q.dispose);
      final done = Completer<Object?>(), attempted = Completer<void>();
      var attempts = 0;
      final op = Operation();
      q.enqueue(ScheduledTransfer(
          id: '1',
          operation: op,
          execute: () async {
            attempts++;
            attempted.complete();
            throw const RemoteException('offline', retryable: true);
          },
          onDone: done.complete));
      await attempted.future;
      await Future<void>.delayed(Duration.zero);
      op.cancel();
      expect(await done.future.timeout(const Duration(seconds: 1)),
          isA<TransferCancelled>());
      expect(attempts, 1);
      expect(q.activeCount, 0);
    });
    test('security errors never retry, transient errors do', () async {
      final q = TransferScheduler<Operation>(
          retryBaseDelay: Duration.zero, maxRetries: 2);
      addTearDown(q.dispose);
      var security = 0, transient = 0;
      final done = Completer<Object?>(), done2 = Completer<Object?>();
      q.enqueue(ScheduledTransfer(
          id: '1',
          operation: Operation(),
          execute: () async {
            security++;
            throw SftpHostKeyException(pin);
          },
          onDone: done.complete));
      q.enqueue(ScheduledTransfer(
          id: '2',
          operation: Operation(),
          execute: () async {
            transient++;
            if (transient < 3) {
              throw const RemoteException('offline', retryable: true);
            }
          },
          onDone: done2.complete));
      expect(await done.future, isA<SftpHostKeyException>());
      expect(await done2.future, isNull);
      expect(security, 1);
      expect(transient, 3);
    });
    test('paused queued work waits, and cancel wakes it', () async {
      final q = TransferScheduler<Operation>();
      addTearDown(q.dispose);
      final done = Completer<Object?>();
      final op = Operation()..pause();
      var ran = false;
      q.enqueue(ScheduledTransfer(
          id: '1',
          operation: op,
          execute: () async {
            ran = true;
          },
          onDone: done.complete));
      await Future<void>.delayed(Duration.zero);
      expect(ran, isFalse);
      op.cancel();
      expect(await done.future, isA<TransferCancelled>());
    });
    test('per-provider limit allows another provider to make progress',
        () async {
      final q = TransferScheduler<Operation>(maxConcurrent: 2);
      addTearDown(q.dispose);
      q.setProviderLimit('slow', 1);
      final gate = Completer<void>();
      final order = <String>[];
      for (final row in [('a', 'slow'), ('b', 'slow'), ('c', 'fast')]) {
        q.enqueue(ScheduledTransfer(
            id: row.$1,
            operation: Operation(),
            providerName: row.$2,
            execute: () async {
              order.add(row.$1);
              await gate.future;
            }));
      }
      await Future<void>.delayed(Duration.zero);
      expect(order, ['a', 'c']);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(order, ['a', 'c', 'b']);
    });
  });
}
