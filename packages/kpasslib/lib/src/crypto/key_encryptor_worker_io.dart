import 'dart:isolate';
import 'dart:typed_data';

import 'aes.dart';

Future<Uint8List> runAesBlock(Aes256 aes, Uint8List block, int rounds) =>
    Isolate.run(() {
      aes.transformBlock(data: block, rounds: rounds);
      return block;
    });
