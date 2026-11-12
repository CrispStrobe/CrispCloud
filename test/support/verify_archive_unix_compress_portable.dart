// Compile with `dart compile js` and run with Node. The host supplies base64
// bytes for compress-reference-width-clear.Z and compress-reference-nine-bit.Z
// through dartMainRunner; the existing independent binary fixtures are reused
// without embedding a second large copy here. No dart:io or Flutter imports.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_unix_compress_codec.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw ArgumentError(
      'Supply the growth/reset and nine-bit fixtures as base64.',
    );
  }
  final growth = base64Decode(arguments[0]);
  final nineBit = base64Decode(arguments[1]);
  final expected = BytesBuilder(copy: false);
  final phrase = ascii.encode('CrispCloud compressed dictionary growth.\n');
  for (var index = 0; index < 6000; index++) {
    expected.add(phrase);
  }
  final random = Uint8List(180000);
  var state = 0x12345678;
  for (var index = 0; index < random.length; index++) {
    state = (1664525 * state + 1013904223) & 0xffffffff;
    random[index] = state >> 24;
  }
  expected.add(random);
  _compare(
    decodeArchiveUnixCompress(growth),
    expected.takeBytes(),
    'growth/reset',
  );
  _compare(
    decodeArchiveUnixCompress(nineBit),
    Uint8List.fromList(List.generate(1280, (index) => index & 255)),
    'nine-bit saturation',
  );
  _mustRefuse(
    () => decodeArchiveUnixCompress(growth, maxOutputBytes: 426000 - 1),
  );
  _mustRefuse(() => decodeArchiveUnixCompress(nineBit, maxOutputBytes: 1279));
  _mustRefuse(
    () => decodeArchiveUnixCompress(Uint8List.fromList([0x1f, 0x9d, 0xb0])),
  );
  // A first code of 257 is an impossible forward dictionary reference.
  _mustRefuse(
    () =>
        decodeArchiveUnixCompress(Uint8List.fromList([0x1f, 0x9d, 0x90, 1, 1])),
  );
  _mustRefuse(
    () =>
        decodeArchiveUnixCompress(Uint8List.fromList([0x1f, 0x9d, 0x90, 0x41])),
  );
  _compare(
    decodeArchiveUnixCompress(Uint8List.fromList([0x1f, 0x9d, 0x90])),
    Uint8List(0),
    'empty stream',
  );
  print(
    'Portable UNIX compress 16-bit growth, reset, nine-bit reference and bounds verified.',
  );
}

void _compare(Uint8List actual, Uint8List expected, String name) {
  if (actual.length != expected.length) {
    throw StateError('$name output length differs.');
  }
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) {
      throw StateError('$name output byte $index differs.');
    }
  }
}

void _mustRefuse(void Function() operation) {
  var refused = false;
  try {
    operation();
  } on ArchiveViewException {
    refused = true;
  }
  if (!refused) {
    throw StateError(
      'Malformed or oversized UNIX compress input was accepted.',
    );
  }
}
