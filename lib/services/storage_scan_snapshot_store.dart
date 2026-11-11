import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/file_item.dart';
import 'file_collection_storage.dart';
import 'file_collection_storage_factory.dart';
import 'storage_scan_service.dart';

/// An inert historical reference. It contains no client, grant, or credentials.
class StorageScanSnapshotSummary {
  const StorageScanSnapshotSummary({
    required this.id,
    required this.storageId,
    required this.sourceLabel,
    required this.rootPath,
    required this.pathStyle,
    required this.savedAt,
    required this.completedAt,
    required this.nodeCount,
    required this.bytes,
    required this.fileCount,
    required this.folderCount,
    required this.isComplete,
  });

  final String id;
  final String storageId;
  final String sourceLabel;
  final String rootPath;
  final String pathStyle;
  final DateTime savedAt;
  final DateTime completedAt;
  final int nodeCount;
  final int bytes;
  final int fileCount;
  final int folderCount;
  final bool isComplete;

  Map<String, Object?> _json() => {
    'id': id,
    'storageId': storageId,
    'sourceLabel': sourceLabel,
    'rootPath': rootPath,
    'pathStyle': pathStyle,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'completedAt': completedAt.toUtc().toIso8601String(),
    'nodes': nodeCount,
    'bytes': bytes.toString(),
    'files': fileCount,
    'folders': folderCount,
    'complete': isComplete,
  };
}

class StorageScanSnapshot {
  const StorageScanSnapshot({required this.summary, required this.result});
  final StorageScanSnapshotSummary summary;
  final StorageScanResult result;
}

/// A save may have published its index, but neither its acknowledgement nor
/// recovery readback established the outcome. Candidate records are retained.
class StorageScanSnapshotCommitUnconfirmed extends StateError {
  StorageScanSnapshotCommitUnconfirmed({
    required this.snapshotId,
    required this.cause,
    required this.recoveryCause,
  }) : super(
         'The saved scan outcome is unknown. '
         'Check saved scan history before retrying.',
       );

  final String snapshotId;
  final Object cause;
  final Object recoveryCause;
}

/// Immutable paged metadata, published only by a small compare-and-swap index.
/// A failed or interrupted save cannot replace an earlier saved scan. Native
/// pages use disk records; browser pages use IndexedDB via the shared factory.
class StorageScanSnapshotStore {
  StorageScanSnapshotStore({FileCollectionStorage? storage})
    : _storage =
          storage ??
          createFileCollectionStorage(
            preferences: SharedPreferences.getInstance,
          );

  final FileCollectionStorage _storage;
  static const version = 1;
  // The scanner admits 200,000 descendants, plus the root itself.
  static const maxNodes = 200001;
  static const maxSnapshots = 100;
  static const pageNodeLimit = 500;
  static const pageByteLimit = 512 * 1024;
  static const manifestByteLimit = 512 * 1024;
  static const indexByteLimit = 512 * 1024;
  static const snapshotByteLimit = 128 * 1024 * 1024;
  static const maxPages = 2048;
  static const indexKey = 'storage-scan-index-v1';
  static const _maxInteger = StorageScanService.maxReportedBytes;

  static String _manifestKey(String id) => 'storage-scan:$id:manifest-v1';
  static String _pageKey(String id, int page) => 'storage-scan:$id:page:$page';

  Future<List<StorageScanSnapshotSummary>> list() async {
    final (_, entries) = await _index();
    return List.unmodifiable(
      entries..sort((a, b) => b.savedAt.compareTo(a.savedAt)),
    );
  }

