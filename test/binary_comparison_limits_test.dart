import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/file_comparison_service.dart';

void main() {
  test('unknown-length streams enforce the byte cap on each side', () async {
    for (final oversizedLeft in [false, true]) {
      final oversized = Stream<List<int>>.fromIterable([
        [1, 2],
        [3, 4, 5],
      ]);
      final small = Stream<List<int>>.value([1, 2]);
      await expectLater(
        compareBinaryStreams(
          oversizedLeft ? oversized : small,
          oversizedLeft ? small : oversized,
          limits: const BinaryComparisonLimits(maxBytes: 4),
        ),
        throwsA(isA<BinaryComparisonLimitExceeded>()),
      );
    }
  });

  test(
    'expected lengths reject truncation and extra bytes after the end',
    () async {
      for (final actual in [1, 3]) {
        await expectLater(
          compareBinaryStreams(
            Stream.value(List<int>.filled(actual, 0)),
            Stream.value([0, 0]),
            expectedLeftBytes: 2,
            expectedRightBytes: 2,
          ),
          throwsA(isA<BinaryComparisonSourceChanged>()),
        );
      }
      final exact = await compareBinaryStreams(
        Stream.fromIterable([
          [1, 2],
          [],
        ]),
        Stream.value([1, 2]),
        expectedLeftBytes: 2,
        expectedRightBytes: 2,
        limits: const BinaryComparisonLimits(maxBytes: 2),
      );
      expect(exact.equal, isTrue);
      expect(exact.leftBytes, 2);
      expect(exact.rightBytes, 2);
    },
  );

  test(
    'chunk and empty-chunk work budgets are independent of byte limits',
    () async {
      await expectLater(
        compareBinaryStreams(
          Stream.fromIterable([
            [0],
            [0],
            [0],
          ]),
          Stream.value([0, 0, 0]),
          limits: const BinaryComparisonLimits(maxChunks: 2),
        ),
        throwsA(isA<BinaryComparisonLimitExceeded>()),
      );
      await expectLater(
        compareBinaryStreams(
          Stream.fromIterable([
            <int>[],
            [0],
            <int>[],
            [0],
            <int>[],
          ]),
          Stream.value([0, 0]),
          limits: const BinaryComparisonLimits(maxEmptyChunks: 2),
        ),
        throwsA(isA<BinaryComparisonLimitExceeded>()),
      );
    },
  );

  test('empty and tiny chunk streams yield to cancellation', () async {
    for (final empty in [true, false]) {
      var cancelled = false;
      var emitted = 0;
      Stream<List<int>> input() async* {
        while (true) {
          emitted++;
          yield empty ? <int>[] : [0];
        }
      }

      final timer = Timer(Duration.zero, () => cancelled = true);
      try {
        await expectLater(
          compareBinaryStreams(
            input(),
            empty ? const Stream.empty() : input(),
            isCancelled: () => cancelled,
            limits: const BinaryComparisonLimits(
              maxEmptyChunks: 100000,
              maxChunks: 100000,
            ),
          ).timeout(const Duration(seconds: 2)),
          throwsA(isA<BinaryComparisonCancelled>()),
        );
        expect(emitted, lessThan(100000));
      } finally {
        timer.cancel();
      }
    }
  });

  test(
    'inactivity times out a provider even when cancellation cleanup stalls',
    () async {
      final cleanup = Completer<void>();
      final input = StreamController<List<int>>(onCancel: () => cleanup.future);
      try {
        await expectLater(
          compareBinaryStreams(
            input.stream,
            const Stream.empty(),
            limits: const BinaryComparisonLimits(
              inactivityTimeout: Duration(milliseconds: 20),
            ),
          ).timeout(const Duration(seconds: 2)),
          throwsA(
            isA<TimeoutException>().having(
              (error) => error.message,
              'message',
              contains('stopped making progress'),
            ),
          ),
        );
      } finally {
        cleanup.complete();
        await input.close();
      }
    },
  );

  test(
    'overall time is bounded even while chunks keep making progress',
    () async {
      Stream<List<int>> active() async* {
        while (true) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
          yield [0];
        }
      }

      await expectLater(
        compareBinaryStreams(
          active(),
          active(),
          limits: const BinaryComparisonLimits(
            overallTimeout: Duration(milliseconds: 25),
            inactivityTimeout: Duration(seconds: 1),
          ),
        ).timeout(const Duration(seconds: 2)),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.message,
            'message',
            contains('overall time'),
          ),
        ),
      );
    },
  );

  test(
    'invalid budgets and expected lengths fail before subscribing',
    () async {
      var listens = 0;
      Stream<List<int>> input() =>
          StreamController<List<int>>(onListen: () => listens++).stream;
      final invalid = <Future<BinaryComparison> Function()>[
        () => compareBinaryStreams(input(), input(), maxIndexedRanges: 1),
        () => compareBinaryStreams(input(), input(), maxIndexedRanges: 4097),
        () => compareBinaryStreams(input(), input(), expectedLeftBytes: -1),
        () => compareBinaryStreams(
          input(),
          input(),
          expectedRightBytes: 3,
          limits: const BinaryComparisonLimits(maxBytes: 2),
        ),
        () => compareBinaryStreams(
          input(),
          input(),
          limits: const BinaryComparisonLimits(maxChunks: 0),
        ),
      ];
      for (final compare in invalid) {
        await expectLater(compare(), throwsArgumentError);
      }
      expect(listens, 0);
    },
  );

  test('non-byte values are not silently normalized', () async {
    for (final invalid in [-1, 256]) {
      await expectLater(
        compareBinaryStreams(Stream.value([invalid]), Stream.value([invalid])),
        throwsFormatException,
      );
    }
  });

  test(
    'deterministic fragmented streams agree with an independent byte oracle',
    () async {
      final random = Random(6735);
      Stream<List<int>> chunks(List<int> bytes) {
        final parts = <List<int>>[];
        var offset = 0;
        while (offset < bytes.length) {
          if (random.nextBool()) parts.add([]);
          final end = min(bytes.length, offset + 1 + random.nextInt(17));
          parts.add(bytes.sublist(offset, end));
          offset = end;
        }
        return Stream.fromIterable(parts);
      }

      for (var trial = 0; trial < 100; trial++) {
        final left = List<int>.generate(
          random.nextInt(200),
          (_) => random.nextInt(4),
        );
        final right = List<int>.generate(
          random.nextInt(200),
          (_) => random.nextInt(4),
        );
        final unequal = List<bool>.generate(
          max(left.length, right.length),
          (i) => i >= left.length || i >= right.length || left[i] != right[i],
        );
        final starts = <int>[], ends = <int>[];
        for (var i = 0; i < unequal.length; i++) {
          if (unequal[i] && (i == 0 || !unequal[i - 1])) starts.add(i);
          if (unequal[i] && (i + 1 == unequal.length || !unequal[i + 1])) {
            ends.add(i + 1);
          }
        }
        final result = await compareBinaryStreams(
          chunks(left),
          chunks(right),
          expectedLeftBytes: left.length,
          expectedRightBytes: right.length,
        );
        expect(result.leftBytes, left.length);
        expect(result.rightBytes, right.length);
        expect(result.differingBytes, unequal.where((value) => value).length);
        expect(result.rangeCount, starts.length);
        expect(result.ranges.map((range) => range.start), starts);
        expect(result.ranges.map((range) => range.end), ends);
        expect(result.firstDifference, starts.isEmpty ? null : starts.first);
      }
    },
  );
}
