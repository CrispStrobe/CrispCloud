// test/migration_service_test.dart
//
// Unit tests for MigrationService, MigrationPlan, MigrationProgress,
// MigrationFileEntry, MigrationError, and MigrationVerification.
//
// All tests run fully in memory.  Cloud I/O is replaced by stub
// CloudStorageClient implementations defined below.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/migration_service.dart';

// ---------------------------------------------------------------------------
// Stub storage backend
// ---------------------------------------------------------------------------

/// In-memory backing store for [_StubClient].
class _StubStorage {
  /// Map of remote path → file bytes.
  final Map<String, List<int>> files = {};

  /// Map of remote path → directory listing.
  final Map<String, Map<String, dynamic>> listings = {};

  /// Map of remote path → metadata (null entry = not found).
  final Map<String, Map<String, dynamic>?> resolvable = {};

  /// Paths created via createFolderPath.
  final Set<String> createdFolders = {};

  /// Upload log: records (bytes, fileName, targetPath).
  final List<(List<int>, String, String)> uploads = [];
}

/// Minimal [CloudStorageClient] backed by [_StubStorage].
class _StubClient extends CloudStorageClient {
  final _StubStorage _stub;

  _StubClient(this._stub);

  @override
  String get providerName => 'stub';

  @override
  String get rootPath => '/';

  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) async {}

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async {}

  @override
  bool get isAuthenticated => true;

  @override
  String? get userId => 'stub-user';

  @override
  String? get bucketId => null;

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async {
    if (_stub.resolvable.containsKey(path)) return _stub.resolvable[path];
    return null;
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    return _stub.listings[path] ?? {'files': [], 'folders': []};
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final full = targetPath.isEmpty ? fileName : '$targetPath/$fileName';
    _stub.files[full] = fileData;
    _stub.uploads.add((fileData, fileName, targetPath));
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    if (!_stub.files.containsKey(remotePath)) {
      throw Exception('File not found: $remotePath');
    }
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    if (!_stub.files.containsKey(remotePath)) {
      throw Exception('File not found: $remotePath');
    }
    return Uint8List.fromList(_stub.files[remotePath]!);
  }

  @override
  Future<void> createFolderPath(String path) async {
    _stub.createdFolders.add(path);
  }

  @override
  Future<void> deletePath(String path) async {}

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {}

  @override
  Future<void> renamePath(String path, String newName) async {}
}

// ---------------------------------------------------------------------------
// Factory helpers
// ---------------------------------------------------------------------------

MigrationPlan _makePlan({
  String id = 'plan-001',
  String name = 'My Migration',
  String sourceProvider = 'dropbox',
  String destinationProvider = 'filen',
  String sourcePath = '/source',
  String destinationPath = '/dest',
  List<String> includePatterns = const [],
  List<String> excludePatterns = const [],
  ConflictPolicy conflictPolicy = ConflictPolicy.skip,
  bool preserveStructure = true,
  bool verifyAfter = false,
  double? throttleMBps,
  MigrationStatus status = MigrationStatus.pending,
}) =>
    MigrationPlan(
      id: id,
      name: name,
      sourceProvider: sourceProvider,
      destinationProvider: destinationProvider,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      includePatterns: includePatterns,
      excludePatterns: excludePatterns,
      conflictPolicy: conflictPolicy,
      preserveStructure: preserveStructure,
      verifyAfter: verifyAfter,
      throttleMBps: throttleMBps,
      status: status,
      createdAt: DateTime(2026, 1, 15),
    );

MigrationFileEntry _makeEntry({
  String relativePath = 'doc.txt',
  int sizeBytes = 1024,
  DateTime? sourceModified,
  MigrationFileStatus status = MigrationFileStatus.pending,
  String? sourceHash,
  String? destHash,
}) =>
    MigrationFileEntry(
      relativePath: relativePath,
      sizeBytes: sizeBytes,
      sourceModified: sourceModified,
      status: status,
      sourceHash: sourceHash,
      destHash: destHash,
    );

