import 'dart:async';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const scanner = StorageScanService();

  final cases = <_Case>[
    _Case(
      'nested, hidden, empty and linked entries',
      () => _Source({
        '/data': [
          _folder('/data/sub'),
          _folder('/data/empty'),
          _file('/data/.hidden', 4),
          _file('/data/zero', 0),
          _folder('/data/link', link: true),
          _file('/data/alias', 900, link: true),
        ],
        '/data/sub': [_file('/data/sub/a', 12), _file('/data/sub/b', 8)],
        '/data/empty': [],
      }),
      bytes: 24,
      files: 4,
      folders: 2,
      links: 2,
    ),
    _Case('empty root', () => _Source({'/data': []})),
    _Case(
      'unknown and invalid sizes',
      () => _Source({
        '/data': [
          _file('/data/known', 7),
          _file('/data/unknown', null),
          _file('/data/negative', -1),
          _file('/data/too-big', StorageScanService.maxReportedBytes + 1),
        ],
      }),
      bytes: 7,
      files: 4,
      unknown: 3,
      complete: false,
    ),
    _Case(
      'unreadable child retains siblings',
      () => _Source({
        '/data': [_folder('/data/denied'), _file('/data/a', 9)],
      }),
      bytes: 9,
      files: 1,
      folders: 1,
      complete: false,
    ),
    _Case('missing root', () => _Source({}), complete: false),
    _Case(
      'symbolic link root',
      () =>
          _Source({'/data': []})
            ..statOverrides['/data'] = _folder('/data', link: true),
      complete: false,
    ),
    _Case(
      'directory replaced by link',
      () => _Source({
        '/data': [_folder('/data/sub'), _file('/data/a', 3)],
        '/data/sub': [_file('/data/sub/outside', 500)],
      })..statOverrides['/data/sub'] = _folder('/data/sub', link: true),
      bytes: 3,
      files: 1,
      folders: 1,
      complete: false,
    ),
    _Case(
      'invalid and duplicate rows',
      () => _Source({
        '/data': [
          _file('/data/a', 2),
          _file('/data/a', 200),
          _file('/outside', 900),
          _file('/data/sub/escape', 900),
          FileItem(
            name: 'wrong',
            path: '/data/right',
            isFolder: false,
            size: 900,
          ),
        ],
      }),
      bytes: 2,
      files: 1,
      complete: false,
      maxIssues: 2,
    ),
    _Case(
      'entry limit includes rejected rows',
      () => _Source({
        '/data': [
          _file('/outside', 20),
          _file('/data/a', 2),
          _file('/data/b', 3),
        ],
      }),
      bytes: 2,
      files: 1,
      complete: false,
      maxEntries: 2,
    ),
    _Case(
      'depth limit counts unscanned folders',
      () => _Source({
        '/data': [_file('/data/a', 4), _folder('/data/sub')],
        '/data/sub': [_file('/data/sub/b', 100)],
      }),
      bytes: 4,
      files: 1,
      folders: 1,
      complete: false,
      maxDepth: 0,
    ),
    _Case(
      'aggregate byte bound',
      () => _Source({
        '/data': [
          _file('/data/huge', StorageScanService.maxReportedBytes),
          _file('/data/extra', 1),
          _file('/data/late', 2),
        ],
      }),
      bytes: StorageScanService.maxReportedBytes,
      files: 2,
      unknown: 1,
      complete: false,
    ),
    _Case(
      'partial listing and bounded diagnostics',
      () =>
          _Source({
              '/data': [_file('/data/a', 5)],
            })
            ..listingOverrides['/data'] = StorageScanDirectory(
              entries: [_file('/data/a', 5)],
              isComplete: false,
              issues: [
                for (var i = 0; i < 4; i++)
                  StorageScanIssue(
                    path: '/data',
                    code: StorageScanIssueCode.incompleteListing,
                    message: 'Page $i was unavailable.',
                  ),
              ],
            ),
      bytes: 5,
      files: 1,
      complete: false,
      maxIssues: 2,
    ),
  ];

  for (final scenario in cases) {
    test('summary matches full traversal: ${scenario.name}', () async {
      final fullSource = scenario.source();
      final summarySource = scenario.source();
      final full = await scanner.scan(
        fullSource,
        '/data',
        maxEntries: scenario.maxEntries,
        maxDepth: scenario.maxDepth,
        maxIssues: scenario.maxIssues,
      );
      final updates = <StorageScanProgress>[];
      final summary = await scanner.scanSummary(
        summarySource,
        '/data',
        maxEntries: scenario.maxEntries,
        maxDepth: scenario.maxDepth,
        maxIssues: scenario.maxIssues,
        onProgress: updates.add,
        progressInterval: const Duration(days: 1),
      );
      expect(summary.rootPath, '/data');
      expect(summary.bytes, scenario.bytes);
      expect(summary.fileCount, scenario.files);
      expect(summary.folderCount, scenario.folders);
      expect(summary.unknownSizeCount, scenario.unknown);
      expect(summary.skippedLinkCount, scenario.links);
      expect(summary.isComplete, scenario.complete);
      expect(summary.bytes, full.root.bytes);
      expect(summary.fileCount, full.root.fileCount);
      expect(summary.folderCount, full.root.folderCount);
      expect(summary.unknownSizeCount, full.root.unknownSizeCount);
      expect(summary.skippedLinkCount, full.root.skippedLinkCount);
      expect(summary.isComplete, full.isComplete);
      expect(summary.cancelled, full.cancelled);
      expect(summary.limited, full.limited);
      expect(summary.sourceChanged, full.sourceChanged);
      expect(summary.suppressedIssueCount, full.suppressedIssueCount);
      expect(_issues(summary.issues), _issues(full.issues));
      expect(summarySource.listed, fullSource.listed);
      expect(summarySource.inspected, fullSource.inspected);
      expect(summary.completedAt.isBefore(summary.startedAt), isFalse);
      expect(updates.first.files, 0);
      expect(updates.last.files, summary.fileCount);
      expect(updates.last.folders, summary.folderCount);
      expect(updates.last.bytes, summary.bytes);
      expect(() => summary.issues.clear(), throwsUnsupportedError);
    });
  }

  for (final disconnect in [false, true]) {
    test(
      'summary discards a pending read after ${disconnect ? 'source change' : 'cancellation'}',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        var cancelled = false;
        final source =
            _Source({
                '/data': [_file('/data/kept', 3), _folder('/data/sub')],
                '/data/sub': [_file('/data/sub/late', 900)],
              })
              ..onList = (path) async {
                if (path != '/data/sub') return;
                entered.complete();
                await release.future;
              };
        final pending = scanner.scanSummary(
          source,
          '/data',
          isCancelled: () => cancelled,
        );
        await entered.future;
        if (disconnect) {
          source.identity = 'replacement';
        } else {
          cancelled = true;
        }
        release.complete();
        final result = await pending;
        expect(result.bytes, 3);
        expect(result.fileCount, 1);
        expect(result.folderCount, 1);
        expect(result.isComplete, isFalse);
        expect(result.sourceChanged, disconnect);
        expect(result.cancelled, !disconnect);
      },
    );

    test(
      'summary rechecks after session close for ${disconnect ? 'source change' : 'cancellation'}',
      () async {
        final closing = Completer<void>();
        final release = Completer<void>();
        var cancelled = false;
        final session =
            _Session({
                '/data': [_file('/data/a', 8)],
              })
              ..onClose = () async {
                closing.complete();
                await release.future;
              };
        final source = _SessionSource({'/data': []}, session);
        final pending = scanner.scanSummary(
          source,
          '/data',
          isCancelled: () => cancelled,
        );
        await closing.future;
        if (disconnect) {
          source.identity = 'replacement';
        } else {
          cancelled = true;
        }
        release.complete();
        final result = await pending;
        expect(result.bytes, 8);
        expect(result.fileCount, 1);
        expect(result.isComplete, isFalse);
        expect(result.sourceChanged, disconnect);
        expect(result.cancelled, !disconnect);
        expect(session.closeCount, 1);
      },
    );
  }

  test(
    'summary close failure preserves totals and incomplete status',
    () async {
      final session = _Session({
        '/data': [_file('/data/a', 8)],
      })..onClose = () async => throw StateError('close failed');
      final result = await scanner.scanSummary(
        _SessionSource({'/data': []}, session),
        '/data',
      );
      expect(result.bytes, 8);
      expect(result.isComplete, isFalse);
      expect(result.issues.single.code, StorageScanIssueCode.incompleteListing);
      expect(session.closeCount, 1);
    },
  );

  test(
    'summary cancellation remains responsive for cached empty directories',
    () async {
      var cancelled = false;
      final source =
          _Source({
              '/data': [for (var i = 0; i < 200; i++) _folder('/data/dir-$i')],
              for (var i = 0; i < 200; i++) '/data/dir-$i': [],
            })
            ..onList = (path) async {
              if (path == '/data/dir-199') Timer.run(() => cancelled = true);
            };
      final result = await scanner.scanSummary(
        source,
        '/data',
        isCancelled: () => cancelled,
      );
      expect(result.cancelled, isTrue);
      expect(result.isComplete, isFalse);
      expect(source.listed.length, lessThan(201));
      expect(result.folderCount, 200);
    },
  );

  test(
    'summary uses Windows comparison and does not double-count aliases',
    () async {
      final source = _Source(
        {
          r'C:\data': [
            FileItem(name: 'A', path: r'C:\data\A', isFolder: false, size: 3),
            FileItem(name: 'a', path: r'C:\data\a', isFolder: false, size: 900),
          ],
        },
        paths: p.Context(style: p.Style.windows),
        caseInsensitive: true,
      );
      final result = await scanner.scanSummary(source, r'C:\data');
      expect(result.bytes, 3);
      expect(result.fileCount, 1);
      expect(result.isComplete, isFalse);
      expect(result.issues.single.code, StorageScanIssueCode.duplicateEntry);
    },
  );

  test('summary enforces configuration bounds', () async {
    final source = _Source({'/data': []});
    await expectLater(
      scanner.scanSummary(source, '/data', maxEntries: 0),
      throwsArgumentError,
    );
    await expectLater(
      scanner.scanSummary(source, '/data', maxDepth: -1),
      throwsArgumentError,
    );
    await expectLater(
      scanner.scanSummary(source, '/data', maxIssues: 0),
      throwsArgumentError,
    );
    await expectLater(
      scanner.scanSummary(
        source,
        '/data',
        progressInterval: const Duration(microseconds: -1),
      ),
      throwsArgumentError,
    );
    expect(source.inspected, isEmpty);
    expect(source.listed, isEmpty);
  });
}

