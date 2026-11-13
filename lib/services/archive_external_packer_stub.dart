import 'archive_external_packer_types.dart';
import 'archive_write_model.dart';

ArchiveExternalPackerEngine createArchiveExternalPackerEngine() =>
    const _UnavailableEngine();

class _UnavailableEngine implements ArchiveExternalPackerEngine {
  const _UnavailableEngine();
  @override
  String? get platform => null;
  @override
  Future<List<ArchiveExternalPackerConfiguration>> discover() async => const [];
  Never _unavailable() => throw const ArchiveExternalPackerException(
    ArchiveExternalPackerFailure.unsupportedPlatform,
  );
  @override
  Future<ArchiveExternalPackerInstallation> probe(
    ArchiveExternalPackerConfiguration configuration, {
    ArchiveExternalSevenZipProfile sevenZipProfile =
        const ArchiveExternalSevenZipProfile(),
    bool Function()? isCancelled,
  }) async => _unavailable();
  @override
  Future<void> write({
    required ArchiveExternalPackerInstallation installation,
    required ArchiveExternalPackerOptions options,
    required List<ArchiveWriteEntry> entries,
    required Future<void> Function(List<int>) sink,
    required int maxOutputBytes,
    bool Function()? isCancelled,
  }) async => _unavailable();
}
