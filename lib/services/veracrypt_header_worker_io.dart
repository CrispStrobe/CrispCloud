// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'archive_types.dart';
import 'veracrypt_service.dart';

/// A test observer of the worker's acknowledgement, before its derivation.
/// No credentials or request metadata are exposed. The public facade does not
/// export this observer.
void Function()? debugOnVeraCryptHeaderWorkerStarted;

final _scheduler = _HeaderScheduler();

/// Derive one header in an isolated worker, with one active KDF at a time.
///
/// Cancellation is checked every 25 ms, including while waiting in the queue.
/// A cancelled running worker is killed; its slot remains occupied until the
/// VM reports its exit, so a replacement cannot overlap its allocation.
///
/// The caller retains ownership of [header] and [options] and must keep them
/// stable until this future completes. Sending the request creates a worker
/// copy; its keyfile buffers are cleared before a normal result or error is
/// transferred. A killed isolate cannot guarantee managed-memory erasure.
Future<VeraCryptUnlockedVolume?> unlockVeraCryptHeaderAsync(
  Uint8List header,
  String password, {
  required VeraCryptUnlockOptions options,
  required int containerSizeBytes,
  bool Function()? isCancelled,
}) => _scheduler.schedule(
  _HeaderRequest(header, password, options, containerSizeBytes),
  isCancelled,
);

class _HeaderRequest {
  const _HeaderRequest(this.header, this.password, this.options, this.size);

  final Uint8List header;
  final String password;
  final VeraCryptUnlockOptions options;
  final int size;

