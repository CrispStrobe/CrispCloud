// Standalone VM/JavaScript acceptance of the real shared bandwidth allocator.
// No Flutter, network access, credentials, package overrides or native hooks.
// Relative imports keep the real source independent of Flutter resolution;
// print emits the same machine-readable process receipt on VM and JavaScript.
// ignore_for_file: avoid_relative_lib_imports, avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../packages/crisp_storage/lib/src/transfer_bandwidth.dart';
import 'transfer_bandwidth_test_clock.dart';

const upload = TransferBandwidthDirection.upload;
const download = TransferBandwidthDirection.download;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

typedef Clock = ManualBandwidthClock;

extension on ManualBandwidthClock {
  TransferBandwidthAllocator allocator({int up = 0, int down = 0}) =>
      TransferBandwidthAllocator(
        limits: TransferBandwidthLimits(
          uploadBytesPerSecond: up,
          downloadBytesPerSecond: down,
        ),
        clock: () => elapsed,
        createTimer: timer,
      );
}

class Capture {
  Capture(Stream<List<int>> stream, {void Function(List<int>)? onPart}) {
    subscription = stream.listen(
      (part) {
        bytes.addAll(part);
        parts.add(part);
        onPart?.call(part);
      },
      onError: (Object failure) {
        error = failure;
      },
      onDone: done.complete,
    );
  }
  final bytes = <int>[];
  final parts = <List<int>>[];
  final done = Completer<void>();
  Object? error;
  late final StreamSubscription<List<int>> subscription;
}

Future<void> settle(
  Clock clock,
  Iterable<Capture> captures, {
  int maximum = 10000,
}) async {
  for (var step = 0; step < maximum; step++) {
    await pump();
    if (captures.every((capture) => capture.done.isCompleted)) return;
    if (clock.activeTimers > 0) await clock.next();
  }
  throw StateError(
    'streams did not settle within the deterministic work bound',
  );
}

Future<void> expectFailure(
  Future<Object?> Function() body,
  bool Function(Object) matches,
) async {
  try {
    await body();
  } catch (error) {
    check(matches(error), 'unexpected failure: $error');
    return;
  }
  throw StateError('expected failure');
}

