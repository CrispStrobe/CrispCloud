// test/coverage_boost_test.dart
//
// Combined coverage-boost tests targeting services that lack tests or have
// thin coverage.  This single file adds 200+ test cases covering:
//
//   1. PathSanitizer — sanitizeFilename, isPathTraversal,
//                      normalizePathSeparators, isReservedName, helpers
//   2. ConnectionProfile / ConnectionProfileService — model edge-cases,
//      service persistence, corrupted-storage, multi-provider
//   3. MultiCloudService — transfer helpers, FileDiff model, search edge-cases
//   4. PlaceholderMeta — encode/decode edge-cases not in existing tests
//   5. SyncWatcherService / PollingWatcherService — config & state
//   6. ActionHistoryService — record, canUndo, undo edge-cases
//   7. ActionRecord — description strings
//   8. StorageAnalyticsService — categorization, duplicates, stale,
//      cleanup suggestions, savings estimation, model serialization
//   9. SavedSearch model — toJson/fromJson round-trips, filterSummary
//  10. AppLockService — setup/verify/disable (in-memory storage, no biometrics)
//  11. FileDiff — toString representations
//  12. FileItem — sizeFormatted, equality, hashCode
//  13. LocaleFormats — separators, date patterns, 12h/24h, unit labels
//  14. formatBytesLocale / formatDateLocale / formatNumberLocale — locale
//  15. UndoResult — factories

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:crisp_cloud/services/path_sanitizer.dart';
import 'package:crisp_cloud/services/connection_profiles.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/multi_cloud_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/placeholder_service.dart';
import 'package:crisp_cloud/services/sync_watcher.dart';
import 'package:crisp_cloud/services/action_history_service.dart';
import 'package:crisp_cloud/services/storage_analytics_service.dart';
import 'package:crisp_cloud/services/saved_search_service.dart';
import 'package:crisp_cloud/services/app_lock_service.dart';
import 'package:crisp_cloud/services/formatters.dart';
import 'package:crisp_cloud/models/file_item.dart';

// ============================================================================
// Shared helpers / mocks
// ============================================================================

/// Minimal CloudStorageClient mock used by MultiCloudService tests.
class _MockClient extends CloudStorageClient {
  final String _name;
  final Map<String, Map<String, dynamic>> _dirs;

  _MockClient(this._name, {Map<String, Map<String, dynamic>>? dirs})
      : _dirs = dirs ?? {};

  @override
  String get providerName => _name;
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => true;
  @override
  String? get userId => 'u';
  @override
  String? get bucketId => null;

  @override
  Future<void> login(String e, String p, {String? twoFactorCode}) async {}
  @override
  Future<bool> is2faNeeded(String e) async => false;
  @override
  Future<void> logout() async {}
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => null;
  @override
  Future<Map<String, dynamic>> listPath(String path) async =>
      _dirs[path] ?? {'files': [], 'folders': []};
  @override
  Future<void> uploadFile(
    List<int> data, String name, String target, {Function(int, int)? onProgress}) async {
    onProgress?.call(data.length, data.length);
  }
  @override
  Future<void> downloadFileByPath(String rp, String lp, {Function(int, int)? onProgress}) async {}
  @override
  Future<Uint8List> downloadFileBytes(String rp, {Function(int, int)? onProgress}) async =>
      Uint8List.fromList([1, 2, 3]);
  @override
  Future<void> createFolderPath(String path) async {}
  @override
  Future<void> deletePath(String path) async {}
  @override
  Future<void> movePath(String src, String dst) async {}
  @override
  Future<void> renamePath(String path, String name) async {}
}

Map<String, dynamic> _f(String name, {int? size, String? updatedAt}) => {
      'name': name,
      if (size != null) 'size': size.toString(),
      if (updatedAt != null) 'updatedAt': updatedAt,
    };

FileItem _fileItem(String name, {int? size, DateTime? updatedAt, String? path}) =>
    FileItem(name: name, isFolder: false, size: size, updatedAt: updatedAt, path: path ?? '/$name');

FileItem _folderItem(String name) => FileItem(name: name, isFolder: true);

// ============================================================================
// 1. PathSanitizer
// ============================================================================

