@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/file_collection_storage_native.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';
import 'package:crisp_cloud/services/storage_scan_snapshot_store.dart';

String _fingerprint(StorageScanResult result) {
  final pending = [result.root];
  final nodes = <List<Object?>>[];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    pending.addAll(node.children.reversed);
    nodes.add([
      node.path,
      node.name,
      node.isFolder,
      node.item.size,
      node.item.uuid,
      node.item.updatedAt?.toUtc().toIso8601String(),
      node.item.isSymlink,
      node.item.symlinkTarget,
      node.bytes,
      node.fileCount,
      node.folderCount,
      node.unknownSizeCount,
      node.skippedLinkCount,
      node.isComplete,
    ]);
  }
  return sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'nodes': nodes,
            'cancelled': result.cancelled,
            'limited': result.limited,
            'sourceChanged': result.sourceChanged,
            'startedAt': result.startedAt.toUtc().toIso8601String(),
            'completedAt': result.completedAt.toUtc().toIso8601String(),
            'suppressedIssues': result.suppressedIssueCount,
            'issues': [
              for (final issue in result.issues)
                [issue.path, issue.code.name, issue.message],
            ],
          }),
        ),
      )
      .toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final root = Platform.environment['STORAGE_SCAN_BENCHMARK_ROOT'];
  test(
    'native saved analyzer snapshot benchmark',
    () async {
      if (root == null)
        throw StateError('Set STORAGE_SCAN_BENCHMARK_ROOT to opt in.');
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
      // Build the source tree once, outside every measured save/load interval.
      final result = await const StorageScanService().scan(source, root);
      expect(result.isComplete, isTrue);
      final manifestPath =
          Platform.environment['STORAGE_SCAN_BENCHMARK_MANIFEST'];
      if (manifestPath != null) {
        final manifest = jsonDecode(
          await File(manifestPath).readAsString(),
        ) as Map<String, dynamic>;
        expect(result.root.fileCount, manifest['files']);
        expect(result.root.folderCount, manifest['folders']);
        expect(result.root.bytes, manifest['logicalBytes']);
      }
      final fingerprint = _fingerprint(result);
      final directory = await Directory.systemTemp.createTemp(
        'crisp-snapshot-benchmark-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = NativeFileCollectionStorage(
        directory: () async => directory,
      );
      final store = StorageScanSnapshotStore(storage: storage);
      final records = <Map<String, Object?>>[];
      for (var run = 0; run <= runs; run++) {
        final saveWatch = Stopwatch()..start();
        final summary = await store.save(
          result: result,
          storageId: 'synthetic-local-fixture',
          sourceLabel: 'Benchmark fixture',
          pathStyle: source.paths.style,
        );
        saveWatch.stop();
        final reader = StorageScanSnapshotStore(
          storage: NativeFileCollectionStorage(
            directory: () async => directory,
          ),
        );
        final loadWatch = Stopwatch()..start();
        final loaded = await reader.load(summary.id);
        loadWatch.stop();
        expect(_fingerprint(loaded.result), fingerprint);
        expect(
          loaded.summary.nodeCount,
          1 +
              result.root.fileCount +
              result.root.folderCount +
              result.root.skippedLinkCount,
        );
        records.add({
          'run': run,
          'warmup': run == 0,
          'save_ms': saveWatch.elapsedMicroseconds / 1000,
          'load_ms': loadWatch.elapsedMicroseconds / 1000,
          'nodes': summary.nodeCount,
          'files': loaded.result.root.fileCount,
          'folders': loaded.result.root.folderCount,
          'logical_bytes': loaded.result.root.bytes,
          'all_metadata_fingerprint': fingerprint,
          'exact_roundtrip': true,
        });
        // ignore: avoid_print
        print('SNAPSHOT_BENCH ${jsonEncode(records.last)}');
      }
      // ignore: avoid_print
      print(
        jsonEncode({
          'benchmark': 'native_storage_snapshot',
          'storage':
              'NativeFileCollectionStorage (atomic files, flush, CAS lease)',
          'runtime': Platform.version,
          'source_scan_excluded': true,
          'runs': records,
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: root == null ? 'Set STORAGE_SCAN_BENCHMARK_ROOT to opt in.' : false,
  );
}
