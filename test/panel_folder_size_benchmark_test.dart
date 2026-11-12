@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/folder_size_measurement.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';
import 'support/workspace_fixture.dart';

const _paneEntries = 8000;
const _scannedFiles = 8000;
const _targetName = 'zz_measure';
const _targetPath = '/$_targetName';
const _expectedBytes = 119705600;

/// Cached provider metadata keeps this benchmark focused on the real panel's
/// source/row checks and inline scan, without network or fixture-generation cost.
class _MetadataCloud extends WorkflowFakeClient
    implements FreshCloudDirectoryReader {
  _MetadataCloud()
    : _rootListing = {
        'folders': [
          for (var i = 0; i < _paneEntries - 1; i++)
            {'name': 'folder_${i.toString().padLeft(5, '0')}'},
          {'name': _targetName},
        ],
        'files': <Map<String, dynamic>>[],
      },
      _targetListing = {
        'folders': <Map<String, dynamic>>[],
        'files': [
          for (var i = 0; i < _scannedFiles; i++)
            {
              'name': 'file_${i.toString().padLeft(5, '0')}.bin',
              'size': const [0, 64, 1024, 8192, 65536][i % 5],
            },
        ],
      };

  final Map<String, dynamic> _rootListing;
  final Map<String, dynamic> _targetListing;
  final freshReads = <String, int>{};
  int browsingReads = 0;
  int authenticationChecks = 0;
  int metadataRowsReturned = 0;
  int downloadCount = 0;

  @override
  bool get isAuthenticated {
    authenticationChecks++;
    return current;
  }

  Map<String, dynamic> _listing(String path) => switch (path) {
    '/' => _rootListing,
    _targetPath => _targetListing,
    _ => throw StateError('Unexpected metadata read: $path'),
  };

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    browsingReads++;
    return _listing(path);
  }

  @override
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) async {
    freshReads.update(path, (count) => count + 1, ifAbsent: () => 1);
    final listing = _listing(path);
    metadataRowsReturned +=
        (listing['folders'] as List).length + (listing['files'] as List).length;
    return listing;
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String path, {
    Function(int, int)? onProgress,
  }) async {
    downloadCount++;
    throw StateError('The metadata benchmark must not read file contents.');
  }

  void resetCounts() {
    freshReads.clear();
    browsingReads = 0;
    authenticationChecks = 0;
    metadataRowsReturned = 0;
    downloadCount = 0;
  }
}

class _UnusedLocal extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
  @override
  String get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => '/';
  @override
  Future<String> getSafeFallbackDirectory() async => '/';
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

/// Opt in with PANEL_FOLDER_SIZE_BENCHMARK=1 and --tags benchmark --run-skipped.
/// This harness also runs unchanged at the pre-optimization d0a1e93 revision.
/// Only calculateFolderSize is timed: setup, refresh, selection, assertions and
/// output are excluded. The first scan warms the runtime; five follow are timed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final enabled = Platform.environment['PANEL_FOLDER_SIZE_BENCHMARK'] == '1';
  test(
    'inline folder measurement with its exact row last in a large pane',
    () async {
      if (!enabled) {
        throw StateError('Set PANEL_FOLDER_SIZE_BENCHMARK=1 to opt in.');
      }
      SharedPreferences.setMockInitialValues({});
      final cloud = _MetadataCloud();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => WorkspaceTestAuth(cloud)),
          localFileServiceProvider.overrideWithValue(_UnusedLocal()),
        ],
      );
      try {
        final panel = container.read(panelProvider(PanelSide.remote));
        await Future<void>.delayed(Duration.zero);
        container
            .read(panelSourceProvider(PanelSide.remote).notifier)
            .setSource(
              RemotePanelSource(
                client: cloud,
                providerName: cloud.providerName,
                path: '/',
              ),
            );
        final records = <Map<String, Object?>>[];
        final timings = <double>[];
        for (var run = 0; run <= 5; run++) {
          // Refresh creates a new verified row so completed-size reuse cannot
          // turn a later run into a cache hit.
          await panel.refresh();
          final target = panel.files!.last;
          expect(panel.files, hasLength(_paneEntries));
          expect(target.path, _targetPath);
          expect(target.calculatedSize, isNull);
          panel.selectVisibleItems([target], cursor: target);
          cloud.resetCounts();
          var notifications = 0;
          void changed() => notifications++;
          panel.addListener(changed);
          final watch = Stopwatch()..start();
          FolderSizeMeasurement? result;
          try {
            result = await panel.calculateFolderSize(target);
          } finally {
            watch.stop();
            panel.removeListener(changed);
          }
          final counts = {
            'freshDirectoryReads': Map<String, int>.of(cloud.freshReads),
            'browsingReads': cloud.browsingReads,
            'authenticationChecks': cloud.authenticationChecks,
            'metadataRowsReturned': cloud.metadataRowsReturned,
            'downloads': cloud.downloadCount,
          };
          // Independent fixed fixture totals and publication checks run after
          // the clock stops. The aggregate-only API is deliberately not used.
          expect(result?.phase, FolderSizePhase.complete);
          expect(result?.bytes, _expectedBytes);
          expect(result?.files, _scannedFiles);
          expect(result?.folders, 0);
          expect(result?.unknownSizes, 0);
          expect(result?.skippedLinks, 0);
          expect(result?.issueCount, 0);
          expect(result?.limited, isFalse);
          expect(result?.sourceChanged, isFalse);
          expect(panel.files!.last.path, _targetPath);
          expect(panel.files!.last.calculatedSize, _expectedBytes);
          expect(identical(panel.selection.single, panel.files!.last), isTrue);
          expect(
            panel.originForFile(panel.selection.single)?.isCurrent,
            isTrue,
          );
          expect(cloud.freshReads, {'/': 1, _targetPath: 1});
          expect(cloud.metadataRowsReturned, _paneEntries + _scannedFiles);
          expect(cloud.browsingReads, 0);
          expect(cloud.downloadCount, 0);
          expect(cloud.writes, isEmpty);
          final milliseconds = watch.elapsedMicroseconds / 1000;
          if (run != 0) timings.add(milliseconds);
          records.add({
            'run': run,
            'warmup': run == 0,
            'milliseconds': milliseconds,
            'notifications': notifications,
            ...counts,
            'validated': true,
          });
        }
        final sorted = [...timings]..sort();
        // ignore: avoid_print
        print(
          jsonEncode({
            'benchmark': 'panel_folder_size',
            'fixture': 'synthetic_cached_provider_metadata',
            'paneEntries': _paneEntries,
            'targetIndex': _paneEntries - 1,
            'scannedFiles': _scannedFiles,
            'logicalBytes': _expectedBytes,
            'protocol': 'One warmup and five measured inline scans; refresh, selection and assertions outside timing; exact source and panel guards retained; no network or content reads.',
            'runs': records,
            'medianMilliseconds': sorted[sorted.length ~/ 2],
            'minimumMilliseconds': sorted.first,
            'maximumMilliseconds': sorted.last,
            'runtime': Platform.version,
            'operatingSystem': Platform.operatingSystem,
          }),
        );
      } finally {
        container.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: enabled ? false : 'Set PANEL_FOLDER_SIZE_BENCHMARK=1 to opt in.',
  );
}
