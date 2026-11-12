/// A provider must opt in to conditional replacement of an existing object.
/// Transfer, streaming and rename capability flags do not imply this contract.
const conditionalFilePublicationLimit = 64 * 1024 * 1024;

enum FilePublicationFailure {
  unsupported,
  invalid,
  changed,
  conflict,
  unavailable,
  uncertain,
}

class FilePublicationException implements Exception {
  const FilePublicationException(this.failure);
  final FilePublicationFailure failure;
  @override
  String toString() => 'File publication: ${failure.name}';
}

/// Credential-free, provider-verified evidence for one original revision.
/// [accountIdentity] is a hash of an immutable provider account identifier;
/// a display name or email address cannot supply this evidence.
class FilePublicationVersion {
  const FilePublicationVersion({
    required this.accountIdentity,
    required this.path,
    required this.objectId,
    required this.revision,
    required this.length,
    required this.contentHash,
  });

  final String accountIdentity, path, objectId, revision, contentHash;
  final int length;

  void validate() {
    final hash = RegExp(r'^[0-9a-f]{64}$');
    if (!hash.hasMatch(accountIdentity) ||
        !hash.hasMatch(contentHash) ||
        !path.startsWith('/') ||
        path.length > 4096 ||
        path.contains('\u0000') ||
        path.endsWith('/') ||
        path.split('/').any((part) => part == '..' || part == '.') ||
        objectId.isEmpty ||
        objectId.length > 512 ||
        objectId.contains('\u0000') ||
        revision.isEmpty ||
        revision.length > 512 ||
        revision.contains('\u0000') ||
        length < 0 ||
        length > conditionalFilePublicationLimit) {
      throw const FilePublicationException(FilePublicationFailure.invalid);
    }
  }

  bool sameObject(FilePublicationVersion other) =>
      accountIdentity == other.accountIdentity &&
      path == other.path &&
      objectId == other.objectId;

  Map<String, dynamic> toJson() => {
    'account': accountIdentity,
    'path': path,
    'id': objectId,
    'revision': revision,
    'length': length,
    'hash': contentHash,
  };

  factory FilePublicationVersion.fromJson(Object? value) {
    if (value is! Map ||
        value['account'] is! String ||
        value['path'] is! String ||
        value['id'] is! String ||
        value['revision'] is! String ||
        value['length'] is! int ||
        value['hash'] is! String) {
      throw const FilePublicationException(FilePublicationFailure.invalid);
    }
    final version = FilePublicationVersion(
      accountIdentity: value['account'] as String,
      path: value['path'] as String,
      objectId: value['id'] as String,
      revision: value['revision'] as String,
      length: value['length'] as int,
      contentHash: value['hash'] as String,
    );
    version.validate();
    return version;
  }

  @override
  bool operator ==(Object other) =>
      other is FilePublicationVersion &&
      sameObject(other) &&
      revision == other.revision &&
      length == other.length &&
      contentHash == other.contentHash;
  @override
  int get hashCode => Object.hash(
    accountIdentity,
    path,
    objectId,
    revision,
    length,
    contentHash,
  );
}

abstract interface class ConditionalFilePublication {
  /// Fresh exact-path metadata, never a cached listing or an alternate object.
  Future<FilePublicationVersion> inspectForPublication(
    String path, {
    required void Function() checkCurrent,
  });

  /// Read the exact immutable revision and verify its returned identity.
  Stream<List<int>> readForPublication(
    FilePublicationVersion version, {
    required void Function() checkCurrent,
  });

  /// Replace only the captured object's current revision. The provider must
  /// validate the entire input before commit, preserve the existing object
  /// identity, and enforce the revision condition at the actual request.
  ///
  /// [prepareCommit] flushes local recovery evidence before the first request
  /// that can change the original. Its hash is the provider's content hash.
  /// An ambiguous acknowledgement throws [FilePublicationFailure.uncertain];
  /// callers reconcile exact account/object/path/hash before any later write.
  Future<FilePublicationVersion> publishFileVersion(
    FilePublicationVersion expected,
    Stream<List<int>> contents, {
    required int length,
    required void Function() checkCurrent,
    required Future<void> Function(String contentHash) prepareCommit,
  });
}