  Future<StorageScanSnapshotSummary> save({
    required StorageScanResult result,
    required String storageId,
    required String sourceLabel,
    p.Style? pathStyle,
    bool Function()? isCancelled,
  }) async {
    void checkCancellation() {
      if (isCancelled?.call() ?? false) {
        throw StateError('Saving the scan was cancelled.');
      }
    }

    checkCancellation();
    _text(storageId, 'storage ID', max: 1024);
    _text(sourceLabel, 'source label', max: 1024, empty: true);
    final style =
        pathStyle ??
        (p.windows.isAbsolute(result.root.path) &&
                !p.posix.isAbsolute(result.root.path)
            ? p.Style.windows
            : p.Style.posix);
    if (style != p.Style.windows && style != p.Style.posix) {
      throw const FormatException('This scan path format cannot be saved.');
    }
    final paths = p.Context(style: style);
    _checkRoot(result.root.path, paths);
    if (result.issues.length > 1000) {
      throw const FormatException('The scan exceeds 1,000 saved diagnostics.');
    }
    _count(result.suppressedIssueCount, 'suppressed issues', max: _maxInteger);
    final (_, existing) = await _index();
    checkCancellation();
    if (existing.length >= maxSnapshots) {
      throw const FormatException(
        'Keep at most 100 saved scans. Delete an older scan first.',
      );
    }
    final id = const Uuid().v4();
    final createdKeys = <String>[];
    var commitUncertain = false;
    try {
      final pages = <Map<String, Object>>[];
      var page = <String>[];
      var pageBytes = 0;
      var totalBytes = 0;
      var nodes = 0;
      final batch = <FileCollectionStorageRecord>[];
      final seen = <String>{};
      final objects = HashSet<StorageNode>.identity();
      final pending = <(StorageNode, int, int, String?)>[
        (result.root, -1, 0, null),
      ];
      Future<void> writeBatch() async {
        if (batch.isEmpty) return;
        checkCancellation();
        await FileCollectionStorageBatch.write(_storage, batch);
        batch.clear();
        checkCancellation();
      }

      Future<void> flush() async {
        if (page.isEmpty) return;
        if (pages.length >= maxPages) {
          throw const FormatException('The scan exceeds its saved-page limit.');
        }
        final raw = '{"version":$version,"nodes":[${page.join(',')}]}';
        final key = _pageKey(id, pages.length);
        final record = FileCollectionStorageRecord(key, raw);
        final bytes = record.bytes;
        totalBytes += bytes.length;
        if (bytes.length > pageByteLimit || totalBytes > snapshotByteLimit) {
          throw const FormatException('The saved scan exceeds 128 MiB.');
        }
        createdKeys.add(key);
        batch.add(record);
        pages.add({
          'bytes': bytes.length,
          'nodes': page.length,
          'sha256': sha256.convert(bytes).toString(),
        });
        page = [];
        pageBytes = 0;
        if (batch.length == FileCollectionStorageBatch.maxRecords) {
          await writeBatch();
        }
      }

      while (pending.isNotEmpty) {
        checkCancellation();
        final (node, parent, depth, parentPath) = pending.removeLast();
        if (++nodes > maxNodes || depth > 201 || !objects.add(node)) {
          throw const FormatException(
            'The saved scan exceeds its tree limits.',
          );
        }
        if (!seen.add(node.path)) {
          throw const FormatException('The scan contains duplicate paths.');
        }
        _checkPath(node.item, parentPath, paths);
        _checkTotals(node, node.children);
        final row = _nodeJson(node, parent);
        final raw = jsonEncode(row);
        final length = utf8.encode(raw).length;
        if (length + 64 > pageByteLimit) {
          throw const FormatException(
            'One scan item exceeds its record limit.',
          );
        }
        if (page.length >= pageNodeLimit ||
            pageBytes + length + 64 > pageByteLimit) {
          await flush();
        }
        page.add(raw);
        pageBytes += length + 1;
        for (final child in node.children.reversed) {
          pending.add((child, nodes - 1, depth + 1, node.path));
        }
        if (nodes % 500 == 0) await Future<void>.delayed(Duration.zero);
      }
      await flush();
      await writeBatch();
      final summary = StorageScanSnapshotSummary(
        id: id,
        storageId: storageId,
        sourceLabel: sourceLabel,
        rootPath: result.root.path,
        pathStyle: style == p.Style.windows ? 'windows' : 'posix',
        savedAt: DateTime.now().toUtc(),
        completedAt: result.completedAt,
        nodeCount: nodes,
        bytes: result.root.bytes,
        fileCount: result.root.fileCount,
        folderCount: result.root.folderCount,
        isComplete: result.isComplete,
      );
      final manifest = jsonEncode({
        'version': version,
        'summary': summary._json(),
        'pages': pages,
        'startedAt': result.startedAt.toUtc().toIso8601String(),
        'cancelled': result.cancelled,
        'limited': result.limited,
        'sourceChanged': result.sourceChanged,
        'suppressedIssues': result.suppressedIssueCount,
        'issues': [
          for (final issue in result.issues)
            {
              'path': _text(issue.path, 'issue path', max: 32768, empty: true),
              'code': issue.code.name,
              'message': _text(
                issue.message,
                'issue message',
                max: 4096,
                empty: true,
              ),
            },
        ],
      });
      _bounded(manifest, manifestByteLimit);
      checkCancellation();
      createdKeys.add(_manifestKey(id));
      await _storage.write(_manifestKey(id), manifest);
      for (var attempt = 0; attempt < 4; attempt++) {
        checkCancellation();
        final (oldRaw, entries) = await _index();
        checkCancellation();
        if (entries.length >= maxSnapshots) {
          throw const FormatException(
            'Keep at most 100 saved scans. Delete an older scan first.',
          );
        }
        final updated = jsonEncode({
          'version': version,
          'snapshots': [
            summary._json(),
            ...entries.map((entry) => entry._json()),
          ],
        });
        _bounded(updated, indexByteLimit);
        // This is the last cancellation boundary. Once CAS commits, return its
        // saved summary even if cancellation arrives while awaiting the reply.
        checkCancellation();
        try {
          if (await _storage.compareAndSwap(indexKey, oldRaw, updated)) {
            return summary;
          }
        } catch (cause) {
          // A thrown commit may already have succeeded. Never remove its pages
          // unless non-publication is certain, including when readback fails.
          commitUncertain = true;
          late List<StorageScanSnapshotSummary> current;
          try {
            final (_, recovered) = await _index();
            current = recovered;
          } catch (recoveryCause) {
            throw StorageScanSnapshotCommitUnconfirmed(
              snapshotId: id,
              cause: cause,
              recoveryCause: recoveryCause,
            );
          }
          if (current.any((entry) => entry.id == id)) return summary;
          rethrow;
        }
      }
      throw StateError('Saved scans changed in another window. Please retry.');
    } catch (_) {
      if (!commitUncertain) {
        for (final key in createdKeys) {
          try {
            await _storage.remove(key);
          } catch (_) {
            /* unreferenced only */
          }
        }
      }
      rethrow;
    }
  }

