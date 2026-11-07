import 'package:flutter/foundation.dart' show kIsWeb;

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
    final grantSource = local is LocalFileSourceIdentity
        ? local as LocalFileSourceIdentity
        : null;
    final capturedGrant = grantSource?.sourceIdentityForPath(
      source.currentPath,
    );
    if (kIsWeb && capturedGrant == null) {
      throw UnsupportedError(
        'Open a selected local folder before scanning browser storage.',
      );
    }
    var grantLost = false;
    return _LocalStorageScanBackend(
      local,
      scanRoot: source.currentPath,
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

class _LocalStorageScanBackend extends LocalOperationBackend
    implements StorageScanDirectoryReader {
  _LocalStorageScanBackend(
    super.service, {
    required super.isCurrent,
    required this.scanRoot,
  });
  final String scanRoot;

  // A case-sensitive macOS/Windows volume may legitimately contain A and a.
  // A read-only census must not use conservative destination collision keys.
  @override
  String pathKey(String path) => paths.normalize(path);

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
    final entries = await super.list(path);
    if (!isCurrent) throw StateError('The selected local folder changed.');
    return StorageScanDirectory(
      entries: entries,
      // Browser-local listings currently expose cached picker snapshots, omit
      // hidden entries in the FSA path, and may suppress enumeration errors.
      // Do not describe that legacy API as a complete/live directory census.
      isComplete: !kIsWeb,
      issues: kIsWeb && samePath(path, scanRoot)
          ? [
              StorageScanIssue(
                path: path,
                code: StorageScanIssueCode.incompleteListing,
                message: 'Browser-local results use a cached folder snapshot. Hidden entries and access failures may be omitted; use the installed app for a complete local scan.',
              ),
            ]
          : const [],
    );
  }
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
