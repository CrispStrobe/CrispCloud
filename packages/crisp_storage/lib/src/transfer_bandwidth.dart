import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

/// The direction of payload crossing a supported client transport boundary.
enum TransferBandwidthDirection { upload, download }

/// Independent runtime limits. Zero means unlimited, never paused.
class TransferBandwidthLimits {
  const TransferBandwidthLimits({
    this.uploadBytesPerSecond = 0,
    this.downloadBytesPerSecond = 0,
  });

  static const maximumBytesPerSecond = 1099511627776;
  final int uploadBytesPerSecond;
  final int downloadBytesPerSecond;

  void validate() {
    for (final value in [uploadBytesPerSecond, downloadBytesPerSecond]) {
      if (value < 0 || value > maximumBytesPerSecond) {
        throw ArgumentError.value(value, 'bytesPerSecond');
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TransferBandwidthLimits &&
      uploadBytesPerSecond == other.uploadBytesPerSecond &&
      downloadBytesPerSecond == other.downloadBytesPerSecond;

  @override
  int get hashCode => Object.hash(uploadBytesPerSecond, downloadBytesPerSecond);
}

/// Payload observed by supported hooks, not TLS/protocol/OS wire traffic.
///
/// Rates use the trailing second in bounded 100 ms buckets and are recomputed
/// when read. Unsupported hooks report coverage but do not count preparation
/// bytes as transported payload. Job counts are distinct operation identities.
class TransferBandwidthSnapshot {
  const TransferBandwidthSnapshot({
    required this.limits,
    required this.uploadBytes,
    required this.downloadBytes,
    required this.uploadBytesPerSecond,
    required this.downloadBytesPerSecond,
    required this.activeJobs,
    required this.pendingUploadJobs,
    required this.pendingDownloadJobs,
    required this.unsupportedUploadJobs,
    required this.unsupportedDownloadJobs,
  });

  final TransferBandwidthLimits limits;
  final int uploadBytes;
  final int downloadBytes;
  final double uploadBytesPerSecond;
  final double downloadBytesPerSecond;
  final int activeJobs;
  final int pendingUploadJobs;
  final int pendingDownloadJobs;
  final int unsupportedUploadJobs;
  final int unsupportedDownloadJobs;
}

class TransferBandwidthCancelled implements Exception {
  const TransferBandwidthCancelled();

  @override
  String toString() => 'Transfer bandwidth operation cancelled';
}

typedef TransferBandwidthTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// One application runtime's shared payload allocator.
///
/// Each direction has one pacing timer. Only bindings with ready bytes compete;
/// a source read, downstream pause or remote acknowledgement holds no share.
/// Equal-weight service is by operation ID and cumulative granted bytes, so
/// splitting an operation into additional contexts does not create more shares.
/// Service quanta are at most 64 KiB and approximately 100 ms at the selected
/// rate (one byte at very low rates). Idle time accrues no burst credit.
///
/// This does not install transport hooks, cover another runtime, or establish
/// browser upload enforcement. Each actual boundary must capture and bind its
/// context explicitly, and mark unsupported paths honestly.
class TransferBandwidthAllocator {
  TransferBandwidthAllocator({
    TransferBandwidthLimits limits = const TransferBandwidthLimits(),
    Duration Function()? clock,
    TransferBandwidthTimerFactory? createTimer,
  }) : _limits = limits,
       _clock = clock ?? _monotonicClock(),
       _createTimer = createTimer ?? Timer.new {
    limits.validate();
    _upload = _BandwidthPool(this, TransferBandwidthDirection.upload);
    _download = _BandwidthPool(this, TransferBandwidthDirection.download);
  }

  static Duration Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  TransferBandwidthLimits _limits;
  final Duration Function() _clock;
  final TransferBandwidthTimerFactory _createTimer;
  final _groups = <String, _BandwidthJob>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  late final _BandwidthPool _upload;
  late final _BandwidthPool _download;
  bool _disposed = false;
  bool _notificationPending = false;

  TransferBandwidthLimits get limits => _limits;
  Stream<void> get changes => _changes.stream;

  TransferBandwidthSnapshot get snapshot {
    final live = _groups.values.where((job) => !job.cancelled).toList();
    final now = _clock();
    int unsupported(TransferBandwidthDirection direction) => live
        .where(
          (job) => job.contexts.any(
            (context) => context._unsupported.contains(direction),
          ),
        )
        .length;
    return TransferBandwidthSnapshot(
      limits: _limits,
      uploadBytes: _upload.bytes,
      downloadBytes: _download.bytes,
      uploadBytesPerSecond: _upload.rate.at(now),
      downloadBytesPerSecond: _download.rate.at(now),
      activeJobs: live.length,
      pendingUploadJobs: _upload.pendingJobs,
      pendingDownloadJobs: _download.pendingJobs,
      unsupportedUploadJobs: unsupported(TransferBandwidthDirection.upload),
      unsupportedDownloadJobs: unsupported(TransferBandwidthDirection.download),
    );
  }

  void updateLimits(TransferBandwidthLimits limits) {
    if (_disposed) throw StateError('The bandwidth allocator is closed.');
    limits.validate();
    if (limits == _limits) return;
    final previous = _limits;
    _limits = limits;
    if (previous.uploadBytesPerSecond != limits.uploadBytesPerSecond) {
      _upload.reconfigure();
    }
    if (previous.downloadBytesPerSecond != limits.downloadBytesPerSecond) {
      _download.reconfigure();
    }
    _notify();
  }

  TransferBandwidthContext openContext(String operationId) {
    if (_disposed) throw StateError('The bandwidth allocator is closed.');
    if (operationId.isEmpty) {
      throw ArgumentError.value(operationId, 'operationId');
    }
    final job = _groups.putIfAbsent(
      operationId,
      () => _BandwidthJob(operationId),
    );
    if (job.cancelled) throw const TransferBandwidthCancelled();
    final context = TransferBandwidthContext._(this, job);
    job.contexts.add(context);
    _notify();
    return context;
  }

  _BandwidthPool _pool(TransferBandwidthDirection direction) =>
      direction == TransferBandwidthDirection.upload ? _upload : _download;

  void _notify() {
    if (_disposed || _notificationPending) return;
    _notificationPending = true;
    scheduleMicrotask(() {
      _notificationPending = false;
      if (!_disposed) _changes.add(null);
    });
  }

  void _withdraw(_BandwidthBinding binding) {
    _upload.withdraw(binding);
    _download.withdraw(binding);
  }

  void _close(TransferBandwidthContext context) {
    final job = context._job;
    job.contexts.remove(context);
    if (job.contexts.isEmpty) {
      if (identical(_groups[job.id], job)) _groups.remove(job.id);
      _upload.forget(job);
      _download.forget(job);
    }
    _notify();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final job in _groups.values.toList()) {
      for (final context in job.contexts.toList()) {
        context.close();
      }
    }
    _upload.dispose();
    _download.dispose();
    unawaited(_changes.close());
  }
}

final _bandwidthContextKey = Object();

/// A captured operation lifetime; bindings never adopt a later caller's zone.
class TransferBandwidthContext {
  TransferBandwidthContext._(this._allocator, this._job);

  final TransferBandwidthAllocator _allocator;
  final _BandwidthJob _job;
  final _bindings = <_BandwidthBinding>{};
  final _unsupported = <TransferBandwidthDirection>{};
  final _cancellation = Completer<void>();
  bool _closed = false;

  static TransferBandwidthContext? get current =>
      Zone.current[_bandwidthContextKey] as TransferBandwidthContext?;

  String get operationId => _job.id;
  bool get isClosed => _closed || _allocator._disposed;
  bool get isPaused => _job.paused;
  bool get isCancelled => _job.cancelled || isClosed;
  Future<void> get cancellationFuture => _cancellation.future;

  /// Records an uncovered boundary with no stream, such as a browser Blob
  /// upload. It does not count body preparation as transported payload.
  void markUnsupported(TransferBandwidthDirection direction) {
    _check();
    if (_unsupported.add(direction)) _allocator._notify();
  }

  T run<T>(T Function() body) {
    _check();
    return runZoned(body, zoneValues: {_bandwidthContextKey: this});
  }

  /// Copies immutable bounded slices while preserving source backpressure.
  ///
  /// Producers must keep their current buffer stable while paused. Unsupported
  /// paths preserve byte contents and controls but bypass pacing and counters;
  /// they record coverage instead of pretending preparation is network traffic.
  Stream<List<int>> bind(
    Stream<List<int>> input, {
    required TransferBandwidthDirection direction,
    bool supported = true,
  }) {
    _check();
    return _BandwidthBinding(this, input, direction, supported).stream;
  }

  void _check() {
    if (isCancelled) throw const TransferBandwidthCancelled();
  }

  void setPaused(bool paused) {
    if (isClosed || _job.cancelled || _job.paused == paused) return;
    _job.paused = paused;
    for (final context in _job.contexts.toList()) {
      for (final binding in context._bindings.toList()) {
        binding.stateChanged();
      }
    }
    _allocator._notify();
  }

  /// Cancellation and pause apply to every context of the same operation ID.
  void cancel() {
    if (isClosed || _job.cancelled) return;
    _job.cancelled = true;
    for (final context in _job.contexts.toList()) {
      if (!context._cancellation.isCompleted) context._cancellation.complete();
      for (final binding in context._bindings.toList()) {
        binding.stateChanged();
      }
    }
    _allocator._notify();
  }

  /// Closing releases this context only, including its own pending bindings.
  void close() {
    if (_closed) return;
    _closed = true;
    if (!_cancellation.isCompleted) _cancellation.complete();
    for (final binding in _bindings.toList()) {
      binding.stateChanged();
    }
    _allocator._close(this);
  }
}

class _BandwidthJob {
  _BandwidthJob(this.id);
  final String id;
  final contexts = <TransferBandwidthContext>{};
  bool paused = false;
  bool cancelled = false;
}

class _BandwidthDemand {
  _BandwidthDemand(this.binding, this.maximum);
  final _BandwidthBinding binding;
  final int maximum;
  final result = Completer<_BandwidthPermit?>();
  _BandwidthJob get job => binding.context._job;
}

class _BandwidthPermit {
  const _BandwidthPermit(this.bytes, this.generation);
  final int bytes;
  final int generation;
}

class _BandwidthReservation {
  _BandwidthReservation(this.demand, this.bytes);
  final _BandwidthDemand demand;
  final int bytes;
  Timer? timer;
}

class _BandwidthPool {
  _BandwidthPool(this.owner, this.direction);
  final TransferBandwidthAllocator owner;
  final TransferBandwidthDirection direction;
  final _queues = <_BandwidthJob, ListQueue<_BandwidthDemand>>{};
  final _finish = <_BandwidthJob, int>{};
  final rate = _BandwidthRate();
  _BandwidthReservation? _active;
  bool _scheduled = false;
  int _virtualTime = 0;
  int generation = 0;
  int bytes = 0;

  int get limit => direction == TransferBandwidthDirection.upload
      ? owner.limits.uploadBytesPerSecond
      : owner.limits.downloadBytesPerSecond;
  int get quantum =>
      limit == 0 ? 65536 : math.max(1, math.min(65536, limit ~/ 10));
  int get pendingJobs =>
      {..._queues.keys, if (_active != null) _active!.demand.job}.length;

  Future<_BandwidthPermit?> request(_BandwidthBinding binding, int maximum) {
    final demand = _BandwidthDemand(binding, maximum);
    final job = demand.job;
    if (!binding.ready) return Future.value(null);
    if (!_queues.containsKey(job) && _active?.demand.job != job) {
      _finish[job] = math.max(_finish[job] ?? 0, _virtualTime);
    }
    (_queues[job] ??= ListQueue()).add(demand);
    _schedule();
    owner._notify();
    return demand.result.future;
  }

  void _schedule() {
    if (_scheduled || owner._disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      _drain();
    });
  }

  void _drain() {
    if (owner._disposed || _active != null || _queues.isEmpty) return;
    _BandwidthJob? chosen;
    for (final job in _queues.keys) {
      if (chosen == null || _finish[job]! < _finish[chosen]!) chosen = job;
    }
    final queue = _queues[chosen]!;
    final demand = queue.removeFirst();
    if (queue.isEmpty) _queues.remove(chosen);
    if (!demand.binding.ready) {
      demand.result.complete(null);
      _schedule();
      return;
    }
    final reservation = _BandwidthReservation(
      demand,
      math.min(demand.maximum, quantum),
    );
    _active = reservation;
    if (limit == 0) {
      _complete(reservation);
    } else {
      final micros =
          (reservation.bytes * Duration.microsecondsPerSecond + limit - 1) ~/
          limit;
      reservation.timer = owner._createTimer(
        Duration(microseconds: micros),
        () => _complete(reservation),
      );
    }
  }

  void _complete(_BandwidthReservation reservation) {
    if (!identical(_active, reservation)) return;
    _active = null;
    final demand = reservation.demand;
    if (demand.binding.ready) {
      final finish = (_finish[demand.job] ?? _virtualTime) + reservation.bytes;
      _finish[demand.job] = finish;
      _virtualTime = math.max(_virtualTime, finish);
      demand.result.complete(_BandwidthPermit(reservation.bytes, generation));
    } else {
      demand.result.complete(null);
    }
    // The completed consumer can hand off and queue its next ready slice before
    // choosing another job. No quota is reserved across a downstream wait.
    _schedule();
    owner._notify();
  }

  void record(int count) {
    bytes += count;
    rate.add(count, owner._clock());
    owner._notify();
  }

  void withdraw(_BandwidthBinding binding) {
    final active = _active;
    if (active != null && identical(active.demand.binding, binding)) {
      active.timer?.cancel();
      _active = null;
      active.demand.result.complete(null);
    }
    for (final entry in _queues.entries.toList()) {
      final retained = ListQueue<_BandwidthDemand>();
      for (final demand in entry.value) {
        if (identical(demand.binding, binding)) {
          demand.result.complete(null);
        } else {
          retained.add(demand);
        }
      }
      if (retained.isEmpty) {
        _queues.remove(entry.key);
      } else {
        _queues[entry.key] = retained;
      }
    }
    _schedule();
    owner._notify();
  }

  void reconfigure() {
    generation++;
    final active = _active;
    if (active != null) {
      active.timer?.cancel();
      _active = null;
      if (active.demand.binding.ready) {
        (_queues[active.demand.job] ??= ListQueue()).addFirst(active.demand);
      } else {
        active.demand.result.complete(null);
      }
    }
    _schedule();
  }

  void forget(_BandwidthJob job) => _finish.remove(job);

  void dispose() {
    _active?.timer?.cancel();
    final active = _active;
    _active = null;
    active?.demand.result.complete(null);
    for (final queue in _queues.values) {
      for (final demand in queue) {
        demand.result.complete(null);
      }
    }
    _queues.clear();
    _finish.clear();
  }
}

class _BandwidthBinding {
  _BandwidthBinding(this.context, this.input, this.direction, this.supported) {
    output = StreamController<List<int>>(
      sync: true,
      onListen: () => scheduleMicrotask(() {
        // Lazy source bodies may open nested transport helpers while subscribed
        // from another zone. They must observe this captured operation too.
        runZoned(_start, zoneValues: {_bandwidthContextKey: context});
      }),
      onPause: () {
        _paused = true;
        stateChanged();
      },
      onResume: () {
        _paused = false;
        stateChanged();
      },
      onCancel: () {
        _consumerCancelled = true;
        stateChanged();
      },
    );
  }