List<Object> _issues(List<StorageScanIssue> issues) => [
  for (final issue in issues) [issue.path, issue.code, issue.message],
];

FileItem _file(String path, int? size, {bool link = false}) => FileItem(
  name: p.posix.basename(path),
  path: path,
  isFolder: false,
  size: size,
  isSymlink: link,
);

FileItem _folder(String path, {bool link = false}) => FileItem(
  name: p.posix.basename(path),
  path: path,
  isFolder: true,
  isSymlink: link,
);

class _Case {
  _Case(
    this.name,
    this.source, {
    this.bytes = 0,
    this.files = 0,
    this.folders = 0,
    this.unknown = 0,
    this.links = 0,
    this.complete = true,
    this.maxEntries = 200000,
    this.maxDepth = 200,
    this.maxIssues = 1000,
  });
  final String name;
  final _Source Function() source;
  final int bytes,
      files,
      folders,
      unknown,
      links,
      maxEntries,
      maxDepth,
      maxIssues;
  final bool complete;
}

class _Source implements StorageScanSource, StorageScanDirectoryReader {
  _Source(this.directories, {p.Context? paths, this.caseInsensitive = false})
    : paths = paths ?? p.posix;
  final Map<String, List<FileItem>> directories;
  final statOverrides = <String, FileItem?>{};
  final listingOverrides = <String, StorageScanDirectory>{};
  final listed = <String>[];
  final inspected = <String>[];
  final bool caseInsensitive;
  Future<void> Function(String)? onList;
  @override
  Object identity = 'original';
  @override
  bool isCurrent = true;
  @override
  final p.Context paths;
  @override
  bool get supportsSymbolicLinks => true;
  @override
  String pathKey(String path) => caseInsensitive
      ? paths.normalize(path).toLowerCase()
      : paths.normalize(path);
  @override
  bool samePath(String first, String second) =>
      pathKey(first) == pathKey(second);
  @override
  bool isWithin(String parent, String child) =>
      paths.isWithin(pathKey(parent), pathKey(child));
  @override
  Future<FileItem?> stat(String path) async {
    inspected.add(path);
    if (statOverrides.containsKey(path)) return statOverrides[path];
    for (final entries in directories.values) {
      for (final item in entries) {
        if (item.path == path) return item;
      }
    }
    return directories.containsKey(path)
        ? FileItem(name: paths.basename(path), path: path, isFolder: true)
        : null;
  }

  @override
  Future<List<FileItem>> list(String path) async {
    listed.add(path);
    await onList?.call(path);
    return directories[path] ?? (throw StateError('Permission denied: $path'));
  }

  @override
  Future<StorageScanDirectory> listForStorageScan(String path) async {
    final entries = await list(path);
    return listingOverrides[path] ?? StorageScanDirectory(entries: entries);
  }
}

class _SessionSource extends _Source implements StorageScanSessionFactory {
  _SessionSource(super.directories, this.session);
  final _Session session;
  @override
  Future<StorageScanSession?> openStorageScanSession() async => session;
}

class _Session implements StorageScanSession {
  _Session(this.directories);
  final Map<String, List<FileItem>> directories;
  Future<void> Function()? onClose;
  int closeCount = 0;
  @override
  Future<StorageScanDirectory> listForStorageScan(String path) async =>
      StorageScanDirectory(entries: directories[path]!);
  @override
  Future<void> close() async {
    closeCount++;
    await onClose?.call();
  }
}
