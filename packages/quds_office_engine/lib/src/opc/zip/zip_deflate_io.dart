import 'dart:io';
import 'dart:typed_data';

import 'zip_deflate.dart' as portable;

Uint8List deflateZipEntry(Uint8List bytes, int level) {
  // Preserve the portable writer's stored blocks and extended levels.
  if (level <= 0 || level > 9) return portable.deflateZipEntry(bytes, level);
  final compressed = ZLibEncoder(raw: true, level: level).convert(bytes);
  return compressed is Uint8List ? compressed : Uint8List.fromList(compressed);
}