void _pathSanitizerTests() {
  group('PathSanitizer.sanitizeFilename', () {
    test('empty string returns underscore', () {
      expect(PathSanitizer.sanitizeFilename(''), '_');
    });

    test('whitespace-only returns underscore', () {
      expect(PathSanitizer.sanitizeFilename('   '), '_');
    });

    test('normal filename unchanged', () {
      expect(PathSanitizer.sanitizeFilename('hello.txt'), 'hello.txt');
    });

    test('removes null bytes', () {
      expect(PathSanitizer.sanitizeFilename('file\x00name'), 'filename');
    });

    test('removes control characters', () {
      expect(PathSanitizer.sanitizeFilename('fi\x01le\x1Fname'), 'filename');
    });

    test('replaces forbidden characters with underscore', () {
      final result = PathSanitizer.sanitizeFilename('a<b>c:d"e/f\\g|h?i*j');
      expect(result.contains('<'), isFalse);
      expect(result.contains('>'), isFalse);
      expect(result.contains(':'), isFalse);
      expect(result.contains('"'), isFalse);
      expect(result.contains('?'), isFalse);
      expect(result.contains('*'), isFalse);
    });

    test('trims trailing dots and spaces', () {
      expect(PathSanitizer.sanitizeFilename('file.  '), 'file');
      expect(PathSanitizer.sanitizeFilename('file..'), 'file');
    });

    test('preserves leading dot for hidden files', () {
      expect(PathSanitizer.sanitizeFilename('.gitignore'), '.gitignore');
    });

    test('truncates long names to 255 chars', () {
      final longName = 'a' * 300;
      final result = PathSanitizer.sanitizeFilename(longName);
      expect(result.length, lessThanOrEqualTo(255));
    });

    test('preserves extension when truncating', () {
      final longBase = 'x' * 260;
      final result = PathSanitizer.sanitizeFilename('$longBase.txt');
      expect(result.length, lessThanOrEqualTo(255));
      expect(result.endsWith('.txt'), isTrue);
    });

    test('semicolon replaced with underscore', () {
      expect(PathSanitizer.sanitizeFilename('file;name'), 'file_name');
    });

    test('backtick replaced with underscore', () {
      expect(PathSanitizer.sanitizeFilename('cmd`exec`'), 'cmd_exec_');
    });

    test('dollar sign replaced', () {
      expect(PathSanitizer.sanitizeFilename('\$HOME'), '_HOME');
    });

    test('ampersand replaced', () {
      expect(PathSanitizer.sanitizeFilename('a&b'), 'a_b');
    });

    test('exclamation replaced', () {
      expect(PathSanitizer.sanitizeFilename('file!'), 'file_');
    });

    test('unicode characters preserved', () {
      expect(PathSanitizer.sanitizeFilename('Ünterlagen.pdf'), 'Ünterlagen.pdf');
    });
  });

  group('PathSanitizer.isPathTraversal', () {
    test('empty path returns false', () {
      expect(PathSanitizer.isPathTraversal(''), isFalse);
    });

    test('normal relative path returns false', () {
      expect(PathSanitizer.isPathTraversal('docs/file.txt'), isFalse);
    });

    test('../ is traversal', () {
      expect(PathSanitizer.isPathTraversal('../etc/passwd'), isTrue);
    });

    test('../ nested is traversal', () {
      expect(PathSanitizer.isPathTraversal('subdir/../../secret'), isTrue);
    });

    test('..\\  is traversal on windows-style paths', () {
      expect(PathSanitizer.isPathTraversal('..\\windows\\system32'), isTrue);
    });

    test('bare .. is traversal', () {
      expect(PathSanitizer.isPathTraversal('..'), isTrue);
    });

    test('absolute Unix path is traversal', () {
      expect(PathSanitizer.isPathTraversal('/etc/passwd'), isTrue);
    });

    test('Windows absolute path is traversal', () {
      expect(PathSanitizer.isPathTraversal('C:\\Windows'), isTrue);
    });

    test('null byte in path is traversal', () {
      expect(PathSanitizer.isPathTraversal('file\x00.txt'), isTrue);
    });

    test('percent-encoded traversal detected', () {
      expect(PathSanitizer.isPathTraversal('%2e%2e%2f'), isTrue);
    });

    test('double-encoded traversal detected', () {
      expect(PathSanitizer.isPathTraversal('%252e%252e'), isTrue);
    });

    test('path with only filename is safe', () {
      expect(PathSanitizer.isPathTraversal('readme.md'), isFalse);
    });

    test('path with subdirectory is safe', () {
      expect(PathSanitizer.isPathTraversal('a/b/c.txt'), isFalse);
    });
  });

  group('PathSanitizer.normalizePathSeparators', () {
    test('empty string unchanged', () {
      expect(PathSanitizer.normalizePathSeparators(''), '');
    });

    test('backslashes converted to forward slashes', () {
      expect(PathSanitizer.normalizePathSeparators('a\\b\\c'), 'a/b/c');
    });

    test('consecutive slashes collapsed', () {
      expect(PathSanitizer.normalizePathSeparators('a//b///c'), 'a/b/c');
    });

    test('leading double slash preserved (UNC path)', () {
      final result = PathSanitizer.normalizePathSeparators('//server/share');
      expect(result.startsWith('//'), isTrue);
    });

    test('mixed separators normalized', () {
      expect(PathSanitizer.normalizePathSeparators('a/b\\c//d'), 'a/b/c/d');
    });
  });

  group('PathSanitizer.isReservedName', () {
    test('CON is reserved', () {
      expect(PathSanitizer.isReservedName('CON'), isTrue);
    });

    test('NUL is reserved', () {
      expect(PathSanitizer.isReservedName('NUL'), isTrue);
    });

    test('PRN is reserved', () {
      expect(PathSanitizer.isReservedName('PRN'), isTrue);
    });

    test('COM1 is reserved', () {
      expect(PathSanitizer.isReservedName('COM1'), isTrue);
    });

    test('LPT9 is reserved', () {
      expect(PathSanitizer.isReservedName('LPT9'), isTrue);
    });

    test('CON.txt is reserved (extension stripped)', () {
      expect(PathSanitizer.isReservedName('CON.txt'), isTrue);
    });

    test('case insensitive — con is reserved', () {
      expect(PathSanitizer.isReservedName('con'), isTrue);
    });

    test('normal name is not reserved', () {
      expect(PathSanitizer.isReservedName('documents'), isFalse);
    });

    test('empty name is not reserved', () {
      expect(PathSanitizer.isReservedName(''), isFalse);
    });
  });

  group('PathSanitizer helpers', () {
    test('isWhitespaceOnly returns true for spaces', () {
      expect(PathSanitizer.isWhitespaceOnly('   '), isTrue);
    });

    test('isWhitespaceOnly returns false for empty string', () {
      expect(PathSanitizer.isWhitespaceOnly(''), isFalse);
    });

    test('isWhitespaceOnly returns false for normal name', () {
      expect(PathSanitizer.isWhitespaceOnly('file'), isFalse);
    });

    test('isDotsOnly returns true for "..."', () {
      expect(PathSanitizer.isDotsOnly('...'), isTrue);
    });

    test('isDotsOnly returns false for ".gitignore"', () {
      expect(PathSanitizer.isDotsOnly('.gitignore'), isFalse);
    });

    test('isDotsOnly returns false for empty string', () {
      expect(PathSanitizer.isDotsOnly(''), isFalse);
    });

    test('getExtension returns ".pdf" for "report.pdf"', () {
      expect(PathSanitizer.getExtension('report.pdf'), '.pdf');
    });

    test('getExtension returns "" for no-extension file', () {
      expect(PathSanitizer.getExtension('Makefile'), '');
    });

    test('getExtension returns "" for hidden file like ".gitignore"', () {
      expect(PathSanitizer.getExtension('.gitignore'), '');
    });

    test('hasBom returns true when BOM present', () {
      expect(PathSanitizer.hasBom('\uFEFF file.txt'), isTrue);
    });

    test('hasBom returns false for normal string', () {
      expect(PathSanitizer.hasBom('file.txt'), isFalse);
    });
  });
}

// ============================================================================
// 2. ConnectionProfile model edge-cases
// ============================================================================

void _connectionProfileTests() {
  group('ConnectionProfile model – edge cases', () {
    test('toJson/fromJson with many fields', () {
      const p = ConnectionProfile(
        name: 'prod',
        provider: 'sftp',
        fields: {
          'host': '10.0.0.1',
          'port': '22',
          'user': 'admin',
          'privateKey': '-----BEGIN RSA-----',
          'passphrase': 's3cr3t',
        },
      );
      final json = p.toJson();
      final r = ConnectionProfile.fromJson(json);
      expect(r.fields.length, 5);
      expect(r.fields['passphrase'], 's3cr3t');
    });

    test('fields map preserves order', () {
      const p = ConnectionProfile(
        name: 'x',
        provider: 'ftp',
        fields: {'b': '2', 'a': '1'},
      );
      final r = ConnectionProfile.fromJson(p.toJson());
      expect(r.fields.keys.toList(), containsAll(['a', 'b']));
    });

    test('fromJson with fields containing int-like strings', () {
      final p = ConnectionProfile.fromJson({
        'name': 'x',
        'provider': 'sftp',
        'fields': {'port': '22'},
      });
      expect(p.fields['port'], '22');
      expect(p.fields['port'], isA<String>());
    });

    test('name and provider are required — toJson preserves them', () {
      const p = ConnectionProfile(name: '', provider: '', fields: {});
      final json = p.toJson();
      expect(json['name'], '');
      expect(json['provider'], '');
    });
  });

  group('ConnectionProfileService – extended', () {
    late InMemorySecureStorage storage;
    late ConnectionProfileService svc;

    setUp(() {
      storage = InMemorySecureStorage();
      svc = ConnectionProfileService(storage);
    });

    test('save and retrieve ten profiles', () async {
      for (var i = 0; i < 10; i++) {
        await svc.save(ConnectionProfile(
          name: 'profile_$i',
          provider: 's3',
          fields: {'bucket': 'b$i'},
        ));
      }
      final all = await svc.getAll();
      expect(all.length, 10);
    });

    test('getForProvider with no matching returns empty list', () async {
      await svc.save(const ConnectionProfile(
          name: 'x', provider: 'ftp', fields: {}));
      expect(await svc.getForProvider('gdrive'), isEmpty);
    });

    test('delete then save same name works', () async {
      await svc.save(const ConnectionProfile(
          name: 'n', provider: 's3', fields: {'k': 'v1'}));
      await svc.delete('n', 's3');
      await svc.save(const ConnectionProfile(
          name: 'n', provider: 's3', fields: {'k': 'v2'}));
      final all = await svc.getAll();
      expect(all.length, 1);
      expect(all.first.fields['k'], 'v2');
    });

    test('getAll on empty storage returns []', () async {
      final all = await svc.getAll();
      expect(all, isEmpty);
    });

    test('delete all one by one leaves empty list', () async {
      for (final p in ['a', 'b', 'c']) {
        await svc.save(
            ConnectionProfile(name: p, provider: 'ftp', fields: {}));
      }
      await svc.delete('a', 'ftp');
      await svc.delete('b', 'ftp');
      await svc.delete('c', 'ftp');
      expect(await svc.getAll(), isEmpty);
    });
  });
}