  void clearKeyfiles() {
    for (final bytes in options.keyfiles) {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}

class _WorkerStarted {
  const _WorkerStarted();
}

class _WorkerResult {
  const _WorkerResult(this.volume);
  final VeraCryptUnlockedVolume? volume;
}

class _WorkerFailure {
  const _WorkerFailure(this.error, this.stack);
  final Object error;
  final String stack;
}

/// The initial handshake deliberately carries no request. The parent must own
/// the killable Isolate handle before it authorizes any KDF allocation.
Future<void> _runHeaderWorker(SendPort owner) async {
  final commands = ReceivePort();
  owner.send(commands.sendPort);
  final request = await commands.first as _HeaderRequest;
  Object result;
  try {
    owner.send(const _WorkerStarted());
    result = _WorkerResult(
      VeraCryptService.unlockHeader(
        request.header,
        request.password,
        options: request.options,
        containerSizeBytes: request.size,
      ),
    );
  } catch (error, stack) {
    // These are ordinary sendable Dart values. In particular, invalid options
    // and resource exceptions retain their type instead of becoming strings.
    result = _WorkerFailure(error, stack.toString());
  } finally {
    request.clearKeyfiles();
    commands.close();
  }
  // Transfer ownership without leaving another reachable copy of volume keys
  // in a live worker. Cleanup has already run: Isolate.exit does not unwind.
  Isolate.exit(owner, result);
}

class _Job {
  _Job(this.request, this.isCancelled);

  final _HeaderRequest request;
  final bool Function()? isCancelled;
  final completer = Completer<VeraCryptUnlockedVolume?>();
  Isolate? isolate;
  ReceivePort? results;
  StreamSubscription<dynamic>? subscription;
  SendPort? commands;
  bool dispatched = false;
  bool cancelled = false;
  bool retired = false;

  void fail(Object error, StackTrace stack) {
    if (!completer.isCompleted) completer.completeError(error, stack);
  }
}

class _HeaderScheduler {
  final _pending = Queue<_Job>();
  _Job? _active;
  Timer? _poll;

  Future<VeraCryptUnlockedVolume?> schedule(
    _HeaderRequest request,
    bool Function()? isCancelled,
  ) {
    final job = _Job(request, isCancelled);
    final cancellation = _cancellation(job);
    if (cancellation != null) {
      job.fail(cancellation.$1, cancellation.$2);
      return job.completer.future;
    }
    _pending.add(job);
    _poll ??= Timer.periodic(const Duration(milliseconds: 25), (_) => _tick());
    _pump();
    return job.completer.future;
  }

  (Object, StackTrace)? _cancellation(_Job job) {
    try {
      if (job.isCancelled?.call() ?? false) {
        return (
          const ArchiveViewException('Container opening was cancelled.'),
          StackTrace.current,
        );
      }
    } catch (error, stack) {
      return (error, stack);
    }
    return null;
  }

  void _tick() {
    for (final job in _pending.toList(growable: false)) {
      final cancellation = _cancellation(job);
      if (cancellation != null) {
        _pending.remove(job);
        job.fail(cancellation.$1, cancellation.$2);
      }
    }
    final active = _active;
    if (active != null && !active.cancelled) {
      final cancellation = _cancellation(active);
      if (cancellation != null) {
        _cancelActive(active, cancellation.$1, cancellation.$2);
      }
    }
    _pump();
  }

  void _pump() {
    if (_active != null) return;
    while (_pending.isNotEmpty) {
      final job = _pending.removeFirst();
      final cancellation = _cancellation(job);
      if (cancellation != null) {
        job.fail(cancellation.$1, cancellation.$2);
        continue;
      }
      _active = job;
      unawaited(_start(job));
      return;
    }
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _start(_Job job) async {
    final results = ReceivePort();
    job.results = results;
    job.subscription = results.listen((message) => _message(job, message));
    try {
      final isolate = await Isolate.spawn<SendPort>(
        _runHeaderWorker,
        results.sendPort,
        onError: results.sendPort,
        onExit: results.sendPort,
        errorsAreFatal: true,
        debugName: 'CrispCloud container header',
      );
      job.isolate = isolate;
      if (job.retired || job.cancelled) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _dispatch(job);
      }
    } catch (error, stack) {
      job.fail(error, stack);
      _retire(job);
    }
  }

  void _dispatch(_Job job) {
    if (job.retired ||
        job.cancelled ||
        job.dispatched ||
        job.isolate == null ||
        job.commands == null) {
      return;
    }
    final cancellation = _cancellation(job);
    if (cancellation != null) {
      _cancelActive(job, cancellation.$1, cancellation.$2);
      return;
    }
    try {
      job.commands!.send(job.request);
      job.dispatched = true;
    } catch (error, stack) {
      _cancelActive(job, error, stack);
    }
  }

  void _cancelActive(_Job job, Object error, StackTrace stack) {
    job.cancelled = true;
    job.fail(error, stack);
    job.isolate?.kill(priority: Isolate.immediate);
    // Keep the active slot until onExit; a pending spawn also has to return
    // its handle and be killed before the next worker is authorized.
  }

  void _message(_Job job, Object? message) {
    if (job.retired) return;
    if (message is SendPort) {
      job.commands = message;
      _dispatch(job);
    } else if (message is _WorkerStarted) {
      if (job.cancelled) return;
      try {
        debugOnVeraCryptHeaderWorkerStarted?.call();
      } catch (error, stack) {
        _cancelActive(job, error, stack);
      }
    } else if (message is _WorkerResult) {
      final cancellation = job.cancelled ? null : _cancellation(job);
      if (job.cancelled || cancellation != null) {
        message.volume?.dispose();
        if (cancellation != null) {
          job.fail(cancellation.$1, cancellation.$2);
        }
      } else {
        job.completer.complete(message.volume);
      }
      _retire(job);
    } else if (message is _WorkerFailure) {
      job.fail(message.error, StackTrace.fromString(message.stack));
      _retire(job);
    } else if (message == null) {
      job.fail(
        StateError('The container header worker exited without a result.'),
        StackTrace.current,
      );
      _retire(job);
    } else if (message is List && message.length == 2) {
      // VM errors that occur outside the worker's guarded derivation.
      job.fail(
        RemoteError('${message[0]}', '${message[1]}'),
        StackTrace.fromString('${message[1]}'),
      );
      _retire(job);
    }
  }

  void _retire(_Job job) {
    if (job.retired) return;
    job.retired = true;
    job.results?.close();
    unawaited(job.subscription?.cancel());
    if (identical(_active, job)) _active = null;
    _pump();
  }
}
