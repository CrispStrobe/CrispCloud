import 'dart:math' as math;

import 'binary_structure_service.dart';
import 'file_bytes_loader.dart';

/// Inspect an already-open viewer source without materializing the whole file.
/// The existing native source may cache one 256 KiB window; only the bounded
/// 64 KiB prefix is passed to the parser. Snapshot checks bracket that read.
Future<BinaryStructureAnalysis> inspectBinaryStructureSource(
  ViewBytesSource source,
) async {
  await source.validateUnchanged();
  final size = source.size;
  final length = math.min(size, binaryStructurePrefixBytes);
  final prefix = source.readSync(0, length);
  if (prefix.length != length) {
    throw StateError('The binary header could not be read completely.');
  }
  await source.validateUnchanged();
  return inspectBinaryStructure(prefix, totalBytes: size);
}