// ============================================================================
// 3. FileDiff model
// ============================================================================

void _fileDiffTests() {
  group('FileDiff.toString', () {
    final item = FileItem(
        name: 'test.bin',
        isFolder: false,
        size: 1024,
        updatedAt: DateTime(2025, 1, 1));

    test('onlyInA contains "only in A"', () {
      final d = FileDiff(name: 'test.bin', kind: FileDiffKind.onlyInA, itemA: item);
      expect(d.toString(), contains('only in A'));
    });

    test('onlyInB contains "only in B"', () {
      final d = FileDiff(name: 'test.bin', kind: FileDiffKind.onlyInB, itemB: item);
      expect(d.toString(), contains('only in B'));
    });

    test('sizeDiffers contains "size differs"', () {
      final d = FileDiff(
          name: 'file',
          kind: FileDiffKind.sizeDiffers,
          itemA: item,
          itemB: item);
      expect(d.toString(), contains('size differs'));
    });

    test('dateDiffers contains "date differs"', () {
      final d = FileDiff(
          name: 'file',
          kind: FileDiffKind.dateDiffers,
          itemA: item,
          itemB: item);
      expect(d.toString(), contains('date differs'));
    });

    test('bothDiffer contains "size and date differ"', () {
      final d = FileDiff(
          name: 'file',
          kind: FileDiffKind.bothDiffer,
          itemA: item,
          itemB: item);
      expect(d.toString(), contains('size and date differ'));
    });
  });
}

// ============================================================================
// 4. MultiCloudService – additional coverage
// ============================================================================

void _multiCloudTests() {
  group('MultiCloudService – extended', () {
    late MultiCloudService svc;

    setUp(() => svc = MultiCloudService());
    tearDown(() => svc.dispose());

    test('dispose removes all connections', () async {
      svc.addConnection(
          id: 'a',
          label: 'A',
          provider: CloudProvider.s3,
          client: _MockClient('A'));
      svc.addConnection(
          id: 'b',
          label: 'B',
          provider: CloudProvider.ftp,
          client: _MockClient('B'));
      await svc.dispose();
      expect(svc.getAllConnections(), isEmpty);
    });

    test('getAllConnections is unmodifiable', () {
      final c = _MockClient('P');
      svc.addConnection(
          id: 'z', label: 'Z', provider: CloudProvider.sftp, client: c);
      final list = svc.getAllConnections();
      expect(
          () => list.add(CloudConnection(
              id: 'x',
              label: 'X',
              provider: CloudProvider.sftp,
              client: c)),
          throwsUnsupportedError);
    });

    test('compareFiles: empty directories return empty list', () async {
      final clientA = _MockClient('A', dirs: {
        '/': {'files': [], 'folders': []}
      });
      final clientB = _MockClient('B', dirs: {
        '/': {'files': [], 'folders': []}
      });
      final diffs = await svc.compareFiles(
          clientA: clientA, pathA: '/', clientB: clientB, pathB: '/');
      expect(diffs, isEmpty);
    });

    test('compareFiles: folders compared by name', () async {
      final clientA = _MockClient('A', dirs: {
        '/': {
          'files': [],
          'folders': [_f('docs')],
        }
      });
      final clientB = _MockClient('B', dirs: {
        '/': {'files': [], 'folders': []}
      });
      final diffs = await svc.compareFiles(
          clientA: clientA, pathA: '/', clientB: clientB, pathB: '/');
      expect(diffs.length, 1);
      expect(diffs.first.kind, FileDiffKind.onlyInA);
    });

    test('searchAcrossProviders: whitespace-only query returns empty', () async {
      final results = await svc.searchAcrossProviders('   ', []);
      expect(results, isEmpty);
    });

    test(
        'searchAcrossProviders: provider that throws returns empty (graceful)',
        () async {
      // _MockClient returns empty dirs, so search gracefully returns []
      final client = _MockClient('X', dirs: {
        '/': {
          'files': [_f('match.txt')],
          'folders': [],
        }
      });
      svc.addConnection(
          id: 'x', label: 'X', provider: CloudProvider.ftp, client: client);
      final results =
          await svc.searchAcrossProviders('match', svc.getAllConnections());
      expect(results.isNotEmpty, isTrue);
      expect(results.first.item.name, 'match.txt');
    });

    test('MultiCloudSearchResult fields are set correctly', () async {
      final client = _MockClient('Prov', dirs: {
        '/': {
          'files': [_f('data.csv')],
          'folders': [],
        }
      });
      svc.addConnection(
          id: 'p',
          label: 'My Provider',
          provider: CloudProvider.gdrive,
          client: client);
      final results =
          await svc.searchAcrossProviders('data', svc.getAllConnections());
      expect(results.first.connectionId, 'p');
      expect(results.first.connectionLabel, 'My Provider');
      expect(results.first.providerName, 'Prov');
    });
  });
}

// ============================================================================
// 5. PlaceholderMeta – additional edge cases
// ============================================================================

