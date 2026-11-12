import 'dart:typed_data';

import '../models/archive_endpoint.dart';
import 'archive_streaming_writer_stub.dart'
    if (dart.library.io) 'archive_streaming_writer_io.dart'
    as platform;
import 'archive_write_model.dart';

/// Whether a bounded-memory native writer is available for this profile.
/// Encryption continues to use the separately bounded, portable writer.
bool supportsStreamingArchiveWriting(
  ArchiveEndpointFormat format, {
  String? password,
  bool encryptNames = false,
}) => platform.supportsStreamingArchiveWriting(
  format,
  password: password,
  encryptNames: encryptNames,
);

/// Writes to an unpublished sink with backpressure. Payload size does not
/// determine memory use: ZIP and gzip stream directly; 7z spools its packed
/// payload privately because its leading header requires the final offsets.
/// A failure may leave partial output; publication and rollback are the
/// caller's responsibility. No caller-owned input is changed or deleted.
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
}) => platform.writeStreamingArchiveEntries(
  format,
  entries,
  sink: sink,
  maxOutputBytes: maxOutputBytes,
  source: source,
  gzipHeader: gzipHeader,
  level: level,
  password: password,
  encryptNames: encryptNames,
  isCancelled: isCancelled,
);
