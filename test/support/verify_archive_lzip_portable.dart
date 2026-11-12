// Compile with dart2js and run in Node to verify Lzip's checksums and bounded
// 64-bit trailer parsing on the JavaScript backend, without dart:io.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_lzip_codec.dart';
import 'package:crisp_cloud/services/archive_types.dart';

void main() {
  // One-byte original libarchive/liblzma fixture.
  final reference = base64Decode(
    'TFpJUAEXADxB+////+AAAACDFtyMAQAAAAAAAAAlAAAAAAAAAA==',
  );
  final collection = Uint8List.fromList([...reference, ...reference]);
  if (utf8.decode(decodeArchiveLzip(collection)) != 'xx') {
    throw StateError('Lzip reference collection did not decode correctly.');
  }
  final excessive = Uint8List.fromList(reference)..[reference.length - 12] = 1;
  var refused = false;
  try {
    decodeArchiveLzip(excessive);
  } on ArchiveViewException {
    refused = true;
  }
  if (!refused) {
    throw StateError('A large 64-bit Lzip decoded size was accepted.');
  }
  print(
    'Portable Lzip CRC, member collection and uint64 size bounds verified.',
  );
}