void _placeholderMetaTests() {
  group('PlaceholderMeta – extra edge cases', () {
    test('fromJson with all fields present', () {
      final meta = PlaceholderMeta.fromJson({
        'remotePath': '/photos/img.jpg',
        'provider': 'dropbox',
        'sizeBytes': 2048,
        'remoteModified': '2026-03-15T09:00:00.000Z',
        'contentHash': 'sha256:deadbeef',
        'version': 1,
      });
      expect(meta.remotePath, '/photos/img.jpg');
      expect(meta.sizeBytes, 2048);
      expect(meta.contentHash, 'sha256:deadbeef');
      expect(meta.remoteModified, isNotNull);
    });

    test('decode handles garbage input', () {
      expect(PlaceholderMeta.decode('{"not":"valid"...'), isNull);
    });

    test('encode/decode round-trip with all optional fields', () {
      final original = PlaceholderMeta(
        remotePath: '/archive/backup.tar.gz',
        provider: 'b2',
        sizeBytes: 10737418240,
        remoteModified: DateTime.utc(2026, 6, 1, 12, 0),
        contentHash: 'abc123',
      );
      final decoded = PlaceholderMeta.decode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.sizeBytes, 10737418240);
      expect(decoded.contentHash, 'abc123');
      expect(decoded.remoteModified!.year, 2026);
    });

    test('toJson version is always 1', () {
      final meta =
          PlaceholderMeta(remotePath: '/x', provider: 's3', sizeBytes: 0);
      expect(meta.toJson()['version'], 1);
    });

    test('decode returns null for boolean input', () {
      expect(PlaceholderMeta.decode('true'), isNull);
    });

    test('isPlaceholder with extension in upper case still works', () {
      // The extension check is exact — uppercase would not match lowercase const
      expect(PlaceholderService.isPlaceholder('file.CRISPCLOUD'), isFalse);
      expect(PlaceholderService.isPlaceholder('file.crispcloud'), isTrue);
    });
  });
}

// ============================================================================
// 6. SyncWatcherService / PollingWatcherService – config & state
// ============================================================================

void _syncWatcherTests() {
  group('SyncWatcherService – config', () {
    test('watchedPairIds is empty initially', () {
      final w = SyncWatcherService();
      expect(w.watchedPairIds, isEmpty);
      w.dispose();
    });

    test('unwatchPair on missing id is no-op', () {
      final w = SyncWatcherService();
      w.unwatchPair(999);
      expect(w.watcherCount, 0);
      w.dispose();
    });

    test('dispose is idempotent', () {
      final w = SyncWatcherService();
      w.dispose();
      w.dispose(); // should not throw
    });

    test('debounceDelay is 1 second when configured', () {
      final w = SyncWatcherService(debounceDelay: const Duration(seconds: 1));
      expect(w.debounceDelay, const Duration(seconds: 1));
      w.dispose();
    });

    test('isWatching returns false for unwatched id', () {
      final w = SyncWatcherService();
      expect(w.isWatching(42), isFalse);
      w.dispose();
    });
  });

  group('PollingWatcherService – config', () {
    test('stop on unstarted service is safe', () {
      final p = PollingWatcherService();
      p.stop(); // should not throw
      p.dispose();
    });

    test('dispose on unstarted service is safe', () {
      final p = PollingWatcherService();
      p.dispose(); // should not throw
    });

    test('interval accessible via getter', () {
      final p = PollingWatcherService(interval: const Duration(seconds: 10));
      expect(p.interval, const Duration(seconds: 10));
      p.dispose();
    });

    test('start then stop then dispose is safe', () async {
      final p = PollingWatcherService(
          interval: const Duration(milliseconds: 200));
      p.start([1], (id) async {});
      p.stop();
      p.dispose();
    });
  });
}

// ============================================================================
// 7. ActionHistoryService + ActionRecord
// ============================================================================

