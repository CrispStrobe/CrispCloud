import 'private_tool_staging_stub.dart'
    if (dart.library.io) 'private_tool_staging_io.dart'
    as platform;

typedef PrivateStageCheckpoint = Future<void> Function();

enum PrivateStageFailure {
  unsupported,
  invalid,
  unavailable,
  busy,
  tooLarge,
  changed,
}

class PrivateStageException implements Exception {
  const PrivateStageException(this.failure);
  final PrivateStageFailure failure;
  @override
  String toString() => 'Private tool staging: ${failure.name}';
}

/// A content identity for one regular file inside a leased private directory.
/// The absolute path is transient; persisted records use [name] instead.
class PrivateStagedFile {
  const PrivateStagedFile({
    required this.name,
    required this.path,
    required this.length,
    required this.sha256,
  });
  final String name, path, sha256;
  final int length;
}

/// Small native staging primitive shared by external editing and comparison.
/// It does not decide whether a remote upload or an external launch is allowed.
abstract class PrivateToolStagingStore {
  factory PrivateToolStagingStore({Future<String> Function()? rootDirectory}) =>
      platform.createPrivateToolStagingStore(rootDirectory: rootDirectory);

  Future<PrivateToolStage> create({required String kind, String? id});
  Future<PrivateToolStage> open({required String kind, required String id});

  /// Lists identifiers without taking leases or executing recovered work.
  Future<List<String>> list(String kind);
}

abstract class PrivateToolStage {
  String get id;
  String get kind;
  String get directoryPath;

  /// Installs a complete, flushed file. Existing completed names are refused.
  Future<PrivateStagedFile> write(
    String name,
    Stream<List<int>> source, {
    required int maxBytes,
    int? expectedLength,
    PrivateStageCheckpoint? checkpoint,
  });
  Future<PrivateStagedFile> inspect(
    String name, {
    required int maxBytes,
    PrivateStageCheckpoint? checkpoint,
  });
  Stream<List<int>> openRead(
    PrivateStagedFile expected, {
    PrivateStageCheckpoint? checkpoint,
  });
  Future<PrivateStagedFile> snapshot(
    String name,
    String snapshotName, {
    required int maxBytes,
    PrivateStageCheckpoint? checkpoint,
  });
  Stream<void> watch(String name);
  Future<void> deleteFile(String name);

  /// Caller-owned metadata inside a bounded, checksummed durable envelope.
  /// No credentials belong in a manifest. Null denotes an interrupted create.
  Future<Map<String, dynamic>?> readManifest();
  Future<void> writeManifest(Map<String, dynamic> manifest);

  /// Releases the native lease and retains every staged file for recovery.
  Future<void> close();

  /// Explicitly removes only this private directory after the caller has
  /// established that external tools and publication no longer need it.
  /// A retained, closed handle must be reopened before deletion.
  Future<void> delete();
}
