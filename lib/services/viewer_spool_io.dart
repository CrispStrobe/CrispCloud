import 'dart:async';
import 'dart:io';

import '../models/file_item.dart';
import 'file_operation_service.dart';
import 'log_service.dart';

const _log = Log('ViewerSpool');
const _revisionKeys = [
  'etag',
  'eTag',
  'version',
  'versionId',
  'revision',
  'rev',
  'cTag',
];

class ViewerSpool {
  ViewerSpool._(this._directory, this.path);
  final Directory _directory;
  final String path;
  bool _closed = false;
  Future<void>? _closing;

  /// Concurrent callers share cleanup. A failed deletion remains retryable.
  Future<void> close() {
    if (_closed) return Future<void>.value();
    return _closing ??= _remove().whenComplete(() => _closing = null);
  }

  Future<void> _remove() async {
    if (await _directory.exists()) await _directory.delete(recursive: true);
    _closed = true;
  }
}

/// Streams a remote file into an owned temporary directory without retaining
/// a whole-file byte array. Metadata is checked before and after the read; this
/// does not promise an immutable remote snapshot.
///
/// Both metadata waits and pending stream reads observe cancellation, source
/// loss and deadlines. Only nonempty bytes written to disk reset inactivity.
/// Source cancellation is requested but its acknowledgement cannot hold the
/// caller open. Native filesystem operations still complete before their owned
/// handles and incomplete directory are released.
///
/// [clock], [createTimer] and [temporaryRoot] allow isolated deterministic tests.
/// A supplied root is only a parent: cleanup owns the new child directory.
Future<ViewerSpool> createViewerSpool(
  FileOperationBackend source,
  FileItem file, {
  int maxBytes = 2 * 1024 * 1024 * 1024,
  bool Function()? isCancelled,
  void Function(int bytes, int? total)? onProgress,
  Duration overallTimeout = const Duration(hours: 6),
  Duration inactivityTimeout = const Duration(minutes: 2),
  Duration Function()? clock,
  Timer Function(Duration, void Function())? createTimer,
  String? temporaryRoot,
}) async {
  if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  if (overallTimeout <= Duration.zero) {
    throw ArgumentError.value(overallTimeout, 'overallTimeout');
  }
  if (inactivityTimeout <= Duration.zero) {
    throw ArgumentError.value(inactivityTimeout, 'inactivityTimeout');
  }
  final path = file.path;
  if (path == null || file.isFolder || file.isSymlink == true) {
    throw StateError('Choose a regular file to prepare for viewing.');
  }

  final guard = _SpoolGuard(
    source,
    isCancelled,
    overallTimeout: overallTimeout,
    inactivityTimeout: inactivityTimeout,
    clock: clock,
    createTimer: createTimer,
  );
  Directory? directory;
  RandomAccessFile? output;
  StreamIterator<List<int>>? input;
  var inputCancelled = false;
  var complete = false;

  void cancelInput() {
    final active = input;
    if (active == null || inputCancelled) return;
    inputCancelled = true;
    try {
      unawaited(
        active.cancel().then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {
            // Provider error text can contain authenticated transport details.
            _log.warn('The viewer source did not confirm stream cleanup.');
          },
        ),
      );
    } catch (_) {
      _log.warn('The viewer source did not confirm stream cleanup.');
    }
  }

  guard.onStop = cancelInput;
  try {
    final found = await guard.wait(() => source.stat(path));
    if (found == null || found.isFolder || found.isSymlink == true) {
      throw StateError(
        'The viewed file is missing or no longer a regular file.',
      );
    }
    if (file.uuid != null && found.uuid != file.uuid) {
      throw StateError('A different file now occupies the viewed path.');
    }
    final current = _captureFile(found);
    if ((current.size ?? 0) > maxBytes) {
      throw StateError(
        'Remote viewer temporary copies are limited to ${maxBytes ~/ (1024 * 1024)} MiB. Download the file to view it locally.',
      );
    }
    final parent = temporaryRoot == null
        ? Directory.systemTemp
        : Directory(temporaryRoot);
    directory = await parent.createTemp('crisp-viewer-');
    guard.check();
    final suffix = RegExp(r'^[A-Za-z0-9]{1,12}$').hasMatch(file.extension)
        ? '.${file.extension}'
        : '';
    final outputPath = '${directory.path}/content$suffix';
    output = await File(outputPath).open(mode: FileMode.write);
    guard.check();
    input = StreamIterator(_ownedInput(source.readFile(current)));
    var received = 0;
    while (await guard.wait(input.moveNext)) {
      guard.check();
      final chunk = input.current;
      if (chunk.isEmpty) {
        // A source emitting only empty chunks must still yield to cancellation.
        await Future<void>.delayed(Duration.zero);
        guard.check();
        continue;
      }
      if (chunk.length > maxBytes - received) {
        throw StateError('Viewer temporary copy limit exceeded.');
      }
      await output.writeFrom(chunk);
      // Await the file write before requesting another source chunk. A final
      // flush is enough for this temporary copy; each chunk needs no fsync.
      guard.progress();
      received += chunk.length;
      onProgress?.call(received, current.size);
      guard.check();
    }
    guard.check();
    await output.flush();
    guard.check();
    await output.close();
    output = null;
    guard.check();

    final after = await guard.wait(() => source.stat(path));
    if (!_sameMetadata(current, after) ||
        (current.size != null && received != current.size)) {
      throw StateError(
        'The remote file changed while preparing the viewer. Reload it.',
      );
    }
    guard.check();
    complete = true;
    return ViewerSpool._(directory, outputPath);
  } finally {
    guard.dispose();
    cancelInput();
    if (!complete) {
      try {
        await output?.close();
      } catch (_) {
        _log.warn('The partial viewer file did not confirm handle cleanup.');
      }
      if (directory != null) {
        try {
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        } catch (_) {
          // Retain the owned local location for manual cleanup, not the raw
          // exception or any remote account/path/transport details.
          _log.warn(
            'Could not remove the partial viewer directory: ${directory.path}',
          );
        }
      }
    }
  }
}

