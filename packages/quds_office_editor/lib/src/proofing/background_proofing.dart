import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:quds_office_engine/quds_office_engine.dart';

/// Native editors share two lazy workers: one owns the German dictionary,
/// the other runs writing rules. Web uses the cooperative Dart providers.
OfficeProofingService defaultWordProofingService(
  OfficeProofingVocabulary vocabulary,
) {
  final providers = <OfficeProofingProvider>[
    GermanWritingRulesProvider(),
    GermanSpellingProvider(vocabulary: vocabulary),
    ArabicWritingRulesProvider(),
  ];
  if (kIsWeb) return OfficeProofingService(providers: providers);
  return OfficeProofingService(
    providers: [
      for (final (index, kind) in _Checker.values.indexed)
        _BackgroundChecker(kind, providers[index], vocabulary),
    ],
    // Include bounded queue time. A slow check must not disable the shared
    // lanes for the rest of a long document or later edits in this session.
    timeout: const Duration(seconds: 30),
    disposeOnTimeout: false,
  );
}

bool usesBackgroundWordProofing(OfficeProofingService service) =>
    service.providers.isNotEmpty &&
    service.providers.every((provider) => provider is _BackgroundChecker);

enum _Checker { germanWriting, germanSpelling, arabicWriting }

final class _BackgroundChecker extends OfficeProofingProvider {
  _BackgroundChecker(this._kind, this._metadata, this._vocabulary);

  static int _nextOwner = 0;
  final int _owner = ++_nextOwner;
  final _Checker _kind;
  final OfficeProofingProvider _metadata;
  final OfficeProofingVocabulary _vocabulary;
  _ProofingWorker? _worker;
  bool _disposed = false;
  int? _snapshotRevision;
  Map<String, Object?>? _vocabularySnapshot;

  bool get _spelling => _kind == _Checker.germanSpelling;

  @override
  String get id => _metadata.id;

  @override
  Set<OfficeProofingCategory> get categories => _metadata.categories;

  @override
  int get configurationRevision => _metadata.configurationRevision;

  @override
  bool supportsLanguage(String language) =>
      _metadata.supportsLanguage(language);

  _ProofingWorker _activeWorker() {
    if (_disposed) throw StateError('Proofing provider is disposed.');
    final worker = _worker;
    if (worker != null && !worker.closed) return worker;
    worker?.release(_owner);
    return _worker = _ProofingWorker.acquire(spelling: _spelling);
  }

  @override
  Future<void> warmUp() => _activeWorker().warmUp();

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    final revision = configurationRevision;
    if (_spelling && _snapshotRevision != revision) {
      _snapshotRevision = revision;
      _vocabularySnapshot = _vocabulary.toJson();
    }
    final result = (await _activeWorker().submit((
      owner: _owner,
      checker: _kind,
      request: request,
      revision: revision,
      vocabulary: _vocabularySnapshot,
    )))!;
    // The original request belongs to this isolate. Rebind it before service
    // validation, which deliberately checks request identity and source spans.
    final changed = _spelling && revision != configurationRevision;
    return OfficeProofingResult(
      request: request,
      providerId: result.providerId,
      status: changed ? OfficeProofingStatus.failed : result.status,
      findings: changed ? const [] : result.findings,
      message: changed
          ? 'Personal vocabulary changed during this check; check again.'
          : result.message,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _worker?.release(_owner);
    _worker = null;
    _vocabularySnapshot = null;
    await _metadata.dispose();
  }
}

typedef _Job = ({
  int? owner,
  _Checker checker,
  OfficeProofingRequest? request,
  int revision,
  Map<String, Object?>? vocabulary,
});

final class _Pending {
  _Pending(this.job);
  final _Job job;
  final completion = Completer<OfficeProofingResult?>();
}

final class _ProofingWorker {
  _ProofingWorker(this._spelling) {
    _events.listen(_receive);
    unawaited(_start());
  }

  static final _workers = <bool, _ProofingWorker>{};

  static _ProofingWorker acquire({required bool spelling}) {
    final existing = _workers[spelling];
    final worker = existing != null && !existing.closed
        ? existing
        : (_workers[spelling] = _ProofingWorker(spelling));
    worker._owners++;
    return worker;
  }

  final bool _spelling;
  final _events = ReceivePort();
  final _queue = Queue<_Pending>();
  final _ready = Completer<void>();
  SendPort? _commands;
  Isolate? _isolate;
  _Pending? _active;
  Future<void>? _dictionary;
  int _owners = 0;
  bool closed = false;

