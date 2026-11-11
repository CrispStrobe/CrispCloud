import 'file_item.dart';

/// A metadata snapshot. [bytes] is the sum of known file sizes, never allocated
/// filesystem blocks, free space, or a provider's account quota.
class StorageNode {
  StorageNode({
    required this.item,
    List<StorageNode> children = const [],
    required this.bytes,
    required this.fileCount,
    required this.folderCount,
    this.unknownSizeCount = 0,
    this.skippedLinkCount = 0,
    this.isComplete = true,
  }) : children = children.isEmpty
           ? const <StorageNode>[]
           : List.unmodifiable(children);

  final FileItem item;
  final List<StorageNode> children;
  final int bytes;
  final int fileCount;

  /// Descendant directories, excluding this node and symbolic links.
  final int folderCount;
  final int unknownSizeCount;
  final int skippedLinkCount;

  /// False when files have unknown sizes, or any subtree could not be scanned.
  /// Intentionally excluded symbolic links are counted separately.
  final bool isComplete;

  String get name => item.name;
  String get path => item.path ?? item.name;
  bool get isFolder => item.isFolder;
}

enum StorageScanIssueCode {
  rootUnavailable,
  unreadableDirectory,
  incompleteListing,
  invalidEntry,
  duplicateEntry,
  depthLimit,
  entryLimit,
  byteLimit,
  sourceChanged,
}

class StorageScanIssue {
  const StorageScanIssue({
    required this.path,
    required this.code,
    required this.message,
  });

  final String path;
  final StorageScanIssueCode code;
  final String message;
}

class StorageScanProgress {
  const StorageScanProgress({
    required this.files,
    required this.folders,
    required this.bytes,
    required this.currentPath,
  });

  final int files;

  /// Discovered descendant directories, excluding the scan root and links.
  final int folders;
  final int bytes;
  final String currentPath;
}

class StorageScanResult {
  StorageScanResult({
    required this.root,
    List<StorageScanIssue> issues = const [],
    required this.cancelled,
    required this.limited,
    required this.sourceChanged,
    required this.startedAt,
    required this.completedAt,
    this.suppressedIssueCount = 0,
  }) : issues = List.unmodifiable(issues);

  final StorageNode root;
  final List<StorageScanIssue> issues;
  final bool cancelled;
  final bool limited;
  final bool sourceChanged;
  final DateTime startedAt;
  final DateTime completedAt;

  /// Diagnostics are bounded independently of the tree; no errors are silently
  /// treated as successful scans when the detail limit is reached.
  final int suppressedIssueCount;

  bool get isComplete =>
      root.isComplete && !cancelled && !limited && !sourceChanged;
}

/// Aggregate metadata for a directory, without retaining its descendant tree.
/// Use this for size displays; saved reports and tree views require a full
/// [StorageScanResult]. Both modes use the same guarded traversal and limits.
class StorageScanSummary {
  StorageScanSummary({
    required this.rootPath,
    required this.bytes,
    required this.fileCount,
    required this.folderCount,
    required this.unknownSizeCount,
    required this.skippedLinkCount,
    required bool isComplete,
    List<StorageScanIssue> issues = const [],
    required this.cancelled,
    required this.limited,
    required this.sourceChanged,
    required this.startedAt,
    required this.completedAt,
    this.suppressedIssueCount = 0,
  }) : _totalsComplete = isComplete,
       issues = List.unmodifiable(issues);

  final String rootPath;
  final int bytes;
  final int fileCount;

  /// Descendant directories, excluding the scan root and symbolic links.
  final int folderCount;
  final int unknownSizeCount;
  final int skippedLinkCount;
  final bool _totalsComplete;
  final List<StorageScanIssue> issues;
  final bool cancelled;
  final bool limited;
  final bool sourceChanged;
  final DateTime startedAt;
  final DateTime completedAt;
  final int suppressedIssueCount;

  bool get isComplete =>
      _totalsComplete && !cancelled && !limited && !sourceChanged;
}

/// Providers with pagination/error metadata can retain partial entries without
/// claiming their directory listing is complete.
class StorageScanDirectory {
  StorageScanDirectory({
    required List<FileItem> entries,
    List<StorageScanIssue> issues = const [],
    this.isComplete = true,
  }) : entries = List.unmodifiable(entries),
       issues = List.unmodifiable(issues);

  final List<FileItem> entries;
  final List<StorageScanIssue> issues;
  final bool isComplete;
}

abstract interface class StorageScanDirectoryReader {
  Future<StorageScanDirectory> listForStorageScan(String path);
}

/// A reader that checks the requested directory without following links before
/// and after its listing. Only that chosen reader can replace the scanner's
/// otherwise necessary pre-descent stat; a backend's unrelated session cannot.
abstract interface class StorageScanDirectoryGuard {
  bool get verifiesStorageScanDirectoryType;
}

/// A scan owns its reader session. Overlapping scans never close or reuse each
/// other's workers. A null session uses the source's ordinary listing API.
abstract interface class StorageScanSessionFactory {
  Future<StorageScanSession?> openStorageScanSession();
}

abstract interface class StorageScanSession
    implements StorageScanDirectoryReader {
  Future<void> close();
}