  final TransferBandwidthContext context;
  final Stream<List<int>> input;
  final TransferBandwidthDirection direction;
  final bool supported;
  late final StreamController<List<int>> output;
  final _abortWaiters = <void Function()>{};
  bool _aborted = false;
  _BandwidthInput? _input;
  Completer<void>? _resume;
  bool _paused = false;
  bool _consumerCancelled = false;
  bool _finished = false;
  int _version = 0;
  Stream<List<int>> get stream => output.stream;
  bool get ready =>
      !_finished &&
      !_consumerCancelled &&
      !context.isCancelled &&
      !_paused &&
      !context.isPaused;

  void stateChanged() {
    _version++;
    _input?.setPaused(_paused || context.isPaused);
    if (!ready) context._allocator._withdraw(this);
    if (_consumerCancelled || context.isCancelled) {
      _aborted = true;
      for (final wake in _abortWaiters.toList()) {
        wake();
      }
      _input?.cancel();
    }
    if (!_paused && !context.isPaused ||
        _consumerCancelled ||
        context.isCancelled) {
      final resume = _resume;
      _resume = null;
      resume?.complete();
    }
  }

  void _check() {
    context._check();
    if (_consumerCancelled) throw const TransferBandwidthCancelled();
  }

  Future<void>? _waitReady() {
    _check();
    if (!_paused && !context.isPaused) return null;
    return (_resume ??= Completer<void>()).future;
  }

