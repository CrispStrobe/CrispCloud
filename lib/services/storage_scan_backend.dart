import '../models/file_item.dart';
import '../models/storage_analysis.dart';
import 'cloud_storage_interface.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';
import 'local_file_service.dart';
import 'panel_source_service.dart';

/// Read metadata from the exact source captured by the initiating panel.
/// Mutation backends deliberately make conservative name/size choices; the
/// scanner preserves case-distinct local entries and stored cloud file sizes.
FileOperationBackend storageScanBackend({
  required PanelSource source,
  required LocalFileService local,
  required bool Function() isCurrent,
}) {
  if (source is LocalPanelSource) {
    return _LocalStorageScanBackend(local, isCurrent: isCurrent);
  }
  if (source is RemotePanelSource) {
    return CloudStorageScanBackend(source.client, isCurrent: isCurrent);
  }
  throw UnsupportedError('Open a local or cloud folder before scanning.');
}

class _LocalStorageScanBackend extends LocalOperationBackend {
  _LocalStorageScanBackend(super.service, {required super.isCurrent});

  // A case-sensitive macOS/Windows volume may legitimately contain A and a.
  // A read-only census must not use conservative destination collision keys.
  @override
  String pathKey(String path) => paths.normalize(path);
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
      throw StateError('The provider could not return a verified directory listing.');
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
    void invalidEntry() {
      // Report malformed data once per directory instead of allocating a
      // diagnostic for every bad row in a large provider response.
      if (!issues.any((issue) => issue.code == StorageScanIssueCode.invalidEntry)) {
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
        final folder = group == 'folders' ||
            item['isFolder'] == true ||
            item['type'] == 'folder' ||
            item['type'] == 'directory';
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
            isSymlink: item['isSymlink'] == true ||
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
    if (value is num && value.isFinite && value >= 0 && value == value.truncateToDouble()) {
      return value.toInt();
    }
    if (value is String && RegExp(r'^\d+$').hasMatch(value)) {
      return int.tryParse(value);
    }
    return null;
  }

  static DateTime? _modified(Map<String, dynamic> item) {
    final value = item['modificationTime'] ??
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
