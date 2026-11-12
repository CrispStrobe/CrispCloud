import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_compression_writer.dart';

/// Controlled framing for malformed-input tests. Native liblzma/reference
/// fixtures cover interoperability independently of this app's XZ encoder.
Uint8List pbzxFixture(
  List<List<int>> chunks, {
  int? blockSize,
  Set<int> compressedChunks = const {},
}) {
  final header = ByteData(12)
    ..setUint32(0, 0x70627a78)
    ..setUint64(4, blockSize ?? (chunks.isEmpty ? 1024 : chunks.first.length));
  final output = BytesBuilder()..add(header.buffer.asUint8List());
  for (var i = 0; i < chunks.length; i++) {
    final raw = Uint8List.fromList(chunks[i]);
    final stored = compressedChunks.contains(i)
        ? encodeArchiveCompression(raw, ArchiveCompressionKind.xz)
        : raw;
    if (compressedChunks.contains(i) && stored.length >= raw.length) {
      throw ArgumentError(
        'Use compressible data for a compressed PBZX fixture.',
      );
    }
    final record = ByteData(16)
      ..setUint64(0, raw.length)
      ..setUint64(8, stored.length);
    output.add(record.buffer.asUint8List());
    output.add(stored);
  }
  return output.takeBytes();
}