  Future<StorageScanSnapshot> load(
    String id, {
    bool Function()? isCancelled,
  }) async {
    void checkCancellation() {
      if (isCancelled?.call() ?? false) {
        throw StateError('Opening the saved scan was cancelled.');
      }
    }

    checkCancellation();
    final (_, entries) = await _index();
    checkCancellation();
    final matches = entries.where((entry) => entry.id == id);
    if (matches.isEmpty) {
      throw const FormatException('This saved scan is no longer available.');
    }
    final summary = matches.single;
    final manifestRaw = await _storage.read(
      _manifestKey(id),
      maxBytes: manifestByteLimit,
    );
    checkCancellation();
    if (manifestRaw == null) {
      throw const FormatException('The saved scan manifest is missing.');
    }
    final manifest = _map(_decode(manifestRaw), 'manifest');
    _version(manifest);
    final savedSummary = _summary(_map(manifest['summary'], 'summary'));
    if (jsonEncode(savedSummary._json()) != jsonEncode(summary._json())) {
      throw const FormatException(
        'The saved scan manifest does not match its history record.',
      );
    }
    final pages = _list(manifest['pages'], 'pages', maxPages);
    if (pages.isEmpty) {
      throw const FormatException('The saved scan has no pages.');
    }
    final rows = <_SnapshotRow>[];
    var totalBytes = 0;
    var totalNodes = 0;
    final descriptors = <(int, int, Object?)>[];
    final paths = p.Context(
      style: summary.pathStyle == 'windows' ? p.Style.windows : p.Style.posix,
    );
    for (var page = 0; page < pages.length; page++) {
      final descriptor = _map(pages[page], 'page descriptor');
      final length = _count(
        descriptor['bytes'],
        'page bytes',
        max: pageByteLimit,
      );
      final count = _count(
        descriptor['nodes'],
        'page nodes',
        max: pageNodeLimit,
      );
      totalNodes += count;
      if (length == 0 || count == 0 || totalNodes > summary.nodeCount) {
        throw const FormatException('Invalid saved scan page limits.');
      }
      totalBytes += length;
      if (totalBytes > snapshotByteLimit) {
        throw const FormatException('The saved scan exceeds 128 MiB.');
      }
      descriptors.add((length, count, descriptor['sha256']));
    }
    if (totalNodes != summary.nodeCount) {
      throw const FormatException('The saved scan is missing items.');
    }
    final seen = <String>{};
    for (
      var start = 0;
      start < descriptors.length;
      start += FileCollectionStorageBatch.maxRecords
    ) {
      checkCancellation();
      final proposedEnd = start + FileCollectionStorageBatch.maxRecords;
      final end = proposedEnd < descriptors.length
          ? proposedEnd
          : descriptors.length;
      // At most four bounded immutable records are outstanding. Future.wait
      // drains failures too; validation remains strictly in manifest order.
      final values = await Future.wait<String?>([
        for (var page = start; page < end; page++)
          Future<String?>.sync(
            () => _storage.read(_pageKey(id, page), maxBytes: pageByteLimit),
          ),
      ]);
      checkCancellation();
      for (var page = start; page < end; page++) {
        final (length, count, digest) = descriptors[page];
        final raw = values[page - start];
        if (raw == null) {
          throw const FormatException('A saved scan page is missing.');
        }
        final bytes = utf8.encode(raw);
        if (bytes.length != length ||
            sha256.convert(bytes).toString() != digest) {
          throw const FormatException('A saved scan page is damaged.');
        }
        final data = _map(_decode(raw), 'page');
        _version(data);
        final records = _list(data['nodes'], 'nodes', pageNodeLimit);
        if (records.length != count) {
          throw const FormatException(
            'A saved scan page has the wrong item count.',
          );
        }
        for (final record in records) {
          checkCancellation();
          final row = _row(_map(record, 'node'));
          final index = rows.length;
          if (row.parent >= index ||
              row.parent < -1 ||
              (index == 0) != (row.parent == -1)) {
            throw const FormatException(
              'Invalid saved scan parent references.',
            );
          }
          final parent = row.parent < 0 ? null : rows[row.parent];
          if (parent != null &&
              (!parent.item.isFolder || parent.item.isSymlink == true)) {
            throw const FormatException(
              'A file or link cannot contain saved children.',
            );
          }
          row.depth = parent == null ? 0 : parent.depth + 1;
          if (row.depth > 201 || !seen.add(row.item.path!)) {
            throw const FormatException(
              'The saved scan contains invalid or repeated paths.',
            );
          }
          _checkPath(row.item, parent?.item.path, paths);
          if (index == 0 && row.item.path != summary.rootPath) {
            throw const FormatException(
              'The saved scan root does not match its history record.',
            );
          }
          parent?.children.add(index);
          rows.add(row);
        }
        await Future<void>.delayed(Duration.zero);
        checkCancellation();
      }
    }
    final built = List<StorageNode?>.filled(rows.length, null);
    for (var index = rows.length - 1; index >= 0; index--) {
      checkCancellation();
      final row = rows[index];
      final children = [for (final child in row.children) built[child]!];
      final node = StorageNode(
        item: row.item,
        children: children,
        bytes: row.bytes,
        fileCount: row.files,
        folderCount: row.folders,
        unknownSizeCount: row.unknown,
        skippedLinkCount: row.links,
        isComplete: row.complete,
      );
      _checkTotals(node, children);
      built[index] = node;
      if (index % 500 == 0) await Future<void>.delayed(Duration.zero);
    }
    final issues = <StorageScanIssue>[];
    for (final value in _list(manifest['issues'], 'issues', 1000)) {
      final issue = _map(value, 'issue');
      final codes = StorageScanIssueCode.values.where(
        (code) => code.name == issue['code'],
      );
      if (codes.isEmpty) {
        throw const FormatException('Unknown saved scan issue code.');
      }
      issues.add(
        StorageScanIssue(
          path: _text(issue['path'], 'issue path', max: 32768, empty: true),
          code: codes.single,
          message: _text(
            issue['message'],
            'issue message',
            max: 4096,
            empty: true,
          ),
        ),
      );
    }
    final result = StorageScanResult(
      root: built.first!,
      issues: issues,
      cancelled: _bool(manifest['cancelled']),
      limited: _bool(manifest['limited']),
      sourceChanged: _bool(manifest['sourceChanged']),
      startedAt: _date(manifest['startedAt']),
      completedAt: summary.completedAt,
      suppressedIssueCount: _count(
        manifest['suppressedIssues'],
        'suppressed issues',
        max: _maxInteger,
      ),
    );
    if (result.root.bytes != summary.bytes ||
        result.root.fileCount != summary.fileCount ||
        result.root.folderCount != summary.folderCount ||
        result.isComplete != summary.isComplete) {
      throw const FormatException(
        'The saved scan totals do not match its history record.',
      );
    }
    checkCancellation();
    return StorageScanSnapshot(summary: summary, result: result);
  }

