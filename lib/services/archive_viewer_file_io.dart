import 'package:koni_archive/io.dart' as koni;

import 'archive_viewer_service.dart';
import 'archive_streamed_reader.dart';

Future<ViewerArchive> openViewerArchiveFile(
  String path, {
  required String name,
  String? password,
  int maxMemberBytes = kArchiveReadLimit,
  bool streaming = false,
}) async {
  final lower = name.toLowerCase();
  if (streaming &&
      const [
        '.zip',
        '.cbz',
        '.7z',
        '.cb7',
        '.tar',
        '.cbt',
        '.tgz',
        '.tar.gz',
      ].any(lower.endsWith)) {
    try {
      final opened = await openStreamedArchiveSource(
        await koni.FileByteSource.open(path),
        name: name,
        password: password,
      );
      return opened.archive;
    } on ArchiveStreamingUnsupported {
      // The streamed reader has closed its input. Protected/filtered profiles
      // retain the existing bounded reader and its password retry behavior.
    }
  }
  return openViewerArchiveSource(
    await koni.FileByteSource.open(path),
    name: name,
    password: password,
    maxMemberBytes: maxMemberBytes,
  );
}
