import 'package:koni_archive/io.dart' as koni;

import 'archive_viewer_service.dart';

Future<ViewerArchive> openViewerArchiveFile(
  String path, {
  required String name,
  String? password,
  int maxMemberBytes = kArchiveReadLimit,
}) async => openViewerArchiveSource(
  await koni.FileByteSource.open(path),
  name: name,
  password: password,
  maxMemberBytes: maxMemberBytes,
);
