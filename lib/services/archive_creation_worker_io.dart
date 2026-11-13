import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'archive_creation_service.dart';
import 'archive_creation_worker.dart';
import 'file_operation_backend.dart';
import 'local_file_service.dart';
import 'local_file_service_native.dart' show DesktopFileService;

Future<ArchiveCreationWorker> startArchiveCreationWorker({
  required LocalFileService local,
  required List<FileItem> files,
  required String destinationDirectory,
  required ArchiveCreationOptions options,
  required void Function(ArchiveCreationProgress) onProgress,
  required Future<void> Function(ArchiveCreationPrepared) onPrepared,
}) async {
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
    throw UnsupportedError(
      'Background archive creation is available on desktop only.',
    );
  }
  options.validate();
  if (files.isEmpty) {
    throw const ArchiveCreationException(ArchiveCreationError.emptySelection);
  }
  if (files.length > 5000) {
    throw const ArchiveCreationException(ArchiveCreationError.tooLarge);
  }
  bool validPath(String path) =>
      path.length <= 16384 &&
      !path.contains('\u0000') &&
      p.isAbsolute(path) &&
      p.normalize(path) == path;
  if (!validPath(destinationDirectory)) {
    throw const ArchiveCreationException(
      ArchiveCreationError.invalidDestination,
    );
  }
  final scopes = <String>{};
  final selected = <Map<String, Object?>>[];
  for (final file in files) {
    final path = file.path;
    if (path == null || !validPath(path)) {
      throw ArchiveCreationException(
        ArchiveCreationError.sourceUnavailable,
        path,
      );
    }
    if (!file.isFolder) scopes.add(p.dirname(path));
    scopes.add(path);
    // Deliberately exclude XFile handles and arbitrary provider metadata.
    selected.add(
      Map.unmodifiable({
        'name': file.name,
        'path': path,
        'uuid': file.uuid,
        'folder': file.isFolder,
        'size': file.size,
        'modified': file.updatedAt?.microsecondsSinceEpoch,
        'modifiedUtc': file.updatedAt?.isUtc,
        'link': file.isSymlink,
      }),
    );
  }
  scopes.add(destinationDirectory);
  final worker = _NativeArchiveCreationWorker(
    local: local,
    scopes: List.unmodifiable(scopes),
    request: Map.unmodifiable({
      'files': List.unmodifiable(selected),
      'directory': destinationDirectory,
      'name': options.name,
      'format': options.format.name,
      'compression': options.compression.name,
      'password': options.password,
      'encryptNames': options.encryptNames,
    }),
    onProgress: onProgress,
    onPrepared: onPrepared,
  );
  worker.start();
  await worker.started;
  return worker;
}

class _NativeArchiveCreationWorker implements ArchiveCreationWorker {
  _NativeArchiveCreationWorker({
    required this.local,
    required this.scopes,
    required Map<String, Object?> request,
    required this.onProgress,
    required this.onPrepared,
    // The public named argument describes the ephemeral request; retain it only
    // until the child receives its own immutable copy.
    // ignore: prefer_initializing_formals
  }) : _request = request {
    _events.listen(_onEvent);
    // Startup may fail before a caller can obtain this worker. Its result is
    // still observable by callers, without a second unhandled startup error.
    _result.future.ignore();
  }

  final LocalFileService local;
  final List<String> scopes;
  final void Function(ArchiveCreationProgress) onProgress;
  final Future<void> Function(ArchiveCreationPrepared) onPrepared;
  Map<String, Object?>? _request;
  final ReceivePort _events = ReceivePort();
  final Completer<void> _started = Completer<void>();
  final Completer<SendPort?> _ready = Completer<SendPort?>();
  final Completer<void> _exited = Completer<void>();
  final Completer<ArchiveCreationResult> _result =
      Completer<ArchiveCreationResult>();
  final Map<String, Object?> _identities = {};
  Isolate? _isolate;
  SendPort? _commands;
  Capability? _pauseCapability;
  late final Future<void> _lifetime;
  Future<void>? _closeFuture;
  Future<void>? _progressTask;
  Future<void>? _preparedTask;
  ArchiveCreationProgress? _pendingProgress;
  ArchiveCreationResult? _reportedResult;
  Object? _failure;
  StackTrace? _failureStack;
  bool _cancelled = false;
  bool _receivedTerminal = false;

  Future<void> get started => _started.future;
  @override
  Future<ArchiveCreationResult> get result => _result.future;

  void start() {
    _lifetime = _runScoped();
  }

