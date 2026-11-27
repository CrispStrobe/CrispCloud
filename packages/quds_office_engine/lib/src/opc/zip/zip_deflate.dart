import 'dart:typed_data';

import 'deflate_codec.dart';

/// Portable ZIP entry compression for runtimes without dart:io.
Uint8List deflateZipEntry(Uint8List bytes, int level) =>
    RawDeflate.deflate(bytes, level: level);
