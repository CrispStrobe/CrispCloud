@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/file_collection_storage_native.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';

const _rowCount = 10000;
const _sources = [
  StorageReference(
    kind: 'remote',
    provider: 'Synthetic benchmark',
    accountKey: 'account-a',
  ),
  StorageReference(
    kind: 'remote',
    provider: 'Synthetic benchmark',
    accountKey: 'account-b',
  ),
];

FileCollection _fixture() {
  final modified = DateTime.utc(2026, 1, 1).microsecondsSinceEpoch;
  final entries = [
    for (var index = 0; index < _rowCount; index++)
      () {
        // Each path appears in both accounts; its source remains part of its
        // identity. Non-millisecond timestamps must survive serialization.
        final number = (index ~/ 2).toString().padLeft(5, '0');
        final name = '資料-📁-$number.txt';
        final path = '/fixture/$name';
        final source = _sources[index % _sources.length];
        final objectId = 'object-$number';
        return FileCollectionEntry(
          reference: FileReference(
            storage: source,
            path: path,
            objectId: objectId,
            version: 'revision-$number',
          ),
          file: FileItem(
            name: name,
            path: path,
            uuid: objectId,
            storageId: source.id,
            isFolder: false,
            size: index % 97 == 0
                ? null
                : index % 19 == 0
                ? 0
                : index * 17,
            updatedAt: DateTime.fromMicrosecondsSinceEpoch(
              modified + index * 1001,
              isUtc: true,
            ),
            isSymlink: false,
          ),
        );
      }(),
  ];
  return FileCollection(
    id: 'native-import-fixture',
    name: 'Synthetic collection import',
    entries: entries,
    selectedKeys: {
      for (final index in [0, 1, 499, 500, 5001, 9999]) entries[index].key,
    },
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

String _digest(List<Map<String, dynamic>> rows, Set<String> selectedKeys) =>
    sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'rows': rows,
              'selectedKeys': selectedKeys.toList()..sort(),
            }),
          ),
        )
        .toString();

FileCollectionStore _store(Directory directory) => FileCollectionStore(
  storage: NativeFileCollectionStorage(directory: () async => directory),
);

/// Uses only APIs present before batched storage writes, so the exact harness
/// can run against both baseline and final production sources.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final enabled = Platform.environment['COLLECTION_IMPORT_BENCHMARK'] == '1';
  test(
    'native collection import benchmark',
    () async {
      if (!enabled) {
        throw StateError('Set COLLECTION_IMPORT_BENCHMARK=1 to opt in.');
      }
      final runs =
          int.tryParse(
            Platform.environment['COLLECTION_IMPORT_BENCHMARK_RUNS'] ?? '',
          ) ??
          5;
      expect(runs, inInclusiveRange(1, 50));

      // Construct and encode independent expected metadata before timing.
      final fixture = _fixture();
      final expectedRows = [
        for (final entry in fixture.entries) entry.toJson(),
      ];
      final expectedKeys = fixture.entries.map((entry) => entry.key).toSet();
      final expectedDigest = _digest(expectedRows, fixture.selectedKeys);
      expect(fixture.entries, hasLength(_rowCount));
      expect(expectedKeys, hasLength(_rowCount));
      expect(
        fixture.entries.map((entry) => entry.reference.path).toSet(),
        hasLength(_rowCount ~/ 2),
      );
      final directory = await Directory.systemTemp.createTemp(
        'collection-import-benchmark-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final timings = <double>[];
      final pageBytes = <int>[];
      double? warmupMilliseconds;
      for (var run = 0; run <= runs; run++) {
        final runDirectory = await Directory(
          '${directory.path}${Platform.pathSeparator}run-$run',
        ).create();
        try {
          final writer = _store(runDirectory);
          late double milliseconds;
          try {
            await writer.ready;
            final watch = Stopwatch()..start();
            await writer.save(fixture);
            watch.stop();
            milliseconds = watch.elapsedMicroseconds / 1000;
          } finally {
            writer.dispose();
          }

          // Reopen actual native files with an empty cache. All verification
          // and cleanup are excluded from the import stopwatch.
          final reader = _store(runDirectory);
          try {
            await reader.ready;
            expect(reader.loadErrors, isEmpty);
            expect(reader.collections, hasLength(1));
            final manifest = await reader.manifest(fixture.id);
            expect(manifest.summary.itemCount, _rowCount);
            expect(manifest.summary.sourceCount, _sources.length);
            expect(manifest.summary.selectedCount, fixture.selectedKeys.length);
            expect(manifest.summary.unavailableCount, 0);
            expect(manifest.pages, hasLength(20));
            for (final page in manifest.pages) {
              expect(
                page.count,
                inInclusiveRange(1, FileCollectionStore.pageEntryLimit),
              );
              expect(
                page.bytes,
                inInclusiveRange(1, FileCollectionStore.pageByteLimit),
              );
            }
            final loaded = await reader.load(fixture.id);
            expect(loaded.id, fixture.id);
            expect(loaded.name, fixture.name);
            expect(loaded.selectedKeys, fixture.selectedKeys);
            expect(
              loaded.entries.map((entry) => entry.key).toSet(),
              expectedKeys,
            );
            final loadedRows = [
              for (final entry in loaded.entries) entry.toJson(),
            ];
            expect(loadedRows, expectedRows);
            expect(_digest(loadedRows, loaded.selectedKeys), expectedDigest);
            expect(reader.loadErrors, isEmpty);
            expect(
              reader.residentEntryCount,
              lessThanOrEqualTo(reader.cacheEntryLimit),
            );
            expect(
              reader.residentPageBytes,
              lessThanOrEqualTo(reader.cacheByteLimit),
            );
            if (run == 0) {
              warmupMilliseconds = milliseconds;
            } else {
              timings.add(milliseconds);
              pageBytes.add(
                manifest.pages.fold(0, (sum, page) => sum + page.bytes),
              );
            }
          } finally {
            reader.dispose();
          }
          // ignore: avoid_print
          print('Collection import $run: $milliseconds ms');
        } finally {
          await runDirectory.delete(recursive: true);
        }
      }
      final sorted = timings.toList()..sort();
      final median = sorted[sorted.length ~/ 2];
      // ignore: avoid_print
      print(
        jsonEncode({
          'benchmark': 'native_collection_import',
          'rows': _rowCount,
          'sources': _sources.length,
          'pages': 20,
          'selectedRows': fixture.selectedKeys.length,
          'metadataDigest': expectedDigest,
          'exactDurableRoundtrip': true,
          'pageBytes': pageBytes,
          'warmupMilliseconds': warmupMilliseconds,
          'milliseconds': timings,
          'medianMilliseconds': median,
          'minimumMilliseconds': sorted.first,
          'maximumMilliseconds': sorted.last,
          'rowsPerSecond': _rowCount * 1000 / median,
          'runtime': Platform.version,
          'operatingSystem': Platform.operatingSystem,
          'sourceRevision':
              Platform.environment['STORAGE_SCAN_BENCHMARK_REVISION'],
          'protocol':
              'One warmup plus $runs measured saves into fresh native stores. '
              'Fixture construction, store initialization, full durable reopen '
              'and metadata/paging verification, and cleanup are outside timing. '
              'Encoding, page persistence and catalog publication are timed.',
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: enabled ? false : 'Set COLLECTION_IMPORT_BENCHMARK=1 to opt in.',
  );
}
