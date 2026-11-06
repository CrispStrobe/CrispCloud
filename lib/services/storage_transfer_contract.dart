import 'dart:typed_data';

/// Filesystem semantics are independent of a pane's position or provider label.
enum StorageCaseSensitivity { sensitive, insensitive, unknown }

/// Object keys form a flat namespace. Displayed folders are prefixes, and a
/// rename requires individually tracked copy/delete operations rather than a
/// native directory move. This marker never implies conditional-write support.
abstract interface class ObjectStorageNamespace {}

/// Conservative capabilities of a connection. An absent capability never
/// authorizes an operation by emulating it with a more destructive operation.
class StorageTransferCapabilities {
  const StorageTransferCapabilities({
    this.caseSensitivity = StorageCaseSensitivity.unknown,
    this.nativeCopy = false,
    this.nativeMove = false,
    this.atomicMove = false,
    this.noReplaceMove = false,
    this.noReplaceCopy = false,
    this.conditionalCopy = false,
    this.conditionalMove = false,
    this.conditionalDelete = false,
    this.readRanges = false,
    this.resumableUpload = false,
    this.append = false,
    this.setModifiedTime = false,
    this.setAccessedTime = false,
    this.setCreatedTime = false,
    this.permissions = false,
    this.ownership = false,
    this.extendedAttributes = false,
    this.accessControlLists = false,
    this.windowsAttributes = false,
    this.symbolicLinks = false,
    this.deleteEmptyDirectory = false,
    this.boundedUpload = false,
    this.boundedDownload = false,
    this.preallocate = false,
    this.copyOnWrite = false,
  });

  final StorageCaseSensitivity caseSensitivity;
  final bool nativeCopy;
  final bool nativeMove;

  /// True only for a provider-native rename, never copy followed by delete.
  /// Local callers must additionally handle cross-volume failure.
  final bool atomicMove;
  final bool noReplaceMove;
  final bool noReplaceCopy;
  final bool conditionalCopy;
  final bool conditionalMove;
  final bool conditionalDelete;
  final bool readRanges;
  final bool resumableUpload;
  final bool append;
  final bool setModifiedTime;
  final bool setAccessedTime;
  final bool setCreatedTime;
  final bool permissions;
  final bool ownership;
  final bool extendedAttributes;
  final bool accessControlLists;
  final bool windowsAttributes;
  final bool symbolicLinks;
  final bool deleteEmptyDirectory;
  final bool boundedUpload;
  final bool boundedDownload;

  /// A physical disk-space reservation, not merely a sparse length change.
  final bool preallocate;

  /// The platform can request filesystem block cloning. A particular volume
  /// may refuse it; explicit clone requests must not silently stream instead.
  final bool copyOnWrite;
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
    this.windowsAttributes,
    this.windowsAttributesMask = 0x27,
  });
  final DateTime? modified;
  final DateTime? accessed;
  final DateTime? created;
  final int? mode;
  final String? owner;
  final String? group;
  final Map<String, Uint8List> extendedAttributes;
  final String? acl;

  /// Native Windows file attributes. Writes apply only [windowsAttributesMask]
  /// and preserve every other attribute already present on the destination.
  /// The writable bits are read-only, hidden, system, and archive (0x27).
  final int? windowsAttributes;
  final int windowsAttributesMask;
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

  /// Match an account-scoped, persisted upload session for this exact private
  /// path. Execution still verifies the remote parts and source digests.
  Future<bool> hasPendingUpload(String path, {int? length}) async => false;

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
