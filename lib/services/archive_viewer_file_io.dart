import 'package:koni_archive/io.dart' as koni;

import 'archive_viewer_service.dart';
import 'archive_volume_backend.dart';
import 'archive_volume_source.dart';
import 'archive_streamed_reader.dart';
import 'archive_viewer_streaming.dart';
import 'file_operation_backend.dart';
import 'local_file_service.dart';

Future<ViewerArchive> openViewerArchiveFile(
  String path, {
  required String name,
  String? password,
  int maxMemberBytes = kArchiveReadLimit,
  bool streaming = false,
  bool Function()? isCancelled,
}) async {
  void check() {
    if (isCancelled?.call() ?? false) {
      throw const ArchiveViewException('Archive opening was cancelled.');
    }
  }

  Future<ViewerArchive> accept(ViewerArchive archive) async {
    try {
      check();
      return archive;
    } catch (_) {
      await archive.close();
      rethrow;
    }
  }

  check();
  if (sevenZipVolumeBaseName(name) != null) {
    final local = LocalFileService();
    final backend = LocalOperationBackend(
      local,
      isCurrent: () => !(isCancelled?.call() ?? false),
    );
    final selected = await backend.stat(path);
    check();
    if (selected == null ||
        selected.name != name.split(RegExp(r'[/\\]')).last) {
      throw const ArchiveViewException(
        'The first split-archive volume is unavailable.',
      );
    }
    final opened = await openSevenZipVolumeArchive(
      backend,
      selected,
      password: password,
      streaming: streaming,
      maxMemberBytes: maxMemberBytes,
      isCancelled: isCancelled,
    );
    return accept(opened.archive);
  }
  if (streaming && isStreamedArchiveViewerName(name)) {
    final source = await koni.FileByteSource.open(path);
    var transferred = false;
    try {
      final prefix = await source.read(
        0,
        source.length < streamedArchiveViewerSignatureBytes
            ? source.length
            : streamedArchiveViewerSignatureBytes,
      );
      check();
      if (matchesStreamedArchiveViewerSignature(name, prefix)) {
        transferred = true;
        final opened = await openStreamedArchiveSource(
          source,
          name: name,
          password: password,
          isCancelled: isCancelled,
          inspectIsoForRewrite: false,
        );
        return await accept(opened.archive);
      }
    } on ArchiveViewException catch (error) {
      if (!useBoundedArchiveViewerFallback(error)) rethrow;
      // The streamed reader has closed its input. Protected/filtered profiles
      // and mislabeled containers retain the bounded sniffing/password reader.
    } finally {
      if (!transferred) await source.close();
    }
  }
  check();
  final archive = await openViewerArchiveSource(
    await koni.FileByteSource.open(path),
    name: name,
    password: password,
    maxMemberBytes: maxMemberBytes,
  );
  return accept(archive);
}
