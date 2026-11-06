import 'archive_viewer_service.dart';

Future<ViewerArchive> openViewerArchiveFile(
  String path, {
  required String name,
  String? password,
  int maxMemberBytes = kArchiveReadLimit,
}) async => throw UnsupportedError('Disk archive browsing is unavailable.');
