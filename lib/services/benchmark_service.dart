// lib/services/benchmark_service.dart
//
// Pure-Dart performance benchmarks for CrispCloud algorithmic operations.
// No IO or network — measures in-memory throughput and scheduling overhead.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'encryption_service.dart';

// ---------------------------------------------------------------------------
// Result / Suite models
// ---------------------------------------------------------------------------

/// The result of a single benchmark run.
class BenchmarkResult {
  final String name;
  final int durationMs;
  final double operationsPerSecond;
  final int itemCount;
  final int bytesProcessed;
  final Map<String, dynamic> metadata;

  const BenchmarkResult({
    required this.name,
    required this.durationMs,
    required this.operationsPerSecond,
    required this.itemCount,
    required this.bytesProcessed,
    this.metadata = const {},
  });

  /// Compute operationsPerSecond from raw counts (avoids division by zero).
  static double _opsPerSec(int ops, int durationMs) {
    if (durationMs <= 0) return ops.toDouble();
    return ops * 1000.0 / durationMs;
  }

  factory BenchmarkResult.fromCounts({
    required String name,
    required int durationMs,
    required int itemCount,
    int bytesProcessed = 0,
    Map<String, dynamic> metadata = const {},
  }) {
    return BenchmarkResult(
      name: name,
      durationMs: durationMs,
      operationsPerSecond: _opsPerSec(itemCount, durationMs),
      itemCount: itemCount,
      bytesProcessed: bytesProcessed,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'durationMs': durationMs,
        'operationsPerSecond': operationsPerSecond,
        'itemCount': itemCount,
        'bytesProcessed': bytesProcessed,
        'metadata': metadata,
      };

  factory BenchmarkResult.fromJson(Map<String, dynamic> json) {
    return BenchmarkResult(
      name: json['name'] as String,
      durationMs: json['durationMs'] as int,
      operationsPerSecond: (json['operationsPerSecond'] as num).toDouble(),
      itemCount: json['itemCount'] as int,
      bytesProcessed: json['bytesProcessed'] as int,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  @override
  String toString() => 'BenchmarkResult(name=$name, durationMs=$durationMs, '
      'ops/s=${operationsPerSecond.toStringAsFixed(1)}, '
      'items=$itemCount, bytes=$bytesProcessed)';
}

/// A collection of benchmark results forming one full suite run.
class BenchmarkSuite {
  final String name;
  final List<BenchmarkResult> results;
  final int totalDurationMs;
  final DateTime timestamp;

  const BenchmarkSuite({
    required this.name,
    required this.results,
    required this.totalDurationMs,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'results': results.map((r) => r.toJson()).toList(),
        'totalDurationMs': totalDurationMs,
        'timestamp': timestamp.toIso8601String(),
      };

  factory BenchmarkSuite.fromJson(Map<String, dynamic> json) {
    return BenchmarkSuite(
      name: json['name'] as String,
      results: (json['results'] as List<dynamic>)
          .map((e) => BenchmarkResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalDurationMs: json['totalDurationMs'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Returns the result with [name], or null if not found.
  BenchmarkResult? resultFor(String name) {
    try {
      return results.firstWhere((r) => r.name == name);
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// BenchmarkService
// ---------------------------------------------------------------------------

class BenchmarkService {
  static final _rng = Random(42); // fixed seed for reproducibility

  // -------------------------------------------------------------------------
  // Generic runner
  // -------------------------------------------------------------------------

  /// Time [function] over [iterations] runs (plus [warmupRuns] discarded runs),
  /// then return a [BenchmarkResult] based on the median duration.
  ///
  /// [itemCount] and [bytesProcessed] are attached as-is to the result.
  static BenchmarkResult runBenchmark(
    String name,
    void Function() function, {
    int iterations = 5,
    int warmupRuns = 2,
    int itemCount = 0,
    int bytesProcessed = 0,
    Map<String, dynamic> metadata = const {},
  }) {
    // Warmup — discard results.
    for (var i = 0; i < warmupRuns; i++) {
      function();
    }

    final durations = <int>[];
    for (var i = 0; i < iterations; i++) {
      final sw = Stopwatch()..start();
      function();
      sw.stop();
      durations.add(sw.elapsedMilliseconds);
    }

    durations.sort();
    final medianMs = durations[durations.length ~/ 2];

    return BenchmarkResult.fromCounts(
      name: name,
      durationMs: medianMs,
      itemCount: itemCount,
      bytesProcessed: bytesProcessed,
      metadata: metadata,
    );
  }

  // -------------------------------------------------------------------------
  // File-list benchmarks
  // -------------------------------------------------------------------------

  static List<FileItem> _buildFileList(int count) {
    return List.generate(count, (i) {
      final ext = _kExts[i % _kExts.length];
      return FileItem(
        name: 'file_${i.toString().padLeft(6, '0')}.$ext',
        path: '/bench/dir_${i % 100}/file_${i.toString().padLeft(6, '0')}.$ext',
        uuid: 'uuid-$i',
        isFolder: i % 20 == 0,
        size: (i + 1) * 1024,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            1700000000000 + i * 60000),
      );
    });
  }

  static const _kExts = ['txt', 'jpg', 'pdf', 'dart', 'mp4', 'png', 'zip'];

  /// Benchmark creation of [count] FileItem objects.
  static BenchmarkResult benchmarkFileListGeneration(int count) {
    return runBenchmark(
      'file_list_generation_$count',
      () => _buildFileList(count),
      itemCount: count,
      metadata: {'count': count},
    );
  }

  /// Benchmark sorting [count] FileItems by [sortField] ('name'|'size'|'date').
  static BenchmarkResult benchmarkFileSorting(int count, String sortField) {
    final items = _buildFileList(count);
    // Shuffle so sort has real work to do.
    items.shuffle(_rng);

    Comparator<FileItem> cmp;
    switch (sortField) {
      case 'size':
        cmp = (a, b) => (a.size ?? 0).compareTo(b.size ?? 0);
        break;
      case 'date':
        cmp = (a, b) =>
            (a.updatedAt ?? DateTime(0)).compareTo(b.updatedAt ?? DateTime(0));
        break;
      default: // 'name'
        cmp = (a, b) => a.name.compareTo(b.name);
    }

    return runBenchmark(
      'file_sort_${sortField}_$count',
      () {
        final copy = List<FileItem>.from(items);
        copy.sort(cmp);
      },
      itemCount: count,
      metadata: {'count': count, 'sortField': sortField},
    );
  }

  /// Benchmark filtering [count] FileItems whose names match [pattern] (glob).
  static BenchmarkResult benchmarkFileFiltering(int count, String pattern) {
    final items = _buildFileList(count);
    final glob = Glob(pattern);

    return runBenchmark(
      'file_filter_${count}_${pattern.replaceAll('*', 'x')}',
      () {
        // ignore: unused_local_variable
        final matched =
            items.where((f) => glob.matches(f.name)).toList(growable: false);
      },
      itemCount: count,
      metadata: {'count': count, 'pattern': pattern},
    );
  }

  // -------------------------------------------------------------------------
  // Encryption benchmark
  // -------------------------------------------------------------------------

  /// Benchmark AES-256-GCM encrypt + decrypt of [dataSizeBytes] of data.
  static BenchmarkResult benchmarkEncryption(int dataSizeBytes) {
    final plaintext = _randomBytes(dataSizeBytes);
    final salt = EncryptionService.generateSalt();
    final key =
        EncryptionService.deriveKey('bench-pass', salt, iterations: 1000);

    return runBenchmark(
      'encryption_${dataSizeBytes}B',
      () {
        final cipher = EncryptionService.encrypt(plaintext, key);
        EncryptionService.decrypt(cipher, key);
      },
      itemCount: 1,
      bytesProcessed: dataSizeBytes,
      metadata: {'dataSizeBytes': dataSizeBytes},
    );
  }

  // -------------------------------------------------------------------------
  // Hashing benchmark
  // -------------------------------------------------------------------------

  /// Benchmark MD5 + SHA-256 hash of [dataSizeBytes] of data.
  static BenchmarkResult benchmarkHashing(int dataSizeBytes) {
    final data = _randomBytes(dataSizeBytes);

    return runBenchmark(
      'hashing_${dataSizeBytes}B',
      () {
        crypto.md5.convert(data);
        crypto.sha256.convert(data);
      },
      itemCount: 2, // 2 hash operations
      bytesProcessed: dataSizeBytes * 2,
      metadata: {'dataSizeBytes': dataSizeBytes},
    );
  }

  // -------------------------------------------------------------------------
  // JSON serialization benchmark
  // -------------------------------------------------------------------------

  /// Benchmark JSON serialize + deserialize of [count] file records.
  static BenchmarkResult benchmarkJsonSerialization(int count) {
    final items = _buildFileList(count);
    // Pre-build the raw map list once so the benchmark only measures JSON.
    final maps = items
        .map((f) => {
              'name': f.name,
              'path': f.path,
              'uuid': f.uuid,
              'isFolder': f.isFolder,
              'size': f.size,
              'updatedAt': f.updatedAt?.toIso8601String(),
            })
        .toList(growable: false);

    return runBenchmark(
      'json_serialization_$count',
      () {
        final encoded = jsonEncode(maps);
        final decoded = jsonDecode(encoded) as List<dynamic>;
        // Touch a field to prevent dead-code elimination.
        if (decoded.isEmpty) throw StateError('empty');
      },
      itemCount: count,
      metadata: {'count': count},
    );
  }

  // -------------------------------------------------------------------------
  // Path operations benchmark
  // -------------------------------------------------------------------------

  /// Benchmark [count] path parsing/joining/normalisation operations.
  static BenchmarkResult benchmarkPathOperations(int count) {
    final segments = List.generate(
        count,
        (i) =>
            '/home/user/documents/project_${i % 50}/subfolder_${i % 10}/file_$i.txt');

    return runBenchmark(
      'path_operations_$count',
      () {
        for (final path in segments) {
          p.basename(path);
          p.dirname(path);
          p.extension(path);
          p.join(p.dirname(path), 'copy_${p.basename(path)}');
          p.normalize('$path/../other');
        }
      },
      itemCount: count,
      metadata: {'count': count},
    );
  }

  // -------------------------------------------------------------------------
  // Transfer-queue scheduling benchmark
  // -------------------------------------------------------------------------

  /// Benchmark enqueue + scheduling overhead for [count] tasks.
  ///
  /// Does NOT actually run the tasks (execute() returns immediately).
  /// Measures pure queue data-structure and priority-sort overhead.
  static BenchmarkResult benchmarkTransferQueueScheduling(int count) {
    return runBenchmark(
      'transfer_queue_scheduling_$count',
      () => _runQueueScheduling(count),
      itemCount: count,
      metadata: {'count': count},
    );
  }

  static void _runQueueScheduling(int count) {
    // Mimic TransferQueue's sorted pending list without importing the full
    // Flutter ChangeNotifier (which requires a widget binding in tests).
    final pending = <_BenchTask>[];
    for (var i = 0; i < count; i++) {
      pending.add(_BenchTask(
        id: 'task-$i',
        priority: _rng.nextInt(10),
      ));
    }
    // Sort by priority descending — the same ordering the real queue does.
    pending.sort((a, b) => b.priority.compareTo(a.priority));
    // Drain the queue.
    while (pending.isNotEmpty) {
      pending.removeAt(0);
    }
  }

  // -------------------------------------------------------------------------
  // Full suite
  // -------------------------------------------------------------------------

  /// Run all benchmarks and return a [BenchmarkSuite].
  static BenchmarkSuite runFullSuite() {
    final sw = Stopwatch()..start();

    final results = <BenchmarkResult>[
      benchmarkFileListGeneration(1000),
      benchmarkFileListGeneration(10000),
      benchmarkFileSorting(1000, 'name'),
      benchmarkFileSorting(1000, 'size'),
      benchmarkFileSorting(1000, 'date'),
      benchmarkFileFiltering(1000, '*.txt'),
      benchmarkEncryption(1024 * 1024), // 1 MB
      benchmarkHashing(1024 * 1024), // 1 MB
      benchmarkJsonSerialization(1000),
      benchmarkPathOperations(10000),
      benchmarkTransferQueueScheduling(100),
    ];

    sw.stop();
    return BenchmarkSuite(
      name: 'CrispCloud Full Benchmark Suite',
      results: results,
      totalDurationMs: sw.elapsedMilliseconds,
      timestamp: DateTime.now(),
    );
  }

  // -------------------------------------------------------------------------
  // Formatting
  // -------------------------------------------------------------------------

  /// Return a human-readable summary of [result].
  static String formatResult(BenchmarkResult result) {
    final buf = StringBuffer();
    buf.write('[${result.name}] ');
    buf.write('${result.durationMs} ms');
    if (result.itemCount > 0) {
      buf.write(' | ${result.itemCount} items');
    }
    if (result.bytesProcessed > 0) {
      buf.write(' | ${_formatBytes(result.bytesProcessed)}');
    }
    buf.write(
        ' | ${result.operationsPerSecond.toStringAsFixed(1)} ops/s');
    return buf.toString();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static Uint8List _randomBytes(int length) {
    final data = Uint8List(length);
    for (var i = 0; i < length; i++) {
      data[i] = _rng.nextInt(256);
    }
    return data;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ---------------------------------------------------------------------------
// Internal helper — lightweight task stub (no Flutter dependency)
// ---------------------------------------------------------------------------
class _BenchTask {
  final String id;
  final int priority;
  _BenchTask({required this.id, required this.priority});
}
