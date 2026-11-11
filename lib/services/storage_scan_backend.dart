import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/storage_analysis.dart';
import 'cloud_storage_interface.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'panel_source_service.dart';
import 'storage_scan_native.dart';

/// Read metadata from the exact source captured by the initiating panel.
/// Mutation backends deliberately make conservative name/size choices; the
/// scanner preserves case-distinct local entries and stored cloud file sizes.
FileOperationBackend storageScanBackend({
  required PanelSource source,
  required LocalFileService local,
  required bool Function() isCurrent,
}) {
  if (source is LocalPanelSource) {
    if (kIsWeb) {
      return VirtualLocalStorageScanBackend(
        local,
        scanRoot: source.currentPath,
        isCurrent: isCurrent,
      );
    }
    final grantSource = local is LocalFileSourceIdentity
        ? local as LocalFileSourceIdentity
        : null;
    final capturedGrant = grantSource?.sourceIdentityForPath(
      source.currentPath,
    );
    var grantLost = false;
    return _LocalStorageScanBackend(
      local,
      isCurrent: () {
        if (!isCurrent()) return false;
        if (grantSource != null &&
            !identical(
              capturedGrant,
              grantSource.sourceIdentityForPath(source.currentPath),
            )) {
          grantLost = true;
        }
        return !grantLost;
      },
    );
  }
  if (source is RemotePanelSource) {
    return CloudStorageScanBackend(source.client, isCurrent: isCurrent);
  }
  throw UnsupportedError('Open a local or cloud folder before scanning.');
}

