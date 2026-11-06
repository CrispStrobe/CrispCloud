import 'dart:async';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/stream_rate_limiter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'each emitted byte is paced before delivery with arbitrary source chunks',
    () async {
      final clock = _ManualClock();
      final control = _Control();
      final limiter = StreamRateLimiter(
        bytesPerSecond: 4,
        clock: () => clock.elapsed,
        createTimer: clock.timer,
      );
      final emitted = <(Duration, List<int>)>[];
      final finished = limiter
          .bind(
            Stream.fromIterable([
              [1, 2],
              [3],
            ]),
            control: control,
          )
          .listen((part) => emitted.add((clock.elapsed, part)))
          .asFuture<void>();
      await _pump();
      expect(emitted, isEmpty);
      expect(clock.activeTimers, 1);
      clock.advance(const Duration(milliseconds: 249));
      await _pump();
      expect(emitted, isEmpty);
      clock.advance(const Duration(milliseconds: 1));
      await _pump();
      expect(emitted.map((event) => (event.$1, event.$2.single)), [
        (const Duration(milliseconds: 250), 1),
      ]);
      clock.advance(const Duration(milliseconds: 250));
      await _pump();
      clock.advance(const Duration(milliseconds: 250));
      await finished;
      expect(emitted.map((event) => (event.$1, event.$2.single)), [
        (const Duration(milliseconds: 250), 1),
        (const Duration(milliseconds: 500), 2),
        (const Duration(milliseconds: 750), 3),
      ]);
      expect(clock.activeTimers, 0);
      await control.dispose();
    },
  );

  test(
    'cancellation wakes a slow limit immediately and cancels its timer/source',
    () async {
      final clock = _ManualClock();
      final control = _Control();
      var sourceCancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () => sourceCancelled = true,
      );
      final result = StreamRateLimiter(
        bytesPerSecond: 1,
        clock: () => clock.elapsed,
        createTimer: clock.timer,
      ).bind(source.stream, control: control).toList();
      final assertion = expectLater(result, throwsStateError);
      source.add([1]);
      await _pump();
      expect(clock.activeTimers, 1);
      control.cancel();
      await assertion;
      expect(clock.elapsed, Duration.zero);
      expect(clock.activeTimers, 0);
      expect(sourceCancelled, isTrue);
      await source.close();
      await control.dispose();
    },
  );

  test('paused time does not consume the remaining byte budget', () async {
    final clock = _ManualClock();
    final control = _Control();
    final emitted = <int>[];
    final finished =
        StreamRateLimiter(
              bytesPerSecond: 4,
              clock: () => clock.elapsed,
              createTimer: clock.timer,
            )
            .bind(Stream.value([7]), control: control)
            .listen(emitted.addAll)
            .asFuture<void>();
    await _pump();
    clock.advance(const Duration(milliseconds: 100));
    control.pause();
    await _pump();
    expect(clock.activeTimers, 0);
    clock.advance(const Duration(hours: 1));
    await _pump();
    expect(emitted, isEmpty);
    control.resume();
    await _pump();
    clock.advance(const Duration(milliseconds: 149));
    await _pump();
    expect(emitted, isEmpty);
    clock.advance(const Duration(milliseconds: 1));
    await finished;
    expect(emitted, [7]);
    expect(clock.elapsed, const Duration(hours: 1, milliseconds: 250));
    await control.dispose();
  });

  test(
    'separate file streams do not accumulate idle-time burst credit',
    () async {
      final clock = _ManualClock();
      final control = _Control();
      final limiter = StreamRateLimiter(
        bytesPerSecond: 4,
        clock: () => clock.elapsed,
        createTimer: clock.timer,
      );
      for (var file = 0; file < 2; file++) {
        final emitted = <int>[];
        final finished = limiter
            .bind(Stream.value([file]), control: control)
            .listen(emitted.addAll)
            .asFuture<void>();
        await _pump();
        expect(emitted, isEmpty);
        clock.advance(const Duration(milliseconds: 250));
        await finished;
        expect(emitted, [file]);
        clock.advance(const Duration(hours: 1));
      }
      expect(clock.activeTimers, 0);
      await control.dispose();
    },
  );

  test('large source chunks are delivered in bounded pieces without changing bytes', () async {
    final clock = _ManualClock();
    final control = _Control();
    final input = List.generate(150000, (index) => index % 256);
    final parts = <List<int>>[];
    var finished = false;
    final result =
        StreamRateLimiter(
          bytesPerSecond: 10000000,
          clock: () => clock.elapsed,
          createTimer: clock.timer,
        ).bind(Stream.value(input), control: control).toList().then((value) {
          parts.addAll(value);
          finished = true;
        });
    await _pump();
    while (!finished) {
      expect(clock.activeTimers, 1);
      clock.advanceToNextTimer();
      await _pump();
    }
    await result;
    expect(parts.every((part) => part.length <= 64 * 1024), isTrue);
    expect(parts.expand((part) => part), input);
    expect(clock.elapsed.inMicroseconds, greaterThanOrEqualTo(15000));
    await control.dispose();
  });

  group('file operation stream integration', () {
    late _ManualClock clock;
    late FileOperationService service;
    late _RateBackend source;
    late _RateBackend target;
    late int createdLimiters;

    setUp(() {
      clock = _ManualClock();
      createdLimiters = 0;
      service = FileOperationService(
        rateLimiterFactory: (rate) {
          createdLimiters++;
          return StreamRateLimiter(
            bytesPerSecond: rate,
            clock: () => clock.elapsed,
            createTimer: clock.timer,
          );
        },
      );
      source = _RateBackend(clock);
      target = _RateBackend(clock);
    });

    Future<FileOperationPlan> prepare({
      int? rate = 4,
      FileOperationKind kind = FileOperationKind.copy,
    }) => service.prepare(
      files: source.bytes.keys.map(source.item).toList(),
      source: source,
      destination: target,
      targetDirectory: '/target',
      options: FileOperationOptions(
        kind: kind,
        copyMethod: FileCopyMethod.stream,
        clientBytesPerSecond: rate,
      ),
    );

    test(
      'actual destination writes and progress obey one job rate across files',
      () async {
        source.bytes['/a'] = [1, 2];
        source.bytes['/b'] = [3, 4];
        final plan = await prepare();
        final progress = <(int, String, int)>[];
        final run = service.execute(
          plan,
          control: FileOperationControl(),
          onProgress: (entry, count, _) => progress.add((
            clock.elapsed.inMilliseconds,
            entry.destination,
            count,
          )),
        );
        await _pump();
        expect(target.received, isEmpty);
        clock.advance(const Duration(milliseconds: 249));
        await _pump();
        expect(target.received, isEmpty);
        clock.advance(const Duration(milliseconds: 1));
        await _pump();
        for (var next = 0; next < 3; next++) {
          clock.advance(const Duration(milliseconds: 250));
          await _pump();
        }
        await run;
        expect(createdLimiters, 1);
        expect(target.received, [
          (250, '/target/a', 1),
          (500, '/target/a', 2),
          (750, '/target/b', 3),
          (1000, '/target/b', 4),
        ]);
        expect(progress, [
          (250, '/target/a', 1),
          (500, '/target/a', 2),
          (750, '/target/b', 1),
          (1000, '/target/b', 2),
        ]);
        expect(target.bytes['/target/a'], [1, 2]);
        expect(target.bytes['/target/b'], [3, 4]);
        expect(plan.entries.every((entry) => entry.completed), isTrue);
        expect(clock.activeTimers, 0);
      },
    );

    test(
      'cancelling a throttled move retains its source without advancing time',
      () async {
        source.bytes['/a'] = [1, 2, 3];
        final plan = await prepare(rate: 1, kind: FileOperationKind.move);
        final control = FileOperationControl();
        final run = service.execute(plan, control: control);
        await _pump();
        expect(clock.activeTimers, 1);
        control.cancel();
        await run;
        expect(plan.entries.single.outcome, FileOperationOutcome.cancelled);
        expect(source.bytes['/a'], [1, 2, 3]);
        expect(source.closedReads, 1);
        expect(target.received, isEmpty);
        expect(target.bytes, isEmpty);
        expect(clock.elapsed, Duration.zero);
        expect(clock.activeTimers, 0);
      },
    );

    test('real operation pause preserves unspent budget even before the next microtask', () async {
      source.bytes['/a'] = [7];
      final plan = await prepare();
      final control = FileOperationControl();
      final run = service.execute(plan, control: control);
      await _pump();
      clock.advance(const Duration(milliseconds: 100));
      control.pause();
      // Capture the pause instant, not when a delayed continuation runs.
      clock.advance(const Duration(hours: 1));
      await _pump();
      expect(clock.activeTimers, 0);
      expect(target.received, isEmpty);
      control.resume();
      await _pump();
      clock.advance(const Duration(milliseconds: 149));
      await _pump();
      expect(target.received, isEmpty);
      clock.advance(const Duration(milliseconds: 1));
      await run;
      expect(target.bytes['/target/a'], [7]);
      expect(clock.elapsed, const Duration(hours: 1, milliseconds: 250));
    });

    test('unlimited copies bypass the rate limiter', () async {
      source.bytes['/a'] = [1, 2, 3];
      final plan = await prepare(rate: null);
      await service.execute(plan, control: FileOperationControl());
      expect(createdLimiters, 0);
      expect(target.bytes['/target/a'], [1, 2, 3]);
      expect(clock.elapsed, Duration.zero);
    });

    test('two concurrent operations have independent byte budgets', () async {
      source.bytes['/a'] = [1];
      final first = await prepare();
      final secondTarget = _RateBackend(clock);
      final second = await service.prepare(
        files: [source.item('/a')],
        source: source,
        destination: secondTarget,
        targetDirectory: '/target',
        options: const FileOperationOptions(clientBytesPerSecond: 4),
      );
      final firstRun = service.execute(first, control: FileOperationControl());
      final secondRun = service.execute(
        second,
        control: FileOperationControl(),
      );
      await _pump();
      expect(clock.activeTimers, 2);
      clock.advance(const Duration(milliseconds: 250));
      await Future.wait([firstRun, secondRun]);
      expect(createdLimiters, 2);
      expect(target.bytes['/target/a'], [1]);
      expect(secondTarget.bytes['/target/a'], [1]);
      expect(clock.elapsed, const Duration(milliseconds: 250));
    });
  });
}

