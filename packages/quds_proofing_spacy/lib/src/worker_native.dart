import 'dart:async';
import 'dart:isolate';

import 'analysis.dart';
import 'backend.dart';
import 'bundle.dart';
import 'source_text.dart';
import 'transport.dart';

Future<SpacyTransport> startWorker({
  required SpacyBundle bundle,
  required SpacyBackendFactory backendFactory,
  required int maximumPendingRequests,
  required int maximumTextCodeUnits,
  required Duration startupTimeout,
  required Duration requestTimeout,
}) async {
  final worker = _NativeWorker(
    bundle,
    maximumPendingRequests,
    maximumTextCodeUnits,
    requestTimeout,
  );
  worker._ready.future.ignore();
  worker._stopped.future.ignore();
  worker._listen();
  try {
    await Isolate.spawn<_Boot>(
      _workerMain,
      _Boot(worker._replies.sendPort, bundle, backendFactory),
      onError: worker._errors.sendPort,
      onExit: worker._exits.sendPort,
      errorsAreFatal: true,
      debugName: 'quds-spacy-${bundle.language.code}-analysis',
    );
    worker._spawned = true;
    await worker._ready.future.timeout(startupTimeout);
    return worker;
  } on Object {
    // An initialization timeout must return to the caller. The worker retains
    // ownership until open returns, receives Stop, and releases its context.
    // Killing an isolate is not safe interruption of a synchronous FFI call.
    unawaited(worker.dispose());
    rethrow;
  }
}

final class _Pending {
  _Pending(this.request);
  final LinguisticAnalysisRequest request;
  final Completer<LinguisticAnalysisResult> completer = Completer();
  Timer? timer;
}

final class _NativeWorker implements SpacyTransport {
  _NativeWorker(
    this._bundle,
    this.maximumPendingRequests,
    this.maximumTextCodeUnits,
    this.requestTimeout,
  );
  final SpacyBundle _bundle;
  final int maximumPendingRequests;
  final int maximumTextCodeUnits;
  final Duration requestTimeout;
  final ReceivePort _replies = ReceivePort();
  final ReceivePort _errors = ReceivePort();
  final ReceivePort _exits = ReceivePort();
  final Completer<void> _ready = Completer();
  final Completer<void> _stopped = Completer();
  final Map<int, _Pending> _pending = {};
  final Map<String, int> _byKey = {};
  final Set<int> _waiting = {};
  final List<StreamSubscription<Object?>> _subscriptions = [];
  SendPort? _commands;
  SpacyBackendIdentity? _identity;
  int? _inFlight;
  int _nextId = 0;
  bool _spawned = false;
  bool _disposed = false;
  bool _closingPorts = false;

  @override
  SpacyBackendIdentity get identity => _identity!;

  void _listen() {
    _subscriptions.add(_replies.listen(_onReply));
    _subscriptions.add(
      _errors.listen((Object? raw) {
        // Do not relay native paths, document text or arbitrary exception payloads
        // to the UI. Detailed initialization errors are already bounded below.
        _fail('The local analysis worker failed.');
      }),
    );
    _subscriptions.add(
      _exits.listen((Object? _) {
        if (!_disposed) _fail('The local analysis worker exited unexpectedly.');
        unawaited(_closePorts());
      }),
    );
  }

  void _onReply(Object? raw) {
    switch (raw) {
      case _Ready():
        _commands = raw.commands;
        try {
          raw.identity.validate(_bundle);
          _identity = raw.identity;
          if (!_ready.isCompleted) _ready.complete();
          if (_disposed) _commands!.send(const _Stop());
        } on Object {
          _fail('The loaded analysis identity is unsupported.');
          _commands!.send(const _Stop());
        }
      case _InitFailed():
        _fail(raw.message);
      case _Reply():
        if (_inFlight != raw.id) {
          _fail('Invalid analysis worker reply.');
          _commands?.send(const _Stop());
          return;
        }
        // Only an actual reply releases this physical slot, including after a
        // caller has cancelled, timed out or replaced its snapshot.
        _inFlight = null;
        final pending = _remove(raw.id);
        if (pending != null) {
          final result = raw.result;
          if (!result.request.sameSnapshot(pending.request) ||
              (result.identity != null && result.identity != _identity) ||
              (result.isSuccess && result.identity != _identity)) {
            pending.completer.complete(
              _failure(
                pending.request,
                LinguisticAnalysisStatus.failed,
                'The analysis result does not match its request or runtime.',
              ),
            );
          } else {
            pending.completer.complete(result);
          }
        }
        _dispatch();
      case _Stopped():
        unawaited(_closePorts(raw.error));
      default:
        _fail('Invalid analysis worker protocol.');
        _commands?.send(const _Stop());
    }
  }

