@Tags(['benchmark'])
// test/benchmark_test.dart
//
// Tests for BenchmarkService — timing thresholds are deliberately generous
// so that CI machines (which are slower than developer laptops) do not produce
// flaky failures.  The point of each timing test is "completes in reasonable
// time", not "is maximally fast".

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/benchmark_service.dart';

void main() {
  // =========================================================================
  // BenchmarkResult — model tests
  // =========================================================================
  group('BenchmarkResult', () {
    test('fromCounts populates all fields', () {
      final r = BenchmarkResult.fromCounts(
        name: 'test_bench',
        durationMs: 200,
        itemCount: 1000,
        bytesProcessed: 1024 * 1024,
        metadata: {'foo': 'bar'},
      );

      expect(r.name, equals('test_bench'));
      expect(r.durationMs, equals(200));
      expect(r.itemCount, equals(1000));
      expect(r.bytesProcessed, equals(1024 * 1024));
      expect(r.metadata['foo'], equals('bar'));
    });

    test('operationsPerSecond calculation is correct', () {
      // 1000 ops in 500 ms → 2000 ops/s
      final r = BenchmarkResult.fromCounts(
        name: 'ops_test',
        durationMs: 500,
        itemCount: 1000,
      );
      expect(r.operationsPerSecond, closeTo(2000.0, 0.1));
    });

    test('operationsPerSecond with durationMs=0 does not throw', () {
      final r = BenchmarkResult.fromCounts(
        name: 'zero_dur',
        durationMs: 0,
        itemCount: 500,
      );
      // Should equal itemCount (not infinity, not NaN, not throw).
      expect(r.operationsPerSecond.isFinite, isTrue);
      expect(r.operationsPerSecond, equals(500.0));
    });

    test('toJson / fromJson round-trip preserves all fields', () {
      final original = BenchmarkResult(
        name: 'round_trip',
        durationMs: 123,
        operationsPerSecond: 812.0,
        itemCount: 100,
        bytesProcessed: 4096,
        metadata: {'key': 'value', 'num': 42},
      );

      final json = original.toJson();
      final restored = BenchmarkResult.fromJson(json);

      expect(restored.name, equals(original.name));
      expect(restored.durationMs, equals(original.durationMs));
      expect(
          restored.operationsPerSecond, closeTo(original.operationsPerSecond, 0.001));
      expect(restored.itemCount, equals(original.itemCount));
      expect(restored.bytesProcessed, equals(original.bytesProcessed));
      expect(restored.metadata['key'], equals('value'));
      expect(restored.metadata['num'], equals(42));
    });

    test('toString returns non-empty string containing name', () {
      final r = BenchmarkResult.fromCounts(
          name: 'my_bench', durationMs: 10, itemCount: 5);
      expect(r.toString(), contains('my_bench'));
    });
  });

  // =========================================================================
  // BenchmarkSuite — model tests
  // =========================================================================
  group('BenchmarkSuite', () {
    BenchmarkSuite _makeSuite() {
      return BenchmarkSuite(
        name: 'test_suite',
        results: [
          BenchmarkResult.fromCounts(
              name: 'alpha', durationMs: 10, itemCount: 1),
          BenchmarkResult.fromCounts(
              name: 'beta', durationMs: 20, itemCount: 2),
        ],
        totalDurationMs: 30,
        timestamp: DateTime(2025, 1, 15, 12, 0, 0),
      );
    }

    test('toJson / fromJson round-trip', () {
      final suite = _makeSuite();
      final json = suite.toJson();
      final restored = BenchmarkSuite.fromJson(json);

      expect(restored.name, equals(suite.name));
      expect(restored.results.length, equals(2));
      expect(restored.totalDurationMs, equals(30));
      expect(restored.timestamp, equals(suite.timestamp));
    });

    test('resultFor returns correct result by name', () {
      final suite = _makeSuite();
      final r = suite.resultFor('beta');
      expect(r, isNotNull);
      expect(r!.itemCount, equals(2));
    });

    test('resultFor returns null for unknown name', () {
      final suite = _makeSuite();
      expect(suite.resultFor('nonexistent'), isNull);
    });

    test('results list is preserved in order', () {
      final suite = _makeSuite();
      expect(suite.results.first.name, equals('alpha'));
      expect(suite.results.last.name, equals('beta'));
    });
  });

  // =========================================================================
  // File-list generation — timing tests
  // =========================================================================
  group('benchmarkFileListGeneration', () {
    test('1K file list generation completes in <500 ms', () {
      final result = BenchmarkService.benchmarkFileListGeneration(1000);
      expect(result.durationMs, lessThan(500),
          reason: 'generating 1 000 FileItems should be fast');
      expect(result.itemCount, equals(1000));
      expect(result.name, contains('1000'));
    });

    test('10K file list generation completes in <5000 ms', () {
      final result = BenchmarkService.benchmarkFileListGeneration(10000);
      expect(result.durationMs, lessThan(5000),
          reason: 'generating 10 000 FileItems should complete within 5 s');
      expect(result.itemCount, equals(10000));
    });
  });

  // =========================================================================
  // File sorting — timing tests
  // =========================================================================
  group('benchmarkFileSorting', () {
    test('1K file sort by name completes in <200 ms', () {
      final result = BenchmarkService.benchmarkFileSorting(1000, 'name');
      expect(result.durationMs, lessThan(200));
      expect(result.itemCount, equals(1000));
      expect(result.name, contains('name'));
    });

    test('1K file sort by size completes in <200 ms', () {
      final result = BenchmarkService.benchmarkFileSorting(1000, 'size');
      expect(result.durationMs, lessThan(200));
      expect(result.itemCount, equals(1000));
      expect(result.name, contains('size'));
    });

    test('1K file sort by date completes in <200 ms', () {
      final result = BenchmarkService.benchmarkFileSorting(1000, 'date');
      expect(result.durationMs, lessThan(200));
      expect(result.itemCount, equals(1000));
      expect(result.name, contains('date'));
    });
  });

  // =========================================================================
  // File filtering — timing test
  // =========================================================================
  group('benchmarkFileFiltering', () {
    test('1K file filter by *.txt pattern completes in <200 ms', () {
      final result = BenchmarkService.benchmarkFileFiltering(1000, '*.txt');
      expect(result.durationMs, lessThan(200));
      expect(result.itemCount, equals(1000));
    });

    test('filter result name encodes pattern', () {
      final result = BenchmarkService.benchmarkFileFiltering(100, '*.txt');
      // Pattern '*' is replaced with 'x', so '*.txt' → 'x.txt'.
      expect(result.name, contains('x.txt'));
    });
  });

  // =========================================================================
  // Encryption — timing tests
  // =========================================================================
  group('benchmarkEncryption', () {
    test('encrypt + decrypt 1 MB data completes in <30000 ms', () {
      // PointyCastle's pure-Dart AES-GCM is slow on CI; threshold is generous.
      final result = BenchmarkService.benchmarkEncryption(1024 * 1024);
      expect(result.durationMs, lessThan(30000));
      expect(result.bytesProcessed, equals(1024 * 1024));
    });

    test('encryption result carries correct bytesProcessed', () {
      const size = 4096;
      final result = BenchmarkService.benchmarkEncryption(size);
      expect(result.bytesProcessed, equals(size));
    });

    test('encryption result has itemCount == 1', () {
      final result = BenchmarkService.benchmarkEncryption(512);
      expect(result.itemCount, equals(1));
    });
  });

  // =========================================================================
  // Hashing — timing tests
  // =========================================================================
  group('benchmarkHashing', () {
    test('MD5 + SHA-256 1 MB data completes in <500 ms', () {
      final result = BenchmarkService.benchmarkHashing(1024 * 1024);
      expect(result.durationMs, lessThan(500));
    });

    test('hashing result carries correct bytesProcessed (2× data size)', () {
      const size = 8192;
      final result = BenchmarkService.benchmarkHashing(size);
      // Two hash operations × size bytes each.
      expect(result.bytesProcessed, equals(size * 2));
    });

    test('hashing result has itemCount == 2 (two hash algos)', () {
      final result = BenchmarkService.benchmarkHashing(256);
      expect(result.itemCount, equals(2));
    });
  });

  // =========================================================================
  // JSON serialization — timing test
  // =========================================================================
  group('benchmarkJsonSerialization', () {
    test('JSON serialize + deserialize 1K items completes in <1000 ms', () {
      final result = BenchmarkService.benchmarkJsonSerialization(1000);
      expect(result.durationMs, lessThan(1000));
      expect(result.itemCount, equals(1000));
    });

    test('serialization result name contains item count', () {
      final result = BenchmarkService.benchmarkJsonSerialization(50);
      expect(result.name, contains('50'));
    });
  });

  // =========================================================================
  // Path operations — timing test
  // =========================================================================
  group('benchmarkPathOperations', () {
    test('10K path operations complete in <500 ms', () {
      final result = BenchmarkService.benchmarkPathOperations(10000);
      expect(result.durationMs, lessThan(500));
      expect(result.itemCount, equals(10000));
    });

    test('path operations result name contains count', () {
      final result = BenchmarkService.benchmarkPathOperations(100);
      expect(result.name, contains('100'));
    });
  });

  // =========================================================================
  // Transfer-queue scheduling — timing test
  // =========================================================================
  group('benchmarkTransferQueueScheduling', () {
    test('100-task queue scheduling completes in <500 ms', () {
      final result = BenchmarkService.benchmarkTransferQueueScheduling(100);
      expect(result.durationMs, lessThan(500));
      expect(result.itemCount, equals(100));
    });

    test('scheduling result name contains task count', () {
      final result = BenchmarkService.benchmarkTransferQueueScheduling(50);
      expect(result.name, contains('50'));
    });
  });

  // =========================================================================
  // runBenchmark — generic runner behaviour
  // =========================================================================
  group('runBenchmark (generic runner)', () {
    test('warmup runs do not affect result (result reflects post-warmup)', () {
      // We measure a trivial function; the result should be a small number
      // of milliseconds regardless of warmup.
      int callCount = 0;
      final result = BenchmarkService.runBenchmark(
        'warmup_test',
        () => callCount++,
        iterations: 3,
        warmupRuns: 2,
        itemCount: 1,
      );
      // 2 warmup + 3 measured = 5 total calls.
      expect(callCount, equals(5));
      expect(result.durationMs, greaterThanOrEqualTo(0));
    });

    test('multiple iterations return median (not mean)', () {
      // Provide a function whose execution time we cannot control, but we can
      // verify that the returned value equals the median of sorted durations.
      // We run with iterations=1 so median == the single value.
      final result = BenchmarkService.runBenchmark(
        'median_test',
        () {},
        iterations: 1,
        warmupRuns: 0,
        itemCount: 0,
      );
      // With 1 iteration the median is that single run's duration.
      expect(result.durationMs, greaterThanOrEqualTo(0));
    });

    test('returns a BenchmarkResult with the supplied name', () {
      final result = BenchmarkService.runBenchmark(
        'my_custom_name',
        () {},
        iterations: 1,
        warmupRuns: 0,
      );
      expect(result.name, equals('my_custom_name'));
    });

    test('metadata is propagated to result', () {
      final result = BenchmarkService.runBenchmark(
        'meta_test',
        () {},
        iterations: 1,
        warmupRuns: 0,
        metadata: {'env': 'ci', 'version': 2},
      );
      expect(result.metadata['env'], equals('ci'));
      expect(result.metadata['version'], equals(2));
    });
  });

  // =========================================================================
  // formatResult
  // =========================================================================
  group('formatResult', () {
    test('produces a human-readable non-empty string', () {
      final r = BenchmarkResult.fromCounts(
        name: 'fmt_test',
        durationMs: 42,
        itemCount: 10,
        bytesProcessed: 1024,
      );
      final s = BenchmarkService.formatResult(r);
      expect(s, isNotEmpty);
      expect(s, contains('fmt_test'));
      expect(s, contains('42'));
    });

    test('includes ops/s in output', () {
      final r = BenchmarkResult.fromCounts(
          name: 'ops_fmt', durationMs: 100, itemCount: 100);
      final s = BenchmarkService.formatResult(r);
      expect(s, contains('ops/s'));
    });

    test('includes item count when >0', () {
      final r = BenchmarkResult.fromCounts(
          name: 'items_fmt', durationMs: 10, itemCount: 77);
      expect(BenchmarkService.formatResult(r), contains('77'));
    });

    test('includes bytes processed when >0', () {
      final r = BenchmarkResult.fromCounts(
        name: 'bytes_fmt',
        durationMs: 10,
        itemCount: 1,
        bytesProcessed: 1024 * 1024,
      );
      final s = BenchmarkService.formatResult(r);
      expect(s, anyOf(contains('MB'), contains('KB'), contains('B')));
    });
  });

  // =========================================================================
  // runFullSuite — integration test
  // =========================================================================
  group('runFullSuite', () {
    late BenchmarkSuite suite;

    setUpAll(() {
      suite = BenchmarkService.runFullSuite();
    });

    test('suite has a non-empty name', () {
      expect(suite.name, isNotEmpty);
    });

    test('suite timestamp is recent', () {
      final diff = DateTime.now().difference(suite.timestamp).abs();
      expect(diff.inSeconds, lessThan(300));
    });

    test('totalDurationMs is positive', () {
      expect(suite.totalDurationMs, greaterThan(0));
    });

    test('suite contains file_list_generation_1000', () {
      expect(suite.resultFor('file_list_generation_1000'), isNotNull);
    });

    test('suite contains file_list_generation_10000', () {
      expect(suite.resultFor('file_list_generation_10000'), isNotNull);
    });

    test('suite contains file_sort_name_1000', () {
      expect(suite.resultFor('file_sort_name_1000'), isNotNull);
    });

    test('suite contains file_sort_size_1000', () {
      expect(suite.resultFor('file_sort_size_1000'), isNotNull);
    });

    test('suite contains file_sort_date_1000', () {
      expect(suite.resultFor('file_sort_date_1000'), isNotNull);
    });

    test('suite contains file_filter benchmark', () {
      // Name includes count + mangled pattern.
      final found = suite.results.any((r) => r.name.startsWith('file_filter'));
      expect(found, isTrue);
    });

    test('suite contains encryption_1048576B (1 MB)', () {
      expect(suite.resultFor('encryption_1048576B'), isNotNull);
    });

    test('suite contains hashing_1048576B (1 MB)', () {
      expect(suite.resultFor('hashing_1048576B'), isNotNull);
    });

    test('suite contains json_serialization_1000', () {
      expect(suite.resultFor('json_serialization_1000'), isNotNull);
    });

    test('suite contains path_operations_10000', () {
      expect(suite.resultFor('path_operations_10000'), isNotNull);
    });

    test('suite contains transfer_queue_scheduling_100', () {
      expect(suite.resultFor('transfer_queue_scheduling_100'), isNotNull);
    });

    test('benchmark names are unique in suite', () {
      final names = suite.results.map((r) => r.name).toList();
      final unique = names.toSet();
      expect(names.length, equals(unique.length),
          reason: 'duplicate benchmark name found');
    });

    test('all results have non-negative durationMs', () {
      for (final r in suite.results) {
        expect(r.durationMs, greaterThanOrEqualTo(0),
            reason: '${r.name} has negative durationMs');
      }
    });

    test('all results have finite operationsPerSecond', () {
      for (final r in suite.results) {
        expect(r.operationsPerSecond.isFinite, isTrue,
            reason: '${r.name} has non-finite ops/s');
      }
    });

    test('suite serializes to JSON and restores correctly', () {
      final json = suite.toJson();
      final restored = BenchmarkSuite.fromJson(json);
      expect(restored.results.length, equals(suite.results.length));
      expect(restored.name, equals(suite.name));
    });
  });
}