/// StreamIterator automatically cancels on error and can delay the error until
/// a provider acknowledges cancellation. Own that upstream subscription here so
/// its error and backpressure survive without waiting for provider cleanup.
Stream<List<int>> _ownedInput(Stream<List<int>> source) {
  StreamSubscription<List<int>>? subscription;
  var stopped = false;
  late StreamController<List<int>> output;

  void stop() {
    if (stopped) return;
    stopped = true;
    if (!output.isClosed) unawaited(output.close());
    try {
      final pending = subscription?.cancel();
      if (pending != null) {
        unawaited(
          pending.then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {
              _log.warn('The viewer source did not confirm stream cleanup.');
            },
          ),
        );
      }
    } catch (_) {
      _log.warn('The viewer source did not confirm stream cleanup.');
    }
  }

  output = StreamController<List<int>>(
    sync: true,
    onListen: () {
      if (stopped) return;
      try {
        subscription = source.listen(
          (chunk) {
            if (!stopped) output.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            if (!stopped) output.addError(error, stack);
          },
          onDone: () {
            if (!stopped && !output.isClosed) unawaited(output.close());
          },
          cancelOnError: false,
        );
        if (output.isPaused) subscription!.pause();
      } catch (error, stack) {
        if (!stopped) output.addError(error, stack);
      }
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: stop,
  );
  return output.stream;
}

FileItem _captureFile(FileItem file) {
  final metadata = Map<String, dynamic>.of(file.metadata ?? const {});
  for (final key in _revisionKeys) {
    final value = metadata[key];
    if (value != null && value is! String && value is! num && value is! bool) {
      throw StateError('The file version metadata cannot be captured safely.');
    }
  }
  return file.copyWith(metadata: Map<String, dynamic>.unmodifiable(metadata));
}

bool _sameMetadata(FileItem before, FileItem? after) =>
    after != null &&
    !after.isFolder &&
    after.isSymlink != true &&
    before.uuid == after.uuid &&
    before.storageId == after.storageId &&
    before.size == after.size &&
    before.updatedAt == after.updatedAt &&
    _revisionKeys.every((key) => before.metadata?[key] == after.metadata?[key]);