  LinguisticAnalysisResult _failure(
    LinguisticAnalysisRequest request,
    LinguisticAnalysisStatus status,
    String message,
  ) => LinguisticAnalysisResult.failure(
    request: request,
    status: status,
    message: message,
    identity: _identity,
  );

  @override
  Future<LinguisticAnalysisResult> analyze(LinguisticAnalysisRequest request) {
    if (_disposed || _commands == null) {
      return Future.value(
        _failure(
          request,
          LinguisticAnalysisStatus.unavailable,
          'Local analysis is unavailable.',
        ),
      );
    }
    // Admission occurs before coalescing so an invalid replacement cannot
    // cancel a previously valid request for the same source unit.
    if (!_bundle.acceptsLocale(request.locale)) {
      return Future.value(
        _failure(
          request,
          LinguisticAnalysisStatus.unsupported,
          _bundle.language == SpacyLanguage.german
              ? 'This analysis profile supports de-DE only.'
              : 'This analysis profile supports '
                    '${_bundle.language.displayName} text only.',
        ),
      );
    }
    if (request.text.length > maximumTextCodeUnits) {
      return Future.value(
        _failure(
          request,
          LinguisticAnalysisStatus.capacity,
          'The selected text exceeds the configured analysis limit.',
        ),
      );
    }
    try {
      SpacySourceText(request.text);
    } on FormatException catch (error) {
      return Future.value(
        _failure(request, LinguisticAnalysisStatus.failed, error.message),
      );
    }
    final previous = _byKey[request.key];
    if (previous != null) {
      _completeFailure(
        previous,
        LinguisticAnalysisStatus.stale,
        'A newer source snapshot superseded this analysis.',
      );
    }
    if (_pending.length >= maximumPendingRequests) {
      return Future.value(
        _failure(
          request,
          LinguisticAnalysisStatus.capacity,
          'The local analysis queue is full.',
        ),
      );
    }
    final id = ++_nextId;
    final pending = _Pending(request);
    _pending[id] = pending;
    _byKey[request.key] = id;
    _waiting.add(id);
    pending.timer = Timer(
      requestTimeout,
      () => _completeFailure(
        id,
        LinguisticAnalysisStatus.timeout,
        'Analysis exceeded the request deadline.',
      ),
    );
    _dispatch();
    return pending.completer.future;
  }

  _Pending? _remove(int id) {
    final pending = _pending.remove(id);
    _waiting.remove(id);
    pending?.timer?.cancel();
    if (pending != null && _byKey[pending.request.key] == id) {
      _byKey.remove(pending.request.key);
    }
    return pending;
  }

  void _completeFailure(
    int id,
    LinguisticAnalysisStatus status,
    String message,
  ) {
    final pending = _remove(id);
    if (pending != null) {
      pending.completer.complete(_failure(pending.request, status, message));
    }
  }

  @override
  void cancel(String key) {
    final id = _byKey[key];
    if (id != null) {
      _completeFailure(
        id,
        LinguisticAnalysisStatus.cancelled,
        'Analysis was cancelled.',
      );
    }
  }

  void _dispatch() {
    if (_disposed ||
        _commands == null ||
        _inFlight != null ||
        _waiting.isEmpty) {
      return;
    }
    final id = _waiting.first;
    _waiting.remove(id);
    _inFlight = id;
    _commands!.send(_Run(id, _pending[id]!.request));
  }

