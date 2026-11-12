import 'dart:typed_data';

import 'package:pointycastle/key_derivators/api.dart' as pc;
import 'package:pointycastle/key_derivators/argon2.dart' as pc;

import '../argon2.dart';

/// Pure Dart Argon2 backed by the existing BSD-licensed PointyCastle library.
/// Its conditional implementation uses exact 64-bit registers in JavaScript
/// and native integers on the VM. Keep the upstream KPassLib factory contract.
class Argon2Dart extends Argon2 {
  Argon2Dart({
    this.type = Argon2Type.argon2id,
    this.version = Argon2Version.v13,
    required this.parallelism,
    required this.memorySizeKB,
    required this.iterations,
    required List<int> salt,
  }) : salt = Uint8List.fromList(salt);

  final Argon2Type type;
  final Argon2Version version;
  final int parallelism;
  final int memorySizeKB;
  final int iterations;
  final Uint8List salt;

  @override
  Uint8List convert(List<int> password) {
    final generator = pc.Argon2BytesGenerator()
      ..init(pc.Argon2Parameters(
        type.value,
        salt,
        desiredKeyLength: 32,
        version: version.value,
        lanes: parallelism,
        memory: memorySizeKB,
        iterations: iterations,
      ));
    return generator.process(Uint8List.fromList(password));
  }
}
