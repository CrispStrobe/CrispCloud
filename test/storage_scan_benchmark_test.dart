@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';

import 'support/storage_scan_benchmark_oracle.dart';

/// Run against an existing, disposable fixture; this test never creates files.
/// Set STORAGE_SCAN_BENCHMARK_ROOT and optionally STORAGE_SCAN_BENCHMARK_RUNS.
/// STORAGE_SCAN_BENCHMARK_ORACLE supplies independent file/directory metadata.
/// Runtime startup is excluded. The first scan warms caches and is not timed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final root = Platform.environment['STORAGE_SCAN_BENCHMARK_ROOT'];
  test(
    'native analyzer scan benchmark',
    () async {
      if (root == null) {
        throw StateError('Set STORAGE_SCAN_BENCHMARK_ROOT to opt in.');
      }
      final legacy =
          Platform.environment['STORAGE_SCAN_BENCHMARK_LEGACY'] == '1';
      final source = legacy
          ? LocalOperationBackend(LocalFileService(), isCurrent: () => true)
          : storageScanBackend(
              source: LocalPanelSource(root),
              local: LocalFileService(),
              isCurrent: () => true,
            );
      final runs =
          int.tryParse(
            Platform.environment['STORAGE_SCAN_BENCHMARK_RUNS'] ?? '',
          ) ??
          5;
      expect(runs, inInclusiveRange(1, 50));
      final timings = <double>[];
      final progressCounts = <int>[];
      final manifestPath =
          Platform.environment['STORAGE_SCAN_BENCHMARK_MANIFEST'];
      final manifest = manifestPath == null
          ? null
          : jsonDecode(await File(manifestPath).readAsString())
                as Map<String, dynamic>;
      final oraclePath = Platform.environment['STORAGE_SCAN_BENCHMARK_ORACLE'];
      final oracle = oraclePath == null
          ? null
          : StorageScanBenchmarkOracle.read(oraclePath);
      if (oracle != null) expect(root, oracle.root);
      StorageScanResult? first;
      String? firstDigest;
      String? firstMetadataDigest;
      String? oracleDigest;
      double? warmupMilliseconds;
      for (var run = 0; run <= runs; run++) {
        StorageScanProgress? finalProgress;
        var progressCalls = 0;
        final watch = Stopwatch()..start();
        final result = await const StorageScanService().scan(
          source,
          root,
          onProgress: (progress) {
            progressCalls++;
            finalProgress = progress;
          },
        );
        watch.stop();
        expect(result.isComplete, isTrue, reason: result.issues.toString());
        expect(progressCalls, greaterThanOrEqualTo(2));
        expect(finalProgress?.files, result.root.fileCount);
        expect(finalProgress?.folders, result.root.folderCount);
        expect(finalProgress?.bytes, result.root.bytes);
        oracleDigest = oracle?.verify(result);
        final metadataDigest = storageScanMetadataFingerprint(result);
        if (firstMetadataDigest != null) {
          expect(metadataDigest, firstMetadataDigest);
        }
        firstMetadataDigest ??= metadataDigest;
        // Validate every relative path and size outside the timed interval.
        final pending = [result.root];
        final records = <List<Object>>[];
        while (pending.isNotEmpty) {
          final node = pending.removeLast();
          pending.addAll(node.children);
          if (!node.isFolder && node.item.isSymlink != true) {
            records.add([
              p.relative(node.path, from: root).split(p.separator).join('/'),
              node.bytes,
            ]);
          }
        }
        records.sort((a, b) => (a[0] as String).compareTo(b[0] as String));
        final digest = sha256
            .convert(utf8.encode(jsonEncode(records)))
            .toString();
        if (firstDigest != null) expect(digest, firstDigest);
        firstDigest ??= digest;
        if (manifest != null) {
          expect(result.root.fileCount, manifest['files']);
          expect(result.root.folderCount, manifest['folders']);
          expect(result.root.bytes, manifest['logicalBytes']);
          expect(digest, manifest['filesDigest']);
        }
        if (first != null) {
          expect(result.root.fileCount, first.root.fileCount);
          expect(result.root.folderCount, first.root.folderCount);
          expect(result.root.bytes, first.root.bytes);
        }
        first ??= result;
        if (run == 0) {
          warmupMilliseconds = watch.elapsedMicroseconds / 1000;
        } else {
          timings.add(watch.elapsedMicroseconds / 1000);
          progressCounts.add(progressCalls);
        }
        // ignore: avoid_print
        print('Scan $run: ${watch.elapsedMilliseconds} ms');
      }
      final sorted = timings.toList()..sort();
      // A machine-readable record for repeatable before/after comparisons.
      // ignore: avoid_print
      print(
        jsonEncode({
          'benchmark': 'storage_scan',
          'backend': legacy ? 'legacy_operation' : 'native_scan',
          'retention': 'tree',
          'root': root,
          'files': first!.root.fileCount,
          'folders': first.root.folderCount,
          'logicalBytes': first.root.bytes,
          'filesDigest': firstDigest,
          'allMetadataDigest': firstMetadataDigest,
          'independentOracle': oracle != null,
          'filesSizeMtimeDigest': oracleDigest,
          'progressCallbacks': progressCounts,
          'warmupMilliseconds': warmupMilliseconds,
          'milliseconds': timings,
          'medianMilliseconds': sorted[sorted.length ~/ 2],
          'minimumMilliseconds': sorted.first,
          'maximumMilliseconds': sorted.last,
          'runtime': Platform.version,
          'operatingSystem': Platform.operatingSystem,
          'sourceRevision':
              Platform.environment['STORAGE_SCAN_BENCHMARK_REVISION'],
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: root == null ? 'Set STORAGE_SCAN_BENCHMARK_ROOT to opt in.' : false,
  );
}