  Future<void> _runScoped() async {
    try {
      await _holdScopes(0, () async {
        final identity = local;
        if (identity is LocalFileSourceIdentity) {
          for (final path in scopes) {
            _identities[path] = (identity as LocalFileSourceIdentity)
                .sourceIdentityForPath(path);
          }
        }
        await _validateAccess();
        _isolate = await Isolate.spawn<SendPort>(
          _runArchiveCreationWorker,
          _events.sendPort,
          onError: _events.sendPort,
          onExit: _events.sendPort,
          errorsAreFatal: true,
          debugName: 'Archive creation',
        );
        try {
          _commands = await _ready.future;
          if (_commands == null) {
            throw StateError('The archive worker could not start.');
          }
          _commands!.send(('start', _request));
          _request = null;
          _started.complete();
          await _exited.future;
          // These callbacks are bounded to the current progress and prepared
          // receipt; no security scope ends while worker I/O is still alive.
          await _progressTask;
          await _preparedTask;
        } finally {
          if (!_exited.isCompleted) {
            // Keep this wait inside all acquired scopes, including unexpected
            // failures between spawning and receiving the startup handshake.
            cancel();
            await _exited.future;
          }
        }
      });
    } catch (error, stack) {
      _fail(error, stack);
      if (_isolate != null && !_exited.isCompleted) {
        cancel();
        await _exited.future;
      }
    } finally {
      _request = null;
      _events.close();
      if (!_started.isCompleted) {
        _started.completeError(
          _failure ?? StateError('The archive worker could not start.'),
          _failureStack,
        );
      }
      final completed = _reportedResult;
      if (completed != null) {
        // Publication is never reclassified as a rollback by a late cancel,
        // grant check, or best-effort access-scope cleanup failure.
        _result.complete(completed);
      } else {
        _result.completeError(
          _failure ?? StateError('The archive worker exited unexpectedly.'),
          _failureStack,
        );
      }
    }
  }

  Future<void> _holdScopes(int index, Future<void> Function() action) async {
    if (index == scopes.length) return action();
    await local.withFileOperationAccess(scopes[index], () async {
      // A service may invoke its callback synchronously. Yield between nested
      // grants so a large selection does not recurse on the native stack.
      await Future<void>.value();
      await _holdScopes(index + 1, action);
    });
  }

  Future<void> _validateAccess() async {
    for (final path in scopes) {
      if (_cancelled) {
        throw const ArchiveCreationException(ArchiveCreationError.cancelled);
      }
      final identity = local;
      if (identity is LocalFileSourceIdentity &&
          (identity as LocalFileSourceIdentity).sourceIdentityForPath(path) !=
              _identities[path]) {
        throw ArchiveCreationException(
          ArchiveCreationError.sourceUnavailable,
          path,
        );
      }
      if (!await local.hasAccessToPath(path)) {
        throw ArchiveCreationException(
          ArchiveCreationError.sourceUnavailable,
          path,
        );
      }
    }
  }

  void _onEvent(dynamic message) {
    if (message is SendPort) {
      _commands = message;
      if (!_ready.isCompleted) _ready.complete(message);
    } else if (message case (
      'progress',
      final String phase,
      final int completed,
      final int total,
      final String path,
    )) {
      if (_cancelled || _receivedTerminal) return;
      _pendingProgress = ArchiveCreationProgress(
        ArchiveCreationPhase.values.byName(phase),
        completed,
        total,
        path,
      );
      _progressTask ??= _drainProgress();
    } else if (message case (
      'prepared',
      final String path,
      final int entries,
      final int bytes,
      final String digest,
    )) {
      if (_preparedTask != null) {
        _fail(StateError('The archive worker repeated its prepared receipt.'));
        cancel();
        return;
      }
      _preparedTask = _prepare(
        ArchiveCreationPrepared(path, entries, bytes, digest),
      );
    } else if (message case (
      'result',
      final String path,
      final int entries,
      final int bytes,
    )) {
      _reportedResult = ArchiveCreationResult(path, entries, bytes);
      _receivedTerminal = true;
    } else if (message case (
      'failure',
      final String? code,
      final String? path,
      final String error,
      final String stack,
    )) {
      _receivedTerminal = true;
      _fail(
        code == null
            ? RemoteError(error, stack)
            : ArchiveCreationException(
                ArchiveCreationError.values.byName(code),
                path,
              ),
        StackTrace.fromString(stack),
      );
    } else if (message is List && message.length == 2) {
      _fail(
        RemoteError(message[0].toString(), message[1].toString()),
        StackTrace.fromString(message[1].toString()),
      );
    } else if (message == null) {
      if (!_receivedTerminal) {
        _fail(StateError('The archive worker exited unexpectedly.'));
      }
      if (!_ready.isCompleted) _ready.complete(null);
      if (!_exited.isCompleted) _exited.complete();
    }
  }

  Future<void> _drainProgress() async {
    try {
      while (_pendingProgress != null && !_cancelled) {
        final progress = _pendingProgress!;
        _pendingProgress = null;
        await _validateAccess();
        if (!_cancelled) onProgress(progress);
      }
    } catch (error, stack) {
      _fail(error, stack);
      cancel();
    } finally {
      _pendingProgress = null;
      _progressTask = null;
    }
  }

