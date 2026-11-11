@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';

import 'support/storage_scan_benchmark_oracle.dart';

/// Final-revision counterpart to the baseline-compatible full-tree benchmark.
/// The independent oracle is mandatory because no descendant tree is retained.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final root = Platform.environment['STORAGE_SCAN_BENCHMARK_ROOT'];
  final oraclePath = Platform.environment['STORAGE_SCAN_BENCHMARK_ORACLE'];
  test(
    'native folder size summary benchmark',
    () async {
      if (root == null || oraclePath == null) {
        throw StateError(
          'Set STORAGE_SCAN_BENCHMARK_ROOT and STORAGE_SCAN_BENCHMARK_ORACLE.',
        );
      }
      final oracle = StorageScanBenchmarkOracle.read(oraclePath);
      expect(root, oracle.root);
      final runs =
          int.tryParse(
            Platform.environment['STORAGE_SCAN_BENCHMARK_RUNS'] ?? '',
          ) ??
          5;
      expect(runs, inInclusiveRange(1, 50));
      final source = storageScanBackend(
        source: LocalPanelSource(root),
        local: LocalFileService(),
        isCurrent: () => true,
      );
      // Prove full metadata and summary totals use the same source fixture.
      // This reference scan and all validation stay outside timed intervals.
      late String fixtureDigest;
      late String referenceMetadataDigest;
      late (int, int, int) referenceTotals;
      {
        final reference = await const StorageScanService().scan(source, root);
        fixtureDigest = oracle.verify(reference);
        referenceMetadataDigest = storageScanMetadataFingerprint(reference);
        referenceTotals = (
          reference.root.bytes,
          reference.root.fileCount,
          reference.root.folderCount,
        );
      }
      final timings = <double>[];
      final progressCounts = <int>[];
      double? warmupMilliseconds;
      for (var run = 0; run <= runs; run++) {
        StorageScanProgress? finalProgress;
        var progressCalls = 0;
        final watch = Stopwatch()..start();
        final result = await const StorageScanService().scanSummary(
          source,
          root,
          onProgress: (progress) {
            progressCalls++;
            finalProgress = progress;
          },
        );
        watch.stop();
        oracle.verifyTotals(
          bytes: result.bytes,
          files: result.fileCount,
          folders: result.folderCount,
          unknownSizes: result.unknownSizeCount,
          skippedLinks: result.skippedLinkCount,
          isComplete: result.isComplete,
          cancelled: result.cancelled,
          limited: result.limited,
          sourceChanged: result.sourceChanged,
          issueCount: result.issues.length + result.suppressedIssueCount,
        );
        expect(result.bytes, referenceTotals.$1);
        expect(result.fileCount, referenceTotals.$2);
        expect(result.folderCount, referenceTotals.$3);
        expect(progressCalls, greaterThanOrEqualTo(2));
        expect(finalProgress?.files, result.fileCount);
        expect(finalProgress?.folders, result.folderCount);
        expect(finalProgress?.bytes, result.bytes);
        if (run == 0) {
          warmupMilliseconds = watch.elapsedMicroseconds / 1000;
        } else {
          timings.add(watch.elapsedMicroseconds / 1000);
          progressCounts.add(progressCalls);
        }
        // ignore: avoid_print
        print('Summary $run: ${watch.elapsedMilliseconds} ms');
      }
      final sorted = timings.toList()..sort();
      // ignore: avoid_print
      print(
        jsonEncode({
          'benchmark': 'storage_scan',
          'backend': 'native_scan',
          'retention': 'summary',
          'root': root,
          'files': oracle.fileCount,
          'folders': oracle.folderCount,
          'logicalBytes': oracle.bytes,
          'independentOracle': true,
          'fixtureFilesSizeMtimeDigest': fixtureDigest,
          'referenceFullMetadataDigest': referenceMetadataDigest,
          'validatedTotals': true,
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
    skip: root == null || oraclePath == null
        ? 'Set STORAGE_SCAN_BENCHMARK_ROOT and STORAGE_SCAN_BENCHMARK_ORACLE.'
        : false,
  );
}