/// A stopped wait releases its listener immediately. Repeated chunk waits do
/// not accumulate listeners on a never-completed cancellation Future.
class _SpoolGuard {
  _SpoolGuard(
    this.source,
    this.cancelled, {
    required this.overallTimeout,
    required this.inactivityTimeout,
    Duration Function()? clock,
    Timer Function(Duration, void Function())? createTimer,
  }) : _clock = clock ?? _monotonicClock(),
       _createTimer = createTimer ?? Timer.new {
    _started = _lastProgress = _clock();
    check();
    _scheduleOverall();
    _scheduleInactivity();
    _schedulePoll();
  }

  final FileOperationBackend source;
  final bool Function()? cancelled;
  final Duration overallTimeout, inactivityTimeout;
  final Duration Function() _clock;
  final Timer Function(Duration, void Function()) _createTimer;
  final _waiters = <void Function()>{};
  late final Duration _started;
  late Duration _lastProgress;
  Timer? _overallTimer, _inactivityTimer, _pollTimer;
  Object? _failure;
  StackTrace? _failureStack;
  bool _disposed = false;
  void Function()? onStop;

  static Duration Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  void check() {
    if (_failure != null) {
      Error.throwWithStackTrace(_failure!, _failureStack!);
    }
    try {
      if (!source.isCurrent) {
        throw StateError('The original viewer source changed.');
      }
      if (cancelled?.call() ?? false) {
        throw StateError('Viewer download cancelled.');
      }
      final now = _clock();
      if (now - _started >= overallTimeout) {
        throw TimeoutException(
          'Viewer preparation exceeded its overall time limit.',
          overallTimeout,
        );
      }
      if (now - _lastProgress >= inactivityTimeout) {
        throw TimeoutException(
          'Viewer preparation stopped making progress.',
          inactivityTimeout,
        );
      }
    } catch (error, stack) {
      _stop(error, stack);
      rethrow;
    }
  }

  void _stop(Object error, StackTrace stack) {
    if (_failure != null || _disposed) return;
    _failure = error;
    _failureStack = stack;
    _cancelTimers();
    onStop?.call();
    for (final waiter in _waiters.toList()) {
      waiter();
    }
  }

  bool _checkTimer() {
    if (_disposed || _failure != null) return false;
    try {
      check();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _scheduleOverall() {
    _overallTimer = _createTimer(overallTimeout - (_clock() - _started), () {
      if (_checkTimer()) _scheduleOverall();
    });
  }

  void _scheduleInactivity() {
    _inactivityTimer?.cancel();
    _inactivityTimer = _createTimer(
      inactivityTimeout - (_clock() - _lastProgress),
      () {
        if (_checkTimer()) _scheduleInactivity();
      },
    );
  }

  void _schedulePoll() {
    _pollTimer = _createTimer(const Duration(milliseconds: 50), () {
      if (_checkTimer()) _schedulePoll();
    });
  }

  void progress() {
    check();
    _lastProgress = _clock();
    _scheduleInactivity();
  }

  Future<T> wait<T>(Future<T> Function() action) {
    check();
    final completed = Completer<T>();
    void stopped() {
      _waiters.remove(stopped);
      if (!completed.isCompleted) {
        completed.completeError(_failure!, _failureStack!);
      }
    }

    _waiters.add(stopped);
    unawaited(
      Future<T>.sync(action).then<void>(
        (value) {
          _waiters.remove(stopped);
          if (completed.isCompleted) return;
          try {
            check();
            completed.complete(value);
          } catch (error, stack) {
            if (!completed.isCompleted) completed.completeError(error, stack);
          }
        },
        onError: (Object error, StackTrace stack) {
          _waiters.remove(stopped);
          if (completed.isCompleted) return;
          try {
            check();
            completed.completeError(error, stack);
          } catch (stopped, stoppedStack) {
            if (!completed.isCompleted) {
              completed.completeError(stopped, stoppedStack);
            }
          }
        },
      ),
    );
    return completed.future;
  }

  void _cancelTimers() {
    _overallTimer?.cancel();
    _inactivityTimer?.cancel();
    _pollTimer?.cancel();
  }

  void dispose() {
    _disposed = true;
    _cancelTimers();
    onStop = null;
  }
}
