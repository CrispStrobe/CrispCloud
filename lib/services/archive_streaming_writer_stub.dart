import 'dart:typed_data';

import '../models/archive_endpoint.dart';
import 'archive_types.dart';
import 'archive_write_model.dart';

bool supportsStreamingArchiveWriting(
  ArchiveEndpointFormat format, {
  String? password,
  bool encryptNames = false,
}) => false;

Future<void> writeStreamingArchiveEntries(
  ArchiveEndpointFormat format,
  List<ArchiveWriteEntry> entries, {
  required Future<void> Function(List<int>) sink,
  required int maxOutputBytes,
  ArchiveRewriteInspection? source,
  Uint8List? gzipHeader,
  int level = 6,
  String? password,
  bool encryptNames = false,
  bool Function()? isCancelled,
}) async {
  throw const ArchiveViewException(
    'Large archive writing requires a native platform with private disk storage.',
  );
}