class _RateBackend extends FileOperationBackend {
  _RateBackend(this.clock);
  final _ManualClock clock;
  final bytes = <String, List<int>>{};
  final received = <(int, String, int)>[];
  int closedReads = 0;
  @override
  Object get identity => this;
  @override
  String get label => 'Memory';
  @override
  p.Context get paths => p.posix;
  @override
  bool get isCurrent => true;

  FileItem item(String path) => FileItem(
    name: paths.basename(path),
    path: path,
    isFolder: !bytes.containsKey(path),
    isSymlink: false,
    size: bytes[path]?.length,
  );

  @override
  Future<FileItem?> stat(String path) async =>
      path == '/' || path == '/target' || bytes.containsKey(path)
      ? item(path)
      : null;
  @override
  Future<List<FileItem>> list(String path) async => [
    for (final file in bytes.keys)
      if (paths.dirname(file) == path) item(file),
  ];
  @override
  Future<void> createDirectory(String path) async =>
      throw UnsupportedError('Not needed');
  @override
  Stream<List<int>> readFile(FileItem file) async* {
    try {
      yield List.of(bytes[file.path!]!);
    } finally {
      closedReads++;
    }
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async {
    final staged = <int>[];
    await for (final chunk in data) {
      for (final byte in chunk) {
        received.add((clock.elapsed.inMilliseconds, path, byte));
      }
      staged.addAll(chunk);
    }
    if (length != null && staged.length != length) {
      throw StateError('Incomplete copy');
    }
    bytes[path] = staged;
  }

  @override
  Future<void> deleteFile(FileItem file) async => bytes.remove(file.path);
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('Not needed');
}

class _Control implements StreamRateControl {
  final _changes = StreamController<void>.broadcast(sync: true);
  Completer<void>? _pause;
  @override
  bool isCancelled = false;
  @override
  bool get isPaused => _pause != null;
  @override
  Stream<void> get changes => _changes.stream;

  void pause() {
    _pause ??= Completer<void>();
    _changes.add(null);
  }

  void resume() {
    final pause = _pause;
    _pause = null;
    pause?.complete();
    _changes.add(null);
  }

  void cancel() {
    isCancelled = true;
    resume();
  }

  @override
  Future<void> checkpoint() async {
    if (isCancelled) throw StateError('Cancelled');
    await _pause?.future;
    if (isCancelled) throw StateError('Cancelled');
  }

  Future<void> dispose() => _changes.close();
}

class _ManualClock {
  Duration elapsed = Duration.zero;
  final _timers = <_ManualTimer>[];
  int get activeTimers => _timers.where((timer) => timer.isActive).length;

  Timer timer(Duration duration, void Function() callback) {
    final timer = _ManualTimer(elapsed + duration, callback);
    _timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    final until = elapsed + duration;
    final due =
        _timers.where((timer) => timer.isActive && timer.due <= until).toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    for (final timer in due) {
      elapsed = timer.due;
      timer.fire();
    }
    elapsed = until;
  }

  void advanceToNextTimer() {
    final next = _timers.where((timer) => timer.isActive).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    advance(next.first.due - elapsed);
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.due, this.callback);
  final Duration due;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}