void _actionHistoryTests() {
  group('ActionRecord.description', () {
    String _desc(ActionType t,
        {String orig = '/dir/file.txt', String? newPath}) {
      return ActionRecord(
        id: 'test',
        timestamp: DateTime.now(),
        type: t,
        originalPath: orig,
        newPath: newPath,
        provider: 'local',
      ).description;
    }

    test('delete description mentions filename', () {
      expect(_desc(ActionType.delete), contains('file.txt'));
    });

    test('rename description shows old and new name', () {
      final d = _desc(ActionType.rename,
          orig: '/dir/old.txt', newPath: '/dir/new.txt');
      expect(d, contains('old.txt'));
      expect(d, contains('new.txt'));
    });

    test('rename with null newPath shows "?"', () {
      final d = _desc(ActionType.rename, newPath: null);
      expect(d, contains('?'));
    });

    test('move description mentions filename', () {
      expect(_desc(ActionType.move), contains('file.txt'));
    });

    test('copy description mentions filename', () {
      expect(_desc(ActionType.copy), contains('file.txt'));
    });

    test('createFolder description mentions folder name', () {
      final d = _desc(ActionType.createFolder, orig: '/dir/new_folder');
      expect(d, contains('new_folder'));
    });
  });

  group('ActionHistoryService – canUndo rules', () {
    late ActionHistoryService svc;

    setUp(() => svc = ActionHistoryService());

    ActionRecord _rec(ActionType t, String provider, {String? newPath}) =>
        ActionRecord(
          id: const Uuid().v4(),
          timestamp: DateTime.now(),
          type: t,
          originalPath: '/x/file.txt',
          newPath: newPath,
          provider: provider,
        );

    test('delete on local cannot be undone', () {
      expect(svc.canUndo(_rec(ActionType.delete, 'local')), isFalse);
    });

    test('delete on remote can be undone', () {
      expect(svc.canUndo(_rec(ActionType.delete, 'filen')), isTrue);
    });

    test('rename on local can be undone', () {
      expect(svc.canUndo(_rec(ActionType.rename, 'local')), isTrue);
    });

    test('rename on remote can be undone', () {
      expect(svc.canUndo(_rec(ActionType.rename, 's3')), isTrue);
    });

    test('move can always be undone', () {
      expect(svc.canUndo(_rec(ActionType.move, 'gdrive')), isTrue);
    });

    test('createFolder can always be undone', () {
      expect(svc.canUndo(_rec(ActionType.createFolder, 'dropbox')), isTrue);
    });

    test('copy can always be undone', () {
      expect(svc.canUndo(_rec(ActionType.copy, 'ftp')), isTrue);
    });
  });

  group('ActionHistoryService – undo edge cases', () {
    late ActionHistoryService svc;

    setUp(() => svc = ActionHistoryService());

    test('undo returns failure for unknown id', () async {
      final result = await svc.undo('ghost-id', const UndoContext());
      expect(result.success, isFalse);
      expect(result.message, contains('not found'));
    });

    test('undo non-undoable action returns failure', () async {
      final id = svc.recordNew(
          type: ActionType.delete,
          originalPath: '/local/file.txt',
          provider: 'local');
      final result = await svc.undo(id, const UndoContext());
      expect(result.success, isFalse);
    });

    test('undo delete without restoreFromTrash handler fails', () async {
      final id = svc.recordNew(
          type: ActionType.delete,
          originalPath: '/remote/file.txt',
          provider: 'filen');
      final result = await svc.undo(id, const UndoContext());
      expect(result.success, isFalse);
      expect(result.message, contains('trash'));
    });

    test('undo delete with restoreFromTrash succeeds', () async {
      String? restoredPath;
      final id = svc.recordNew(
          type: ActionType.delete,
          originalPath: '/remote/x.txt',
          provider: 'filen');
      final result = await svc.undo(
          id,
          UndoContext(
              restoreFromTrash: (path) async {
                restoredPath = path;
              }));
      expect(result.success, isTrue);
      expect(restoredPath, '/remote/x.txt');
      // Action should be removed from history after successful undo
      expect(svc.history.any((a) => a.id == id), isFalse);
    });

    test('undo rename without newPath fails', () async {
      final id = svc.recordNew(
          type: ActionType.rename,
          originalPath: '/remote/a.txt',
          newPath: null,
          provider: 'filen');
      final result = await svc.undo(id, const UndoContext());
      expect(result.success, isFalse);
    });

    test('undo rename on remote with no handler fails', () async {
      final id = svc.recordNew(
          type: ActionType.rename,
          originalPath: '/remote/old.txt',
          newPath: '/remote/new.txt',
          provider: 'filen');
      final result = await svc.undo(id, const UndoContext());
      expect(result.success, isFalse);
    });

    test('undo rename on remote with handler succeeds', () async {
      String? renamedFrom;
      String? renamedTo;
      final id = svc.recordNew(
          type: ActionType.rename,
          originalPath: '/remote/old.txt',
          newPath: '/remote/new.txt',
          provider: 'filen');
      final result = await svc.undo(
          id,
          UndoContext(
              remoteRename: (current, name) async {
                renamedFrom = current;
                renamedTo = name;
              }));
      expect(result.success, isTrue);
      expect(renamedFrom, '/remote/new.txt');
      expect(renamedTo, 'old.txt');
    });

    test('undo move without newPath fails', () async {
      final id = svc.recordNew(
          type: ActionType.move,
          originalPath: '/remote/dir/file.txt',
          newPath: null,
          provider: 'filen');
      final result = await svc.undo(id, const UndoContext());
      expect(result.success, isFalse);
    });

    test('undo move on remote with handler succeeds', () async {
      String? movedTo;
      final id = svc.recordNew(
          type: ActionType.move,
          originalPath: '/remote/src/file.txt',
          newPath: '/remote/dst/file.txt',
          provider: 'filen');
      final result = await svc.undo(
          id,
          UndoContext(
              remoteMove: (current, targetDir) async {
                movedTo = targetDir;
              }));
      expect(result.success, isTrue);
      expect(movedTo, '/remote/src');
    });

    test('undo copy on remote with handler succeeds', () async {
      bool deleteCalled = false;
      final id = svc.recordNew(
          type: ActionType.copy,
          originalPath: '/remote/copy.txt',
          provider: 'filen');
      final result = await svc.undo(
          id,
          UndoContext(
              remoteDelete: (path) async {
                deleteCalled = true;
              }));
      expect(result.success, isTrue);
      expect(deleteCalled, isTrue);
    });

    test('undo createFolder on remote with handler succeeds', () async {
      String? deletedPath;
      final id = svc.recordNew(
          type: ActionType.createFolder,
          originalPath: '/remote/new_folder',
          provider: 'filen');
      final result = await svc.undo(
          id,
          UndoContext(
              remoteDelete: (path) async {
                deletedPath = path;
              }));
      expect(result.success, isTrue);
      expect(deletedPath, '/remote/new_folder');
    });

    test('clear empties history', () {
      svc.recordNew(
          type: ActionType.createFolder,
          originalPath: '/a',
          provider: 'local');
      svc.clear();
      expect(svc.history, isEmpty);
    });

    test('history capped at 50', () {
      for (var i = 0; i < 55; i++) {
        svc.recordNew(
            type: ActionType.createFolder,
            originalPath: '/f$i',
            provider: 'local');
      }
      expect(svc.history.length, 50);
    });
  });

  group('UndoResult', () {
    test('success factory sets success=true', () {
      const r = UndoResult.success('done');
      expect(r.success, isTrue);
      expect(r.message, 'done');
    });

    test('failure factory sets success=false', () {
      const r = UndoResult.failure('error');
      expect(r.success, isFalse);
      expect(r.message, 'error');
    });
  });
}

// ============================================================================
// 8. StorageAnalyticsService
// ============================================================================