  Future<void> _start() async {
    // Startup errors may arrive before a caller has attached to _ready.
    unawaited(_ready.future.catchError((Object _) {}));
    try {
      final isolate = await Isolate.spawn(
        _serveProofing,
        _events.sendPort,
        debugName: _spelling ? 'word-spelling' : 'word-writing-rules',
        onError: _events.sendPort,
        onExit: _events.sendPort,
        errorsAreFatal: true,
      );
      if (closed) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    } catch (_) {
      _close('The local proofing worker could not start.');
    }
  }

  Future<void> warmUp() {
    if (!_spelling) return _ready.future;
    return _dictionary ??= _loadDictionary();
  }

  Future<void> _loadDictionary() async {
    try {
      await submit((
        owner: null,
        checker: _Checker.germanSpelling,
        request: null,
        revision: 0,
        vocabulary: null,
      ));
    } catch (_) {
      _dictionary = null;
      rethrow;
    }
  }

  Future<OfficeProofingResult?> submit(_Job job) {
    if (closed) return Future.error(StateError('Proofing worker is closed.'));
    final pending = _Pending(job);
    _queue.addLast(pending);
    _dispatch();
    return pending.completion.future;
  }

  void _dispatch() {
    final commands = _commands;
    if (commands == null || _active != null || _queue.isEmpty) return;
    final next = _active = _queue.removeFirst();
    commands.send(next.job);
  }

  void _receive(Object? message) {
    if (message is SendPort) {
      _commands = message;
      _ready.complete();
    } else if (message is (bool, OfficeProofingResult?)) {
      final active = _active;
      _active = null;
      if (active != null && !active.completion.isCompleted) {
        if (message.$1) {
          active.completion.complete(message.$2);
        } else {
          active.completion.completeError(
            StateError('The local proofing check failed.'),
          );
        }
      }
    } else {
      _close('The local proofing worker exited unexpectedly.');
      return;
    }
    _dispatch();
  }

  void release(int owner) {
    final error = StateError('Proofing provider is disposed.');
    _queue.removeWhere((pending) {
      if (pending.job.owner != owner) return false;
      pending.completion.completeError(error);
      return true;
    });
    final active = _active;
    if (active != null &&
        active.job.owner == owner &&
        !active.completion.isCompleted) {
      active.completion.completeError(error);
    }
    if (--_owners == 0) _close('Proofing worker is closed.');
  }

  void _close(String reason) {
    if (closed) return;
    closed = true;
    if (identical(_workers[_spelling], this)) _workers.remove(_spelling);
    final error = StateError(reason);
    if (!_ready.isCompleted) _ready.completeError(error);
    final active = _active;
    if (active != null && !active.completion.isCompleted) {
      active.completion.completeError(error);
    }
    _active = null;
    for (final pending in _queue) {
      pending.completion.completeError(error);
    }
    _queue.clear();
    _events.close();
    _isolate?.kill(priority: Isolate.immediate);
  }
}

Future<void> _serveProofing(SendPort replies) async {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  final germanWriting = GermanWritingRulesProvider();
  final arabicWriting = ArabicWritingRulesProvider();
  var germanSpelling = GermanSpellingProvider(yieldBetweenChecks: false);
  (int?, int)? spellingOwner;
  // Bound inter-isolate work to one paragraph per lane and keep provider
  // mutable state private to the worker.
  await for (final _Job job in commands.cast<_Job>()) {
    try {
      OfficeProofingResult? result;
      final request = job.request;
      if (request == null) {
        await germanSpelling.warmUp();
      } else {
        if (job.checker == _Checker.germanSpelling &&
            spellingOwner != (job.owner, job.revision)) {
          germanSpelling = GermanSpellingProvider(
            vocabulary: OfficeProofingVocabulary.fromJson(job.vocabulary!),
            yieldBetweenChecks: false,
          );
          spellingOwner = (job.owner, job.revision);
        }
        final checker = switch (job.checker) {
          _Checker.germanWriting => germanWriting,
          _Checker.germanSpelling => germanSpelling,
          _Checker.arabicWriting => arabicWriting,
        };
        result = await checker.check(request);
      }
      replies.send((true, result));
    } catch (_) {
      // A provider exception must not relay document text or isolate internals.
      replies.send((false, null));
    }
  }
}