  Future<void> delete(String id) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final (raw, entries) = await _index();
      if (!entries.any((entry) => entry.id == id)) return;
      final next = jsonEncode({
        'version': version,
        'snapshots': entries
            .where((entry) => entry.id != id)
            .map((entry) => entry._json())
            .toList(),
      });
      var published = false;
      try {
        published = await _storage.compareAndSwap(indexKey, raw, next);
      } catch (_) {
        // Just like a save, deletion may have committed before its write
        // acknowledgement failed. Retain pages if readback is unavailable.
        final (_, current) = await _index();
        if (current.any((entry) => entry.id == id)) rethrow;
        published = true;
      }
      if (!published) continue;
      // History publication is authoritative. Cleanup is best effort; never
      // turn a successful deletion into a reported failure due to orphan data.
      try {
        final manifest = await _storage.read(
          _manifestKey(id),
          maxBytes: manifestByteLimit,
        );
        if (manifest != null) {
          final data = _map(_decode(manifest), 'manifest');
          final pages = _list(data['pages'], 'pages', maxPages);
          for (var page = 0; page < pages.length; page++) {
            await _storage.remove(_pageKey(id, page));
          }
        }
        await _storage.remove(_manifestKey(id));
      } catch (_) {
        /* only unreferenced records remain */
      }
      return;
    }
    throw StateError('Saved scans changed in another window. Please retry.');
  }

  Future<(String?, List<StorageScanSnapshotSummary>)> _index() async {
    final raw = await _storage.read(indexKey, maxBytes: indexByteLimit);
    if (raw == null) return (null, <StorageScanSnapshotSummary>[]);
    final data = _map(_decode(raw), 'history');
    _version(data);
    final entries = [
      for (final value in _list(data['snapshots'], 'snapshots', maxSnapshots))
        _summary(_map(value, 'summary')),
    ];
    if (entries.map((entry) => entry.id).toSet().length != entries.length) {
      throw const FormatException(
        'The saved scan history contains duplicate IDs.',
      );
    }
    return (raw, entries);
  }

  static StorageScanSnapshotSummary _summary(Map<String, dynamic> data) {
    final id = _text(data['id'], 'ID', max: 36);
    if (!RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
    ).hasMatch(id)) {
      throw const FormatException('Invalid saved scan ID.');
    }
    final style = _text(data['pathStyle'], 'path style', max: 16);
    if (style != 'windows' && style != 'posix') {
      throw const FormatException('Unsupported saved path style.');
    }
    final root = _text(data['rootPath'], 'root path', max: 32768);
    _checkRoot(
      root,
      p.Context(style: style == 'windows' ? p.Style.windows : p.Style.posix),
    );
    final count = _count(data['nodes'], 'nodes', max: maxNodes);
    if (count == 0) throw const FormatException('The saved scan has no root.');
    return StorageScanSnapshotSummary(
      id: id,
      storageId: _text(data['storageId'], 'storage ID', max: 1024),
      sourceLabel: _text(
        data['sourceLabel'],
        'source label',
        max: 1024,
        empty: true,
      ),
      rootPath: root,
      pathStyle: style,
      savedAt: _date(data['savedAt']),
      completedAt: _date(data['completedAt']),
      nodeCount: count,
      bytes: _integer(data['bytes']),
      fileCount: _count(data['files'], 'files'),
      folderCount: _count(data['folders'], 'folders'),
      isComplete: _bool(data['complete']),
    );
  }

  static Map<String, Object?> _nodeJson(StorageNode node, int parent) {
    final item = node.item;
    // Deliberate whitelist: never serialize metadata, XFile handles, source
    // objects, credentials, or provider-specific download links.
    return {
      'parent': parent,
      'name': _text(item.name, 'name', max: 4096),
      'path': _text(item.path, 'path', max: 32768),
      'folder': item.isFolder,
      'uuid': item.uuid == null
          ? null
          : _text(item.uuid, 'object ID', max: 4096, empty: true),
      'size': item.size == null
          ? null
          : _encodeInteger(item.size!, signed: true),
      'updated': item.updatedAt?.toUtc().toIso8601String(),
      'symlink': item.isSymlink,
      'target': item.symlinkTarget == null
          ? null
          : _text(item.symlinkTarget, 'link target', max: 32768, empty: true),
      'bytes': _encodeInteger(node.bytes),
      'files': _count(node.fileCount, 'files'),
      'folders': _count(node.folderCount, 'folders'),
      'unknown': _count(node.unknownSizeCount, 'unknown sizes'),
      'links': _count(node.skippedLinkCount, 'links'),
      'complete': node.isComplete,
    };
  }

  static _SnapshotRow _row(Map<String, dynamic> data) => _SnapshotRow(
    parent: data['parent'] is int
        ? data['parent'] as int
        : throw const FormatException('Invalid saved parent.'),
    item: FileItem(
      name: _text(data['name'], 'name', max: 4096),
      path: _text(data['path'], 'path', max: 32768),
      isFolder: _bool(data['folder']),
      uuid: data['uuid'] == null
          ? null
          : _text(data['uuid'], 'object ID', max: 4096, empty: true),
      size: data['size'] == null ? null : _integer(data['size'], signed: true),
      updatedAt: data['updated'] == null ? null : _date(data['updated']),
      isSymlink: data['symlink'] == null ? null : _bool(data['symlink']),
      symlinkTarget: data['target'] == null
          ? null
          : _text(data['target'], 'link target', max: 32768, empty: true),
    ),
    bytes: _integer(data['bytes']),
    files: _count(data['files'], 'files'),
    folders: _count(data['folders'], 'folders'),
    unknown: _count(data['unknown'], 'unknown sizes'),
    links: _count(data['links'], 'links'),
    complete: _bool(data['complete']),
  );

  static void _checkRoot(String root, p.Context paths) {
    _text(root, 'root path', max: 32768);
    if (!paths.isAbsolute(root) || paths.normalize(root) != root) {
      throw const FormatException(
        'The saved scan needs a normalized absolute root.',
      );
    }
  }

  static void _checkPath(FileItem item, String? parent, p.Context paths) {
    final path = _text(item.path, 'path', max: 32768);
    _text(item.name, 'name', max: 4096);
    if (parent == null) {
      _checkRoot(path, paths);
      if (!item.isFolder || item.isSymlink == true) {
        throw const FormatException('The saved root must be a folder.');
      }
    } else if (!_canonicalChild(item.name, path, parent, paths.style) &&
        (!paths.isAbsolute(path) ||
            paths.normalize(path) != path ||
            paths.dirname(path) != parent ||
            paths.basename(path) != item.name ||
            item.name == '.' ||
            item.name == '..')) {
      throw const FormatException(
        'A saved item is not a direct child of its folder.',
      );
    }
  }

  // The parent has already passed validation earlier in the traversal. Exact
  // parent + separator + one ordinary component proves canonical membership
  // without reparsing the full path for every sibling. Unusual names and path
  // styles retain the general predicates above.
  static bool _canonicalChild(
    String name,
    String path,
    String parent,
    p.Style style,
  ) {
    final windows = style == p.Style.windows;
    if ((style != p.Style.posix && !windows) ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        (windows && (name.contains(r'\') || name.contains(':')))) {
      return false;
    }
    final separator = windows ? r'\' : '/';
    final terminated = parent.endsWith(separator);
    final prefixLength = parent.length + (terminated ? 0 : 1);
    return path.length == prefixLength + name.length &&
        path.startsWith(parent) &&
        (terminated ||
            path.codeUnitAt(parent.length) == separator.codeUnitAt(0)) &&
        path.endsWith(name);
  }

  static void _checkTotals(StorageNode node, List<StorageNode> children) {
    _encodeInteger(node.bytes);
    final link = node.item.isSymlink == true;
    final file = !node.isFolder && !link;
    if ((file || link) && children.isNotEmpty) {
      throw const FormatException('A saved file or link has children.');
    }
    var files = 0;
    var folders = 0;
    var links = 0;
    var unknown = 0;
    var bytes = 0;
    var complete = true;
    for (final child in children) {
      files += child.fileCount;
      folders +=
          child.folderCount +
          (child.isFolder && child.item.isSymlink != true ? 1 : 0);
      links += child.skippedLinkCount;
      unknown += child.unknownSizeCount;
      bytes += child.bytes;
      if (bytes < 0 || bytes > _maxInteger) {
        throw const FormatException('The saved scan has inconsistent totals.');
      }
      complete = complete && child.isComplete;
    }
    if (node.fileCount != (file ? 1 : files) ||
        node.folderCount != folders ||
        node.skippedLinkCount != (link ? 1 : links) ||
        node.unknownSizeCount !=
            (file ? (node.unknownSizeCount == 1 ? 1 : 0) : unknown) ||
        (file && node.unknownSizeCount != 0 && node.unknownSizeCount != 1) ||
        node.bytes !=
            (file
                ? (node.unknownSizeCount == 1 ? 0 : node.item.size)
                : bytes) ||
        (node.isComplete && (node.unknownSizeCount > 0 || !complete))) {
      throw const FormatException('The saved scan has inconsistent totals.');
    }
  }

  static Object? _decode(String raw) {
    // Reject deep JSON before recursive decoding. Records are flat, so nesting
    // beyond this allowance is corruption, not legitimate folder depth.
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (final c in raw.codeUnits) {
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == 92) {
          escaped = true;
        } else if (c == 34) {
          quoted = false;
        }
      } else if (c == 34) {
        quoted = true;
      } else if (c == 91 || c == 123) {
        if (++depth > 12) {
          throw const FormatException('Saved scan JSON is too deeply nested.');
        }
      } else if (c == 93 || c == 125) {
        if (--depth < 0) {
          throw const FormatException('Malformed saved scan JSON.');
        }
      }
    }
    return jsonDecode(raw);
  }

  static void _bounded(String raw, int limit) {
    if (utf8.encode(raw).length > limit) {
      throw const FormatException('Saved scan record exceeds its size limit.');
    }
  }

  static Map<String, dynamic> _map(Object? value, String name) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('Invalid saved scan $name.');
    }
    return value;
  }

  static List<dynamic> _list(Object? value, String name, int max) {
    if (value is! List || value.length > max) {
      throw FormatException('Invalid saved scan $name limit.');
    }
    return value;
  }

  static void _version(Map<String, dynamic> data) {
    if (data['version'] is! int || data['version'] != version) {
      throw const FormatException('Unsupported saved scan version.');
    }
  }

  static String _text(
    Object? value,
    String name, {
    required int max,
    bool empty = false,
  }) {
    if (value is! String ||
        (!empty && value.isEmpty) ||
        value.length > max ||
        value.contains('\u0000')) {
      throw FormatException('Invalid saved scan $name.');
    }
    return value;
  }

  static bool _bool(Object? value) {
    if (value is! bool) throw const FormatException('Invalid saved scan flag.');
    return value;
  }

  static int _count(Object? value, String name, {int max = maxNodes}) {
    if (value is! int || value < 0 || value > max) {
      throw FormatException('Invalid saved scan $name.');
    }
    return value;
  }

  static String _encodeInteger(int value, {bool signed = false}) {
    if (value > _maxInteger || value < (signed ? -_maxInteger : 0)) {
      throw const FormatException(
        'Saved bytes must fit the exact cross-platform integer range.',
      );
    }
    return value.toString();
  }

  static int _integer(Object? value, {bool signed = false}) {
    if (value is! String ||
        value.length > 17 ||
        !RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(value)) {
      throw const FormatException('Invalid exact saved byte count.');
    }
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw const FormatException('Invalid exact saved byte count.');
    }
    _encodeInteger(parsed, signed: signed);
    return parsed;
  }

  static DateTime _date(Object? value) {
    final text = _text(value, 'timestamp', max: 40);
    final date = DateTime.tryParse(text);
    if (date == null) {
      throw const FormatException('Invalid saved scan timestamp.');
    }
    return date;
  }
}

class _SnapshotRow {
  _SnapshotRow({
    required this.parent,
    required this.item,
    required this.bytes,
    required this.files,
    required this.folders,
    required this.unknown,
    required this.links,
    required this.complete,
  });
  final int parent;
  final FileItem item;
  final int bytes;
  final int files;
  final int folders;
  final int unknown;
  final int links;
  final bool complete;
  final children = <int>[];
  int depth = 0;
}