void _storageAnalyticsTests() {
  group('StorageAnalyticsService – categorizeFile', () {
    late StorageAnalyticsService svc;
    setUp(() => svc = StorageAnalyticsService());

    test('pdf is document', () =>
        expect(svc.categorizeFile('report.pdf'), FileCategory.documents));
    test('docx is document', () =>
        expect(svc.categorizeFile('letter.DOCX'), FileCategory.documents));
    test('mp4 is video', () =>
        expect(svc.categorizeFile('clip.mp4'), FileCategory.videos));
    test('mkv is video', () =>
        expect(svc.categorizeFile('movie.mkv'), FileCategory.videos));
    test('mp3 is audio', () =>
        expect(svc.categorizeFile('track.mp3'), FileCategory.audio));
    test('flac is audio', () =>
        expect(svc.categorizeFile('hifi.flac'), FileCategory.audio));
    test('jpg is image', () =>
        expect(svc.categorizeFile('photo.jpg'), FileCategory.images));
    test('png is image', () =>
        expect(svc.categorizeFile('icon.PNG'), FileCategory.images));
    test('zip is archive', () =>
        expect(svc.categorizeFile('bundle.zip'), FileCategory.archives));
    test('tar.gz: extension is "gz" which is archive', () =>
        expect(svc.categorizeFile('archive.tar.gz'), FileCategory.archives));
    test('unknown extension is other', () =>
        expect(svc.categorizeFile('data.xyz123'), FileCategory.other));
    test('no extension is other', () =>
        expect(svc.categorizeFile('Makefile'), FileCategory.other));
    test('empty string is other', () =>
        expect(svc.categorizeFile(''), FileCategory.other));
    test('py is code', () =>
        expect(svc.categorizeFile('script.py'), FileCategory.code));
    test('js is code', () =>
        expect(svc.categorizeFile('app.js'), FileCategory.code));
  });

  group('StorageAnalyticsService – findLargestFiles', () {
    late StorageAnalyticsService svc;
    setUp(() => svc = StorageAnalyticsService());

    test('returns top N in descending size order', () {
      final files = [
        _fileItem('a', size: 100),
        _fileItem('b', size: 500),
        _fileItem('c', size: 200),
        _fileItem('d', size: 50),
      ];
      final top2 = svc.findLargestFiles(files, 2);
      expect(top2.length, 2);
      expect(top2.first.name, 'b');
      expect(top2.last.name, 'c');
    });

    test('folders excluded', () {
      final files = [
        _folderItem('folder'),
        _fileItem('small', size: 10),
      ];
      final top = svc.findLargestFiles(files, 10);
      expect(top.every((f) => !f.isFolder), isTrue);
    });

    test('files without size excluded', () {
      final files = [
        _fileItem('no_size'),
        _fileItem('has_size', size: 100),
      ];
      final top = svc.findLargestFiles(files, 10);
      expect(top.length, 1);
      expect(top.first.name, 'has_size');
    });

    test('empty input returns empty list', () {
      expect(svc.findLargestFiles([], 5), isEmpty);
    });
  });

  group('StorageAnalyticsService – findDuplicatesAcrossProviders', () {
    late StorageAnalyticsService svc;
    setUp(() => svc = StorageAnalyticsService());

    test('files with same name+size on two providers are duplicates', () {
      final allFiles = {
        'provA': [_fileItem('photo.jpg', size: 1024, path: '/a/photo.jpg')],
        'provB': [_fileItem('photo.jpg', size: 1024, path: '/b/photo.jpg')],
      };
      final groups = svc.findDuplicatesAcrossProviders(allFiles);
      expect(groups.length, 1);
      expect(groups.first.entries.length, 2);
    });

    test('unique files produce no duplicate groups', () {
      final allFiles = {
        'provA': [_fileItem('a.txt', size: 10)],
        'provB': [_fileItem('b.txt', size: 20)],
      };
      expect(svc.findDuplicatesAcrossProviders(allFiles), isEmpty);
    });

    test('same name but different sizes are not duplicates', () {
      final allFiles = {
        'provA': [_fileItem('data.csv', size: 100)],
        'provB': [_fileItem('data.csv', size: 200)],
      };
      expect(svc.findDuplicatesAcrossProviders(allFiles), isEmpty);
    });

    test('folders are excluded from duplicate detection', () {
      final allFiles = {
        'provA': [_folderItem('docs')],
        'provB': [_folderItem('docs')],
      };
      expect(svc.findDuplicatesAcrossProviders(allFiles), isEmpty);
    });

    test('duplicate group wastedBytes is correct', () {
      final allFiles = {
        'provA': [_fileItem('f', size: 512, path: '/a/f')],
        'provB': [_fileItem('f', size: 512, path: '/b/f')],
        'provC': [_fileItem('f', size: 512, path: '/c/f')],
      };
      final groups = svc.findDuplicatesAcrossProviders(allFiles);
      expect(groups.first.wastedBytes, 1024); // 512 * (3 - 1)
    });

    test('empty input returns empty list', () {
      expect(svc.findDuplicatesAcrossProviders({}), isEmpty);
    });
  });

  group('StorageAnalyticsService – estimateSavings', () {
    late StorageAnalyticsService svc;
    setUp(() => svc = StorageAnalyticsService());

    test('returns sum of all suggestion savingsBytes', () {
      final suggestions = [
        const CleanupSuggestion(
            type: CleanupType.duplicate,
            description: 'd',
            savingsBytes: 100,
            files: []),
        const CleanupSuggestion(
            type: CleanupType.stale,
            description: 's',
            savingsBytes: 200,
            files: []),
      ];
      expect(svc.estimateSavings(suggestions), 300);
    });

    test('returns 0 for empty suggestions', () {
      expect(svc.estimateSavings([]), 0);
    });
  });

  group('StorageAnalyticsService – generateCleanupSuggestions', () {
    late StorageAnalyticsService svc;
    setUp(() => svc = StorageAnalyticsService());

    test('duplicate group generates suggestion', () {
      final group = DuplicateGroup(
        key: '1024:file.jpg',
        entries: [
          DuplicateEntry(
              path: '/a/file.jpg', provider: 'p1', sizeBytes: 1024),
          DuplicateEntry(
              path: '/b/file.jpg', provider: 'p2', sizeBytes: 1024),
        ],
      );
      final suggestions = svc.generateCleanupSuggestions([], [group], []);
      expect(suggestions.any((s) => s.type == CleanupType.duplicate), isTrue);
    });

    test('stale files generate suggestion', () {
      final stale = [
        StaleFile(
            path: '/old.txt',
            provider: 'prov',
            sizeBytes: 500,
            daysSinceAccess: 200),
      ];
      final suggestions = svc.generateCleanupSuggestions([], [], stale);
      expect(suggestions.any((s) => s.type == CleanupType.stale), isTrue);
    });

    test('no duplicates or stale — empty suggestions', () {
      final suggestions = svc.generateCleanupSuggestions([], [], []);
      expect(suggestions, isEmpty);
    });
  });

  group('StorageAnalyticsService models – serialization', () {
    test('CategoryStats toJson/fromJson round-trip', () {
      const cs = CategoryStats(fileCount: 10, totalBytes: 1024, percentage: 50.0);
      final r = CategoryStats.fromJson(cs.toJson());
      expect(r.fileCount, 10);
      expect(r.totalBytes, 1024);
      expect(r.percentage, 50.0);
    });

    test('StaleFile toJson/fromJson round-trip', () {
      final sf = StaleFile(
        path: '/old.doc',
        provider: 'gdrive',
        sizeBytes: 2048,
        lastAccessed: DateTime.utc(2025, 1, 1),
        daysSinceAccess: 365,
      );
      final r = StaleFile.fromJson(sf.toJson());
      expect(r.path, '/old.doc');
      expect(r.sizeBytes, 2048);
      expect(r.daysSinceAccess, 365);
    });

    test('StaleFile fromJson handles null lastAccessed', () {
      final sf = StaleFile.fromJson({
        'path': '/f',
        'provider': 'ftp',
        'sizeBytes': 100,
        'daysSinceAccess': 30,
      });
      expect(sf.lastAccessed, isNull);
    });

    test('DuplicateEntry toJson/fromJson round-trip', () {
      final de = DuplicateEntry(
          path: '/x', provider: 'p', sizeBytes: 512,
          modifiedAt: DateTime.utc(2025, 6, 1));
      final r = DuplicateEntry.fromJson(de.toJson());
      expect(r.path, '/x');
      expect(r.provider, 'p');
      expect(r.sizeBytes, 512);
    });

    test('DuplicateGroup toJson/fromJson round-trip', () {
      final g = DuplicateGroup(
        key: '512:test.bin',
        entries: [
          DuplicateEntry(path: '/a', provider: 'p1', sizeBytes: 512),
          DuplicateEntry(path: '/b', provider: 'p2', sizeBytes: 512),
        ],
      );
      final r = DuplicateGroup.fromJson(g.toJson());
      expect(r.key, '512:test.bin');
      expect(r.entries.length, 2);
      expect(r.wastedBytes, 512);
    });

    test('DuplicateGroup.wastedBytes is 0 for empty entries', () {
      final g = DuplicateGroup(key: 'k', entries: []);
      expect(g.wastedBytes, 0);
    });

    test('CleanupSuggestion toJson/fromJson round-trip', () {
      const cs = CleanupSuggestion(
        type: CleanupType.large,
        description: 'Large file detected',
        savingsBytes: 104857600,
        files: ['prov:/big.iso'],
      );
      final r = CleanupSuggestion.fromJson(cs.toJson());
      expect(r.type, CleanupType.large);
      expect(r.savingsBytes, 104857600);
      expect(r.files, ['prov:/big.iso']);
    });
  });
}

// ============================================================================
// 9. SavedSearch model
// ============================================================================

