// Portable runtime verification: compile with `dart compile js` and run the
// result in Node (or run this file directly in Dart). No dart:io/Flutter imports.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_lz4_codec.dart';

void main() {
  final allBytes = Uint8List.fromList(List.generate(256, (i) => i));
  if (archiveLz4Xxh32(allBytes, seed: 0xffffffff) != 0x3ee648a9) {
    throw StateError('XXH32 does not match the independent libxxhash vector.');
  }
  // Original fixture produced by liblz4 1.10.0; payload includes high bytes.
  final native = base64Decode(
    'BCJNGHxA2FkAAAAAAACKfAAAAP8IUG9ydGFibGUgTFo0IGNvbnRlbnQA/woXAP'
    '////////////////////////////////////////////////////////////////'
    '///////////////////////////////////////////////////////wNQbnQA/wrf'
    'xAOQAAAAALAoyq4=',
  );
  final phrase = [...ascii.encode('Portable LZ4 content'), 0, 255, 10];
  final expected = Uint8List.fromList([
    for (var i = 0; i < 1000; i++) ...phrase,
  ]);
  void compare(Uint8List actual, Uint8List wanted) {
    if (actual.length != wanted.length) throw StateError('Wrong output size.');
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != wanted[i]) throw StateError('Wrong output byte $i.');
    }
  }

  compare(decodeArchiveLz4(native).bytes, expected);
  final multipleBlocks = Uint8List.fromList([
    for (var i = 0; i < 20; i++) ...expected,
  ]);
  compare(
    decodeArchiveLz4(encodeArchiveLz4(multipleBlocks)).bytes,
    multipleBlocks,
  );
  print('Portable LZ4 checksums, native fixture and multiple blocks verified.');
}
