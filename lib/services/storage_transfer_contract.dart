import 'dart:typed_data';

/// Filesystem semantics are independent of a pane's position or provider label.
enum StorageCaseSensitivity { sensitive, insensitive, unknown }

/// Conservative capabilities of a connection. An absent capability never
/// authorizes an operation by emulating it with a more destructive operation.
class StorageTransferCapabilities {
  const StorageTransferCapabilities({
    this.caseSensitivity = StorageCaseSensitivity.unknown,
    this.nativeCopy = false,
    this.nativeMove = false,
    this.atomicMove = false,
    this.noReplaceMove = false,
    this.conditionalDelete = false,
    this.readRanges = false,
    this.resumableUpload = false,
    this.append = false,
    this.setModifiedTime = false,
    this.permissions = false,
    this.ownership = false,
    this.extendedAttributes = false,
    this.accessControlLists = false,
    this.symbolicLinks = false,
    this.deleteEmptyDirectory = false,
    this.boundedUpload = false,
    this.boundedDownload = false,
  });

  final StorageCaseSensitivity caseSensitivity;
  final bool nativeCopy;
  final bool nativeMove;

  /// True only for a provider-native rename, never copy followed by delete.
  /// Local callers must additionally handle cross-volume failure.
  final bool atomicMove;
  final bool noReplaceMove;
  final bool conditionalDelete;
  final bool readRanges;
  final bool resumableUpload;
  final bool append;
  final bool setModifiedTime;
  final bool permissions;
  final bool ownership;
  final bool extendedAttributes;
  final bool accessControlLists;
  final bool symbolicLinks;
  final bool deleteEmptyDirectory;
  final bool boundedUpload;
  final bool boundedDownload;
}

/// Returned only after the provider confirms completion, including any
/// asynchronous server-side copy. [path] is the actual, exact destination.
class CloudTransferResult {
  const CloudTransferResult({
    required this.path,
    this.id,
    this.version,
    this.size,
  });
  final String path;
  final String? id;
  final String? version;
  final int? size;
}

class TransferMetadata {
  const TransferMetadata({
    this.modified,
    this.accessed,
    this.created,
    this.mode,
    this.owner,
    this.group,
    this.extendedAttributes = const {},
    this.acl,
  });
  final DateTime? modified;
  final DateTime? accessed;
  final DateTime? created;
  final int? mode;
  final String? owner;
  final String? group;
  final Map<String, Uint8List> extendedAttributes;
  final String? acl;
}

typedef TransferCheckpoint = Future<void> Function();

/// Optional provider surface. Keeping this separate preserves compatibility
/// with existing clients and test doubles that implement CloudStorageClient.
/// Methods take a complete destination path, never a destination directory.
mixin CloudTransferOperations {
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities();

  /// Stable, non-secret connection identity (endpoint/account/bucket/drive).
  /// An empty value means the provider cannot restore a job after restart.
  String get transferIdentity => '';

  Future<CloudTransferResult> copyToExact(
    String sourcePath,
    String destinationPath, {
    bool replace = false,
    String? expectedSourceVersion,
    String? expectedDestinationVersion,
    TransferCheckpoint? checkpoint,
    void Function(int, int)? onProgress,
  }) async => throw UnsupportedError('Exact server-side copy is unavailable.');

  Future<CloudTransferResult> moveToExact(
    String sourcePath,
    String destinationPath, {
    bool replace = false,
    String? expectedSourceVersion,
    String? expectedDestinationVersion,
    TransferCheckpoint? checkpoint,
  }) async => throw UnsupportedError('Exact native move is unavailable.');

  Future<void> deleteDirectoryIfEmpty(String path) async =>
      throw UnsupportedError('Safe empty-directory deletion is unavailable.');

  Future<void> deleteTransferFile(
    String path, {
    String? expectedVersion,
  }) async =>
      throw UnsupportedError('Conditional file deletion is unavailable.');

  Future<TransferMetadata> readTransferMetadata(String path) async =>
      throw UnsupportedError('Transfer metadata is unavailable.');

  Future<void> setTransferMetadata(
    String path,
    TransferMetadata metadata,
  ) async => throw UnsupportedError('Transfer metadata cannot be set.');

  Stream<List<int>> readTransferRange(
    String path,
    int offset, {
    int? length,
    String? expectedVersion,
  }) => throw UnsupportedError('Validated range reads are unavailable.');
}