MigrationError _makeError({
  String filePath = 'a.txt',
  String error = 'something went wrong',
  bool retryable = false,
}) =>
    MigrationError(
      filePath: filePath,
      error: error,
      timestamp: DateTime(2026, 3, 1, 12, 0),
      retryable: retryable,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // =========================================================================
  // MigrationPlan — serialisation
  // =========================================================================

  group('MigrationPlan serialisation', () {
    test('toJson includes all fields', () {
      final plan = _makePlan(
        id: 'p1',
        name: 'Test',
        sourceProvider: 'gdrive',
        destinationProvider: 'onedrive',
        sourcePath: '/src',
        destinationPath: '/dst',
        includePatterns: ['*.jpg'],
        excludePatterns: ['node_modules/**'],
        conflictPolicy: ConflictPolicy.overwrite,
        preserveStructure: false,
        verifyAfter: true,
        throttleMBps: 2.5,
        status: MigrationStatus.running,
      );

      final json = plan.toJson();

      expect(json['id'], 'p1');
      expect(json['name'], 'Test');
      expect(json['sourceProvider'], 'gdrive');
      expect(json['destinationProvider'], 'onedrive');
      expect(json['sourcePath'], '/src');
      expect(json['destinationPath'], '/dst');
      expect(json['includePatterns'], ['*.jpg']);
      expect(json['excludePatterns'], ['node_modules/**']);
      expect(json['conflictPolicy'], 'overwrite');
      expect(json['preserveStructure'], false);
      expect(json['verifyAfter'], true);
      expect(json['throttleMBps'], 2.5);
      expect(json['status'], 'running');
      expect(json['createdAt'], isA<String>());
    });

    test('fromJson round-trips all fields', () {
      final original = _makePlan(
        conflictPolicy: ConflictPolicy.rename,
        includePatterns: ['*.png', '*.pdf'],
        excludePatterns: ['.git/**'],
        throttleMBps: 1.0,
        status: MigrationStatus.completed,
      );
      final restored = MigrationPlan.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.sourceProvider, original.sourceProvider);
      expect(restored.destinationProvider, original.destinationProvider);
      expect(restored.sourcePath, original.sourcePath);
      expect(restored.destinationPath, original.destinationPath);
      expect(restored.includePatterns, original.includePatterns);
      expect(restored.excludePatterns, original.excludePatterns);
      expect(restored.conflictPolicy, ConflictPolicy.rename);
      expect(restored.preserveStructure, original.preserveStructure);
      expect(restored.verifyAfter, original.verifyAfter);
      expect(restored.throttleMBps, 1.0);
      expect(restored.status, MigrationStatus.completed);
      expect(restored.createdAt, original.createdAt);
    });

    test('fromJson handles all ConflictPolicy values', () {
      for (final policy in ConflictPolicy.values) {
        final plan = _makePlan(conflictPolicy: policy);
        final restored = MigrationPlan.fromJson(plan.toJson());
        expect(restored.conflictPolicy, policy);
      }
    });

    test('fromJson handles all MigrationStatus values', () {
      for (final status in MigrationStatus.values) {
        final plan = _makePlan(status: status);
        final restored = MigrationPlan.fromJson(plan.toJson());
        expect(restored.status, status);
      }
    });

    test('fromJson uses skip as default for unknown conflictPolicy', () {
      final json = _makePlan().toJson();
      json['conflictPolicy'] = 'unknown_policy';
      final plan = MigrationPlan.fromJson(json);
      expect(plan.conflictPolicy, ConflictPolicy.skip);
    });

    test('fromJson uses pending as default for unknown status', () {
      final json = _makePlan().toJson();
      json['status'] = 'unknown_status';
      final plan = MigrationPlan.fromJson(json);
      expect(plan.status, MigrationStatus.pending);
    });

    test('throttleMBps is omitted from json when null', () {
      final plan = _makePlan(throttleMBps: null);
      expect(plan.toJson().containsKey('throttleMBps'), isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      final original = _makePlan(name: 'Old', conflictPolicy: ConflictPolicy.skip);
      final copy = original.copyWith(
          name: 'New', conflictPolicy: ConflictPolicy.overwrite);
      expect(copy.id, original.id);
      expect(copy.name, 'New');
      expect(copy.conflictPolicy, ConflictPolicy.overwrite);
      expect(copy.sourcePath, original.sourcePath);
    });
  });

  // =========================================================================
  // MigrationPlan — validation
  // =========================================================================

  group('MigrationPlan validation', () {
    test('valid plan returns null', () {
      expect(_makePlan().validate(), isNull);
    });

    test('empty name fails', () {
      expect(_makePlan(name: '').validate(), isNotNull);
    });

    test('empty sourceProvider fails', () {
      expect(_makePlan(sourceProvider: '').validate(), isNotNull);
    });

    test('empty destinationProvider fails', () {
      expect(_makePlan(destinationProvider: '').validate(), isNotNull);
    });

    test('empty sourcePath fails', () {
      expect(_makePlan(sourcePath: '').validate(), isNotNull);
    });

    test('empty destinationPath fails', () {
      expect(_makePlan(destinationPath: '').validate(), isNotNull);
    });

    test('negative throttleMBps fails', () {
      expect(_makePlan(throttleMBps: -1.0).validate(), isNotNull);
    });

    test('zero throttleMBps fails', () {
      expect(_makePlan(throttleMBps: 0.0).validate(), isNotNull);
    });

    test('positive throttleMBps passes', () {
      expect(_makePlan(throttleMBps: 5.0).validate(), isNull);
    });
  });

  // =========================================================================
  // MigrationProgress — serialisation and calculations
  // =========================================================================

  group('MigrationProgress serialisation', () {
    test('toJson / fromJson round-trips', () {
      final progress = MigrationProgress(
        planId: 'p1',
        totalFiles: 10,
        totalBytes: 1024 * 1024,
        migratedFiles: 4,
        skippedFiles: 1,
        failedFiles: 0,
        migratedBytes: 512 * 1024,
        currentFile: 'images/photo.jpg',
        startedAt: DateTime(2026, 5, 1, 8, 0),
        estimatedCompletion: DateTime(2026, 5, 1, 8, 5),
        errors: [_makeError(retryable: true)],
      );

      final json = progress.toJson();
      final restored = MigrationProgress.fromJson(json);

      expect(restored.planId, 'p1');
      expect(restored.totalFiles, 10);
      expect(restored.totalBytes, 1024 * 1024);
      expect(restored.migratedFiles, 4);
      expect(restored.skippedFiles, 1);
      expect(restored.failedFiles, 0);
      expect(restored.migratedBytes, 512 * 1024);
      expect(restored.currentFile, 'images/photo.jpg');
      expect(restored.errors.length, 1);
      expect(restored.errors.first.retryable, isTrue);
    });

    test('bytesProgress is correct', () {
      final p = MigrationProgress(
        planId: 'p1',
        totalFiles: 5,
        totalBytes: 200,
        migratedBytes: 100,
        startedAt: DateTime.now(),
      );
      expect(p.bytesProgress, closeTo(0.5, 0.001));
    });

    test('bytesProgress is 1.0 when totalBytes is zero', () {
      final p = MigrationProgress(
        planId: 'p1',
        totalFiles: 0,
        totalBytes: 0,
        startedAt: DateTime.now(),
      );
      expect(p.bytesProgress, 1.0);
    });

    test('filesProgress counts migrated + skipped + failed', () {
      final p = MigrationProgress(
        planId: 'p1',
        totalFiles: 10,
        totalBytes: 1000,
        migratedFiles: 3,
        skippedFiles: 2,
        failedFiles: 1,
        startedAt: DateTime.now(),
      );
      expect(p.filesProgress, closeTo(0.6, 0.001));
    });

    test('processedFiles sums migrated + skipped + failed', () {
      final p = MigrationProgress(
        planId: 'p1',
        totalFiles: 10,
        totalBytes: 1000,
        migratedFiles: 2,
        skippedFiles: 3,
        failedFiles: 1,
        startedAt: DateTime.now(),
      );
      expect(p.processedFiles, 6);
    });
  });

  // =========================================================================
  // MigrationFileEntry — serialisation & status transitions
  // =========================================================================

  group('MigrationFileEntry serialisation', () {
    test('toJson includes all fields', () {
      final entry = _makeEntry(
        relativePath: 'photos/pic.jpg',
        sizeBytes: 2048,
        sourceModified: DateTime(2026, 4, 1),
        status: MigrationFileStatus.migrated,
        sourceHash: 'sha256abc',
        destHash: 'sha256abc',
      );
      final json = entry.toJson();

      expect(json['relativePath'], 'photos/pic.jpg');
      expect(json['sizeBytes'], 2048);
      expect(json['status'], 'migrated');
      expect(json['sourceHash'], 'sha256abc');
      expect(json['destHash'], 'sha256abc');
      expect(json['sourceModified'], isA<String>());
    });

    test('fromJson round-trips', () {
      final original = _makeEntry(
        relativePath: 'a/b/c.txt',
        status: MigrationFileStatus.failed,
        sourceHash: 'h1',
      );
      final restored = MigrationFileEntry.fromJson(original.toJson());
      expect(restored.relativePath, 'a/b/c.txt');
      expect(restored.status, MigrationFileStatus.failed);
      expect(restored.sourceHash, 'h1');
      expect(restored.destHash, isNull);
    });

    test('fromJson handles all status values', () {
      for (final status in MigrationFileStatus.values) {
        final entry = _makeEntry(status: status);
        final restored = MigrationFileEntry.fromJson(entry.toJson());
        expect(restored.status, status);
      }
    });

    test('fromJson defaults to pending for unknown status', () {
      final json = _makeEntry().toJson();
      json['status'] = 'unknown';
      expect(
          MigrationFileEntry.fromJson(json).status, MigrationFileStatus.pending);
    });

    test('copyWith updates status and hashes', () {
      final entry = _makeEntry();
      final updated = entry.copyWith(
        status: MigrationFileStatus.verified,
        destHash: 'newhash',
      );
      expect(updated.status, MigrationFileStatus.verified);
      expect(updated.destHash, 'newhash');
      expect(updated.relativePath, entry.relativePath);
    });

    test('optional fields omitted from json when null', () {
      final entry = _makeEntry();
      final json = entry.toJson();
      expect(json.containsKey('sourceHash'), isFalse);
      expect(json.containsKey('destHash'), isFalse);
      expect(json.containsKey('sourceModified'), isFalse);
    });
  });

  // =========================================================================
  // MigrationError — serialisation
  // =========================================================================

  group('MigrationError serialisation', () {
    test('toJson / fromJson round-trips', () {
      final err = _makeError(
        filePath: 'folder/file.txt',
        error: 'rate limited',
        retryable: true,
      );
      final restored = MigrationError.fromJson(err.toJson());
      expect(restored.filePath, 'folder/file.txt');
      expect(restored.error, 'rate limited');
      expect(restored.retryable, isTrue);
      expect(restored.timestamp, err.timestamp);
    });

    test('retryable defaults to false when missing from json', () {
      final json = _makeError().toJson()..remove('retryable');
      final err = MigrationError.fromJson(json);
      expect(err.retryable, isFalse);
    });
  });

  // =========================================================================
  // Plan CRUD
  // =========================================================================

  group('Plan CRUD', () {
    test('createPlan returns plan with generated id', () async {
      final service = MigrationService();
      final plan = await service.createPlan(
        name: 'Move Photos',
        sourceProvider: 'dropbox',
        destinationProvider: 'gdrive',
        sourcePath: '/Photos',
        destinationPath: '/Migrated',
      );

      expect(plan.id, isNotEmpty);
      expect(plan.name, 'Move Photos');
      expect(plan.status, MigrationStatus.pending);
    });

    test('created plan is returned by getPlans', () async {
      final service = MigrationService();
      final plan = await service.createPlan(
        name: 'P1',
        sourceProvider: 'dropbox',
        destinationProvider: 'filen',
        sourcePath: '/src',
        destinationPath: '/dst',
      );

      final plans = await service.getPlans();
      expect(plans.any((p) => p.id == plan.id), isTrue);
    });

    test('getPlan returns the correct plan', () async {
      final service = MigrationService();
      final plan = await service.createPlan(
        name: 'Find Me',
        sourceProvider: 'onedrive',
        destinationProvider: 'pcloud',
        sourcePath: '/A',
        destinationPath: '/B',
      );

      final found = await service.getPlan(plan.id);
      expect(found, isNotNull);
      expect(found!.name, 'Find Me');
    });

    test('getPlan returns null for unknown id', () async {
      final service = MigrationService();
      expect(await service.getPlan('nonexistent-id'), isNull);
    });

    test('deletePlan removes it from storage', () async {
      final service = MigrationService();
      final plan = await service.createPlan(
        name: 'To Delete',
        sourceProvider: 'sftp',
        destinationProvider: 'webdav',
        sourcePath: '/old',
        destinationPath: '/new',
      );

      await service.deletePlan(plan.id);
      final plans = await service.getPlans();
      expect(plans.any((p) => p.id == plan.id), isFalse);
    });

    test('multiple plans are stored and retrieved', () async {
      final service = MigrationService();
      for (int i = 1; i <= 3; i++) {
        await service.createPlan(
          name: 'Plan $i',
          sourceProvider: 'dropbox',
          destinationProvider: 'filen',
          sourcePath: '/src$i',
          destinationPath: '/dst$i',
        );
      }
      final plans = await service.getPlans();
      expect(plans.length, 3);
    });

    test('createPlan throws on invalid plan (empty name)', () async {
      final service = MigrationService();
      expect(
        () => service.createPlan(
          name: '',
          sourceProvider: 'dropbox',
          destinationProvider: 'filen',
          sourcePath: '/src',
          destinationPath: '/dst',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('createPlan throws when sourceProvider is empty', () async {
      final service = MigrationService();
      expect(
        () => service.createPlan(
          name: 'Test',
          sourceProvider: '',
          destinationProvider: 'filen',
          sourcePath: '/src',
          destinationPath: '/dst',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // =========================================================================
  // Estimation
  // =========================================================================

  group('estimateMigration', () {
    test('returns correct totalFiles and totalBytes', () {
      final service = MigrationService();
      final plan = _makePlan(throttleMBps: 10.0);
      final entries = [
        _makeEntry(sizeBytes: 1024 * 1024),
        _makeEntry(relativePath: 'b.txt', sizeBytes: 2 * 1024 * 1024),
      ];
      final est = service.estimateMigration(plan, entries);
      expect(est.totalFiles, 2);
      expect(est.totalBytes, 3 * 1024 * 1024);
    });

    test('estimatedDuration respects throttleMBps', () {
      final service = MigrationService();
      // 10 MB at 1 MB/s → ~10 seconds
      final plan = _makePlan(throttleMBps: 1.0);
      final entries = [_makeEntry(sizeBytes: 10 * 1024 * 1024)];
      final est = service.estimateMigration(plan, entries);
      expect(est.estimatedDuration.inSeconds, greaterThanOrEqualTo(9));
    });

    test('empty entries gives zero duration', () {
      final service = MigrationService();
      final plan = _makePlan();
      final est = service.estimateMigration(plan, []);
      expect(est.totalFiles, 0);
      expect(est.totalBytes, 0);
      expect(est.estimatedDuration.inSeconds, 0);
    });

    test('estimation accuracy: 100 MB at 5 MB/s is ~20 seconds', () {
      final service = MigrationService();
      final plan = _makePlan(throttleMBps: 5.0);
      final entries = [_makeEntry(sizeBytes: 100 * 1024 * 1024)];
      final est = service.estimateMigration(plan, entries);
      expect(est.estimatedDuration.inSeconds, closeTo(20, 1));
    });
  });

  // =========================================================================
  // Glob filtering
  // =========================================================================

  group('Glob filtering in scanSource', () {
    _StubClient _makeSourceWithFiles(
        List<String> fileNames, String basePath) {
      final stub = _StubStorage();
      stub.listings[basePath] = {
        'files': fileNames.map((n) => {'name': n, 'size': 100}).toList(),
        'folders': [],
      };
      return _StubClient(stub);
    }

    test('no include/exclude patterns includes all files', () async {
      final service = MigrationService();
      final plan = _makePlan(sourcePath: '/photos');
      final source =
          _makeSourceWithFiles(['a.jpg', 'b.txt', 'c.png'], '/photos');
      final entries = await service.scanSource(plan, source);
      expect(entries.length, 3);
    });

    test('include pattern *.jpg filters to only jpg files', () async {
      final service = MigrationService();
      final plan = _makePlan(
        sourcePath: '/photos',
        includePatterns: ['*.jpg'],
      );
      final source =
          _makeSourceWithFiles(['a.jpg', 'b.txt', 'c.jpg'], '/photos');
      final entries = await service.scanSource(plan, source);
      expect(entries.length, 2);
      expect(entries.every((e) => e.relativePath.endsWith('.jpg')), isTrue);
    });

    test('exclude pattern *.tmp excludes tmp files', () async {
      final service = MigrationService();
      final plan = _makePlan(
        sourcePath: '/data',
        excludePatterns: ['*.tmp'],
      );
      final source =
          _makeSourceWithFiles(['a.txt', 'b.tmp', 'c.tmp'], '/data');
      final entries = await service.scanSource(plan, source);
      expect(entries.length, 1);
      expect(entries.first.relativePath, 'a.txt');
    });

    test('exclude pattern node_modules/** excludes nested paths', () async {
      final service = MigrationService();
      final plan = _makePlan(
        sourcePath: '/project',
        excludePatterns: ['node_modules/**'],
      );
      final stub = _StubStorage();
      stub.listings['/project'] = {
        'files': [
          {'name': 'index.js', 'size': 500}
        ],
        'folders': [
          {'name': 'node_modules'}
        ],
      };
      stub.listings['/project/node_modules'] = {
        'files': [
          {'name': 'lodash.js', 'size': 2000}
        ],
        'folders': [],
      };
      final entries = await service.scanSource(plan, _StubClient(stub));
      expect(entries.any((e) => e.relativePath == 'index.js'), isTrue);
      expect(entries.any((e) => e.relativePath.contains('lodash')), isFalse);
    });

    test('include and exclude combined keeps only non-excluded matches', () async {
      final service = MigrationService();
      final stub = _StubStorage();
      stub.listings['/base'] = {
        'files': [
          {'name': 'photo.jpg', 'size': 100},
          {'name': 'readme.txt', 'size': 50},
        ],
        'folders': [
          {'name': 'thumbnails'}
        ],
      };
      stub.listings['/base/thumbnails'] = {
        'files': [
          {'name': 'thumb.jpg', 'size': 10}
        ],
        'folders': [],
      };
      final plan = _makePlan(
        sourcePath: '/base',
        includePatterns: ['*.jpg', 'thumbnails/*.jpg'],
        excludePatterns: ['thumbnails/*.jpg'],
      );
      final entries = await service.scanSource(plan, _StubClient(stub));
      // Only top-level photo.jpg survives.
      expect(entries.length, 1);
      expect(entries.first.relativePath, 'photo.jpg');
    });
  });

  // =========================================================================
  // Conflict resolution
  // =========================================================================

  group('Conflict resolution', () {
    Future<_StubStorage> _runSingleFileConflict({
      required ConflictPolicy policy,
      bool destExists = true,
      DateTime? sourceModified,
      DateTime? destModified,
    }) async {
      final srcStub = _StubStorage();
      srcStub.files['/source/file.txt'] = [1, 2, 3];
      srcStub.listings['/source'] = {
        'files': [
          {
            'name': 'file.txt',
            'size': 3,
            if (sourceModified != null)
              'modified': sourceModified.toIso8601String(),
          }
        ],
        'folders': [],
      };

      final dstStub = _StubStorage();
      if (destExists) {
        dstStub.resolvable['/dest/file.txt'] = {
          'name': 'file.txt',
          'size': 3,
          if (destModified != null)
            'modified': destModified.toIso8601String(),
        };
      }

      final service = MigrationService();
      final plan = _makePlan(
        sourcePath: '/source',
        destinationPath: '/dest',
        conflictPolicy: policy,
      );
      final entries = [
        _makeEntry(
          relativePath: 'file.txt',
          sizeBytes: 3,
          sourceModified: sourceModified,
        )
      ];

      await service.executeMigration(
        plan,
        entries,
        source: _StubClient(srcStub),
        destination: _StubClient(dstStub),
      );

      return dstStub;
    }

    test('skip policy skips files that already exist', () async {
      final dst =
          await _runSingleFileConflict(policy: ConflictPolicy.skip, destExists: true);
      expect(dst.uploads.isEmpty, isTrue);
    });

    test('skip policy transfers when file does not exist', () async {
      final dst = await _runSingleFileConflict(
          policy: ConflictPolicy.skip, destExists: false);
      expect(dst.uploads.isNotEmpty, isTrue);
    });

    test('overwrite policy transfers even when file exists', () async {
      final dst = await _runSingleFileConflict(
          policy: ConflictPolicy.overwrite, destExists: true);
      expect(dst.uploads.isNotEmpty, isTrue);
    });

    test('rename policy generates unique name when conflict exists', () async {
      final srcStub = _StubStorage();
      srcStub.files['/source/file.txt'] = [10, 20, 30];
      srcStub.listings['/source'] = {
        'files': [
          {'name': 'file.txt', 'size': 3}
        ],
        'folders': [],
      };

      final dstStub = _StubStorage();
      // file.txt exists; file_1.txt does not
      dstStub.resolvable['/dest/file.txt'] = {'name': 'file.txt', 'size': 3};
      dstStub.resolvable['/dest/file_1.txt'] = null; // not found

      final service = MigrationService();
      final plan = _makePlan(
        sourcePath: '/source',
        destinationPath: '/dest',
        conflictPolicy: ConflictPolicy.rename,
      );
      final entries = [_makeEntry(relativePath: 'file.txt', sizeBytes: 3)];

      await service.executeMigration(
        plan,
        entries,
        source: _StubClient(srcStub),
        destination: _StubClient(dstStub),
      );

      expect(dstStub.uploads.isNotEmpty, isTrue);
      // Uploaded file name should include _1
      final uploadedName = dstStub.uploads.first.$2;
      expect(uploadedName, contains('_1'));
    });

    test('newest policy skips when destination is newer', () async {
      final dst = await _runSingleFileConflict(
        policy: ConflictPolicy.newest,
        destExists: true,
        sourceModified: DateTime(2026, 1, 1),
        destModified: DateTime(2026, 6, 1),
      );
      expect(dst.uploads.isEmpty, isTrue);
    });

    test('newest policy transfers when source is newer', () async {
      final dst = await _runSingleFileConflict(
        policy: ConflictPolicy.newest,
        destExists: true,
        sourceModified: DateTime(2026, 6, 1),
        destModified: DateTime(2026, 1, 1),
      );
      expect(dst.uploads.isNotEmpty, isTrue);
    });
  });

  // =========================================================================
  // Progress tracking
  // =========================================================================

  group('Progress tracking', () {
    test('getProgress returns null before migration starts', () {
      final service = MigrationService();
      expect(service.getProgress('unknown-id'), isNull);
    });

    test('progress is updated after executeMigration', () async {
      final srcStub = _StubStorage();
      srcStub.files['/src/a.txt'] = [1, 2];
      srcStub.files['/src/b.txt'] = [3, 4];
      srcStub.listings['/src'] = {
        'files': [
          {'name': 'a.txt', 'size': 2},
          {'name': 'b.txt', 'size': 2},
        ],
        'folders': [],
      };

      final service = MigrationService();
      final plan = _makePlan(sourcePath: '/src', destinationPath: '/dst');
      final entries = await service.scanSource(plan, _StubClient(srcStub));

      MigrationProgress? lastProgress;
      await service.executeMigration(
        plan,
        entries,
        source: _StubClient(srcStub),
        destination: _StubClient(_StubStorage()),
        onProgress: (p) => lastProgress = p,
      );

      expect(lastProgress, isNotNull);
      expect(lastProgress!.migratedFiles, 2);
      expect(lastProgress!.skippedFiles, 0);
      expect(lastProgress!.failedFiles, 0);
    });

    test('failed files increment failedFiles counter', () async {
      final srcStub = _StubStorage();
      // intentionally do NOT add the file to stub.files → download will fail
      srcStub.listings['/src'] = {
        'files': [
          {'name': 'missing.txt', 'size': 100}
        ],
        'folders': [],
      };

      final service = MigrationService();
      final plan = _makePlan(sourcePath: '/src', destinationPath: '/dst');
      final entries = [_makeEntry(relativePath: 'missing.txt', sizeBytes: 100)];

      MigrationProgress? lastProgress;
      await service.executeMigration(
        plan,
        entries,
        source: _StubClient(srcStub),
        destination: _StubClient(_StubStorage()),
        onProgress: (p) => lastProgress = p,
      );

      expect(lastProgress!.failedFiles, 1);
      expect(lastProgress!.errors.length, 1);
    });
  });

  // =========================================================================
  // Pause / Resume / Cancel
  // =========================================================================

  group('Pause and resume', () {
    test('pauseMigration is a no-op when plan is not running', () {
      final service = MigrationService();
      expect(service.isPaused('not-running'), isFalse);
      service.pauseMigration('not-running'); // must not throw
      expect(service.isPaused('not-running'), isFalse);
    });

    test('resumeMigration on non-paused plan does not throw', () {
      final service = MigrationService();
      service.resumeMigration('any-id'); // must not throw
    });

    test('cancelMigration marks plan as cancelled', () {
      final service = MigrationService();
      service.cancelMigration('p999');
      expect(service.isCancelled('p999'), isTrue);
    });

    test('cancelMigration removes in-memory progress', () {
      final service = MigrationService();
      service.cancelMigration('p1');
      expect(service.getProgress('p1'), isNull);
    });

    test('isRunning is false before and after a completed migration', () async {
      final srcStub = _StubStorage();
      srcStub.files['/src/x.txt'] = [42];

      final service = MigrationService();
      final plan = _makePlan(sourcePath: '/src', destinationPath: '/dst');
      expect(service.isRunning(plan.id), isFalse);

      await service.executeMigration(
        plan,
        [_makeEntry(relativePath: 'x.txt', sizeBytes: 1)],
        source: _StubClient(srcStub),
        destination: _StubClient(_StubStorage()),
      );

      expect(service.isRunning(plan.id), isFalse);
    });
  });

  // =========================================================================
  // Single file migration
  // =========================================================================

  group('Single file migration', () {
    test('migrates exactly one file', () async {
      final srcStub = _StubStorage();
      srcStub.files['/src/single.pdf'] = List.generate(64, (i) => i);

      final dstStub = _StubStorage();

      final service = MigrationService();
      final plan = _makePlan(sourcePath: '/src', destinationPath: '/dst');
      final entries = [_makeEntry(relativePath: 'single.pdf', sizeBytes: 64)];

      await service.executeMigration(
        plan,
        entries,
        source: _StubClient(srcStub),
        destination: _StubClient(dstStub),
      );

      expect(dstStub.uploads.length, 1);
      expect(dstStub.uploads.first.$2, 'single.pdf');
    });

    test('single file entry has migrated status after execution', () async {
      final srcStub = _StubStorage();
      srcStub.files['/src/doc.txt'] = [1, 2, 3];

      final service = MigrationService();
      final plan = _makePlan(sourcePath: '/src', destinationPath: '/dst');
      final entry = _makeEntry(relativePath: 'doc.txt', sizeBytes: 3);

      await service.executeMigration(
        plan,
        [entry],
        source: _StubClient(srcStub),
        destination: _StubClient(_StubStorage()),
      );

      expect(entry.status, MigrationFileStatus.migrated);
    });
  });

  // =========================================================================
  // Empty migration (no files match)
  // =========================================================================

  group('Empty migration', () {
    test('empty entries list completes without error', () async {
      final service = MigrationService();
      final plan = _makePlan();

      await expectLater(
        service.executeMigration(
          plan,
          [],
          source: _StubClient(_StubStorage()),
          destination: _StubClient(_StubStorage()),
        ),
        completes,
      );
    });

    test('progress totalFiles is zero for empty migration', () async {
      final service = MigrationService();
      final plan = _makePlan();
      MigrationProgress? captured;

      await service.executeMigration(
        plan,
        [],
        source: _StubClient(_StubStorage()),
        destination: _StubClient(_StubStorage()),
        onProgress: (p) => captured = p,
      );

      expect(captured?.totalFiles ?? 0, 0);
    });
  });

  // =========================================================================
  // Bandwidth throttle delay calculation
  // =========================================================================

  group('Bandwidth throttle', () {
    test('throttleDelayMs is zero when throttleMBps is zero', () {
      final service = MigrationService();
      expect(service.throttleDelayMs(1024 * 1024, 0.0), 0);
    });

    test('throttleDelayMs for 1 MB at 1 MB/s is ~1000 ms', () {
      final service = MigrationService();
      final delayMs = service.throttleDelayMs(1024 * 1024, 1.0);
      expect(delayMs, closeTo(1000, 10));
    });

    test('throttleDelayMs for 512 KB at 2 MB/s is ~250 ms', () {
      final service = MigrationService();
      final delayMs = service.throttleDelayMs(512 * 1024, 2.0);
      expect(delayMs, closeTo(250, 10));
    });

    test('throttleDelayMs scales linearly with file size', () {
      final service = MigrationService();
      final d1 = service.throttleDelayMs(1024, 1.0);
      final d2 = service.throttleDelayMs(2048, 1.0);
      expect(d2, closeTo(d1 * 2, 2));
    });

    test('throttleDelayMs is zero for empty file', () {
      final service = MigrationService();
      expect(service.throttleDelayMs(0, 5.0), 0);
    });
  });

  // =========================================================================
  // Error tracking (retryable vs non-retryable)
  // =========================================================================

  group('Error tracking', () {
    test('network timeout error is marked retryable', () {
      final err = MigrationError(
        filePath: 'f.txt',
        error: 'connection timeout',
        timestamp: DateTime.now(),
        retryable: true,
      );
      expect(err.retryable, isTrue);
    });

    test('authentication error is not retryable', () {
      final err = MigrationError(
        filePath: 'f.txt',
        error: 'unauthorized 401',
        timestamp: DateTime.now(),
        retryable: false,
      );
      expect(err.retryable, isFalse);
    });

    test('progress accumulates multiple errors', () async {
      final srcStub = _StubStorage();
      // Both files missing → both fail
      srcStub.listings['/s'] = {
        'files': [
          {'name': 'a.txt', 'size': 10},
          {'name': 'b.txt', 'size': 10},
        ],
        'folders': [],
      };

      final service = MigrationService();
      final plan = _makePlan(sourcePath: '/s', destinationPath: '/d');
      final entries = [
        _makeEntry(relativePath: 'a.txt', sizeBytes: 10),
        _makeEntry(relativePath: 'b.txt', sizeBytes: 10),
      ];

      MigrationProgress? finalProgress;
      await service.executeMigration(
        plan,
        entries,
        source: _StubClient(srcStub),
        destination: _StubClient(_StubStorage()),
        onProgress: (p) => finalProgress = p,
      );

      expect(finalProgress!.errors.length, 2);
      expect(finalProgress!.failedFiles, 2);
    });

    test('each error records the correct filePath', () async {
      final srcStub = _StubStorage();
      srcStub.listings['/s'] = {
        'files': [
          {'name': 'missing.bin', 'size': 5}
        ],
        'folders': [],
      };

      final service = MigrationService();
      final plan = _makePlan(sourcePath: '/s', destinationPath: '/d');
      MigrationProgress? finalProgress;

      await service.executeMigration(
        plan,
        [_makeEntry(relativePath: 'missing.bin', sizeBytes: 5)],
        source: _StubClient(srcStub),
        destination: _StubClient(_StubStorage()),
        onProgress: (p) => finalProgress = p,
      );

      expect(finalProgress!.errors.first.filePath, 'missing.bin');
    });
  });

  // =========================================================================
  // Verification
  // =========================================================================

  group('verifyMigration', () {
    test('all files match → allMatch is true', () async {
      final dstStub = _StubStorage();
      dstStub.resolvable['/dest/a.txt'] = {'name': 'a.txt', 'size': 100};
      dstStub.resolvable['/dest/b.txt'] = {'name': 'b.txt', 'size': 200};

      final service = MigrationService();
      final plan = _makePlan(destinationPath: '/dest');
      final entries = [
        _makeEntry(
            relativePath: 'a.txt',
            sizeBytes: 100,
            status: MigrationFileStatus.migrated),
        _makeEntry(
            relativePath: 'b.txt',
            sizeBytes: 200,
            status: MigrationFileStatus.migrated),
      ];

      final result =
          await service.verifyMigration(plan, entries, _StubClient(dstStub));
      expect(result.allMatch, isTrue);
      expect(result.matchedFiles, 2);
      expect(result.mismatchedFiles, 0);
    });

    test('size mismatch is detected', () async {
      final dstStub = _StubStorage();
      // Destination has wrong size
      dstStub.resolvable['/dest/file.bin'] = {'name': 'file.bin', 'size': 999};

      final service = MigrationService();
      final plan = _makePlan(destinationPath: '/dest');
      final entries = [
        _makeEntry(
            relativePath: 'file.bin',
            sizeBytes: 500,
            status: MigrationFileStatus.migrated),
      ];

      final result =
          await service.verifyMigration(plan, entries, _StubClient(dstStub));
      expect(result.allMatch, isFalse);
      expect(result.mismatchedFiles, 1);
      expect(result.mismatches.first['path'], 'file.bin');
    });

    test('hash mismatch is detected when both hashes available', () async {
      final dstStub = _StubStorage();
      dstStub.resolvable['/dest/doc.txt'] = {
        'name': 'doc.txt',
        'size': 100,
        'md5Hash': 'different-hash',
      };

      final service = MigrationService();
      final plan = _makePlan(destinationPath: '/dest');
      final entries = [
        MigrationFileEntry(
          relativePath: 'doc.txt',
          sizeBytes: 100,
          status: MigrationFileStatus.migrated,
          sourceHash: 'original-hash',
        ),
      ];

      final result =
          await service.verifyMigration(plan, entries, _StubClient(dstStub));
      expect(result.allMatch, isFalse);
      expect(result.mismatches.first['sourceHash'], 'original-hash');
      expect(result.mismatches.first['destHash'], 'different-hash');
    });

    test('missing destination file is treated as mismatch', () async {
      final dstStub = _StubStorage(); // no entries in resolvable

      final service = MigrationService();
      final plan = _makePlan(destinationPath: '/dest');
      final entries = [
        _makeEntry(
            relativePath: 'lost.txt',
            sizeBytes: 50,
            status: MigrationFileStatus.migrated),
      ];

      final result =
          await service.verifyMigration(plan, entries, _StubClient(dstStub));
      expect(result.allMatch, isFalse);
      expect(result.mismatchedFiles, 1);
    });

    test('pending/skipped files are excluded from verification', () async {
      final dstStub = _StubStorage();
      dstStub.resolvable['/dest/done.txt'] = {'name': 'done.txt', 'size': 100};

      final service = MigrationService();
      final plan = _makePlan(destinationPath: '/dest');
      final entries = [
        _makeEntry(
            relativePath: 'done.txt',
            sizeBytes: 100,
            status: MigrationFileStatus.migrated),
        _makeEntry(
            relativePath: 'skip.txt',
            sizeBytes: 50,
            status: MigrationFileStatus.skipped),
        _makeEntry(
            relativePath: 'pend.txt',
            sizeBytes: 20,
            status: MigrationFileStatus.pending),
      ];

      final result =
          await service.verifyMigration(plan, entries, _StubClient(dstStub));
      expect(result.verifiedFiles, 1);
    });

    test('MigrationVerification toJson serialises all fields', () async {
      final v = MigrationVerification(
        totalFiles: 5,
        verifiedFiles: 5,
        matchedFiles: 4,
        mismatchedFiles: 1,
        mismatches: [
          {'path': 'x.bin', 'sourceHash': 'h1', 'destHash': 'h2'}
        ],
      );
      final json = v.toJson();
      expect(json['totalFiles'], 5);
      expect(json['matchedFiles'], 4);
      expect(json['mismatchedFiles'], 1);
      expect((json['mismatches'] as List).length, 1);
    });
  });

  // =========================================================================
  // Multiple concurrent migrations blocked
  // =========================================================================

  group('Concurrent migration guard', () {
    test('isRunning is false before execution starts', () {
      final service = MigrationService();
      expect(service.isRunning('any-plan'), isFalse);
    });

    test('isRunning is false after migration completes', () async {
      final srcStub = _StubStorage();
      srcStub.files['/src/f.txt'] = [1];

      final service = MigrationService();
      final plan = _makePlan(sourcePath: '/src', destinationPath: '/dst');

      await service.executeMigration(
        plan,
        [_makeEntry(relativePath: 'f.txt', sizeBytes: 1)],
        source: _StubClient(srcStub),
        destination: _StubClient(_StubStorage()),
      );

      expect(service.isRunning(plan.id), isFalse);
    });
  });

  // =========================================================================
  // Structure preservation
  // =========================================================================

  group('preserveStructure flag', () {
    test('preserveStructure=true recreates folder hierarchy', () async {
      final srcStub = _StubStorage();
      srcStub.files['/src/subdir/file.txt'] = [1, 2, 3];

      final dstStub = _StubStorage();

      final service = MigrationService();
      final plan = _makePlan(
        sourcePath: '/src',
        destinationPath: '/dst',
        preserveStructure: true,
      );
      final entries = [
        _makeEntry(relativePath: 'subdir/file.txt', sizeBytes: 3)
      ];

      await service.executeMigration(
        plan,
        entries,
        source: _StubClient(srcStub),
        destination: _StubClient(dstStub),
      );

      expect(dstStub.createdFolders.any((f) => f.contains('subdir')), isTrue);
    });

    test('preserveStructure=false flattens files into destinationPath', () async {
      final srcStub = _StubStorage();
      srcStub.files['/src/deep/nested/file.txt'] = [1, 2, 3];

      final dstStub = _StubStorage();

      final service = MigrationService();
      final plan = _makePlan(
        sourcePath: '/src',
        destinationPath: '/dst',
        preserveStructure: false,
      );
      final entries = [
        _makeEntry(relativePath: 'deep/nested/file.txt', sizeBytes: 3),
      ];

      await service.executeMigration(
        plan,
        entries,
        source: _StubClient(srcStub),
        destination: _StubClient(dstStub),
      );

      // The target path for the upload should be /dst (no subdir)
      expect(dstStub.uploads.any((u) => u.$3 == '/dst'), isTrue);
    });
  });
}