  Future<bool> _readNext(_BandwidthInput source) async {
    final done = Completer<bool>();
    void abort() {
      if (!done.isCompleted) done.complete(false);
    }

    _abortWaiters.add(abort);
    try {
      if (_aborted) {
        abort();
      } else {
        unawaited(
          source.cursor.moveNext().then<void>(
            (value) {
              if (!done.isCompleted) done.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              if (!done.isCompleted) done.completeError(error, stack);
            },
          ),
        );
      }
      return await done.future;
    } finally {
      _abortWaiters.remove(abort);
    }
  }

  Future<void> _start() async {
    context._bindings.add(this);
    final pool = context._allocator._pool(direction);
    var chunksSinceYield = 0;
    var bytesSinceYield = 0;
    try {
      _check();
      if (!supported) {
        context.markUnsupported(direction);
      }
      while (true) {
        final waiting = _waitReady();
        if (waiting != null) {
          await waiting;
          continue;
        }
        final source = _input ??= _BandwidthInput(input);
        final hasNext = await _readNext(source);
        _check();
        if (!hasNext) break;
        final chunk = source.cursor.current;
        for (var offset = 0; offset < chunk.length;) {
          final waiting = _waitReady();
          if (waiting != null) {
            await waiting;
            continue;
          }
          final count = math.min(
            supported ? pool.quantum : 65536,
            chunk.length - offset,
          );
          final copied = Uint8List(count);
          for (var index = 0; index < count; index++) {
            final value = chunk[offset + index];
            if (value < 0 || value > 255) {
              throw RangeError.range(value, 0, 255, 'byte');
            }
            copied[index] = value;
          }
          final version = _version;
          final permit = supported ? await pool.request(this, count) : null;
          _check();
          if (!ready ||
              version != _version ||
              supported &&
                  (permit == null || permit.generation != pool.generation)) {
            continue;
          }
          final delivered = supported ? permit!.bytes : count;
          final part = delivered == copied.length
              ? copied.asUnmodifiableView()
              : Uint8List.sublistView(
                  copied,
                  0,
                  delivered,
                ).asUnmodifiableView();
          if (supported) pool.record(delivered);
          output.add(part);
          offset += delivered;
          bytesSinceYield += delivered;
          if (bytesSinceYield >= 1024 * 1024) {
            bytesSinceYield = 0;
            await Future<void>.delayed(Duration.zero);
          }
        }
        if (++chunksSinceYield >= 64) {
          chunksSinceYield = 0;
          await Future<void>.delayed(Duration.zero);
        }
      }
    } catch (error, stack) {
      if (!_consumerCancelled) output.addError(error, stack);
    } finally {
      _finished = true;
      context._allocator._withdraw(this);
      _input?.cancel();
      context._bindings.remove(this);
      unawaited(output.close());
    }
  }
}

/// Synchronous forwarding preserves a borrowed buffer while the pull consumer
/// is paused. Detached cancellation also prevents StreamIterator's
/// cancelOnError behavior from delaying a read error behind stalled cleanup.
class _BandwidthInput {
  _BandwidthInput(Stream<List<int>> input) {
    _forward = StreamController<List<int>>(
      sync: true,
      onListen: () {
        _source = input.listen(
          _forward.add,
          onError: _forward.addError,
          onDone: () => unawaited(_forward.close()),
          cancelOnError: false,
        );
        _applyPause();
      },
      onPause: () {
        _consumerPaused = true;
        _applyPause();
      },
      onResume: () {
        _consumerPaused = false;
        _applyPause();
      },
      onCancel: _cancelSource,
    );
    cursor = StreamIterator(_forward.stream);
  }

