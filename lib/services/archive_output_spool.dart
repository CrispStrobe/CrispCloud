import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_types.dart';

import 'archive_output_spool_memory.dart'
    if (dart.library.io) 'archive_output_spool_io.dart'
    as platform;

/// Bounded private output for creating and verifying an archive before upload.
/// Await each write; finish seals the output before readers can open it.
/// Native platforms use a private temporary file. Web/fallback storage is
/// capped at 256 MiB and keeps chunks without flattening the image in memory.
/// Positional reads permit up to 256 MiB for existing buffered compression
/// codecs; disk readers and [openRead] continue to request bounded chunks.
abstract class ArchiveOutputSpool {
  static Future<ArchiveOutputSpool> create({required int maxBytes}) =>
      platform.createArchiveOutputSpool(maxBytes: maxBytes);

  int get length;
  int get maxBytes;
  bool get isSealed;
  Future<void> write(List<int> bytes);
  Future<void> finish();
  Stream<List<int>> openRead({int chunkSize = 256 * 1024});
  Future<koni.ByteSource> openByteSource();

  /// Closes all sources opened through this spool and removes its own storage.
  /// No caller-provided path or surrounding directory is deleted.
  Future<void> dispose();
}

void validateArchiveSpoolLimit(int limit) {
  if (limit <= 0 || limit > kArchiveStreamingLimit) {
    throw ArgumentError.value(limit, 'maxBytes');
  }
}

void validateArchiveSpoolChunkSize(int size) {
  if (size <= 0 || size > 16 * 1024 * 1024) {
    throw ArgumentError.value(size, 'chunkSize');
  }
}