  void _fail(String message) {
    _disposed = true;
    if (!_ready.isCompleted) {
      _ready.completeError(SpacyUnavailableException(message));
    }
    for (final id in _pending.keys.toList()) {
      _completeFailure(id, LinguisticAnalysisStatus.unavailable, message);
    }
  }

  @override
  Future<void> dispose() {
    if (!_disposed) _fail('Local analysis was closed.');
    _commands?.send(const _Stop());
    if (!_spawned) unawaited(_closePorts());
    return _stopped.future;
  }

  Future<void> _closePorts([String? error]) async {
    if (_closingPorts) return;
    _closingPorts = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _replies.close();
    _errors.close();
    _exits.close();
    if (!_stopped.isCompleted) {
      if (error == null) {
        _stopped.complete();
      } else {
        _stopped.completeError(SpacyUnavailableException(error));
      }
    }
  }
}

final class _Boot {
  const _Boot(this.replies, this.bundle, this.factory);
  final SendPort replies;
  final SpacyBundle bundle;
  final SpacyBackendFactory factory;
}

final class _Ready {
  const _Ready(this.commands, this.identity);
  final SendPort commands;
  final SpacyBackendIdentity identity;
}

final class _InitFailed {
  const _InitFailed(this.message);
  final String message;
}

final class _Run {
  const _Run(this.id, this.request);
  final int id;
  final LinguisticAnalysisRequest request;
}

final class _Reply {
  const _Reply(this.id, this.result);
  final int id;
  final LinguisticAnalysisResult result;
}

final class _Stop {
  const _Stop();
}

final class _Stopped {
  const _Stopped([this.error]);
  final String? error;
}

Future<void> _workerMain(_Boot boot) async {
  SpacyBackend? backend;
  try {
    backend = await boot.factory.open(boot.bundle);
    backend.identity.validate(boot.bundle);
    _WorkerState(boot.replies, backend).listen();
  } on Object {
    try {
      await backend?.dispose();
    } on Object {
      /* Preserve init failure. */
    }
    boot.replies.send(
      const _InitFailed(
        'Cannot open the configured local spaCy runtime and model.',
      ),
    );
  }
}

final class _WorkerState {
  _WorkerState(this.replies, this.backend);
  final SendPort replies;
  final SpacyBackend backend;
  final ReceivePort commands = ReceivePort();
  StreamSubscription<Object?>? subscription;
  bool active = false;
  bool stopping = false;
  bool closing = false;

  void listen() {
    subscription = commands.listen((Object? raw) {
      switch (raw) {
        case _Run():
          if (active || stopping) {
            replies.send(
              _Reply(
                raw.id,
                LinguisticAnalysisResult.failure(
                  request: raw.request,
                  status: LinguisticAnalysisStatus.failed,
                  message: 'Invalid analysis dispatch.',
                  identity: backend.identity,
                ),
              ),
            );
          } else {
            active = true;
            unawaited(_run(raw));
          }
        case _Stop():
          stopping = true;
          if (!active) unawaited(_close());
        default:
          stopping = true;
          if (!active) unawaited(_close());
      }
    });
    replies.send(_Ready(commands.sendPort, backend.identity));
  }

  Future<void> _run(_Run task) async {
    try {
      final result = await backend.analyze(task.request);
      replies.send(_Reply(task.id, result));
    } on Object {
      replies.send(
        _Reply(
          task.id,
          LinguisticAnalysisResult.failure(
            request: task.request,
            status: LinguisticAnalysisStatus.failed,
            message: 'Local analysis failed.',
            identity: backend.identity,
          ),
        ),
      );
    } finally {
      active = false;
      if (stopping) await _close();
    }
  }

  Future<void> _close() async {
    if (closing) return;
    closing = true;
    String? failure;
    try {
      await backend.dispose();
    } on Object {
      failure = 'The local analysis backend could not close cleanly.';
    }
    await subscription?.cancel();
    commands.close();
    replies.send(_Stopped(failure));
  }
}
