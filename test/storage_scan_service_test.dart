import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scanner = StorageScanService();

  test('sums nested files, including hidden and empty files, without reading contents', () async {
    final source = _MetadataBackend({
      '/data': [
        _folder('/data/sub'),
        _file('/data/.hidden', 4),
        _file('/data/empty', 0),
      ],
      '/data/sub': [
        _file('/data/sub/movie.mp4', 12),
        _file('/data/sub/photo.jpg', 8),
      ],
    });
    final result = await scanner.scan(source, '/data');

    expect(result.isComplete, isTrue);
    expect(result.root.bytes, 24);
    expect(result.root.fileCount, 4);
    expect(result.root.folderCount, 1);
    expect(result.root.children.first.name, 'sub');
    expect(result.root.children.first.bytes, 20);
    expect(result.issues, isEmpty);
    expect(source.contentReads, 0);
    expect(source.mutations, 0);
    expect(result.completedAt.isBefore(result.startedAt), isFalse);
  });

  test('an empty directory is complete with zero bytes', () async {
    final result = await scanner.scan(
      _MetadataBackend({'/empty': []}),
      '/empty',
    );
    expect(result.isComplete, isTrue);
    expect(result.root.children, isEmpty);
    expect(result.root.bytes, 0);
    expect(result.root.fileCount, 0);
    expect(result.root.folderCount, 0);
  });

  test(
    'unknown, negative and unrepresentable sizes remain visibly unknown',
    () async {
      final source = _MetadataBackend({
        '/data': [
          _file('/data/known', 7),
          _file('/data/unknown', null),
          _file('/data/negative', -1),
          _file('/data/too-large', StorageScanService.maxReportedBytes + 1),
        ],
      });
      final result = await scanner.scan(source, '/data');
      expect(result.root.bytes, 7);
      expect(result.root.fileCount, 4);
      expect(result.root.unknownSizeCount, 3);
      expect(result.isComplete, isFalse);
      expect(source.contentReads, 0);
    },
  );

  test(
    'counts and skips file and directory symbolic links without following them',
    () async {
      final source = _MetadataBackend({
        '/data': [
          _file('/data/regular', 3),
          FileItem(
            name: 'cycle',
            path: '/data/cycle',
            isFolder: true,
            isSymlink: true,
          ),
          FileItem(
            name: 'alias',
            path: '/data/alias',
            isFolder: false,
            isSymlink: true,
            size: 500,
          ),
        ],
      });
      final result = await scanner.scan(source, '/data');
      expect(result.isComplete, isTrue);
      expect(result.root.bytes, 3);
      expect(result.root.fileCount, 1);
      expect(result.root.folderCount, 0);
      expect(result.root.skippedLinkCount, 2);
      expect(source.listed, ['/data']);
      expect(source.inspected, ['/data']);
    },
  );

  test('refuses a symbolic-link root', () async {
    final source = _MetadataBackend({'/link': []})
      ..statOverrides['/link'] = FileItem(
        name: 'link',
        path: '/link',
        isFolder: true,
        isSymlink: true,
      );
    final result = await scanner.scan(source, '/link');
    expect(result.isComplete, isFalse);
    expect(result.issues.single.code, StorageScanIssueCode.rootUnavailable);
    expect(source.listed, isEmpty);
  });

  test('rechecks link-capable folders immediately before descending', () async {
    final source =
        _MetadataBackend({
            '/data': [_folder('/data/changed')],
            '/data/changed': [_file('/data/changed/outside', 100)],
          })
          ..statOverrides['/data/changed'] = FileItem(
            name: 'changed',
            path: '/data/changed',
            isFolder: true,
            isSymlink: true,
          );
    final result = await scanner.scan(source, '/data');
    expect(result.root.bytes, 0);
    expect(result.isComplete, isFalse);
    expect(result.issues.single.path, '/data/changed');
    expect(source.listed, ['/data']);
  });

  test('retains readable siblings when a directory is denied', () async {
    final source = _MetadataBackend({
      '/data': [_folder('/data/good'), _folder('/data/denied')],
      '/data/good': [_file('/data/good/keep.txt', 19)],
    });
    final result = await scanner.scan(source, '/data');
    expect(result.root.bytes, 19);
    expect(result.root.fileCount, 1);
    expect(result.root.folderCount, 2);
    expect(result.isComplete, isFalse);
    expect(result.issues.single.code, StorageScanIssueCode.unreadableDirectory);
    expect(result.issues.single.path, '/data/denied');
    expect(result.root.children.first.isComplete, isTrue);
  });

  test('stops on cancellation and retains previously counted files', () async {
    final source = _MetadataBackend({
      '/data': [
        _file('/data/first', 7),
        _file('/data/second', 8),
        _folder('/data/sub'),
      ],
      '/data/sub': [_file('/data/sub/later', 100)],
    });
    var cancelled = false;
    final result = await scanner.scan(
      source,
      '/data',
      isCancelled: () => cancelled,
      progressInterval: Duration.zero,
      onProgress: (progress) {
        if (progress.files == 1) cancelled = true;
      },
    );
    expect(result.cancelled, isTrue);
    expect(result.root.bytes, 7);
    expect(result.root.fileCount, 1);
    expect(result.isComplete, isFalse);
    expect(source.listed, ['/data']);
  });

  test(
    'cancellation after a pending directory read discards its late entries',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final source =
          _MetadataBackend({
              '/data': [_file('/data/late', 99)],
            })
            ..onList = (_) async {
              entered.complete();
              await release.future;
            };
      var cancelled = false;
      final running = scanner.scan(
        source,
        '/data',
        isCancelled: () => cancelled,
      );
      await entered.future;
      cancelled = true;
      release.complete();
      final result = await running;
      expect(result.cancelled, isTrue);
      expect(result.root.bytes, 0);
      expect(result.root.children, isEmpty);
    },
  );

  test('source identity changes after a read cannot mix accounts', () async {
    final source = _MetadataBackend({
      '/data': [_file('/data/other-account', 999)],
    });
    source.onList = (_) async {
      source.storageIdentity = 'other-account';
    };
    final result = await scanner.scan(source, '/data');
    expect(result.sourceChanged, isTrue);
    expect(result.root.bytes, 0);
    expect(result.root.children, isEmpty);
    expect(result.issues.single.code, StorageScanIssueCode.sourceChanged);
  });

  test(
    'a failed stat after disconnect is reported as a source change',
    () async {
      final source = _MetadataBackend({'/data': []});
      source.onStat = (_) async {
        source.current = false;
        throw StateError('Disconnected');
      };
      final result = await scanner.scan(source, '/data');
      expect(result.sourceChanged, isTrue);
      expect(result.issues.single.code, StorageScanIssueCode.sourceChanged);
      expect(source.listed, isEmpty);
    },
  );

  test('invalid children, ancestor loops and duplicate paths cannot inflate totals', () async {
    final source = _MetadataBackend({
      '/data': [
        _file('/data/ok', 3),
        _file('/data/ok', 300),
        _file('/outside', 100),
        _folder('/data'),
        _file('/data/deeper/unlisted', 100),
        FileItem(
          name: 'escape',
          path: '/data/../escape',
          isFolder: false,
          size: 100,
        ),
        FileItem(name: '..', path: '/', isFolder: true),
      ],
    });
    final result = await scanner.scan(source, '/data');
    expect(result.root.bytes, 3);
    expect(result.root.fileCount, 1);
    expect(result.root.folderCount, 0);
    expect(result.isComplete, isFalse);
    expect(
      result.issues.where(
        (issue) => issue.code == StorageScanIssueCode.duplicateEntry,
      ),
      hasLength(1),
    );
    expect(
      result.issues.where(
        (issue) => issue.code == StorageScanIssueCode.invalidEntry,
      ),
      hasLength(5),
    );
    expect(source.listed, ['/data']);
  });

  test('entry limits retain a bounded and explicitly partial tree', () async {
    final source = _MetadataBackend({
      '/data': [_file('/data/a', 1), _file('/data/b', 2), _file('/data/c', 3)],
    });
    final result = await scanner.scan(source, '/data', maxEntries: 2);
    expect(result.limited, isTrue);
    expect(result.root.bytes, 3);
    expect(result.root.fileCount, 2);
    expect(result.issues.single.code, StorageScanIssueCode.entryLimit);
    expect(result.isComplete, isFalse);
  });

  test(
    'depth limits keep shallow files and expose unscanned folders',
    () async {
      final source = _MetadataBackend({
        '/data': [_file('/data/a', 4), _folder('/data/sub')],
        '/data/sub': [_file('/data/sub/b', 100)],
      });
      final result = await scanner.scan(source, '/data', maxDepth: 0);
      expect(result.limited, isTrue);
      expect(result.root.bytes, 4);
      expect(result.root.folderCount, 1);
      expect(result.issues.single.code, StorageScanIssueCode.depthLimit);
      expect(source.listed, ['/data']);
    },
  );

  test(
    'aggregate byte overflow stops at the exact cross-platform limit',
    () async {
      final source = _MetadataBackend({
        '/data': [
          _file('/data/huge', StorageScanService.maxReportedBytes),
          _file('/data/extra', 1),
        ],
      });
      final result = await scanner.scan(source, '/data');
      expect(result.root.bytes, StorageScanService.maxReportedBytes);
      expect(result.root.unknownSizeCount, 1);
      expect(result.limited, isTrue);
      expect(result.issues.single.code, StorageScanIssueCode.byteLimit);
    },
  );

  test(
    'diagnostics have an independent cap without claiming completeness',
    () async {
      final source = _MetadataBackend({
        '/data': [for (var i = 0; i < 5; i++) _file('/outside-$i', 1)],
      });
      final result = await scanner.scan(source, '/data', maxIssues: 2);
      expect(result.issues, hasLength(2));
      expect(result.suppressedIssueCount, 3);
      expect(result.isComplete, isFalse);
    },
  );

  test(
    'progress is throttled while always publishing initial and final totals',
    () async {
      final source = _MetadataBackend({
        '/data': [for (var i = 0; i < 600; i++) _file('/data/file-$i', 2)],
      });
      final updates = <StorageScanProgress>[];
      final result = await scanner.scan(
        source,
        '/data',
        onProgress: updates.add,
        progressInterval: const Duration(days: 1),
      );
      expect(result.isComplete, isTrue);
      expect(updates, hasLength(2));
      expect(updates.first.files, 0);
      expect(updates.last.files, 600);
      expect(updates.last.bytes, 1200);
    },
  );

  test('uses the backend path convention for Windows folders', () async {
    final source = _MetadataBackend({
      r'C:\data': [
        FileItem(name: 'file', path: r'C:\data\file', isFolder: false, size: 3),
      ],
    }, paths: p.Context(style: p.Style.windows));
    final result = await scanner.scan(source, r'C:\data');
    expect(result.isComplete, isTrue);
    expect(result.root.bytes, 3);
  });

  for (final disconnect in [false, true]) {
    test(
      'a late ${disconnect ? 'account change' : 'cancellation'} during aggregation invalidates the final snapshot',
      () async {
        final source = _MetadataBackend({
          '/data': [for (var i = 0; i < 800; i++) _file('/data/file-$i', 1)],
        });
        var cancelled = false;
        var scheduled = false;
        final result = await scanner.scan(
          source,
          '/data',
          progressInterval: Duration.zero,
          isCancelled: () => cancelled,
          onProgress: (progress) {
            if (progress.files != 800 || scheduled) return;
            scheduled = true;
            // Allow traversal's final yield to finish first, then deliver the
            // signal while a large tree is being converted to its final snapshot.
            unawaited(
              Future<void>.delayed(Duration.zero, () async {
                await Future<void>.delayed(Duration.zero);
                if (disconnect) {
                  source.storageIdentity = 'replacement';
                } else {
                  cancelled = true;
                }
              }),
            );
          },
        );
        expect(result.root.bytes, 800);
        expect(result.root.fileCount, 800);
        expect(result.isComplete, isFalse);
        expect(result.root.isComplete, isFalse);
        expect(result.cancelled, !disconnect);
        expect(result.sourceChanged, disconnect);
        expect(result.root.children.every((child) => child.isComplete), isTrue);
      },
    );
  }

  test('local scan keys preserve case-distinct source entries', () {
    final source = storageScanBackend(
      source: const LocalPanelSource('/data'),
      local: LocalFileService(),
      isCurrent: () => true,
    );
    expect(source.pathKey('/data/A'), isNot(source.pathKey('/data/a')));
  });

  test('native directory scan includes hidden and empty files without changing contents', () async {
    SharedPreferences.setMockInitialValues({});
    final temporary = await Directory.systemTemp.createTemp(
      'crisp-storage-scan-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    // macOS may expose its temporary directory through a /var symlink. Use
    // the real grant path so this tests the scanned tree, not an ancestor alias.
    final root = Directory(await temporary.resolveSymbolicLinks());
    await Directory(p.join(root.path, 'nested', 'empty'))
        .create(recursive: true);
    final originalBytes = <String, List<int>>{
      p.join(root.path, '.hidden'): [1, 2, 3, 4],
      p.join(root.path, 'zero.bin'): [],
      p.join(root.path, 'small.bin'): [10, 20, 30],
      p.join(root.path, 'nested', 'payload.bin'): List<int>.generate(
        17,
        (index) => index,
      ),
    };
    for (final entry in originalBytes.entries) {
      await File(entry.key).writeAsBytes(entry.value);
    }
    // Creating links on Windows can require developer mode or an elevated
    // token. The file/tree integration still runs there without that fixture.
    if (!Platform.isWindows) {
      await Link(p.join(root.path, 'cycle')).create(root.path);
    }

    final backend = storageScanBackend(
      source: LocalPanelSource(root.path),
      local: LocalFileService(),
      isCurrent: () => true,
    );
    final result = await scanner.scan(backend, root.path);
    expect(result.isComplete, isTrue);
    expect(result.issues, isEmpty);
    expect(result.root.bytes, 24);
    expect(result.root.fileCount, 4);
    expect(result.root.folderCount, 2);
    expect(result.root.unknownSizeCount, 0);
    expect(result.root.skippedLinkCount, Platform.isWindows ? 0 : 1);
    expect(result.root.children.any((node) => node.name == '.hidden'), isTrue);
    final zero = result.root.children.singleWhere(
      (node) => node.name == 'zero.bin',
    );
    expect(zero.bytes, 0);
    expect(zero.isComplete, isTrue);
    final nested = result.root.children.singleWhere(
      (node) => node.name == 'nested',
    );
    expect(nested.bytes, 17);
    expect(nested.fileCount, 1);
    expect(nested.folderCount, 1);
    expect(nested.children.map((node) => node.name).toSet(), {
      'payload.bin',
      'empty',
    });
    if (!Platform.isWindows) {
      final cycle = result.root.children.singleWhere(
        (node) => node.name == 'cycle',
      );
      expect(cycle.item.isSymlink, isTrue);
      expect(cycle.children, isEmpty);
      expect(await Link(cycle.path).target(), root.path);
    }
    for (final entry in originalBytes.entries) {
      expect(
        await File(entry.key).readAsBytes(),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('a replaced local folder grant cannot rebind a captured scan', () async {
    final local = _GrantedLocalService();
    final originalGrant = local.grant;
    final source = storageScanBackend(
      source: const LocalPanelSource('/selected'),
      local: local,
      isCurrent: () => true,
    );
    expect(source.isCurrent, isTrue);
    local.grant = Object();
    final result = await scanner.scan(source, '/selected');
    expect(result.sourceChanged, isTrue);
    expect(result.root.bytes, 0);
    expect(source.isCurrent, isFalse);
    local.grant = originalGrant;
    expect(source.isCurrent, isFalse);
  });

  group('cloud metadata adapter', () {
    test(
      'scans an exact case-distinct root without repeatedly listing ancestors',
      () async {
        final client = _CloudMetadataClient({
          '/parent': {
            'files': [],
            'folders': [
              {'name': 'A'},
              {'name': 'a'},
            ],
          },
          '/parent/A': {
            'files': [
              {'name': 'keep', 'size': 4},
            ],
          },
        });
        final source = CloudStorageScanBackend(client, isCurrent: () => true);
        final result = await scanner.scan(source, '/parent/A');
        expect(result.isComplete, isTrue);
        expect(result.root.bytes, 4);
        expect(client.freshReads, ['/parent', '/parent/A']);
      },
    );

    test(
      'virtual bucket-index rows do not scan misleading child prefixes',
      () async {
        final client = _CloudMetadataClient({
          '/': {
            'files': [
              {
                'name': 'bucket',
                'uuid': 'bucket-id',
                'isFolder': true,
                'bucketType': 'allPrivate',
              },
            ],
          },
          '/bucket': {'files': []},
        });
        final result = await scanner.scan(
          CloudStorageScanBackend(client, isCurrent: () => true),
          '/',
        );
        expect(result.isComplete, isFalse);
        expect(result.root.children, isEmpty);
        expect(
          result.issues.single.code,
          StorageScanIssueCode.incompleteListing,
        );
        expect(result.issues.single.message, contains('S3-compatible'));
        expect(client.freshReads, ['/']);
      },
    );

    test(
      'recognizes mixed folders, uses fresh listings and original stored sizes',
      () async {
        final client = _CloudMetadataClient({
          '/': {
            'files': [
              {'name': 'sub', 'isFolder': true, 'size': 10000},
              {'name': 'encrypted.bin', 'size': 12, 'downloadSize': 2},
            ],
          },
          '/sub': {
            'files': [
              {'name': 'file.txt', 'size': '3'},
            ],
            'folders': [],
          },
        });
        final source = CloudStorageScanBackend(client, isCurrent: () => true);
        final result = await scanner.scan(source, '/');
        expect(result.isComplete, isTrue);
        expect(result.root.bytes, 15);
        expect(result.root.fileCount, 2);
        expect(result.root.folderCount, 1);
        expect(client.cachedReads, 0);
        expect(client.freshReads, ['/', '/sub']);
        expect(client.contentReads, 0);
      },
    );

    for (final key in [
      'nextStartFileName',
      'nextFileName',
      'nextMarker',
      'NextMarker',
      'nextPageToken',
      'nextContinuationToken',
      'continuationToken',
      'nextCursor',
      'nextLink',
      '@odata.nextLink',
    ]) {
      test('retains partial entries and flags $key pagination', () async {
        final client = _CloudMetadataClient({
          '/': {
            'files': [
              {'name': 'known', 'size': 3},
            ],
            'folders': [],
            key: 'next-page',
          },
        });
        final result = await scanner.scan(
          CloudStorageScanBackend(client, isCurrent: () => true),
          '/',
        );
        expect(result.root.bytes, 3);
        expect(result.isComplete, isFalse);
        expect(
          result.issues.single.code,
          StorageScanIssueCode.incompleteListing,
        );
      });
    }

    for (final flag in [
      'hasMore',
      'has_more',
      'isTruncated',
      'IsTruncated',
      'truncated',
      'hasNextPage',
    ]) {
      test(
        'flags $flag even when the provider encodes true as a string',
        () async {
          final client = _CloudMetadataClient({
            '/': {'files': [], flag: 'true'},
          });
          final result = await scanner.scan(
            CloudStorageScanBackend(client, isCurrent: () => true),
            '/',
          );
          expect(result.isComplete, isFalse);
          expect(
            result.issues.single.code,
            StorageScanIssueCode.incompleteListing,
          );
        },
      );
    }

    test(
      'does not turn provider failure into an empty complete directory',
      () async {
        final client = _CloudMetadataClient({
          '/': {'files': [], 'folders': [], 'success': false},
        });
        final result = await scanner.scan(
          CloudStorageScanBackend(client, isCurrent: () => true),
          '/',
        );
        expect(result.isComplete, isFalse);
        expect(
          result.issues.single.code,
          StorageScanIssueCode.unreadableDirectory,
        );
      },
    );

    test('bad provider rows and names cannot escape the directory', () async {
      final client = _CloudMetadataClient({
        '/': {
          'files': [
            {'name': '../escape', 'size': 100},
            {'name': 'wrong/name', 'size': 100},
            {'name': '', 'fileType': 'pdf', 'size': 100},
            {'name': 'good', 'size': 4},
            null,
          ],
        },
      });
      final result = await scanner.scan(
        CloudStorageScanBackend(client, isCurrent: () => true),
        '/',
      );
      expect(result.root.bytes, 4);
      expect(result.root.fileCount, 1);
      expect(result.isComplete, isFalse);
      expect(result.issues.single.code, StorageScanIssueCode.invalidEntry);
    });

    test(
      'account changes inside an awaited provider read invalidate its results',
      () async {
        final client = _CloudMetadataClient({
          '/': {
            'files': [
              {'name': 'later', 'size': 42},
            ],
          },
        });
        client.onRead = () => client.account = 'replacement';
        final result = await scanner.scan(
          CloudStorageScanBackend(client, isCurrent: () => true),
          '/',
        );
        expect(result.sourceChanged, isTrue);
        expect(result.root.bytes, 0);
        expect(result.root.children, isEmpty);
      },
    );
  });
}

FileItem _file(String path, int? size) => FileItem(
  name: p.posix.basename(path),
  path: path,
  isFolder: false,
  size: size,
);

FileItem _folder(String path) =>
    FileItem(name: p.posix.basename(path), path: path, isFolder: true);

class _MetadataBackend extends FileOperationBackend {
  _MetadataBackend(this.directories, {p.Context? paths})
    : paths = paths ?? p.posix;
  final Map<String, List<FileItem>> directories;
  final statOverrides = <String, FileItem?>{};
  final listed = <String>[];
  final inspected = <String>[];
  Future<void> Function(String)? onList;
  Future<void> Function(String)? onStat;
  Object storageIdentity = 'original';
  bool current = true;
  int contentReads = 0;
  int mutations = 0;
  @override
  Object get identity => storageIdentity;
  @override
  String get label => 'Fixture';
  @override
  final p.Context paths;
  @override
  bool get isCurrent => current;
  @override
  bool get supportsSymbolicLinks => true;
  @override
  Future<List<FileItem>> list(String path) async {
    listed.add(path);
    await onList?.call(path);
    if (!directories.containsKey(path)) {
      throw StateError('Permission denied: $path');
    }
    return directories[path]!;
  }

  @override
  Future<FileItem?> stat(String path) async {
    inspected.add(path);
    await onStat?.call(path);
    if (statOverrides.containsKey(path)) return statOverrides[path];
    for (final entries in directories.values) {
      for (final file in entries) {
        if (file.path == path) return file;
      }
    }
    return directories.containsKey(path)
        ? FileItem(name: paths.basename(path), path: path, isFolder: true)
        : null;
  }

  @override
  Stream<List<int>> readFile(FileItem file) {
    contentReads++;
    throw StateError('The analyzer must never read file contents.');
  }

  Never _mutation() {
    mutations++;
    throw StateError('The analyzer must never mutate files.');
  }

  @override
  Future<void> createDirectory(String path) async => _mutation();
  @override
  Future<void> deleteEmptyDirectory(String path) async => _mutation();
  @override
  Future<void> deleteFile(FileItem file) async => _mutation();
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => _mutation();
}

class _CloudMetadataClient extends CloudStorageClient
    implements FreshCloudDirectoryReader {
  _CloudMetadataClient(this.directories);
  final Map<String, Map<String, dynamic>> directories;
  final freshReads = <String>[];
  int cachedReads = 0;
  int contentReads = 0;
  String account = 'original';
  void Function()? onRead;
  @override
  bool get isAuthenticated => true;
  @override
  String? get userId => account;
  @override
  String? get bucketId => null;
  @override
  String get rootPath => '/';
  @override
  String get providerName => 'Metadata fixture';
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    cachedReads++;
    throw StateError('Use a fresh directory snapshot.');
  }

  @override
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) async {
    freshReads.add(path);
    onRead?.call();
    return directories[path]!;
  }

  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) {
    contentReads++;
    throw StateError('The analyzer must never download cloud contents.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected provider operation: ${invocation.memberName}',
  );
}

class _GrantedLocalService extends Fake
    implements LocalFileService, LocalFileSourceIdentity {
  Object grant = Object();
  @override
  Object? sourceIdentityForPath(String path) => grant;
}