  late final StreamController<List<int>> _forward;
  late final StreamIterator<List<int>> cursor;
  StreamSubscription<List<int>>? _source;
  bool _consumerPaused = false;
  bool _externalPaused = false;
  bool _sourcePaused = false;
  bool _cancelled = false;

  void _applyPause() {
    final source = _source;
    if (source == null || _cancelled) return;
    final pause = _consumerPaused || _externalPaused;
    if (pause == _sourcePaused) return;
    _sourcePaused = pause;
    if (pause) {
      source.pause();
    } else {
      source.resume();
    }
  }

  void setPaused(bool paused) {
    _externalPaused = paused;
    _applyPause();
  }

  void _cancelSource() {
    if (_cancelled) return;
    _cancelled = true;
    final source = _source;
    _source = null;
    if (source != null) {
      unawaited(source.cancel().catchError((Object _, StackTrace _) {}));
    }
  }

  void cancel() {
    _cancelSource();
    unawaited(cursor.cancel().catchError((Object _, StackTrace _) {}));
  }
}

class _BandwidthRate {
  final _buckets = ListQueue<(int, int)>();

  void add(int bytes, Duration now) {
    final tick = now.inMicroseconds ~/ 100000;
    _prune(tick);
    if (_buckets.isNotEmpty && _buckets.last.$1 == tick) {
      final previous = _buckets.removeLast();
      _buckets.add((tick, previous.$2 + bytes));
    } else {
      _buckets.add((tick, bytes));
    }
  }

  void _prune(int tick) {
    while (_buckets.isNotEmpty && _buckets.first.$1 <= tick - 10) {
      _buckets.removeFirst();
    }
  }

  double at(Duration now) {
    _prune(now.inMicroseconds ~/ 100000);
    return _buckets.fold<int>(0, (sum, bucket) => sum + bucket.$2).toDouble();
  }
}