/// Reads a granted virtual folder without populating the interactive cache.
/// Kept independent of the host platform so its grant boundaries can also be
/// exercised with deterministic virtual filesystems in native tests.
class VirtualLocalStorageScanBackend extends LocalOperationBackend
    implements StorageScanDirectoryReader {
  factory VirtualLocalStorageScanBackend(
    LocalFileService service, {
    required String scanRoot,
    required bool Function() isCurrent,
  }) {
    if (scanRoot.isEmpty ||
        scanRoot.contains('\u0000') ||
        !p.posix.isAbsolute(scanRoot)) {
      throw FileSystemException(
        'Use an absolute selected folder path.',
        scanRoot,
      );
    }
    final root = p.posix.normalize(scanRoot);
    if (service is! LocalFileSourceIdentity ||
        service is! LocalDirectorySnapshotReader) {
      throw UnsupportedError(
        'Noninteractive folder snapshots are unavailable.',
      );
    }
    final identities = service as LocalFileSourceIdentity;
    final grant = identities.sourceIdentityForPath(root);
    if (grant == null) {
      throw UnsupportedError('Open a selected local folder before scanning.');
    }
    var lost = false;
    bool current() {
      if (lost) return false;
      if (!isCurrent() ||
          !identical(identities.sourceIdentityForPath(root), grant)) {
        lost = true;
      }
      return !lost;
    }

    return VirtualLocalStorageScanBackend._(
      service,
      scanRoot: root,
      identities: identities,
      grant: grant,
      isCurrent: current,
    );
  }

  VirtualLocalStorageScanBackend._(
    super.service, {
    required this.scanRoot,
    required LocalFileSourceIdentity identities,
    required Object grant,
    required super.isCurrent,
  }) : _identities = identities,
       _grant = grant;

  final String scanRoot;
  final LocalFileSourceIdentity _identities;
  final Object _grant;
  StorageScanDirectory? _rootSnapshot;

  @override
  p.Context get paths => p.posix;
  @override
  String pathKey(String path) => paths.normalize(path);
  @override
  bool get supportsModifiedTime => false;
  @override
  bool get supportsSymbolicLinks => false;

  String _checkedPath(String path) {
    if (!isCurrent) throw StateError('The selected local folder changed.');
    if (path.isEmpty || path.contains('\u0000') || !paths.isAbsolute(path)) {
      throw FileSystemException('Use an absolute selected folder path.', path);
    }
    final normalized = paths.normalize(path);
    if ((normalized != scanRoot && !paths.isWithin(scanRoot, normalized)) ||
        !identical(_identities.sourceIdentityForPath(normalized), _grant)) {
      throw FileSystemException(
        'The path is outside the selected folder.',
        path,
      );
    }
    return normalized;
  }

  @override
  Future<FileItem?> stat(String path) async {
    final normalized = _checkedPath(path);
    if (normalized == scanRoot) {
      // A successful directory snapshot verifies a selected root directly.
      // Its parent may be the ungranted browser namespace or another root.
      _rootSnapshot = await _readDirectory(normalized);
      return FileItem(
        name: paths.basename(normalized),
        path: normalized,
        isFolder: true,
      );
    }
    final parent = paths.dirname(normalized);
    final listing = await _readDirectory(parent);
    _checkedPath(normalized);
    final matches = listing.entries
        .where((entry) => entry.path == normalized)
        .toList();
    if (matches.length > 1) {
      throw StateError('Ambiguous directory entry: $normalized');
    }
    return matches.isEmpty ? null : matches.single;
  }

  @override
  Future<List<FileItem>> list(String path) async =>
      (await listForStorageScan(path)).entries;

  @override
  Future<StorageScanDirectory> listForStorageScan(String path) async {
    final normalized = _checkedPath(path);
    if (normalized == scanRoot && _rootSnapshot != null) {
      final snapshot = _rootSnapshot!;
      _rootSnapshot = null;
      return snapshot;
    }
    return _readDirectory(normalized);
  }

  Future<StorageScanDirectory> _readDirectory(String path) async {
    _checkedPath(path);
    final snapshot = await service.listDirectorySnapshot(path);
    _checkedPath(path);
    if (snapshot == null) {
      throw FileSystemException('The selected folder is unavailable.', path);
    }
    final entries = <FileItem>[];
    final issues = <StorageScanIssue>[];
    final pathCounts = <String, int>{};
    for (final entity in snapshot) {
      pathCounts.update(entity.path, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final entity in snapshot) {
      final child = entity.path;
      if (child.contains('\u0000') ||
          !paths.isAbsolute(child) ||
          paths.normalize(child) != child ||
          paths.dirname(child) != path ||
          child == path ||
          pathCounts[child] != 1 ||
          !identical(_identities.sourceIdentityForPath(child), _grant) ||
          (entity is! File && entity is! Directory && entity is! Link)) {
        issues.add(
          StorageScanIssue(
            path: child,
            code: StorageScanIssueCode.invalidEntry,
            message: 'An entry did not identify a direct child of the selected folder.',
          ),
        );
        continue;
      }
      final metadata = entity is File
          ? service.getWebMetadata(child)
          : const <String, dynamic>{};
      _checkedPath(child);
      entries.add(
        FileItem(
          name: paths.basename(child),
          path: child,
          isFolder: entity is Directory,
          isSymlink: entity is Link,
          size: metadata['size'] is int ? metadata['size'] as int : null,
          updatedAt: metadata['modified'] is DateTime
              ? metadata['modified'] as DateTime
              : null,
        ),
      );
    }
    return StorageScanDirectory(
      entries: entries,
      // Snapshot enumeration is nonmutating. Available file metadata can still
      // be older than that enumeration, and new entries may have no size.
      isComplete: false,
      issues: [
        ...issues,
        if (path == scanRoot)
          StorageScanIssue(
            path: path,
            code: StorageScanIssueCode.incompleteListing,
            message: 'Browser-local sizes may use older file metadata or omit unavailable sizes. This report is a partial observation.',
          ),
      ],
    );
  }
}

class _LocalStorageScanBackend extends LocalOperationBackend
    implements
        StorageScanDirectoryReader,
        StorageScanDirectoryGuard,
        StorageScanSessionFactory {
  _LocalStorageScanBackend(super.service, {required super.isCurrent});

  // A case-sensitive macOS/Windows volume may legitimately contain A and a.
  // A read-only census must not use conservative destination collision keys.
  @override
  String pathKey(String path) => paths.normalize(path);

  @override
  bool get verifiesStorageScanDirectoryType => !kIsWeb;

  @override
  Future<StorageScanSession?> openStorageScanSession() async {
    if (kIsWeb) return null;
    if (!isCurrent) throw StateError('The selected local folder changed.');
    final worker = await NativeStorageScanWorker.start();
    try {
      if (!isCurrent) throw StateError('The selected local folder changed.');
      return _LocalStorageScanSession(service, worker, () => isCurrent);
    } catch (_) {
      await worker.close();
      rethrow;
    }
  }

  @override
  Future<StorageScanDirectory> listForStorageScan(String path) async {
    if (!isCurrent) throw StateError('The selected local folder changed.');
    if (!kIsWeb) {
      final result = await service.withFileOperationAccess(path, () async {
        if (!isCurrent) throw StateError('The selected local folder changed.');
        final listing = await readNativeStorageScanDirectory(path);
        if (!isCurrent) throw StateError('The selected local folder changed.');
        return listing;
      });
      if (!isCurrent) throw StateError('The selected local folder changed.');
      return result;
    }
    throw UnsupportedError(
      'Use virtual directory snapshots for browser scans.',
    );
  }
}

class _LocalStorageScanSession
    implements StorageScanSession, StorageScanDirectoryGuard {
  _LocalStorageScanSession(this._service, this._worker, this._isCurrent);

  final LocalFileService _service;
  final NativeStorageScanWorker _worker;
  final bool Function() _isCurrent;

  @override
  bool get verifiesStorageScanDirectoryType => true;

  void _check() {
    if (!_isCurrent()) throw StateError('The selected local folder changed.');
  }

  @override
  Future<StorageScanDirectory> listForStorageScan(String path) async {
    _check();
    final result = await _service.withFileOperationAccess(path, () async {
      _check();
      final listing = await _worker.readDirectory(path);
      _check();
      return listing;
    });
    _check();
    return result;
  }

  @override
  Future<void> close() => _worker.close();
}

/// A scan-specific cloud adapter retains incomplete pages as partial results.
/// Most adapters exhaust pagination internally; those exposing another page
/// remain visibly incomplete rather than silently understating their totals.
class CloudStorageScanBackend extends CloudOperationBackend
    implements StorageScanDirectoryReader {
  CloudStorageScanBackend(super.client, {required super.isCurrent});

  void _check() {
    if (!isCurrent) throw StateError('The original cloud account changed.');
  }

  @override
  Future<List<FileItem>> list(String path) async =>
      (await listForStorageScan(path)).entries;

  @override
  Future<FileItem?> stat(String path) async {
    _check();
    path = paths.normalize(path);
    if (isRootPath(path)) {
      return FileItem(name: paths.basename(path), path: path, isFolder: true);
    }
    // Scan source names exactly first. The mutation backend intentionally uses
    // conservative collision matching; that would reject two real A/a folders
    // on a case-sensitive remote with an unknown case capability. Reading one
    // direct parent also avoids recursively relisting every ancestor.
    final listing = await listForStorageScan(paths.dirname(path));
    _check();
    final name = paths.basename(path);
    var matches = listing.entries.where((item) => item.name == name).toList();
    if (matches.isEmpty &&
        capabilities.caseSensitivity == StorageCaseSensitivity.insensitive) {
      matches = listing.entries
          .where((item) => item.name.toLowerCase() == name.toLowerCase())
          .toList();
    }
    if (matches.length > 1) {
      throw StateError('The provider returned ambiguous entries for $path.');
    }
    if (matches.isNotEmpty) return matches.single;
    if (!listing.isComplete) {
      throw StateError(
        listing.issues.isNotEmpty ? listing.issues.first.message : 'The directory could not be found in an incomplete parent listing.',
      );
    }
    return null;
  }

  @override
  Future<StorageScanDirectory> listForStorageScan(String path) async {
    _check();
    final identityBefore = identity;
    final listing = await client.listPathForEdit(path);
    _check();
    if (identity != identityBefore) {
      throw StateError('The original cloud account changed.');
    }
    if (listing['success'] == false ||
        (listing['error'] != null && listing['error'] != false)) {
      throw StateError(
        'The provider could not return a verified directory listing.',
      );
    }

    final issues = <StorageScanIssue>[];
    if (listing['complete'] == false || _hasMorePages(listing)) {
      issues.add(
        StorageScanIssue(
          path: path,
          code: StorageScanIssueCode.incompleteListing,
          message: 'The provider returned a partial directory page; totals are incomplete.',
        ),
      );
    }
    final entries = <FileItem>[];
    var excludedBucketIndex = false;
    void invalidEntry() {
      // Report malformed data once per directory instead of allocating a
      // diagnostic for every bad row in a large provider response.
      if (!issues.any(
        (issue) => issue.code == StorageScanIssueCode.invalidEntry,
      )) {
        issues.add(_invalidEntry(path));
      }
    }

    // B2 returns a single mixed "files" array with isFolder flags. Other
    // providers generally split the listing into "folders" and "files".
    if (listing['files'] is! List ||
        (listing.containsKey('folders') && listing['folders'] is! List)) {
      throw StateError('The provider returned an invalid directory listing.');
    }
    for (final group in ['folders', 'files']) {
      for (final raw in (listing[group] as List?) ?? const []) {
        if (raw is! Map || raw.keys.any((key) => key is! String)) {
          invalidEntry();
          continue;
        }
        final item = Map<String, dynamic>.from(raw);
        final folder =
            group == 'folders' ||
            item['isFolder'] == true ||
            item['type'] == 'folder' ||
            item['type'] == 'directory';
        if (isRootPath(path) && folder && item.containsKey('bucketType')) {
          // Native B2 exposes bucket-index rows at /, while its child path API
          // addresses prefixes within one configured bucket. Descending these
          // virtual rows would measure unrelated prefixes as empty buckets.
          // Detect the metadata shape rather than a provider display name.
          if (!excludedBucketIndex) {
            issues.add(
              StorageScanIssue(
                path: path,
                code: StorageScanIssueCode.incompleteListing,
                message: 'This root lists virtual buckets. Use an S3-compatible connection to scan the bucket contents.',
              ),
            );
            excludedBucketIndex = true;
          }
          continue;
        }
        final originalName = item['name'];
        if (originalName is! String || originalName.isEmpty) {
          invalidEntry();
          continue;
        }
        var name = originalName;
        final fileType = item['fileType']?.toString() ?? '';
        if (!folder &&
            fileType.isNotEmpty &&
            fileType.toLowerCase() != 'file' &&
            !name.toLowerCase().endsWith('.${fileType.toLowerCase()}')) {
          name = '$name.$fileType';
        }
        if (name.isEmpty ||
            name == '.' ||
            name == '..' ||
            name.contains('/') ||
            name.contains('\\') ||
            name.contains('\u0000')) {
          invalidEntry();
          continue;
        }
        final nested = item['metadata'];
        final rawSize = item['size'] ?? (nested is Map ? nested['size'] : null);
        entries.add(
          FileItem(
            name: name,
            path: paths.join(path, name),
            uuid: item['uuid']?.toString(),
            isFolder: folder,
            // downloadSize is a transformed stream's length, not the storage
            // size. The analyzer intentionally uses the original size field.
            size: folder ? null : _size(rawSize),
            isSymlink:
                item['isSymlink'] == true ||
                item['type'] == 'symlink' ||
                item['type'] == 'link',
            updatedAt: _modified(item),
            metadata: item,
          ),
        );
      }
    }
    return StorageScanDirectory(
      entries: entries,
      issues: issues,
      isComplete: issues.isEmpty,
    );
  }

  static StorageScanIssue _invalidEntry(String path) => StorageScanIssue(
    path: path,
    code: StorageScanIssueCode.invalidEntry,
    message: 'A malformed provider entry was excluded from the scan.',
  );

  static int? _size(dynamic value) {
    if (value is int) return value >= 0 ? value : null;
    if (value is num &&
        value.isFinite &&
        value >= 0 &&
        value == value.truncateToDouble()) {
      return value.toInt();
    }
    if (value is String && RegExp(r'^\d+$').hasMatch(value)) {
      return int.tryParse(value);
    }
    return null;
  }

  static DateTime? _modified(Map<String, dynamic> item) {
    final value =
        item['modificationTime'] ??
        item['lastModified'] ??
        item['updatedAt'] ??
        item['timestamp'];
    if (value is DateTime) return value;
    if (value is num && value.isFinite) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      } on ArgumentError {
        return null;
      }
    }
    return value == null ? null : DateTime.tryParse(value.toString());
  }

  static bool _hasMorePages(Map<String, dynamic> listing) {
    for (final key in const [
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
      final value = listing[key];
      if (value != null && value != false && '$value'.trim().isNotEmpty) {
        return true;
      }
    }
    for (final key in const [
      'hasMore',
      'has_more',
      'isTruncated',
      'IsTruncated',
      'truncated',
      'hasNextPage',
    ]) {
      if (listing[key] == true || listing[key] == 'true') return true;
    }
    return false;
  }
}