  Future<void> _prepare(ArchiveCreationPrepared prepared) async {
    try {
      await _progressTask;
      await _validateAccess();
      await onPrepared(prepared);
      // Persistence itself may have awaited user code or disk I/O. Recheck
      // access and cancellation before granting publication authority.
      await _validateAccess();
      _commands?.send(('prepared', true));
    } catch (error, stack) {
      _fail(error, stack);
      cancel();
      _commands?.send(('prepared', false));
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    _failure ??= error;
    _failureStack ??= stack ?? StackTrace.current;
  }

  @override
  void cancel() {
    if (_exited.isCompleted) return;
    _cancelled = true;
    resume();
    _commands?.send('cancel');
  }

  @override
  void pause() {
    if (_cancelled ||
        _receivedTerminal ||
        _exited.isCompleted ||
        _pauseCapability != null) {
      return;
    }
    _pauseCapability = _isolate?.pause();
  }

  @override
  void resume() {
    final capability = _pauseCapability;
    _pauseCapability = null;
    if (capability != null) _isolate?.resume(capability);
  }

  @override
  Future<void> close() => _closeFuture ??= _shutdown();

  Future<void> _shutdown() async {
    cancel();
    await _lifetime;
  }
}

/// The child has no UI callbacks, bookmark service, picker, or root messenger.
/// DesktopFileService reaches native I/O only; parent-held grants cover it.
void _runArchiveCreationWorker(SendPort events) {
  final commands = ReceivePort();
  var cancelled = false;
  var started = false;
  Completer<bool>? publication;
  events.send(commands.sendPort);
  commands.listen((dynamic command) async {
    if (command == 'cancel') {
      cancelled = true;
      final pending = publication;
      if (pending != null && !pending.isCompleted) pending.complete(false);
      if (!started) commands.close();
      return;
    }
    if (command case ('prepared', final bool allowed)) {
      final pending = publication;
      if (pending != null && !pending.isCompleted) pending.complete(allowed);
      return;
    }
    if (command case ('start', final Map request)) {
      if (started) return;
      started = true;
      try {
        final files = <FileItem>[
          for (final item in request['files'] as List)
            FileItem(
              name: item['name'] as String,
              path: item['path'] as String,
              uuid: item['uuid'] as String?,
              isFolder: item['folder'] as bool,
              size: item['size'] as int?,
              updatedAt: item['modified'] == null
                  ? null
                  : DateTime.fromMicrosecondsSinceEpoch(
                      item['modified'] as int,
                      isUtc: item['modifiedUtc'] as bool,
                    ),
              isSymlink: item['link'] as bool?,
            ),
        ];
        final options = ArchiveCreationOptions(
          name: request['name'] as String,
          format: ArchiveCreationFormat.values.byName(
            request['format'] as String,
          ),
          compression: ArchiveCreationCompression.values.byName(
            request['compression'] as String,
          ),
          password: request['password'] as String?,
          encryptNames: request['encryptNames'] as bool,
        );
        final backend = LocalOperationBackend(
          DesktopFileService(),
          isCurrent: () => !cancelled,
        );
        ArchiveCreationPhase? previousPhase;
        final progressClock = Stopwatch()..start();
        final result = await const ArchiveCreationService().create(
          source: backend,
          destination: backend,
          files: files,
          destinationDirectory: request['directory'] as String,
          options: options,
          isCancelled: () => cancelled,
          onProgress: (progress) {
            // Coalesce fine-grained byte reports before crossing isolates.
            if (progress.phase == previousPhase &&
                progressClock.elapsedMilliseconds < 50 &&
                !(progress.total > 0 && progress.completed == progress.total)) {
              return;
            }
            previousPhase = progress.phase;
            progressClock.reset();
            events.send((
              'progress',
              progress.phase.name,
              progress.completed,
              progress.total,
              progress.path,
            ));
          },
          onPrepared: (prepared) async {
            if (cancelled) {
              throw const ArchiveCreationException(
                ArchiveCreationError.cancelled,
              );
            }
            final approved = Completer<bool>();
            publication = approved;
            events.send((
              'prepared',
              prepared.path,
              prepared.entryCount,
              prepared.bytes,
              prepared.sha256,
            ));
            if (!await approved.future || cancelled) {
              throw const ArchiveCreationException(
                ArchiveCreationError.cancelled,
              );
            }
          },
        );
        events.send(('result', result.path, result.entryCount, result.bytes));
      } catch (error, stack) {
        // Cancellation can race the creator's initial stat, before its spool
        // cleanup try/catch begins. Keep the worker API's cancellation result
        // consistent with cancellations during packing and staged verification.
        final failure = cancelled
            ? const ArchiveCreationException(ArchiveCreationError.cancelled)
            : error;
        events.send((
          'failure',
          failure is ArchiveCreationException ? failure.code.name : null,
          failure is ArchiveCreationException ? failure.path : null,
          failure.toString(),
          stack.toString(),
        ));
      } finally {
        commands.close();
      }
    }
  });
}