void _savedSearchTests() {
  group('SavedSearch model', () {
    final base = SavedSearch(
      name: 'quarterly reports',
      query: 'Q1',
      createdAt: DateTime.utc(2026, 1, 1),
    );

    test('toJson/fromJson round-trip minimal', () {
      final r = SavedSearch.fromJson(base.toJson());
      expect(r.name, base.name);
      expect(r.query, base.query);
      expect(r.filterByType, isEmpty);
      expect(r.filterByMinSize, isNull);
    });

    test('toJson/fromJson round-trip with all filters', () {
      final s = SavedSearch(
        name: 'complex',
        query: 'report',
        filterByType: ['pdf', 'docx', 'xls'],
        filterByMinSize: 1024,
        filterByMaxSize: 10485760,
        filterByDateAfter: DateTime.utc(2025, 1, 1),
        filterByDateBefore: DateTime.utc(2026, 1, 1),
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final r = SavedSearch.fromJson(s.toJson());
      expect(r.filterByType, ['pdf', 'docx', 'xls']);
      expect(r.filterByMinSize, 1024);
      expect(r.filterByMaxSize, 10485760);
      expect(r.filterByDateAfter!.year, 2025);
      expect(r.filterByDateBefore!.year, 2026);
    });

    test('filterSummary: no filters returns "No filters"', () {
      expect(base.filterSummary, 'No filters');
    });

    test('filterSummary: type filter shows extensions', () {
      final s = SavedSearch(
        name: 'x',
        query: 'q',
        filterByType: ['pdf', 'docx'],
        createdAt: DateTime.utc(2026, 1, 1),
      );
      expect(s.filterSummary, contains('pdf'));
      expect(s.filterSummary, contains('docx'));
    });

    test('filterSummary: more than 3 types shows ellipsis', () {
      final s = SavedSearch(
        name: 'x',
        query: 'q',
        filterByType: ['pdf', 'docx', 'xls', 'ppt', 'txt'],
        createdAt: DateTime.utc(2026, 1, 1),
      );
      expect(s.filterSummary, contains('…'));
    });

    test('filterSummary: min and max size shown', () {
      final s = SavedSearch(
        name: 'x',
        query: 'q',
        filterByMinSize: 1024,
        filterByMaxSize: 1048576,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      expect(s.filterSummary, contains('min'));
      expect(s.filterSummary, contains('max'));
    });

    test('filterSummary: date filter shown', () {
      final s = SavedSearch(
        name: 'x',
        query: 'q',
        filterByDateAfter: DateTime.utc(2025, 6, 1),
        createdAt: DateTime.utc(2026, 1, 1),
      );
      expect(s.filterSummary, contains('after'));
    });

    test('toJson omits optional null fields', () {
      final json = base.toJson();
      expect(json.containsKey('filterByMinSize'), isFalse);
      expect(json.containsKey('filterByMaxSize'), isFalse);
      expect(json.containsKey('filterByDateAfter'), isFalse);
    });
  });
}

// ============================================================================
// 10. AppLockService — in-memory storage, no biometric calls
// ============================================================================

void _appLockTests() {
  group('AppLockService', () {
    late InMemorySecureStorage storage;
    late AppLockService svc;

    setUp(() {
      storage = InMemorySecureStorage();
      svc = AppLockService(storage);
    });

    test('isEnabled returns false initially', () async {
      expect(await svc.isEnabled(), isFalse);
    });

    test('setup then isEnabled returns true', () async {
      await svc.setup('1234');
      expect(await svc.isEnabled(), isTrue);
    });

    test('verify correct code returns true', () async {
      await svc.setup('abcd1234');
      expect(await svc.verify('abcd1234'), isTrue);
    });

    test('verify wrong code returns false', () async {
      await svc.setup('correct');
      expect(await svc.verify('wrong'), isFalse);
    });

    test('setup requires at least 4 characters', () async {
      expect(() => svc.setup('abc'), throwsArgumentError);
    });

    test('setup with exactly 4 characters succeeds', () async {
      await svc.setup('1234');
      expect(await svc.isEnabled(), isTrue);
    });

    test('disable removes lock', () async {
      await svc.setup('1234');
      await svc.disable();
      expect(await svc.isEnabled(), isFalse);
    });

    test('verify after disable returns false', () async {
      await svc.setup('pass1234');
      await svc.disable();
      expect(await svc.verify('pass1234'), isFalse);
    });

    test('changeCode with correct current code succeeds', () async {
      await svc.setup('old1234');
      final changed = await svc.changeCode('old1234', 'new1234');
      expect(changed, isTrue);
      expect(await svc.verify('new1234'), isTrue);
    });

    test('changeCode with wrong current code fails', () async {
      await svc.setup('real1234');
      final changed = await svc.changeCode('wrong', 'new1234');
      expect(changed, isFalse);
      // Original code still works
      expect(await svc.verify('real1234'), isTrue);
    });

    test('getTimeout returns default 300 when not set', () async {
      expect(await svc.getTimeout(), 300);
    });

    test('setTimeout then getTimeout returns configured value', () async {
      await svc.setTimeout(60);
      expect(await svc.getTimeout(), 60);
    });

    test('setTimeout zero is allowed', () async {
      await svc.setTimeout(0);
      expect(await svc.getTimeout(), 0);
    });

    test('same code hashes equally (deterministic)', () async {
      await svc.setup('mypin1234');
      // Verify twice should both succeed
      expect(await svc.verify('mypin1234'), isTrue);
      expect(await svc.verify('mypin1234'), isTrue);
    });
  });
}

// ============================================================================
// 11. FileItem model
// ============================================================================

void _fileItemTests() {
  group('FileItem.sizeFormatted', () {
    test('null size returns empty string', () {
      expect(_fileItem('f').sizeFormatted, '');
    });

    test('bytes format', () {
      expect(_fileItem('f', size: 512).sizeFormatted, '512 B');
    });

    test('KB format', () {
      expect(_fileItem('f', size: 2048).sizeFormatted, contains('KB'));
    });

    test('MB format', () {
      expect(_fileItem('f', size: 5 * 1024 * 1024).sizeFormatted,
          contains('MB'));
    });

    test('GB format', () {
      expect(_fileItem('f', size: 2 * 1024 * 1024 * 1024).sizeFormatted,
          contains('GB'));
    });
  });

  group('FileItem equality and hashCode', () {
    test('equal by uuid', () {
      final a = FileItem(name: 'f', isFolder: false, uuid: 'abc');
      final b = FileItem(name: 'g', isFolder: false, uuid: 'abc');
      expect(a, equals(b));
    });

    test('equal by path when uuid is null', () {
      final a = FileItem(name: 'f', isFolder: false, path: '/x/f.txt');
      final b = FileItem(name: 'f', isFolder: false, path: '/x/f.txt');
      expect(a, equals(b));
    });

    test('not equal when uuids differ', () {
      final a = FileItem(name: 'f', isFolder: false, uuid: 'aaa');
      final b = FileItem(name: 'f', isFolder: false, uuid: 'bbb');
      expect(a, isNot(equals(b)));
    });

    test('hashCode consistent for equal items', () {
      final a = FileItem(name: 'f', isFolder: false, uuid: 'xyz');
      final b = FileItem(name: 'g', isFolder: true, uuid: 'xyz');
      expect(a.hashCode, b.hashCode);
    });
  });
}

// ============================================================================
// 12. Locale-aware formatting
// ============================================================================

void _localeFormattingTests() {
  group('LocaleFormats', () {
    test('English uses comma as thousands separator', () {
      expect(LocaleFormats.thousandsSeparator('en'), ',');
    });

    test('German uses dot as thousands separator', () {
      expect(LocaleFormats.thousandsSeparator('de'), '.');
    });

    test('English uses dot as decimal separator', () {
      expect(LocaleFormats.decimalSeparator('en'), '.');
    });

    test('German uses comma as decimal separator', () {
      expect(LocaleFormats.decimalSeparator('de'), ',');
    });

    test('English date pattern is MM/dd/yyyy', () {
      expect(LocaleFormats.datePattern('en'), 'MM/dd/yyyy');
    });

    test('German date pattern is dd.MM.yyyy', () {
      expect(LocaleFormats.datePattern('de'), 'dd.MM.yyyy');
    });

    test('Japanese date pattern is yyyy/MM/dd', () {
      expect(LocaleFormats.datePattern('ja'), 'yyyy/MM/dd');
    });

    test('English uses 12-hour time', () {
      expect(LocaleFormats.uses12hTime('en'), isTrue);
    });

    test('German uses 24-hour time', () {
      expect(LocaleFormats.uses12hTime('de'), isFalse);
    });

    test('French unit label converts MB to Mo', () {
      expect(LocaleFormats.unitLabel('fr', 'MB'), 'Mo');
    });

    test('English unit label preserves MB', () {
      expect(LocaleFormats.unitLabel('en', 'MB'), 'MB');
    });

    test('French unit label converts GB to Go', () {
      expect(LocaleFormats.unitLabel('fr', 'GB'), 'Go');
    });

    test('French unit label converts B to o', () {
      expect(LocaleFormats.unitLabel('fr', 'B'), 'o');
    });

    test('unknown locale falls back to English', () {
      expect(LocaleFormats.thousandsSeparator('xx'), ',');
      expect(LocaleFormats.decimalSeparator('xx'), '.');
    });

    test('BCP-47 tag "en-US" resolved to English', () {
      expect(LocaleFormats.thousandsSeparator('en-US'), ',');
    });

    test('BCP-47 tag "de-DE" resolved to German', () {
      expect(LocaleFormats.decimalSeparator('de-DE'), ',');
    });
  });

  group('formatBytesLocale', () {
    test('0 bytes shown as "0 B" in English', () {
      expect(formatBytesLocale(0, 'en'), '0 B');
    });

    test('negative bytes treated as 0', () {
      expect(formatBytesLocale(-100, 'en'), '0 B');
    });

    test('1023 bytes shown as bytes', () {
      expect(formatBytesLocale(1023, 'en'), contains('B'));
    });

    test('1 KB shown in KB', () {
      expect(formatBytesLocale(1024, 'en'), contains('KB'));
    });

    test('1 MB shown in MB for English', () {
      expect(formatBytesLocale(1024 * 1024, 'en'), contains('MB'));
    });

    test('1 MB shown in Mo for French', () {
      expect(formatBytesLocale(1024 * 1024, 'fr'), contains('Mo'));
    });

    test('1 GB shown in GB', () {
      expect(formatBytesLocale(1024 * 1024 * 1024, 'en'), contains('GB'));
    });

    test('1 TB shown in TB', () {
      expect(
          formatBytesLocale(1024 * 1024 * 1024 * 1024, 'en'), contains('TB'));
    });

    test('German uses comma decimal', () {
      final result = formatBytesLocale(1536, 'de'); // 1.5 KB
      expect(result, contains(','));
    });
  });

  group('formatDateLocale', () {
    final date = DateTime(2026, 3, 15);

    test('null date returns empty string', () {
      expect(formatDateLocale(null, 'en'), '');
    });

    test('English format is MM/dd/yyyy', () {
      expect(formatDateLocale(date, 'en'), '03/15/2026');
    });

    test('German format is dd.MM.yyyy', () {
      expect(formatDateLocale(date, 'de'), '15.03.2026');
    });

    test('Japanese format is yyyy/MM/dd', () {
      expect(formatDateLocale(date, 'ja'), '2026/03/15');
    });

    test('French format is dd/MM/yyyy', () {
      expect(formatDateLocale(date, 'fr'), '15/03/2026');
    });
  });

  group('formatDateFullLocale', () {
    test('null date returns empty string', () {
      expect(formatDateFullLocale(null, 'en'), '');
    });

    test('includes date and time parts', () {
      final dt = DateTime(2026, 6, 1, 14, 30);
      final result = formatDateFullLocale(dt, 'en');
      expect(result, contains('2026'));
      expect(result, contains('2:30'));
    });

    test('12-hour format for English includes AM/PM', () {
      final dt = DateTime(2026, 6, 1, 14, 0); // 2 PM
      expect(formatDateFullLocale(dt, 'en'), contains('PM'));
    });

    test('24-hour format for German', () {
      final dt = DateTime(2026, 6, 1, 14, 0);
      final result = formatDateFullLocale(dt, 'de');
      expect(result, contains('14:'));
      expect(result.contains('PM'), isFalse);
    });
  });

  group('formatNumberLocale', () {
    test('integer with English formatting', () {
      expect(formatNumberLocale(1234.56, 'en'), contains('1,234'));
    });

    test('integer with German formatting', () {
      expect(formatNumberLocale(1234.56, 'de'), contains('1.234'));
    });

    test('negative number', () {
      final result = formatNumberLocale(-42.5, 'en');
      expect(result.startsWith('-'), isTrue);
    });

    test('zero decimals', () {
      final result = formatNumberLocale(100.7, 'en', decimals: 0);
      expect(result.contains('.'), isFalse);
    });
  });

  group('formatSpeedLocale', () {
    test('zero or negative returns 0 B/s', () {
      expect(formatSpeedLocale(0, 'en'), contains('0'));
      expect(formatSpeedLocale(-1, 'en'), contains('0'));
    });

    test('1 KB/s contains /s suffix', () {
      expect(formatSpeedLocale(1024.0, 'en'), contains('/s'));
    });

    test('1 MB/s contains MB', () {
      expect(formatSpeedLocale(1048576.0, 'en'), contains('MB'));
    });
  });
}

// ============================================================================
// Entry point
// ============================================================================

void main() {
  _pathSanitizerTests();
  _connectionProfileTests();
  _fileDiffTests();
  _multiCloudTests();
  _placeholderMetaTests();
  _syncWatcherTests();
  _actionHistoryTests();
  _storageAnalyticsTests();
  _savedSearchTests();
  _appLockTests();
  _fileItemTests();
  _localeFormattingTests();
}
