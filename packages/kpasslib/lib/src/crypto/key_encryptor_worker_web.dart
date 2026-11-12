import 'dart:math';
import 'dart:typed_data';

import 'aes.dart';

Future<Uint8List> runAesBlock(Aes256 aes, Uint8List block, int rounds) async {
  // Browser Dart has no isolates. Yield between bounded work chunks so a
  // permitted AES KDF does not monopolize the browser event loop.
  for (var done = 0; done < rounds; done += 4096) {
    aes.transformBlock(data: block, rounds: min(4096, rounds - done));
    await Future<void>.delayed(Duration.zero);
  }
  return block;
}
