import '../models/file_item.dart';
import 'file_operation_service.dart';

/// A provider capability for an explicitly reviewed verified-block copy.
/// Generic range support alone does not grant this capability.
abstract interface class VerifiedBlockContentSource {
  bool supportsVerifiedBlockContentsTo(FileOperationBackend destination);

  Future<T> withVerifiedBlockContents<T>({
    required FileItem sourceFile,
    required FileOperationBackend destination,
    required String destinationPath,
    required FileItem? existingDestination,
    required FileOperationControl control,
    required Future<T> Function(PreparedFileContents contents) consume,
  });
}

/// Live, single-use contents owned by one reviewed file-copy execution.
///
/// This is deliberately not serializable. The ordinary copy service remains
/// responsible for stream accounting, staging, journal phases and outcomes.
/// Implementations keep their captured access scope alive while consumed.
abstract interface class PreparedFileContents {
  int get length;

  /// The complete logical file, including any locally reused bytes.
  Stream<List<int>> openRead();

  /// Verify a complete private candidate before the publication checkpoint.
  Future<void> verifyStaged(FileItem staged);

  /// Runs after the awaited durable `committing` checkpoint and control gate.
  /// Revalidate source, baseline and candidate, ending with synchronous guards.
  Future<void> revalidateBeforePublication();

  /// Optional bookkeeping after acknowledged publication. Implementations must
  /// not turn an installed copy into a failure because an auxiliary cache fails.
  Future<void> committed();
}