Future<void> main() async {
  var passed = 0;
  Future<void> test(String name, FutureOr<void> Function() body) async {
    await Future<void>.sync(body).timeout(const Duration(seconds: 8));
    passed++;
    print(jsonEncode({'test': name, 'result': 'passed'}));
  }

  await test(
    'limits reject invalid values without changing runtime state',
    () async {
      final allocator = TransferBandwidthAllocator();
      for (final bad in [
        -1,
        TransferBandwidthLimits.maximumBytesPerSecond + 1,
      ]) {
        await expectFailure(
          () async => allocator.updateLimits(
            TransferBandwidthLimits(uploadBytesPerSecond: bad),
          ),
          (error) => error is ArgumentError,
        );
        check(
          allocator.limits == const TransferBandwidthLimits(),
          'invalid limit became active',
        );
      }
      const TransferBandwidthLimits(
        uploadBytesPerSecond: TransferBandwidthLimits.maximumBytesPerSecond,
      ).validate();
      allocator.dispose();
    },
  );

  await test(
    'independent directions pace before handoff and count actual payload',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 4, down: 2);
      final context = allocator.openContext('both');
      final uploads = Capture(
        context.bind(Stream.value([1, 2]), direction: upload),
      );
      final downloads = Capture(
        context.bind(Stream.value([3]), direction: download),
      );
      await pump();
      check(
        clock.activeTimers == 2,
        'directions did not get independent timers',
      );
      clock.advance(const Duration(milliseconds: 249));
      await pump();
      check(
        uploads.bytes.isEmpty && downloads.bytes.isEmpty,
        'unpaid data escaped',
      );
      clock.advance(const Duration(milliseconds: 1));
      await pump();
      check(
        uploads.bytes.length == 1 && downloads.bytes.isEmpty,
        'upload quantum timing wrong',
      );
      clock.advance(const Duration(milliseconds: 250));
      await pump();
      await Future.wait([uploads.done.future, downloads.done.future]);
      check(
        allocator.snapshot.uploadBytes == 2 &&
            allocator.snapshot.downloadBytes == 1,
        'direction accounting wrong',
      );
      check(clock.activeTimers == 0, 'settled directions retained timers');
      context.close();
      allocator.dispose();
    },
  );

  await test(
    'many sibling contexts share one fair operation allocation',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 10);
      final a = List.generate(4, (_) => allocator.openContext('a'));
      final b = allocator.openContext('b');
      var sentA = 0, sentB = 0;
      final captures = [
        for (final context in a)
          Capture(
            context.bind(Stream.value([1, 1, 1]), direction: upload),
            onPart: (part) => sentA += part.length,
          ),
        Capture(
          b.bind(Stream.value(List.filled(12, 2)), direction: upload),
          onPart: (part) => sentB += part.length,
        ),
      ];
      await pump();
      for (var step = 0; step < 24; step++) {
        await clock.next();
        check(
          (sentA - sentB).abs() <= 1,
          'task splitting gained a bandwidth share: $sentA/$sentB',
        );
        check(
          sentA + sentB <= clock.elapsed.inMilliseconds ~/ 100,
          'aggregate rate exceeded',
        );
      }
      await settle(clock, captures);
      check(sentA == 12 && sentB == 12, 'payload was lost');
      check(
        allocator.snapshot.activeJobs == 2,
        'context count was mistaken for job count',
      );
      for (final context in [...a, b]) {
        context.close();
      }
      check(
        allocator.snapshot.activeJobs == 0,
        'closed groups retained participation',
      );
      allocator.dispose();
    },
  );

  await test('byte fairness does not depend on request chunk sizes', () async {
    final clock = Clock();
    final allocator = clock.allocator(up: 100);
    final a = allocator.openContext('large-parts');
    final siblings = List.generate(
      40,
      (_) => allocator.openContext('tiny-parts'),
    );
    var sentA = 0, sentB = 0;
    void verify() => check(
      (sentA - sentB).abs() <= 10,
      'fairness used request count instead of byte service',
    );
    final captures = [
      Capture(
        a.bind(Stream.value(List.filled(40, 1)), direction: upload),
        onPart: (part) {
          sentA += part.length;
          verify();
        },
      ),
      for (final sibling in siblings)
        Capture(
          sibling.bind(Stream.value([2]), direction: upload),
          onPart: (part) {
            sentB += part.length;
            verify();
          },
        ),
    ];
    await settle(clock, captures);
    check(
      sentA == 40 &&
          sentB == 40 &&
          clock.elapsed == const Duration(milliseconds: 800),
      'unequal chunk accounting failed',
    );
    for (final context in [a, ...siblings]) {
      context.close();
    }
    allocator.dispose();
  });

  await test(
    'late joiners start at current service without historical catch-up',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 10);
      final a = allocator.openContext('old');
      final ca = Capture(
        a.bind(Stream.value(List.filled(30, 1)), direction: upload),
      );
      for (var step = 0; step < 10; step++) {
        await clock.next();
      }
      check(ca.bytes.length == 10, 'old job setup failed');
      final b = allocator.openContext('late');
      final cb = Capture(
        b.bind(Stream.value(List.filled(10, 2)), direction: upload),
      );
      await pump();
      for (var step = 0; step < 10; step++) {
        await clock.next();
        check(
          ((ca.bytes.length - 10) - cb.bytes.length).abs() <= 1,
          'late job received catch-up credit',
        );
      }
      await settle(clock, [ca, cb]);
      a.close();
      b.close();
      allocator.dispose();
    },
  );

  await test(
    'idle rejoiners receive no credit for time spent without ready data',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 10);
      final a = allocator.openContext('busy');
      final b = allocator.openContext('returning');
      final firstB = Capture(b.bind(Stream.value([2]), direction: upload));
      await clock.next();
      await firstB.done.future;
      final ca = Capture(
        a.bind(Stream.value(List.filled(30, 1)), direction: upload),
      );
      for (var step = 0; step < 10; step++) {
        await clock.next();
      }
      final before = ca.bytes.length;
      final cb = Capture(
        b.bind(Stream.value(List.filled(8, 2)), direction: upload),
      );
      await pump();
      for (var step = 0; step < 8; step++) {
        await clock.next();
        check(
          ((ca.bytes.length - before) - cb.bytes.length).abs() <= 1,
          'returning job accrued idle credit',
        );
      }
      await settle(clock, [ca, cb]);
      a.close();
      b.close();
      allocator.dispose();
    },
  );

  await test(
    'a waiting source does not reserve another ready jobs capacity',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(down: 10);
      final slow = allocator.openContext('slow');
      final fast = allocator.openContext('fast');
      final source = StreamController<List<int>>();
      final waiting = Capture(slow.bind(source.stream, direction: download));
      final ready = Capture(
        fast.bind(Stream.value([1, 2, 3]), direction: download),
      );
      await pump();
      check(
        allocator.snapshot.pendingDownloadJobs == 1,
        'waiting source occupied quota',
      );
      await settle(clock, [ready]);
      check(
        clock.elapsed == const Duration(milliseconds: 300),
        'slow source reduced ready throughput',
      );
      slow.cancel();
      await waiting.done.future;
      check(
        waiting.error is TransferBandwidthCancelled,
        'waiting source did not observe cancellation',
      );
      await source.close();
      slow.close();
      fast.close();
      allocator.dispose();
    },
  );

  await test(
    'pause withdraws pending work and no paused time becomes burst credit',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 4);
      final context = allocator.openContext('paused');
      var cancelled = false;
      context.cancellationFuture.then((_) => cancelled = true);
      final capture = Capture(
        context.bind(Stream.value([1, 2]), direction: upload),
      );
      await pump();
      clock.advance(const Duration(milliseconds: 100));
      context.setPaused(true);
      await pump();
      check(
        clock.activeTimers == 0 && allocator.snapshot.pendingUploadJobs == 0,
        'paused job held quota',
      );
      clock.advance(const Duration(hours: 1));
      await pump();
      check(
        capture.bytes.isEmpty && !cancelled,
        'pause emitted bytes or cancelled context',
      );
      context.setPaused(false);
      await pump();
      check(capture.bytes.isEmpty, 'paused time became burst credit');
      await settle(clock, [capture]);
      check(capture.bytes.length == 2, 'resume lost payload');
      context.close();
      await pump();
      check(cancelled, 'close did not settle cancellation signal');
      allocator.dispose();
    },
  );

  await test(
    'downstream pause releases pending quota for another job',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 10);
      final a = allocator.openContext('paused-consumer');
      final b = allocator.openContext('ready-consumer');
      final ca = Capture(a.bind(Stream.value([1, 2]), direction: upload));
      await pump();
      ca.subscription.pause();
      await pump();
      check(clock.activeTimers == 0, 'consumer pause kept pacing timer');
      final cb = Capture(b.bind(Stream.value([3, 4]), direction: upload));
      await settle(clock, [cb]);
      check(
        ca.bytes.isEmpty && cb.bytes.length == 2,
        'paused consumer retained share',
      );
      ca.subscription.resume();
      await settle(clock, [ca]);
      a.close();
      b.close();
      allocator.dispose();
    },
  );

  await test('limit changes wake pending work and zero is unlimited', () async {
    final clock = Clock();
    final allocator = clock.allocator(up: 1);
    final context = allocator.openContext('changing');
    final capture = Capture(
      context.bind(Stream.value([1, 2, 3]), direction: upload),
    );
    await pump();
    allocator.updateLimits(
      const TransferBandwidthLimits(uploadBytesPerSecond: 10),
    );
    await clock.next();
    check(
      clock.elapsed == const Duration(milliseconds: 100) &&
          capture.bytes.length == 1,
      'new rate did not replace pending wait',
    );
    allocator.updateLimits(const TransferBandwidthLimits());
    await capture.done.future;
    check(
      capture.bytes.length == 3 && clock.activeTimers == 0,
      'zero did not wake unlimited path',
    );
    check(
      allocator.snapshot.uploadBytes == 3,
      'unlimited supported payload not counted',
    );
    context.close();
    allocator.dispose();
  });

  await test(
    'changing upload limits leaves download pacing untouched',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 1, down: 2);
      final context = allocator.openContext('independent-change');
      final capture = Capture(
        context.bind(Stream.value([1]), direction: download),
      );
      await pump();
      clock.advance(const Duration(milliseconds: 100));
      allocator.updateLimits(
        const TransferBandwidthLimits(
          uploadBytesPerSecond: 10,
          downloadBytesPerSecond: 2,
        ),
      );
      await pump();
      clock.advance(const Duration(milliseconds: 400));
      await pump();
      check(
        capture.bytes.length == 1,
        'an upload-only change restarted the download wait',
      );
      await capture.done.future;
      context.close();
      allocator.dispose();
    },
  );

  await test(
    'lowering a limit invalidates already waiting higher-rate slices',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 100);
      final context = allocator.openContext('lowered');
      final capture = Capture(
        context.bind(Stream.value([1, 2]), direction: upload),
      );
      await pump();
      allocator.updateLimits(
        const TransferBandwidthLimits(uploadBytesPerSecond: 1),
      );
      await pump();
      clock.advance(const Duration(milliseconds: 999));
      await pump();
      check(capture.bytes.isEmpty, 'old rate escaped after lowering');
      clock.advance(const Duration(milliseconds: 1));
      await pump();
      check(
        capture.bytes.length == 1,
        'lowered rate did not deliver one paid byte',
      );
      await settle(clock, [capture]);
      context.close();
      allocator.dispose();
    },
  );

  await test(
    'one-byte and maximum allowed rates retain safe timing arithmetic',
    () async {
      for (final rate in [1, TransferBandwidthLimits.maximumBytesPerSecond]) {
        final clock = Clock();
        final allocator = clock.allocator(up: rate);
        final context = allocator.openContext('rate-$rate');
        final length = rate == 1 ? 1 : 65536;
        final capture = Capture(
          context.bind(Stream.value(List.filled(length, 7)), direction: upload),
        );
        await settle(clock, [capture]);
        check(capture.bytes.length == length, 'rate arithmetic lost bytes');
        check(
          clock.elapsed.inMicroseconds == (rate == 1 ? 1000000 : 1),
          'rate arithmetic overflowed',
        );
        context.close();
        allocator.dispose();
      }
    },
  );

  await test(
    'cancel affects sibling contexts while close releases only its own demand',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 1);
      final first = allocator.openContext('shared');
      final second = allocator.openContext('shared');
      final ca = Capture(first.bind(Stream.value([1]), direction: upload));
      final cb = Capture(second.bind(Stream.value([2]), direction: upload));
      await pump();
      first.close();
      await ca.done.future;
      check(
        ca.error is TransferBandwidthCancelled && !second.isCancelled,
        'close cancelled siblings',
      );
      await settle(clock, [cb]);
      check(cb.bytes.single == 2, 'sibling lost its demand');
      final third = allocator.openContext('shared');
      final cc = Capture(third.bind(Stream.value([3]), direction: upload));
      await pump();
      second.cancel();
      await Future.wait([
        second.cancellationFuture,
        third.cancellationFuture,
        cc.done.future,
      ]);
      check(
        cc.error is TransferBandwidthCancelled &&
            allocator.snapshot.pendingUploadJobs == 0,
        'group cancellation left demand',
      );
      second.close();
      third.close();
      allocator.dispose();
    },
  );

  await test(
    'allocator disposal wakes sources, paused consumers and quotas',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 1);
      final waitingSource = StreamController<List<int>>();
      final a = allocator.openContext('source');
      final b = allocator.openContext('quota');
      final c = allocator.openContext('paused');
      final captures = [
        Capture(a.bind(waitingSource.stream, direction: upload)),
        Capture(b.bind(Stream.value([1]), direction: upload)),
        Capture(c.bind(Stream.value([2]), direction: upload)),
      ];
      c.setPaused(true);
      await pump();
      allocator.dispose();
      await Future.wait(captures.map((capture) => capture.done.future));
      check(
        captures.every(
          (capture) => capture.error is TransferBandwidthCancelled,
        ),
        'dispose did not settle all waits',
      );
      check(
        clock.activeTimers == 0 && allocator.snapshot.activeJobs == 0,
        'dispose retained work',
      );
      await waitingSource.close();
    },
  );

  await test(
    'captured binding remains owned by A when subscribed inside B',
    () async {
      final allocator = TransferBandwidthAllocator();
      final a = allocator.openContext('a');
      final b = allocator.openContext('b');
      TransferBandwidthContext? sourceContext;
      Stream<List<int>> source() async* {
        sourceContext = TransferBandwidthContext.current;
        yield [1, 2];
      }

      final stream = a.run(() {
        check(
          identical(TransferBandwidthContext.current, a),
          'zone did not capture A',
        );
        return TransferBandwidthContext.current!.bind(
          source(),
          direction: upload,
        );
      });
      a.setPaused(true);
      final capture = b.run(() {
        check(
          identical(TransferBandwidthContext.current, b),
          'zone did not capture B',
        );
        return Capture(stream);
      });
      await pump();
      check(
        capture.bytes.isEmpty,
        'subscription adopted B instead of paused A',
      );
      a.setPaused(false);
      await capture.done.future;
      check(
        capture.bytes.length == 2 && TransferBandwidthContext.current == null,
        'zone leaked or payload lost',
      );
      check(
        identical(sourceContext, a),
        'a lazy source or nested transport adopted subscriber B',
      );
      a.close();
      b.close();
      allocator.dispose();
    },
  );

  await test(
    'a closed captured context cannot reopen under a reused job ID',
    () async {
      final allocator = TransferBandwidthAllocator();
      final old = allocator.openContext('same-id');
      final stream = old.bind(Stream.value([1]), direction: upload);
      old.close();
      final replacement = allocator.openContext('same-id');
      final capture = replacement.run(() => Capture(stream));
      await capture.done.future;
      check(
        capture.error is TransferBandwidthCancelled && capture.bytes.isEmpty,
        'closed identity adopted replacement',
      );
      replacement.close();
      allocator.dispose();
    },
  );

  await test('unsupported paths preserve bytes and controls without false upload accounting', () async {
    final clock = Clock();
    final allocator = clock.allocator(up: 1);
    final context = allocator.openContext('browser');
    final capture = Capture(
      context.bind(
        Stream.value([1, 2, 3]),
        direction: upload,
        supported: false,
      ),
    );
    await capture.done.future;
    check(
      capture.bytes.join(',') == '1,2,3' && clock.activeTimers == 0,
      'unsupported path was throttled or changed',
    );
    check(
      allocator.snapshot.uploadBytes == 0 &&
          allocator.snapshot.unsupportedUploadJobs == 1,
      'preparation counted as transport',
    );
    context.markUnsupported(download);
    check(
      allocator.snapshot.unsupportedDownloadJobs == 1,
      'streamless unsupported hook absent',
    );
    context.close();
    check(
      allocator.snapshot.unsupportedUploadJobs == 0,
      'closed job retained live coverage',
    );
    allocator.dispose();
  });

  await test('reused 100KiB input is copied under pull backpressure into immutable slices', () async {
    final allocator = TransferBandwidthAllocator();
    final context = allocator.openContext('reused');
    final input = Uint8List(100 * 1024)..fillRange(0, 100 * 1024, 1);
    Stream<List<int>> source() async* {
      yield input;
      input.fillRange(0, input.length, 2);
      yield input;
    }

    final capture = Capture(context.bind(source(), direction: download));
    await capture.done.future;
    check(
      capture.error == null && capture.bytes.length == 200 * 1024,
      'reused payload length wrong',
    );
    check(
      capture.bytes.take(100 * 1024).every((byte) => byte == 1),
      'first buffer was reused too soon',
    );
    check(
      capture.bytes.skip(100 * 1024).every((byte) => byte == 2),
      'second buffer wrong',
    );
    check(
      capture.parts.every((part) => part.length <= 65536),
      'unbounded handoff slice',
    );
    await expectFailure(
      () async => capture.parts.first[0] = 9,
      (error) => error is UnsupportedError,
    );
    context.close();
    allocator.dispose();
  });

  await test('original read error is delivered before stalled upstream cancellation completes', () async {
    final allocator = TransferBandwidthAllocator();
    final context = allocator.openContext('error');
    final cleanup = Completer<void>();
    final failure = StateError('original transport read error');
    var cancellationRequested = false;
    late StreamController<List<int>> source;
    source = StreamController<List<int>>(
      onListen: () => scheduleMicrotask(() => source.addError(failure)),
      onCancel: () {
        cancellationRequested = true;
        return cleanup.future;
      },
    );
    final capture = Capture(context.bind(source.stream, direction: download));
    try {
      await capture.done.future;
      check(
        identical(capture.error, failure) &&
            cancellationRequested &&
            !cleanup.isCompleted,
        'read error waited for or was replaced by cleanup',
      );
      check(
        allocator.snapshot.pendingDownloadJobs == 0,
        'failed reader held quota',
      );
    } finally {
      cleanup.complete();
      await source.close();
      context.close();
      allocator.dispose();
    }
  });

  await test(
    'downstream cancellation detaches stalled provider cleanup promptly',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 1);
      final context = allocator.openContext('consumer-cancel');
      final cleanup = Completer<void>();
      final source = StreamController<List<int>>(
        onCancel: () => cleanup.future,
      );
      final capture = Capture(context.bind(source.stream, direction: upload));
      source.add([1]);
      await pump();
      try {
        await capture.subscription.cancel();
        check(
          !cleanup.isCompleted && clock.activeTimers == 0,
          'consumer cancel awaited provider cleanup',
        );
        check(
          allocator.snapshot.uploadBytes == 0,
          'cancelled unsubmitted byte was counted',
        );
      } finally {
        cleanup.complete();
        await source.close();
        context.close();
        allocator.dispose();
      }
    },
  );

  await test(
    'submitted payload is not refunded when a later source error occurs',
    () async {
      final allocator = TransferBandwidthAllocator();
      final context = allocator.openContext('partial');
      Stream<List<int>> source() async* {
        yield [1, 2, 3];
        throw StateError('after handoff');
      }

      final capture = Capture(context.bind(source(), direction: upload));
      await capture.done.future;
      check(
        capture.error is StateError && allocator.snapshot.uploadBytes == 3,
        'failure refunded submitted bytes',
      );
      context.close();
      allocator.dispose();
    },
  );

  await test('observed direction rates decay without idle timers', () async {
    final clock = Clock();
    final allocator = clock.allocator();
    final context = allocator.openContext('observed');
    await context
        .bind(Stream.value(List.filled(1024, 1)), direction: upload)
        .drain<void>();
    check(
      allocator.snapshot.uploadBytesPerSecond == 1024,
      'recent handoff rate absent',
    );
    clock.advance(const Duration(seconds: 2));
    check(
      allocator.snapshot.uploadBytesPerSecond == 0 &&
          allocator.snapshot.uploadBytes == 1024,
      'idle rate did not decay',
    );
    check(clock.activeTimers == 0, 'rate observation retained an idle timer');
    context.close();
    allocator.dispose();
  });

  await test(
    'invalid input bytes fail before handoff and release quota',
    () async {
      final clock = Clock();
      final allocator = clock.allocator(up: 1);
      final context = allocator.openContext('invalid');
      final capture = Capture(
        context.bind(Stream.value([256]), direction: upload),
      );
      await capture.done.future;
      check(
        capture.error is RangeError && allocator.snapshot.uploadBytes == 0,
        'invalid byte was normalized or delivered',
      );
      check(clock.activeTimers == 0, 'invalid bytes retained pacing work');
      context.close();
      allocator.dispose();
    },
  );

  print(
    jsonEncode({
      'suite': 'shared-transfer-bandwidth',
      'passed': passed,
      'failed': 0,
    }),
  );
}
