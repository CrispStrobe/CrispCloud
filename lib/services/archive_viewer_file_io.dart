import 'package:koni_archive/io.dart' as koni;

import 'archive_viewer_service.dart';
import 'archive_streamed_reader.dart';
import 'archive_viewer_streaming.dart';

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
  if (streaming && isStreamedArchiveViewerName(name)) {
    final source = await koni.FileByteSource.open(path);
    var transferred = false;
    try {
      final prefix = await source.read(
        0,
        source.length < 8 ? source.length : 8,
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
