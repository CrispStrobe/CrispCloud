// test/multi_cloud_test.dart
//
// Tests for MultiCloudService: connection management and file comparison logic.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/multi_cloud_service.dart';

// ---------------------------------------------------------------------------
// Mock CloudStorageClient
// ---------------------------------------------------------------------------

class MockCloudClient extends CloudStorageClient {
  final String _providerName;
  final Map<String, Map<String, dynamic>> _dirs;

  MockCloudClient(this._providerName, {Map<String, Map<String, dynamic>>? dirs})
      : _dirs = dirs ?? {};

  @override
  String get providerName => _providerName;

  @override
  String get rootPath => '/';

  @override
  bool get isAuthenticated => true;

  @override
  String? get userId => 'mock_user';

  @override
  String? get bucketId => null;

  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) async {}

  @override
  Future<bool> is2faNeeded(String email) async => false;

  @override
  Future<void> logout() async {}

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => null;

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    return _dirs[path] ?? {'files': [], 'folders': []};
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    onProgress?.call(fileData.length, fileData.length);
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {}

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    return Uint8List.fromList([1, 2, 3, 4]);
  }

  @override
  Future<void> createFolderPath(String path) async {}

  @override
  Future<void> deletePath(String path) async {}

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {}

  @override
  Future<void> renamePath(String path, String newName) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _file(String name, {int? size, String? updatedAt}) => {
      'name': name,
      'size': size?.toString(),
      'updatedAt': updatedAt,
    };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MultiCloudService – connection management', () {
    late MultiCloudService svc;

    setUp(() => svc = MultiCloudService());
    tearDown(() => svc.dispose());

    test('starts with no connections', () {
      expect(svc.getAllConnections(), isEmpty);
    });

    test('addConnection registers a connection', () {
      final client = MockCloudClient('ProviderA');
      svc.addConnection(
        id: 'a',
        label: 'Provider A',
        provider: CloudProvider.filen,
        client: client,
      );
      expect(svc.getAllConnections().length, 1);
      expect(svc.getConnection('a')?.label, 'Provider A');
    });

    test('getConnection returns null for unknown id', () {
      expect(svc.getConnection('does_not_exist'), isNull);
    });

    test('addConnection with same id overwrites previous', () {
      final c1 = MockCloudClient('P1');
      final c2 = MockCloudClient('P2');
      svc.addConnection(id: 'x', label: 'First', provider: CloudProvider.filen, client: c1);
      svc.addConnection(id: 'x', label: 'Second', provider: CloudProvider.s3, client: c2);
      expect(svc.getAllConnections().length, 1);
      expect(svc.getConnection('x')?.label, 'Second');
    });

    test('removeConnection removes entry', () async {
      final client = MockCloudClient('P');
      svc.addConnection(id: 'r', label: 'R', provider: CloudProvider.ftp, client: client);
      await svc.removeConnection('r');
      expect(svc.getConnection('r'), isNull);
      expect(svc.getAllConnections(), isEmpty);
    });

    test('removeConnection on unknown id is a no-op', () async {
      await svc.removeConnection('ghost');
      expect(svc.getAllConnections(), isEmpty);
    });

    test('getAllConnections returns unmodifiable snapshot', () {
      final c = MockCloudClient('P');
      svc.addConnection(id: 'z', label: 'Z', provider: CloudProvider.sftp, client: c);
      final list = svc.getAllConnections();
      expect(() => list.add(CloudConnection(id: 'x', label: 'X', provider: CloudProvider.sftp, client: c)), throwsUnsupportedError);
    });
  });

  group('MultiCloudService – compareFiles', () {
    late MultiCloudService svc;

    setUp(() => svc = MultiCloudService());
    tearDown(() => svc.dispose());

    test('returns empty list when directories are identical', () async {
      final now = DateTime(2025, 1, 1).toIso8601String();
      final dirData = {
        '/': {
          'files': [_file('readme.txt', size: 100, updatedAt: now)],
          'folders': [],
        }
      };
      final clientA = MockCloudClient('A', dirs: dirData);
      final clientB = MockCloudClient('B', dirs: dirData);

      final diffs = await svc.compareFiles(
        clientA: clientA,
        pathA: '/',
        clientB: clientB,
        pathB: '/',
      );
      expect(diffs, isEmpty);
    });

    test('detects file only in A', () async {
      final clientA = MockCloudClient('A', dirs: {
        '/': {
          'files': [_file('only_in_a.txt', size: 50)],
          'folders': [],
        }
      });
      final clientB = MockCloudClient('B', dirs: {
        '/': {'files': [], 'folders': []}
      });

      final diffs = await svc.compareFiles(
        clientA: clientA,
        pathA: '/',
        clientB: clientB,
        pathB: '/',
      );
      expect(diffs.length, 1);
      expect(diffs.first.kind, FileDiffKind.onlyInA);
      expect(diffs.first.name, 'only_in_a.txt');
    });

    test('detects file only in B', () async {
      final clientA = MockCloudClient('A', dirs: {
        '/': {'files': [], 'folders': []}
      });
      final clientB = MockCloudClient('B', dirs: {
        '/': {
          'files': [_file('only_in_b.txt', size: 60)],
          'folders': [],
        }
      });

      final diffs = await svc.compareFiles(
        clientA: clientA,
        pathA: '/',
        clientB: clientB,
        pathB: '/',
      );
      expect(diffs.length, 1);
      expect(diffs.first.kind, FileDiffKind.onlyInB);
    });

    test('detects size difference', () async {
      final now = DateTime(2025, 1, 1).toIso8601String();
      final clientA = MockCloudClient('A', dirs: {
        '/': {
          'files': [_file('data.bin', size: 1024, updatedAt: now)],
          'folders': [],
        }
      });
      final clientB = MockCloudClient('B', dirs: {
        '/': {
          'files': [_file('data.bin', size: 2048, updatedAt: now)],
          'folders': [],
        }
      });

      final diffs = await svc.compareFiles(
        clientA: clientA,
        pathA: '/',
        clientB: clientB,
        pathB: '/',
      );
      expect(diffs.length, 1);
      expect(diffs.first.kind, FileDiffKind.sizeDiffers);
    });

    test('detects date difference', () async {
      final clientA = MockCloudClient('A', dirs: {
        '/': {
          'files': [_file('log.txt', size: 100, updatedAt: '2025-01-01T00:00:00Z')],
          'folders': [],
        }
      });
      final clientB = MockCloudClient('B', dirs: {
        '/': {
          'files': [_file('log.txt', size: 100, updatedAt: '2025-06-01T00:00:00Z')],
          'folders': [],
        }
      });

      final diffs = await svc.compareFiles(
        clientA: clientA,
        pathA: '/',
        clientB: clientB,
        pathB: '/',
      );
      expect(diffs.length, 1);
      expect(diffs.first.kind, FileDiffKind.dateDiffers);
    });

    test('detects both size and date differ', () async {
      final clientA = MockCloudClient('A', dirs: {
        '/': {
          'files': [_file('doc.pdf', size: 500, updatedAt: '2024-01-01T00:00:00Z')],
          'folders': [],
        }
      });
      final clientB = MockCloudClient('B', dirs: {
        '/': {
          'files': [_file('doc.pdf', size: 999, updatedAt: '2025-06-01T00:00:00Z')],
          'folders': [],
        }
      });

      final diffs = await svc.compareFiles(
        clientA: clientA,
        pathA: '/',
        clientB: clientB,
        pathB: '/',
      );
      expect(diffs.length, 1);
      expect(diffs.first.kind, FileDiffKind.bothDiffer);
    });

    test('handles multiple diffs in one comparison', () async {
      final now = DateTime(2025, 3, 1).toIso8601String();
      final clientA = MockCloudClient('A', dirs: {
        '/': {
          'files': [
            _file('same.txt', size: 10, updatedAt: now),
            _file('a_only.txt', size: 20),
            _file('size_diff.bin', size: 100, updatedAt: now),
          ],
          'folders': [],
        }
      });
      final clientB = MockCloudClient('B', dirs: {
        '/': {
          'files': [
            _file('same.txt', size: 10, updatedAt: now),
            _file('b_only.txt', size: 30),
            _file('size_diff.bin', size: 200, updatedAt: now),
          ],
          'folders': [],
        }
      });

      final diffs = await svc.compareFiles(
        clientA: clientA,
        pathA: '/',
        clientB: clientB,
        pathB: '/',
      );
      // same.txt should produce no diff; expect 3 diffs
      expect(diffs.length, 3);
      final kinds = diffs.map((d) => d.kind).toSet();
      expect(kinds, containsAll([FileDiffKind.onlyInA, FileDiffKind.onlyInB, FileDiffKind.sizeDiffers]));
    });
  });

  group('MultiCloudService – searchAcrossProviders', () {
    late MultiCloudService svc;

    setUp(() => svc = MultiCloudService());
    tearDown(() => svc.dispose());

    test('returns empty list for blank query', () async {
      final results = await svc.searchAcrossProviders('', []);
      expect(results, isEmpty);
    });

    test('finds matching files across multiple connections', () async {
      final clientA = MockCloudClient('A', dirs: {
        '/': {
          'files': [_file('report_2025.pdf'), _file('photo.jpg')],
          'folders': [],
        }
      });
      final clientB = MockCloudClient('B', dirs: {
        '/': {
          'files': [_file('annual_report.docx'), _file('notes.txt')],
          'folders': [],
        }
      });

      svc.addConnection(id: 'a', label: 'A', provider: CloudProvider.filen, client: clientA);
      svc.addConnection(id: 'b', label: 'B', provider: CloudProvider.s3, client: clientB);

      final results = await svc.searchAcrossProviders('report', svc.getAllConnections());
      expect(results.length, 2);
      final names = results.map((r) => r.item.name).toSet();
      expect(names, containsAll(['report_2025.pdf', 'annual_report.docx']));
    });
  });
}
